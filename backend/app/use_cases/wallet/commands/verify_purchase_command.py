from __future__ import annotations
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, ConflictException
from app.core.logger import get_logger
from app.services.store.base import PurchaseResult
from app.services.store.apple_verifier import VALID_CONSUMABLE_IDS, VALID_SUBSCRIPTION_IDS
from app.services.store.factory import StoreVerifierFactory

logger = get_logger(__name__)

# Consumable paket → teqlik miktarı (bonus dahil)
_CONSUMABLE_AMOUNTS: dict[str, int] = {
    "teqlik_pack_100":  100,
    "teqlik_pack_250":  275,   # 250 + 25 bonus
    "teqlik_pack_500":  575,   # 500 + 75 bonus
    "teqlik_pack_1000": 1200,  # 1000 + 200 bonus
}

# Abonelik product_id → plan_type
_PLAN_TYPE: dict[str, str] = {
    "teqlif_pro_1m":  "monthly",
    "teqlif_pro_3m":  "quarterly",
    "teqlif_pro_6m":  "biannual",
    "teqlif_pro_12m": "annual",
}

# Redis velocity key: rate:iap:{device_id}  |  rolling 24h window (₺5.000/gün)
# Değer: approx TRY tutarı (paket tutarı dışarıdan gelir; şimdilik 0 olarak geçilir)
_IAP_VELOCITY_LIMIT_TRY = 5000.0
_IAP_VELOCITY_TTL_SEC   = 86400  # 24 saat


async def _check_velocity(redis, device_id: str, try_amount: float) -> None:
    """Cihaz başına günlük ₺5.000 velocity limiti — Fail-Closed."""
    if redis is None:
        # Redis bağlantısı yoksa Fail-Closed: reddet
        raise BadRequestException(code="IAP_VELOCITY_UNAVAILABLE")
    key = f"rate:iap:{device_id}"
    current = await redis.get(key)
    current_val = float(current or 0)
    if current_val + try_amount > _IAP_VELOCITY_LIMIT_TRY:
        logger.warning("[VerifyPurchase] Velocity limit aşıldı | device=%s total=%.2f", device_id, current_val + try_amount)
        raise BadRequestException(code="IAP_VELOCITY_LIMIT_EXCEEDED")
    pipe = redis.pipeline()
    pipe.incrbyfloat(key, try_amount)
    pipe.expire(key, _IAP_VELOCITY_TTL_SEC)
    await pipe.execute()


class VerifyPurchaseCommand:
    """IAP satın alımı doğrulama ve bakiye/abonelik güncelleme."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(
        self,
        user_id: int,
        platform: str,
        payload: str,
        product_id: str,
        device_id: str | None = None,
        try_amount: float = 0.0,
    ) -> dict:
        verifier = StoreVerifierFactory.get(platform)

        result: PurchaseResult = await verifier.verify(payload)

        # Replay koruması — (store_platform, store_transaction_id) partial unique
        existing = await self._session.execute(
            text(
                "SELECT id FROM teqlik_transactions "
                "WHERE store_platform = :platform "
                "AND store_transaction_id = :tx_id "
                "LIMIT 1"
            ),
            {"platform": platform, "tx_id": result.transaction_id},
        )
        if existing.fetchone() is not None:
            logger.warning(
                "[VerifyPurchase] Replay tespit edildi | platform=%s tx=%s",
                platform, result.transaction_id,
            )
            raise ConflictException(code="IAP_ALREADY_PROCESSED")

        # Velocity limiti (Fail-Closed — Redis yoksa reddet)
        if device_id and try_amount > 0:
            try:
                from app.utils.redis_client import get_redis
                redis = await get_redis()
                await _check_velocity(redis, device_id, try_amount)
            except (BadRequestException, ConflictException):
                raise
            except Exception as exc:
                logger.error("[VerifyPurchase] Redis velocity check başarısız | %s", exc)
                raise BadRequestException(code="IAP_VELOCITY_UNAVAILABLE")

        if result.product_id in VALID_CONSUMABLE_IDS:
            return await self._handle_consumable(user_id, platform, result)
        else:
            return await self._handle_subscription(user_id, platform, result)

    async def _handle_consumable(
        self, user_id: int, platform: str, result: PurchaseResult
    ) -> dict:
        teqlik_amount = _CONSUMABLE_AMOUNTS[result.product_id]

        await self._session.execute(
            text("UPDATE users SET teqlik_balance = teqlik_balance + :amt WHERE id = :uid"),
            {"amt": teqlik_amount, "uid": user_id},
        )

        tx_row = await self._session.execute(
            text(
                "INSERT INTO teqlik_transactions "
                "(user_id, amount, transaction_type, store_platform, "
                " store_transaction_id, raw_payload, product_type) "
                "VALUES (:uid, :amt, 'iap_purchase', :platform, :tx_id, :raw, 'consumable') "
                "RETURNING id"
            ),
            {
                "uid": user_id,
                "amt": teqlik_amount,
                "platform": platform,
                "tx_id": result.transaction_id,
                "raw": result.raw_payload,
            },
        )
        tx_id_db = tx_row.fetchone()[0]

        balance_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = :uid"),
            {"uid": user_id},
        )
        balance_after = balance_row.fetchone()[0]

        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, :delta, :bal, 'iap_purchase', :ref_id, 'teqlik_transaction')"
            ),
            {
                "uid": user_id,
                "delta": teqlik_amount,
                "bal": balance_after,
                "ref_id": tx_id_db,
            },
        )

        logger.info(
            "[VerifyPurchase] Consumable | user=%s product=%s amount=%s",
            user_id, result.product_id, teqlik_amount,
        )
        return {"status": "ok", "product_type": "consumable", "teqlik_added": teqlik_amount}

    async def _handle_subscription(
        self, user_id: int, platform: str, result: PurchaseResult
    ) -> dict:
        plan_type = _PLAN_TYPE.get(result.product_id, "monthly")
        now = datetime.now(timezone.utc)

        await self._session.execute(
            text(
                "UPDATE users SET "
                "user_type = 'pro', "
                "plan_type = :plan, "
                "premium_since = COALESCE(premium_since, :now), "
                "pro_expires_at = :exp, "
                "store_subscription_id = :sub_id, "
                "store_subscription_platform = :platform "
                "WHERE id = :uid"
            ),
            {
                "plan": plan_type,
                "now": now,
                "exp": result.expires_at,
                "sub_id": result.subscription_id,
                "platform": platform,
                "uid": user_id,
            },
        )

        sub_tx_row = await self._session.execute(
            text(
                "INSERT INTO teqlik_transactions "
                "(user_id, amount, transaction_type, store_platform, "
                " store_transaction_id, raw_payload, product_type) "
                "VALUES (:uid, 0, 'pro_subscription', :platform, :tx_id, :raw, 'subscription') "
                "RETURNING id"
            ),
            {
                "uid": user_id,
                "platform": platform,
                "tx_id": result.transaction_id,
                "raw": result.raw_payload,
            },
        )
        sub_tx_id = sub_tx_row.fetchone()[0]

        sub_balance_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = :uid"),
            {"uid": user_id},
        )
        sub_balance_after = sub_balance_row.fetchone()[0]

        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, 0, :bal, 'iap_purchase', :ref_id, 'teqlik_transaction')"
            ),
            {
                "uid": user_id,
                "bal": sub_balance_after,
                "ref_id": sub_tx_id,
            },
        )

        logger.info(
            "[VerifyPurchase] Subscription | user=%s product=%s plan=%s expires=%s",
            user_id, result.product_id, plan_type, result.expires_at,
        )
        return {"status": "ok", "product_type": "subscription", "plan_type": plan_type}
