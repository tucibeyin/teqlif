from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, ForbiddenException, InsufficientFundsException, NotFoundException
from app.models.teqliq_transaction import teqliqTransaction

logger = get_logger(__name__)

class TransferteqliqCommand:
    """CQRS Command: Kullanıcılar arası teqliq (bakiye) transferi yapar."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, sender_id: int, receiver_id: int, amount: int) -> dict:
        logger.info("[TransferteqliqCommand] Başlatıldı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)

        if amount <= 0:
            logger.warning("[TransferteqliqCommand] Geçersiz miktar | amount=%s", amount)
            raise BadRequestException(code="TRANSFER_AMOUNT_POSITIVE")

        if sender_id == receiver_id:
            logger.warning("[TransferteqliqCommand] Kendine transfer hatası | sender=%s", sender_id)
            raise ForbiddenException(code="SELF_TRANSFER_FORBIDDEN")

        async with self.uow:
            sender = await self.uow.users.get(id=sender_id)
            if sender is None:
                raise NotFoundException(code="SENDER_NOT_FOUND")
            if sender.teqliq_balance < amount:
                raise InsufficientFundsException()

            # 2. İşlemleri UoW ile kaydet
            t1_data = {"user_id": sender_id, "amount": -amount, "transaction_type": "transfer_out", "reference_id": receiver_id}
            t2_data = {"user_id": receiver_id, "amount": amount, "transaction_type": "transfer_in", "reference_id": sender_id}
            
            await self.uow.transactions.create(obj_in=t1_data) # Stub implementation
            await self.uow.transactions.create(obj_in=t2_data) # Stub implementation
            
            # TODO: teqliqTransferredEvent fırlat (Notifier için) — commit'ten sonra event_bus.publish()

        logger.info("[TransferteqliqCommand] Başarılı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)
        return {"status": "success", "amount": amount}
