import json
from typing import Optional
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func

from app.database import get_db
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.utils.auth import bearer_scheme, decode_token

router = APIRouter(prefix="/api/search", tags=["search"])


def _sanitize_ts_query(q: str) -> str:
    """Fazla boşlukları temizler. websearch_to_tsquery AND/OR/NOT semantiğini kendisi yönetir."""
    return " ".join(q.split())


async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("/users")
async def search_users(
    q: str = "",
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    if not q.strip():
        return []
    term = f"%{q.strip()}%"

    query = (
        select(User)
        .where(
            User.is_active == True,  # noqa: E712
            or_(
                User.username.ilike(term),
                User.full_name.ilike(term),
            ),
        )
        .limit(20)
    )

    if current_user_id:
        query = _block_filters(query, User.id, current_user_id)

    result = await db.execute(query)
    users = result.scalars().all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "profile_image_url": u.profile_image_url,
        }
        for u in users
    ]


def _listing_dict(l: Listing, u: User) -> dict:
    return {
        "id": l.id,
        "title": l.title,
        "price": l.price,
        "category": l.category,
        "location": l.location,
        "image_url": l.image_url,
        "image_urls": json.loads(l.image_urls) if l.image_urls else [],
        "created_at": l.created_at.isoformat() if l.created_at else None,
        "user": {"id": u.id, "username": u.username, "full_name": u.full_name},
    }


def _stream_dict(s: LiveStream) -> dict:
    return {
        "id": s.id,
        "room_name": s.room_name,
        "title": s.title,
        "category": s.category,
        "thumbnail_url": s.thumbnail_url,
        "started_at": s.started_at.isoformat() if s.started_at else None,
        "host": {
            "id": s.host.id,
            "username": s.host.username,
            "full_name": s.host.full_name,
        },
    }


def _block_filters(query, model_id_col, current_user_id: int):
    """Engelleme filtrelerini verilen query'ye uygular."""
    blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    blocking_me = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    return query.where(
        model_id_col.not_in(blocked_by_me),
        model_id_col.not_in(blocking_me),
    )


@router.get("/explore")
async def explore(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Varsayılan keşfet sayfası: son ilanlar (12) + aktif yayınlar (4)."""
    # İlanlar
    listing_q = (
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
        .order_by(Listing.created_at.desc())
        .limit(12)
    )
    listings_result = await db.execute(listing_q)
    listings = [_listing_dict(l, u) for l, u in listings_result.all()]

    # Aktif yayınlar
    stream_q = (
        select(LiveStream)
        .where(LiveStream.is_live == True)  # noqa: E712
        .order_by(LiveStream.started_at.desc())
        .limit(4)
    )
    if current_user_id:
        stream_q = _block_filters(stream_q, LiveStream.host_id, current_user_id)
    streams_result = await db.execute(stream_q)
    streams = [_stream_dict(s) for s in streams_result.scalars().all()]

    return {"listings": listings, "streams": streams}


@router.get("/all")
async def search_all(
    q: str = "",
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Birleşik arama: kullanıcılar + ilanlar + yayınlar."""
    if not q.strip():
        return {"users": [], "listings": [], "streams": []}

    term = f"%{q.strip()}%"

    # Kullanıcılar
    user_q = (
        select(User)
        .where(
            User.is_active == True,  # noqa: E712
            or_(User.username.ilike(term), User.full_name.ilike(term)),
        )
        .limit(10)
    )
    if current_user_id:
        user_q = _block_filters(user_q, User.id, current_user_id)
    users_result = await db.execute(user_q)
    users = [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "profile_image_url": u.profile_image_url,
        }
        for u in users_result.scalars().all()
    ]

    # İlanlar — PostgreSQL Full-Text Search (GIN index üzerinden)
    ts_q = _sanitize_ts_query(q)
    tsquery = func.websearch_to_tsquery('turkish', ts_q)
    rank = func.ts_rank(Listing.search_vector, tsquery)

    listing_q = (
        select(Listing, User, rank.label('rank'))
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.is_active == True,  # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
            Listing.search_vector.op('@@')(tsquery),
        )
        .order_by(rank.desc())
        .limit(12)
    )
    listings_result = await db.execute(listing_q)
    listings = [_listing_dict(l, u) for l, u, _rank in listings_result.all()]

    # Aktif yayınlar
    stream_q = (
        select(LiveStream)
        .where(
            LiveStream.is_live == True,  # noqa: E712
            LiveStream.title.ilike(term),
        )
        .order_by(LiveStream.started_at.desc())
        .limit(6)
    )
    if current_user_id:
        stream_q = _block_filters(stream_q, LiveStream.host_id, current_user_id)
    streams_result = await db.execute(stream_q)
    streams = [_stream_dict(s) for s in streams_result.scalars().all()]

    return {"users": users, "listings": listings, "streams": streams}
