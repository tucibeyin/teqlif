"""
CQRS Read Model Cache — uyumluluk katmanı.

Bu modül geriye dönük uyumluluğu korur: mevcut router ve use-case
importları değişmeden çalışmaya devam eder.  Tüm iş mantığı
``app.infrastructure.adapters.redis_cache_service.RedisCacheService``
içinde yaşar (CACHE-16/17/18).

Kullanım (eskisiyle aynı):
    from app.core.read_cache import cache_get, cache_set, invalidate_cache

    cached = await cache_get("listing:42", params)
    if cached is not None:
        return cached
    result = await service.get(...)
    await cache_set("listing:42", params, result, ttl=60)
    return result

    # İlan güncellendiğinde:
    await invalidate_cache("listing:42")

Stampede-safe erişim (yeni API):
    from app.core.read_cache import cache_get_or_compute

    return await cache_get_or_compute(
        "listing:42", params,
        compute_fn=lambda: service.get(...),
        ttl=60,
    )
"""
from __future__ import annotations

from typing import Any, Awaitable, Callable

from app.infrastructure.adapters.redis_cache_service import RedisCacheService

_cache: RedisCacheService = RedisCacheService()


async def cache_get(
    namespace: str,
    params: dict,
    prefix_key: str | None = None,
) -> Any | None:
    """Cache hit → veri, miss → None."""
    return await _cache.get(namespace, params, prefix_key)


async def cache_set(
    namespace: str,
    params: dict,
    data: Any,
    ttl: int = 30,
    prefix_key: str | None = None,
) -> None:
    """Veriyi cache'e yazar."""
    await _cache.set(namespace, params, data, ttl=ttl, prefix_key=prefix_key)


async def invalidate_cache(namespace: str) -> int:
    """
    Namespace'e ait tüm girişleri O(1) maliyetle geçersiz kılar.

    Eski uygulama ``scan_iter`` ile O(N) Redis taraması yapıyordu.
    Yeni uygulama yalnızca ``INCR ns_ver:{namespace}`` çağırır;
    eski anahtarlar TTL'leri dolunca otomatik silinir (CACHE-18).
    """
    return await _cache.invalidate(namespace)


async def invalidate_user_profile_cache(username: str) -> None:
    """Tek bir kullanıcının profil cache'ini O(1) maliyetle geçersiz kılar."""
    await _cache.invalidate("user_profile", prefix_key=username)


def etag_normalize(tag: str | None) -> str:
    """ETag veya If-None-Match değerinden W/ öneki ve tırnakları soyar.

    CACHE-20: router ve middleware'de ETag karşılaştırması için tek kaynak.
    RFC 7232 §3.2: weak/strong fark gözetilmez; raw hash yeterlidir.
    """
    if not tag:
        return ""
    tag = tag.strip()
    if tag.startswith("W/"):
        tag = tag[2:]
    return tag.strip('"')


async def cache_get_etag(
    namespace: str,
    params: dict,
    prefix_key: str | None = None,
) -> str | None:
    """
    Namespace versiyonu ile doğrulanmış ETag hash'ini döner (CACHE-20).

    Namespace invalidate edilmişse None döner; eski ETag store'lar
    otomatik olarak geçersiz sayılır.
    """
    return await _cache.get_etag(namespace, params, prefix_key)


async def cache_store_etag(
    namespace: str,
    params: dict,
    etag: str,
    *,
    ttl: int = 600,
    prefix_key: str | None = None,
) -> None:
    """ETag hash'ini namespace versiyonuyla birlikte Redis'e kaydeder (CACHE-20)."""
    await _cache.store_etag(namespace, params, etag, ttl=ttl, prefix_key=prefix_key)


async def cache_get_or_compute(
    namespace: str,
    params: dict,
    compute_fn: Callable[[], Awaitable[Any]],
    ttl: int = 30,
    prefix_key: str | None = None,
) -> Any:
    """
    Stampede-safe cache-aside (CACHE-17).

    Cache hit → veriyi döner.  Miss → distributed lock → compute_fn()
    çalıştırır → cache'e yazar.
    """
    return await _cache.get_or_compute(
        namespace, params, compute_fn, ttl=ttl, prefix_key=prefix_key
    )
