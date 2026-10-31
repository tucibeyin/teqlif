"""
İlan Yaşam Döngüsü Görevleri

deactivate_expired_listings_task  — Her gün 04:00
  - 30 günden eski aktif ilanları pasife alır
  - İlan sahibine push bildirimi gönderir

delete_expired_inactive_listings_task — Her gün 04:30
  - 60+ gün önce pasife alınmış ilanları siler (is_deleted=True)
  - İlan sahibine push bildirimi gönderir
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone, timedelta

from sqlalchemy import update

from app.models.enums import ListingStatus
from app.core.logger import get_logger, capture_exception
from app.database import AsyncSessionLocal
from app.models.listing import Listing

logger = get_logger(__name__)

_FREE_LISTING_DAYS = 30    # Aktif kalma süresi (gün)
_INACTIVE_DELETE_DAYS = 60  # Pasifken silinme süresi (gün)
_BATCH_SIZE = 20


async def deactivate_expired_listings_task(ctx: dict) -> None:
    """
    ARQ cron görevi — her gün 04:00'da çalışır.
    30 günden eski aktif ilanları pasife alır ve sahibine bildirim gönderir.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=_FREE_LISTING_DAYS)
    now = datetime.now(timezone.utc)

    try:
        async with AsyncSessionLocal() as db:
            # Tek UPDATE ... RETURNING: SELECT + IN parametre patlaması olmadan
            # sıfır bellek tüketimiyle pasife al ve bildirim için gereken küçük
            # tuple'ları döndür.
            stmt = (
                update(Listing)
                .where(
                    Listing.status == ListingStatus.ACTIVE,
                    Listing.expires_at.is_(None),
                    Listing.created_at < cutoff,
                )
                .values(status=ListingStatus.PASSIVE, deactivated_at=now)
                .returning(Listing.id, Listing.user_id, Listing.title)
                .execution_options(synchronize_session=False)
            )
            result = await db.execute(stmt)
            updated_rows = result.all()

            if not updated_rows:
                logger.info("[ListingTasks] Pasife alınacak ilan bulunamadı.")
                from app.worker import _agent_ok
                await _agent_ok(ctx, "deactivate_expired_listings_task")
                return

            await db.commit()

            listing_ids: list[int] = []
            user_ids_set: set[int] = set()
            user_listing_map: dict[int, list[tuple[int, str]]] = {}
            for row_id, row_user_id, row_title in updated_rows:
                listing_ids.append(row_id)
                user_ids_set.add(row_user_id)
                user_listing_map.setdefault(row_user_id, []).append((row_id, row_title))

            logger.info("[ListingTasks] %d ilan pasife alındı | ids=%s", len(listing_ids), listing_ids[:10])

        await _notify_deactivated(list(user_ids_set), user_listing_map)
        from app.worker import _agent_ok
        await _agent_ok(ctx, "deactivate_expired_listings_task")
    except Exception as exc:
        logger.error("[ListingTasks] deactivate_expired_listings_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def delete_expired_inactive_listings_task(ctx: dict) -> None:
    """
    ARQ cron görevi — her gün 04:30'da çalışır.
    60+ gün önce pasife alınmış ilanları siler ve sahibine bildirim gönderir.
    """
    from app.utils.listing_cleanup import (
        delete_listing_files,
        cleanup_listings_redis_batch,
        cleanup_listings_notifications_batch,
    )

    cutoff = datetime.now(timezone.utc) - timedelta(days=_INACTIVE_DELETE_DAYS)

    try:
        async with AsyncSessionLocal() as db:
            # Tek UPDATE ... RETURNING: SELECT + IN parametre patlaması yok;
            # medya sütunları RETURNING ile alınır, ayrı SELECT gerekmez.
            stmt = (
                update(Listing)
                .where(
                    Listing.status == ListingStatus.PASSIVE,
                    Listing.deactivated_at.is_not(None),
                    Listing.deactivated_at < cutoff,
                )
                .values(status=ListingStatus.DELETED)
                .returning(
                    Listing.id, Listing.user_id, Listing.title,
                    Listing.image_url, Listing.image_urls,
                    Listing.thumbnail_url, Listing.video_url,
                )
                .execution_options(synchronize_session=False)
            )
            result = await db.execute(stmt)
            updated_rows = result.all()

            if not updated_rows:
                logger.info("[ListingTasks] Silinecek pasif ilan bulunamadı.")
                from app.worker import _agent_ok
                await _agent_ok(ctx, "delete_expired_inactive_listings_task")
                return

            await db.commit()

            listing_ids: list[int] = []
            user_ids_set: set[int] = set()
            user_listing_map: dict[int, list[tuple[int, str]]] = {}
            media_info: list[tuple] = []
            for row_id, row_user_id, row_title, img_url, img_urls, thumb_url, vid_url in updated_rows:
                listing_ids.append(row_id)
                user_ids_set.add(row_user_id)
                user_listing_map.setdefault(row_user_id, []).append((row_id, row_title))
                media_info.append((row_id, img_url, img_urls, thumb_url, vid_url))

            logger.info("[ListingTasks] %d pasif ilan silindi | ids=%s", len(listing_ids), listing_ids[:10])

        # Commit sonrası: dosyaları sil
        for lid, img_url, img_urls, thumb, vid in media_info:
            await delete_listing_files(lid, img_url, img_urls, thumb, vid)

        # Redis ALS vektörleri + bildirimleri toplu temizle
        await asyncio.gather(
            cleanup_listings_redis_batch(listing_ids),
            cleanup_listings_notifications_batch(listing_ids),
        )

        await _notify_deleted(list(user_ids_set), user_listing_map)
        from app.worker import _agent_ok
        await _agent_ok(ctx, "delete_expired_inactive_listings_task")
    except Exception as exc:
        logger.error("[ListingTasks] delete_expired_inactive_listings_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


# ── Bildirim yardımcıları ─────────────────────────────────────────────────────

async def _notify_deactivated(
    user_ids: list[int],
    user_listing_map: dict[int, list[tuple[int, str]]],
) -> None:
    from app.routers.notifications import push_notification

    async def _notify(user_id: int) -> None:
        listings_data = user_listing_map.get(user_id, [])
        count = len(listings_data)

        notif: dict = {"type": "listing_deactivated"}
        if count == 1:
            listing_id, title = listings_data[0]
            notif["i18n"] = {
                "title_key": "notifListingDeactivated",
                "body_key": "notifListingDeactivatedBodySingle",
                "body_params": {"title": title},
            }
            notif["related_id"] = listing_id
        else:
            notif["i18n"] = {
                "title_key": "notifListingDeactivated",
                "body_key": "notifListingDeactivatedBodyMultiple",
                "body_params": {"count": count},
            }

        try:
            await push_notification(
                user_id=user_id,
                notif=notif,
                pref_key=None,
            )
        except Exception as exc:
            logger.warning("[ListingTasks] Pasif bildirim gönderilemedi | user_id=%s | %s", user_id, exc)

    for i in range(0, len(user_ids), _BATCH_SIZE):
        batch = user_ids[i: i + _BATCH_SIZE]
        await asyncio.gather(*[_notify(uid) for uid in batch])

    logger.info("[ListingTasks] %d kullanıcıya pasif bildirimi gönderildi.", len(user_ids))


async def _notify_deleted(
    user_ids: list[int],
    user_listing_map: dict[int, list[tuple[int, str]]],
) -> None:
    from app.routers.notifications import push_notification

    async def _notify(user_id: int) -> None:
        listings_data = user_listing_map.get(user_id, [])
        count = len(listings_data)
        if count == 1:
            _, title = listings_data[0]
            _i18n = {
                "title_key": "notifListingDeleted",
                "body_key": "notifListingDeletedBodySingle",
                "body_params": {"title": title},
            }
        else:
            _i18n = {
                "title_key": "notifListingDeleted",
                "body_key": "notifListingDeletedBodyMultiple",
                "body_params": {"count": count},
            }
        try:
            await push_notification(
                user_id=user_id,
                notif={
                    "type": "listing_deleted",
                    "i18n": _i18n,
                },
                pref_key=None,
            )
        except Exception as exc:
            logger.warning("[ListingTasks] Silme bildirimi gönderilemedi | user_id=%s | %s", user_id, exc)

    for i in range(0, len(user_ids), _BATCH_SIZE):
        batch = user_ids[i: i + _BATCH_SIZE]
        await asyncio.gather(*[_notify(uid) for uid in batch])

    logger.info("[ListingTasks] %d kullanıcıya silme bildirimi gönderildi.", len(user_ids))
