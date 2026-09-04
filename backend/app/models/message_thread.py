from datetime import datetime
from sqlalchemy import Boolean, DateTime, Integer, String, ForeignKey, func, false
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class MessageThread(Base):
    __tablename__ = "message_threads"

    # user_a_id < user_b_id — canonical pair, CONSTRAINT ordered_user_pair
    user_a_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    user_b_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    # Who sent the first message (enables auto-accept detection when receiver replies)
    initiator_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # 'pending': request awaiting acceptance  'accepted': normal thread  'declined': soft-declined
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="accepted")
    # acceptor'ın arama toggle'ı — default OFF, yalnızca acceptor değiştirebilir
    call_allowed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=false())
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
