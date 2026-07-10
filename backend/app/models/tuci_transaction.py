from datetime import datetime
from typing import Optional
from sqlalchemy import Integer, String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class TuciTransaction(Base):
    __tablename__ = "tuci_transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)  # negatif = harcama, pozitif = kazanç
    transaction_type: Mapped[str] = mapped_column(String(50), nullable=False)
    reference_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    reference_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)  # "listing" | "stream"
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
