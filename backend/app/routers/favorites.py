import json
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.models.enums import ListingStatus
from app.database import get_db
from app.models.favorite import Favorite
from app.models.like import ListingLike
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import NotFoundException, BadRequestException

router = APIRouter(prefix="/api/favorites", tags=["favorites"])


def _listing_dict(l: Listing, u: User, likes_count: int = 0, is_liked: bool = False) -> dict:
    return {
        "id": l.id,
        "title": l.title,
        "description": l.description,
        "price": l.price,
        "category": l.category,
        "location": l.location,
        "image_url": l.image_url,
        "image_urls": json.loads(l.image_urls) if l.image_urls else [],
        "created_at": l.created_at.isoformat() if l.created_at else None,
        "status": l.status.value,
        "user": {"id": u.id, "username": u.username, "full_name": u.full_name},
        "likes_count": likes_count,
        "is_liked": is_liked,
    }


@router.get("")
async def get_favorites(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Listing, User, Favorite)
        .join(Favorite, Favorite.listing_id == Listing.id)
        .join(User, User.id == Listing.user_id)
        .where(Favorite.user_id == current_user.id, Listing.status != ListingStatus.DELETED)  # noqa: E712
        .order_by(Favorite.created_at.desc())
    )).all()

    if not rows:
        return []

    listing_ids = [l.id for l, _, _ in rows]

    # Toplam beğeni sayıları
    like_counts_rows = (await db.execute(
        select(ListingLike.listing_id, func.count().label("cnt"))
        .where(ListingLike.listing_id.in_(listing_ids))
        .group_by(ListingLike.listing_id)
    )).all()
    like_counts = {r.listing_id: r.cnt for r in like_counts_rows}

    # Kullanıcının beğendikleri
    liked_rows = (await db.execute(
        select(ListingLike.listing_id)
        .where(ListingLike.user_id == current_user.id, ListingLike.listing_id.in_(listing_ids))
    )).scalars().all()
    liked_set = set(liked_rows)

    return [
        _listing_dict(l, u, likes_count=like_counts.get(l.id, 0), is_liked=l.id in liked_set)
        for l, u, _ in rows
    ]


@router.get("/{listing_id}")
async def check_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    fav = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    return {"is_favorited": fav is not None}


@router.post("/{listing_id}")
async def add_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    listing = await db.scalar(select(Listing).where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED))  # noqa: E712
    if not listing:
        raise NotFoundException("İlan bulunamadı")
    if listing.user_id == current_user.id:
        raise BadRequestException("Kendi ilanınızı favorileyemezsiniz")
    existing = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    if existing:
        return {"ok": True}
    db.add(Favorite(user_id=current_user.id, listing_id=listing_id))
    await db.commit()
    return {"ok": True}


@router.delete("/{listing_id}")
async def remove_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    fav = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    if fav:
        await db.delete(fav)
        await db.commit()
    return {"ok": True}
