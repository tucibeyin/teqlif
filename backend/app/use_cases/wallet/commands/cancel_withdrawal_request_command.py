from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictException, ForbiddenException, NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)


class CancelWithdrawalRequestCommand:
    """DELETE /api/wallet/withdraw/{request_id} — pending talebi iptal et."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int, request_id: int) -> dict:
        # FOR UPDATE: satır kilidi — çift iptal ve approve-cancel yarışını önler
        row = await self._session.execute(
            text(
                "SELECT user_id, teqlik_amount, status "
                "FROM withdrawal_requests WHERE id = :rid FOR UPDATE"
            ),
            {"rid": request_id},
        )
        request = row.fetchone()
        if request is None:
            raise NotFoundException(code="WITHDRAWAL_NOT_FOUND")

        owner_id, teqlik_amount, status = request

        if owner_id != user_id:
            raise ForbiddenException(code="WITHDRAWAL_NOT_YOURS")

        if status != "pending":
            raise ConflictException(code="WITHDRAWAL_NOT_CANCELLABLE")

        # Atomik güncelleme: AND status='pending' — başka tx geçmişse RETURNING boş döner
        upd = await self._session.execute(
            text(
                "UPDATE withdrawal_requests "
                "SET status = 'cancelled', cancelled_at = NOW() "
                "WHERE id = :rid AND status = 'pending' RETURNING id"
            ),
            {"rid": request_id},
        )
        if upd.fetchone() is None:
            raise ConflictException(code="WITHDRAWAL_ALREADY_PROCESSED")

        # Yalnızca status değiştiyse iade et
        await self._session.execute(
            text(
                "UPDATE user_wallet_earnings "
                "SET available = available + :amt, updated_at = NOW() "
                "WHERE user_id = :uid"
            ),
            {"amt": teqlik_amount, "uid": user_id},
        )

        avail_after_row = await self._session.execute(
            text("SELECT available FROM user_wallet_earnings WHERE user_id = :uid"),
            {"uid": user_id},
        )
        avail_after = avail_after_row.fetchone()[0]

        await self._session.execute(
            text(
                "INSERT INTO wallet_ledger "
                "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
                "VALUES (:uid, :delta, :bal, 'withdrawal_cancelled', :ref_id, 'withdrawal_request')"
            ),
            {
                "uid": user_id,
                "delta": teqlik_amount,
                "bal": int(avail_after),
                "ref_id": request_id,
            },
        )

        logger.info(
            "[Withdrawal] İptal edildi | user=%s request=%s teqlik=%s iade",
            user_id, request_id, teqlik_amount,
        )
        return {"request_id": request_id, "status": "cancelled", "teqlik_refunded": teqlik_amount}
