"""
CQRS Read Model Cache — Cache-Aside pattern.

Write tarafı (PostgreSQL) değişmez; okuma tarafı Redis üzerinden
servis edilir. Miss durumunda DB'den çekip cache'e yazar.

Kullanım:
    from app.core.read_cache import read_cache, invalidate_cache

    # Endpoint'te:
    cached = await read_cache("listings:search", params, ttl=30)
    if cached is not None:
        return cached
    result = await ListingService(db).get_listings(...)
    await read_cache.set("listings:search", params, result, ttl=30)
    return result

    # İlan oluşturulduğunda/güncellendiğinde:
    await invalidate_cache("listings:search")
"""
from __future__ import annotations

import hashlib
import json
from typing import Any

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_PREFIX = "cqrs"


def _make_key(namespace: str, params: dict) -> str:
    params_hash = hashlib.md5(
        json.dumps(params, sort_keys=True, default=str).encode()
    ).hexdigest()[:12]
    return f"{_PREFIX}:{namespace}:{params_hash}"


async def cache_get(namespace: str, params: dict) -> Any | None:
    """Cache miss → None, hit → deserialize edilmiş veri."""
    try:
        redis = await get_redis()
        raw = await redis.get(_make_key(namespace, params))
        if raw:
            logger.debug("[CQRS] Cache HIT | ns=%s", namespace)
            return json.loads(raw)
    except Exception as exc:
        logger.warning("[CQRS] Cache get hatası | ns=%s | %s", namespace, exc)
    return None


async def cache_set(namespace: str, params: dict, data: Any, ttl: int = 30) -> None:
    """Veriyi Redis'e yazar."""
    try:
        redis = await get_redis()
        await redis.set(
            _make_key(namespace, params),
            json.dumps(data, default=str),
            ex=ttl,
        )
        logger.debug("[CQRS] Cache SET | ns=%s ttl=%s", namespace, ttl)
    except Exception as exc:
        logger.warning("[CQRS] Cache set hatası | ns=%s | %s", namespace, exc)


async def invalidate_cache(namespace: str) -> int:
    """
    Namespace'e ait tüm cache key'lerini siler.
    İlan oluşturma/güncelleme/silme sonrası çağrılır.
    """
    try:
        redis = await get_redis()
        pattern = f"{_PREFIX}:{namespace}:*"
        keys = [k async for k in redis.scan_iter(pattern)]
        if keys:
            await redis.delete(*keys)
            logger.info("[CQRS] Cache INVALIDATE | ns=%s | %d key silindi", namespace, len(keys))
            return len(keys)
    except Exception as exc:
        logger.warning("[CQRS] Cache invalidate hatası | ns=%s | %s", namespace, exc)
    return 0
