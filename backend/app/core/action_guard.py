"""
Action Guard — Aşama 3: Kritik Eylem Koruması

Authenticated kullanıcı bazlı iki katmanlı aksiyon koruması:

1. Kullanıcı-Aksiyon Hız Sınırı (User-Action Rate Limit)
   - IP değil, user_id + aksiyon kombinasyonuna özel pencereler.
   - Her kritik aksiyon bağımsız sayaç ve pencereye sahiptir.
   - check_user_action_rate(user_id, action, limit, window) → (allowed, retry_after)
   - check_sliding_window_rate(user_id, action, limit, window, scope) → (allowed, retry_after)
     Sliding-window (sorted set) varyantı: fixed-window'daki burst sorununu önler.
     scope: birden fazla kaynak için izolasyon (örn. auction_id).

2. Idempotency Kilidi (SETNX Lock)
   - Aynı anda gelen çoklu isteklerde (race condition) tek işlemi garantiler.
   - SET key NX EX atomik komutu: kilit yalnızca bir coroutine tarafından alınır.
   - acquire_action_lock(user_id, action, ttl) → bool
   - release_action_lock(user_id, action) → başarılı işlem sonrası erken serbest bırakma

Kullanım (router endpoint'lerinde):
    from app.core.action_guard import (
        check_user_action_rate, check_sliding_window_rate,
        acquire_action_lock, release_action_lock,
    )
    from app.core.exceptions import TooManyRequestsException, ConflictException

    # 1a. Fixed-window hız sınırı
    allowed, retry_after = await check_user_action_rate(uid, "listing_create", limit=1, window=60)
    if not allowed:
        raise TooManyRequestsException(code="LISTING_RATE_LIMIT", retry_after=retry_after)

    # 1b. Sliding-window hız sınırı (açık artırma teklif gibi yüksek frekanslı aksiyonlar)
    allowed, retry_after = await check_sliding_window_rate(uid, "bid", limit=20, window=60, scope=str(stream_id))
    if not allowed:
        raise TooManyRequestsException(code="BID_RATE_LIMIT", retry_after=retry_after)

    # 2. Idempotency kilidi
    if not await acquire_action_lock(uid, "listing_create", ttl=3):
        raise ConflictException(code="REQUEST_IN_PROGRESS")

    # ... işlem ...
    await release_action_lock(uid, "listing_create")
"""

import time

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_ACTION_RATE_PREFIX  = "act_rate:"
_ACTION_LOCK_PREFIX  = "act_lock:"
_SLIDE_RATE_PREFIX   = "slide_rate:"


async def check_user_action_rate(
    user_id: int,
    action: str,
    limit: int,
    window: int,
) -> tuple[bool, int]:
    """
    Kullanıcı + aksiyon bazlı fixed-window hız sınırı.

    Args:
        user_id: Authenticated kullanıcı ID'si
        action:  Aksiyon tanımlayıcısı ("listing_create", "stream_start" vb.)
        limit:   Penceredeki maksimum izin verilen istek sayısı
        window:  Zaman penceresi (saniye)

    Returns:
        (allowed: bool, retry_after: int)
        allowed=False → retry_after, pencere bitişine kalan saniyedir.
        Redis hatasında fail-open → (True, 0) döner.
    """
    try:
        redis = await get_redis()
        key = f"{_ACTION_RATE_PREFIX}{user_id}:{action}"
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, window)
        if count > limit:
            ttl = await redis.ttl(key)
            return False, max(ttl, 1)
        return True, 0
    except Exception as exc:
        logger.error(
            "[ACTION GUARD] check_user_action_rate hatası | user_id=%s action=%s | %s",
            user_id, action, exc, exc_info=True,
        )
        return True, 0  # fail-open: Redis kesintisi işlemi bloke etmez


async def check_sliding_window_rate(
    user_id: int,
    action: str,
    limit: int,
    window: int,
    scope: str = "",
) -> tuple[bool, int]:
    """
    Sliding-window hız sınırı (Redis sorted set, mikrosaniye üyeler).

    Fixed-window'daki burst sorununu önler: pencere başında patlama yok,
    kullanıcı her zaman eşit dağılımlı limit hakkına sahip.

    Args:
        user_id: Authenticated kullanıcı ID'si
        action:  Aksiyon tanımlayıcısı ("bid", "stream_start" vb.)
        limit:   Penceredeki maksimum izin verilen istek sayısı
        window:  Zaman penceresi (saniye)
        scope:   İzolasyon anahtarı (örn. auction_id — farklı açık artırmalar bağımsız)

    Returns:
        (allowed: bool, retry_after: int)
        Redis hatasında fail-open → (True, 0) döner.
    """
    key = f"{_SLIDE_RATE_PREFIX}{user_id}:{action}"
    if scope:
        key = f"{key}:{scope}"

    now_us   = int(time.time() * 1_000_000)   # mikrosaniye — üye çakışmasını önler
    cutoff_us = now_us - window * 1_000_000

    try:
        redis = await get_redis()
        pipe = redis.pipeline()
        pipe.zremrangebyscore(key, "-inf", cutoff_us)
        pipe.zadd(key, {str(now_us): now_us})
        pipe.zcard(key)
        pipe.expire(key, window + 1)
        results = await pipe.execute()
        count = int(results[2])

        if count > limit:
            # Yeni eklenen kaydı geri al — sayaç bozulmasın
            await redis.zrem(key, str(now_us))
            oldest = await redis.zrange(key, 0, 0, withscores=True)
            if oldest:
                oldest_us = float(oldest[0][1])
                retry_after = max(1, int((oldest_us + window * 1_000_000 - now_us) / 1_000_000))
            else:
                retry_after = window
            return False, retry_after
        return True, 0

    except Exception as exc:
        logger.error(
            "[ACTION GUARD] check_sliding_window_rate hatası | user_id=%s action=%s | %s",
            user_id, action, exc, exc_info=True,
        )
        return True, 0  # fail-open


async def acquire_action_lock(
    user_id: int,
    action: str,
    ttl: int = 2,
) -> bool:
    """
    SETNX tabanlı kısa süreli idempotency kilidi.

    Aynı user_id + action için TTL süresi dolmadan ikinci bir istek
    geldiğinde False döner. Race condition ile gelen eş zamanlı istekler
    DB'ye ulaşamadan reddedilir.

    Args:
        user_id: Authenticated kullanıcı ID'si
        action:  Aksiyon tanımlayıcısı
        ttl:     Kilit ömrü saniye (varsayılan 2 — en uzun DB commit süresinden fazla olmalı)

    Returns:
        True  — Kilit alındı, işlem güvenle başlatılabilir
        False — Kilit başkası tarafından tutuluyor, istek reddedilmeli
        Redis hatasında fail-open → True
    """
    try:
        redis = await get_redis()
        key = f"{_ACTION_LOCK_PREFIX}{user_id}:{action}"
        # SET key "1" NX EX ttl — atomik: ya alır ya almaz
        result = await redis.set(key, "1", nx=True, ex=ttl)
        return result is not None
    except Exception as exc:
        logger.error(
            "[ACTION GUARD] acquire_action_lock hatası | user_id=%s action=%s | %s",
            user_id, action, exc, exc_info=True,
        )
        return True  # fail-open


async def release_action_lock(user_id: int, action: str) -> None:
    """
    İşlem başarıyla tamamlandıktan sonra kilidi TTL beklemeden serbest bırakır.

    Kullanıcının kısa süre içinde meşru bir ikinci istek gönderebilmesi için
    başarılı işlem sonrasında çağrılması önerilir.

    Not: Çağrılmasa da kilit TTL sonunda otomatik düşer — zorunlu değil.
    """
    try:
        redis = await get_redis()
        await redis.delete(f"{_ACTION_LOCK_PREFIX}{user_id}:{action}")
    except Exception as exc:
        logger.error(
            "[ACTION GUARD] release_action_lock hatası | user_id=%s action=%s | %s",
            user_id, action, exc, exc_info=True,
        )
