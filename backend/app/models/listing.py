from datetime import datetime
from typing import Any, Optional
from sqlalchemy import String, Float, DateTime, ForeignKey, Boolean, Text, Index, func
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = (
        Index('ix_listings_search_vector', 'search_vector', postgresql_using='gin'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    location: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    image_urls: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # JSON array of URLs
    buy_it_now_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    search_vector: Mapped[Optional[Any]] = mapped_column(TSVECTOR, nullable=True)
