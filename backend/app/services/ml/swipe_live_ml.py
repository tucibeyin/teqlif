"""
SwipeLive ML — ALS Collaborative Filtering

30 günlük swipe_live_events (dwell/skip) verisinden ALS modeli eğitir.
Kullanıcı ve stream vektörlerini Redis'te saklar; swipe_live_service bu
vektörlerden anlık benzerlik skoru hesaplar.

ARQ worker her gece 03:00'te train_swipe_live_als_task'ı çalıştırır.
Yeterli veri yoksa (<10 satır) sessizce çıkar — fallback affiniy skoruna düşer.
"""
from __future__ import annotations

import logging
import math
import numpy as np

logger = logging.getLogger(__name__)

_ALS_USER_VEC_KEY = "swipelive:als:user_vec:{uid}"
_ALS_STREAM_VEC_KEY = "swipelive:als:stream_vec:{sid}"
_ALS_TTL = 90_000  # 25 saat — günlük yeniden eğitimden önce bayatlamasın


# ── Public API ─────────────────────────────────────────────────────────────────

async def get_als_scores(user_id: int, stream_ids: list[int]) -> dict[int, float]:
    """
    ALS modelinden kullanıcı–stream benzerlik skorlarını döndürür.
    Model yoksa ya da vektör eksikse boş dict → çağıran 0.0 kullanır.
    """
    if not stream_ids:
        return {}

    from app.utils.redis_client import get_redis
    redis = await get_redis()

    user_key = _ALS_USER_VEC_KEY.format(uid=user_id)
    user_bytes = await redis.get(user_key)
    if not user_bytes:
        return {}

    user_vec = np.frombuffer(user_bytes, dtype=np.float32)
    user_norm = float(np.linalg.norm(user_vec))
    if user_norm == 0:
        return {}

    # Stream vektörlerini batch olarak çek
    stream_keys = [_ALS_STREAM_VEC_KEY.format(sid=sid) for sid in stream_ids]
    raw_vecs = await redis.mget(*stream_keys)

    scores: dict[int, float] = {}
    for sid, raw in zip(stream_ids, raw_vecs):
        if not raw:
            continue
        sv = np.frombuffer(raw, dtype=np.float32)
        sv_norm = float(np.linalg.norm(sv))
        if sv_norm == 0:
            continue
        # Cosine similarity → [0, 1] aralığına taşı
        cosine = float(np.dot(user_vec, sv) / (user_norm * sv_norm))
        scores[sid] = max(0.0, (cosine + 1.0) / 2.0)

    return scores


async def train_swipe_live_als() -> None:
    """
    30 günlük swipe_live_events verisinden ALS modeli eğit.
    Faktör vektörlerini Redis'e yaz (25 saat TTL).
    """
    try:
        import implicit
        import scipy.sparse as sp
    except ImportError:
        logger.warning("[SwipeLiveML] implicit/scipy kurulu değil, ALS atlanıyor")
        return

    from app.database_clickhouse import get_clickhouse_client
    from app.utils.redis_client import get_redis

    ch = await get_clickhouse_client()
    result = await ch.query("""
        SELECT
            user_id,
            stream_id,
            countIf(event_type = 'dwell')                           AS dwells,
            countIf(event_type = 'skip')                            AS skips,
            avgIf(dwell_ms, event_type = 'dwell')                   AS avg_dwell,
            countIf(event_type = 'stream_heart')                    AS hearts,
            countIf(event_type IN ('stream_gift', 'stream_bid'))    AS strong_eng
        FROM swipe_live_events
        WHERE timestamp  >= now() - INTERVAL 30 DAY
          AND stream_id  >  0
          AND user_id    >  0
        GROUP BY user_id, stream_id
        HAVING dwells + skips > 0
    """)

    rows = result.result_rows
    if len(rows) < 10:
        logger.info("[SwipeLiveML] Yetersiz veri (%d satır), ALS atlanıyor", len(rows))
        return

    # İndeks haritaları
    user_ids = sorted({r[0] for r in rows})
    stream_ids = sorted({r[1] for r in rows})
    u2i = {uid: i for i, uid in enumerate(user_ids)}
    s2i = {sid: i for i, sid in enumerate(stream_ids)}

    data, rows_idx, cols_idx = [], [], []
    for uid, sid, dwells, skips, avg_dwell, hearts, strong in rows:
        
        # 1. GÜVENLİK: ClickHouse'dan gelen "NaN" zehrini temizle
        if avg_dwell is None or math.isnan(float(avg_dwell)):
            safe_avg_dwell = 0.0
        else:
            safe_avg_dwell = float(avg_dwell)

        dwell_quality = min(safe_avg_dwell / 8000.0, 1.0)
        confidence = dwell_quality * dwells + 0.1 * skips + 0.3 * hearts + 1.0 * strong
        
        # 2. GÜVENLİK: Tavan ve Taban Değerleri (Clipping)
        # Çok fazla spam (10 bin kalp vs.) modelin patlamasına neden olmasın diye 500'de kesiyoruz.
        confidence = max(confidence, 0.01)
        confidence = min(confidence, 500.0)
        
        data.append(float(confidence))
        rows_idx.append(u2i[uid])
        cols_idx.append(s2i[sid])

    n_users = len(user_ids)
    n_streams = len(stream_ids)

    # user × stream CSR
    user_items = sp.csr_matrix(
        (data, (rows_idx, cols_idx)),
        shape=(n_users, n_streams),
        dtype=np.float32,
    )

    # 3. GÜVENLİK: NumPy Seviyesinde Son Filtre (Ne olur ne olmaz)
    user_items.data = np.nan_to_num(user_items.data, nan=0.01, posinf=500.0, neginf=0.01)

    factors = min(32, max(8, n_users // 3, n_streams // 3))
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
    sf = np.asarray(model.item_factors, dtype=np.float32)

    for uid, ui in u2i.items():
        pipe.setex(_ALS_USER_VEC_KEY.format(uid=uid), _ALS_TTL, uf[ui].tobytes())
    for sid, si in s2i.items():
        pipe.setex(_ALS_STREAM_VEC_KEY.format(sid=sid), _ALS_TTL, sf[si].tobytes())

    await pipe.execute()
    logger.info(
        "[SwipeLiveML] ALS eğitim tamamlandı | users=%d streams=%d factors=%d",
        n_users, n_streams, factors,
    )
