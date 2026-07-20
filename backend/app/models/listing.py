from datetime import datetime
from typing import Any, Optional
from sqlalchemy import String, Float, DateTime, ForeignKey, Boolean, Text, Index, func, text
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column, relationship
from pgvector.sqlalchemy import Vector
from sqlalchemy import Enum as SQLEnum
from app.models.enums import ListingStatus
from app.database import Base


class Listing(Base):
    __tablename__ = "listings"
    __table_args__ = (
        Index('ix_listings_search_vector', 'search_vector', postgresql_using='gin'),
        Index('ix_listings_embedding_hnsw', 'embedding', postgresql_using='hnsw', postgresql_with={'m': 16, 'ef_construction': 64}, postgresql_ops={'embedding': 'vector_cosine_ops'}),
        Index('ix_listings_feed_organic', 'category', 'status', text('created_at DESC')),
        Index('ix_listings_feed_recent', 'status', text('created_at DESC')),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    brand: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
    model_name: Mapped[Optional[str]] = mapped_column(String(150), nullable=True, index=True)
    condition: Mapped[Optional[str]] = mapped_column(String(50), nullable=True, index=True)
    location: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    image_urls: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # JSON array of URLs
    thumbnail_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    video_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    buy_it_now_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    last_sold_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True, index=True)
    last_start_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    status: Mapped[ListingStatus] = mapped_column(SQLEnum(ListingStatus, values_callable=lambda obj: [e.value for e in obj]), default=ListingStatus.ACTIVE, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    search_vector: Mapped[Optional[Any]] = mapped_column(TSVECTOR, nullable=True)
    embedding: Mapped[Optional[Any]] = mapped_column(Vector(384), nullable=True)
    visual_embedding: Mapped[Optional[Any]] = mapped_column(Vector(512), nullable=True)

    image_phash: Mapped[Optional[str]] = mapped_column(String(16), nullable=True, index=True)
    nsfw_score: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    nsfw_checked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    is_highlight: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    active_room_id: Mapped[Optional[int]] = mapped_column(nullable=True, index=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    # Otomatik pasife alındığında set edilir; 60 gün sonra ilan silinir.
    deactivated_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    likes: Mapped[list["ListingLike"]] = relationship(  # type: ignore[name-defined]
        "ListingLike", cascade="all, delete-orphan", passive_deletes=True, lazy="selectin"
    )
