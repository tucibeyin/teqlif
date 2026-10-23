from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class GiftEvent(Base):
    """
    Canlı yayında gönderilen her hediyenin tam kaydı.

    TeqlikTransaction.reference_id → GiftEvent.id (reference_type="gift_event")
    hem sender hem receiver transaction'ı aynı GiftEvent'e işaret eder.
    Redis: gift:log:{stream_id} listesine de LPUSH yapılır (TTL 24h).
    """

    __tablename__ = "gift_events"
    __table_args__ = (
        Index("ix_gift_events_stream", "stream_id", "sent_at"),
        Index("ix_gift_events_sender", "sender_id"),
        Index("ix_gift_events_receiver", "receiver_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    stream_id: Mapped[Optional[int]] = mapped_column(
        Integer, ForeignKey("live_streams.id", ondelete="SET NULL"), nullable=True
    )
    sender_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    receiver_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    gift_name: Mapped[str] = mapped_column(String(50), nullable=False)
    cost_teqlik: Mapped[int] = mapped_column(Integer, nullable=False)
    host_share: Mapped[int] = mapped_column(Integer, nullable=False)
    earnings_tl: Mapped[Decimal] = mapped_column(Numeric(10, 4), nullable=False, server_default='0')
    payout_status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="'pending'")
    released_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
