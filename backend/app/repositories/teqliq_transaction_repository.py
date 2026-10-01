from sqlalchemy.ext.asyncio import AsyncSession
from app.models.teqliq_transaction import teqliqTransaction
from app.repositories.base_repository import BaseRepository

class teqliqTransactionRepository(BaseRepository[teqliqTransaction]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(teqliqTransaction, session)

teqliqTransactionRepository = teqliqTransactionRepository  # backward-compat alias
