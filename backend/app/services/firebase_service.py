import asyncio
import logging
from functools import lru_cache

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _get_firebase_app():
    from app.config import settings
    if not settings.firebase_service_account:
        logger.warning("[FCM] firebase_service_account ayarlanmamış — push devre dışı")
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(settings.firebase_service_account)
        app = firebase_admin.initialize_app(cred)
        logger.info("[FCM] Firebase başarıyla başlatıldı")
        return app
    except Exception as exc:
        logger.warning("[FCM] Firebase init failed: %s", exc)
        return None


async def send_push(
    token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
) -> None:
    if not token:
        logger.warning("[FCM] send_push çağrıldı ama token boş")
        return
    app = _get_firebase_app()
    if app is None:
        logger.warning("[FCM] Firebase app yok — push gönderilemiyor")
        return
    logger.info("[FCM] Push gönderiliyor | token=%s… | title=%r | type=%s | badge=%s", token[:12], title, notif_type, badge)
    try:
        from firebase_admin import messaging
        # data payload: Flutter tarafı bu alanı okuyarak UI'ı anında günceller
        data: dict[str, str] = {}
        if notif_type:
            data["type"] = notif_type
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data,
            token=token,
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", badge=badge)
                )
            ),
        )
        result = await asyncio.get_event_loop().run_in_executor(
            None, messaging.send, msg
        )
        logger.info("[FCM] Push başarılı | message_id=%s", result)
    except Exception as exc:
        logger.warning("[FCM] Push başarısız | %s", exc)
