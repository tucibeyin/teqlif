from datetime import datetime
from typing import Optional
from decimal import Decimal
from sqlalchemy import String, Numeric, DateTime, ForeignKey, Index, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Purchase(Base):
    __tablename__ = "purchases"
    __table_args__ = (
        Index("ix_purchases_buyer_created", "buyer_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    buyer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("listings.id", ondelete="SET NULL"), nullable=True, index=True)
    auction_id: Mapped[Optional[int]] = mapped_column(ForeignKey("auctions.id"), nullable=True, index=True)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    # 'AUCTION' | 'BUY_IT_NOW'
    purchase_type: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
