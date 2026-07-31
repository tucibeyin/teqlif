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

    app: init_di() tarafından dışarıdan enjekte edilen firebase_admin.App instance.
    messaging.send(msg, app=self._app) ile her zaman bu spesifik app kullanılır —
    default app belirsizliğine ve _apps singleton race condition'ına karşı koruma sağlar.
    """

    def __init__(self, app):
        self._app = app

    async def send_notification(
        self,
        token: str,
        title: str,
        body: str,
        data: Dict[str, Any] = None,
        is_silent: bool = False,
        ttl: int | None = None,
        android_channel_id: str | None = None,
    ) -> bool:
        if not token:
            logger.error("[FirebaseAdapter] send_notification çağrıldı ama token boş")
            return False

        if self._app is None:
            logger.error("[FirebaseAdapter] Firebase app None — push devre dışı")
            return False

        try:
            async with fcm_breaker:
                from firebase_admin import messaging

                formatted_data = {k: str(v) for k, v in data.items()} if data else {}

                # is_silent=True → data-only mesaj (notification alanı yok).
                # Callkit/background handler bildirimi kendisi yönetir; sistem
                # bildirim + callkit double-UI'ını önler.
                notification = None if is_silent else messaging.Notification(title=title, body=body)

                android_cfg = messaging.AndroidConfig(
                    priority="high",
                    ttl=ttl,
                    notification=messaging.AndroidNotification(
                        channel_id=android_channel_id,
                    ) if (android_channel_id and not is_silent) else None,
                )

                # iOS: apns-priority 10 (high) olmadan arka planda/kapalıyken bildirim gösterilmez.
                # is_silent=True (VoIP çağrıları) için APNs config gönderilmez — o akış
                # apns_service.py üzerinden PushType.VOIP ile ayrıca gidiyor.
                apns_cfg = None if is_silent else messaging.APNSConfig(
                    headers={
                        "apns-priority": "10",
                        "apns-push-type": "alert",
                    },
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default"),
                    ),
                )

                msg = messaging.Message(
                    notification=notification,
                    data=formatted_data,
                    token=token,
                    android=android_cfg,
                    apns=apns_cfg,
                )

                result = await asyncio.get_event_loop().run_in_executor(
                    None, messaging.send, msg, False, self._app
                )
                logger.info("[FirebaseAdapter] Push başarılı | message_id=%s | token=%s…", result, token[:12])
                return True

        except CircuitOpenError:
            logger.warning("[FirebaseAdapter] Circuit AÇIK — push atlandı | token=%s…", token[:12])
            return False
        except Exception as exc:
            try:
                from firebase_admin import exceptions as fb_exceptions
                if isinstance(exc, (fb_exceptions.NotFoundError, fb_exceptions.InvalidArgumentError)):
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
