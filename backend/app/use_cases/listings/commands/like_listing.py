from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.enums import ListingStatus

logger = get_logger(__name__)

class LikeListingCommand:
    """CQRS Command: Bir ilanı favorilere ekler veya çıkarır (Toggle)."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, user_id: int) -> dict:
        logger.info("[LikeListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, user_id)

        from app.models.favorite import Favorite

        async with self.uow:
            listing = await self.uow.listings.get(listing_id)
            if not listing or listing.status != ListingStatus.ACTIVE:
                logger.warning("[LikeListingCommand] İlan aktif değil veya bulunamadı | listing_id=%s", listing_id)
                raise NotFoundException("İlan bulunamadı veya aktif değil")

            if listing.user_id == user_id:
                logger.warning("[LikeListingCommand] Kendi ilanını beğenme engellendi | listing_id=%s", listing_id)
                raise BadRequestException("Kendi ilanınızı favorilere ekleyemezsiniz")

            # Mevcut favori kontrolü (Repository üzerinden yapılmalı ancak şimdilik doğrudan)
            # Normalde: await self.uow.favorites.get_by_user_and_listing(user_id, listing_id)
            from sqlalchemy import select
            stmt = select(Favorite).where(Favorite.user_id == user_id, Favorite.listing_id == listing_id)
            result = await self.uow.session.execute(stmt)
            favorite = result.scalar_one_or_none()

            action = "liked"
            if favorite:
                await self.uow.session.delete(favorite)
                action = "unliked"
                logger.info("[LikeListingCommand] Favoriden çıkarıldı | listing_id=%s", listing_id)
            else:
                new_fav = Favorite(user_id=user_id, listing_id=listing_id)
                self.uow.session.add(new_fav)
                logger.info("[LikeListingCommand] Favoriye eklendi | listing_id=%s", listing_id)

            # TODO: EventBus publish ListingLikedEvent

        return {"id": listing_id, "action": action}
