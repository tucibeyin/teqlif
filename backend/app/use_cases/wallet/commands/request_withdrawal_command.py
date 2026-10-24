from __future__ import annotations
import json
from decimal import Decimal

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException, ConflictException, ForbiddenException
from app.core.logger import get_logger

logger = get_logger(__name__)

_REDIS_KEY_CASHOUT   = "teqlif:config:cashout_enabled"
_REDIS_KEY_TRY_RATE  = "teqlif:config:teqlik_try_rate"
_DEFAULT_TRY_RATE    = Decimal("0.50")
_DEFAULT_MIN_WITHDRAWAL = Decimal("500.00")


async def _get_platform_config(session: AsyncSession, redis) -> tuple[bool, Decimal, Decimal]:
    """(cashout_enabled, try_rate, min_withdrawal_try) döner."""
    cashout_enabled = False
    try_rate = _DEFAULT_TRY_RATE
    min_withdrawal = _DEFAULT_MIN_WITHDRAWAL

    try:
        if redis:
            val = await redis.get(_REDIS_KEY_CASHOUT)
            if val is not None:
                cashout_enabled = str(val) == "1"

            rate_val = await redis.get(_REDIS_KEY_TRY_RATE)
            if rate_val:
                try_rate = Decimal(str(json.loads(rate_val).get("rate", _DEFAULT_TRY_RATE)))
    except Exception:
        pass

    if not cashout_enabled or try_rate == _DEFAULT_TRY_RATE:
        rows = await session.execute(
            text(
                "SELECT key, value FROM platform_config "
                "WHERE key IN ('teqlik_try_rate', 'cashout_enabled', 'min_withdrawal_try')"
            )
        )
        for key, value in rows.fetchall():
            if key == "cashout_enabled":
                cashout_enabled = bool(value.get("enabled", False))
            elif key == "teqlik_try_rate":
                try_rate = Decimal(str(value.get("rate", _DEFAULT_TRY_RATE)))
            elif key == "min_withdrawal_try":
                min_withdrawal = Decimal(str(value.get("try", _DEFAULT_MIN_WITHDRAWAL)))

    return cashout_enabled, try_rate, min_withdrawal


class RequestWithdrawalCommand:
    """POST /api/wallet/withdraw — available atomik düşüm + kurları kilitle."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(
        self,
        user_id: int,
        teqlik_amount: int,
        currency: str,
        iban: str,
        account_holder: str,
    ) -> dict:
        try:
            from app.utils.redis_client import get_redis
            redis = await get_redis()
        except Exception:
            redis = None

        cashout_enabled, try_rate, min_withdrawal = await _get_platform_config(
            self._session, redis
        )

        if not cashout_enabled:
            raise ForbiddenException(code="CASHOUT_NOT_ENABLED")

        try_amount = Decimal(teqlik_amount) * try_rate
        if try_amount < min_withdrawal:
            raise BadRequestException(code="BELOW_MIN_WITHDRAWAL")

        # Aktif pending talep kontrolü
        pending_row = await self._session.execute(
            text(
                "SELECT id FROM withdrawal_requests "
                "WHERE user_id = :uid AND status = 'pending' LIMIT 1"
            ),
            {"uid": user_id},
        )
        if pending_row.fetchone():
            raise ConflictException(code="WITHDRAWAL_PENDING_EXISTS")

        # TCMB kuru (eğer TRY ise NULL)
        tcmb_rate = None
        fiat_amount = try_amount

        if currency != "TRY":
            # ExchangeRates tablosundan anlık kur al
            rate_row = await self._session.execute(
                text(
                    "SELECT rate FROM exchange_rates "
                    "WHERE base = 'TRY' AND target = :cur "
                    "ORDER BY fetched_at DESC LIMIT 1"
                ),
                {"cur": currency},
            )
            rate_r = rate_row.fetchone()
            if rate_r is None:
                raise BadRequestException(code="UNSUPPORTED_CURRENCY")
            tcmb_rate = Decimal(str(rate_r[0]))
            fiat_amount = try_amount / tcmb_rate

        # Atomik bakiye düşümü — double-spend önlemi
        deduct = await self._session.execute(
            text(
                "UPDATE user_wallet_earnings "
                "SET available = available - :amt, updated_at = NOW() "
                "WHERE user_id = :uid AND available >= :amt "
                "RETURNING available"
            ),
            {"amt": teqlik_amount, "uid": user_id},
        )
        if deduct.fetchone() is None:
            raise BadRequestException(code="INSUFFICIENT_AVAILABLE_BALANCE")

        # withdrawal_requests INSERT — kurlar aynı transaction'da kilitlenir
        result = await self._session.execute(
            text(
                "INSERT INTO withdrawal_requests "
                "(user_id, teqlik_amount, try_amount, currency, fiat_amount, "
                " try_rate_used, tcmb_rate_used, iban, account_holder, status) "
                "VALUES (:uid, :teqlik, :try_amt, :currency, :fiat, "
                "        :try_rate, :tcmb_rate, :iban, :holder, 'pending') "
                "RETURNING id"
            ),
            {
                "uid": user_id,
                "teqlik": teqlik_amount,
                "try_amt": try_amount,
                "currency": currency,
                "fiat": fiat_amount,
                "try_rate": try_rate,
                "tcmb_rate": tcmb_rate,
                "iban": iban,
                "holder": account_holder,
            },
        )
        request_id = result.fetchone()[0]

        logger.info(
            "[Withdrawal] Talep oluşturuldu | user=%s teqlik=%s try=%.2f currency=%s",
            user_id, teqlik_amount, float(try_amount), currency,
        )
        return {
            "request_id": request_id,
            "teqlik_amount": teqlik_amount,
            "try_amount": float(try_amount),
            "fiat_amount": float(fiat_amount),
            "currency": currency,
            "status": "pending",
        }
