"""
Merkezi Pro/Normal kullanıcı kredi yönetimi.

Tüm özellik limitleri, maliyetler ve Redis sayaç mantığı burada toplanmıştır.
Router'lar kendi limit/Redis kodlarını tutmaz; yalnızca bu modülü kullanır.
"""
from __future__ import annotations

import calendar
from datetime import datetime, date, timezone
from typing import Literal

FeatureName = Literal["blast", "boost", "ai_price", "ai_desc", "reactivation"]

# ── Özellik Tablosu ────────────────────────────────────────────────────────────
# free_standard    : Normal kullanıcının aylık ücretsiz hakkı
# free_pro         : Pro kullanıcının aylık ücretsiz hakkı
# cost_tuci        : Ücretli kullanım başına TUCi maliyeti
# per_op_cap_*     : Tek işlemde maks kişi sayısı (yalnızca blast için)

_FEATURES: dict[str, dict] = {
    "blast": {
        "key_prefix":          "blast_credits",
        "free_standard":       3,
        "free_pro":            6,
        "cost_tuci":           10,
        "per_op_cap_standard": 5,
        "per_op_cap_pro":      10,
    },
    "boost": {
        "key_prefix":    "boost_credits",
        "free_standard": 0,
        "free_pro":      3,
        "cost_tuci":     50,
    },
    "ai_price": {
        "key_prefix":    "ai_price_credits",
        "free_standard": 0,
        "free_pro":      6,
        "cost_tuci":     5,
    },
    "ai_desc": {
        "key_prefix":    "ai_desc_credits",
        "free_standard": 0,
        "free_pro":      6,
        "cost_tuci":     5,
    },
    "reactivation": {
        "key_prefix":    "reactivation_credits",
        "free_standard": 0,
        "free_pro":      3,
        "cost_tuci":     10,
    },
}


def free_limit(feature: FeatureName, is_premium: bool) -> int:
    """Kullanıcı tipine göre aylık ücretsiz hak sayısı."""
    cfg = _FEATURES[feature]
    return cfg["free_pro"] if is_premium else cfg["free_standard"]


def cost_tuci(feature: FeatureName) -> int:
    """Ücretli kullanım başına TUCi maliyeti."""
    return _FEATURES[feature]["cost_tuci"]


def per_op_cap(feature: FeatureName, is_premium: bool) -> int | None:
    """Tek işlemde maks kullanım sayısı (yalnızca blast için tanımlı)."""
    cfg = _FEATURES[feature]
    if "per_op_cap_pro" not in cfg:
        return None
    return cfg["per_op_cap_pro"] if is_premium else cfg["per_op_cap_standard"]


# ── Fatura Dönemi Hesabı ───────────────────────────────────────────────────────

def billing_period_start(premium_since: datetime) -> date:
    """Premium abonelik dönümüne göre mevcut fatura dönemi başlangıcı."""
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


# ── Redis Sayaç Yardımcıları ──────────────────────────────────────────────────

def redis_key(feature: FeatureName, user_id: int, premium_since: datetime | None) -> str:
    prefix = _FEATURES[feature]["key_prefix"]
    if premium_since:
        period = billing_period_start(premium_since)
        return f"{prefix}:{user_id}:{period.isoformat()}"
    now = datetime.now(timezone.utc)
    return f"{prefix}:{user_id}:{now.strftime('%Y-%m')}"


async def get_used(feature: FeatureName, user_id: int, premium_since: datetime | None) -> int:
    """Bu dönemde kullanılan kredi sayısını Redis'ten okur."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        val = await redis.get(redis_key(feature, user_id, premium_since))
        return int(val) if val else 0
    except Exception:
        return 0


async def increment(
    feature: FeatureName,
    user_id: int,
    premium_since: datetime | None,
    count: int = 1,
) -> int:
    """
    Redis sayacını artırır; dönem başındaki ilk yazımda otomatik TTL ayarlar.
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
            now = datetime.now(timezone.utc)
            if premium_since:
                nxt = next_billing_date(premium_since)
                end_dt = datetime(nxt.year, nxt.month, nxt.day, tzinfo=timezone.utc)
            else:
                last_day = calendar.monthrange(now.year, now.month)[1]
                end_dt = now.replace(day=last_day, hour=23, minute=59, second=59, microsecond=0)
            ttl = max(60, int((end_dt - now).total_seconds()) + 1)
            await redis.expire(key, ttl)
        return new_val
    except Exception:
        return 0
