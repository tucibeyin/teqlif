from decimal import Decimal
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from app.schemas.base import BaseSchema


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
