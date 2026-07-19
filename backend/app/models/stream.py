from datetime import datetime
from typing import Optional
from sqlalchemy import String, Boolean, Integer, DateTime, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class LiveStream(Base):
    __tablename__ = "live_streams"
    __table_args__ = (
        Index("ix_live_streams_is_live_started_at", "is_live", "started_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    room_name: Mapped[str] = mapped_column(String(120), unique=True, index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[str] = mapped_column(String(60), nullable=False, default="diger")
    host_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    is_live: Mapped[bool] = mapped_column(Boolean, default=True)
    viewer_count: Mapped[int] = mapped_column(Integer, default=0)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    thumbnail_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    host: Mapped["User"] = relationship("User", lazy="selectin")  # noqa: F821
    likes: Mapped[list["StreamLike"]] = relationship(  # type: ignore[name-defined]
        "StreamLike", cascade="all, delete-orphan", passive_deletes=True, lazy="selectin"
    )


class LiveStreamViewer(Base):
    __tablename__ = "live_stream_viewers"

    stream_id: Mapped[int] = mapped_column(ForeignKey("live_streams.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
