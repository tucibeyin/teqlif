from __future__ import annotations

from app.core.logger import get_logger

logger = get_logger(__name__)


class HandleStoreNotificationCommand:
    """POST /api/wallet/store-notifications/{platform} — hızlı 200 OK + ARQ kuyruğa at."""

    async def execute(self, platform: str, signed_payload: str) -> None:
        """signedPayload'u Redis kuyruğuna yazar; ağır JWS + DB işlemi worker'da yapılır.

        Apple 4xx alırsa 3 gün retry storm başlatır — bu endpoint asla 4xx dönmez.
        """
        try:
            from app.core.task_queue import get_pool
            pool = get_pool()
            if pool:
                await pool.enqueue_job(
                    "process_store_notification_task",
                    platform=platform,
                    signed_payload=signed_payload,
                )
                logger.info(
                    "[StoreNotif] ARQ kuyruğuna eklendi | platform=%s",
                    platform,
                )
            else:
                logger.warning("[StoreNotif] ARQ pool hazır değil, payload atıldı | platform=%s", platform)
        except Exception as exc:
            # ARQ başarısız olsa bile 200 dön — Apple retry storm önlenir.
            logger.error(
                "[StoreNotif] ARQ enqueue başarısız | platform=%s | %s",
                platform, exc,
            )
