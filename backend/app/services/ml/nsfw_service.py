"""
NSFW Görsel Moderasyon — NudeNet ile uygunsuz içerik tespiti

NudeNet classifier ilan fotoğraflarını analiz eder.
  nsfw_score >= 0.85 → status = 'passive' (otomatik kaldır + warn log)
  nsfw_score >= 0.60 → flag (warn log, manuel inceleme)
  nsfw_score <  0.60 → temiz

İlk çalıştırmada model ~100 MB indirilir (sadece bir kez).
VPS CPU koruması: her görsel arası 0.3s + task arası 2s bekleme.
"""
from __future__ import annotations

import asyncio
import logging
import os
import tempfile
from typing import Optional

logger = logging.getLogger(__name__)

_NSFW_AUTO_DEACTIVATE = 0.85
_NSFW_FLAG_THRESHOLD = 0.60
_EXPOSED_LABELS = {
    "EXPOSED_BREAST_F",
    "EXPOSED_GENITALIA_F",
    "EXPOSED_GENITALIA_M",
    "EXPOSED_BUTTOCKS",
    "EXPOSED_BREAST_M",
}

_detector = None


def _load_detector():
    global _detector
    if _detector is not None:
        return _detector
    from nudenet import NudeDetector  # type: ignore
    _detector = NudeDetector()
    logger.info("[NSFW] NudeNet detector yüklendi")
    return _detector


async def _score_url(image_url: str) -> float:
    """Tek URL → NSFW skoru (0.0–1.0)."""
    import httpx

    if image_url.startswith("/"):
        from app.config import settings
        base = getattr(settings, "base_url", "https://teqlif.com")
        image_url = base.rstrip("/") + image_url

    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            resp = await client.get(image_url)
            resp.raise_for_status()
            img_bytes = resp.content
    except Exception as exc:
        logger.warning("[NSFW] Görsel indirilemedi %s: %s", image_url, exc)
        return 0.0

    try:
        loop = asyncio.get_running_loop()

        def _detect():
            det = _load_detector()
            with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
                f.write(img_bytes)
                tmp_path = f.name
            try:
                results = det.detect(tmp_path)
                return max(
                    (r.get("score", 0.0) for r in results if r.get("class") in _EXPOSED_LABELS),
                    default=0.0,
                )
            finally:
                os.unlink(tmp_path)

        return float(await loop.run_in_executor(None, _detect))
    except Exception as exc:
        logger.warning("[NSFW] Analiz başarısız %s: %s", image_url, exc)
        return 0.0


async def check_listing_nsfw(listing_id: int) -> None:
    """
    Bir ilanın tüm görsellerini NSFW için kontrol et (max 5 görsel).
    Sonucu DB'ye yaz, skora göre otomatik aksiyon al.
    """
    import json
    from datetime import datetime, timezone
    from sqlalchemy import select, update as sa_update
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        listing = await db.scalar(
            select(Listing).where(Listing.id == listing_id, Listing.status != "deleted")
        )
        if not listing:
            return

        urls: list[str] = []
        if listing.image_url:
            urls.append(listing.image_url)
        if listing.image_urls:
            try:
                urls.extend(json.loads(listing.image_urls))
            except Exception:
                pass

        if not urls:
            return

        max_score = 0.0
        for url in urls[:5]:
            score = await _score_url(url)
            max_score = max(max_score, score)
            await asyncio.sleep(0.3)

        updates: dict = {
            "nsfw_score": max_score,
            "nsfw_checked_at": datetime.now(timezone.utc),
        }
        if max_score >= _NSFW_AUTO_DEACTIVATE:
            updates["status"] = ListingStatus.SUSPENDED.value
            logger.warning(
                "[NSFW] İlan otomatik pasife alındı | listing_id=%d score=%.3f",
                listing_id, max_score,
            )
        elif max_score >= _NSFW_FLAG_THRESHOLD:
            logger.warning(
                "[NSFW] İlan flaglendi (manuel inceleme) | listing_id=%d score=%.3f",
                listing_id, max_score,
            )

        await db.execute(sa_update(Listing).where(Listing.id == listing_id).values(**updates))
        await db.commit()
        logger.info("[NSFW] Kontrol tamamlandı | listing_id=%d score=%.3f", listing_id, max_score)

    if max_score >= _NSFW_AUTO_DEACTIVATE:
        try:
            from app.routers.notifications import push_notification
            await push_notification(
                user_id=listing.user_id,
                notif={
                    "type": "listing_removed",
                    "i18n": {
                        "title_key": "notifListingRemoved",
                        "body_key": "notifListingRemovedBody",
                    },
                    "related_id": listing_id,
                    "listing_id": listing_id,
                },
            )
        except Exception as exc:
            logger.warning("[NSFW] Bildirim gönderilemedi | listing_id=%d | %s", listing_id, exc)


async def nsfw_backfill(batch_size: int = 20) -> int:
    """nsfw_checked_at NULL olan ilanlar için NSFW kontrolü yap. Döndürür: işlenen sayı."""
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        rows = (await db.scalars(
            select(Listing)
            .where(
                Listing.status != "deleted",
                Listing.image_url.isnot(None),
                text("nsfw_checked_at IS NULL"),
            )
            .order_by(Listing.id)
            .limit(batch_size)
        )).all()

    count = 0
    for listing in rows:
        await check_listing_nsfw(listing.id)
        count += 1
        await asyncio.sleep(2.0)

    return count
