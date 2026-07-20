from sqlalchemy.ext.asyncio import AsyncSession
from app.models.block import UserBlock
from app.repositories.base_repository import BaseRepository

class BlockRepository(BaseRepository[UserBlock]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(UserBlock, session)
