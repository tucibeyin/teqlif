import redis.asyncio as aioredis
from app.config import settings

_redis: aioredis.Redis | None = None
_redis_binary: aioredis.Redis | None = None


async def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    return _redis


async def get_redis_binary() -> aioredis.Redis:
    """decode_responses=False client — for storing/reading raw bytes (numpy vectors etc.)."""
    global _redis_binary
    if _redis_binary is None:
        _redis_binary = aioredis.from_url(settings.redis_url, decode_responses=False)
    return _redis_binary
