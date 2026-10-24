"""W12 — Admin çekim talebi onay / red işlemi.

Onay (approve): withdrawal_requests.status='approved' + processed_at=NOW()
Red  (reject):  withdrawal_requests.status='rejected' + processed_at=NOW()
               + user_wallet_earnings.available += teqlik_amount (geri iade)
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictException, NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)

_VALID_ACTIONS = {"approve", "reject"}


class ProcessWithdrawalCommand:
    """Admin: POST /api/admin-data/wallet/withdrawals/{id}/process"""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(
        self,
        request_id: int,
        action: str,
        admin_note: str | None = None,
    ) -> dict:
        if action not in _VALID_ACTIONS:
            from app.core.exceptions import BadRequestException
            raise BadRequestException(code="INVALID_WITHDRAWAL_ACTION")

        row = await self._session.execute(
            text(
                "SELECT id, user_id, teqlik_amount, status "
                "FROM withdrawal_requests WHERE id = :rid"
            ),
            {"rid": request_id},
        )
        request = row.fetchone()
        if request is None:
            raise NotFoundException(code="WITHDRAWAL_NOT_FOUND")

        _id, user_id, teqlik_amount, current_status = request

        if current_status != "pending":
            raise ConflictException(code="WITHDRAWAL_NOT_PENDING")

        new_status = "approved" if action == "approve" else "rejected"

        await self._session.execute(
            text(
                "UPDATE withdrawal_requests "
                "SET status = :status, processed_at = NOW(), admin_note = :note "
                "WHERE id = :rid"
            ),
            {"status": new_status, "note": admin_note, "rid": request_id},
        )

        if action == "reject":
            await self._session.execute(
                text(
                    "UPDATE user_wallet_earnings "
                    "SET available = available + :amt, updated_at = NOW() "
                    "WHERE user_id = :uid"
                ),
                {"amt": teqlik_amount, "uid": user_id},
            )
            logger.info(
                "[Withdrawal] Reddedildi | request=%s user=%s teqlik=%s iade",
                request_id, user_id, teqlik_amount,
            )
        else:
            logger.info(
                "[Withdrawal] Onaylandı | request=%s user=%s teqlik=%s",
                request_id, user_id, teqlik_amount,
            )

        return {
            "request_id": request_id,
            "status": new_status,
            "user_id": user_id,
            "teqlik_amount": teqlik_amount,
        }
