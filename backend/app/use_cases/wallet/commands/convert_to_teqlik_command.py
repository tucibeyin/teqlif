from __future__ import annotations
import math

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException
from app.core.logger import get_logger

logger = get_logger(__name__)

_BONUS_PCT = 0.10   # +%10 bonus (Seçenek C)


class ConvertToTeqlikCommand:
    """POST /api/wallet/convert-to-teqlik — Seçenek C, +%10 bonus.

    Kapalı döngü dönüşüm: available → teqlik_balance; nakde geri çevrilemez.
    cashout_enabled flag'inden bağımsız — yayıncının kazancıdır, çekim değil.
    wallet_ledger 3 satır:
      1. user: -teqlik_amount (convert_to_teqlik, available çıkışı)
      2. user: +total_teqlik  (convert_to_teqlik, balance girişi)
      3. id=0: -bonus_teqlik  (bonus_mint, sistem "basar")
    Delta toplamı: -amount + (amount + bonus) - bonus = 0 ✓
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int, teqlik_amount: int) -> dict:
        if teqlik_amount <= 0:
            raise BadRequestException(code="CONVERT_AMOUNT_POSITIVE")

        bonus_teqlik = math.floor(teqlik_amount * _BONUS_PCT)
        total_teqlik = teqlik_amount + bonus_teqlik

        # Atomik available düşümü
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

        # teqlik_balance artırımı
        bal_row = await self._session.execute(
            text(
                "UPDATE users SET teqlik_balance = teqlik_balance + :total "
                "WHERE id = :uid RETURNING teqlik_balance"
            ),
            {"total": total_teqlik, "uid": user_id},
        )
        new_balance = bal_row.fetchone()[0]

        # wallet_ledger — 3 satır
        prev_balance = new_balance - total_teqlik
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type) "
                "VALUES (:uid, :delta, :bal, 'convert_to_teqlik')"
            ),
            {"uid": user_id, "delta": -teqlik_amount, "bal": prev_balance},
        )
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type) "
                "VALUES (:uid, :delta, :bal, 'convert_to_teqlik')"
            ),
            {"uid": user_id, "delta": total_teqlik, "bal": new_balance},
        )
        # Sistem (id=0) bonus mint — negatif (sistem basar)
        sys_bal_row = await self._session.execute(
            text("SELECT teqlik_balance FROM users WHERE id = 0")
        )
        sys_balance = sys_bal_row.scalar() or 0
        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type) "
                "VALUES (0, :delta, :bal, 'bonus_mint')"
            ),
            {"delta": -bonus_teqlik, "bal": sys_balance - bonus_teqlik},
        )

        logger.info(
            "[ConvertToTeqlik] user=%s amount=%s bonus=%s total=%s new_balance=%s",
            user_id, teqlik_amount, bonus_teqlik, total_teqlik, new_balance,
        )
        return {
            "teqlik_converted": teqlik_amount,
            "bonus_teqlik": bonus_teqlik,
            "total_teqlik_added": total_teqlik,
            "new_teqlik_balance": new_balance,
        }

