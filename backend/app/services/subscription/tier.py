"""Subscription tier sabitleri ve yardımcıları — V2.1.

TEK KAYNAK: Tüm tier mantığı buradan okunur.
Hiçbir router/use-case/service literal tier değeri veya limit içermemelidir.

Yeni tier eklemek için:
  1. TIER_* sabiti ekle
  2. SUBSCRIPTION_TIERS'a ekle
  3. Tüm dict'lere giriş ekle
  4. Alembic migration: user_type CHECK constraint güncelle
"""
from __future__ import annotations

# ── Tier sabitleri ────────────────────────────────────────────────────────────

TIER_STANDARD = "standard"
TIER_1        = "tier1"    # PRO       (Temel üyelik)
TIER_2        = "tier2"    # PRO+      (İleri üyelik)
TIER_3        = "tier3"    # PREMIUM   (Premium üyelik)
TIER_4        = "tier4"    # PREMIUM+  (Sınırsız üyelik)

SUBSCRIPTION_TIERS: frozenset[str] = frozenset({TIER_1, TIER_2, TIER_3, TIER_4})

# Tier sıralaması — yükseltme/sınırlama mantığı için
TIER_RANK: dict[str, int] = {
    TIER_STANDARD: 0,
    TIER_1:        1,
    TIER_2:        2,
    TIER_3:        3,
    TIER_4:        4,
}

# ── Yayın limitleri ───────────────────────────────────────────────────────────

# Aylık yayın süre limiti (dakika). None = sınırsız.
STREAM_LIMIT_MINUTES: dict[str, int | None] = {
    TIER_STANDARD: 1_800,   # 30 saat
    TIER_1:        5_400,   # 90 saat
    TIER_2:        10_800,  # 180 saat
    TIER_3:        21_600,  # 360 saat
    TIER_4:        None,    # sınırsız
}

# ── Gelir modeli ──────────────────────────────────────────────────────────────

# Yayın geliri komisyon oranı (0.0–1.0, host'a kalan pay).
COMMISSION_RATE: dict[str, float] = {
    TIER_STANDARD: 0.50,
    TIER_1:        0.75,
    TIER_2:        0.90,
    TIER_3:        1.00,
    TIER_4:        1.00,
}

# ── Kalite profili ────────────────────────────────────────────────────────────

# Kalite profil sabitleri — Flutter stream_quality_profile.dart ile senkron tutulmalı.
_QUALITY_540P  = "sd"
_QUALITY_720P  = "hd"
_QUALITY_1080P = "fhd"

QUALITY_PROFILE: dict[str, str] = {
    TIER_STANDARD: _QUALITY_540P,
    TIER_1:        _QUALITY_720P,
    TIER_2:        _QUALITY_720P,
    TIER_3:        _QUALITY_1080P,
    TIER_4:        _QUALITY_1080P,
}

# ── Kredi limitleri ───────────────────────────────────────────────────────────

CREDIT_FREE_LIMITS: dict[str, dict[str, int]] = {
    "blast": {
        TIER_STANDARD: 3,
        TIER_1:        10,
        TIER_2:        20,
        TIER_3:        30,
        TIER_4:        30,
    },
    "boost": {
        TIER_STANDARD: 0,
        TIER_1:        3,
        TIER_2:        6,
        TIER_3:        10,
        TIER_4:        10,
    },
    "ai_desc": {
        TIER_STANDARD: 0,
        TIER_1:        6,
        TIER_2:        15,
        TIER_3:        30,
        TIER_4:        30,
    },
    "reactivation": {
        TIER_STANDARD: 0,
        TIER_1:        3,
        TIER_2:        6,
        TIER_3:        10,
        TIER_4:        10,
    },
}

# Tek blast işleminde gönderilebilecek maksimum kişi sayısı (per-operation cap).
CREDIT_PER_OP_CAPS: dict[str, dict[str, int]] = {
    "blast": {
        TIER_STANDARD: 5,
        TIER_1:        15,
        TIER_2:        30,
        TIER_3:        50,
        TIER_4:        50,
    },
}

# Ücretsiz hak aşıldığında ücretli kullanım başına teqlik maliyeti.
CREDIT_COSTS_TEQLIK: dict[str, int] = {
    "blast":        10,
    "boost":        50,
    "ai_desc":       5,
    "reactivation": 10,
}

# ── IAP product mapping ───────────────────────────────────────────────────────

# Product ID → user_type (Apple/Google'da kayıtlı ID'ler değişmez)
PRODUCT_TIER: dict[str, str] = {
    "teqlif_pro_1m":              TIER_1,
    "teqlif_pro_3m":              TIER_1,
    "teqlif_pro_6m":              TIER_1,
    "teqlif_pro_12m":             TIER_1,
    "teqlif_pro_plus_1m":         TIER_2,
    "teqlif_pro_plus_3m":         TIER_2,
    "teqlif_pro_plus_6m":         TIER_2,
    "teqlif_pro_plus_12m":        TIER_2,
    "teqlif_premium_1m":          TIER_3,
    "teqlif_premium_3m":          TIER_3,
    "teqlif_premium_6m":          TIER_3,
    "teqlif_premium_12m":         TIER_3,
    "teqlif_premium_plus_1m":     TIER_4,
    "teqlif_premium_plus_3m":     TIER_4,
    "teqlif_premium_plus_6m":     TIER_4,
    "teqlif_premium_plus_12m":    TIER_4,
}

# Product ID → plan_type (ödeme periyodu)
PRODUCT_PLAN_TYPE: dict[str, str] = {
    "teqlif_pro_1m":              "monthly",
    "teqlif_pro_3m":              "quarterly",
    "teqlif_pro_6m":              "biannual",
    "teqlif_pro_12m":             "annual",
    "teqlif_pro_plus_1m":         "monthly",
    "teqlif_pro_plus_3m":         "quarterly",
    "teqlif_pro_plus_6m":         "biannual",
    "teqlif_pro_plus_12m":        "annual",
    "teqlif_premium_1m":          "monthly",
    "teqlif_premium_3m":          "quarterly",
    "teqlif_premium_6m":          "biannual",
    "teqlif_premium_12m":         "annual",
    "teqlif_premium_plus_1m":     "monthly",
    "teqlif_premium_plus_3m":     "quarterly",
    "teqlif_premium_plus_6m":     "biannual",
    "teqlif_premium_plus_12m":    "annual",
}

# ── Feed ──────────────────────────────────────────────────────────────────────

# Takip edilmeyen üst tier (TIER_3+) yayıncıya eklenen feed skor ağırlığı.
FEED_TOP_TIER_BOOST = 0.25

# Feed boost uygulanan minimum tier seviyesi.
FEED_TOP_TIER_MIN_RANK = TIER_RANK[TIER_3]


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def has_subscription(user_type: str) -> bool:
    """Aktif üyeliği (tier1–tier4) olan kullanıcı ise True döner."""
    return user_type in SUBSCRIPTION_TIERS


def tier_rank(user_type: str) -> int:
    """Tier sıralaması (0=standard … 4=tier4)."""
    return TIER_RANK.get(user_type, 0)


def is_top_tier(user_type: str) -> bool:
    """FEED_TOP_TIER_MIN_RANK ve üzeri tier ise True döner (feed boost için)."""
    return TIER_RANK.get(user_type, 0) >= FEED_TOP_TIER_MIN_RANK


def commission_rate(user_type: str) -> float:
    """Tier'a göre komisyon oranı (0.0–1.0, host'a kalan pay)."""
    return COMMISSION_RATE.get(user_type, COMMISSION_RATE[TIER_STANDARD])


def quality_profile(user_type: str) -> str:
    """Tier'a göre LiveKit kalite profil adı."""
    return QUALITY_PROFILE.get(user_type, QUALITY_PROFILE[TIER_STANDARD])


def stream_limit_minutes(user_type: str) -> int | None:
    """Tier'a göre aylık yayın sınırı (dakika). None = sınırsız."""
    return STREAM_LIMIT_MINUTES.get(user_type, STREAM_LIMIT_MINUTES[TIER_STANDARD])


def credit_free_limit(feature: str, user_type: str) -> int:
    """Tier ve özelliğe göre aylık ücretsiz kredi hakkı."""
    return CREDIT_FREE_LIMITS.get(feature, {}).get(
        user_type,
        CREDIT_FREE_LIMITS.get(feature, {}).get(TIER_STANDARD, 0),
    )


def credit_per_op_cap(feature: str, user_type: str) -> int | None:
    """Tek işlemde maksimum kullanım sayısı. Tanımsız özellik için None."""
    caps = CREDIT_PER_OP_CAPS.get(feature)
    if caps is None:
        return None
    return caps.get(user_type, caps.get(TIER_STANDARD))


def credit_cost_teqlik(feature: str) -> int:
    """Ücretsiz hak aşıldığında ücretli kullanım başına teqlik maliyeti."""
    return CREDIT_COSTS_TEQLIK.get(feature, 0)


def tier_from_product(product_id: str) -> str | None:
    """Product ID'den tier döner; bilinmiyorsa None."""
    return PRODUCT_TIER.get(product_id)


def plan_type_from_product(product_id: str) -> str | None:
    """Product ID'den plan_type (ödeme periyodu) döner."""
    return PRODUCT_PLAN_TYPE.get(product_id)
