from decimal import Decimal
from datetime import datetime
from typing import Annotated, Literal, Optional, Union
from pydantic import BaseModel, Field, field_validator, model_validator

from app.schemas.base import BaseSchema


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


class DirectSaleStateOut(BaseSchema):
    status: str
    sale_id: int
    title: str
    price: Decimal
    total_stock: int
    remaining_stock: int
    product_image_url: Optional[str] = None
    proof_image_url: Optional[str] = None
    end_reason: Optional[str] = None
    listing_id: Optional[int] = None


class _DirectSaleSummaryBase(BaseSchema):
    sale_id: int
    item_name: str
    proof_image_url: Optional[str] = None
    image_url: Optional[str] = None
    status: str
    end_reason: Optional[str] = None
    ended_at: Optional[datetime] = None


class SellerSummaryOut(_DirectSaleSummaryBase):
    role: Literal["seller"] = "seller"
    total_revenue: Optional[Decimal] = None
    total_quantity_sold: Optional[int] = None
    order_count: Optional[int] = None
    seller_username: Optional[str] = None


class BuyerSummaryOut(_DirectSaleSummaryBase):
    role: Literal["buyer"] = "buyer"
    buyer_quantity: Optional[int] = None
    buyer_unit_price: Optional[Decimal] = None
    buyer_total: Optional[Decimal] = None
    buyer_order_status: Optional[str] = None


DirectSaleSummaryOut = Annotated[
    Union[SellerSummaryOut, BuyerSummaryOut],
    Field(discriminator="role"),
]


class DirectSaleSuggestionsOut(BaseSchema):
    suggested_price: Optional[float] = None
    avg_conversion_rate: Optional[float] = None
    avg_demand: Optional[float] = None
    recommended_stock: Optional[int] = None
    sample_count: int = 0
    confidence: str = "low"


class DirectSaleOrderOut(BaseSchema):
    id: int
    buyer_username: str
    quantity: int
    unit_price: Decimal
    total_price: Decimal
    status: str
    created_at: datetime
