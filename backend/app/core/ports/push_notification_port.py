import abc
from typing import Dict, Any

class PushNotificationPort(abc.ABC):
    """
    Push bildirim servisi için arayüz (Port).
    Firebase gibi altyapı araçları bu arayüzü implement eder.
    """

    @abc.abstractmethod
    def send_notification(self, token: str, title: str, body: str, data: Dict[str, Any] = None) -> bool:
        """
        Tek bir cihaza bildirim gönderir.
        """
        pass

    @abc.abstractmethod
    def send_multicast(self, tokens: list[str], title: str, body: str, data: Dict[str, Any] = None) -> dict:
        """
        Çoklu cihaza bildirim gönderir.
        """
        pass
