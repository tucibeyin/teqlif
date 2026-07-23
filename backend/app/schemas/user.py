from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator
from app.models.enums import UserStatus
import re


class UserRegister(BaseModel):
    email: EmailStr
    username: str
    full_name: str
    password: str
    phone: str | None = None
    referred_by: str | None = None  # davet kodu (isteğe bağlı)
    lang: str = "tr"

    @field_validator("username")
    @classmethod
    def username_valid(cls, v: str) -> str:
        if not re.match(r"^[a-z0-9_]{3,50}$", v):
            raise ValueError("USERNAME_INVALID")
        return v

    @field_validator("password")
    @classmethod
    def password_strong(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Şifre en az 8 karakter olmalı")
        return v

    @field_validator("full_name")
    @classmethod
    def full_name_valid(cls, v: str) -> str:
        if len(v.strip()) < 2:
            raise ValueError("Ad soyad en az 2 karakter olmalı")
        return v.strip()


class UserLogin(BaseModel):
    login_identifier: str
    password: str

    @model_validator(mode='before')
    @classmethod
    def _accept_legacy_username(cls, data: dict) -> dict:
        # Accept 'username' or 'email' as aliases for 'login_identifier'.
        # External tools (Postman, Python scripts, monitoring) may use the old
        # field name; silently map them so they get a 200 instead of a 422.
        if isinstance(data, dict) and 'login_identifier' not in data:
            for alias in ('username', 'email'):
                if alias in data:
                    data = {**data, 'login_identifier': data[alias]}
                    break
        return data


class UserOut(BaseModel):
    id: int
    email: str
    username: str
    full_name: str
    status: UserStatus
    is_verified: bool
    locale: Optional[str] = None
    is_private: bool = False
    phone: Optional[str] = None
    phone_verified: bool = False
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None
    created_at: datetime
    is_premium: bool = False
    plan_type: Optional[str] = None
    bio: Optional[str] = None
    website_url: Optional[str] = None
    instagram_url: Optional[str] = None
    kick_url: Optional[str] = None
    twitch_url: Optional[str] = None
    facebook_url: Optional[str] = None
    youtube_url: Optional[str] = None
    tiktok_url: Optional[str] = None
    onboarding_completed: bool = False

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    username: Optional[str] = None
    locale: Optional[str] = None
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None
    bio: Optional[str] = None
    website_url: Optional[str] = None
    instagram_url: Optional[str] = None
    kick_url: Optional[str] = None
    twitch_url: Optional[str] = None
    facebook_url: Optional[str] = None
    youtube_url: Optional[str] = None
    tiktok_url: Optional[str] = None
    locale: Optional[str] = None
    is_private: Optional[bool] = None


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut


class VerifyEmail(BaseModel):
    email: EmailStr
    code: str


class ResendCode(BaseModel):
    email: EmailStr
    lang: str = "tr"


DEFAULT_NOTIF_PREFS = {
    "messages": True,
    "follows": True,
    "auction_won": True,
    "stream_started": True,
    "new_listing": True,
    "new_bid": True,
    "outbid": True,
    "smart_alert": True,
    "bid_threshold_tl": 0,
    "quiet_hours_enabled": False,
    "quiet_from": "22:00",
    "quiet_to": "08:00",
    "receive_blast_notifications": True,
}


class NotificationPrefs(BaseModel):
    messages: bool = True
    follows: bool = True
    auction_won: bool = True
    stream_started: bool = True
    new_listing: bool = True
    new_bid: bool = True
    outbid: bool = True
    smart_alert: bool = True
    bid_threshold_tl: int = Field(default=0, ge=0, le=50000)
    quiet_hours_enabled: bool = False
    quiet_from: str = "22:00"
    quiet_to: str = "08:00"
    receive_blast_notifications: bool = True


class ChangePasswordConfirm(BaseModel):
    current_password: str
    new_password: str
    code: str

    @field_validator("new_password")
    @classmethod
    def password_strong(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Şifre en az 8 karakter olmalı")
        return v


class ForgotPassword(BaseModel):
    email: EmailStr
    lang: str = "tr"


class ResetPassword(BaseModel):
    email: EmailStr
    code: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strong(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Şifre en az 8 karakter olmalı")
        return v
