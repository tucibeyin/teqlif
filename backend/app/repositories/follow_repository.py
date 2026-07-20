from sqlalchemy.ext.asyncio import AsyncSession
from app.models.follow import Follow
from app.repositories.base_repository import BaseRepository

class FollowRepository(BaseRepository[Follow]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Follow, session)
