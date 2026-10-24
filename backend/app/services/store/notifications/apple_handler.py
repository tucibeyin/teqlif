from __future__ import annotations
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger
from app.services.store.apple_verifier import verify_signed_payload_jws
from app.services.store.notifications.base import StoreNotificationHandler

logger = get_logger(__name__)


class AppleNotificationHandler(StoreNotificationHandler):
    """App Store Server Notifications V2 — abonelik yaşam döngüsü."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def handle(self, signed_payload: str) -> None:
        claims = verify_signed_payload_jws(signed_payload)

        notification_type = claims.get("notificationType", "")
        subtype = claims.get("subtype", "")

        signed_tx = claims.get("data", {}).get("signedTransactionInfo")
        if not signed_tx:
            logger.warning("[AppleNotif] signedTransactionInfo eksik | type=%s", notification_type)
            return

        tx_claims = verify_signed_payload_jws(signed_tx)
        original_tx_id = tx_claims.get("originalTransactionId")
        subscription_id = tx_claims.get("originalTransactionId")

        user_row = await self._session.execute(
            text(
                "SELECT id FROM users "
                "WHERE store_subscription_id = :sub_id "
                "AND store_subscription_platform = 'apple' "
                "LIMIT 1"
            ),
            {"sub_id": subscription_id},
        )
        user = user_row.fetchone()
        if user is None:
            logger.warning(
                "[AppleNotif] Kullanıcı bulunamadı | sub_id=%s tx=%s",
                subscription_id, original_tx_id,
            )
            return

        user_id = user[0]

        if notification_type == "DID_RENEW" and not subtype:
            await self._handle_did_renew(user_id, tx_claims)

        elif notification_type == "DID_RENEW" and subtype == "BILLING_RETRY":
            await self._handle_billing_retry(user_id, tx_claims)

        elif notification_type in ("EXPIRED",) or subtype == "GRACE_PERIOD_EXPIRED":
            await self._handle_expired(user_id)

        elif notification_type == "REVOKE":
            await self._handle_revoke(user_id)

        else:
            logger.info(
                "[AppleNotif] İşlenmeyen event | type=%s subtype=%s user=%s",
                notification_type, subtype, user_id,
            )

    async def _handle_did_renew(self, user_id: int, tx_claims: dict) -> None:
        expires_ms = tx_claims.get("expiresDate", 0)
        expires_at = datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc)
        await self._session.execute(
            text(
                "UPDATE users SET pro_expires_at = :exp, pro_grace_until = NULL "
                "WHERE id = :uid"
            ),
            {"exp": expires_at, "uid": user_id},
        )
        logger.info("[AppleNotif] DID_RENEW | user=%s expires=%s", user_id, expires_at)

    async def _handle_billing_retry(self, user_id: int, tx_claims: dict) -> None:
        grace_ms = tx_claims.get("gracePeriodExpiresDate", 0)
        grace_until = datetime.fromtimestamp(grace_ms / 1000, tz=timezone.utc)
        await self._session.execute(
            text(
                "UPDATE users SET user_type = 'pro', pro_grace_until = :grace "
                "WHERE id = :uid"
            ),
            {"grace": grace_until, "uid": user_id},
        )
        logger.info("[AppleNotif] BILLING_RETRY | user=%s grace_until=%s", user_id, grace_until)

    async def _handle_expired(self, user_id: int) -> None:
        await self._session.execute(
            text(
                "UPDATE users SET user_type = 'standard', "
                "pro_expires_at = NULL, pro_grace_until = NULL "
                "WHERE id = :uid"
            ),
            {"uid": user_id},
        )
        logger.info("[AppleNotif] EXPIRED | user=%s → standard", user_id)

    async def _handle_revoke(self, user_id: int) -> None:
        await self._session.execute(
            text(
                "UPDATE users SET user_type = 'standard', pro_expires_at = NULL "
                "WHERE id = :uid"
            ),
            {"uid": user_id},
        )
        logger.info("[AppleNotif] REVOKE | user=%s → standard", user_id)
