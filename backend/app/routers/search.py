import asyncio
import json
import re
from typing import Optional
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_, func, text as sa_text

from app.database import get_db
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.models.user_interest import UserInterest
from app.utils.auth import bearer_scheme, decode_token
from app.services.ml_service import generate_embedding

router = APIRouter(prefix="/api/search", tags=["search"])


def _sanitize_ts_query(q: str) -> str:
    return " ".join(q.split())


def _build_prefix_tsquery(q: str) -> str:
    """Her kelimeye :* ekler — to_tsquery ile prefix (as-you-type) arama sağlar."""
    # to_tsquery için özel karakterleri temizle
    safe = re.sub(r"[&|!():<>@*\\]", " ", q)
    words = [w for w in safe.split() if w]
    if not words:
        return ""
    return " & ".join(f"{w}:*" for w in words)


async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("/users")
async def search_users(
    q: str = "",
    offset: int = 0,
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
        .offset(offset)
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
    """
    Keşfet sayfası verisi.

    Misafir: son ilanlar (20) + tüm aktif yayınlar (görüntüleyici sayısına göre)
    Giriş yapmış: ilanlar yok (frontend /api/feed kullanır) +
                  aktif yayınlar (kullanıcının kategori ilgisine göre sıralı)
    """
    # ── Canlı Yayınlar ───────────────────────────────────────────────────────
    if current_user_id:
        # Kişiselleştirilmiş: kullanıcının ilgi kategorisine uyan yayınlar önce
        stream_q = (
            select(LiveStream, func.coalesce(UserInterest.score, 0.0).label("cat_score"))
            .outerjoin(
                UserInterest,
                (UserInterest.user_id == current_user_id)
                & (UserInterest.category == LiveStream.category),
            )
            .where(LiveStream.is_live == True)  # noqa: E712
            .order_by(
                func.coalesce(UserInterest.score, 0.0).desc(),
                LiveStream.started_at.desc(),
            )
            .limit(10)
        )
        stream_q = _block_filters(stream_q, LiveStream.host_id, current_user_id)
        streams_result = await db.execute(stream_q)
        streams = [_stream_dict(s) for s, _ in streams_result.all()]
        listings = []  # Giriş yapan için ilanlar /api/feed'den gelir
    else:
        # Misafir: tüm yayınlar, en yeni önce
        stream_q = (
            select(LiveStream)
            .where(LiveStream.is_live == True)  # noqa: E712
            .order_by(LiveStream.started_at.desc())
            .limit(10)
        )
        streams_result = await db.execute(stream_q)
        streams = [_stream_dict(s) for s in streams_result.scalars().all()]

        # Misafir için ilanlar: en yeni 20
        listing_q = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
            .order_by(Listing.created_at.desc())
            .limit(20)
        )
        listings_result = await db.execute(listing_q)
        listings = [_listing_dict(l, u) for l, u in listings_result.all()]

    return {"listings": listings, "streams": streams}


@router.get("/all")
async def search_all(
    q: str = "",
    offset: int = 0,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    """
    Birleşik arama: kullanıcılar + ilanlar + canlı yayınlar.

    İlan arama modu:
      ≤2 karakter  → ILIKE
      ≥3 kelime    → pgvector cosine distance < 0.6 (semantic), search_type='semantic'
      diğer        → PostgreSQL FTS websearch_to_tsquery, search_type='text'
    """
    q = q.strip()
    if not q:
        return {"users": [], "listings": [], "streams": [], "search_type": "text"}

    term = f"%{q}%"
    words = q.split()

    # ── Kullanıcılar (ILIKE — her modda aynı) ─────────────────────────────────
    user_q = (
        select(User)
        .where(
            User.is_active == True,  # noqa: E712
            or_(User.username.ilike(term), User.full_name.ilike(term)),
        )
        .offset(offset)
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

    # ── Canlı yayınlar (ILIKE başlık — semantic gerekmez) ─────────────────────
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

    # ── İlanlar ───────────────────────────────────────────────────────────────
    search_type = "text"

    if len(q) <= 2:
        # Kısa sorgu → ILIKE
        listing_q = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.is_active == True,  # noqa: E712
                Listing.is_deleted == False,  # noqa: E712
                or_(Listing.title.ilike(term), Listing.description.ilike(term)),
            )
            .order_by(Listing.created_at.desc())
            .offset(offset)
            .limit(12)
        )
        if current_user_id:
            listing_q = _block_filters(listing_q, Listing.user_id, current_user_id)
        result = await db.execute(listing_q)
        listings = [_listing_dict(l, u) for l, u in result.all()]

    elif len(words) >= 3:
        # Uzun sorgu → Semantic / pgvector
        search_type = "semantic"
        loop = asyncio.get_running_loop()
        vector: list[float] = await loop.run_in_executor(None, generate_embedding, q)
        vec_str = "[" + ",".join(f"{v:.8f}" for v in vector) + "]"

        block_clause = ""
        params: dict = {"vec": vec_str, "offset": offset, "threshold": 0.6}
        if current_user_id:
            block_clause = """
                AND l.user_id NOT IN (
                    SELECT blocked_id FROM user_blocks WHERE blocker_id = :uid
                )
                AND l.user_id NOT IN (
                    SELECT blocker_id FROM user_blocks WHERE blocked_id = :uid
                )
            """
            params["uid"] = current_user_id

        raw = sa_text(f"""
            SELECT
                l.id, l.title, l.price, l.category, l.location,
                l.image_url, l.image_urls, l.created_at,
                u.id AS uid, u.username, u.full_name
            FROM listings l
            JOIN users u ON u.id = l.user_id
            WHERE l.is_active = TRUE
              AND l.is_deleted = FALSE
              AND l.embedding IS NOT NULL
              AND (l.embedding <=> :vec::vector) < :threshold
              {block_clause}
            ORDER BY (l.embedding <=> :vec::vector)
            LIMIT 12 OFFSET :offset
        """)
        result = await db.execute(raw, params)
        listings = [
            {
                "id": row[0],
                "title": row[1],
                "price": row[2],
                "category": row[3],
                "location": row[4],
                "image_url": row[5],
                "image_urls": json.loads(row[6]) if row[6] else [],
                "created_at": row[7].isoformat() if row[7] else None,
                "user": {"id": row[8], "username": row[9], "full_name": row[10]},
            }
            for row in result.fetchall()
        ]

    else:
        # Orta uzunluk → prefix FTS + NULL-search_vector ILIKE
        ts_q = _sanitize_ts_query(q)
        term = f"%{ts_q}%"
        prefix_q = _build_prefix_tsquery(ts_q)
        tsquery = func.to_tsquery("turkish", prefix_q) if prefix_q else None
        rank = func.ts_rank(Listing.search_vector, tsquery) if tsquery else func.cast(0, func.Float)
        fts_cond = Listing.search_vector.op("@@")(tsquery) if tsquery else False
        listing_q = (
            select(Listing, User, func.coalesce(rank, 0.0).label("rank"))
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.is_active == True,  # noqa: E712
                Listing.is_deleted == False,  # noqa: E712
                or_(
                    fts_cond,
                    and_(
                        Listing.search_vector.is_(None),
                        or_(Listing.title.ilike(term), Listing.description.ilike(term)),
                    ),
                ),
            )
            .order_by(func.coalesce(rank, 0.0).desc())
            .offset(offset)
            .limit(12)
        )
        if current_user_id:
            listing_q = _block_filters(listing_q, Listing.user_id, current_user_id)
        result = await db.execute(listing_q)
        listings = [_listing_dict(l, u) for l, u, _r in result.all()]

    return {
        "users": users,
        "listings": listings,
        "streams": streams,
        "search_type": search_type,
    }


# ── Anlamsal İlan Arama ────────────────────────────────────────────────────────

@router.get("/listings")
async def search_listings(
    q: str = "",
    offset: int = 0,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    """
    İlan arama — üç mod:
      1. Kısa sorgu (≤2 karakter):  ILIKE metin eşleştirme
      2. Uzun sorgu (≥3 kelime):    pgvector cosine distance (semantic)
      3. Orta uzunluk:              PostgreSQL FTS websearch_to_tsquery

    Yanıt: {"listings": [...], "search_type": "semantic" | "text"}
    """
    q = q.strip()
    if not q:
        return {"listings": [], "search_type": "text"}

    words = q.split()

    # ── 1. Çok kısa → ILIKE ────────────────────────────────────────────────────
    if len(q) <= 2:
        term = f"%{q}%"
        stmt = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.is_active == True,  # noqa: E712
                Listing.is_deleted == False,  # noqa: E712
                or_(Listing.title.ilike(term), Listing.description.ilike(term)),
            )
            .order_by(Listing.created_at.desc())
            .offset(offset)
            .limit(12)
        )
        if current_user_id:
            stmt = _block_filters(stmt, Listing.user_id, current_user_id)
        result = await db.execute(stmt)
        listings = [_listing_dict(l, u) for l, u in result.all()]
        return {"listings": listings, "search_type": "text"}

    # ── 2. Uzun sorgu (≥3 kelime) → Semantic / pgvector ───────────────────────
    if len(words) >= 3:
        loop = asyncio.get_running_loop()
        vector: list[float] = await loop.run_in_executor(None, generate_embedding, q)
        vec_str = "[" + ",".join(f"{v:.8f}" for v in vector) + "]"

        block_clause = ""
        params: dict = {"vec": vec_str, "offset": offset, "threshold": 0.6}
        if current_user_id:
            block_clause = """
                AND l.user_id NOT IN (
                    SELECT blocked_id FROM user_blocks WHERE blocker_id = :uid
                )
                AND l.user_id NOT IN (
                    SELECT blocker_id FROM user_blocks WHERE blocked_id = :uid
                )
            """
            params["uid"] = current_user_id

        raw = sa_text(f"""
            SELECT
                l.id, l.title, l.price, l.category, l.location,
                l.image_url, l.image_urls, l.created_at,
                u.id AS uid, u.username, u.full_name
            FROM listings l
            JOIN users u ON u.id = l.user_id
            WHERE l.is_active = TRUE
              AND l.is_deleted = FALSE
              AND l.embedding IS NOT NULL
              AND (l.embedding <=> :vec::vector) < :threshold
              {block_clause}
            ORDER BY (l.embedding <=> :vec::vector)
            LIMIT 12 OFFSET :offset
        """)
        result = await db.execute(raw, params)
        rows = result.fetchall()
        listings = [
            {
                "id": row[0],
                "title": row[1],
                "price": row[2],
                "category": row[3],
                "location": row[4],
                "image_url": row[5],
                "image_urls": json.loads(row[6]) if row[6] else [],
                "created_at": row[7].isoformat() if row[7] else None,
                "user": {"id": row[8], "username": row[9], "full_name": row[10]},
            }
            for row in rows
        ]
        return {"listings": listings, "search_type": "semantic"}

    # ── 3. Orta uzunluk → prefix FTS + NULL-search_vector ILIKE birlikte ────
    ts_q = _sanitize_ts_query(q)
    term = f"%{ts_q}%"
    prefix_q = _build_prefix_tsquery(ts_q)
    if not prefix_q:
        return {"listings": [], "search_type": "text"}
    # to_tsquery + :* → "çam:*" her "çam" ile başlayan lexeme'i bulur
    tsquery = func.to_tsquery("turkish", prefix_q)
    rank = func.ts_rank(Listing.search_vector, tsquery)
    stmt = (
        select(Listing, User, func.coalesce(rank, 0.0).label("rank"))
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.is_active == True,  # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
            or_(
                # search_vector dolu → FTS eşleşmesi
                Listing.search_vector.op("@@")(tsquery),
                # search_vector NULL → başlık/açıklama ILIKE ile kapsama al
                and_(
                    Listing.search_vector.is_(None),
                    or_(
                        Listing.title.ilike(term),
                        Listing.description.ilike(term),
                    ),
                ),
            ),
        )
        .order_by(func.coalesce(rank, 0.0).desc())
        .offset(offset)
        .limit(12)
    )
    if current_user_id:
        stmt = _block_filters(stmt, Listing.user_id, current_user_id)
    result = await db.execute(stmt)
    listings = [_listing_dict(l, u) for l, u, _r in result.all()]
    return {"listings": listings, "search_type": "text"}
