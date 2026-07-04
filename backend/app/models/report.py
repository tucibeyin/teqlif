from datetime import datetime
from typing import Optional
from sqlalchemy import String, Integer, ForeignKey, DateTime
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(primary_key=True)
    listing_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("listings.id", ondelete="SET NULL"), nullable=True, index=True)
    reporter_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    reason: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
