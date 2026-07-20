from sqlalchemy.ext.asyncio import AsyncSession
from app.models.message import Message
from app.repositories.base_repository import BaseRepository

class MessageRepository(BaseRepository[Message]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Message, session)

