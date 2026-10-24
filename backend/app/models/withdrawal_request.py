from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy import Integer, Numeric, String, Text, ForeignKey, DateTime, Index, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WithdrawalRequest(Base):
    __tablename__ = "withdrawal_requests"
    __table_args__ = (
        Index("idx_withdrawal_user", "user_id", "created_at"),
        Index(
            "idx_withdrawal_pending", "status", "created_at",
            postgresql_where="status = 'pending'",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False
    )
    teqlik_amount: Mapped[int] = mapped_column(Integer, nullable=False)
    try_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(
        String(3), nullable=False, default="TRY", server_default="'TRY'"
    )
    fiat_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    try_rate_used: Mapped[Decimal] = mapped_column(Numeric(10, 6), nullable=False)
    tcmb_rate_used: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 6), nullable=True)
    iban: Mapped[str] = mapped_column(String(34), nullable=False)
    account_holder: Mapped[str] = mapped_column(String(120), nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending", server_default="'pending'"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    processed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    cancelled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    admin_note: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
