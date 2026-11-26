from __future__ import annotations
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from sqlalchemy.exc import IntegrityError

from app.core.exceptions import BadRequestException, ConflictException
from app.core.logger import get_logger
from app.services.store.base import PurchaseResult
from app.services.store.apple_verifier import VALID_CONSUMABLE_IDS
from app.services.store.factory import StoreVerifierFactory
from app.services.subscription.tier import tier_from_product, plan_type_from_product

logger = get_logger(__name__)

# Consumable paket → teqlik miktarı (bonus dahil)
_CONSUMABLE_AMOUNTS: dict[str, int] = {
    "teqlik_pack_100":  100,
    "teqlik_pack_250":  275,   # 250 + 25 bonus
    "teqlik_pack_500":  575,   # 500 + 75 bonus
    "teqlik_pack_1000": 1200,  # 1000 + 200 bonus
}

# Mobil try_amount <= 0 gelirse fallback fiyat tablosu kullanılır
# — direkt API çağrılarında client manipülasyonu önlenir
_PRODUCT_TRY_PRICES: dict[str, float] = {
    "teqlik_pack_100":       149.99,
    "teqlik_pack_250":       349.99,
    "teqlik_pack_500":       599.99,
    "teqlik_pack_1000":      999.99,
    # Abonelikler
    "teqlif_pro_1m":               999.99,
    "teqlif_pro_12m":             8999.99,   # 999.99 × 12 × 0.75
    "teqlif_pro_plus_1m":         1999.99,
    "teqlif_pro_plus_12m":       17999.99,   # 1999.99 × 12 × 0.75
    "teqlif_premium_1m":          2999.99,
    "teqlif_premium_12m":        26999.99,   # 2999.99 × 12 × 0.75
    "teqlif_premium_plus_1m":     3999.99,
    "teqlif_premium_plus_12m":   35999.99,   # 3999.99 × 12 × 0.75
}


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

        if result.product_id in VALID_CONSUMABLE_IDS:
            return await self._handle_consumable(user_id, platform, result)
        else:
            if result.expires_at is None:
                logger.error(
                    "[VerifyPurchase] Abonelik için expiresDate eksik | product=%s tx=%s",
                    result.product_id, result.transaction_id,
                )
                raise BadRequestException(code="IAP_MISSING_EXPIRY")
            stored_try_amount = (
                try_amount if try_amount > 0
                else _PRODUCT_TRY_PRICES.get(result.product_id, 0.0)
            )
            return await self._handle_subscription(user_id, platform, result, stored_try_amount)

    async def _handle_consumable(
        self, user_id: int, platform: str, result: PurchaseResult
    ) -> dict:
        teqlik_amount = _CONSUMABLE_AMOUNTS[result.product_id]

        bal_row = await self._session.execute(
            text(
                "UPDATE users SET teqlik_balance = teqlik_balance + :amt "
                "WHERE id = :uid RETURNING teqlik_balance"
            ),
            {"amt": teqlik_amount, "uid": user_id},
        )
        balance_after = bal_row.fetchone()[0]

        try:
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
        except IntegrityError:
            raise ConflictException(code="IAP_ALREADY_PROCESSED")
        tx_id_db = tx_row.fetchone()[0]

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
        self, user_id: int, platform: str, result: PurchaseResult,
        try_amount: float = 0.0,
    ) -> dict:
        new_tier  = tier_from_product(result.product_id) or "tier1"
        plan_type = plan_type_from_product(result.product_id) or "monthly"
        now = datetime.now(timezone.utc)

        sub_upd_row = await self._session.execute(
            text(
                "UPDATE users SET "
                "user_type = :tier, "
                "plan_type = :plan, "
                "premium_since = COALESCE(premium_since, :now), "
                "sub_expires_at = :exp, "
                "store_subscription_id = :sub_id, "
                "store_subscription_platform = :platform "
                "WHERE id = :uid RETURNING teqlik_balance"
            ),
            {
                "tier": new_tier,
                "plan": plan_type,
                "now": now,
                "exp": result.expires_at,
                "sub_id": result.subscription_id,
                "platform": platform,
                "uid": user_id,
            },
        )
        sub_balance_after = sub_upd_row.fetchone()[0]

        stored_try = try_amount if try_amount > 0 else None
        try:
            sub_tx_row = await self._session.execute(
                text(
                    "INSERT INTO teqlik_transactions "
                    "(user_id, amount, transaction_type, store_platform, "
                    " store_transaction_id, raw_payload, product_type, try_amount) "
                    "VALUES (:uid, 0, :tx_type, :platform, :tx_id, :raw, 'subscription', :try_amt) "
                    "RETURNING id"
                ),
                {
                    "uid": user_id,
                    "tx_type": f"subscription_{new_tier}_{plan_type}",
                    "platform": platform,
                    "tx_id": result.transaction_id,
                    "raw": result.raw_payload,
                    "try_amt": stored_try,
                },
            )
        except IntegrityError:
            raise ConflictException(code="IAP_ALREADY_PROCESSED")
        sub_tx_id = sub_tx_row.fetchone()[0]

        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, 0, :bal, :tx_type, :ref_id, 'teqlik_transaction')"
            ),
            {
                "uid": user_id,
                "bal": sub_balance_after,
                "tx_type": f"subscription_{new_tier}_{plan_type}",
                "ref_id": sub_tx_id,
            },
        )

        logger.info(
            "[VerifyPurchase] Subscription | user=%s product=%s plan=%s expires=%s",
            user_id, result.product_id, plan_type, result.expires_at,
        )
        return {"status": "ok", "product_type": "subscription", "plan_type": plan_type}
