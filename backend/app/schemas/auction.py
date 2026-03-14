from typing import Optional
from pydantic import BaseModel, field_validator


class AuctionStart(BaseModel):
    item_name: str
    start_price: float

    @field_validator("item_name")
    @classmethod
    def item_name_valid(cls, v: str) -> str:
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
