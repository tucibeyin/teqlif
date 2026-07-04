"""
Listing resource cleanup — listing_service ve listing_tasks tarafından kullanılır.

Silinen/pasife alınan ilanlar için:
  - Disk dosyaları (image, video, thumbnail)
  - Redis ALS item vektörü
  - İlgili bildirimler (related_id eşleşmesi)
"""
from __future__ import annotations

import json
import os

from app.core.logger import get_logger

logger = get_logger(__name__)

# Bildirim türleri: listing silinince temizlenecek olanlar
_LISTING_NOTIF_TYPES = (
    "new_listing",
    "search_alert",
    "budget_match",
    "listing_removed",
    "listing_deactivated",
)


# ── Dosya Temizliği ───────────────────────────────────────────────────────────

def _url_to_fs_path(url: str) -> str | None:
    """'/uploads/...' URL'ini sunucu dosya yoluna çevirir."""
    if not url or not url.startswith("/uploads"):
        return None
    from app.config import settings
    return settings.upload_dir + url[len("/uploads"):]


def _safe_remove(url: str, label: str, listing_id: int) -> None:
    path = _url_to_fs_path(url)
    if not path:
        return
    try:
        os.remove(path)
        logger.info("[LISTING CLEANUP] %s silindi | listing_id=%d | path=%s", label, listing_id, path)
    except FileNotFoundError:
        pass  # Zaten silinmiş
    except OSError as exc:
        logger.warning("[LISTING CLEANUP] %s silinemedi | listing_id=%d | %s", label, listing_id, exc)


def delete_listing_files(
    listing_id: int,
    image_url: str | None,
    image_urls_json: str | None,
    thumbnail_url: str | None,
    video_url: str | None,
) -> None:
    """Bir ilanın tüm medya dosyalarını diskten siler."""
    if image_url:
        _safe_remove(image_url, "image_url", listing_id)

    if image_urls_json:
        try:
            for i, url in enumerate(json.loads(image_urls_json)):
                if url:
                    _safe_remove(url, f"image_urls[{i}]", listing_id)
        except (json.JSONDecodeError, TypeError, ValueError):
            logger.warning("[LISTING CLEANUP] image_urls parse hatası | listing_id=%d", listing_id)

    if thumbnail_url:
        _safe_remove(thumbnail_url, "thumbnail_url", listing_id)

    if video_url:
        _safe_remove(video_url, "video_url", listing_id)


# ── Redis Temizliği ───────────────────────────────────────────────────────────

async def cleanup_listing_redis(listing_id: int) -> None:
    """Silinen ilanın Redis ALS item vektörünü temizler."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        deleted = await redis.delete(f"feed:als:item_vec:{listing_id}")
        if deleted:
            logger.info("[LISTING CLEANUP] Redis ALS vektörü silindi | listing_id=%d", listing_id)
    except Exception as exc:
        logger.warning("[LISTING CLEANUP] Redis ALS temizliği başarısız | listing_id=%d | %s", listing_id, exc)


async def cleanup_listings_redis_batch(listing_ids: list[int]) -> None:
    """Toplu ilan silme için Redis ALS vektörlerini temizler."""
    if not listing_ids:
        return
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        keys = [f"feed:als:item_vec:{lid}" for lid in listing_ids]
        deleted = await redis.delete(*keys)
        logger.info("[LISTING CLEANUP] %d Redis ALS vektörü silindi | batch", deleted)
    except Exception as exc:
        logger.warning("[LISTING CLEANUP] Toplu Redis temizliği başarısız | %s", exc)


# ── Bildirim Temizliği ────────────────────────────────────────────────────────

async def cleanup_listing_notifications(listing_id: int) -> None:
    """Silinen ilana ait bildirimleri siler (related_id eşleşmesi)."""
    try:
        from app.database import AsyncSessionLocal
        from app.models.notification import Notification
        from sqlalchemy import delete as sql_delete
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                sql_delete(Notification).where(
                    Notification.related_id == listing_id,
                    Notification.type.in_(_LISTING_NOTIF_TYPES),
                )
            )
            if result.rowcount:
                logger.info(
                    "[LISTING CLEANUP] %d bildirim silindi | listing_id=%d",
                    result.rowcount, listing_id,
                )
            await db.commit()
    except Exception as exc:
        logger.warning("[LISTING CLEANUP] Bildirim temizliği başarısız | listing_id=%d | %s", listing_id, exc)


async def cleanup_listings_notifications_batch(listing_ids: list[int]) -> None:
    """Toplu ilan silme için ilgili bildirimleri temizler."""
    if not listing_ids:
        return
    try:
        from app.database import AsyncSessionLocal
        from app.models.notification import Notification
        from sqlalchemy import delete as sql_delete
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                sql_delete(Notification).where(
                    Notification.related_id.in_(listing_ids),
                    Notification.type.in_(_LISTING_NOTIF_TYPES),
                )
            )
            if result.rowcount:
                logger.info(
                    "[LISTING CLEANUP] Toplu %d bildirim silindi | batch_size=%d",
                    result.rowcount, len(listing_ids),
                )
            await db.commit()
    except Exception as exc:
        logger.warning("[LISTING CLEANUP] Toplu bildirim temizliği başarısız | %s", exc)


# ── Tek Noktadan Tam Temizlik ─────────────────────────────────────────────────

async def cleanup_listing_resources(
    listing_id: int,
    image_url: str | None,
    image_urls_json: str | None,
    thumbnail_url: str | None,
    video_url: str | None,
) -> None:
    """Silinen ilanın tüm kaynaklarını temizler: dosyalar + Redis + bildirimler."""
    delete_listing_files(listing_id, image_url, image_urls_json, thumbnail_url, video_url)
    await cleanup_listing_redis(listing_id)
    await cleanup_listing_notifications(listing_id)
