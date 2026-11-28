from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestException
from app.core.logger import get_logger
from app.models.user import User
from app.services.subscription.tier import TEQLIK_PER_STREAM_MINUTE
from app.models.wallet_ledger import WalletLedger

logger = get_logger(__name__)


@dataclass
class ConversionResult:
    spent_teqlik: int
    added_minutes: int
    new_balance: int
    new_bonus_minutes: int


class ConvertStreamMinutesCommand:
    """CQRS Command: Teqlik bakiyesini bonus yayın dakikasına dönüştürür.

    Atomiklik: SELECT ... FOR UPDATE ile row lock alınır; teqlik düşme ve
    bonus dakika artışı tek transaction içinde gerçekleşir.
    Bonus dakikalar aylık reset'e dahil değildir — kullanıcı teqlik ödemiştir.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def execute(self, user_id: int, minutes: int) -> ConversionResult:
        if minutes <= 0:
            raise BadRequestException(code="INVALID_CONVERSION_AMOUNT")

        cost = minutes * TEQLIK_PER_STREAM_MINUTE

        # FOR UPDATE: eş zamanlı dönüşüm yarışını önler
        result = await self._session.execute(
            select(User).where(User.id == user_id).with_for_update()
        )
        user = result.scalar_one_or_none()
        if user is None:
            raise BadRequestException(code="USER_NOT_FOUND")

        if user.teqlik_balance < cost:
            raise BadRequestException(code="INSUFFICIENT_TEQLIK")

        user.teqlik_balance -= cost
        user.stream_minutes_bonus += minutes

        await self._session.flush()

        # Audit: wallet ledger'a yaz
        self._session.add(
            WalletLedger(
                user_id=user_id,
                delta_teqlik=-cost,
                balance_after=user.teqlik_balance,
                tx_type="spend_stream_minutes",
                reference_id=minutes,
                reference_type="stream_minute_bonus",
            )
        )

        logger.info(
            "[ConvertStreamMinutes] user_id=%s dakika=%s maliyet=%s yeni_bakiye=%s bonus=%s",
            user_id, minutes, cost, user.teqlik_balance, user.stream_minutes_bonus,
        )

        return ConversionResult(
            spent_teqlik=cost,
            added_minutes=minutes,
            new_balance=user.teqlik_balance,
            new_bonus_minutes=user.stream_minutes_bonus,
        )
