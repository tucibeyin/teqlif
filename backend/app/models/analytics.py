from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import JSONB

from app.database import Base

class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(255), index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    event_type = Column(String(100), index=True, nullable=False)
    url = Column(String(1024), nullable=True)

    device_type = Column(String(50), nullable=True)
    os = Column(String(50), nullable=True)
    browser = Column(String(50), nullable=True)

    ip_address = Column(String(50), nullable=True)

    event_metadata = Column(JSONB, nullable=True)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)

    __table_args__ = (
        Index("ix_analytics_events_session_type", "session_id", "event_type"),
        Index("ix_analytics_events_user_created", "user_id", "created_at"),
    )


class UserInteraction(Base):
    """
    Implicit signal collection — kullanıcının içerikle etkileşim süreleri.
    Doğrudan DB'ye yazılmaz; Redis kuyruğundan periyodik bulk-insert ile dolar.
    """
    __tablename__ = "user_interactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    item_id = Column(Integer, nullable=False)
    item_type = Column(String(20), nullable=False)
    interaction_type = Column(String(30), nullable=False)
    duration_seconds = Column(Float, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)

    __table_args__ = (
        Index("ix_user_interactions_user_item", "user_id", "item_id"),
        Index("ix_user_interactions_created", "created_at"),
    )
