from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Index
from sqlalchemy.dialects.postgresql import JSONB

from app.database import Base

class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String(255), index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    
    event_type = Column(String(100), index=True, nullable=False)
    url = Column(String(1024), nullable=True)
    
    device_type = Column(String(50), nullable=True) # e.g., 'mobile', 'desktop', 'tablet'
    os = Column(String(50), nullable=True) # e.g., 'iOS', 'Android', 'Windows', 'Mac'
    browser = Column(String(50), nullable=True)
    
    ip_address = Column(String(50), nullable=True)
    
    # Store any additional custom event parameters
    event_metadata = Column(JSONB, nullable=True) 
    
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)

    __table_args__ = (
        Index("ix_analytics_events_session_type", "session_id", "event_type"),
    )
