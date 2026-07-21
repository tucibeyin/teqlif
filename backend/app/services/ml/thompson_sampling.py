"""
Thompson Sampling — Kategori Keşif/Sömürü Dengesi

Her kullanıcı × kategori çifti için Beta dağılımı parametreleri (α, β) tutar.
Feed her açıldığında her kategori için Beta'dan bir örnek çekilir;
en yüksek örnekler o sayfa için kategori öncelik sırasını belirler.

Neden:
  - Saf exploitation: kullanıcı tek kategoride sıkışır
  - Saf exploration: alakasız içerik, kullanıcı ayrılır
  - Thompson: belirsiz kategorileri zaman zaman test eder,
    güvenli kategorileri de düzenli gösterir — optimum denge

Depolama: Redis hash   user:ts:{user_id}  →  {category: "α,β"}
TTL: 30 gün (sinyalsiz kullanıcılar silinir)
Güncelleme: analytics_events işlenirken (worker flush)
Okuma: feed scoring sonrası kategori çeşitlilik adımında
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_REDIS_PREFIX = "user:ts:"
_REDIS_TTL = 30 * 86400   # 30 gün

# Beta başlangıç değerleri — merak (exploration) taraflı
_ALPHA_INIT = 1.0
_BETA_INIT = 1.0

# Ödül büyüklükleri — kuvvetli sinyal daha hızlı öğretir
_REWARDS = {
    "listing_offer_submit": 5.0,
    "listing_chat_open":    3.0,
    "listing_favorite":     3.0,
    "listing_share":        2.5,
    "listing_like":         1.5,
    "detail_dwell":         1.5,
    "listing_view":         0.5,
    "listing_impression":   0.1,
    "listing_skip":        -1.0,
    "listing_unfavorite":  -1.0,
}


# ── Redis yardımcıları ────────────────────────────────────────────────────────

async def _load_params(user_id: int) -> dict[str, tuple[float, float]]:
    """Redis'ten kullanıcının Beta parametrelerini okur."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        raw = await redis.hgetall(f"{_REDIS_PREFIX}{user_id}")
        result: dict[str, tuple[float, float]] = {}
        for cat, val in raw.items():
            try:
                a, b = val.split(",")
                result[cat] = (float(a), float(b))
            except Exception:
                continue
        return result
    except Exception as exc:
        logger.debug("[TS] Redis okuma hatası: %s", exc)
        return {}


async def _save_params(user_id: int, params: dict[str, tuple[float, float]]) -> None:
    """Beta parametrelerini Redis'e yazar."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        key = f"{_REDIS_PREFIX}{user_id}"
        mapping = {cat: f"{a:.4f},{b:.4f}" for cat, (a, b) in params.items()}
        await redis.hset(key, mapping=mapping)
        await redis.expire(key, _REDIS_TTL)
    except Exception as exc:
        logger.debug("[TS] Redis yazma hatası: %s", exc)


# ── Sinyal güncelleme ─────────────────────────────────────────────────────────

async def record_event(
    user_id: int,
    category: str,
    event_type: str,
) -> None:
    """
    Bir analitik event'e göre kategori Beta parametrelerini günceller.
    Worker flush sonrasında her listing event için çağrılır.
    """
    if not category:
        return
    delta = _REWARDS.get(event_type, 0.0)
    if delta == 0.0:
        return

    params = await _load_params(user_id)
    alpha, beta = params.get(category, (_ALPHA_INIT, _BETA_INIT))

    if delta > 0:
        alpha = min(alpha + delta, 500.0)   # α üst sınırı — overflow önleme
    else:
        beta = min(beta - delta, 500.0)     # delta negatif → β artar

    params[category] = (alpha, beta)
    await _save_params(user_id, params)


async def record_events_batch(
    events: list[tuple[int, str, str]],  # (user_id, category, event_type)
) -> None:
    """
    Toplu event güncellemesi — worker flush'ta daha verimli.
    """
    # user_id → {category → (α_delta, β_delta)}
    user_deltas: dict[int, dict[str, list[float, float]]] = {}
    for user_id, category, event_type in events:
        if not category:
            continue
        delta = _REWARDS.get(event_type, 0.0)
        if delta == 0.0:
            continue
        if user_id not in user_deltas:
            user_deltas[user_id] = {}
        if category not in user_deltas[user_id]:
            user_deltas[user_id][category] = [0.0, 0.0]
        if delta > 0:
            user_deltas[user_id][category][0] += delta
        else:
            user_deltas[user_id][category][1] += (-delta)

    for user_id, cat_deltas in user_deltas.items():
        params = await _load_params(user_id)
        for category, (alpha_inc, beta_inc) in cat_deltas.items():
            alpha, beta = params.get(category, (_ALPHA_INIT, _BETA_INIT))
            alpha = min(alpha + alpha_inc, 500.0)
            beta  = min(beta  + beta_inc,  500.0)
            params[category] = (alpha, beta)
        await _save_params(user_id, params)


# ── Kategori öncelik örneklemesi ─────────────────────────────────────────────

async def sample_category_priorities(
    user_id: int,
    categories: list[str],
    seed: Optional[int] = None,
) -> dict[str, float]:
    """
    Her kategori için Beta(α, β)'dan bir örnek çeker.
    Dönüş: {category: sample_score} — yüksek skor = bu istekte öncelikli.

    Feed greedy diversity adımında kullanılır:
    MAX_PER_CAT değişken yerine Thompson sample'a göre slot paylaştırılır.
    """
    if not categories:
        return {}

    params = await _load_params(user_id)
    rng = np.random.default_rng(seed)

    scores: dict[str, float] = {}
    for cat in categories:
        alpha, beta = params.get(cat, (_ALPHA_INIT, _BETA_INIT))
        scores[cat] = float(rng.beta(alpha, beta))

    return scores


async def get_category_confidence(
    user_id: int,
    category: str,
) -> float:
    """
    Belirli bir kategorideki beklenen başarı olasılığı (exploitation değeri).
    α / (α + β) — model ne kadar emin, o kadar yüksek.
    """
    params = await _load_params(user_id)
    alpha, beta = params.get(category, (_ALPHA_INIT, _BETA_INIT))
    return alpha / (alpha + beta)
