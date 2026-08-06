from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Numeric, DateTime, ForeignKey, Boolean, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DirectSale(Base):
    __tablename__ = "direct_sales"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stream_id: Mapped[int] = mapped_column(ForeignKey("live_streams.id", ondelete="CASCADE"), nullable=False, index=True)
    host_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("listings.id", ondelete="SET NULL"), nullable=True)

    title: Mapped[str] = mapped_column(String(100), nullable=False)
    price: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    product_image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    proof_image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    total_stock: Mapped[int] = mapped_column(Integer, nullable=False)
    remaining_stock: Mapped[int] = mapped_column(Integer, nullable=False)

    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    end_reason: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    orders_voided: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    viewer_count_at_start: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)

    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


class DirectSaleOrder(Base):
    __tablename__ = "direct_sale_orders"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sale_id: Mapped[int] = mapped_column(ForeignKey("direct_sales.id", ondelete="CASCADE"), nullable=False, index=True)
    seller_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    buyer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("listings.id", ondelete="SET NULL"), nullable=True)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="completed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
