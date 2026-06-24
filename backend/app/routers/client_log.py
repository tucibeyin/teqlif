"""
Mobil istemciden gelen hata loglarını uvicorn log'una yazar.

Endpoint: POST /api/client-log
Kimlik doğrulama: opsiyonel (token varsa user_id loglanır)
Rate limit: Redis ile IP başına dakikada 20 istek

Kullanım:
    Mobil cihazda yakalanan istisnalar bu endpoint'e gönderilir;
    böylece tüm hatalar tek bir yerden (journalctl) takip edilebilir.
"""
from __future__ import annotations

import time
from typing import Any, Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from app.core.logger import get_logger
from app.utils.auth import decode_token, bearer_scheme

logger = get_logger(__name__)
router = APIRouter(prefix="/api/client-log", tags=["client-log"])

_RL_WINDOW = 60   # saniye
_RL_LIMIT  = 20   # pencere başına max istek


class ClientLogEntry(BaseModel):
    tag:      str
    message:  str
    error:    Optional[str]            = None
    details:  Optional[dict[str, Any]] = None
    platform: Optional[str]           = None  # "ios" | "android"
    version:  Optional[str]           = None  # app version


async def _optional_user_id(credentials=Depends(bearer_scheme)) -> Optional[int]:
    if not credentials:
        return None
    try:
        return decode_token(credentials.credentials)
    except Exception:
        return None


async def _rate_check(request: Request) -> bool:
    """IP başına dakikada 20 istek sınırı. Redis yoksa sınır uygulanmaz."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        if not redis:
            return True
        ip  = request.client.host if request.client else "unknown"
        key = f"rl:client_log:{ip}"
        cnt = await redis.incr(key)
        if cnt == 1:
            await redis.expire(key, _RL_WINDOW)
        return cnt <= _RL_LIMIT
    except Exception:
        return True


@router.post("")
async def client_log(
    entry:   ClientLogEntry,
    request: Request,
    user_id: Optional[int] = Depends(_optional_user_id),
) -> dict:
    if not await _rate_check(request):
        return {"ok": True}

    ip       = request.client.host if request.client else "?"
    platform = entry.platform or "?"
    version  = entry.version  or "?"

    logger.warning(
        "[CLIENT_LOG] tag=%s | user_id=%s | platform=%s | v=%s | ip=%s | %s%s",
        entry.tag,
        user_id  or "anon",
        platform,
        version,
        ip,
        entry.message,
        f" | error={entry.error}" if entry.error else "",
    )

    if entry.details:
        logger.warning("[CLIENT_LOG] details | tag=%s | %s", entry.tag, entry.details)

    return {"ok": True}
