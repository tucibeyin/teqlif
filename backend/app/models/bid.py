from datetime import datetime
from sqlalchemy import String, Float, DateTime, ForeignKey, Index, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Bid(Base):
    __tablename__ = "bids"
    __table_args__ = (
        # "stream_id ile sırala, en son teklifi bul" sorguları için composite index
        Index("ix_bids_stream_created", "stream_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stream_id: Mapped[int] = mapped_column(ForeignKey("live_streams.id"), nullable=False, index=True)
    bidder_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    bidder_username: Mapped[str] = mapped_column(String(100), nullable=False)
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
