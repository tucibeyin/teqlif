from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import get_current_user
from app.schemas.stream import VALID_CATEGORIES

router = APIRouter(prefix="/api/listings", tags=["listings"])


@router.get("")
async def get_listings(user_id: Optional[int] = None, category: Optional[str] = None, db: AsyncSession = Depends(get_db)):
    q = select(Listing, User).join(User, User.id == Listing.user_id).where(Listing.is_active == True)  # noqa: E712
    if user_id:
        q = q.where(Listing.user_id == user_id)
    if category:
        q = q.where(Listing.category == category)
    q = q.order_by(Listing.created_at.desc())
    result = await db.execute(q)
    rows = result.all()
    return [
        {
            "id": l.id,
            "title": l.title,
            "description": l.description,
            "price": l.price,
            "category": l.category,
            "location": l.location,
            "image_url": l.image_url,
            "created_at": l.created_at.isoformat() if l.created_at else None,
            "user": {"id": u.id, "username": u.username, "full_name": u.full_name},
        }
        for l, u in rows
    ]


@router.post("")
async def create_listing(payload: dict, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    category = (payload.get("category") or "diger").strip().lower()
    if category not in VALID_CATEGORIES:
        raise HTTPException(status_code=422, detail=f"Geçersiz kategori: {category}")
    listing = Listing(
        user_id=current_user.id,
        title=payload.get("title", ""),
        description=payload.get("description"),
        price=payload.get("price"),
        category=category,
        location=payload.get("location"),
        image_url=payload.get("image_url"),
    )
    db.add(listing)
    await db.commit()
    await db.refresh(listing)
    return {"id": listing.id}


@router.delete("/{listing_id}")
async def delete_listing(listing_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id))
    listing = result.scalar_one_or_none()
    if not listing:
        raise HTTPException(status_code=404, detail="İlan bulunamadı")
    listing.is_active = False
    await db.commit()
    return {"ok": True}
