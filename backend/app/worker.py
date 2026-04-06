"""
ARQ Worker — arka plan görev tanımları.

Başlatmak için sunucuda ayrı bir process olarak çalıştır:
    arq app.worker.WorkerSettings

Her task:
- Hata durumunda logger.error + Sentry ile raporlar (error-logger standardı)
- raise ile hatayı yeniden fırlatır → ARQ görevi "failed" işaretler ve retries devreye girer
"""

from __future__ import annotations

from arq import cron
from arq.connections import RedisSettings

from app.config import settings
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


# ── Task: E-posta Gönderimi ──────────────────────────────────────────────────

async def send_verification_email_task(
    ctx: dict,
    email: str,
    full_name: str,
    code: str,
) -> None:
    """
    Doğrulama kodunu e-posta ile iletir.
    Brevo API çağrısı bu task içinde yapılır; API endpoint'i bloklamaz.
    """
    try:
        from app.utils.email import send_verification_code
        await send_verification_code(email, full_name, code)
        logger.info("[Worker] Doğrulama e-postası gönderildi: %s", email)
    except Exception as exc:
        logger.error(
            "[Worker] Doğrulama e-postası gönderilemedi [%s]: %s",
            email,
            str(exc),
            exc_info=True,
        )
        capture_exception(exc)
        raise  # ARQ görevi "failed" olarak işaretlenir


# ── Task: FCM Push Bildirimi ─────────────────────────────────────────────────

async def send_push_notification_task(
    ctx: dict,
    fcm_token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
) -> None:
    """
    FCM üzerinden push bildirimi gönderir.
    Firebase SDK çağrısı bu task içinde yapılır; API endpoint'i bloklamaz.
    """
    if not fcm_token:
        logger.warning("[Worker] send_push_notification_task: fcm_token boş, atlanıyor")
        return
    try:
        from app.services.firebase_service import send_push
        await send_push(fcm_token, title, body, badge=badge, notif_type=notif_type)
        logger.info("[Worker] Push bildirimi gönderildi | token=%s…", fcm_token[:12])
    except Exception as exc:
        logger.error(
            "[Worker] Push bildirimi gönderilemedi | token=%s… | %s",
            fcm_token[:12],
            str(exc),
            exc_info=True,
        )
        capture_exception(exc)
        raise  # ARQ görevi "failed" olarak işaretlenir


# ── Task: Süresi Dolan Hikaye Temizliği ──────────────────────────────────────

async def cleanup_expired_stories_task(ctx: dict) -> None:
    """
    Her saat başında çalışır; expires_at geçmiş hikayeleri diskten ve DB'den siler.
    story_views kayıtları CASCADE ile otomatik silinir.
    """
    try:
        from app.database import AsyncSessionLocal
        from app.services.story_service import StoryService
        async with AsyncSessionLocal() as db:
            deleted = await StoryService.cleanup_expired_stories(db)
            logger.info("[Worker] Story cleanup tamamlandı | silinen=%d", deleted)
    except Exception as exc:
        logger.error(
            "[Worker] Story cleanup başarısız | %s", str(exc), exc_info=True
        )
        capture_exception(exc)
        raise


# ── Task: Eski Bildirimleri Temizle ──────────────────────────────────────────

async def cleanup_old_notifications_task(ctx: dict) -> None:
    """
    Her gün 03:00'da çalışır; 30 günden eski bildirimleri siler.

    Kullanıcı başına birikim: ~30 bildirim/gün × 1000 kullanıcı = 900K satır/ay.
    30 günlük retention yeterli; daha eskisi operasyonel değer taşımaz.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '30 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Bildirim cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Bildirim cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Eski Analitik Eventleri Temizle ────────────────────────────────────

async def cleanup_old_analytics_task(ctx: dict) -> None:
    """
    Her Pazartesi 04:00'da çalışır; 90 günden eski analytics_events kayıtlarını siler.

    Bu tablo en hızlı büyüyen tablodur; retention olmadan GB'larca büyür.
    90 günlük veri çoğu analiz ihtiyacı için fazlasıyla yeterli.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM analytics_events WHERE created_at < NOW() - INTERVAL '90 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Analytics cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Analytics cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Eski Stream Kalplerini Temizle ─────────────────────────────────────

async def cleanup_old_stream_likes_task(ctx: dict) -> None:
    """
    Her gün 01:00'da çalışır; 7 günden eski stream_likes kayıtlarını siler.

    stream_likes unique constraint içermez — kalp animasyonu için her tıkta 1 satır.
    Canlı yayın genellikle birkaç saat sürer; 7 gün sonra bu kayıtların
    hiçbir operasyonel ya da analitik değeri kalmaz.

    Not: stream bitişinde inline temizlik de yapılır (stream_service.py).
    Bu job, o temizliği atlayan edge case'leri yakalar.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM stream_likes WHERE created_at < NOW() - INTERVAL '7 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Stream likes cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Stream likes cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Gizlenmiş Mesajları Temizle ────────────────────────────────────────

async def cleanup_hidden_messages_task(ctx: dict) -> None:
    """
    Her gün 02:30'da çalışır; is_hidden=True olan ve 60 günden eski
    direkt mesajları hard-delete eder.

    is_hidden flag'i moderasyon/shadowban için kullanılır; gizlenen mesajlar
    görüntülenmez ama tabloda kalır. 60 gün sonra itiraz penceresi kapanmış
    sayılır ve kayıtlar silinebilir.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("""
                    DELETE FROM direct_messages
                    WHERE is_hidden = TRUE
                      AND created_at < NOW() - INTERVAL '60 days'
                """)
            )
            await db.commit()
            logger.info(
                "[Worker] Gizli mesaj cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Gizli mesaj cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Worker Ayarları ──────────────────────────────────────────────────────────

class WorkerSettings:
    """
    `arq app.worker.WorkerSettings` komutuyla başlatılır.

    Redis bağlantısı projenin REDIS_URL config'inden alınır.
    max_jobs: Aynı anda çalışabilecek maksimum task sayısı.
    job_timeout: Tek bir task'ın zaman aşımı (saniye).
    keep_result: Tamamlanan task sonuçlarının Redis'te tutulma süresi.
    """

    functions = [
        send_verification_email_task,
        send_push_notification_task,
        cleanup_expired_stories_task,
        cleanup_old_notifications_task,
        cleanup_old_analytics_task,
        cleanup_old_stream_likes_task,
        cleanup_hidden_messages_task,
    ]

    cron_jobs = [
        # Her saat başında süresi dolan hikayeleri temizle
        cron(cleanup_expired_stories_task, minute=0),
        # Her gün 01:00 — eski stream kalplerini temizle
        cron(cleanup_old_stream_likes_task, hour=1, minute=0),
        # Her gün 02:30 — gizlenmiş mesajları temizle
        cron(cleanup_hidden_messages_task, hour=2, minute=30),
        # Her gün 03:00 — eski bildirimleri temizle
        cron(cleanup_old_notifications_task, hour=3, minute=0),
        # Her Pazartesi 04:00 — eski analitik verilerini temizle
        cron(cleanup_old_analytics_task, weekday=0, hour=4, minute=0),
    ]

    redis_settings = RedisSettings.from_dsn(settings.redis_url)

    max_jobs = 20
    job_timeout = 300     # 5 dakika — bulk delete sorguları için artırıldı
    keep_result = 3600    # 1 saat — hata ayıklama için sonuçlar saklı tutulur
    max_tries = 3         # başarısız task'lar 3 kez yeniden denenir
