import redis.asyncio as aioredis
from app.config import settings

_redis: aioredis.Redis | None = None
_redis_binary: aioredis.Redis | None = None
_redis_stream: aioredis.Redis | None = None


async def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    return _redis


async def get_redis_stream() -> aioredis.Redis:
    """Dedicated client for XREAD BLOCK commands.

    redis-py 5+ async raises TimeoutError on blocking reads when socket_timeout
    is shorter than the BLOCK duration. This client sets socket_timeout=10s
    (> _BLOCK_MS=5s) so XREAD BLOCK 5000 always completes before the timeout.
    socket_connect_timeout=5 keeps the initial handshake snappy.
    """
    global _redis_stream
    if _redis_stream is None:
        _redis_stream = aioredis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_timeout=10,
            socket_connect_timeout=5,
        )
    return _redis_stream


_redis_blpop: aioredis.Redis | None = None


async def get_redis_blpop() -> aioredis.Redis:
    """Dedicated client for BLPOP commands.

    socket_timeout=None prevents TimeoutError on long blocking reads.
    Redis itself sends a nil reply after the blpop timeout expires, so the
    blocking duration is always bounded — no risk of indefinite suspension.
    """
    global _redis_blpop
    if _redis_blpop is None:
        _redis_blpop = aioredis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_timeout=None,
        )
    return _redis_blpop


async def get_redis_binary() -> aioredis.Redis:
    """decode_responses=False client — for storing/reading raw bytes (numpy vectors etc.)."""
    global _redis_binary
    if _redis_binary is None:
        _redis_binary = aioredis.from_url(settings.redis_url, decode_responses=False)
    return _redis_binary
