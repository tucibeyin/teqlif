import abc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import SQLAlchemyError

from app.database import AsyncSessionLocal
from app.repositories.user_repository import UserRepository, user_repository
from app.core.exceptions import DatabaseException, AppException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


class AbstractUnitOfWork(abc.ABC):
    """
    Unit of Work (UoW) için temel soyut sınıf.
    Repository'lere erişimi merkezi hale getirir ve transaction'ları yönetir.
    """
    users: UserRepository

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, traceback):
        if exc_type is not None:
            await self.rollback()
            # Eğer hata bilinen bir AppException ise onu olduğu gibi yukarı bırak.
            if issubclass(exc_type, AppException):
                return False  # Hatayı yutma, yeniden fırlat
            # Eğer SQLAlchemy / veritabanı kaynaklı bir hataysa logla ve DatabaseException fırlat
            if issubclass(exc_type, SQLAlchemyError):
                logger.error("[UoW] Database transaction failed: %s", exc_val, exc_info=(exc_type, exc_val, traceback))
                capture_exception(exc_val)
                raise DatabaseException("Veritabanı işlemi sırasında beklenmeyen bir hata oluştu")
            # Diğer hatalar için (örn. KeyError, ValueError vs.)
            logger.error("[UoW] Unexpected transaction error: %s", exc_val, exc_info=(exc_type, exc_val, traceback))
            capture_exception(exc_val)
            return False  # Yeniden fırlat
        else:
            await self.commit()

    @abc.abstractmethod
    async def commit(self):
        raise NotImplementedError

    @abc.abstractmethod
    async def rollback(self):
        raise NotImplementedError


class SqlAlchemyUnitOfWork(AbstractUnitOfWork):
    """
    SQLAlchemy'nin AsyncSession'ını sarmalayan somut UoW sınıfı.
    """
    def __init__(self, session_factory=AsyncSessionLocal):
        self.session_factory = session_factory
        self.session: AsyncSession = None

    async def __aenter__(self):
        self.session = self.session_factory()
        # Gelecekte eklenecek repoları burada inject edeceğiz:
        self.users = UserRepository(self.session)
        # Her repo'ya session vermek için BaseRepository yapısı update edilmelidir.
        # userRepository şimdilik db'yi argüman alıyordu, onu da düzenleyeceğiz.
        return super().__aenter__()

    async def __aexit__(self, exc_type, exc_val, traceback):
        try:
            await super().__aexit__(exc_type, exc_val, traceback)
        finally:
            await self.session.close()

    async def commit(self):
        await self.session.commit()

    async def rollback(self):
        await self.session.rollback()
