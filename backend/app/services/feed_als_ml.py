"""
Feed ALS ML — İlan Feed'i için Collaborative Filtering

30 günlük feed_analytics (ClickHouse) verisinden ALS modeli eğitir.
Kullanıcı ve ilan vektörlerini Redis'te saklar; feed_service bu
vektörlerden anlık ALS benzerlik skoru hesaplar.

ARQ worker her gece 03:45'te train_feed_als_task'ı çalıştırır.
Yeterli veri yoksa (<50 satır) sessizce çıkar.

Confidence ağırlıkları:
  click                              → 1.0
  impression + dwell_time > 8000ms  → 0.7
  impression + dwell_time > 3000ms  → 0.4
  skip                               → 0.05  (negatif örnek, düşük ağırlık)
"""
from __future__ import annotations

import logging

import numpy as np

logger = logging.getLogger(__name__)

_USER_VEC_KEY = "feed:als:user_vec:{uid}"
_ITEM_VEC_KEY = "feed:als:item_vec:{lid}"
_ALS_TTL = 90_000   # 25 saat — günlük yeniden eğitimden önce bayatlamasın
_MIN_ROWS = 50       # Bu kadar satır yoksa eğitimi atla


# ── Public API ─────────────────────────────────────────────────────────────────

async def get_als_scores(user_id: int, listing_ids: list[int]) -> dict[int, float]:
    """
    ALS modelinden kullanıcı–ilan benzerlik skorlarını döndürür.
    Model yoksa ya da vektör eksikse boş dict → çağıran 0.0 kullanır.
    """
    if not listing_ids:
        return {}

    from app.utils.redis_client import get_redis_binary
    redis = await get_redis_binary()

    user_bytes = await redis.get(_USER_VEC_KEY.format(uid=user_id))
    if not user_bytes:
        return {}

    user_vec = np.frombuffer(user_bytes, dtype=np.float32)
    user_norm = float(np.linalg.norm(user_vec))
    if user_norm == 0:
        return {}

    item_keys = [_ITEM_VEC_KEY.format(lid=lid) for lid in listing_ids]
    raw_vecs = await redis.mget(*item_keys)

    scores: dict[int, float] = {}
    for lid, raw in zip(listing_ids, raw_vecs):
        if not raw:
            continue
        iv = np.frombuffer(raw, dtype=np.float32)
        iv_norm = float(np.linalg.norm(iv))
        if iv_norm == 0:
            continue
        cosine = float(np.dot(user_vec, iv) / (user_norm * iv_norm))
        # Cosine [-1, 1] → [0, 1]
        scores[lid] = max(0.0, (cosine + 1.0) / 2.0)

    return scores


async def train_feed_als() -> None:
    """
    30 günlük feed_analytics verisinden ALS modeli eğit.
    Faktör vektörlerini Redis'e yaz (25 saat TTL).
    """
    try:
        import implicit
        import scipy.sparse as sp
    except ImportError:
        logger.warning("[FeedALS] implicit/scipy kurulu değil, eğitim atlanıyor")
        return

    from app.database_clickhouse import get_clickhouse_client
    from app.utils.redis_client import get_redis_binary as get_redis

    try:
        ch = await get_clickhouse_client()
        if ch is None:
            logger.warning("[FeedALS] ClickHouse bağlantısı yok, eğitim atlanıyor")
            return
    except Exception as exc:
        logger.warning("[FeedALS] ClickHouse bağlanamadı: %s", exc)
        return

    # Position bias düzeltmesi: tıklamaları log2(slot+2) ile ağırlıklandır.
    # Üst slotlar doğal olarak daha fazla tıklanır; alt slottaki tıklama daha güçlü sinyal.
    result = await ch.query("""
        SELECT
            user_id,
            listing_id,
            SUM(if(event_type = 'click',
                   log2(toFloat64(slot_index) + 2.0), 0))                           AS clicks,
            countIf(event_type = 'impression' AND dwell_time_ms > 8000)             AS long_dwells,
            countIf(event_type = 'impression' AND dwell_time_ms BETWEEN 3001 AND 8000) AS short_dwells,
            countIf(event_type = 'skip')                                             AS skips
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND user_id   != ''
          AND listing_id != ''
        GROUP BY user_id, listing_id
        HAVING (clicks + long_dwells + short_dwells + skips) > 0
    """)

    rows = result.result_rows
    if len(rows) < _MIN_ROWS:
        logger.info("[FeedALS] Yetersiz veri (%d satır), eğitim atlanıyor", len(rows))
        return

    # user_id ve listing_id ClickHouse'da String; int'e çevir
    valid_rows = []
    for uid_s, lid_s, clicks, long_dwells, short_dwells, skips in rows:
        try:
            uid = int(uid_s)
            lid = int(lid_s)
        except (ValueError, TypeError):
            continue
        valid_rows.append((uid, lid, clicks, long_dwells, short_dwells, skips))

    if len(valid_rows) < _MIN_ROWS:
        logger.info("[FeedALS] Geçerli satır sayısı yetersiz (%d), atlanıyor", len(valid_rows))
        return

    user_ids = sorted({r[0] for r in valid_rows})
    listing_ids = sorted({r[1] for r in valid_rows})
    u2i = {uid: i for i, uid in enumerate(user_ids)}
    l2i = {lid: i for i, lid in enumerate(listing_ids)}

    data, row_idx, col_idx = [], [], []
    for uid, lid, clicks, long_dwells, short_dwells, skips in valid_rows:
        confidence = (
            1.0 * clicks
            + 0.7 * long_dwells
            + 0.4 * short_dwells
            + 0.05 * skips
        )
        confidence = max(confidence, 0.01)
        data.append(confidence)
        row_idx.append(u2i[uid])
        col_idx.append(l2i[lid])

    n_users = len(user_ids)
    n_items = len(listing_ids)

    user_items = sp.csr_matrix(
        (data, (row_idx, col_idx)),
        shape=(n_users, n_items),
        dtype=np.float32,
    )

    factors = min(64, max(16, n_users // 4, n_items // 4))
    model = implicit.als.AlternatingLeastSquares(
        factors=factors,
        regularization=0.1,
        iterations=20,
        use_gpu=False,
        num_threads=2,
        random_state=42,
    )
    model.fit(user_items)

    redis = await get_redis()
    pipe = redis.pipeline()

    uf = np.asarray(model.user_factors, dtype=np.float32)
    itf = np.asarray(model.item_factors, dtype=np.float32)

    for uid, ui in u2i.items():
        pipe.setex(_USER_VEC_KEY.format(uid=uid), _ALS_TTL, uf[ui].tobytes())
    for lid, li in l2i.items():
        pipe.setex(_ITEM_VEC_KEY.format(lid=lid), _ALS_TTL, itf[li].tobytes())

    await pipe.execute()
    logger.info(
        "[FeedALS] Eğitim tamamlandı | users=%d listings=%d factors=%d",
        n_users, n_items, factors,
    )
