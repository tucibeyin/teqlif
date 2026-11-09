"""
CQRS Read Model Cache — Redis implementasyonu.

CACHE-16: ICacheService portunu implement eden tekil altyapı adaptörü.
CACHE-17: get_or_compute() distributed mutex ile Thundering Herd koruması.
CACHE-18: scan_iter O(N) yerine namespace versioning ile O(1) invalidasyon.

Namespace Versioning Tasarımı
──────────────────────────────
  • Her namespace (ve opsiyonel prefix_key) için Redis'te bir sayaç tutulur:
      ``ns_ver:{namespace}``          → global namespace sayacı
      ``ns_ver:{namespace}:{prefix}`` → prefix bazlı sayaç
  • Cache key'i sayaç değerinden BAĞIMSIZ tutulur; bunun yerine değer
    içine ``_ver`` gömülür:
      Redis key   → ``cqrs:{namespace}[:{prefix}]:{params_hash}``
      Redis value → ``{"_ver": <sayaç>, "_d": <veri>}``
  • ``invalidate()`` sadece sayacı artırır (``INCR``, O(1)).
  • ``get()`` değeri okur; ``_ver`` ≠ güncel sayaç ise "miss" sayar.
  • Eski anahtarlar TTL'leri dolunca Redis'ten otomatik kalkar — hiçbir
    ek temizleme işlemi gerekmez.

GET Optimizasyonu
──────────────────
  ``get()`` sayaç ve veriyi aynı pipeline içinde tek round-trip'te okur
  (redis-py ``pipeline(transaction=False)``).
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import random
from typing import Any, Awaitable, Callable
from uuid import uuid4

from app.core.ports.cache_port import ICacheService
from app.core.logger import get_logger
from app.utils.redis_client import get_redis

logger = get_logger(__name__)

_PREFIX = "cqrs"
_ETAG_PREFIX = "etag_store"
_LOCK_TTL_S = 5       # dağıtık kilit için maks bekleme süresi (saniye)
_ETAG_STORE_TTL = 600  # 10 dk — data TTL'inden bağımsız; ns_ver check güvencesi sağlar

# Atomik check-and-delete: yalnızca token sahibi kilidi siler (Redlock standardı).
_UNLOCK_SCRIPT = """
if redis.call('get', KEYS[1]) == ARGV[1] then
    return redis.call('del', KEYS[1])
else
    return 0
end
"""


class RedisCacheService(ICacheService):
    """Redis tabanlı CQRS Read Model önbelleği."""

    # ── İç yardımcılar ──────────────────────────────────────────────────────

    @staticmethod
    def _ns_ver_key(namespace: str, prefix_key: str | None) -> str:
        if prefix_key:
            return f"ns_ver:{namespace}:{prefix_key}"
        return f"ns_ver:{namespace}"

    @staticmethod
    def _make_key(namespace: str, params: dict, prefix_key: str | None) -> str:
        h = hashlib.md5(
            json.dumps(params, sort_keys=True, default=str).encode()
        ).hexdigest()[:12]
        if prefix_key:
            return f"{_PREFIX}:{namespace}:{prefix_key}:{h}"
        return f"{_PREFIX}:{namespace}:{h}"

    @staticmethod
    def _etag_key(namespace: str, params: dict, prefix_key: str | None) -> str:
        h = hashlib.md5(
            json.dumps(params, sort_keys=True, default=str).encode()
        ).hexdigest()[:12]
        if prefix_key:
            return f"{_ETAG_PREFIX}:{namespace}:{prefix_key}:{h}"
        return f"{_ETAG_PREFIX}:{namespace}:{h}"

    # ── ICacheService implementasyonu ───────────────────────────────────────

    async def get(
        self,
        namespace: str,
        params: dict,
        prefix_key: str | None = None,
    ) -> Any | None:
        """Pipeline ile tek round-trip: sayaç + veri birlikte okunur."""
        try:
            redis = await get_redis()
            cache_key = self._make_key(namespace, params, prefix_key)
            ns_ver_key = self._ns_ver_key(namespace, prefix_key)

            async with redis.pipeline(transaction=False) as pipe:
                pipe.get(ns_ver_key)
                pipe.get(cache_key)
                ver_raw, data_raw = await pipe.execute()

            current_ver = int(ver_raw) if ver_raw else 0

            if data_raw:
                try:
                    envelope = json.loads(data_raw)
                    if (
                        isinstance(envelope, dict)
                        and envelope.get("_ver", -1) == current_ver
                    ):
                        logger.debug("[CQRS] Cache HIT | ns=%s", namespace)
                        return envelope["_d"]
                    # Farklı versiyon → eski giriş, miss gibi davran
                except Exception:
                    pass
        except Exception as exc:
            logger.warning("[CQRS] Cache get hatası | ns=%s | %s", namespace, exc)
        return None

    async def set(
        self,
        namespace: str,
        params: dict,
        data: Any,
        *,
        ttl: int = 30,
        prefix_key: str | None = None,
    ) -> None:
        try:
            redis = await get_redis()
            ver_raw = await redis.get(self._ns_ver_key(namespace, prefix_key))
            current_ver = int(ver_raw) if ver_raw else 0
            envelope = json.dumps({"_ver": current_ver, "_d": data}, default=str)
            await redis.set(
                self._make_key(namespace, params, prefix_key),
                envelope,
                ex=ttl,
            )
            logger.debug("[CQRS] Cache SET | ns=%s ttl=%s", namespace, ttl)
        except Exception as exc:
            logger.warning("[CQRS] Cache set hatası | ns=%s | %s", namespace, exc)

    async def invalidate(
        self,
        namespace: str,
        prefix_key: str | None = None,
    ) -> int:
        """
        O(1) invalidasyon — scan_iter yok.

        Sayacı bir artırır; mevcut cache girişleri artık eski versiyon
        numarasını taşıdığı için otomatik olarak miss sayılır.  TTL dolunca
        Redis'ten silinirler.
        """
        try:
            redis = await get_redis()
            new_ver = await redis.incr(self._ns_ver_key(namespace, prefix_key))
            logger.info(
                "[CQRS] Cache INVALIDATE | ns=%s prefix=%s | yeni sürüm=%d",
                namespace,
                prefix_key,
                new_ver,
            )
            return 1
        except Exception as exc:
            logger.warning(
                "[CQRS] Cache invalidate hatası | ns=%s | %s", namespace, exc
            )
        return 0

    async def get_etag(
        self,
        namespace: str,
        params: dict,
        prefix_key: str | None = None,
    ) -> str | None:
        """
        Namespace versiyonu ile doğrulanmış ETag hash'ini döner (CACHE-20).

        Pipeline ile tek round-trip: ns_ver + etag_store birlikte okunur.
        ns_ver değişmişse (invalidasyon sonrası) None döner — otomatik geçersizleştirme.
        """
        try:
            redis = await get_redis()
            etag_key = self._etag_key(namespace, params, prefix_key)
            ns_ver_key = self._ns_ver_key(namespace, prefix_key)

            async with redis.pipeline(transaction=False) as pipe:
                pipe.get(ns_ver_key)
                pipe.get(etag_key)
                ver_raw, store_raw = await pipe.execute()

            current_ver = int(ver_raw) if ver_raw else 0

            if store_raw:
                envelope = json.loads(store_raw)
                if isinstance(envelope, dict) and envelope.get("_ver") == current_ver:
                    return envelope.get("_etag")
        except Exception as exc:
            logger.debug("[CQRS] ETag get hatası | ns=%s | %s", namespace, exc)
        return None

    async def store_etag(
        self,
        namespace: str,
        params: dict,
        etag: str,
        *,
        ttl: int = _ETAG_STORE_TTL,
        prefix_key: str | None = None,
    ) -> None:
        """
        ETag hash'ini namespace versiyonuyla birlikte kaydeder (CACHE-20).

        TTL bilinçli olarak data cache TTL'inden uzundur; ns_ver check
        invalidasyon güvencesini sağlar.  TTL yalnızca Redis bellek baskısı
        için kullanılır.
        """
        try:
            redis = await get_redis()
            ver_raw = await redis.get(self._ns_ver_key(namespace, prefix_key))
            current_ver = int(ver_raw) if ver_raw else 0
            envelope = json.dumps({"_ver": current_ver, "_etag": etag})
            await redis.set(
                self._etag_key(namespace, params, prefix_key),
                envelope,
                ex=ttl,
            )
            logger.debug("[CQRS] ETag STORE | ns=%s ttl=%s", namespace, ttl)
        except Exception as exc:
            logger.debug("[CQRS] ETag store hatası | ns=%s | %s", namespace, exc)

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
        Stampede-safe cache-aside (CACHE-17).

        Distributed mutex: yalnızca bir worker DB'ye gider; diğerleri
        50 ms bekleyip cache'ten okur.  Lock sahibi çökerse fallback
        olarak compute edilir.
        """
        cached = await self.get(namespace, params, prefix_key)
        if cached is not None:
            return cached

        try:
            redis = await get_redis()
            lock_key = f"lock:{self._make_key(namespace, params, prefix_key)}"

            token = uuid4().hex
            acquired = await redis.set(lock_key, token, nx=True, ex=_LOCK_TTL_S)
            if acquired:
                try:
                    # Double-check: başka worker cache'i doldurmuş olabilir.
                    cached = await self.get(namespace, params, prefix_key)
                    if cached is not None:
                        return cached
                    result = await compute_fn()
                    await self.set(namespace, params, result, ttl=ttl, prefix_key=prefix_key)
                    return result
                finally:
                    try:
                        # Redlock: yalnızca kendi token'ımızı sil — TTL aşımında
                        # başka worker'ın kilidini silmemek için atomik Lua script.
                        await redis.eval(_UNLOCK_SCRIPT, 1, lock_key, token)
                    except Exception:
                        pass
            else:
                # Lock başka worker'da; jitter ile bekle ve tekrar dene.
                # Sabit 50ms yerine 30-70ms arası rastgele bekleme: kilit açılınca
                # tüm worker'ların eş zamanlı Redis'e vurmasını önler.
                await asyncio.sleep(random.uniform(0.03, 0.07))
                cached = await self.get(namespace, params, prefix_key)
                if cached is not None:
                    return cached
                # Lock sahibi hata almış olabilir — biz de compute edelim.
                return await compute_fn()
        except Exception:
            # Redis tamamen erişilemez — grace: DB'den çek.
            return await compute_fn()
