from sqlalchemy.ext.asyncio import AsyncSession
from app.models.stream import LiveStream
from app.repositories.base_repository import BaseRepository

class StreamRepository(BaseRepository[LiveStream]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(LiveStream, session)

