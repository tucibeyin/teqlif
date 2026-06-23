from datetime import datetime
from sqlalchemy import ForeignKey, DateTime, Index, func
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class ListingImpression(Base):
    __tablename__ = "listing_impressions"
    __table_args__ = (
        Index("ix_listing_impressions_user_seen", "user_id", "seen_at"),
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, nullable=False
    )
    listing_id: Mapped[int] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), primary_key=True, nullable=False
    )
    seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
