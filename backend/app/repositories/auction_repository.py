from sqlalchemy.ext.asyncio import AsyncSession
from app.models.auction import Auction
from app.repositories.base_repository import BaseRepository

class AuctionRepository(BaseRepository[Auction]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Auction, session)
