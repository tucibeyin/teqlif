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
    ]

    cron_jobs = [
        # Her saat başında süresi dolan hikayeleri temizle
        cron(cleanup_expired_stories_task, minute=0),
    ]

    redis_settings = RedisSettings.from_dsn(settings.redis_url)

    max_jobs = 20
    job_timeout = 120      # saniye (cleanup disk I/O için biraz daha uzun)
    keep_result = 3600     # 1 saat — hata ayıklama için sonuçlar saklı tutulur
    max_tries = 3          # başarısız task'lar 3 kez yeniden denenir
