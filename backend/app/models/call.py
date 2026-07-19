from datetime import datetime
from typing import Optional
from sqlalchemy import Boolean, DateTime, Integer, String, Text, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Call(Base):
    __tablename__ = "calls"
    __table_args__ = (
        Index("ix_calls_caller_id", "caller_id"),
        Index("ix_calls_callee_id", "callee_id"),
        Index("ix_calls_started_at", "started_at"),
        Index("ix_calls_caller_status", "caller_id", "status"),
        Index("ix_calls_callee_status", "callee_id", "status"),
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
    duration_seconds: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    had_video: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    max_participants: Mapped[int] = mapped_column(Integer, nullable=False, default=2)


class CallParticipant(Base):
    """Tracks every participant in a call (initiator, callee, and any guests added mid-call)."""
    __tablename__ = "call_participants"
    __table_args__ = (
        Index("idx_call_participants_call_id", "call_id"),
        Index("idx_call_participants_user_id", "user_id"),
        Index("idx_call_participants_call_user", "call_id", "user_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    call_id: Mapped[int] = mapped_column(Integer, ForeignKey("calls.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # initiator | callee | guest
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    # invited | ringing | joined | left | rejected | timeout | removed
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="invited")
    invited_by: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    livekit_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    invited_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    ringing_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    joined_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    left_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
