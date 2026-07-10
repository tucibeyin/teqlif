"""
Feed Hybrid BPR ML — Collaborative + Content Filtering

LightFM'in Python 3.13 uyumsuzluğu nedeniyle implicit.bpr + text embedding
blending ile aynı işlevsellik sağlanır.

Algoritma:
  1. implicit.BayesianPersonalizedRanking → collaborative faktörler (CF)
  2. DB'deki 384-dim text embedding'lerden TruncatedSVD ile 64-dim içerik vektörü
  3. Hybrid item vec = normalize(CF * 0.70 + content * 0.30)
  4. User/item vektörler Redis'e yazılır (25 saat TTL)

ARQ worker her gece 04:15'te train_lightfm_task'ı çalıştırır.
num_threads=2 — VPS CPU koruması.

Confidence ağırlıkları:
  click                              → 1.0
  bid_hesitation (user_events)       → 2.0  (fiyat yazdı ama göndermedi — güçlü sinyal)
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
_CONTENT_WEIGHT = 0.30   # içerik vektörü ağırlığı
_CF_WEIGHT = 0.70        # collaborative faktör ağırlığı


async def get_lightfm_scores(user_id: int, listing_ids: list[int]) -> dict[int, float]:
    """
    Hybrid BPR modelinden kullanıcı–ilan benzerlik skorları.
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
    30 günlük feed_analytics verisinden Hybrid BPR modeli eğit.
    implicit.BayesianPersonalizedRanking + text embedding blending.
    Faktör vektörlerini Redis'e yaz (25 saat TTL).
    """
    try:
        import implicit  # type: ignore
        import scipy.sparse as sp
        from sklearn.decomposition import TruncatedSVD  # type: ignore
    except ImportError as e:
        logger.warning("[HybridBPR] Bağımlılık eksik: %s", e)
        return

    from app.database_clickhouse import get_clickhouse_client
    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis
    from sqlalchemy import text

    # ── 1. ClickHouse interaction verisi ─────────────────────────────────────
    try:
        ch = await get_clickhouse_client()
        if ch is None:
            logger.warning("[HybridBPR] ClickHouse bağlantısı yok, eğitim atlanıyor")
            return
    except Exception as exc:
        logger.warning("[HybridBPR] ClickHouse bağlanamadı: %s", exc)
        return

    result = await ch.query("""
        SELECT
            user_id,
            listing_id,
            SUM(if(event_type = 'click',
                   log2(toFloat64(slot_index) + 2.0), 0))                               AS clicks,
            countIf(event_type = 'impression' AND dwell_time_ms > 8000)                 AS long_dwells,
            countIf(event_type = 'impression' AND dwell_time_ms BETWEEN 3001 AND 8000)  AS short_dwells,
            countIf(event_type = 'skip')                                                 AS skips
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND user_id   != ''
          AND listing_id != ''
        GROUP BY user_id, listing_id
        HAVING (clicks + long_dwells + short_dwells + skips) > 0
    """)

    rows = result.result_rows
    if len(rows) < _MIN_ROWS:
        logger.info("[HybridBPR] Yetersiz veri (%d satır), eğitim atlanıyor", len(rows))
        return

    hes_map: dict[tuple[int, int], int] = {}
    try:
        hes_result = await ch.query("""
            SELECT user_id, item_id, count() AS cnt
            FROM user_events
            WHERE event_type = 'bid_hesitation'
              AND item_type  = 'listing'
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id IS NOT NULL
            GROUP BY user_id, item_id
        """)
        for uid_s, lid_s, cnt in hes_result.result_rows:
            try:
                hes_map[(int(uid_s), int(lid_s))] = int(cnt)
            except (ValueError, TypeError):
                pass
    except Exception as hes_exc:
        logger.warning("[HybridBPR] bid_hesitation sorgusu başarısız, atlanıyor: %s", hes_exc)

    valid_rows = []
    for uid_s, lid_s, clicks, long_dwells, short_dwells, skips in rows:
        try:
            uid = int(uid_s)
            lid = int(lid_s)
        except (ValueError, TypeError):
            continue
        hesitations = hes_map.get((uid, lid), 0)
        conf = max(
            float(clicks) * 1.0
            + float(long_dwells) * 0.7
            + float(short_dwells) * 0.4
            + float(hesitations) * 2.0
            + float(skips) * 0.05,
            0.01,
        )
        valid_rows.append((uid, lid, conf))

    if len(valid_rows) < _MIN_ROWS:
        logger.info("[HybridBPR] Geçerli satır yetersiz (%d), atlanıyor", len(valid_rows))
        return

    user_ids = sorted({r[0] for r in valid_rows})
    listing_ids = sorted({r[1] for r in valid_rows})
    u2i = {uid: i for i, uid in enumerate(user_ids)}
    l2i = {lid: i for i, lid in enumerate(listing_ids)}
    n_users, n_items = len(user_ids), len(listing_ids)

    data, row_idx, col_idx = [], [], []
    for uid, lid, conf in valid_rows:
        data.append(conf)
        row_idx.append(u2i[uid])
        col_idx.append(l2i[lid])

    user_items = sp.csr_matrix(
        (data, (row_idx, col_idx)),
        shape=(n_users, n_items),
        dtype=np.float32,
    )

    # ── 2. BPR Collaborative Filtering ───────────────────────────────────────
    factors = min(64, max(16, n_users // 4, n_items // 4))
    model = implicit.bpr.BayesianPersonalizedRanking(
        factors=factors,
        iterations=50,
        learning_rate=0.05,
        regularization=0.01,
        num_threads=2,
        random_state=42,
    )
    model.fit(user_items)

    uf = np.asarray(model.user_factors, dtype=np.float32)   # (n_users, factors)
    itf = np.asarray(model.item_factors, dtype=np.float32)  # (n_items, factors)

    # ── 3. Text Embedding İçerik Vektörleri (PostgreSQL) ────────────────────
    content_matrix: np.ndarray | None = None
    try:
        async with AsyncSessionLocal() as db:
            emb_result = await db.execute(
                text("SELECT id, embedding FROM listings WHERE id = ANY(:ids) AND embedding IS NOT NULL"),
                {"ids": listing_ids},
            )
            emb_map = {row.id: row.embedding for row in emb_result}

        if emb_map:
            # Sadece embedding'i olan ilanlar için içerik matrisini doldur
            raw_content = np.zeros((n_items, 384), dtype=np.float32)
            has_content = np.zeros(n_items, dtype=bool)
            for lid, li in l2i.items():
                emb = emb_map.get(lid)
                if emb is not None:
                    raw_content[li] = np.array(emb, dtype=np.float32)
                    has_content[li] = True

            if has_content.sum() >= 10:
                # TruncatedSVD ile faktör boyutuna indir
                svd = TruncatedSVD(n_components=factors, random_state=42)
                reduced = svd.fit_transform(raw_content).astype(np.float32)
                # Normalize
                norms = np.linalg.norm(reduced, axis=1, keepdims=True)
                norms[norms == 0] = 1.0
                content_matrix = reduced / norms
                logger.info("[HybridBPR] İçerik vektörleri hazır | ilan=%d", has_content.sum())
    except Exception as fe:
        logger.warning("[HybridBPR] İçerik özellikleri alınamadı, CF-only: %s", fe)

    # ── 4. Hybrid Blending ───────────────────────────────────────────────────
    # CF vektörlerini normalize et
    cf_norms = np.linalg.norm(itf, axis=1, keepdims=True)
    cf_norms[cf_norms == 0] = 1.0
    itf_norm = itf / cf_norms

    if content_matrix is not None:
        hybrid_itf = itf_norm * _CF_WEIGHT + content_matrix * _CONTENT_WEIGHT
        # Yeniden normalize
        h_norms = np.linalg.norm(hybrid_itf, axis=1, keepdims=True)
        h_norms[h_norms == 0] = 1.0
        hybrid_itf = (hybrid_itf / h_norms).astype(np.float32)
    else:
        hybrid_itf = itf_norm

    # ── 5. Redis'e yaz ───────────────────────────────────────────────────────
    redis = await get_redis()
    pipe = redis.pipeline()

    for uid, ui in u2i.items():
        pipe.setex(_USER_VEC_KEY.format(uid=uid), _LFM_TTL, uf[ui].tobytes())
    for lid, li in l2i.items():
        pipe.setex(_ITEM_VEC_KEY.format(lid=lid), _LFM_TTL, hybrid_itf[li].tobytes())

    await pipe.execute()
    logger.info(
        "[HybridBPR] Eğitim tamamlandı | users=%d listings=%d factors=%d content=%s",
        n_users, n_items, factors,
        f"{int(content_matrix is not None and (content_matrix != 0).any())}",
    )
