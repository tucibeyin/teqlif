"""
Idempotency Key middleware — çift tıklama ve ağ retry'larına karşı koruma.

Kullanım (FastAPI endpoint'inde):
    @router.post("/bid")
    async def place_bid(
        idempotency=Depends(idempotency_key("bid", ttl=30)),
        ...
    ):
        ...

İstemci X-Idempotency-Key header'ı gönderir.
Aynı key + endpoint 30sn içinde tekrar gelirse cached response dönülür,
iş mantığı tekrar çalışmaz.
"""
from __future__ import annotations

import json
from typing import Callable

from fastapi import Depends, Header, Request, Response
from fastapi.responses import JSONResponse

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_PREFIX = "idempotency"


def idempotency_key(scope: str, ttl: int = 30) -> Callable:
    """
    FastAPI dependency factory.

    scope : endpoint grubunu ayırt eder (örn. "bid", "wallet_spend")
    ttl   : aynı key'in geçerli olduğu süre (saniye)
    """
    async def _dep(
        request: Request,
        x_idempotency_key: str | None = Header(default=None, alias="X-Idempotency-Key"),
    ):
        if not x_idempotency_key:
            return  # Header yoksa geç — idempotency isteğe bağlı

        redis = await get_redis()
        redis_key = f"{_PREFIX}:{scope}:{x_idempotency_key}"

        cached = await redis.get(redis_key)
        if cached:
            logger.info(
                "[IDEMPOTENCY] Tekrar istek yakalandı | scope=%s key=%s",
                scope, x_idempotency_key[:12],
            )
            data = json.loads(cached)
            # Middleware response objesi döndürerek endpoint'i atlar
            raise _IdempotencyReplay(JSONResponse(
                content=data["body"],
                status_code=data["status_code"],
            ))

        # Sonucu response hook ile yakala ve cache'le
        request.state._idempotency_redis_key = redis_key
        request.state._idempotency_ttl = ttl

    return _dep


class _IdempotencyReplay(Exception):
    """Cached response'u endpoint'i çalıştırmadan döndürmek için."""
    def __init__(self, response: JSONResponse):
        self.response = response


async def store_idempotency_result(
    request: Request,
    body: dict,
    status_code: int = 200,
) -> None:
    """
    Endpoint başarıyla tamamlandıktan sonra çağrılır.
    Sonucu Redis'e yazar.
    """
    redis_key = getattr(request.state, "_idempotency_redis_key", None)
    ttl = getattr(request.state, "_idempotency_ttl", 30)
    if not redis_key:
        return
    try:
        redis = await get_redis()
        await redis.set(
            redis_key,
            json.dumps({"body": body, "status_code": status_code}),
            ex=ttl,
        )
    except Exception as exc:
        logger.warning("[IDEMPOTENCY] Cache yazılamadı | %s", exc)
