import abc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import SQLAlchemyError

from app.database import AsyncSessionLocal
from app.repositories.user_repository import UserRepository
from app.core.exceptions import DatabaseException, AppException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


class AbstractUnitOfWork(abc.ABC):
    users: UserRepository

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, traceback):
        if exc_type is not None:
            await self.rollback()
            if issubclass(exc_type, AppException):
                return False
            if issubclass(exc_type, SQLAlchemyError):
                logger.error("[UoW] Database transaction failed: %s", exc_val, exc_info=(exc_type, exc_val, traceback))
                capture_exception(exc_val)
                raise DatabaseException(code="DB_OPERATION_FAILED")
            logger.error("[UoW] Unexpected transaction error: %s", exc_val, exc_info=(exc_type, exc_val, traceback))
            capture_exception(exc_val)
            return False
        else:
            await self.commit()

    @abc.abstractmethod
    async def commit(self):
        raise NotImplementedError

    @abc.abstractmethod
    async def rollback(self):
        raise NotImplementedError


class SqlAlchemyUnitOfWork(AbstractUnitOfWork):
    def __init__(self, session_factory=AsyncSessionLocal):
        self.session_factory = session_factory
        self.session: AsyncSession = None
        self._owns_session = True  # __aexit__ session'ı kapatır

    # ── Repository binding ────────────────────────────────────────────────────

    def _bind_repos(self):
        """Mevcut session'a tüm repository'leri bağlar."""
        from app.repositories.listing_repository import ListingRepository
        from app.repositories.stream_repository import StreamRepository
        from app.repositories.message_repository import MessageRepository
        from app.repositories.favorite_repository import FavoriteRepository
        from app.repositories.category_repository import CategoryRepository
        from app.repositories.auction_repository import AuctionRepository
        from app.repositories.bid_repository import BidRepository
        from app.repositories.tuci_transaction_repository import TuciTransactionRepository
        from app.repositories.user_repository import UserRepository
        from app.repositories.follow_repository import FollowRepository
        from app.repositories.block_repository import BlockRepository
        from app.repositories.story_repository import StoryRepository
        from app.repositories.ad_campaign_repository import AdCampaignRepository

        self.listings = ListingRepository(self.session)
        self.streams = StreamRepository(self.session)
        self.messages = MessageRepository(self.session)
        self.favorites = FavoriteRepository(self.session)
        self.categories = CategoryRepository(self.session)
        self.auctions = AuctionRepository(self.session)
        self.bids = BidRepository(self.session)
        self.transactions = TuciTransactionRepository(self.session)
        self.users = UserRepository(self.session)
        self.follows = FollowRepository(self.session)
        self.blocks = BlockRepository(self.session)
        self.stories = StoryRepository(self.session)
        self.ads = AdCampaignRepository(self.session)

    @classmethod
    def from_session(cls, session: AsyncSession) -> "SqlAlchemyUnitOfWork":
        """
        Router'dan enjekte edilen mevcut bir session'ı sarar.

        Session yaşam döngüsü (commit/close) get_uow tarafından yönetilir;
        bu UoW yalnızca repository erişimi sağlar. __aexit__ session'ı kapatmaz.
        """
        uow = object.__new__(cls)
        uow.session = session
        uow.session_factory = lambda: session
        uow._owns_session = False  # session get_uow tarafından kapatılır
        uow._bind_repos()
        return uow

    # ── Context manager ───────────────────────────────────────────────────────

    async def __aenter__(self):
        self.session = self.session_factory()
        self._bind_repos()
        await super().__aenter__()
        return self

    async def __aexit__(self, exc_type, exc_val, traceback):
        try:
            await super().__aexit__(exc_type, exc_val, traceback)
        finally:
            if self._owns_session:
                await self.session.close()

    async def commit(self):
        await self.session.commit()

    async def rollback(self):
        await self.session.rollback()
