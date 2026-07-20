from sqlalchemy.ext.asyncio import AsyncSession
from app.models.tuci_transaction import TuciTransaction
from app.repositories.base_repository import BaseRepository

class TuciTransactionRepository(BaseRepository[TuciTransaction]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(TuciTransaction, session)
