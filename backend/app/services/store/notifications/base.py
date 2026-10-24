from __future__ import annotations
from abc import ABC, abstractmethod


class StoreNotificationHandler(ABC):
    """Platform-agnostic store bildirim işleyici soyut sınıfı."""

    @abstractmethod
    async def handle(self, signed_payload: str) -> None:
        """signedPayload'u doğrulayıp event'e göre DB güncelleme yapar."""
        ...
