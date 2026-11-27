from __future__ import annotations
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger
from app.services.store.apple_verifier import verify_signed_payload_jws
from app.services.store.notifications.base import StoreNotificationHandler
from app.services.subscription.tier import tier_from_product, plan_type_from_product, TIER_STANDARD

logger = get_logger(__name__)


class AppleNotificationHandler(StoreNotificationHandler):
    """App Store Server Notifications V2 — abonelik yaşam döngüsü."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def handle(self, signed_payload: str) -> None:
        claims = verify_signed_payload_jws(signed_payload)

        # Idempotency: notificationUUID bazlı duplicate rejection (3 gün TTL)
        notif_uuid = claims.get("notificationUUID")
        if notif_uuid:
            try:
                from app.utils.redis_client import get_redis
                _redis = await get_redis()
                if not await _redis.set(f"notif:apple:uuid:{notif_uuid}", "1", nx=True, ex=259200):
                    logger.info("[AppleNotif] Duplicate UUID atlandı | uuid=%s", notif_uuid)
                    return
            except Exception as exc:
                logger.warning("[AppleNotif] Redis idempotency check başarısız | %s", exc)

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

        if notification_type == "SUBSCRIBED":
            await self._handle_subscribed(user_id, tx_claims)

        elif notification_type == "DID_RENEW" and not subtype:
            await self._handle_did_renew(user_id, tx_claims)

        elif notification_type == "DID_RENEW" and subtype == "BILLING_RETRY":
            await self._handle_billing_retry(user_id, tx_claims)

        elif notification_type == "DID_RENEW" and subtype == "UPGRADE":
            await self._handle_upgrade(user_id, tx_claims)

        elif notification_type == "DID_CHANGE_RENEWAL_PREF" and subtype == "UPGRADE":
            await self._handle_upgrade(user_id, tx_claims)

        elif notification_type == "DID_CHANGE_RENEWAL_PREF" and subtype == "DOWNGRADE":
            # Mevcut dönem üst planda devam eder; pending_tier kaydedilir, geçiş DID_RENEW'da olur
            await self._handle_downgrade_pref(user_id, tx_claims)

        elif notification_type == "DID_FAIL_TO_RENEW" and subtype == "GRACE_PERIOD":
            # Grace period aktif — DID_RENEW+BILLING_RETRY ile aynı mantık
            await self._handle_billing_retry(user_id, tx_claims)

        elif notification_type == "DID_FAIL_TO_RENEW":
            # Fatura başarısız, grace period yok; abonelik expiresDate'e kadar hala geçerli
            logger.info("[AppleNotif] DID_FAIL_TO_RENEW (billing retry, işlem yok) | user=%s", user_id)

        elif notification_type == "DID_CHANGE_RENEWAL_STATUS":
            await self._handle_renewal_status(user_id, subtype)

        elif notification_type in ("EXPIRED",) or subtype == "GRACE_PERIOD_EXPIRED":
            await self._handle_expired(user_id)

        elif notification_type == "REVOKE":
            await self._handle_revoke(user_id)

        elif notification_type in ("TEST", "CONSUMPTION_REQUEST", "REFUND_DECLINED"):
            logger.info("[AppleNotif] %s | user=%s", notification_type, user_id)

        else:
            logger.warning(
                "[AppleNotif] Bilinmeyen event | type=%s subtype=%s user=%s",
                notification_type, subtype, user_id,
            )

    async def _handle_subscribed(self, user_id: int, tx_claims: dict) -> None:
        product_id = tx_claims.get("productId", "")
        new_tier  = tier_from_product(product_id)
        plan_type = plan_type_from_product(product_id)
        expires_ms = tx_claims.get("expiresDate", 0)
        expires_at = datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc) if expires_ms else None
        if not new_tier or not expires_at:
            logger.warning("[AppleNotif] SUBSCRIBED eksik veri | product=%s user=%s", product_id, user_id)
            return
        await self._session.execute(
            text(
                "UPDATE users SET user_type = :tier, plan_type = :plan, "
                "sub_expires_at = :exp, sub_grace_until = NULL, "
                "auto_renew_enabled = TRUE, pending_tier = NULL "
                "WHERE id = :uid"
            ),
            {"tier": new_tier, "plan": plan_type, "exp": expires_at, "uid": user_id},
        )
        logger.info("[AppleNotif] SUBSCRIBED | user=%s tier=%s plan=%s expires=%s",
                    user_id, new_tier, plan_type, expires_at)

    async def _handle_did_renew(self, user_id: int, tx_claims: dict) -> None:
        product_id = tx_claims.get("productId", "")
        expires_ms = tx_claims.get("expiresDate", 0)
        expires_at = datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc)
        # Downgrade pending ise bu yenilemede yeni tiere geç
        new_tier  = tier_from_product(product_id)
        plan_type = plan_type_from_product(product_id)
        # sub_expires_at asla geri taşınmaz: Apple Sandbox veya gecikmiş S2S bildirimleri
        # eski expiresDate ile gelebilir. GREATEST(mevcut, yeni) ile en ileri tarih korunur.
        if new_tier and plan_type:
            await self._session.execute(
                text(
                    "UPDATE users SET user_type = :tier, plan_type = :plan, "
                    "sub_expires_at = GREATEST(COALESCE(sub_expires_at, :exp), :exp), "
                    "sub_grace_until = NULL, "
                    "auto_renew_enabled = TRUE, pending_tier = NULL, "
                    "monthly_stream_minutes_used = 0, monthly_stream_reset_at = NOW() "
                    "WHERE id = :uid"
                ),
                {"tier": new_tier, "plan": plan_type, "exp": expires_at, "uid": user_id},
            )
        else:
            await self._session.execute(
                text(
                    "UPDATE users SET "
                    "sub_expires_at = GREATEST(COALESCE(sub_expires_at, :exp), :exp), "
                    "sub_grace_until = NULL, "
                    "monthly_stream_minutes_used = 0, monthly_stream_reset_at = NOW() "
                    "WHERE id = :uid"
                ),
                {"exp": expires_at, "uid": user_id},
            )
        logger.info("[AppleNotif] DID_RENEW | user=%s tier=%s expires=%s", user_id, new_tier, expires_at)

    async def _handle_upgrade(self, user_id: int, tx_claims: dict) -> None:
        product_id = tx_claims.get("productId", "")
        new_tier  = tier_from_product(product_id)
        plan_type = plan_type_from_product(product_id)
        expires_ms = tx_claims.get("expiresDate", 0)
        expires_at = datetime.fromtimestamp(expires_ms / 1000, tz=timezone.utc)
        if new_tier and plan_type:
            await self._session.execute(
                text(
                    "UPDATE users SET user_type = :tier, plan_type = :plan, "
                    "sub_expires_at = :exp, sub_grace_until = NULL, "
                    "auto_renew_enabled = TRUE, pending_tier = NULL "
                    "WHERE id = :uid"
                ),
                {"tier": new_tier, "plan": plan_type, "exp": expires_at, "uid": user_id},
            )
            logger.info("[AppleNotif] UPGRADE | user=%s tier=%s", user_id, new_tier)
        else:
            logger.warning("[AppleNotif] UPGRADE bilinmeyen ürün | product_id=%s user=%s",
                           product_id, user_id)

    async def _handle_downgrade_pref(self, user_id: int, tx_claims: dict) -> None:
        product_id = tx_claims.get("productId", "")
        new_tier = tier_from_product(product_id)
        if new_tier:
            await self._session.execute(
                text("UPDATE users SET pending_tier = :tier, auto_renew_enabled = FALSE WHERE id = :uid"),
                {"tier": new_tier, "uid": user_id},
            )
            logger.info("[AppleNotif] DOWNGRADE pref | user=%s pending_tier=%s", user_id, new_tier)

    async def _handle_renewal_status(self, user_id: int, subtype: str) -> None:
        enabled = subtype == "AUTO_RENEW_ENABLED"
        await self._session.execute(
            text("UPDATE users SET auto_renew_enabled = :val WHERE id = :uid"),
            {"val": enabled, "uid": user_id},
        )
        logger.info("[AppleNotif] DID_CHANGE_RENEWAL_STATUS | user=%s auto_renew=%s", user_id, enabled)

    async def _handle_billing_retry(self, user_id: int, tx_claims: dict) -> None:
        grace_ms = tx_claims.get("gracePeriodExpiresDate", 0)
        grace_until = datetime.fromtimestamp(grace_ms / 1000, tz=timezone.utc)
        await self._session.execute(
            text("UPDATE users SET sub_grace_until = :grace WHERE id = :uid"),
            {"grace": grace_until, "uid": user_id},
        )
        logger.info("[AppleNotif] BILLING_RETRY | user=%s grace_until=%s", user_id, grace_until)

    async def _handle_expired(self, user_id: int) -> None:
        await self._session.execute(
            text(
                "UPDATE users SET last_tier = user_type, user_type = :tier, "
                "plan_type = NULL, sub_expires_at = NULL, sub_grace_until = NULL, "
                "auto_renew_enabled = TRUE, pending_tier = NULL, "
                "monthly_stream_minutes_used = 0, monthly_stream_reset_at = NULL "
                "WHERE id = :uid"
            ),
            {"tier": TIER_STANDARD, "uid": user_id},
        )
        await self._invalidate_cache(user_id)
        logger.info("[AppleNotif] EXPIRED | user=%s → standard", user_id)

    async def _handle_revoke(self, user_id: int) -> None:
        await self._session.execute(
            text(
                "UPDATE users SET last_tier = user_type, user_type = :tier, "
                "plan_type = NULL, sub_expires_at = NULL, sub_grace_until = NULL, "
                "auto_renew_enabled = TRUE, pending_tier = NULL, "
                "monthly_stream_minutes_used = 0, monthly_stream_reset_at = NULL "
                "WHERE id = :uid"
            ),
            {"tier": TIER_STANDARD, "uid": user_id},
        )
        await self._invalidate_cache(user_id)
        logger.info("[AppleNotif] REVOKE | user=%s → standard", user_id)

    @staticmethod
    async def _invalidate_cache(user_id: int) -> None:
        try:
            from app.utils.auth import invalidate_user_session_cache
            await invalidate_user_session_cache(user_id)
        except Exception as exc:
            logger.warning("[AppleNotif] session cache invalidate başarısız | user=%s | %s", user_id, exc)
