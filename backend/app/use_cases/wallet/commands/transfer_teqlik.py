from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, ForbiddenException, InsufficientFundsException, NotFoundException
from app.models.teqlik_transaction import TeqlikTransaction  # noqa: F401

logger = get_logger(__name__)

class TransferTeqlikCommand:
    """CQRS Command: Kullanıcılar arası teqlik (bakiye) transferi yapar."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, sender_id: int, receiver_id: int, amount: int) -> dict:
        logger.info("[TransferTeqlikCommand] Başlatıldı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)

        if amount <= 0:
            logger.warning("[TransferTeqlikCommand] Geçersiz miktar | amount=%s", amount)
            raise BadRequestException(code="TRANSFER_AMOUNT_POSITIVE")

        if sender_id == receiver_id:
            logger.warning("[TransferTeqlikCommand] Kendine transfer hatası | sender=%s", sender_id)
            raise ForbiddenException(code="SELF_TRANSFER_FORBIDDEN")

        async with self.uow:
            sender = await self.uow.users.get(id=sender_id)
            if sender is None:
                raise NotFoundException(code="SENDER_NOT_FOUND")
            if sender.teqlik_balance < amount:
                raise InsufficientFundsException()

            t1_data = {"user_id": sender_id, "amount": -amount, "transaction_type": "transfer_out", "reference_id": receiver_id}
            t2_data = {"user_id": receiver_id, "amount": amount, "transaction_type": "transfer_in", "reference_id": sender_id}

            await self.uow.transactions.create(obj_in=t1_data)
            await self.uow.transactions.create(obj_in=t2_data)

        logger.info("[TransferTeqlikCommand] Başarılı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)
        return {"status": "success", "amount": amount}
