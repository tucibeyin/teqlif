import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Cookie, Depends, HTTPException, Response, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.enums import UserStatus
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


_USER_SESSION_TTL = 900  # 15 dakika
_USER_DATETIME_COLS = ("voip_token_updated_at", "created_at", "premium_since", "referral_code_expires_at", "locale_updated_at")


def _serialize_user(user) -> dict:
    data = {}
    for col in user.__table__.columns:
        if col.name == "preference_embedding":
            data[col.name] = None
            continue
        val = getattr(user, col.name, None)
        if isinstance(val, datetime):
            data[col.name] = val.isoformat()
        elif isinstance(val, UserStatus):
            data[col.name] = val.value
        else:
            data[col.name] = val
    return data


async def _fetch_and_cache_user(db: AsyncSession, user_id: int):
    from app.models.user import User
    from app.utils.redis_client import get_redis
    from app.core.logger import get_logger

    try:
        redis = await get_redis()
        cached = await redis.get(f"session:user:{user_id}")
        if cached:
            data = json.loads(cached)
            for dt_col in _USER_DATETIME_COLS:
                val = data.get(dt_col)
                if val and isinstance(val, str):
                    try:
                        data[dt_col] = datetime.fromisoformat(val.replace("Z", "+00:00"))
                    except (ValueError, TypeError):
                        data[dt_col] = None
            if data.get("status"):
                try:
                    data["status"] = UserStatus(data["status"])
                except ValueError:
                    data["status"] = UserStatus.ACTIVE
            user = User(**data)
            return await db.merge(user, load=False)
    except Exception as exc:
        get_logger(__name__).debug("[AUTH] Redis session cache read error for user_id=%s: %s", user_id, exc)

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user and user.status == UserStatus.ACTIVE:
        try:
            redis = await get_redis()
            data = _serialize_user(user)
            await redis.setex(f"session:user:{user_id}", _USER_SESSION_TTL, json.dumps(data, ensure_ascii=False))
        except Exception as exc:
            get_logger(__name__).debug("[AUTH] Redis session cache write error for user_id=%s: %s", user_id, exc)
    return user


async def invalidate_user_session_cache(user_id: int) -> None:
    """Kullanıcı bilgileri güncellendiğinde 15 dakikalık session cache'ini temizler."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        await redis.delete(f"session:user:{user_id}")
    except Exception:
        pass


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    cookie_token: Optional[str] = Cookie(default=None, alias=ACCESS_COOKIE),
    db: AsyncSession = Depends(get_db),
):
    # Bearer header öncelikli (mobile), sonra cookie (web tarayıcı)
    raw_token = (credentials.credentials if credentials else None) or cookie_token
    if not raw_token:
        from app.core.logger import get_logger
        get_logger(__name__).error("[AUTH] get_current_user 401: Giriş yapmanız gerekiyor (raw_token is None)")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Giriş yapmanız gerekiyor")

    user_id = decode_token(raw_token)
    if not user_id:
        from app.core.logger import get_logger
        get_logger(__name__).error(f"[AUTH] get_current_user 401: Geçersiz token (raw_token={raw_token})")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Geçersiz token")

    user = await _fetch_and_cache_user(db, user_id)

    if not user or user.status != UserStatus.ACTIVE:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Kullanıcı bulunamadı")

    return user


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    cookie_token: Optional[str] = Cookie(default=None, alias=ACCESS_COOKIE),
    db: AsyncSession = Depends(get_db),
):
    """Token varsa kullanıcıyı döndürür, yoksa None (misafir erişimi için)."""
    raw_token = (credentials.credentials if credentials else None) or cookie_token
    if not raw_token:
        return None

    user_id = decode_token(raw_token)
    if not user_id:
        return None

    user = await _fetch_and_cache_user(db, user_id)
    return user if user and (user.status == UserStatus.ACTIVE) else None
