from datetime import datetime

from sqlalchemy import Float, DateTime, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ListingOffer(Base):
    __tablename__ = "listing_offers"
    __table_args__ = (
        Index("ix_listing_offers_listing_id", "listing_id"),
        Index("ix_listing_offers_user_id", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    listing_id: Mapped[int] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
