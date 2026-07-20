from sqlalchemy.ext.asyncio import AsyncSession
from app.models.story import Story
from app.repositories.base_repository import BaseRepository

class StoryRepository(BaseRepository[Story]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Story, session)
