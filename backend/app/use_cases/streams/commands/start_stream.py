from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException
from app.models.enums import StreamStatus

logger = get_logger(__name__)

class StartStreamCommand:
    """CQRS Command: Kullanıcı canlı yayın başlatır."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: int, title: str) -> dict:
        logger.info("[StartStreamCommand] Başlatıldı | user_id=%s title=%s", user_id, title)
        
        if not title.strip():
            logger.warning("[StartStreamCommand] Boş yayın başlığı | user_id=%s", user_id)
            raise BadRequestException("Yayın başlığı boş olamaz")

        async with self.uow:
            # 1. Kullanıcının halihazırda açık yayını var mı kontrolü
            # existing = await self.uow.streams.get_active_stream(user_id) vs.
            
            stream_data = {
                "user_id": user_id,
                "title": title.strip(),
                "status": StreamStatus.LIVE
            }
            new_stream = await self.uow.streams.create(obj_in=stream_data)
            
            from app.core.event_bus import event_bus
            from app.core.events import StreamStartedEvent
            
            event_bus.publish(
                StreamStartedEvent(
                    stream_id=new_stream.id,
                    user_id=user_id,
                    title=title
                )
            )
            
            await self.uow.commit()

        logger.info("[StartStreamCommand] Başarılı | stream_id=%s", new_stream.id)
        return {"id": new_stream.id, "status": "live"}
