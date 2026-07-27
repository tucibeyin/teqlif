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
from app.services.like_service import LikeService
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException

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
        "is_liked": True,
        "is_favorited": True,
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

    like_counts, liked_set = await LikeService.batch_listing_likes(db, listing_ids, current_user.id)

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
        raise NotFoundException(code="LISTING_NOT_FOUND")
    if listing.user_id == current_user.id:
        raise ForbiddenException(code="SELF_FAVORITE_FORBIDDEN")
    existing_fav = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    existing_like = await db.scalar(
        select(ListingLike).where(ListingLike.user_id == current_user.id, ListingLike.listing_id == listing_id)
    )
    if not existing_fav:
        db.add(Favorite(user_id=current_user.id, listing_id=listing_id))
    if not existing_like:
        db.add(ListingLike(user_id=current_user.id, listing_id=listing_id))
    await db.commit()
    return {"ok": True, "is_favorited": True, "is_liked": True}


@router.delete("/{listing_id}")
async def remove_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    fav = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    like_obj = await db.scalar(
        select(ListingLike).where(ListingLike.user_id == current_user.id, ListingLike.listing_id == listing_id)
    )
    if fav:
        await db.delete(fav)
    if like_obj:
        await db.delete(like_obj)
    await db.commit()
    return {"ok": True, "is_favorited": False, "is_liked": False}
