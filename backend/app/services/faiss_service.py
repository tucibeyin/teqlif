"""
FAISS Vektör Arama Servisi

Aktif listing embedding'lerinden IVFFlat index üretir.
pgvector yerine FAISS ANN ile top-K ilan ID'si döner.

Strateji:
  - FAISS → hızlı candidate retrieval (top-K listing_id)
  - SQL → candidate listesi üzerinde pgvector sıralama + kişiselleştirme
  - Index dosyaya yazılır, worker lazy yükler (mtime kontrolü)

Worker: rebuild_faiss_index_task — 00:30 + 12:30 (günde 2x)
Index: /var/www/teqlif.com/faiss/listings_384.index
"""
from __future__ import annotations

import asyncio
import logging
import os
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_INDEX_PATH = "/var/www/teqlif.com/faiss/listings_384.index"
_ID_MAP_PATH = "/var/www/teqlif.com/faiss/listings_384.ids.npy"
_DIM = 384
_NLIST = 100
_NPROBE = 10

_index = None
_id_map: Optional[np.ndarray] = None
_index_mtime: float = 0.0


def _load_index_sync():
    try:
        import faiss  # type: ignore
        if not os.path.exists(_INDEX_PATH) or not os.path.exists(_ID_MAP_PATH):
            return None
        idx = faiss.read_index(_INDEX_PATH)
        idx.nprobe = _NPROBE
        ids = np.load(_ID_MAP_PATH)
        logger.info("[FAISS] Index yüklendi | ntotal=%d", idx.ntotal)
        return idx, ids
    except Exception as exc:
        logger.warning("[FAISS] Index yüklenemedi: %s", exc)
        return None


async def _ensure_index() -> None:
    """Index'i lazy yükle; disk versiyonu daha yeniyse reload et."""
    global _index, _id_map, _index_mtime
    try:
        mtime = os.path.getmtime(_INDEX_PATH) if os.path.exists(_INDEX_PATH) else 0.0
    except OSError:
        mtime = 0.0

    if _index is None or mtime > _index_mtime:
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(None, _load_index_sync)
        if result is not None:
            _index, _id_map = result
            _index_mtime = mtime


async def faiss_search(query_vec: list[float] | np.ndarray, k: int = 80) -> list[int]:
    """
    FAISS ile en yakın k ilanı döner (listing_id listesi).
    Index yoksa veya hata olursa boş liste döner (pgvector fallback için).
    """
    await _ensure_index()
    if _index is None or _id_map is None:
        return []

    try:
        import faiss  # type: ignore
        loop = asyncio.get_running_loop()

        def _search():
            vec = np.array(query_vec, dtype=np.float32).reshape(1, -1)
            faiss.normalize_L2(vec)
            _, indices = _index.search(vec, k)
            return [
                int(_id_map[i])
                for i in indices[0]
                if 0 <= i < len(_id_map)
            ]

        return await loop.run_in_executor(None, _search)
    except Exception as exc:
        logger.warning("[FAISS] Arama başarısız: %s", exc)
        return []


async def rebuild_index() -> None:
    """
    PostgreSQL'deki tüm aktif listing embedding'lerinden FAISS index yeniden kur.
    IVFFlat (cosine) — listing sayısı < nlist ise FlatIP kullanılır.
    """
    global _index, _id_map, _index_mtime

    try:
        import faiss  # type: ignore
    except ImportError:
        logger.warning("[FAISS] faiss-cpu kurulu değil, index build atlanıyor")
        return

    from sqlalchemy import text
    from app.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            text("""
                SELECT id, embedding FROM listings
                WHERE is_active = TRUE
                  AND is_deleted = FALSE
                  AND embedding IS NOT NULL
                ORDER BY id
            """)
        )
        rows = result.fetchall()

    if not rows:
        logger.info("[FAISS] Embedding'li aktif ilan yok, index build atlanıyor")
        return

    listing_ids = np.array([r[0] for r in rows], dtype=np.int64)

    # embedding DB'den string olarak gelebilir ('[-0.08, ...]' formatı)
    # pgvector native list döndürüyorsa isinstance kontrolü bunu yakalar
    def _parse_embedding(raw) -> list:
        if isinstance(raw, str):
            import json
            return json.loads(raw)
        return list(raw)

    vectors = np.array([_parse_embedding(r[1]) for r in rows], dtype=np.float32)
    faiss.normalize_L2(vectors)

    n = len(rows)
    if n < _NLIST:
        index = faiss.IndexFlatIP(_DIM)
    else:
        quantizer = faiss.IndexFlatIP(_DIM)
        index = faiss.IndexIVFFlat(quantizer, _DIM, _NLIST, faiss.METRIC_INNER_PRODUCT)
        index.train(vectors)

    index.add(vectors)

    os.makedirs(os.path.dirname(_INDEX_PATH), exist_ok=True)
    faiss.write_index(index, _INDEX_PATH)
    np.save(_ID_MAP_PATH, listing_ids)

    index.nprobe = _NPROBE
    _index = index
    _id_map = listing_ids
    _index_mtime = os.path.getmtime(_INDEX_PATH)

    logger.info("[FAISS] Index yeniden kuruldu | listings=%d", n)
