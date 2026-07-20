from datetime import datetime
from typing import Optional
from sqlalchemy import String, Boolean, Float, DateTime, Integer, ForeignKey, func, Index
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import Enum as SQLEnum
from app.models.enums import SearchAlertStatus
from app.database import Base


class SearchAlert(Base):
    __tablename__ = "search_alerts"
    __table_args__ = (
        Index("ix_search_alerts_user_status", "user_id", "status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    query: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    max_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    status: Mapped[SearchAlertStatus] = mapped_column(SQLEnum(SearchAlertStatus), default=SearchAlertStatus.ACTIVE, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
