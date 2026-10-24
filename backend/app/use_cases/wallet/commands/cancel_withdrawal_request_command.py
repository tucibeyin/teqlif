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
        row = await self._session.execute(
            text(
                "SELECT user_id, teqlik_amount, status "
                "FROM withdrawal_requests WHERE id = :rid"
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

        # available iade + status güncelleme — aynı transaction
        await self._session.execute(
            text(
                "UPDATE user_wallet_earnings "
                "SET available = available + :amt, updated_at = NOW() "
                "WHERE user_id = :uid"
            ),
            {"amt": teqlik_amount, "uid": user_id},
        )
        await self._session.execute(
            text(
                "UPDATE withdrawal_requests "
                "SET status = 'cancelled', cancelled_at = NOW() "
                "WHERE id = :rid"
            ),
            {"rid": request_id},
        )

        logger.info(
            "[Withdrawal] İptal edildi | user=%s request=%s teqlik=%s iade",
            user_id, request_id, teqlik_amount,
        )
        return {"request_id": request_id, "status": "cancelled", "teqlik_refunded": teqlik_amount}
