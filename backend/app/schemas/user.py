from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr, field_validator
import re


class UserRegister(BaseModel):
    email: EmailStr
    username: str
    full_name: str
    password: str
    phone: str | None = None
    firebase_token: str | None = None

    @field_validator("username")
    @classmethod
    def username_valid(cls, v: str) -> str:
        if not re.match(r"^[a-z0-9_]{3,50}$", v):
            raise ValueError("Kullanıcı adı 3-50 karakter, sadece küçük harf/rakam/alt çizgi")
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
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: int
    email: str
    username: str
    full_name: str
    is_active: bool
    is_verified: bool
    phone: Optional[str] = None
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    username: Optional[str] = None
    profile_image_url: Optional[str] = None
    profile_image_thumb_url: Optional[str] = None


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class VerifyEmail(BaseModel):
    email: EmailStr
    code: str


class ResendCode(BaseModel):
    email: EmailStr


DEFAULT_NOTIF_PREFS = {
    "messages": True,
    "follows": True,
    "auction_won": True,
    "stream_started": True,
    "new_listing": True,
    "new_bid": True,
    "outbid": True,
}


class NotificationPrefs(BaseModel):
    messages: bool = True
    follows: bool = True
    auction_won: bool = True
    stream_started: bool = True
    new_listing: bool = True
    new_bid: bool = True
    outbid: bool = True


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
