from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError

from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException

logger = get_logger(__name__)

class SendDirectMessageCommand:
    """
    Direct Message (Özel Mesaj) gönderme Command'ı.
    Sadece Unit of Work alır. Veritabanına yazar ve EventBus'a sinyal yollar.
    """
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, sender_id: int, receiver_id: int, content: str, content_type: str = "text") -> dict:
        logger.info("[SendDirectMessageCommand] İşlem başladı | sender=%s receiver=%s", sender_id, receiver_id)

        if not content or not content.strip():
            logger.warning("[SendDirectMessageCommand] Boş mesaj | sender=%s", sender_id)
            raise BadRequestException("Mesaj içeriği boş olamaz")

        if sender_id == receiver_id:
            logger.warning("[SendDirectMessageCommand] Kendine mesaj atma | sender=%s", sender_id)
            raise BadRequestException("Kendinize mesaj gönderemezsiniz")

        # Gerçekte EventBus'ı da inject edebiliriz
        from app.core.event_bus import event_bus
        from app.core.events import DirectMessageCreatedEvent

        async with self.uow:
            # 1. Receiver var mı kontrolü
            receiver = await self.uow.users.get(receiver_id)
            if not receiver:
                raise NotFoundException("Alıcı bulunamadı")

            # 2. Mesaj oluştur ve repoya ekle
            msg_data = {
                "sender_id": sender_id,
                "receiver_id": receiver_id,
                "content": content,
                "content_type": content_type
            }
            # dict veya kwargs ile create metodu
            new_message = await self.uow.messages.create(obj_in=msg_data)
            
            # Commit
            await self.uow.commit()

            # Event fırlat (Okuma modellerinin (Queries/Projectors) haberdar olması için)
            event_bus.publish(
                DirectMessageCreatedEvent(
                    message_id=new_message.id,
                    sender_id=sender_id,
                    receiver_id=receiver_id,
                    content=content
                )
            )

        logger.info("[SendDirectMessageCommand] Başarılı | message_id=%s", new_message.id)
        return {"id": new_message.id, "status": "sent"}
