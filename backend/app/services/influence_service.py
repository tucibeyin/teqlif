"""
Influence Scoring Servisi — NetworkX PageRank tabanlı sosyal etki skoru.

follows tablosundaki yönlü graf üzerinde PageRank hesaplar.
Yüksek PageRank → takip edilen ama aynı zamanda çok sayıda etkili kişi tarafından takip edilen.

Redis: influence_rank:{uid} = int (0–100, yüksek = etkili)  TTL: 7 gün
Cron: ARQ worker, her Pazar 05:30
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_REDIS_TTL = 7 * 86_400  # 7 gün


async def compute_influence_scores() -> int:
    """
    PG'den follows tablosunu çeker, directed graph kurar, PageRank hesaplar.
    Skorları normalize edip Redis'e yazar.
    Döner: işlenen kullanıcı sayısı.
    """
    import asyncio
    import networkx as nx
    import numpy as np

    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis
    from sqlalchemy import text as sql_text

    async with AsyncSessionLocal() as db:
        rows = await db.execute(sql_text(
            "SELECT follower_id, followed_id FROM follows"
        ))
        edges = rows.fetchall()

    if not edges:
        logger.info("[Influence] follows tablosu boş, atlanıyor")
        return 0

    loop = asyncio.get_event_loop()
    scores: dict[int, int] = await loop.run_in_executor(
        None, _compute_pagerank_sync, edges
    )

    redis = await get_redis()
    pipe = redis.pipeline()
    for uid, score in scores.items():
        pipe.setex(f"influence_rank:{uid}", _REDIS_TTL, str(score))
    await pipe.execute()

    logger.info("[Influence] PageRank yazıldı | kullanıcı=%d", len(scores))
    return len(scores)


def _compute_pagerank_sync(edges: list) -> dict[int, int]:
    """CPU-yoğun PageRank hesabı — executor'da çalışır."""
    import networkx as nx
    import numpy as np

    G = nx.DiGraph()
    G.add_edges_from((int(f), int(t)) for f, t in edges)

    raw_scores = nx.pagerank(G, alpha=0.85, max_iter=100, tol=1e-6)

    if not raw_scores:
        return {}

    values = np.array(list(raw_scores.values()), dtype=np.float64)
    # Log-normalize → daha az skewed dağılım
    log_vals = np.log1p(values * 1e6)
    vmin, vmax = log_vals.min(), log_vals.max()
    if vmax == vmin:
        normalized = np.zeros_like(log_vals)
    else:
        normalized = (log_vals - vmin) / (vmax - vmin) * 100

    return {uid: int(round(score)) for uid, score in zip(raw_scores.keys(), normalized)}
