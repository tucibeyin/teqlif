from __future__ import annotations
import json

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger import get_logger

logger = get_logger(__name__)

_REDIS_KEY_CASHOUT = "teqlif:config:cashout_enabled"
_REDIS_KEY_TRY_RATE = "teqlif:config:teqlik_try_rate"
_DB_FALLBACK_RATE = 0.50  # platform_config seed değeri

# DB'deki plan_type → IAP product ID dönüşümü
_PLAN_TYPE_TO_IAP = {
    'monthly':   'teqlif_pro_1m',
    'quarterly': 'teqlif_pro_3m',
    'biannual':  'teqlif_pro_6m',
    'annual':    'teqlif_pro_12m',
}


class GetWalletSummaryQuery:
    """GET /api/wallet/summary — bakiye + kazanç + OTA flag."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int) -> dict:
        # ── kullanıcı temel alanları ───────────────────────────────────────────
        user_row = await self._session.execute(
            text(
                "SELECT teqlik_balance, user_type, pro_expires_at, plan_type "
                "FROM users WHERE id = :uid"
            ),
            {"uid": user_id},
        )
        u = user_row.fetchone()
        teqlik_balance   = u[0] if u else 0
        is_pro           = (u[1] == "pro") if u else False
        pro_expires_at   = u[2].isoformat() if u and u[2] else None
        plan_type        = _PLAN_TYPE_TO_IAP.get(u[3]) if u and u[3] else None

        # ── aktif çekim talebi ────────────────────────────────────────────────
        wr_row = await self._session.execute(
            text(
                "SELECT id FROM withdrawal_requests "
                "WHERE user_id = :uid AND status = 'pending' "
                "ORDER BY created_at DESC LIMIT 1"
            ),
            {"uid": user_id},
        )
        active_withdrawal_id = wr_row.scalar()

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
            "is_pro": is_pro,
            "pro_expires_at": pro_expires_at,
            "plan_type": plan_type,
            "active_withdrawal_id": active_withdrawal_id,
        }
