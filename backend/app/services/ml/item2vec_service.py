"""
Item2Vec Servisi

Kullanıcıların aynı oturumda birlikte görüntülediği ilanlardan
Word2Vec (skip-gram) modeli eğitir.

Fikir: "kullanıcı X → ilan A gördü → ilan B gördü → ilan C gördü"
       bu sıra, NLP'deki kelime dizisine eşdeğer.
       Birlikte görülen ilanlar birbirine yakın vektörler alır.

Model: gensim Word2Vec, 64-dim, skip-gram, window=5
Eğitim: haftalık (Pazar 04:00)
Depolama: .model_cache/item2vec.model
Redis:    item2vec:sim:{listing_id} = JSON liste [id1, id2, ...] (top-20)
          TTL: 7 gün (haftalık eğitimle yenilenir)
"""
from __future__ import annotations

import json
import logging
import threading
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "item2vec.model"

_model = None
_model_lock = threading.Lock()

REDIS_SIM_TTL = 7 * 86400  # 7 gün
TOP_N_SIMILAR = 20
VECTOR_SIZE = 64


# ── Model yükleme ─────────────────────────────────────────────────────────────

def _load_model():
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        if _MODEL_PATH.exists():
            try:
                from gensim.models import Word2Vec
                _model = Word2Vec.load(str(_MODEL_PATH))
                logger.info("[Item2Vec] Model yüklendi: %s", _MODEL_PATH)
            except Exception as exc:
                logger.warning("[Item2Vec] Model yüklenemedi: %s", exc)
                _model = None
    return _model


def get_embedding(listing_id: int) -> Optional[list[float]]:
    """Bir ilanın Item2Vec vektörünü döndürür (model yoksa None)."""
    model = _load_model()
    if model is None:
        return None
    key = str(listing_id)
    if key not in model.wv:
        return None
    return model.wv[key].tolist()


def get_similar_ids(listing_id: int, topn: int = TOP_N_SIMILAR) -> list[int]:
    """Bir ilana en benzer ilan ID'lerini döndürür (model yoksa [])."""
    model = _load_model()
    if model is None:
        return []
    key = str(listing_id)
    if key not in model.wv:
        return []
    try:
        similar = model.wv.most_similar(key, topn=topn)
        return [int(s[0]) for s in similar]
    except Exception as exc:
        logger.warning("[Item2Vec] get_similar_ids hata: %s", exc)
        return []


# ── Redis yardımcıları ────────────────────────────────────────────────────────

async def get_similar_from_redis(listing_id: int) -> list[int]:
    """Redis'ten benzer ilan ID'lerini döndürür (önbellek)."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        raw = await redis.get(f"item2vec:sim:{listing_id}")
        if raw:
            return json.loads(raw)
    except Exception as exc:
        logger.debug("[Item2Vec] Redis okuma hatası: %s", exc)
    return []


async def _cache_similarities_to_redis(model) -> int:
    """
    Modeldeki tüm ilanlar için top-20 benzer ilanı Redis'e yazar.
    Dönüş: yazılan ilan sayısı.
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        count = 0
        vocab = list(model.wv.key_to_index.keys())
        pipe = redis.pipeline()
        for key in vocab:
            try:
                similar = model.wv.most_similar(key, topn=TOP_N_SIMILAR)
                ids = [int(s[0]) for s in similar]
                pipe.setex(f"item2vec:sim:{key}", REDIS_SIM_TTL, json.dumps(ids))
                count += 1
                if count % 500 == 0:
                    await pipe.execute()
                    pipe = redis.pipeline()
            except Exception:
                continue
        await pipe.execute()
        logger.info("[Item2Vec] Redis'e %d ilan için benzerlik yazıldı", count)
        return count
    except Exception as exc:
        logger.error("[Item2Vec] Redis cache yazılamadı: %s", exc)
        return 0


# ── Oturum verisi ─────────────────────────────────────────────────────────────

async def _fetch_sessions(db_session, days: int = 90) -> list[list[str]]:
    """
    analytics_events tablosundan kullanıcı oturumlarını çeker.

    Oturum tanımı: aynı kullanıcının 30 dakika içindeki listing görüntülemeleri.
    Her oturum bir liste: ['12', '45', '8', ...]
    """
    from sqlalchemy import text

    try:
        rows = await db_session.execute(text("""
            WITH events AS (
                SELECT
                    user_id,
                    item_id::text                                                     AS listing_id,
                    created_at,
                    created_at - LAG(created_at) OVER (
                        PARTITION BY user_id ORDER BY created_at
                    )                                                                AS gap
                FROM analytics_events
                WHERE event_type IN ('listing_view', 'detail_dwell', 'listing_impression')
                  AND item_id IS NOT NULL
                  AND user_id IS NOT NULL
                  AND created_at > NOW() - INTERVAL :days
            ),
            session_markers AS (
                SELECT
                    user_id,
                    listing_id,
                    created_at,
                    SUM(CASE WHEN gap > INTERVAL '30 minutes' OR gap IS NULL THEN 1 ELSE 0 END)
                        OVER (PARTITION BY user_id ORDER BY created_at) AS session_id
                FROM events
            )
            SELECT user_id, session_id, ARRAY_AGG(listing_id ORDER BY created_at) AS items
            FROM session_markers
            GROUP BY user_id, session_id
            HAVING COUNT(*) >= 2
               AND COUNT(*) <= 100
            ORDER BY user_id, session_id
            LIMIT 500000
        """), {"days": f"{days} days"})
        data = rows.fetchall()
    except Exception as exc:
        logger.error("[Item2Vec] Oturum verisi çekilemedi: %s", exc)
        return []

    sessions = []
    for row in data:
        items = row[2]
        if items and len(items) >= 2:
            sessions.append([str(i) for i in items])

    logger.info("[Item2Vec] %d oturum çekildi", len(sessions))
    return sessions


# ── Eğitim ───────────────────────────────────────────────────────────────────

async def train_item2vec(db_session) -> int:
    """
    Oturum verisinden Word2Vec modeli eğitir ve kaydeder.

    Dönüş: oturum sayısı (0 ise model güncellenmedi).
    """
    from gensim.models import Word2Vec

    sessions = await _fetch_sessions(db_session)

    if len(sessions) < 100:
        logger.warning("[Item2Vec] Yetersiz oturum (%d), model güncellenmedi.", len(sessions))
        return 0

    # Worker sayısını VPS'e göre sınırla — ana process'i bloke etmemek için
    model = Word2Vec(
        sentences=sessions,
        vector_size=VECTOR_SIZE,
        window=5,
        min_count=2,
        workers=3,       # 6 vCPU VPS'te 3 worker güvenli
        sg=1,            # skip-gram (seyrek veri için daha iyi)
        epochs=15,
        seed=42,
    )

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    model.save(str(_MODEL_PATH))

    # Singleton sıfırla — bir sonraki çağrı yeni modeli yükler
    global _model
    _model = None

    logger.info(
        "[Item2Vec] Model eğitildi | oturum=%d vocab=%d",
        len(sessions), len(model.wv)
    )

    # Redis benzerlik cache'ini güncelle
    await _cache_similarities_to_redis(model)

    return len(sessions)
