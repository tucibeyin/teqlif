from sqlalchemy.ext.asyncio import AsyncSession
from app.models.tuci_transaction import TeqlikTransaction
from app.repositories.base_repository import BaseRepository

class TeqlikTransactionRepository(BaseRepository[TeqlikTransaction]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(TeqlikTransaction, session)

TuciTransactionRepository = TeqlikTransactionRepository  # backward-compat alias
