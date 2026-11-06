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

Depolama: Redis hash   user:ts:{user_id}
  Alan adları: "{category}:alpha"  ve  "{category}:beta"
  Güncelleme: HINCRBYFLOAT — atomik, kilit gerektirmez, O(1)
TTL: 30 gün (sinyalsiz kullanıcılar silinir)
Güncelleme: analytics_events işlenirken (worker flush)
Okuma: feed scoring sonrası kategori çeşitlilik adımında
"""
from __future__ import annotations

import logging
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_REDIS_PREFIX = "user:ts:"
_REDIS_TTL = 30 * 86400   # 30 gün

# Beta başlangıç değerleri — merak (exploration) taraflı
_ALPHA_INIT = 1.0
_BETA_INIT = 1.0
_MAX_PARAM = 500.0

# Ödül büyüklükleri — kuvvetli sinyal daha hızlı öğretir
_REWARDS = {
    "listing_offer_submit": 5.0,
    "listing_chat_open":    3.0,
    "listing_favorite":     3.0,
    "listing_share":        2.5,
    "listing_like":         1.5,
    "detail_dwell":         1.5,
    "hesitated_shelf_tap":  2.0,  # yeniden-ilgi: detail_dwell'den güçlü, favoriden zayıf
    "listing_view":         0.5,
    "listing_impression":   0.1,
    "listing_skip":        -1.0,
    "listing_unfavorite":  -1.0,
}

# Lua: HSETNX ile başlat (ilk kez) + HINCRBYFLOAT ile atomik artır + 500 cap.
# KEYS[1] = hash key
# ARGV[1] = alpha_field   ARGV[2] = beta_field
# ARGV[3] = alpha_init    ARGV[4] = beta_init
# ARGV[5] = alpha_delta   ARGV[6] = beta_delta  (her ikisi de ≥ 0)
_UPDATE_SCRIPT = """
redis.call('HSETNX', KEYS[1], ARGV[1], ARGV[3])
redis.call('HSETNX', KEYS[1], ARGV[2], ARGV[4])
if tonumber(ARGV[5]) > 0 then
    local a = tonumber(redis.call('HINCRBYFLOAT', KEYS[1], ARGV[1], ARGV[5]))
    if a > 500 then redis.call('HSET', KEYS[1], ARGV[1], '500') end
end
if tonumber(ARGV[6]) > 0 then
    local b = tonumber(redis.call('HINCRBYFLOAT', KEYS[1], ARGV[2], ARGV[6]))
    if b > 500 then redis.call('HSET', KEYS[1], ARGV[2], '500') end
end
return 1
"""


# ── Redis yardımcıları ────────────────────────────────────────────────────────

async def _load_params(user_id: int) -> dict[str, tuple[float, float]]:
    """Redis'ten kullanıcının Beta parametrelerini okur.
    Format: {cat}:alpha / {cat}:beta alanları."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        raw = await redis.hgetall(f"{_REDIS_PREFIX}{user_id}")
        result: dict[str, tuple[float, float]] = {}
        for field, val in raw.items():
            if not field.endswith(":alpha"):
                continue
            cat = field[:-6]
            beta_key = f"{cat}:beta"
            try:
                alpha = float(val)
                beta = float(raw.get(beta_key, _BETA_INIT))
                result[cat] = (alpha, beta)
            except Exception:
                continue
        return result
    except Exception as exc:
        logger.debug("[TS] Redis okuma hatası: %s", exc)
        return {}


# ── Sinyal güncelleme ─────────────────────────────────────────────────────────

async def record_event(
    user_id: int,
    category: str,
    event_type: str,
) -> None:
    """
    Bir analitik event'e göre kategori Beta parametrelerini günceller.
    HINCRBYFLOAT Lua scripti ile atomik — race condition yok.
    """
    if not category:
        return
    delta = _REWARDS.get(event_type, 0.0)
    if delta == 0.0:
        return

    alpha_delta = max(delta, 0.0)
    beta_delta  = max(-delta, 0.0)

    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        key = f"{_REDIS_PREFIX}{user_id}"
        script = redis.register_script(_UPDATE_SCRIPT)
        await script(
            keys=[key],
            args=[
                f"{category}:alpha", f"{category}:beta",
                str(_ALPHA_INIT), str(_BETA_INIT),
                str(alpha_delta), str(beta_delta),
            ],
        )
        await redis.expire(key, _REDIS_TTL)
    except Exception as exc:
        logger.debug("[TS] Redis yazma hatası: %s", exc)


async def record_events_batch(
    events: list[tuple[int, str, str]],  # (user_id, category, event_type)
) -> None:
    """
    Toplu event güncellemesi — ARQ worker flush'ta kullanılır.
    Önce user×category başına delta'lar toplanır; ardından tek pipeline ile
    HSETNX + HINCRBYFLOAT çağrıları gönderilir.
    ARQ worker tek coroutine olarak çalışır — pipeline içi sıra garantili.
    """
    # user_id → {category → [alpha_inc, beta_inc]}
    user_deltas: dict[int, dict[str, list[float]]] = {}
    for user_id, category, event_type in events:
        if not category:
            continue
        delta = _REWARDS.get(event_type, 0.0)
        if delta == 0.0:
            continue
        ud = user_deltas.setdefault(user_id, {})
        pair = ud.setdefault(category, [0.0, 0.0])
        if delta > 0:
            pair[0] += delta
        else:
            pair[1] += (-delta)

    if not user_deltas:
        return

    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        pipe = redis.pipeline(transaction=False)
        for user_id, cat_deltas in user_deltas.items():
            key = f"{_REDIS_PREFIX}{user_id}"
            for cat, (alpha_inc, beta_inc) in cat_deltas.items():
                alpha_field = f"{cat}:alpha"
                beta_field  = f"{cat}:beta"
                # Initialize only if the field is brand new
                pipe.hsetnx(key, alpha_field, str(_ALPHA_INIT))
                pipe.hsetnx(key, beta_field,  str(_BETA_INIT))
                if alpha_inc > 0:
                    pipe.hincrbyfloat(key, alpha_field, alpha_inc)
                if beta_inc > 0:
                    pipe.hincrbyfloat(key, beta_field, beta_inc)
            pipe.expire(key, _REDIS_TTL)
        await pipe.execute()
    except Exception as exc:
        logger.debug("[TS] batch Redis yazma hatası: %s", exc)


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
