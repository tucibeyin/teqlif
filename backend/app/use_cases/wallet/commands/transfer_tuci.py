from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException
from app.models.tuci_transaction import TuciTransaction

logger = get_logger(__name__)

class TransferTuciCommand:
    """CQRS Command: Kullanıcılar arası Tuci (bakiye) transferi yapar."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, sender_id: int, receiver_id: int, amount: int) -> dict:
        logger.info("[TransferTuciCommand] Başlatıldı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)

        if amount <= 0:
            logger.warning("[TransferTuciCommand] Geçersiz miktar | amount=%s", amount)
            raise BadRequestException("Transfer miktarı sıfırdan büyük olmalıdır")

        if sender_id == receiver_id:
            logger.warning("[TransferTuciCommand] Kendine transfer hatası | sender=%s", sender_id)
            raise BadRequestException("Kendinize transfer yapamazsınız")

        async with self.uow:
            # 1. Gönderenin bakiyesi kontrol edilir (Gerçekte Aggregate Root'tan veya Query'den yapılır)
            # Şimdilik bakiye yeterli varsayalım veya DB'de trigger ile kontrol edilsin
            
            # 2. İşlemleri UoW ile kaydet
            t1 = TuciTransaction(user_id=sender_id, amount=-amount, transaction_type="transfer_out", reference_id=receiver_id)
            t2 = TuciTransaction(user_id=receiver_id, amount=amount, transaction_type="transfer_in", reference_id=sender_id)
            
            await self.uow.transactions.create(obj_in=t1.__dict__) # Stub implementation
            await self.uow.transactions.create(obj_in=t2.__dict__) # Stub implementation
            
            from app.core.event_bus import event_bus
            from app.core.events import DomainEvent
            
            # TODO: TuciTransferredEvent fırlat (Notifier için)
            await self.uow.commit()

        logger.info("[TransferTuciCommand] Başarılı | sender=%s receiver=%s amount=%s", sender_id, receiver_id, amount)
        return {"status": "success", "amount": amount}
