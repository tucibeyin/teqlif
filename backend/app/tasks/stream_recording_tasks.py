"""Stream kayıt yaşam döngüsü ARQ görevleri.

expire_recordings_task      : available → expired      (expires_at geçince)
archive_recordings_task     : expired   → archived     (MinIO lifecycle süresi + güvenli bekleme)
notify_new_recordings_task  : available + host_notified_at IS NULL → host'a push bildirimi
"""
from __future__ import annotations

from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


async def expire_recordings_task(ctx: dict) -> None:
    """expires_at geçmiş 'available' kayıtları 'expired' yapar."""
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as session:
            result = await session.execute(text("""
                UPDATE stream_recordings
                SET status = 'expired', updated_at = NOW()
                WHERE status = 'available'
                  AND expires_at < NOW()
            """))
            await session.commit()
            count = result.rowcount
        if count:
            logger.info("expire_recordings_task: %d kayıt expired", count)
    except Exception as exc:
        capture_exception(exc)
        logger.error("expire_recordings_task hata: %s", exc)
        raise


async def notify_new_recordings_task(ctx: dict) -> None:
    """Yeni available olan kayıtlar için host'a bir kez push bildirimi gönderir.

    host_notified_at IS NULL → henüz bildirim gönderilmemiş.
    Bildirim gönderildikten sonra host_notified_at = NOW() set edilir.
    2 saatlik lookback: agent gecikmeli yazarsa da yakalanır.
    """
    try:
        from app.database import AsyncSessionLocal
        from app.services.notification_service import push_notification
        from sqlalchemy import text

        async with AsyncSessionLocal() as session:
            rows = (await session.execute(text("""
                SELECT sr.id, sr.stream_id, ls.host_id
                FROM stream_recordings sr
                JOIN live_streams ls ON ls.id = sr.stream_id
                WHERE sr.status = 'available'
                  AND sr.host_notified_at IS NULL
                  AND sr.available_at > NOW() - INTERVAL '6 hours'
            """))).fetchall()

        if not rows:
            return

        for rec_id, stream_id, host_id in rows:
            try:
                await push_notification(
                    user_id=host_id,
                    notif={
                        "type": "recording_available",
                        "i18n": {
                            "title_key": "notifRecordingAvailableTitle",
                            "body_key":  "notifRecordingAvailableBody",
                        },
                        "stream_id":    str(stream_id),
                        "recording_id": str(rec_id),
                    },
                )
            except Exception as exc:
                logger.warning(
                    "notify_new_recordings_task: bildirim hatası | rec_id=%d host_id=%d | %s",
                    rec_id, host_id, exc,
                )

            # Başarılı veya başarısız — tekrar denememe (idempotent)
            async with AsyncSessionLocal() as session:
                await session.execute(text("""
                    UPDATE stream_recordings
                    SET host_notified_at = NOW(), updated_at = NOW()
                    WHERE id = :id
                """), {"id": rec_id})
                await session.commit()

        logger.info("notify_new_recordings_task: %d kayıt için bildirim işlendi", len(rows))
    except Exception as exc:
        capture_exception(exc)
        logger.error("notify_new_recordings_task hata: %s", exc)
        raise


async def archive_recordings_task(ctx: dict) -> None:
    """node2 onaylı ve MinIO ILM süresi geçmiş 'expired' kayıtları 'archived' yapar.

    Prod: iki koşul birlikte sağlanmalı:
      1. node2_confirmed_at IS NOT NULL  — node2 backup script dosyayı gördüğünü onayladı
      2. transferred_at < NOW() - 2 days — ILM (2 gün expiry) büyük olasılıkla tetiklendi

    Staging (DEBUG=True): node2 backup pipeline yok, node2_confirmed_at hiç set edilmez.
    Bu ortamda koşul 2 yeterli — kayıtlar yaşam döngüsünü tamamlayabilir.
    """
    try:
        from app.database import AsyncSessionLocal
        from app.config import get_settings
        from sqlalchemy import text

        is_staging = get_settings().debug

        if is_staging:
            query = text("""
                UPDATE stream_recordings
                SET status = 'archived', archived_at = NOW(), updated_at = NOW()
                WHERE status = 'expired'
                  AND transferred_at < NOW() - INTERVAL '2 days'
            """)
        else:
            query = text("""
                UPDATE stream_recordings
                SET status = 'archived', archived_at = NOW(), updated_at = NOW()
                WHERE status = 'expired'
                  AND node2_confirmed_at IS NOT NULL
                  AND transferred_at < NOW() - INTERVAL '2 days'
            """)

        async with AsyncSessionLocal() as session:
            result = await session.execute(query)
            await session.commit()
            count = result.rowcount
        if count:
            logger.info("archive_recordings_task: %d kayıt archived (staging=%s)", count, is_staging)
    except Exception as exc:
        capture_exception(exc)
        logger.error("archive_recordings_task hata: %s", exc)
        raise
