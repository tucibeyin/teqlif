from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, Integer, String, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class GiftEvent(Base):
    """
    Canlı yayında gönderilen her hediyenin tam kaydı.

    TuciTransaction.reference_id → GiftEvent.id (reference_type="gift_event")
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
    stream_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("live_streams.id", ondelete="CASCADE"), nullable=False
    )
    sender_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    receiver_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    gift_name: Mapped[str] = mapped_column(String(50), nullable=False)
    cost_tuci: Mapped[int] = mapped_column(Integer, nullable=False)
    host_share: Mapped[int] = mapped_column(Integer, nullable=False)
    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
