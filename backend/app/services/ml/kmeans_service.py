"""
K-Means Cold Start Servisi

Yeni kullanıcılar preference_embedding olmadan ForYou feed'e gelince
"popular ilanlar" görmek yerine onboarding'de seçtiği kategorilere
en yakın K-Means centroid'ini başlangıç embedding olarak alır.

Fikir: 50 cluster → her cluster'ın baskın kategorisi bellidir.
Kullanıcı "Elektronik + Moda" seçtiyse → bu kategorilerde yoğun
cluster centroid'lerinin ağırlıklı ortalaması → anında kişisel feed.

Model: sklearn KMeans(n_clusters=50) on listing embeddings (384-dim)
Eğitim: haftalık (Pazar 05:00)
Depolama: .model_cache/kmeans_cold_start.pkl
"""
from __future__ import annotations

import logging
import pickle
import threading
from pathlib import Path
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "kmeans_cold_start.pkl"

_model: Optional[dict] = None   # {"centroids": np.array, "cat_profiles": list[dict]}
_model_lock = threading.Lock()

N_CLUSTERS = 50
DIM = 384


# ── Model yükleme (singleton) ─────────────────────────────────────────────────

def _load_model() -> Optional[dict]:
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        if _MODEL_PATH.exists():
            try:
                with open(_MODEL_PATH, "rb") as f:
                    _model = pickle.load(f)
                logger.info(
                    "[KMeans] Model yüklendi | clusters=%d",
                    len(_model["centroids"]),
                )
            except Exception as exc:
                logger.warning("[KMeans] Model yüklenemedi: %s", exc)
                _model = None
    return _model


# ── Cold-start embedding ──────────────────────────────────────────────────────

def get_cold_start_embedding(
    category_scores: dict[str, float],
) -> Optional[list[float]]:
    """
    Kullanıcının kategori ilgi skorlarından başlangıç embedding üretir.

    category_scores: {category: score} — user_interests tablosundan
    Dönüş: 384-dim embedding listesi veya None (model yoksa)

    Mantık:
      1. Her cluster için kullanıcı kategorileriyle örtüşme skoru hesapla
      2. Top-3 cluster'ı ilgi ağırlığıyla ortala
      3. Normalize et → preference_embedding ile aynı formatta
    """
    model = _load_model()
    if model is None:
        return None

    centroids: np.ndarray = model["centroids"]      # (K, 384)
    cat_profiles: list[dict] = model["cat_profiles"] # K adet {cat: fraction}

    if not category_scores:
        return None

    # Her cluster'ın kullanıcı profiliyle örtüşme skoru
    cluster_scores: list[tuple[float, int]] = []
    for k_idx, cat_profile in enumerate(cat_profiles):
        relevance = sum(
            category_scores.get(cat, 0.0) * fraction
            for cat, fraction in cat_profile.items()
        )
        if relevance > 0.0:
            cluster_scores.append((relevance, k_idx))

    if not cluster_scores:
        return None

    cluster_scores.sort(reverse=True)
    top = cluster_scores[:3]

    total_w = sum(s for s, _ in top)
    if total_w == 0:
        return None

    embedding = np.zeros(DIM, dtype=np.float32)
    for score, k_idx in top:
        embedding += centroids[k_idx] * (score / total_w)

    norm = np.linalg.norm(embedding)
    if norm > 0:
        embedding /= norm

    return embedding.tolist()


# ── Eğitim ───────────────────────────────────────────────────────────────────

async def train_kmeans(db_session) -> int:
    """
    Aktif ilan embedding'lerinden KMeans modeli eğitir.

    Dönüş: eğitimde kullanılan ilan sayısı (0 → model güncellenmedi).
    """
    from sqlalchemy import text
    from sklearn.cluster import MiniBatchKMeans

    try:
        rows = await db_session.execute(text("""
            SELECT id, embedding, category
            FROM listings
            WHERE status = 'active'
              AND embedding IS NOT NULL
            ORDER BY id
            LIMIT 200000
        """))
        data = rows.fetchall()
    except Exception as exc:
        logger.error("[KMeans] Veri çekilemedi: %s", exc)
        return 0

    if len(data) < N_CLUSTERS * 2:
        logger.warning(
            "[KMeans] Yetersiz veri (%d ilan, min %d), model güncellenmedi.",
            len(data), N_CLUSTERS * 2,
        )
        return 0

    listing_ids = [r[0] for r in data]
    categories = [r[2] or "" for r in data]

    def _parse(raw) -> list:
        if isinstance(raw, str):
            import json
            return json.loads(raw)
        return list(raw)

    vectors = np.array([_parse(r[1]) for r in data], dtype=np.float32)

    # L2 normalize → cosine similarity = inner product
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    vectors /= norms

    kmeans = MiniBatchKMeans(
        n_clusters=N_CLUSTERS,
        init="k-means++",
        n_init=3,
        batch_size=4096,
        max_iter=100,
        random_state=42,
        verbose=0,
    )
    labels = kmeans.fit_predict(vectors)

    # Her cluster için kategori profili (fraction)
    cat_profiles: list[dict] = []
    for k_idx in range(N_CLUSTERS):
        mask = labels == k_idx
        cluster_cats = [categories[i] for i in range(len(categories)) if mask[i] and categories[i]]
        if not cluster_cats:
            cat_profiles.append({})
            continue
        from collections import Counter
        counts = Counter(cluster_cats)
        total = sum(counts.values())
        cat_profiles.append({cat: cnt / total for cat, cnt in counts.most_common(10)})

    centroids = kmeans.cluster_centers_.astype(np.float32)

    # Centroid'leri de normalize et
    cn = np.linalg.norm(centroids, axis=1, keepdims=True)
    cn[cn == 0] = 1.0
    centroids /= cn

    payload = {
        "centroids": centroids,
        "cat_profiles": cat_profiles,
        "n_listings": len(data),
    }

    _MODEL_DIR.mkdir(parents=True, exist_ok=True)
    with open(_MODEL_PATH, "wb") as f:
        pickle.dump(payload, f)

    global _model
    _model = None  # singleton sıfırla

    logger.info(
        "[KMeans] Model eğitildi | ilan=%d cluster=%d",
        len(data), N_CLUSTERS,
    )
    return len(data)
