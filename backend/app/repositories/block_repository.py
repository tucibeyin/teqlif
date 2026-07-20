from sqlalchemy.ext.asyncio import AsyncSession
from app.models.block import Block
from app.repositories.base_repository import BaseRepository

class BlockRepository(BaseRepository[Block]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Block, session)
