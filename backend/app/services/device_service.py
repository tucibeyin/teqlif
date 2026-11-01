import logging
from app.core.event_bus import event_bus
from app.core.events import TokenInvalidatedEvent

logger = logging.getLogger(__name__)


class DeviceService:
    """Kullanıcı cihazları ve Push Token yönetiminden sorumlu servis."""

    @staticmethod
    async def handle_invalid_token(event: TokenInvalidatedEvent):
        """
        EventBus'tan gelen geçersiz token olayını dinler ve sadece o cihazı siler.

        Önceki tasarım: user.fcm_token = None — tüm cihazları susturuyordu.
        Yeni tasarım: yalnızca ilgili UserDevice kaydını sil; kullanıcının
        diğer aktif cihazları bildirim almaya devam eder.
        """
        logger.info("[DeviceService] Geçersiz token temizleniyor: %s…", event.token[:12])
        try:
            from sqlalchemy import delete
            from app.database import AsyncSessionLocal
            from app.models.user_device import UserDevice

            async with AsyncSessionLocal() as db:
                result = await db.execute(
                    delete(UserDevice).where(UserDevice.fcm_token == event.token)
                )
                await db.commit()
                if result.rowcount:
                    logger.info(
                        "[DeviceService] UserDevice kaydı silindi | token=%s…", event.token[:12]
                    )
                else:
                    logger.debug(
                        "[DeviceService] Token zaten yoktu | token=%s…", event.token[:12]
                    )
        except Exception as exc:
            logger.error("[DeviceService] Token temizleme hatası: %s", exc)


# Servis başlatıldığında event_bus'a abone ol
event_bus.subscribe(TokenInvalidatedEvent, DeviceService.handle_invalid_token)
