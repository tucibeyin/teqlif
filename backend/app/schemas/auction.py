from decimal import Decimal
from typing import Optional
from datetime import datetime
from pydantic import BaseModel, field_validator, model_validator

from app.schemas.base import BaseSchema


class AuctionStart(BaseModel):
    item_name: Optional[str] = None
    start_price: float  # kullanıcı girişi — float kabul edilir
    buy_it_now_price: Optional[float] = None
    listing_id: Optional[int] = None

    @model_validator(mode="after")
    def check_source(self):
        if self.listing_id is None and not self.item_name:
            raise ValueError("Ürün adı girilmeli veya ilan seçilmeli")
        return self

    @field_validator("item_name")
    @classmethod
    def item_name_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if len(v) < 2:
                raise ValueError("Ürün adı en az 2 karakter olmalı")
        return v

    @field_validator("start_price")
    @classmethod
    def price_valid(cls, v: float) -> float:
        if v < 0:
            raise ValueError("Başlangıç fiyatı negatif olamaz")
        return v

    @field_validator("buy_it_now_price")
    @classmethod
    def bin_price_valid(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v <= 0:
            raise ValueError("Hemen al fiyatı sıfırdan büyük olmalı")
        return v


class BidIn(BaseModel):
    amount: float

    @field_validator("amount")
    @classmethod
    def amount_valid(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Teklif sıfırdan büyük olmalı")
        return v


class BidOut(BaseSchema):
    bidder_username: str
    amount: Decimal
    created_at: datetime


class AuctionStateOut(BaseSchema):
    status: str
    winner_accepted: bool = False
    item_name: Optional[str] = None
    start_price: Optional[Decimal] = None
    buy_it_now_price: Optional[Decimal] = None
    current_bid: Optional[Decimal] = None
    current_bidder: Optional[str] = None
    bid_count: int = 0
    listing_id: Optional[int] = None
    bin_buyer_username: Optional[str] = None


class EndAuctionIn(BaseModel):
    proof_image_url: Optional[str] = None


class AcceptBidIn(BaseModel):
    proof_image_url: Optional[str] = None
