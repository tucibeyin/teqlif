"""
CQRS Read Model Cache portu (Hexagonal Architecture).

Domain / Application katmanı bu arayüzü bilir; Redis gibi altyapı
detaylarından tamamen izoledir.  Somut uygulama Infrastructure katmanında
(``app.infrastructure.adapters.redis_cache_service``) yaşar.
"""
from __future__ import annotations

import abc
from typing import Any, Awaitable, Callable


class ICacheService(abc.ABC):
    """CQRS okuma modeli önbellek portu."""

    @abc.abstractmethod
    async def get(
        self,
        namespace: str,
        params: dict,
        prefix_key: str | None = None,
    ) -> Any | None:
        """Cache hit → veri, miss → None."""

    @abc.abstractmethod
    async def set(
        self,
        namespace: str,
        params: dict,
        data: Any,
        *,
        ttl: int = 30,
        prefix_key: str | None = None,
    ) -> None:
        """Veriyi cache'e yazar."""

    @abc.abstractmethod
    async def invalidate(
        self,
        namespace: str,
        prefix_key: str | None = None,
    ) -> int:
        """
        Namespace'i (opsiyonel olarak prefix ile) invalidate eder.
        Dönen değer her zaman 1 (komut sayısı); eski anahtar sayısı değil.
        """

    @abc.abstractmethod
    async def get_or_compute(
        self,
        namespace: str,
        params: dict,
        compute_fn: Callable[[], Awaitable[Any]],
        *,
        ttl: int = 30,
        prefix_key: str | None = None,
    ) -> Any:
        """
        Stampede-safe cache-aside.

        Hit → veriyi döner.  Miss → distributed lock al → ``compute_fn()``
        çalıştır → cache'e yaz → döner.  Lock sahibi olmayanlar 50 ms
        bekleyip cache'ten tekrar okur; son çare olarak ``compute_fn()``
        çağırır.
        """
