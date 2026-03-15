from typing import Optional
from pydantic import BaseModel, field_validator, model_validator


class AuctionStart(BaseModel):
    item_name: Optional[str] = None
    start_price: float  # her zaman zorunlu
    listing_id: Optional[int] = None  # seçilince başlık buradan gelir

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


class BidIn(BaseModel):
    amount: float

    @field_validator("amount")
    @classmethod
    def amount_valid(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Teklif sıfırdan büyük olmalı")
        return v


class AuctionStateOut(BaseModel):
    status: str
    item_name: Optional[str] = None
    start_price: Optional[float] = None
    current_bid: Optional[float] = None
    current_bidder: Optional[str] = None
    bid_count: int = 0
    listing_id: Optional[int] = None
