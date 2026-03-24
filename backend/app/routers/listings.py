"""
İlan router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db, captcha) alır
  2. ListingService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, DB sorguları ve bildirimler tamamen
app.services.listing_service.ListingService'e taşınmıştır.
"""
from typing import Optional

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi_cache.decorator import cache

from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user
from app.security.captcha import verify_captcha_token
from app.services.listing_service import ListingService

router = APIRouter(prefix="/api/listings", tags=["listings"])


@router.get("")
@cache(expire=30)  # 30 sn mikro-cache — spike koruması, query params cache key'e dahil edilir
async def get_listings(
    request: Request,
    user_id: Optional[int] = None,
    category: Optional[str] = None,
    location: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listings(user_id, category, location)


@router.get("/my")
async def get_my_listings(
    active: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_my_listings(current_user, active)


@router.get("/{listing_id}")
async def get_listing(
    listing_id: int,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing(listing_id)


@router.post("")
async def create_listing(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _captcha: None = Depends(verify_captcha_token),
):
    return await ListingService(db).create_listing(payload, current_user)


@router.patch("/{listing_id}/toggle")
async def toggle_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).toggle_listing(listing_id, current_user)


@router.delete("/{listing_id}")
async def delete_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).delete_listing(listing_id, current_user)
