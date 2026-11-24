"""Subscription tier sabitleri ve yardımcıları — V1.1.

TEK KAYNAK: Tüm tier mantığı buradan okunur.
Hiçbir router/use-case/service literal tier değeri veya limit içermemelidir.

Yeni tier eklemek için:
  1. TIER_* sabiti ekle
  2. PAID_TIERS'a ekle (ücretliyse)
  3. Tüm dict'lere giriş ekle
  4. Alembic migration: user_type CHECK constraint güncelle
"""
from __future__ import annotations

# ── Tier sabitleri ────────────────────────────────────────────────────────────

TIER_STANDARD = "standard"
TIER_PRO      = "pro"
TIER_PRO_PLUS = "pro_plus"
TIER_PREMIUM  = "premium"

PAID_TIERS: frozenset[str] = frozenset({TIER_PRO, TIER_PRO_PLUS, TIER_PREMIUM})

# Tier sıralaması — yükseltme/sınırlama mantığı için
TIER_RANK: dict[str, int] = {
    TIER_STANDARD: 0,
    TIER_PRO:      1,
    TIER_PRO_PLUS: 2,
    TIER_PREMIUM:  3,
}

# ── Yayın limitleri ───────────────────────────────────────────────────────────

# Aylık yayın süre limiti (saniye). None = sınırsız.
STREAM_LIMIT_SECONDS: dict[str, int | None] = {
    TIER_STANDARD: 54_000,    # 15 saat
    TIER_PRO:      108_000,   # 30 saat
    TIER_PRO_PLUS: 324_000,   # 90 saat
    TIER_PREMIUM:  None,      # sınırsız
}

# ── Gelir modeli ──────────────────────────────────────────────────────────────

# Yayın geliri komisyon oranı (0.0–1.0, host'a kalan pay).
COMMISSION_RATE: dict[str, float] = {
    TIER_STANDARD: 0.50,
    TIER_PRO:      0.75,
    TIER_PRO_PLUS: 0.90,
    TIER_PREMIUM:  1.00,
}

# ── Kalite profili ────────────────────────────────────────────────────────────

# LiveKit kalite profili adı.
QUALITY_PROFILE: dict[str, str] = {
    TIER_STANDARD: "standard",   # 540p
    TIER_PRO:      "pro",        # 720p
    TIER_PRO_PLUS: "pro",        # 720p
    TIER_PREMIUM:  "premium",    # 1080p — sadece PREMIUM
}

# ── Kredi limitleri ───────────────────────────────────────────────────────────
#
# Her özellik için tier başına aylık ücretsiz kullanım hakkı.
# Yeni özellik eklenmesi: _FEATURES içine yeni key + tüm tier'lara değer.
# Değer belirsizse 0 kullan — açık erişim, maliyet alınmaz.

CREDIT_FREE_LIMITS: dict[str, dict[str, int]] = {
    "blast": {
        TIER_STANDARD: 3,
        TIER_PRO:      10,
        TIER_PRO_PLUS: 20,
        TIER_PREMIUM:  30,
    },
    "boost": {
        TIER_STANDARD: 0,
        TIER_PRO:      3,
        TIER_PRO_PLUS: 6,
        TIER_PREMIUM:  10,
    },
    "ai_desc": {
        TIER_STANDARD: 0,
        TIER_PRO:      6,
        TIER_PRO_PLUS: 15,
        TIER_PREMIUM:  30,
    },
    "reactivation": {
        TIER_STANDARD: 0,
        TIER_PRO:      3,
        TIER_PRO_PLUS: 6,
        TIER_PREMIUM:  10,
    },
}

# Tek blast işleminde gönderilebilecek maksimum kişi sayısı (per-operation cap).
# Tanımsız özellik için None döner (sınır yok).
CREDIT_PER_OP_CAPS: dict[str, dict[str, int]] = {
    "blast": {
        TIER_STANDARD: 5,
        TIER_PRO:      15,
        TIER_PRO_PLUS: 30,
        TIER_PREMIUM:  50,
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

# ── Feed ──────────────────────────────────────────────────────────────────────

# Takip edilmeyen PREMIUM yayıncıya eklenen feed skor ağırlığı.
FEED_PREMIUM_BOOST = 0.25


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

def is_paid_tier(user_type: str) -> bool:
    """Ücretli tier (PRO, PRO+ veya PREMIUM) ise True döner."""
    return user_type in PAID_TIERS


def tier_rank(user_type: str) -> int:
    """Tier sıralaması (0=standard, 1=pro, 2=pro_plus, 3=premium)."""
    return TIER_RANK.get(user_type, 0)


def commission_rate(user_type: str) -> float:
    """Tier'a göre komisyon oranı (0.0–1.0, host'a kalan pay)."""
    return COMMISSION_RATE.get(user_type, COMMISSION_RATE[TIER_STANDARD])


def quality_profile(user_type: str) -> str:
    """Tier'a göre LiveKit kalite profil adı."""
    return QUALITY_PROFILE.get(user_type, QUALITY_PROFILE[TIER_STANDARD])


def stream_limit_seconds(user_type: str) -> int | None:
    """Tier'a göre aylık yayın sınırı (saniye). None = sınırsız."""
    return STREAM_LIMIT_SECONDS.get(user_type, STREAM_LIMIT_SECONDS[TIER_STANDARD])


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
