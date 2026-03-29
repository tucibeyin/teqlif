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
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.security.captcha import verify_captcha_token
from app.services.listing_service import ListingService
from app.services.like_service import LikeService
from app.schemas.listing import ListingOfferCreate

router = APIRouter(prefix="/api/listings", tags=["listings"])


# ── Opsiyonel token çözümleyici ─────────────────────────────────────────────
async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("")
async def get_listings(
    request: Request,
    user_id: Optional[int] = None,
    category: Optional[str] = None,
    location: Optional[str] = None,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listings(user_id, category, location, current_user_id)


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
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing(listing_id, current_user_id)


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


@router.post("/{listing_id}/offers")
async def create_offer(
    listing_id: int,
    payload: ListingOfferCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).create_offer(listing_id, current_user, payload.amount)


@router.post("/{listing_id}/like")
async def toggle_listing_like(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """İlanı beğen / beğeniyi kaldır (toggle). Güncel `likes_count` ve `is_liked` döner."""
    return await LikeService(db).toggle_listing_like(listing_id, current_user.id)


@router.get("/{listing_id}/offers")
async def get_listing_offers(
    listing_id: int,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing_offers(listing_id)
