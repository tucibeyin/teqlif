from __future__ import annotations
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.store.notifications.base import StoreNotificationHandler


class StoreNotificationHandlerFactory:
    @staticmethod
    def get(platform: str, session: AsyncSession) -> StoreNotificationHandler:
        if platform == "apple":
            from app.services.store.notifications.apple_handler import AppleNotificationHandler
            return AppleNotificationHandler(session)
        raise ValueError(f"Desteklenmeyen notification platform: {platform!r}")
