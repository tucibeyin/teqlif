"""Kredi yönetimi servisi.

Tüm özellik limitleri, maliyetler ve Redis sayaç mantığı burada toplanmıştır.
Limit ve maliyet değerleri tier.py'dan okunur — bu dosyada literal değer yoktur.
Router'lar kendi limit/Redis kodlarını tutmaz; yalnızca bu modülü kullanır.
"""
from __future__ import annotations

import calendar
import logging
from datetime import datetime, date, timezone
from enum import Enum

from app.services.subscription.tier import (
    credit_free_limit,
    credit_per_op_cap,
    credit_cost_teqlik,
)

logger = logging.getLogger(__name__)


class CreditFeature(str, Enum):
    """Kredi takibi yapılan özellikler.

    str mixin ile dict key ve Redis prefix olarak kullanılabilir.
    Yeni özellik eklendiğinde tier.py'daki CREDIT_FREE_LIMITS,
    CREDIT_PER_OP_CAPS ve CREDIT_COSTS_TEQLIK'e de giriş eklenmelidir.
    """
    BLAST        = "blast"
    BOOST        = "boost"
    AI_DESC      = "ai_desc"
    REACTIVATION = "reactivation"


# ── Public API ─────────────────────────────────────────────────────────────────

def free_limit(feature: CreditFeature, user_type: str) -> int:
    """Tier'a göre aylık ücretsiz kullanım hakkı sayısı."""
    return credit_free_limit(feature.value, user_type)


def cost_teqlik(feature: CreditFeature) -> int:
    """Ücretsiz hak aşıldığında ücretli kullanım başına teqlik maliyeti."""
    return credit_cost_teqlik(feature.value)


def per_op_cap(feature: CreditFeature, user_type: str) -> int | None:
    """Tek işlemde maksimum kullanım sayısı. Tanımsız özellik için None."""
    return credit_per_op_cap(feature.value, user_type)


# ── Fatura dönemi hesabı ───────────────────────────────────────────────────────

def billing_period_start(premium_since: datetime) -> date:
    """Abonelik dönümüne göre mevcut fatura dönemi başlangıcı."""
    today = date.today()
    day = premium_since.day
    last_this = calendar.monthrange(today.year, today.month)[1]
    ann_this = date(today.year, today.month, min(day, last_this))
    if today >= ann_this:
        return ann_this
    prev_m = today.month - 1 if today.month > 1 else 12
    prev_y = today.year if today.month > 1 else today.year - 1
    return date(prev_y, prev_m, min(day, calendar.monthrange(prev_y, prev_m)[1]))


def next_billing_date(premium_since: datetime) -> date:
    """Bir sonraki fatura tarihi."""
    p = billing_period_start(premium_since)
    day = premium_since.day
    nm = p.month + 1 if p.month < 12 else 1
    ny = p.year if p.month < 12 else p.year + 1
    return date(ny, nm, min(day, calendar.monthrange(ny, nm)[1]))


def _billing_ttl(premium_since: datetime | None) -> int:
    """Mevcut fatura döneminin sonuna kadar saniye cinsinden TTL."""
    now = datetime.now(timezone.utc)
    if premium_since:
        nxt = next_billing_date(premium_since)
        end_dt = datetime(nxt.year, nxt.month, nxt.day, tzinfo=timezone.utc)
    else:
        last_day = calendar.monthrange(now.year, now.month)[1]
        end_dt = now.replace(day=last_day, hour=23, minute=59, second=59, microsecond=0)
    return max(60, int((end_dt - now).total_seconds()) + 1)


# ── Redis anahtarı ─────────────────────────────────────────────────────────────

def redis_key(feature: CreditFeature, user_id: int, premium_since: datetime | None) -> str:
    prefix = f"{feature.value}_credits"
    if premium_since:
        period = billing_period_start(premium_since)
        return f"{prefix}:{user_id}:{period.isoformat()}"
    now = datetime.now(timezone.utc)
    return f"{prefix}:{user_id}:{now.strftime('%Y-%m')}"


# ── Redis sayaç yardımcıları ───────────────────────────────────────────────────

async def get_used(
    feature: CreditFeature,
    user_id: int,
    premium_since: datetime | None,
) -> int:
    """Bu dönemde kullanılan kredi sayısını Redis'ten okur.

    Redis erişilemezse 0 döner (fail-open — Availability > Consistency tercihi).
    Kısa Redis kesintilerinde ücretsiz sayaç geçici olarak atlatılabilir;
    bu risk iş birimi tarafından onaylanmıştır.
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        val = await redis.get(redis_key(feature, user_id, premium_since))
        return int(val) if val else 0
    except Exception as exc:
        logger.warning(
            "[CreditService] Redis erişilemedi (get_used) — fail-open: 0. "
            "feature=%s user_id=%s hata=%s",
            feature, user_id, exc,
        )
        return 0


async def increment(
    feature: CreditFeature,
    user_id: int,
    premium_since: datetime | None,
    count: int = 1,
) -> int:
    """Redis sayacını artırır; dönem başındaki ilk yazımda TTL ayarlar.

    Yeni değeri döndürür (atomik INCRBY sonucu).
    """
    if count <= 0:
        return await get_used(feature, user_id, premium_since)
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        key = redis_key(feature, user_id, premium_since)
        new_val = await redis.incrby(key, count)
        if new_val <= count:
            await redis.expire(key, _billing_ttl(premium_since))
        return new_val
    except Exception as exc:
        logger.warning(
            "[CreditService] Redis erişilemedi (increment) — fail-open: 0. "
            "feature=%s user_id=%s count=%s hata=%s",
            feature, user_id, count, exc,
        )
        return 0


# Lua: atomik check-and-consume — TOCTOU önleme.
# KEYS[1]: kredi anahtarı  ARGV[1]: tüketilmek istenen miktar
# ARGV[2]: ücretsiz limit  ARGV[3]: ttl (saniye)
# Dönüş: fiilen tüketilen ücretsiz kredi sayısı (0 ≤ returned ≤ count)
_LUA_CHECK_AND_CONSUME = """
local current = tonumber(redis.call('GET', KEYS[1]) or '0')
local limit   = tonumber(ARGV[2])
local count   = tonumber(ARGV[1])
if current >= limit then
    return 0
end
local allowed = math.min(count, limit - current)
local new_val = redis.call('INCRBY', KEYS[1], allowed)
if new_val == allowed then
    redis.call('EXPIRE', KEYS[1], tonumber(ARGV[3]))
end
return allowed
"""


async def check_and_consume(
    feature: CreditFeature,
    user_id: int,
    premium_since: datetime | None,
    count: int,
    user_type: str,
) -> int:
    """Atomik check-and-consume: Lua script ile tek adımda kontrol + rezervasyon.

    Döner: tüketilen ücretsiz kredi sayısı (0 ≤ returned ≤ count).
    Redis erişilemezse fail-open: count döner.
    """
    limit = free_limit(feature, user_type)
    if count <= 0 or limit <= 0:
        return 0
    key = redis_key(feature, user_id, premium_since)
    ttl = _billing_ttl(premium_since)
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        result = await redis.eval(_LUA_CHECK_AND_CONSUME, 1, key, count, limit, ttl)
        return int(result)
    except Exception as exc:
        logger.warning(
            "[CreditService] Redis erişilemedi (check_and_consume) — fail-open: %d. "
            "feature=%s user_id=%s hata=%s",
            count, feature, user_id, exc,
        )
        return count
