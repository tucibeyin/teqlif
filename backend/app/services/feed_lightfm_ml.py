"""
Feed LightFM ML — Hybrid Collaborative + Content Filtering

30 günlük feed_analytics (ClickHouse) verisinden LightFM hybrid modeli eğitir.
Kullanıcı ve ilan vektörlerini Redis'te saklar; feed_service bu
vektörlerden anlık skor hesaplayabilir.

ARQ worker her gece 04:15'te train_lightfm_task'ı çalıştırır.
num_threads=2 — VPS CPU koruması.

Confidence ağırlıkları (ALS ile aynı):
  click                              → 1.0
  impression + dwell_time > 8000ms  → 0.7
  impression + dwell_time > 3000ms  → 0.4
  skip                               → 0.05
"""
from __future__ import annotations

import logging

import numpy as np

logger = logging.getLogger(__name__)

_USER_VEC_KEY = "feed:lfm:user_vec:{uid}"
_ITEM_VEC_KEY = "feed:lfm:item_vec:{lid}"
_LFM_TTL = 90_000  # 25 saat
_MIN_ROWS = 100


async def get_lightfm_scores(user_id: int, listing_ids: list[int]) -> dict[int, float]:
    """
    LightFM modelinden kullanıcı–ilan benzerlik skorları.
    Model yoksa ya da vektör eksikse boş dict döner.
    """
    if not listing_ids:
        return {}

    from app.utils.redis_client import get_redis
    redis = await get_redis()

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
        scores[lid] = max(0.0, (cosine + 1.0) / 2.0)

    return scores


async def train_lightfm() -> None:
    """
    30 günlük feed_analytics verisinden LightFM hybrid modeli eğit.
    Faktör vektörlerini Redis'e yaz (25 saat TTL).
    """
    try:
        from lightfm import LightFM  # type: ignore
        import scipy.sparse as sp
    except ImportError:
        logger.warning("[LightFM] lightfm kurulu değil: pip install lightfm")
        return

    from app.database_clickhouse import get_clickhouse_client
    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis
    from sqlalchemy import text

    try:
        ch = await get_clickhouse_client()
        if ch is None:
            logger.warning("[LightFM] ClickHouse bağlantısı yok, eğitim atlanıyor")
            return
    except Exception as exc:
        logger.warning("[LightFM] ClickHouse bağlanamadı: %s", exc)
        return

    result = await ch.query("""
        SELECT
            user_id,
            listing_id,
            countIf(event_type = 'click')                                               AS clicks,
            countIf(event_type = 'impression' AND dwell_time_ms > 8000)                AS long_dwells,
            countIf(event_type = 'impression' AND dwell_time_ms BETWEEN 3001 AND 8000) AS short_dwells,
            countIf(event_type = 'skip')                                                AS skips
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND user_id   != ''
          AND listing_id != ''
        GROUP BY user_id, listing_id
        HAVING (clicks + long_dwells + short_dwells + skips) > 0
    """)

    rows = result.result_rows
    if len(rows) < _MIN_ROWS:
        logger.info("[LightFM] Yetersiz veri (%d satır), eğitim atlanıyor", len(rows))
        return

    valid_rows = []
    for uid_s, lid_s, clicks, long_dwells, short_dwells, skips in rows:
        try:
            uid = int(uid_s)
            lid = int(lid_s)
        except (ValueError, TypeError):
            continue
        conf = (
            1.0 * clicks
            + 0.7 * long_dwells
            + 0.4 * short_dwells
            + 0.05 * skips
        )
        valid_rows.append((uid, lid, max(conf, 0.01)))

    if len(valid_rows) < _MIN_ROWS:
        logger.info("[LightFM] Geçerli satır yetersiz (%d), atlanıyor", len(valid_rows))
        return

    user_ids = sorted({r[0] for r in valid_rows})
    listing_ids = sorted({r[1] for r in valid_rows})
    u2i = {uid: i for i, uid in enumerate(user_ids)}
    l2i = {lid: i for i, lid in enumerate(listing_ids)}

    n_users = len(user_ids)
    n_items = len(listing_ids)

    data, row_idx, col_idx = [], [], []
    for uid, lid, conf in valid_rows:
        data.append(conf)
        row_idx.append(u2i[uid])
        col_idx.append(l2i[lid])

    interactions = sp.coo_matrix(
        (data, (row_idx, col_idx)),
        shape=(n_users, n_items),
        dtype=np.float32,
    )

    # İçerik özellikleri: ilan kategorilerini one-hot feature matrix olarak ekle
    item_features: sp.csr_matrix | None = None
    try:
        async with AsyncSessionLocal() as db:
            cat_result = await db.execute(
                text("""
                    SELECT id, category FROM listings
                    WHERE id = ANY(:ids) AND category IS NOT NULL
                """),
                {"ids": listing_ids},
            )
            cat_map = {row.id: row.category for row in cat_result}

        all_cats = sorted(set(cat_map.values()))
        cat2ci = {cat: i for i, cat in enumerate(all_cats)}

        if all_cats:
            feat_data, feat_rows, feat_cols = [], [], []
            for lid, li in l2i.items():
                cat = cat_map.get(lid)
                if cat and cat in cat2ci:
                    feat_rows.append(li)
                    feat_cols.append(cat2ci[cat])
                    feat_data.append(1.0)
            if feat_data:
                item_features = sp.csr_matrix(
                    (feat_data, (feat_rows, feat_cols)),
                    shape=(n_items, len(all_cats)),
                    dtype=np.float32,
                )
    except Exception as fe:
        logger.warning("[LightFM] İçerik özellikleri alınamadı, CF only: %s", fe)

    factors = min(64, max(16, n_users // 4, n_items // 4))
    model = LightFM(
        no_components=factors,
        loss="warp",
        random_state=42,
        max_sampled=10,
    )

    model.fit(
        interactions,
        item_features=item_features,
        epochs=20,
        num_threads=2,
        verbose=False,
    )

    redis = await get_redis()
    pipe = redis.pipeline()

    user_repr = model.get_user_representations(features=None)
    item_repr = model.get_item_representations(features=item_features)

    # user_repr = (biases, vectors), item_repr = (biases, vectors)
    uf = np.asarray(user_repr[1], dtype=np.float32)
    itf = np.asarray(item_repr[1], dtype=np.float32)

    for uid, ui in u2i.items():
        pipe.setex(_USER_VEC_KEY.format(uid=uid), _LFM_TTL, uf[ui].tobytes())
    for lid, li in l2i.items():
        pipe.setex(_ITEM_VEC_KEY.format(lid=lid), _LFM_TTL, itf[li].tobytes())

    await pipe.execute()
    logger.info(
        "[LightFM] Eğitim tamamlandı | users=%d listings=%d factors=%d",
        n_users, n_items, factors,
    )
