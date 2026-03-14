import asyncio
import logging
from functools import lru_cache

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _get_firebase_app():
    from app.config import settings
    if not settings.firebase_service_account:
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(settings.firebase_service_account)
        return firebase_admin.initialize_app(cred)
    except Exception as exc:
        logger.warning("Firebase init failed: %s", exc)
        return None


async def send_push(token: str, title: str, body: str | None = None) -> None:
    if not token:
        return
    app = _get_firebase_app()
    if app is None:
        return
    try:
        from firebase_admin import messaging
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            token=token,
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default")
                )
            ),
        )
        await asyncio.get_event_loop().run_in_executor(
            None, messaging.send, msg
        )
        logger.debug("FCM push sent to token=%s…", token[:10])
    except Exception as exc:
        logger.warning("FCM push failed: %s", exc)
