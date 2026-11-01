"""
Influence Scoring Servisi — SciPy sparse PageRank tabanlı sosyal etki skoru.

follows tablosundaki yönlü graf üzerinde PageRank hesaplar.
Yüksek PageRank → takip edilen ama aynı zamanda çok sayıda etkili kişi tarafından takip edilen.

Redis: influence_rank:{uid} = int (0–100, yüksek = etkili)  TTL: 7 gün
Cron: ARQ worker, her Pazar 05:30
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_REDIS_TTL = 7 * 86_400   # 7 gün
_CHUNK     = 1_000          # Redis pipeline chunk boyutu


async def compute_influence_scores() -> int:
    """
    PG'den onaylı follows kenarlarını çeker, scipy sparse CSR grafı kurar,
    güç iterasyonuyla PageRank hesaplar, skorları normalize edip Redis'e yazar.
    Döner: işlenen kullanıcı sayısı.
    """
    import asyncio

    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis
    from sqlalchemy import text as sql_text

    async with AsyncSessionLocal() as db:
        rows = await db.execute(sql_text(
            "SELECT follower_id, followed_id FROM follows WHERE status = 'accepted'"
        ))
        edges = rows.fetchall()

    if not edges:
        logger.info("[Influence] Onaylı follows yok, atlanıyor")
        return 0

    loop = asyncio.get_running_loop()
    scores: dict[int, int] = await loop.run_in_executor(
        None, _compute_pagerank_sync, edges
    )

    redis = await get_redis()
    items = list(scores.items())
    for i in range(0, len(items), _CHUNK):
        pipe = redis.pipeline()
        for uid, score in items[i : i + _CHUNK]:
            pipe.setex(f"influence_rank:{uid}", _REDIS_TTL, str(score))
        await pipe.execute()

    logger.info("[Influence] PageRank yazıldı | kullanıcı=%d", len(scores))
    return len(scores)


def _compute_pagerank_sync(edges: list) -> dict[int, int]:
    """
    CPU-yoğun scipy sparse PageRank — executor'da çalışır.

    NetworkX'in Python dict-of-dicts yapısı (10M kenarda ~10 GB RAM) yerine
    scipy CSR sparse matrix (~300 MB) kullanır.
    Kenar: follower_id → followed_id (takip eden → takip edilen).
    """
    import numpy as np
    from scipy import sparse

    src_arr = np.array([e[0] for e in edges], dtype=np.int64)
    dst_arr = np.array([e[1] for e in edges], dtype=np.int64)

    all_nodes = np.unique(np.concatenate([src_arr, dst_arr]))
    n = len(all_nodes)

    # 0-indexed mapping — searchsorted, Python dict yerine numpy kullanır
    src_idx = np.searchsorted(all_nodes, src_arr).astype(np.int32)
    dst_idx = np.searchsorted(all_nodes, dst_arr).astype(np.int32)

    # Sparse adjacency: A[follower_idx, followed_idx] = 1
    data = np.ones(len(src_idx), dtype=np.float32)
    A = sparse.csr_matrix((data, (src_idx, dst_idx)), shape=(n, n))

    # Satır-normalize → geçiş olasılığı matrisi
    row_sums = np.asarray(A.sum(axis=1)).flatten()
    row_sums[row_sums == 0] = 1.0
    D_inv = sparse.diags(1.0 / row_sums)
    # M^T sütun-stokastik: PageRank r = α * M^T * r + (1-α)/n
    M_T = (D_inv @ A).T

    # Güç iterasyonu
    alpha    = 0.85
    r        = np.full(n, 1.0 / n, dtype=np.float64)
    teleport = (1.0 - alpha) / n
    for _ in range(100):
        r_new = alpha * M_T.dot(r) + teleport
        if np.linalg.norm(r_new - r, 1) < 1e-6:
            break
        r = r_new

    # Log-normalize 0–100 (skewed dağılımı düzleştirir)
    log_vals = np.log1p(r * 1e6)
    vmin, vmax = log_vals.min(), log_vals.max()
    if vmax > vmin:
        normalized = (log_vals - vmin) / (vmax - vmin) * 100
    else:
        normalized = np.zeros_like(log_vals)

    return {int(all_nodes[i]): int(round(float(normalized[i]))) for i in range(n)}
