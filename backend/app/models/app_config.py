from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime
from app.database import Base

class AppConfig(Base):
    __tablename__ = "app_configs"

    # key is something like 'ios_min_version', 'ios_latest_version', 'android_min_version', 'android_latest_version'
    key = Column(String, primary_key=True, index=True)
    value = Column(String, nullable=False)
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc).replace(tzinfo=None), onupdate=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
