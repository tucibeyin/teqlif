import asyncio

from app.core.logger import get_logger, capture_exception
from app.core.circuit_breaker import fcm_breaker, CircuitOpenError

logger = get_logger(__name__)



class InvalidFCMTokenError(Exception):
    """FCM token geçersiz veya süresi dolmuş — DB'den temizlenmeli."""
    def __init__(self, token: str):
        self.token = token
        super().__init__(f"Invalid FCM token: {token[:12]}…")


import asyncio
from app.core.logger import get_logger
from app.core.di import container
from app.core.ports.push_notification_port import PushNotificationPort

logger = get_logger(__name__)

class InvalidFCMTokenError(Exception):
    """Geriye dönük uyumluluk için bırakıldı."""
    def __init__(self, token: str):
        self.token = token
        super().__init__(f"Invalid FCM token: {token[:12]}…")


async def send_push(
    token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
    extra_data: dict[str, str] | None = None,
    image_url: str | None = None,
    is_silent: bool = False,
) -> None:
    """
    Eski servis fonksiyonu, geriye dönük uyumluluk (Facade) amacıyla korunmuştur.
    Tüm iş mantığı app.core.ports.PushNotificationPort'a (FirebaseAdapter) delege edilmiştir.
    """
    if not token:
        logger.error("[FCM Facade] send_push çağrıldı ama token boş")
        return

    data: dict[str, str] = {}
    if notif_type:
        data["type"] = notif_type
    if extra_data:
        data.update(extra_data)

    try:
        # DI Container üzerinden port'u alıyoruz.
        # init_di() main.py veya worker tarafından daha önce çağrılmış olmalı.
        push_port = container.resolve(PushNotificationPort)
        success = await push_port.send_notification(token, title, body, data)
        if not success:
            logger.warning("[FCM Facade] Push gönderimi başarısız döndü.")
    except Exception as exc:
        logger.error("[FCM Facade] Adapter çağrısı sırasında hata: %s", exc)
        raise
