from decimal import Decimal
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, field_validator

from app.schemas.base import BaseSchema


class SellerMiniOut(BaseSchema):
    id: int
    username: str
    full_name: Optional[str] = None
    avatar_url: Optional[str] = None
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None
    is_premium: bool = False
    is_verified: bool = False
    badge: Optional[str] = None
    trust_score: Optional[float] = None
    influence_rank: Optional[int] = None


class ListingOut(BaseSchema):
    id: int
    title: str
    description: Optional[str] = None
    price: Optional[Decimal] = None
    category: Optional[str] = None
    subcategory: Optional[str] = None
    brand: Optional[str] = None
    condition: Optional[str] = None
    extra_fields: Optional[Any] = None
    image_url: Optional[str] = None
    image_urls: list[str] = []
    thumbnail_url: Optional[str] = None
    video_url: Optional[str] = None
    province: Optional[str] = None
    district: Optional[str] = None
    location: Optional[str] = None
    status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    deactivated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    is_highlight: bool = False
    buy_it_now_price: Optional[Decimal] = None
    likes_count: int = 0
    is_liked: bool = False
    is_favorited: bool = False
    impression_count: int = 0
    is_sponsored: bool = False
    campaign_id: Optional[int] = None
    is_trending: bool = False
    user: SellerMiniOut


ListingDetailOut = ListingOut


class ListingOfferCreate(BaseModel):
    amount: float

    @field_validator("amount")
    @classmethod
    def amount_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Teklif sıfırdan büyük olmalı")
        return v


class ListingOfferResponse(BaseSchema):
    id: int
    listing_id: int
    amount: Decimal
    created_at: datetime
    user_id: int
    username: str
    profile_image_url: Optional[str] = None
