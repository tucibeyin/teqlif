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

    @abc.abstractmethod
    async def get_etag(
        self,
        namespace: str,
        params: dict,
        prefix_key: str | None = None,
    ) -> str | None:
        """
        Namespace versiyonu ile doğrulanmış ETag hash'ini döner.

        Namespace invalidate edilmişse (ns_ver değişmişse) None döner;
        böylece eski ETag store'lar otomatik olarak geçersiz sayılır.
        """

    @abc.abstractmethod
    async def store_etag(
        self,
        namespace: str,
        params: dict,
        etag: str,
        *,
        ttl: int = 600,
        prefix_key: str | None = None,
    ) -> None:
        """
        ETag hash'ini namespace versiyonuyla birlikte kaydeder.

        TTL bilinçli olarak data cache TTL'inden uzundur; ns_ver check
        invalidasyon güvencesini sağlar, TTL yalnızca Redis bellek baskısı
        için kullanılır.
        """
