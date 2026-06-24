from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class AdCampaign(Base):
    """
    Reklam kampanyası. Bütçe ve tıklama maliyeti TUCi (tam sayı) cinsinden.

    status değerleri:
      active    — yayında, tıklama kabul ediyor
      paused    — satıcı tarafından duraklatıldı
      completed — bütçe tükendi veya bitiş tarihi geçti
    """

    __tablename__ = "ad_campaigns"
    __table_args__ = (
        Index("ix_ad_campaigns_seller_status", "seller_id", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    listing_id: Mapped[int] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    seller_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    total_budget: Mapped[int] = mapped_column(Integer, nullable=False)
    spent_budget: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cpc_bid: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="active", index=True
    )
    start_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
