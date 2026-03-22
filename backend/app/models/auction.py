from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, Float, DateTime, ForeignKey, Boolean, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Auction(Base):
    __tablename__ = "auctions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stream_id: Mapped[int] = mapped_column(ForeignKey("live_streams.id"), nullable=False, index=True)
    listing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("listings.id"), nullable=True)
    item_name: Mapped[str] = mapped_column(String(300), nullable=False)
    start_price: Mapped[float] = mapped_column(Float, nullable=False)
    buy_it_now_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    final_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    is_bought_it_now: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    winner_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), nullable=True)
    winner_username: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    bid_count: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="completed")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
