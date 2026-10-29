"""
FAISS Vektör Arama Servisi

Aktif listing embedding'lerinden IVFFlat index üretir.
pgvector yerine FAISS ANN ile top-K ilan ID'si döner.

Strateji:
  - FAISS → hızlı candidate retrieval (top-K listing_id)
  - SQL → candidate listesi üzerinde pgvector sıralama + kişiselleştirme
  - Index dosyaya yazılır, worker lazy yükler (mtime kontrolü)

Worker: rebuild_faiss_index_task — 00:30 + 12:30 (günde 2x)
Index: settings.faiss_index_dir/listings_384.index
"""
from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_DIM = 384
_NLIST = 100
_NPROBE = 10
_MTIME_CHECK_INTERVAL = 30.0  # disk stat syscall'ı en fazla 30 sn'de bir

# Eşzamanlı yükleme koruması: ilk açılışta onlarca isteğin aynı anda
# faiss.read_index başlatmasını önler.
_load_lock = asyncio.Lock()


def _index_path() -> str:
    from app.config import settings
    return os.path.join(settings.faiss_index_dir, "listings_384.index")


def _id_map_path() -> str:
    from app.config import settings
    return os.path.join(settings.faiss_index_dir, "listings_384.ids.npy")


_index = None
_id_map: Optional[np.ndarray] = None
_index_mtime: float = 0.0
_last_mtime_check: float = 0.0


def _load_index_sync(index_path: str, id_map_path: str):
    try:
        import faiss  # type: ignore
        if not os.path.exists(index_path) or not os.path.exists(id_map_path):
            return None
        idx = faiss.read_index(index_path)
        if hasattr(idx, "nprobe"):  # IVFFlat only — IndexFlatIP has no nprobe
            idx.nprobe = _NPROBE
        ids = np.load(id_map_path)
        # Vektör sayısı ile ID haritası tutarlı değilse yüklemeyi reddet
        if idx.ntotal != len(ids):
            logger.error(
                "[FAISS] Index/ID desync: ntotal=%d ids=%d — yükleme reddedildi",
                idx.ntotal, len(ids),
            )
            return None
        logger.info("[FAISS] Index yüklendi | ntotal=%d", idx.ntotal)
        return idx, ids
    except Exception as exc:
        logger.warning("[FAISS] Index yüklenemedi: %s", exc)
        return None


async def _ensure_index() -> None:
    """Index'i lazy yükle; disk versiyonu daha yeniyse reload et.

    - mtime kontrolü en fazla 30 sn'de bir (disk stat fırtınasını önler)
    - asyncio.Lock ile eşzamanlı yükleme koruması
    """
    global _index, _id_map, _index_mtime, _last_mtime_check
    now = time.monotonic()
    if _index is not None and (now - _last_mtime_check) < _MTIME_CHECK_INTERVAL:
        return

    async with _load_lock:
        # Lock alındıktan sonra başka coroutine zaten yüklemiş olabilir
        now = time.monotonic()
        if _index is not None and (now - _last_mtime_check) < _MTIME_CHECK_INTERVAL:
            return
        _last_mtime_check = now

        ipath = _index_path()
        mpath = _id_map_path()
        try:
            mtime = os.path.getmtime(ipath) if os.path.exists(ipath) else 0.0
        except OSError:
            mtime = 0.0

        if _index is None or mtime > _index_mtime:
            loop = asyncio.get_running_loop()
            result = await loop.run_in_executor(None, _load_index_sync, ipath, mpath)
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
                WHERE status = 'active'
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

    ipath = _index_path()
    mpath = _id_map_path()

    def _build_and_save(vecs: np.ndarray, ids: np.ndarray):
        """CPU-bound index build — executor'da çalışır, event loop bloklamaz.

        Atomik yazım protokolü:
          1. ID haritasını .tmp dosyasına yaz (file handle ile — np.save uzantı eklemez)
          2. FAISS index'i .tmp dosyasına yaz
          3. ID haritasını atomik olarak yerine taşı
          4. Index'i atomik olarak yerine taşı (mtime tetikleyici — en son)
        """
        faiss.normalize_L2(vecs)
        n = len(vecs)
        if n < _NLIST * 39:
            idx = faiss.IndexFlatIP(_DIM)
        else:
            quantizer = faiss.IndexFlatIP(_DIM)
            idx = faiss.IndexIVFFlat(quantizer, _DIM, _NLIST, faiss.METRIC_INNER_PRODUCT)
            idx.train(vecs)
        idx.add(vecs)
        os.makedirs(os.path.dirname(ipath), exist_ok=True)

        tmp_idx = ipath + ".tmp"
        tmp_ids = mpath + ".tmp"

        # np.save'e string path verilirse otomatik .npy uzantısı ekler!
        # File handle kullanılırsa uzantı eklenmez.
        with open(tmp_ids, "wb") as f:
            np.save(f, ids)
        faiss.write_index(idx, tmp_idx)

        # ID haritası önce yerine gelsin, sonra mtime tetikleyici index
        os.replace(tmp_ids, mpath)
        os.replace(tmp_idx, ipath)
        return idx

    loop = asyncio.get_running_loop()
    new_index = await loop.run_in_executor(None, _build_and_save, vectors, listing_ids)

    if hasattr(new_index, "nprobe"):  # IVFFlat only — IndexFlatIP has no nprobe
        new_index.nprobe = _NPROBE
    _index = new_index
    _id_map = listing_ids
    _index_mtime = os.path.getmtime(ipath)

    logger.info("[FAISS] Index yeniden kuruldu | listings=%d", len(rows))
