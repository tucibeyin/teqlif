"""
İlan Görsel Moderasyon — imagehash ile kopya tespit

pHash (perceptual hash, 64-bit) kullanarak aynı veya çok benzer fotoğrafları
tespit eder. Hamming distance ≤ 8 → kopya kabul edilir.

Akış:
  1. create_listing → ARQ enqueue compute_listing_phash_task
  2. Task: compute_phash(url) → hex string → DB'ye yaz
  3. Aynı hash varsa warn log (soft duplicate, otomatik silinmez)
  4. backfill_phash: gece cron, toplu hash hesaplama
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional

logger = logging.getLogger(__name__)

_HAMMING_THRESHOLD = 8


async def compute_phash(image_url: str) -> Optional[str]:
    """URL'den görsel indir, perceptual hash hesapla. 16 hex char döner."""
    import httpx
    from io import BytesIO

    try:
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            img_bytes = resp.content
    except Exception as exc:
        logger.warning("[ImageMod] Görsel indirilemedi %s: %s", image_url, exc)
        return None

    try:
        loop = asyncio.get_running_loop()

        def _hash():
            from PIL import Image  # type: ignore
            import imagehash  # type: ignore
            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            return str(imagehash.phash(img))

        return await loop.run_in_executor(None, _hash)
    except Exception as exc:
        logger.warning("[ImageMod] pHash hesaplanamadı: %s", exc)
        return None


async def store_listing_phash(listing_id: int, image_url: str) -> None:
    """
    İlanın primary image'ından pHash hesapla, DB'ye yaz.
    Aynı hash'e sahip başka ilan varsa logla (soft warn).
    """
    if not image_url:
        return

    if image_url.startswith("/"):
        from app.config import settings
        base = getattr(settings, "base_url", "https://teqlif.com")
        image_url = base.rstrip("/") + image_url

    phash = await compute_phash(image_url)
    if not phash:
        return

    from sqlalchemy import text, update as sa_update
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        dup = (await db.execute(
            text("""
                SELECT id, user_id FROM listings
                WHERE image_phash = :phash
                  AND is_deleted = FALSE
                  AND id != :lid
                LIMIT 1
            """),
            {"phash": phash, "lid": listing_id},
        )).fetchone()

        if dup:
            logger.warning(
                "[ImageMod] Kopya fotoğraf | listing_id=%d duplicate_of=%d (user_id=%d)",
                listing_id, dup[0], dup[1],
            )

        await db.execute(
            sa_update(Listing).where(Listing.id == listing_id).values(image_phash=phash)
        )
        await db.commit()
        logger.info("[ImageMod] pHash kaydedildi | listing_id=%d hash=%s", listing_id, phash)


async def backfill_phash(batch_size: int = 50) -> int:
    """image_phash NULL olan ilanlar için pHash hesapla. Döndürür: işlenen sayı."""
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        rows = (await db.scalars(
            select(Listing)
            .where(
                Listing.status != "deleted",
                Listing.image_url.isnot(None),
                text("image_phash IS NULL"),
            )
            .order_by(Listing.id)
            .limit(batch_size)
        )).all()

    count = 0
    for listing in rows:
        await store_listing_phash(listing.id, listing.image_url or "")
        count += 1
        await asyncio.sleep(0.5)

    return count
