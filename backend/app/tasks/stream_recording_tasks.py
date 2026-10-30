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

    PRO host     → "recording_available"  bildirim + expires_at = NOW() + 24h (kullanıcı penceresi)
    Standart host → "recording_upsell"    bildirim + expires_at = NOW() + 14 days (hukuki arşiv)

    host_notified_at IS NULL → henüz bildirim gönderilmemiş.

    SRE-148: 6 saatlik pencere filtresi kaldırıldı — tüm unnotified available kayıtlar işlenir.
    Fallback: bildirim gönderilmiş ama expires_at hâlâ NULL olan kayıtlar 14 gün ile kapatılır
    (önceki run'larda notify başarılı ama UPDATE yarıda kalan edge-case'ler için).
    """
    try:
        from app.database import AsyncSessionLocal
        from app.services.notification_service import push_notification
        from sqlalchemy import text

        # ─── 1. Bildirim gönderilmemiş tüm available kayıtları seç (zaman sınırı yok)
        async with AsyncSessionLocal() as session:
            rows = (await session.execute(text("""
                SELECT sr.id, sr.stream_id, ls.host_id, u.user_type
                FROM stream_recordings sr
                JOIN live_streams ls ON ls.id = sr.stream_id
                JOIN users u         ON u.id  = ls.host_id
                WHERE sr.status = 'available'
                  AND sr.host_notified_at IS NULL
            """))).fetchall()

        notified = 0
        for rec_id, stream_id, host_id, user_type in (rows or []):
            is_pro = user_type == 'pro'
            try:
                if is_pro:
                    notif = {
                        "type": "recording_available",
                        "i18n": {
                            "title_key": "notifRecordingAvailableTitle",
                            "body_key":  "notifRecordingAvailableBody",
                        },
                        "stream_id":    str(stream_id),
                        "recording_id": str(rec_id),
                    }
                else:
                    notif = {
                        "type": "recording_upsell",
                        "i18n": {
                            "title_key": "notifRecordingUpsellTitle",
                            "body_key":  "notifRecordingUpsellBody",
                        },
                        "stream_id": str(stream_id),
                    }
                await push_notification(user_id=host_id, notif=notif)
            except Exception as exc:
                logger.warning(
                    "notify_new_recordings_task: bildirim hatası | rec_id=%d host_id=%d | %s",
                    rec_id, host_id, exc,
                )

            # PRO: 24 saat kullanıcı erişim penceresi
            # Standart: 14 gün hukuki/sistem arşiv süresi (erişim PRO_REQUIRED ile engellidir)
            expires_interval = "24 hours" if is_pro else "14 days"
            async with AsyncSessionLocal() as session:
                await session.execute(text(f"""
                    UPDATE stream_recordings
                    SET host_notified_at = NOW(),
                        expires_at       = NOW() + INTERVAL '{expires_interval}',
                        updated_at       = NOW()
                    WHERE id = :id
                """), {"id": rec_id})
                await session.commit()
            notified += 1

        # ─── 2. Fallback: önceki çalışmada notify gönderilmiş ama expires_at hâlâ NULL olanlar
        async with AsyncSessionLocal() as session:
            fallback_result = await session.execute(text("""
                UPDATE stream_recordings
                SET expires_at = NOW() + INTERVAL '14 days',
                    updated_at = NOW()
                WHERE status = 'available'
                  AND expires_at IS NULL
                  AND host_notified_at IS NOT NULL
            """))
            await session.commit()
            fallback_count = fallback_result.rowcount

        if fallback_count:
            logger.warning(
                "notify_new_recordings_task: fallback expires_at düzeltmesi | %d zombi kayıt kapatıldı",
                fallback_count,
            )

        if notified:
            logger.info("notify_new_recordings_task: %d kayıt için bildirim işlendi", notified)

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
        from app.config import settings
        from sqlalchemy import text

        is_staging = settings.debug

        if is_staging:
            query = text("""
                UPDATE stream_recordings
                SET status = 'archived', archived_at = NOW(), updated_at = NOW()
                WHERE status = 'expired'
                  AND COALESCE(transferred_at, available_at, created_at) < NOW() - INTERVAL '2 days'
            """)
        else:
            query = text("""
                UPDATE stream_recordings
                SET status = 'archived', archived_at = NOW(), updated_at = NOW()
                WHERE status = 'expired'
                  AND node2_confirmed_at IS NOT NULL
                  AND COALESCE(transferred_at, available_at, created_at) < NOW() - INTERVAL '2 days'
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
