from __future__ import annotations
import json

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger

logger = get_logger(__name__)

_REDIS_KEY_CASHOUT = "teqlif:config:cashout_enabled"
_REDIS_KEY_TRY_RATE = "teqlif:config:teqlik_try_rate"
_DB_FALLBACK_RATE = 0.50  # platform_config seed değeri


class GetWalletSummaryQuery:
    """GET /api/wallet/summary — bakiye + kazanç + OTA flag."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int) -> dict:
        # ── teqlik_balance ─────────────────────────────────────────────────────
        user_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = :uid"),
            {"uid": user_id},
        )
        teqlik_balance = user_row.scalar() or 0

        # ── user_wallet_earnings ───────────────────────────────────────────────
        earn_row = await self._session.execute(
            text(
                "SELECT pending, available FROM user_wallet_earnings "
                "WHERE user_id = :uid"
            ),
            {"uid": user_id},
        )
        earn = earn_row.fetchone()
        earnings_pending   = earn[0] if earn else 0
        earnings_available = earn[1] if earn else 0

        # ── cashout_enabled + try_rate (Redis → fallback DB) ──────────────────
        cashout_enabled = False
        try_rate = _DB_FALLBACK_RATE

        try:
            from app.utils.redis_client import get_redis
            redis = await get_redis()

            cashout_val = await redis.get(_REDIS_KEY_CASHOUT)
            if cashout_val is not None:
                cashout_enabled = str(cashout_val) == "1"

            rate_val = await redis.get(_REDIS_KEY_TRY_RATE)
            if rate_val is not None:
                parsed = json.loads(rate_val)
                try_rate = float(parsed.get("rate", _DB_FALLBACK_RATE))
            else:
                # Redis miss → DB fallback
                db_rate = await self._session.execute(
                    text(
                        "SELECT value FROM platform_config "
                        "WHERE key = 'teqlik_try_rate' LIMIT 1"
                    )
                )
                row = db_rate.fetchone()
                if row:
                    try_rate = float(row[0].get("rate", _DB_FALLBACK_RATE))

        except Exception as exc:
            logger.warning(
                "[WalletSummary] Redis/DB config okunamadı, fallback kullanılıyor | %s", exc
            )

        return {
            "teqlik_balance": teqlik_balance,
            "earnings_pending_teqlik": earnings_pending,
            "earnings_available_teqlik": earnings_available,
            "try_rate": try_rate,
            "cashout_enabled": cashout_enabled,
        }
