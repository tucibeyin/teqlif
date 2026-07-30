import abc
from typing import Dict, Any

class PushNotificationPort(abc.ABC):
    """
    Push bildirim servisi için arayüz (Port).
    Firebase gibi altyapı araçları bu arayüzü implement eder.
    """

    @abc.abstractmethod
    def send_notification(
        self,
        token: str,
        title: str,
        body: str,
        data: Dict[str, Any] = None,
        is_silent: bool = False,
        ttl: int | None = None,
        android_channel_id: str | None = None,
    ) -> bool:
        """
        Tek bir cihaza bildirim gönderir.
        is_silent=True → notification alanı olmadan data-only mesaj (callkit için).
        ttl → FCM mesaj yaşam süresi (saniye).
        android_channel_id → özel kanal ID'si.
        """
        pass

    @abc.abstractmethod
    def send_multicast(self, tokens: list[str], title: str, body: str, data: Dict[str, Any] = None) -> dict:
        """
        Çoklu cihaza bildirim gönderir.
        """
        pass
