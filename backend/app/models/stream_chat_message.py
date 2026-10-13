from datetime import datetime
from typing import Optional

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class StreamChatMessage(Base):
    __tablename__ = "stream_chat_messages"

    id:         Mapped[int]           = mapped_column(BigInteger, primary_key=True)
    stream_id:  Mapped[int]           = mapped_column(ForeignKey("live_streams.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id:    Mapped[Optional[int]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    username:   Mapped[str]           = mapped_column(String(100), nullable=False)
    avatar_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    content:    Mapped[str]           = mapped_column(Text, nullable=False)
    is_host:    Mapped[bool]          = mapped_column(Boolean, default=False, nullable=False)
    is_mod:     Mapped[bool]          = mapped_column(Boolean, default=False, nullable=False)
    is_hidden:  Mapped[bool]          = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime]      = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
