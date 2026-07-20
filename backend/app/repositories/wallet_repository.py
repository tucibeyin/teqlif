from sqlalchemy.ext.asyncio import AsyncSession
# Tuci cüzdanı vs. normal cüzdanı modellerine göre adlandırılır. 
# Örnekte model adını Wallet varsayıyoruz. 
from app.database import Base # placeholder
# from app.models.wallet import Wallet # Gerçek model

# Stub class
class Wallet(Base):
    __tablename__ = "dummy_wallets"
    pass

from app.repositories.base_repository import BaseRepository

class WalletRepository(BaseRepository[Wallet]):
    def __init__(self, session: AsyncSession = None):
        super().__init__(Wallet, session)
