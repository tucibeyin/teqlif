"""
CLIP Görsel Embedding Servisi

CLIP ViT-B/32 modeli ile ilan fotoğraflarından 512 boyutlu görsel embedding üretir.
Bu embedding listings.visual_embedding kolonuna yazılır ve pgvector ile benzer
görsel ilan arama / öneri için kullanılır.

VPS güvenliği:
  - Model belleğe lazy yüklenir (~350 MB)
  - Backfill: 30 ilan/çalıştırma, her işlem arası 2s bekleme (~0.5 core sustained)
  - ARQ cron 04:30'da tetiklenir
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)

_model = None
_processor = None


def _load_clip():
    """CLIP modelini bellekten lazy yükle. İlk çağrıda ~350 MB RAM kullanır."""
    global _model, _processor
    if _model is not None:
        return _model, _processor
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore
        # ViT-B/32 görsel kanalı — sentence-transformers üzerinden
        _model = SentenceTransformer("clip-ViT-B-32")
        _processor = None
        logger.info("[CLIP] Model yüklendi: clip-ViT-B-32")
        return _model, _processor
    except Exception as exc:
        logger.error("[CLIP] Model yüklenemedi: %s", exc)
        raise


async def generate_visual_embedding(image_url: str) -> Optional[list[float]]:
    """
    Verilen URL'den görsel embedding üretir.
    İndirme veya model hatalarında None döner.
    """
    import httpx
    from io import BytesIO
    from PIL import Image  # type: ignore

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            img_bytes = resp.content
    except Exception as exc:
        logger.warning("[CLIP] Görsel indirilemedi %s: %s", image_url, exc)
        return None

    try:
        loop = asyncio.get_running_loop()

        def _embed():
            model, _ = _load_clip()
            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            emb = model.encode(img, normalize_embeddings=True)
            return emb.tolist()

        embedding = await loop.run_in_executor(None, _embed)
        return embedding
    except Exception as exc:
        logger.warning("[CLIP] Embedding üretilemedi: %s", exc)
        return None


async def backfill_clip_embeddings(batch_size: int = 30) -> int:
    """
    visual_embedding'i NULL olan ilanlar için CLIP embedding üretir.
    Rate limit: her işlem arası 2 saniye bekleme.
    Döndürür: işlenen ilan sayısı.
    """
    from sqlalchemy import select, update as sa_update, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        rows = (await db.scalars(
            select(Listing)
            .where(
                Listing.status != "deleted",
                Listing.image_url.isnot(None),
                text("visual_embedding IS NULL"),
            )
            .order_by(Listing.id)
            .limit(batch_size)
        )).all()

        if not rows:
            return 0

        count = 0
        for listing in rows:
            url = listing.image_url
            if not url:
                continue

            # Göreceli URL'leri mutlak URL'e çevir
            if url.startswith("/"):
                from app.config import settings
                base = getattr(settings, "base_url", "https://teqlif.com")
                url = base.rstrip("/") + url

            emb = await generate_visual_embedding(url)
            if emb is None:
                await asyncio.sleep(0.5)
                continue

            await db.execute(
                sa_update(Listing)
                .where(Listing.id == listing.id)
                .values(visual_embedding=emb)
            )
            count += 1
            # Rate limit: VPS CPU koruması
            await asyncio.sleep(2.0)

        if count:
            await db.commit()
            logger.info("[CLIP] %d ilan için visual_embedding üretildi", count)

    return count
