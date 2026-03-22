import json
from typing import Optional
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.schemas.stream import VALID_CATEGORIES
from app.core.exceptions import NotFoundException, BadRequestException

router = APIRouter(prefix="/api/listings", tags=["listings"])


def _row_dict(l: Listing, u: User) -> dict:
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
async def get_listings(user_id: Optional[int] = None, category: Optional[str] = None, location: Optional[str] = None, db: AsyncSession = Depends(get_db)):
    q = (
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
    )
    if user_id:
        q = q.where(Listing.user_id == user_id)
    if category:
        q = q.where(Listing.category == category)
    if location:
        q = q.where(Listing.location == location)
    q = q.order_by(Listing.created_at.desc())
    result = await db.execute(q)
    return [_row_dict(l, u) for l, u in result.all()]


@router.get("/my")
async def get_my_listings(active: Optional[bool] = None, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    q = (
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.user_id == current_user.id, Listing.is_deleted == False)  # noqa: E712
    )
    if active is not None:
        q = q.where(Listing.is_active == active)  # noqa: E712
    q = q.order_by(Listing.created_at.desc())
    result = await db.execute(q)
    return [_row_dict(l, u) for l, u in result.all()]


@router.get("/{listing_id}")
async def get_listing(listing_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.id == listing_id, Listing.is_deleted == False)  # noqa: E712
    )
    row = result.first()
    if not row:
        raise NotFoundException("İlan bulunamadı")
    l, u = row
    return _row_dict(l, u)


@router.post("")
async def create_listing(payload: dict, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    category = (payload.get("category") or "diger").strip().lower()
    if category not in VALID_CATEGORIES:
        raise BadRequestException(f"Geçersiz kategori: {category}")
    listing = Listing(
        user_id=current_user.id,
        title=payload.get("title", ""),
        description=payload.get("description"),
        price=payload.get("price"),
        category=category,
        location=payload.get("location"),
        image_url=payload.get("image_url"),
        image_urls=json.dumps(payload.get("image_urls") or []),
    )
    db.add(listing)
    await db.commit()
    await db.refresh(listing)

    # Takipçilere new_listing bildirimi gönder (non-blocking)
    import asyncio as _asyncio
    from app.models.follow import Follow
    from app.routers.notifications import push_notification

    async def _notify_followers():
        followers = await db.scalars(
            select(Follow.follower_id).where(Follow.followed_id == current_user.id)
        )
        for follower_id in followers:
            _asyncio.create_task(push_notification(
                user_id=follower_id,
                notif={
                    "type": "new_listing",
                    "title": f"@{current_user.username} yeni ilan ekledi",
                    "body": listing.title or None,
                    "related_id": listing.id,
                },
                pref_key="new_listing",
            ))

    _asyncio.create_task(_notify_followers())

    return {"id": listing.id}


@router.patch("/{listing_id}/toggle")
async def toggle_listing(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id, Listing.is_deleted == False)  # noqa: E712
    )
    listing = result.scalar_one_or_none()
    if not listing:
        raise NotFoundException("İlan bulunamadı")
    listing.is_active = not listing.is_active
    await db.commit()
    return {"is_active": listing.is_active}


@router.delete("/{listing_id}")
async def delete_listing(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id))
    listing = result.scalar_one_or_none()
    if not listing:
        raise NotFoundException("İlan bulunamadı")
    listing.is_deleted = True
    listing.is_active = False
    await db.commit()
    return {"ok": True}
