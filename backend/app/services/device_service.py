import logging
from app.core.event_bus import event_bus
from app.core.events import TokenInvalidatedEvent

logger = logging.getLogger(__name__)

class DeviceService:
    """Kullanıcı cihazları ve Push Token yönetiminden sorumlu servis."""
    
    @staticmethod
    async def handle_invalid_token(event: TokenInvalidatedEvent):
        """EventBus'tan gelen geçersiz token olayını dinler ve DB'den temizler."""
        logger.info("[DeviceService] Geçersiz token temizleniyor: %s…", event.token[:12])
        try:
            from app.database import AsyncSessionLocal
            from app.repositories.user_repository import user_repository
            
            async with AsyncSessionLocal() as db:
                user = await user_repository.get_by_fcm_token(db, event.token)
                if user:
                    user.fcm_token = None
                    await db.commit()
            logger.info("[DeviceService] FCM token başarıyla temizlendi.")
        except Exception as exc:
            logger.error("[DeviceService] Token temizleme hatası: %s", exc)

# Servis başlatıldığında event_bus'a abone ol
event_bus.subscribe(TokenInvalidatedEvent, DeviceService.handle_invalid_token)
