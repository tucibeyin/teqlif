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
    subcat_scores: dict[str, float] | None = None,
) -> Optional[list[float]]:
    """
    Kullanıcının kategori + subcategory ilgi skorlarından başlangıç embedding üretir.

    category_scores: {category: score}
    subcat_scores:   {'category|subcategory': score} — opsiyonel, subcategory hassasiyeti artırır
    """
    model = _load_model()
    if model is None:
        return None

    centroids: np.ndarray = model["centroids"]        # (K, 384)
    cat_profiles: list[dict] = model["cat_profiles"]  # K adet {cat: fraction}
    subcat_profiles: list[dict] = model.get("subcat_profiles", [{} for _ in cat_profiles])

    if not category_scores:
        return None

    cluster_scores: list[tuple[float, int]] = []
    for k_idx, cat_profile in enumerate(cat_profiles):
        # Kategori bazlı örtüşme
        relevance = sum(
            category_scores.get(cat, 0.0) * fraction
            for cat, fraction in cat_profile.items()
        )
        # Subcategory bonus — varsa cluster'ı daha hassas eşleştir
        if subcat_scores and subcat_profiles:
            for key, fraction in subcat_profiles[k_idx].items():
                relevance += subcat_scores.get(key, 0.0) * fraction * 0.5
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
            SELECT id, embedding, category, subcategory
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
    subcategories = [r[3] or "" for r in data]

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

    # Her cluster için kategori + subcategory profilleri
    cat_profiles: list[dict] = []
    subcat_profiles: list[dict] = []
    from collections import Counter
    for k_idx in range(N_CLUSTERS):
        mask = labels == k_idx
        cluster_cats = [categories[i] for i in range(len(categories)) if mask[i] and categories[i]]
        cluster_subcats = [
            f"{categories[i]}|{subcategories[i]}"
            for i in range(len(categories))
            if mask[i] and categories[i] and subcategories[i]
        ]
        if cluster_cats:
            counts = Counter(cluster_cats)
            total = sum(counts.values())
            cat_profiles.append({cat: cnt / total for cat, cnt in counts.most_common(10)})
        else:
            cat_profiles.append({})

        if cluster_subcats:
            scounts = Counter(cluster_subcats)
            stotal = sum(scounts.values())
            subcat_profiles.append({key: cnt / stotal for key, cnt in scounts.most_common(20)})
        else:
            subcat_profiles.append({})

    centroids = kmeans.cluster_centers_.astype(np.float32)

    # Centroid'leri de normalize et
    cn = np.linalg.norm(centroids, axis=1, keepdims=True)
    cn[cn == 0] = 1.0
    centroids /= cn

    payload = {
        "centroids": centroids,
        "cat_profiles": cat_profiles,
        "subcat_profiles": subcat_profiles,
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
