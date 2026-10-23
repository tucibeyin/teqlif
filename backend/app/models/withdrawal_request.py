from datetime import datetime
from decimal import Decimal
from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WithdrawalRequest(Base):
    __tablename__ = "withdrawal_requests"
    __table_args__ = (
        Index("ix_withdrawal_requests_user", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    amount_tl: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    iban: Mapped[str] = mapped_column(String(34), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
