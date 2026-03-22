import json
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.favorite import Favorite
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import NotFoundException, BadRequestException

router = APIRouter(prefix="/api/favorites", tags=["favorites"])


def _listing_dict(l: Listing, u: User) -> dict:
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
        "is_active": l.is_active,
        "user": {"id": u.id, "username": u.username, "full_name": u.full_name},
    }


@router.get("")
async def get_favorites(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Listing, User, Favorite)
        .join(Favorite, Favorite.listing_id == Listing.id)
        .join(User, User.id == Listing.user_id)
        .where(Favorite.user_id == current_user.id, Listing.is_deleted == False)  # noqa: E712
        .order_by(Favorite.created_at.desc())
    )
    return [_listing_dict(l, u) for l, u, _ in result.all()]


@router.get("/{listing_id}")
async def check_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    fav = await db.scalar(
        select(Favorite).where(Favorite.user_id == current_user.id, Favorite.listing_id == listing_id)
    )
    return {"is_favorited": fav is not None}


@router.post("/{listing_id}")
async def add_favorite(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    listing = await db.scalar(select(Listing).where(Listing.id == listing_id, Listing.is_deleted == False))  # noqa: E712
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
