from sqlalchemy.ext.asyncio import AsyncSession
from app.models.message import DirectMessage
from app.repositories.base_repository import BaseRepository

class MessageRepository(BaseRepository[DirectMessage]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(DirectMessage, session)

