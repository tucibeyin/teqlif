from datetime import datetime
from typing import Optional
from sqlalchemy import DateTime, Integer, String, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Call(Base):
    __tablename__ = "calls"
    __table_args__ = (
        Index("ix_calls_caller_id", "caller_id"),
        Index("ix_calls_callee_id", "callee_id"),
        Index("ix_calls_started_at", "started_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    caller_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    callee_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    room_name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    # calling | active | ended | rejected | missed
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="calling")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    accepted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
