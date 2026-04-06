from datetime import datetime
from sqlalchemy import Boolean, DateTime, Text, Integer, String, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DirectMessage(Base):
    __tablename__ = "direct_messages"
    __table_args__ = (
        # Konuşma sorgularında ve cleanup cron'unda kullanılır
        Index("ix_direct_messages_conv_created", "sender_id", "receiver_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    sender_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    receiver_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    flag_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
