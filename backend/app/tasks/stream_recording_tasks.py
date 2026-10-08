"""Stream kayıt yaşam döngüsü ARQ görevleri.

expire_recordings_task  : available → expired  (expires_at geçince)
archive_recordings_task : expired   → archived (MinIO lifecycle süresi + güvenli bekleme)
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
