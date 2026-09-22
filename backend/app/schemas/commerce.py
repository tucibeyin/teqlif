from decimal import Decimal
from typing import Optional

from app.schemas.base import BaseSchema
from app.schemas.user import UserOut


class InitOut(BaseSchema):
    user: UserOut
    wallet_balance: Optional[Decimal] = None
    notifications_unread: int
    messages_unread: int


class CommerceItemOut(BaseSchema):
    type: str
    id: int
    sale_id: Optional[int] = None
    item_name: Optional[str] = None
    unit_price: Optional[float] = None
    quantity: Optional[int] = None
    final_price: float
    seller_username: Optional[str] = None
    image_url: Optional[str] = None
    proof_image_url: Optional[str] = None
    order_status: str
    is_bought_it_now: Optional[bool] = None
    ended_at: Optional[str] = None


class CommerceSaleOut(BaseSchema):
    type: str
    id: int
    item_name: Optional[str] = None
    total_revenue: float
    total_quantity_sold: Optional[int] = None
    order_count: Optional[int] = None
    buyer_username: Optional[str] = None
    image_url: Optional[str] = None
    ended_at: Optional[str] = None
    end_reason: Optional[str] = None
    orders_voided: Optional[bool] = None
