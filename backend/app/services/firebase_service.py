import asyncio

from app.core.logger import get_logger, capture_exception
from app.core.circuit_breaker import fcm_breaker, CircuitOpenError

logger = get_logger(__name__)



class InvalidFCMTokenError(Exception):
    """FCM token geçersiz veya süresi dolmuş — DB'den temizlenmeli."""
    def __init__(self, token: str):
        self.token = token
        super().__init__(f"Invalid FCM token: {token[:12]}…")


def _get_firebase_app():
    from app.config import settings
    if not settings.firebase_service_account:
        logger.error("[FCM] firebase_service_account ayarlanmamış — push devre dışı")
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials
        if not firebase_admin._apps:
            cred = credentials.Certificate(settings.firebase_service_account)
            firebase_admin.initialize_app(cred)
            logger.info("[FCM] Firebase başarıyla başlatıldı")
        return firebase_admin.get_app()
    except Exception as exc:
        logger.error("[FCM] Firebase init failed: %s", exc, exc_info=True)
        capture_exception(exc)
        return None


async def send_push(
    token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
    extra_data: dict[str, str] | None = None,
    image_url: str | None = None,
) -> None:
    if not token:
        logger.error("[FCM] send_push çağrıldı ama token boş")
        return
    try:
        await fcm_breaker.__aenter__()
    except CircuitOpenError:
        logger.warning("[FCM] Circuit açık — push atlandı | token=%s…", token[:12])
        return
    app = _get_firebase_app()
    if app is None:
        await fcm_breaker.__aexit__(Exception, Exception("no app"), None)
        logger.error("[FCM] Firebase app yok — push gönderilemiyor")
        return
    logger.info("[FCM] Push gönderiliyor | token=%s… | title=%r | type=%s | badge=%s", token[:12], title, notif_type, badge)
    try:
        from firebase_admin import messaging
        # data payload: Flutter tarafı bu alanı okuyarak UI'ı anında günceller
        data: dict[str, str] = {}
        if notif_type:
            data["type"] = notif_type
        if extra_data:
            data.update(extra_data)
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body, image=image_url),
            data=data,
            token=token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(image=image_url) if image_url else None,
            ),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", badge=badge)
                ),
            ),
        )
        result = await asyncio.get_event_loop().run_in_executor(
            None, messaging.send, msg
        )
        logger.info("[FCM] Push başarılı | message_id=%s", result)
        await fcm_breaker.__aexit__(None, None, None)
    except Exception as exc:
        await fcm_breaker.__aexit__(type(exc), exc, None)
        # Token geçersiz/silinmiş → özel hata fırlat, worker DB'den temizler
        try:
            from firebase_admin import exceptions as fb_exceptions
            if isinstance(exc, fb_exceptions.NotFoundError):
                raise InvalidFCMTokenError(token) from exc
        except InvalidFCMTokenError:
            raise
        except ImportError:
            pass
        logger.error("[FCM] Push başarısız | %s", exc)
