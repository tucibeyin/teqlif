from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class UserBlock(Base):
    __tablename__ = "user_blocks"
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    blocker_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    blocked_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
