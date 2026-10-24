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
            from app.utils.redis_client import get_redis
            redis = await get_redis()
            queue_key = f"arq:store_notif:{platform}"
            await redis.rpush(queue_key, signed_payload)
            logger.info(
                "[StoreNotif] Kuyruğa eklendi | platform=%s queue=%s",
                platform, queue_key,
            )
        except Exception as exc:
            # Redis yazma başarısız olsa bile 200 dön — Apple retry storm önlenir.
            # Worker Redis'i izlediğinden, bir sonraki başarılı push'ta payload işlenir.
            logger.error(
                "[StoreNotif] Redis kuyruğuna yazılamadı | platform=%s | %s",
                platform, exc,
            )
