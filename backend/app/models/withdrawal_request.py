from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WithdrawalRequest(Base):
    __tablename__ = "withdrawal_requests"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    amount_tl: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    iban: Mapped[str] = mapped_column(String(34), nullable=False)
    account_holder: Mapped[str] = mapped_column(String(120), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, server_default='pending')
    # pending | approved | completed | rejected | cancelled
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    cancelled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    admin_note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
