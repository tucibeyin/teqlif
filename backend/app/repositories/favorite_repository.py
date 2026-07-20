from sqlalchemy.ext.asyncio import AsyncSession
from app.models.favorite import Favorite
from app.repositories.base_repository import BaseRepository

class FavoriteRepository(BaseRepository[Favorite]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Favorite, session)
