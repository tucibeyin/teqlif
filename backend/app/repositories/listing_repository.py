from sqlalchemy.ext.asyncio import AsyncSession
from app.models.listing import Listing
from app.repositories.base_repository import BaseRepository

class ListingRepository(BaseRepository[Listing]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Listing, session)

