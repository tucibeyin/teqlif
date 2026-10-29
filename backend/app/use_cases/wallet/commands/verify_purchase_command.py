from __future__ import annotations
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, ConflictException
from app.core.logger import get_logger
from app.services.store.base import PurchaseResult
from app.services.store.apple_verifier import VALID_CONSUMABLE_IDS
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

# Redis velocity key: rate:iap:{device_id}  |  fixed 24h window (₺5.000/gün)
_IAP_VELOCITY_LIMIT_TRY = 5000.0
_IAP_VELOCITY_TTL_SEC   = 86400  # 24 saat

# Mobil try_amount <= 0 gelirse fallback fiyat tablosu kullanılır
# — direkt API çağrılarında client manipülasyonu önlenir
_PRODUCT_TRY_PRICES: dict[str, float] = {
    "teqlik_pack_100":   149.99,
    "teqlik_pack_250":   349.99,
    "teqlik_pack_500":   599.99,
    "teqlik_pack_1000":  999.99,
    # Abonelikler: try_amount=0 gönderildiğinde velocity hesabına girer
    "teqlif_pro_1m":     299.99,
    "teqlif_pro_3m":     749.99,
    "teqlif_pro_6m":    1299.99,
    "teqlif_pro_12m":   1999.99,
}

# Atomik Lua: GET+limit kontrolü+INCRBYFLOAT+TTL guard tek round-trip'te
# TTL < 0 kontrolü: key expire/yaratılma arasında race ile TTL=-1 olan key'leri onarır
_VELOCITY_LUA = """
local cur = tonumber(redis.call('GET', KEYS[1]) or '0')
local add = tonumber(ARGV[1])
local lim = tonumber(ARGV[2])
if cur + add > lim then
    return -1
end
redis.call('INCRBYFLOAT', KEYS[1], add)
if redis.call('TTL', KEYS[1]) < 0 then
    redis.call('EXPIRE', KEYS[1], tonumber(ARGV[3]))
end
return 1
"""


async def _check_velocity(redis, device_id: str, try_amount: float) -> None:
    """Cihaz başına günlük ₺5.000 velocity limiti — Fail-Closed, atomik Lua."""
    if redis is None:
        raise BadRequestException(code="IAP_VELOCITY_UNAVAILABLE")
    key = f"rate:iap:{device_id}"
    result = await redis.eval(
        _VELOCITY_LUA, 1, key,
        str(try_amount),
        str(_IAP_VELOCITY_LIMIT_TRY),
        str(_IAP_VELOCITY_TTL_SEC),
    )
    if result == -1:
        logger.warning("[VerifyPurchase] Velocity limit aşıldı | device=%s", device_id)
        raise BadRequestException(code="IAP_VELOCITY_LIMIT_EXCEEDED")


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
        # try_amount <= 0 gelirse product_id bazlı fallback fiyat tablosu kullanılır
        # — direkt API çağrısıyla velocity bypass'ı önlenir
        if device_id:
            effective_try_amount = (
                try_amount if try_amount > 0
                else _PRODUCT_TRY_PRICES.get(result.product_id, 0.0)
            )
            if effective_try_amount > 0:
                try:
                    from app.utils.redis_client import get_redis
                    redis = await get_redis()
                    await _check_velocity(redis, device_id, effective_try_amount)
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
