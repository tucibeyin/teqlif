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

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger, capture_exception
from app.database import AsyncSessionLocal
from app.models.listing import Listing
from app.models.user import User

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
            # Pasife alınacak ilanları bul
            result = await db.execute(
                select(Listing)
                .where(
                    Listing.is_active == True,       # noqa: E712
                    Listing.is_deleted == False,     # noqa: E712
                    Listing.expires_at == None,      # noqa: E711 — highlight değil
                    Listing.created_at < cutoff,
                )
            )
            listings = result.scalars().all()

            if not listings:
                logger.info("[ListingTasks] Pasife alınacak ilan bulunamadı.")
                return

            listing_ids = [l.id for l in listings]
            user_ids = list({l.user_id for l in listings})

            # Toplu güncelleme
            await db.execute(
                update(Listing)
                .where(Listing.id.in_(listing_ids))
                .values(is_active=False, deactivated_at=now)
            )
            await db.commit()
            logger.info("[ListingTasks] %d ilan pasife alındı | ids=%s", len(listing_ids), listing_ids[:10])

            # Kullanıcı başına hangi ilanlar pasife alındı
            user_listing_map: dict[int, list[str]] = {}
            for l in listings:
                user_listing_map.setdefault(l.user_id, []).append(l.title)

        # Bildirimleri gönder
        await _notify_deactivated(user_ids, user_listing_map)

    except Exception as exc:
        logger.error("[ListingTasks] deactivate_expired_listings_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def delete_expired_inactive_listings_task(ctx: dict) -> None:
    """
    ARQ cron görevi — her gün 04:30'da çalışır.
    60+ gün önce pasife alınmış ilanları siler ve sahibine bildirim gönderir.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=_INACTIVE_DELETE_DAYS)

    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(Listing)
                .where(
                    Listing.is_active == False,       # noqa: E712
                    Listing.is_deleted == False,      # noqa: E712
                    Listing.deactivated_at != None,   # noqa: E711 — otomatik pasife alınanlar
                    Listing.deactivated_at < cutoff,
                )
            )
            listings = result.scalars().all()

            if not listings:
                logger.info("[ListingTasks] Silinecek pasif ilan bulunamadı.")
                return

            listing_ids = [l.id for l in listings]
            user_ids = list({l.user_id for l in listings})
            user_listing_map: dict[int, list[str]] = {}
            for l in listings:
                user_listing_map.setdefault(l.user_id, []).append(l.title)

            await db.execute(
                update(Listing)
                .where(Listing.id.in_(listing_ids))
                .values(is_deleted=True)
            )
            await db.commit()
            logger.info("[ListingTasks] %d pasif ilan silindi | ids=%s", len(listing_ids), listing_ids[:10])

        await _notify_deleted(user_ids, user_listing_map)

    except Exception as exc:
        logger.error("[ListingTasks] delete_expired_inactive_listings_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


# ── Bildirim yardımcıları ─────────────────────────────────────────────────────

async def _notify_deactivated(
    user_ids: list[int],
    user_listing_map: dict[int, list[str]],
) -> None:
    from app.routers.notifications import push_notification

    async def _notify(user_id: int) -> None:
        titles = user_listing_map.get(user_id, [])
        count = len(titles)
        if count == 1:
            body = f'"{titles[0]}" adlı ilanınız 30 günlük ücretsiz süreyi doldurdu ve pasife alındı.'
        else:
            body = f'{count} ilanınız 30 günlük ücretsiz süreyi doldurdu ve pasife alındı.'
        try:
            await push_notification(
                user_id=user_id,
                notif={
                    "type": "listing_deactivated",
                    "title": "İlanınız Pasife Alındı",
                    "body": body,
                },
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
    user_listing_map: dict[int, list[str]],
) -> None:
    from app.routers.notifications import push_notification

    async def _notify(user_id: int) -> None:
        titles = user_listing_map.get(user_id, [])
        count = len(titles)
        if count == 1:
            body = f'"{titles[0]}" adlı ilanınız sistemden kaldırıldı. Yeniden yayınlamak için yeni ilan oluşturabilirsiniz.'
        else:
            body = f'{count} ilanınız sistemden kaldırıldı. Yeniden yayınlamak için yeni ilan oluşturabilirsiniz.'
        try:
            await push_notification(
                user_id=user_id,
                notif={
                    "type": "listing_deleted",
                    "title": "İlanınız Silindi",
                    "body": body,
                },
                pref_key=None,
            )
        except Exception as exc:
            logger.warning("[ListingTasks] Silme bildirimi gönderilemedi | user_id=%s | %s", user_id, exc)

    for i in range(0, len(user_ids), _BATCH_SIZE):
        batch = user_ids[i: i + _BATCH_SIZE]
        await asyncio.gather(*[_notify(uid) for uid in batch])

    logger.info("[ListingTasks] %d kullanıcıya silme bildirimi gönderildi.", len(user_ids))
