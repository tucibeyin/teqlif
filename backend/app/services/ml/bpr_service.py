"""
BPR (Bayesian Personalized Ranking) Collaborative Filtering

implicit kütüphanesiyle kullanıcı-ilan etkileşim matrisinden öğrenir.
Sıralama bazlı kayıp fonksiyonu → implicit (görüntüleme/like gibi) feedback için
ALS'tan teorik üstünlük, özellikle negatif sinyal yokken.

Akış:
  1. analytics_events → ağırlıklı user-item CSR matrisi
  2. BPR model eğitimi (factors=64, iterations=50)
  3. Tüm kullanıcılar için top-20 öneri Redis'e yazılır
  4. Feed'de BPR pool olarak kullanılır (sim_score=0.40)

Depolama:
  .model_cache/bpr_model.pkl
  Redis: bpr:rec:{user_id}  →  JSON [listing_id, ...]  TTL=7 gün
Eğitim: Cumartesi 03:00 (haftalık)
"""
from __future__ import annotations

import json
import logging
import pickle
import threading
from pathlib import Path
from typing import Optional

import numpy as np
import scipy.sparse as sp

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "bpr_model.pkl"

_model_data: Optional[dict] = None
_model_lock = threading.Lock()

_REDIS_PREFIX = "bpr:rec:"
_REDIS_TTL = 7 * 86400

_WEIGHTS: dict[str, float] = {
    "listing_offer_submit": 10.0,
    "listing_chat_open":    6.0,
    "listing_favorite":     5.0,
    "listing_share":        4.0,
    "listing_like":         3.0,
    "detail_dwell":         2.0,
    "listing_view":         1.0,
    "listing_impression":   0.3,
}


def _load_model() -> Optional[dict]:
    global _model_data
    if _model_data is not None:
        return _model_data
    with _model_lock:
        if _model_data is not None:
            return _model_data
        if _MODEL_PATH.exists():
            try:
                with open(_MODEL_PATH, "rb") as f:
                    _model_data = pickle.load(f)
                logger.info(
                    "[BPR] Model yüklendi | users=%d items=%d",
                    _model_data["n_users"], _model_data["n_items"],
                )
            except Exception as exc:
                logger.warning("[BPR] Model yüklenemedi: %s", exc)
    return _model_data


async def get_bpr_recommendations(user_id: int) -> list[int]:
    """Redis'ten kullanıcının BPR önerilerini döndürür."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        raw = await redis.get(f"{_REDIS_PREFIX}{user_id}")
        if raw:
            return json.loads(raw)
    except Exception as exc:
        logger.debug("[BPR] Redis okuma uid=%d: %s", user_id, exc)
    return []


async def _cache_all_recommendations(
    model,
    idx2user: dict[int, int],
    idx2item: dict[int, int],
    n_recs: int = 20,
) -> int:
    """Tüm kullanıcıların önerilerini toplu Redis pipeline ile yazar."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()

    user_factors = model.user_factors  # (n_users, factors)
    item_factors = model.item_factors  # (n_items, factors)

    n_users = len(idx2user)
    batch_size = 500
    cached = 0

    for start in range(0, n_users, batch_size):
        end = min(start + batch_size, n_users)
        u_indices = list(range(start, end))
        u_vecs = user_factors[u_indices]        # (batch, factors)
        scores = u_vecs @ item_factors.T        # (batch, n_items)

        pipe = redis.pipeline()
        for local_i, u_idx in enumerate(u_indices):
            user_id = idx2user[u_idx]
            n_items = scores.shape[1]
            k = min(n_recs, n_items)
            top_local = np.argpartition(scores[local_i], -k)[-k:]
            top_local = top_local[np.argsort(-scores[local_i][top_local])]
            rec_ids = [idx2item[i] for i in top_local if i in idx2item]
            pipe.set(f"{_REDIS_PREFIX}{user_id}", json.dumps(rec_ids), ex=_REDIS_TTL)
            cached += 1
        await pipe.execute()

    return cached


async def train_bpr(db_session) -> int:
    """
    Son 120 günün etkileşim verisinden BPR modeli eğitir.
    Başarılıysa önbelleği günceller ve cached kullanıcı sayısını döndürür.
    """
    from sqlalchemy import text
    from implicit.bpr import BayesianPersonalizedRanking

    try:
        rows = await db_session.execute(text("""
            SELECT user_id, item_id, event_type, COUNT(*) AS cnt
            FROM analytics_events
            WHERE event_type = ANY(ARRAY[
                'listing_offer_submit', 'listing_chat_open', 'listing_favorite',
                'listing_share', 'listing_like', 'detail_dwell',
                'listing_view', 'listing_impression'
            ])
              AND user_id IS NOT NULL
              AND item_type = 'listing'
              AND created_at >= NOW() - INTERVAL '120 days'
            GROUP BY user_id, item_id, event_type
        """))
        interactions = rows.fetchall()
    except Exception as exc:
        logger.error("[BPR] Veri çekilemedi: %s", exc)
        return 0

    if len(interactions) < 200:
        logger.warning("[BPR] Yetersiz etkileşim (%d), model güncellenmedi", len(interactions))
        return 0

    user_ids = sorted({r[0] for r in interactions})
    item_ids = sorted({r[1] for r in interactions})

    if len(user_ids) < 20 or len(item_ids) < 20:
        return 0

    user2idx = {uid: i for i, uid in enumerate(user_ids)}
    item2idx = {iid: i for i, iid in enumerate(item_ids)}
    idx2user = {i: uid for uid, i in user2idx.items()}
    idx2item = {i: iid for iid, i in item2idx.items()}

    row_idx, col_idx, weights = [], [], []
    for user_id, item_id, event_type, cnt in interactions:
        w = _WEIGHTS.get(event_type, 0.0)
        if w > 0:
            row_idx.append(user2idx[user_id])
            col_idx.append(item2idx[item_id])
            weights.append(w * float(cnt))

    if not weights:
        return 0

    n_users, n_items = len(user_ids), len(item_ids)
    user_item = sp.csr_matrix(
        (weights, (row_idx, col_idx)),
        shape=(n_users, n_items),
        dtype=np.float32,
    )
    item_user = user_item.T.tocsr()

    model = BayesianPersonalizedRanking(
        factors=64,
        learning_rate=0.01,
        regularization=0.01,
        iterations=50,
        num_threads=3,
        random_state=42,
        verify_negative_samples=True,
    )
    model.fit(item_user)

    payload = {
        "model": model,
        "user2idx": user2idx,
        "item2idx": item2idx,
        "idx2user": idx2user,
        "idx2item": idx2item,
        "n_users": n_users,
        "n_items": n_items,
    }
    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    with open(_MODEL_PATH, "wb") as f:
        pickle.dump(payload, f)

    global _model_data
    _model_data = None

    logger.info("[BPR] Model eğitildi | users=%d items=%d", n_users, n_items)

    cached = await _cache_all_recommendations(model, idx2user, idx2item, n_recs=20)
    logger.info("[BPR] %d kullanıcı için öneri önbelleklendi", cached)
    return cached
