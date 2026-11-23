"""Subscription tier sabitleri — V1.1.

Tüm tier mantığı (commission, kalite, süre, product mapping) buradan okunur.
Hiçbir router/use-case literal 'pro_plus' / 0.90 gibi değer içermemeli.
"""
from __future__ import annotations

# ── Sabitler ─────────────────────────────────────────────────────────────────

TIER_STANDARD = "standard"
TIER_PRO      = "pro"
TIER_PRO_PLUS = "pro_plus"
TIER_PREMIUM  = "premium"

PAID_TIERS: frozenset[str] = frozenset({TIER_PRO, TIER_PRO_PLUS, TIER_PREMIUM})

# Aylık yayın süre limiti (saniye). None = sınırsız.
STREAM_LIMIT_SECONDS: dict[str, int | None] = {
    TIER_STANDARD: 54_000,    # 15 saat
    TIER_PRO:      108_000,   # 30 saat
    TIER_PRO_PLUS: 324_000,   # 90 saat
    TIER_PREMIUM:  None,      # sınırsız
}

# Yayın geliri komisyon oranı (0.0–1.0, host'a kalan pay).
COMMISSION_RATE: dict[str, float] = {
    TIER_STANDARD: 0.50,
    TIER_PRO:      0.75,
    TIER_PRO_PLUS: 0.90,
    TIER_PREMIUM:  1.00,
}

# LiveKit kalite profili.
QUALITY_PROFILE: dict[str, str] = {
    TIER_STANDARD: "standard",   # 540p
    TIER_PRO:      "pro",        # 720p
    TIER_PRO_PLUS: "pro_plus",   # 1080p
    TIER_PREMIUM:  "pro_plus",   # 1080p
}

# Product ID → user_type
PRODUCT_TIER: dict[str, str] = {
    "teqlif_pro_1m":        TIER_PRO,
    "teqlif_pro_3m":        TIER_PRO,
    "teqlif_pro_6m":        TIER_PRO,
    "teqlif_pro_12m":       TIER_PRO,
    "teqlif_pro_plus_1m":   TIER_PRO_PLUS,
    "teqlif_pro_plus_3m":   TIER_PRO_PLUS,
    "teqlif_pro_plus_6m":   TIER_PRO_PLUS,
    "teqlif_pro_plus_12m":  TIER_PRO_PLUS,
    "teqlif_premium_1m":    TIER_PREMIUM,
    "teqlif_premium_3m":    TIER_PREMIUM,
    "teqlif_premium_6m":    TIER_PREMIUM,
    "teqlif_premium_12m":   TIER_PREMIUM,
}

# Product ID → plan_type (ödeme periyodu)
PRODUCT_PLAN_TYPE: dict[str, str] = {
    "teqlif_pro_1m":        "monthly",
    "teqlif_pro_3m":        "quarterly",
    "teqlif_pro_6m":        "biannual",
    "teqlif_pro_12m":       "annual",
    "teqlif_pro_plus_1m":   "monthly",
    "teqlif_pro_plus_3m":   "quarterly",
    "teqlif_pro_plus_6m":   "biannual",
    "teqlif_pro_plus_12m":  "annual",
    "teqlif_premium_1m":    "monthly",
    "teqlif_premium_3m":    "quarterly",
    "teqlif_premium_6m":    "biannual",
    "teqlif_premium_12m":   "annual",
}

# Feed boost: takip edilmeyen PREMIUM yayıncıya eklenen skor ağırlığı.
FEED_PREMIUM_BOOST = 0.25


# ── Yardımcılar ───────────────────────────────────────────────────────────────

def is_paid_tier(user_type: str) -> bool:
    """PRO, PRO+ veya PREMIUM ise True döner."""
    return user_type in PAID_TIERS


def commission_rate(user_type: str) -> float:
    """Kullanıcı tier'ına göre komisyon oranı (host payı)."""
    return COMMISSION_RATE.get(user_type, COMMISSION_RATE[TIER_STANDARD])


def quality_profile(user_type: str) -> str:
    """LiveKit kalite profil adı."""
    return QUALITY_PROFILE.get(user_type, QUALITY_PROFILE[TIER_STANDARD])


def stream_limit_seconds(user_type: str) -> int | None:
    """Aylık yayın sınırı (saniye). None = sınırsız."""
    return STREAM_LIMIT_SECONDS.get(user_type, STREAM_LIMIT_SECONDS[TIER_STANDARD])


def tier_from_product(product_id: str) -> str | None:
    """Product ID'den tier döner; bilinmiyorsa None."""
    return PRODUCT_TIER.get(product_id)


def plan_type_from_product(product_id: str) -> str | None:
    """Product ID'den plan_type (ödeme periyodu) döner."""
    return PRODUCT_PLAN_TYPE.get(product_id)
