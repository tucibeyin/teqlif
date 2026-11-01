from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class UserDevice(Base):
    __tablename__ = "user_devices"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    fcm_token: Mapped[str] = mapped_column(String(500), unique=True, index=True, nullable=False)
    platform: Mapped[str] = mapped_column(String(20), nullable=False, server_default="unknown")
    apns_sandbox: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
