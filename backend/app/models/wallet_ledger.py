from datetime import datetime
from decimal import Decimal
from typing import Optional
from sqlalchemy import BigInteger, Integer, Numeric, String, ForeignKey, DateTime, Index, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WalletLedger(Base):
    __tablename__ = "wallet_ledger"
    __table_args__ = (
        Index("idx_wallet_ledger_user_time", "user_id", "created_at"),
        Index("idx_wallet_ledger_type", "tx_type", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False
    )
    delta_teqlik: Mapped[int] = mapped_column(Integer, nullable=False)
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    try_equivalent: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 4), nullable=True)
    try_rate_used: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 6), nullable=True)
    tcmb_rate_used: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 6), nullable=True)
    currency: Mapped[Optional[str]] = mapped_column(String(3), nullable=True)
    tx_type: Mapped[str] = mapped_column(String(40), nullable=False)
    reference_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    reference_type: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
