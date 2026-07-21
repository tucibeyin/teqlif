from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException

logger = get_logger(__name__)

class CreateStoryCommand:
    """CQRS Command: Kullanıcı yeni bir hikaye paylaşır."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: int, media_url: str, caption: Optional[str] = None) -> dict:
        logger.info("[CreateStoryCommand] Başlatıldı | user_id=%s", user_id)

        if not media_url.strip():
            logger.warning("[CreateStoryCommand] Medya URL eksik | user_id=%s", user_id)
            raise BadRequestException("Hikaye için medya URL'si zorunludur")

        async with self.uow:
            story_data = {
                "user_id": user_id,
                "media_url": media_url,
                "caption": caption
            }
            
            new_story = await self.uow.stories.create(obj_in=story_data)
            # TODO: EventBus publish StoryCreatedEvent

        logger.info("[CreateStoryCommand] Başarılı | story_id=%s", new_story.id)
        return {"id": new_story.id, "status": "created"}
