from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, BadRequestException, ContentPolicyException
from app.core.auto_mod import analyze_listing_text

logger = get_logger(__name__)

class UpdateListingCommand:
    """CQRS Command: Mevcut bir ilanı günceller."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        listing_id: int,
        user_id: int,
        title: Optional[str] = None,
        description: Optional[str] = None,
        price: Optional[float] = None
    ) -> dict:
        logger.info("[UpdateListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, user_id)

        if title is not None and not title.strip():
            logger.warning("[UpdateListingCommand] Boş başlık hatası | listing_id=%s", listing_id)
            raise BadRequestException("İlan başlığı boş olamaz")

        if title or description:
            if analyze_listing_text(title or "", description or ""):
                logger.warning("[UpdateListingCommand] Uygunsuz içerik | listing_id=%s", listing_id)
                raise ContentPolicyException("Uygunsuz içerik tespit edildi")

        async with self.uow:
            listing = await self.uow.listings.get(listing_id)
            if not listing:
                logger.warning("[UpdateListingCommand] İlan bulunamadı | listing_id=%s", listing_id)
                raise NotFoundException("İlan bulunamadı")

            if listing.user_id != user_id:
                logger.warning("[UpdateListingCommand] Yetkisiz erişim | listing_id=%s user_id=%s", listing_id, user_id)
                raise BadRequestException("Bu ilanı güncelleme yetkiniz yok")

            if title is not None:
                listing.title = title.strip()
            if description is not None:
                listing.description = description.strip()
            if price is not None:
                listing.price = price

            # TODO: EventBus publish ListingUpdatedEvent

        logger.info("[UpdateListingCommand] Başarılı | listing_id=%s", listing_id)
        return {"id": listing_id, "status": "updated"}
