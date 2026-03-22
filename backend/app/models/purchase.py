from datetime import datetime
from typing import Optional
from sqlalchemy import String, Float, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Purchase(Base):
    __tablename__ = "purchases"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    buyer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    listing_id: Mapped[Optional[int]] = mapped_column(ForeignKey("listings.id"), nullable=True, index=True)
    auction_id: Mapped[Optional[int]] = mapped_column(ForeignKey("auctions.id"), nullable=True, index=True)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    # 'AUCTION' | 'BUY_IT_NOW'
    purchase_type: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
