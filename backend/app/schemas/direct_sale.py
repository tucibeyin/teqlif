from datetime import datetime
from typing import Optional
from pydantic import BaseModel, field_validator, model_validator


class DirectSaleStartIn(BaseModel):
    listing_id: Optional[int] = None
    title: Optional[str] = None
    price: float
    stock_quantity: int
    proof_image_url: Optional[str] = None

    @model_validator(mode="after")
    def check_title_source(self):
        if self.listing_id is None and not self.title:
            raise ValueError("Ürün adı girilmeli veya ilan seçilmeli")
        return self

    @field_validator("title")
    @classmethod
    def title_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if len(v) < 2:
                raise ValueError("Ürün adı en az 2 karakter olmalı")
            if len(v) > 100:
                raise ValueError("Ürün adı en fazla 100 karakter olabilir")
        return v

    @field_validator("price")
    @classmethod
    def price_valid(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Fiyat sıfırdan büyük olmalı")
        return v

    @field_validator("stock_quantity")
    @classmethod
    def stock_valid(cls, v: int) -> int:
        if v < 1:
            raise ValueError("Stok en az 1 olmalı")
        return v


class DirectSalePurchaseIn(BaseModel):
    quantity: int

    @field_validator("quantity")
    @classmethod
    def quantity_valid(cls, v: int) -> int:
        if v < 1:
            raise ValueError("Adet en az 1 olmalı")
        if v > 10:
            raise ValueError("Tek seferinde en fazla 10 adet alınabilir")
        return v


class DirectSaleCancelIn(BaseModel):
    orders_voided: bool


class DirectSaleStateOut(BaseModel):
    status: str
    sale_id: int
    title: str
    price: float
    total_stock: int
    remaining_stock: int
    product_image_url: Optional[str] = None
    proof_image_url: Optional[str] = None
    end_reason: Optional[str] = None


class DirectSaleSummaryOut(BaseModel):
    role: str                            # "buyer" | "seller"
    sale_id: int
    item_name: str
    proof_image_url: Optional[str] = None
    image_url: Optional[str] = None
    status: str
    end_reason: Optional[str] = None
    ended_at: Optional[datetime] = None

    # Seller alanları (role == "seller")
    total_revenue: Optional[float] = None
    total_quantity_sold: Optional[int] = None
    order_count: Optional[int] = None
    seller_username: Optional[str] = None

    # Buyer alanları (role == "buyer")
    buyer_quantity: Optional[int] = None
    buyer_unit_price: Optional[float] = None
    buyer_total: Optional[float] = None
    buyer_order_status: Optional[str] = None


class DirectSaleSuggestionsOut(BaseModel):
    suggested_price: Optional[float] = None
    avg_conversion_rate: Optional[float] = None
    avg_demand: Optional[float] = None
    recommended_stock: Optional[int] = None
    sample_count: int = 0
    confidence: str = "low"          # "low" | "medium" | "high"


class DirectSaleOrderOut(BaseModel):
    id: int
    buyer_username: str
    quantity: int
    unit_price: float
    total_price: float
    status: str
    created_at: datetime

    class Config:
        from_attributes = True
