import asyncio
import logging

logger = logging.getLogger(__name__)


async def verify_phone_token(id_token: str) -> str:
    """
    Firebase Phone Auth ID token'ını doğrular.
    Geçerliyse E.164 formatında telefon numarasını döndürür (+905551234567).
    Geçersizse ForbiddenException fırlatır.
    """
    from app.core.exceptions import ForbiddenException, ServiceException

    app = _get_firebase_app()
    if app is None:
        raise ServiceException("Firebase yapılandırılmamış")
    try:
        from firebase_admin import auth as fb_auth
        decoded = await asyncio.get_event_loop().run_in_executor(
            None, fb_auth.verify_id_token, id_token
        )
        phone_number: str | None = decoded.get("phone_number")
        if not phone_number:
            raise ForbiddenException("Token içinde telefon numarası bulunamadı")
        return phone_number
    except (ForbiddenException, ServiceException):
        raise
    except Exception as exc:
        logger.warning("[FCM] Telefon token doğrulama başarısız | %s", exc)
        raise ForbiddenException("Geçersiz veya süresi dolmuş telefon doğrulama token'ı") from exc


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
        logger.error("[FCM] Firebase init failed: %s", exc)
        return None


async def send_push(
    token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
) -> None:
    if not token:
        logger.error("[FCM] send_push çağrıldı ama token boş")
        return
    app = _get_firebase_app()
    if app is None:
        logger.error("[FCM] Firebase app yok — push gönderilemiyor")
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
            android=messaging.AndroidConfig(priority="high"),
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
    except Exception as exc:
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
