from datetime import datetime
from typing import Optional
from sqlalchemy import Index, Integer, String, DateTime, ForeignKey, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class TeqlikTransaction(Base):
    __tablename__ = "teqlik_transactions"
    __table_args__ = (
        Index("ix_teqlik_transactions_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    transaction_type: Mapped[str] = mapped_column(String(50), nullable=False)
    reference_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    reference_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    store_transaction_id: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    store_platform: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    raw_payload: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    product_type: Mapped[str] = mapped_column(String(20), nullable=False, server_default='consumable')


