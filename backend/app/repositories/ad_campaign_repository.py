from sqlalchemy.ext.asyncio import AsyncSession
from app.models.ad_campaign import AdCampaign
from app.repositories.base_repository import BaseRepository

class AdCampaignRepository(BaseRepository[AdCampaign]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(AdCampaign, session)
