from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.enums import ListingStatus

logger = get_logger(__name__)

class DeleteListingCommand:
    """CQRS Command: Bir ilanı siler (soft delete)."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, user_id: int) -> dict:
        logger.info("[DeleteListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, user_id)

        async with self.uow:
            listing = await self.uow.listings.get(listing_id)
            if not listing or listing.status == ListingStatus.DELETED:
                logger.warning("[DeleteListingCommand] İlan bulunamadı veya silinmiş | listing_id=%s", listing_id)
                raise NotFoundException("İlan bulunamadı")

            if listing.user_id != user_id:
                logger.warning("[DeleteListingCommand] Yetkisiz erişim | listing_id=%s user_id=%s", listing_id, user_id)
                raise BadRequestException("Bu ilanı silme yetkiniz yok")

            listing.status = ListingStatus.DELETED
            # TODO: EventBus publish ListingDeletedEvent

        logger.info("[DeleteListingCommand] Başarılı | listing_id=%s", listing_id)
        return {"id": listing_id, "status": "deleted"}
