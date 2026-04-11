import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Cookie, Depends, HTTPException, Response, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.database import get_db

REFRESH_TOKEN_TTL = 60 * 60 * 24 * 30  # 30 gün (saniye)

# ── Cookie sabitleri ──────────────────────────────────────────────────────────
ACCESS_COOKIE   = "access_token"
REFRESH_COOKIE  = "refresh_token"
_COOKIE_MAX_AGE = REFRESH_TOKEN_TTL  # 30 gün


def set_auth_cookies(response: Response, access_token: str, refresh_token: str) -> None:
    """access_token ve refresh_token'ı HttpOnly Secure cookie olarak ayarlar."""
    response.set_cookie(
        key=ACCESS_COOKIE,
        value=access_token,
        httponly=True,
        secure=True,
        samesite="strict",
        max_age=_COOKIE_MAX_AGE,
        path="/",
    )
    # refresh_token yalnızca /api/auth/refresh path'ine gönderilir
    response.set_cookie(
        key=REFRESH_COOKIE,
        value=refresh_token,
        httponly=True,
        secure=True,
        samesite="strict",
        max_age=_COOKIE_MAX_AGE,
        path="/api/auth/refresh",
    )


def clear_auth_cookies(response: Response) -> None:
    """Oturum cookie'lerini siler (logout)."""
    response.delete_cookie(ACCESS_COOKIE, path="/")
    response.delete_cookie(REFRESH_COOKIE, path="/api/auth/refresh")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(user_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    return jwt.encode({"sub": str(user_id), "exp": expire}, settings.secret_key, algorithm=settings.algorithm)


def create_refresh_token() -> str:
    """Kriptografik güvenli 48 karakterlik opak refresh token üretir."""
    return secrets.token_urlsafe(36)


def decode_token(token: str) -> Optional[int]:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        return int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        return None


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    cookie_token: Optional[str] = Cookie(default=None, alias=ACCESS_COOKIE),
    db: AsyncSession = Depends(get_db),
):
    from app.models.user import User

    # Bearer header öncelikli (mobile), sonra cookie (web tarayıcı)
    raw_token = (credentials.credentials if credentials else None) or cookie_token
    if not raw_token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Giriş yapmanız gerekiyor")

    user_id = decode_token(raw_token)
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Geçersiz token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Kullanıcı bulunamadı")

    return user
