from sqlalchemy import select

from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import NotFoundException, BadRequestException, DatabaseException
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.listing_offer import ListingOffer
from app.models.user import User

logger = get_logger(__name__)

class CreateListingOfferCommand:
    """CQRS Command: Kullanıcı bir ilana teklif verir."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, current_user: User, amount: float) -> dict:
        logger.info("[CreateListingOfferCommand] Başlatıldı | listing_id=%s user_id=%s amount=%s", listing_id, current_user.id, amount)
        
        async with self.uow:
            result = await self.uow.session.execute(
                select(Listing).where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED)
            )
            listing = result.scalar_one_or_none()
            if not listing:
                raise NotFoundException("İlan bulunamadı")

            if listing.user_id == current_user.id:
                raise BadRequestException("Kendi ilanınıza teklif veremezsiniz")

            offer = ListingOffer(
                listing_id=listing_id,
                user_id=current_user.id,
                amount=amount,
            )
            self.uow.session.add(offer)
            await self.uow.commit()

            # Refresh is typically needed to get the generated ID
            await self.uow.session.refresh(offer)

        logger.info(
            "[CreateListingOfferCommand] Teklif verildi | listing_id=%s user_id=%s amount=%s",
            listing_id, current_user.id, amount,
        )
        return {"id": offer.id, "amount": offer.amount}
