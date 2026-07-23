"""
Circuit Breaker — dış servis çağrılarını izole eder.

Durum makinesi (Redis-backed, multi-worker tutarlı):
  CLOSED    → normal akış, hatalar sayılır
  OPEN      → tüm çağrılar reddedilir, fallback çalışır
  HALF_OPEN → tek bir deneme geçirilir, başarılıysa CLOSED'a döner

Kullanım:
    fcm_breaker = CircuitBreaker("fcm", failure_threshold=5, recovery_timeout=60)

    @fcm_breaker
    async def send_push(...):
        ...

    # veya context manager olarak:
    async with fcm_breaker:
        await send_push(...)
"""
from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Callable, Any

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_STATE_CLOSED    = "closed"
_STATE_OPEN      = "open"
_STATE_HALF_OPEN = "half_open"


class CircuitOpenError(Exception):
    """Circuit açık — çağrı reddedildi."""


@dataclass
class CircuitBreaker:
    """
    name              : Redis key prefix'i
    failure_threshold : kaç hata sonrası OPEN'a geçilir
    recovery_timeout  : OPEN'dan HALF_OPEN'a geçiş süresi (saniye)
    half_open_timeout : HALF_OPEN test çağrısının timeout'u (saniye)
    """
    name: str
    failure_threshold: int = 5
    recovery_timeout: int  = 60
    half_open_timeout: int = 10
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False, repr=False)

    # ── Redis key'leri ────────────────────────────────────────────────────────
    @property
    def _key_state(self)   -> str: return f"cb:{self.name}:state"
    @property
    def _key_failures(self)-> str: return f"cb:{self.name}:failures"
    @property
    def _key_opened_at(self)-> str: return f"cb:{self.name}:opened_at"

    # ── Durum okuma ───────────────────────────────────────────────────────────
    async def _get_state(self) -> str:
        redis = await get_redis()
        state = await redis.get(self._key_state)
        if not state:
            return _STATE_CLOSED

        if state == _STATE_OPEN:
            opened_at = await redis.get(self._key_opened_at)
            if opened_at and time.time() - float(opened_at) >= self.recovery_timeout:
                await redis.set(self._key_state, _STATE_HALF_OPEN)
                logger.info("[CB:%s] OPEN → HALF_OPEN (recovery timeout doldu)", self.name)
                return _STATE_HALF_OPEN

        return state

    # ── Başarı / hata kayıt ───────────────────────────────────────────────────
    async def _on_success(self) -> None:
        redis = await get_redis()
        state = await redis.get(self._key_state)
        if state in (_STATE_HALF_OPEN, _STATE_OPEN):
            await redis.delete(self._key_state, self._key_failures, self._key_opened_at)
            logger.info("[CB:%s] → CLOSED (başarılı çağrı)", self.name)
        else:
            await redis.delete(self._key_failures)

    async def _on_failure(self) -> None:
        redis = await get_redis()
        failures = await redis.incr(self._key_failures)
        await redis.expire(self._key_failures, self.recovery_timeout * 2)

        state = await redis.get(self._key_state)
        if state == _STATE_HALF_OPEN or (failures or 0) >= self.failure_threshold:
            await redis.set(self._key_state, _STATE_OPEN)
            await redis.set(self._key_opened_at, str(time.time()))
            await redis.delete(self._key_failures)
            logger.warning(
                "[CB:%s] → OPEN (failures=%s threshold=%s)",
                self.name, failures, self.failure_threshold,
            )

    # ── Dekoratör / context manager ───────────────────────────────────────────
    def __call__(self, func: Callable) -> Callable:
        import functools

        @functools.wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            async with self:
                return await func(*args, **kwargs)

        return wrapper

    async def __aenter__(self):
        state = await self._get_state()
        if state == _STATE_OPEN:
            raise CircuitOpenError(f"Circuit '{self.name}' open — call rejected")
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            await self._on_success()
        elif not issubclass(exc_type, CircuitOpenError):
            await self._on_failure()
        return False  # exception'ı yutma

    async def call(self, func: Callable, *args, fallback=None, **kwargs) -> Any:
        """
        Fallback destekli çağrı.
        Circuit açıksa veya çağrı başarısızsa fallback değerini döner.
        """
        try:
            async with self:
                return await func(*args, **kwargs)
        except CircuitOpenError:
            logger.warning("[CB:%s] Fallback kullanılıyor (circuit açık)", self.name)
            return fallback() if callable(fallback) else fallback
        except Exception as exc:
            logger.error("[CB:%s] Çağrı başarısız, fallback | %s", self.name, exc)
            return fallback() if callable(fallback) else fallback


# ── Hazır circuit breaker örnekleri ──────────────────────────────────────────

fcm_breaker = CircuitBreaker(
    name="fcm",
    failure_threshold=5,
    recovery_timeout=60,
)

clickhouse_breaker = CircuitBreaker(
    name="clickhouse",
    failure_threshold=3,
    recovery_timeout=30,
)

livekit_breaker = CircuitBreaker(
    name="livekit",
    failure_threshold=3,
    recovery_timeout=30,
)
