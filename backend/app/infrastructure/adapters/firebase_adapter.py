import asyncio
from typing import Dict, Any

from app.core.ports.push_notification_port import PushNotificationPort
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import ServiceException
from app.core.circuit_breaker import fcm_breaker, CircuitOpenError

logger = get_logger(__name__)


class FirebaseAdapter(PushNotificationPort):
    """
    Firebase altyapısını saran Adapter (Hexagonal Architecture).
    Port (Arayüz) üzerinden iş mantığına servis edilir.
    """

    def _get_firebase_app(self):
        from app.config import settings
        if not settings.firebase_service_account:
            logger.error("[FirebaseAdapter] firebase_service_account ayarlanmamış — push devre dışı")
            return None
        try:
            import firebase_admin
            from firebase_admin import credentials
            if not firebase_admin._apps:
                cred = credentials.Certificate(settings.firebase_service_account)
                firebase_admin.initialize_app(cred)
                logger.info("[FirebaseAdapter] Firebase başarıyla başlatıldı")
            return firebase_admin.get_app()
        except Exception as exc:
            logger.error("[FirebaseAdapter] Firebase init failed: %s", exc, exc_info=True)
            capture_exception(exc)
            return None

    async def send_notification(self, token: str, title: str, body: str, data: Dict[str, Any] = None) -> bool:
        if not token:
            logger.error("[FirebaseAdapter] send_notification çağrıldı ama token boş")
            return False

        try:
            async with fcm_breaker:
                app = self._get_firebase_app()
                if app is None:
                    raise ServiceException("Firebase app not initialized")

                from firebase_admin import messaging
                
                # Sadece standart push parametreleri için mock bir implementasyon uyarladık.
                # data dict olarak geliyorsa string'e dönüştürülmeli
                formatted_data = {k: str(v) for k, v in data.items()} if data else {}

                msg = messaging.Message(
                    notification=messaging.Notification(title=title, body=body),
                    data=formatted_data,
                    token=token,
                    android=messaging.AndroidConfig(priority="high"),
                )
                
                result = await asyncio.get_event_loop().run_in_executor(
                    None, messaging.send, msg
                )
                logger.info("[FirebaseAdapter] Push başarılı | message_id=%s | token=%s…", result, token[:12])
                return True

        except CircuitOpenError:
            logger.warning("[FirebaseAdapter] Circuit AÇIK — push atlandı | token=%s…", token[:12])
            return False
        except Exception as exc:
            try:
                from firebase_admin import exceptions as fb_exceptions
                if isinstance(exc, fb_exceptions.NotFoundError):
                    logger.warning("[FirebaseAdapter] Geçersiz token (Event fırlatılıyor): %s…", token[:12])
                    from app.core.event_bus import event_bus
                    from app.core.events import TokenInvalidatedEvent
                    event_bus.publish(TokenInvalidatedEvent(token=token))
                    return False
            except ImportError:
                pass
                
            logger.error("[FirebaseAdapter] Push başarısız | token=%s… | hata=%s", token[:12], exc, exc_info=True)
            capture_exception(exc)
            raise ServiceException(f"Push notification failed: {exc}")

    async def send_multicast(self, tokens: list[str], title: str, body: str, data: Dict[str, Any] = None) -> dict:
        # Şimdilik implemente edilmedi
        raise NotImplementedError("Multicast is not yet implemented")
