from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException
from app.models.enums import StreamStatus

logger = get_logger(__name__)

class StartStreamCommand:
    """CQRS Command: Kullanıcı canlı yayın başlatır."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: int, title: str, category: str = None, listing_id: int = None, thumbnail_url: str = None) -> dict:
        import uuid
        from app.config import settings
        from app.use_cases.streams.stream_utils import make_livekit_token

        logger.info("[StartStreamCommand] Başlatıldı | user_id=%s title=%s", user_id, title)
        
        if not title.strip():
            logger.warning("[StartStreamCommand] Boş yayın başlığı | user_id=%s", user_id)
            raise BadRequestException("Yayın başlığı boş olamaz")

        async with self.uow:
            user = await self.uow.users.get(user_id)
            if not user:
                raise BadRequestException("Kullanıcı bulunamadı")

            room_name = f"stream_{user_id}_{uuid.uuid4().hex[:8]}"

            stream_data = {
                "room_name": room_name,
                "host_id": user_id,
                "title": title.strip(),
                "is_live": False,
                "category": category if category else "diger",
                "thumbnail_url": thumbnail_url
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

        token = make_livekit_token(room_name, user, can_publish=True)
        logger.info("[StartStreamCommand] Başarılı | stream_id=%s", new_stream.id)
        
        return {
            "stream_id": new_stream.id,
            "room_name": room_name,
            "livekit_url": settings.livekit_url,
            "token": token,
            "category": category if category else "diger",
        }
