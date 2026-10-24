from __future__ import annotations
from datetime import datetime
from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class RefundLog(Base):
    __tablename__ = "refund_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    store_platform: Mapped[str] = mapped_column(String(20), nullable=False)
    store_transaction_id: Mapped[str] = mapped_column(String(128), nullable=False)
    refunded_teqlik: Mapped[int] = mapped_column(Integer, nullable=False)
    original_teqlik: Mapped[int] = mapped_column(Integer, nullable=False)
    gift_teqlik_cancelled: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    raw_payload: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
