from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Referral(Base):
    __tablename__ = "referrals"

    id: Mapped[int] = mapped_column(primary_key=True)
    referrer_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    referred_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    # 'pending' | 'completed'
    status: Mapped[str] = mapped_column(String(20), default="completed", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
