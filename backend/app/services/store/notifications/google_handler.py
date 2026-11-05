from __future__ import annotations

import base64
import json
from datetime import datetime, timezone

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger
from app.services.store.notifications.base import StoreNotificationHandler

logger = get_logger(__name__)

_PLAY_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3"

# subscriptionNotification.notificationType değerleri
_TYPE_RENEWED         = 2
_TYPE_CANCELED        = 3
_TYPE_ON_HOLD         = 5
_TYPE_IN_GRACE_PERIOD = 6
_TYPE_REVOKED         = 12
_TYPE_EXPIRED         = 13


class GoogleNotificationHandler(StoreNotificationHandler):
    """Google Play Real-Time Developer Notifications (RTDN) — abonelik yaşam döngüsü.

    signed_payload: Pub/Sub tarafından gönderilen base64-encoded RTDN JSON body.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def handle(self, signed_payload: str) -> None:
        try:
            rtdn = json.loads(base64.b64decode(signed_payload + "=="))
        except Exception as exc:
            logger.error("[GoogleNotif] Payload çözülemedi | %s", exc)
            return

        package_name = rtdn.get("packageName", "")
        sub_notif = rtdn.get("subscriptionNotification")

        if sub_notif is None:
            logger.info(
                "[GoogleNotif] subscriptionNotification yok, atlandı | keys=%s",
                list(rtdn.keys()),
            )
            return

        notif_type     = sub_notif.get("notificationType")
        purchase_token = sub_notif.get("purchaseToken", "")
        subscription_id = sub_notif.get("subscriptionId", "")

        user_row = await self._session.execute(
            text(
                "SELECT id FROM users "
                "WHERE store_subscription_id = :token "
                "AND store_subscription_platform = 'google' "
                "LIMIT 1"
            ),
            {"token": purchase_token},
        )
        user = user_row.fetchone()
        if user is None:
            logger.warning(
                "[GoogleNotif] Kullanıcı bulunamadı | token=%.20s type=%s",
                purchase_token, notif_type,
            )
            return

        user_id = user[0]

        if notif_type == _TYPE_RENEWED:
            await self._handle_renewed(user_id, purchase_token, subscription_id, package_name)
        elif notif_type in (_TYPE_REVOKED, _TYPE_EXPIRED):
            await self._handle_expired(user_id, notif_type)
        elif notif_type in (_TYPE_ON_HOLD, _TYPE_IN_GRACE_PERIOD):
            label = "ON_HOLD" if notif_type == _TYPE_ON_HOLD else "IN_GRACE_PERIOD"
            logger.info(
                "[GoogleNotif] %s | user=%s — grace; check_expired_pro_users sigorta",
                label, user_id,
            )
        elif notif_type == _TYPE_CANCELED:
            # Abonelik iptal edildi ama expire olmadı — EXPIRED/REVOKED gelince düşürülür.
            logger.info("[GoogleNotif] CANCELED | user=%s — EXPIRED beklenecek", user_id)
        else:
            logger.info("[GoogleNotif] İşlenmeyen tip | type=%s user=%s", notif_type, user_id)

    async def _handle_renewed(
        self,
        user_id: int,
        purchase_token: str,
        subscription_id: str,
        package_name: str,
    ) -> None:
        expires_at = await self._fetch_subscription_expiry(
            purchase_token, subscription_id, package_name
        )
        if expires_at is None:
            logger.warning("[GoogleNotif] RENEWED expiry alınamadı | user=%s", user_id)
            return
        await self._session.execute(
            text(
                "UPDATE users SET user_type = 'pro', pro_expires_at = :exp, pro_grace_until = NULL "
                "WHERE id = :uid"
            ),
            {"exp": expires_at, "uid": user_id},
        )
        logger.info("[GoogleNotif] RENEWED | user=%s expires=%s", user_id, expires_at)

    async def _handle_expired(self, user_id: int, notif_type: int) -> None:
        await self._session.execute(
            text(
                "UPDATE users SET user_type = 'standard', "
                "pro_expires_at = NULL, pro_grace_until = NULL "
                "WHERE id = :uid"
            ),
            {"uid": user_id},
        )
        label = "REVOKED" if notif_type == _TYPE_REVOKED else "EXPIRED"
        logger.info("[GoogleNotif] %s | user=%s → standard", label, user_id)

    async def _fetch_subscription_expiry(
        self, purchase_token: str, subscription_id: str, package_name: str
    ) -> datetime | None:
        from app.services.store.google_play_verifier import _load_credentials, _get_access_token
        from app.config import settings as _settings
        try:
            pkg = package_name or _settings.google_play_package_name
            creds = _load_credentials()
            token = _get_access_token(creds)
            url = (
                f"{_PLAY_BASE}/applications/{pkg}"
                f"/purchases/subscriptionsv2/tokens/{purchase_token}"
            )
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, headers={"Authorization": f"Bearer {token}"})
            if resp.status_code != 200:
                logger.error(
                    "[GoogleNotif] subscriptionsv2 başarısız | status=%s body=%.200s",
                    resp.status_code, resp.text,
                )
                return None
            line_items = resp.json().get("lineItems", [])
            if line_items:
                expiry_str = line_items[0].get("expiryTime", "")
                if expiry_str:
                    return datetime.fromisoformat(expiry_str.replace("Z", "+00:00"))
        except Exception as exc:
            logger.error("[GoogleNotif] expiry fetch hatası | %s", exc)
        return None
