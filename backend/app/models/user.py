from datetime import datetime
from typing import Any, Optional
from sqlalchemy import String, Boolean, DateTime, Float, Integer, JSON, func
from sqlalchemy.orm import Mapped, mapped_column
from pgvector.sqlalchemy import Vector

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    fcm_token: Mapped[str | None] = mapped_column(String(500), nullable=True)
    profile_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    profile_image_thumb_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    notification_prefs: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True)
    phone_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")

    @property
    def is_verified(self) -> bool:
        """Tam doğrulama: hem e-posta hem telefon doğrulandıysa True."""
        return self.email_verified and self.phone_verified
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_shadowbanned: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    preference_embedding: Mapped[Optional[Any]] = mapped_column(Vector(384), nullable=True)
    # 90. yüzdelik fiyat tavanı — ClickHouse'daki son 7 gün etkileşim verisinden hesaplanır
    max_budget: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    is_premium: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")
    plan_type: Mapped[str | None] = mapped_column(String(20), nullable=True, default=None)
    premium_since: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True, default=None)
    tuci_balance: Mapped[int] = mapped_column(Integer, default=100, nullable=False, server_default="100")
    bio: Mapped[str | None] = mapped_column(String(150), nullable=True)
    website_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    instagram_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    kick_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    twitch_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    facebook_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    youtube_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    tiktok_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True, default=None)
    onboarding_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="false")
    referral_code: Mapped[str | None] = mapped_column(String(12), unique=True, index=True, nullable=True)
    referral_code_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    pending_referred_by: Mapped[str | None] = mapped_column(String(12), nullable=True, default=None)
    locale: Mapped[str] = mapped_column(String(10), default="tr", nullable=False, server_default="tr")
