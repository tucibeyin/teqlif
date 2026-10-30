from sqlalchemy import select, or_, and_

from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import NotFoundException, BadRequestException, DatabaseException, ForbiddenException
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.listing_offer import ListingOffer
from app.models.block import UserBlock
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
                raise NotFoundException(code="LISTING_NOT_FOUND")

            if listing.user_id == current_user.id:
                raise ForbiddenException(code="SELF_BID_FORBIDDEN")

            block = await self.uow.session.scalar(
                select(UserBlock).where(
                    or_(
                        and_(UserBlock.blocker_id == current_user.id, UserBlock.blocked_id == listing.user_id),
                        and_(UserBlock.blocker_id == listing.user_id, UserBlock.blocked_id == current_user.id),
                    )
                ).limit(1)
            )
            if block:
                raise ForbiddenException(code="OFFER_FORBIDDEN")

            offer = ListingOffer(
                listing_id=listing_id,
                user_id=current_user.id,
                amount=amount,
            )
            self.uow.session.add(offer)
            await self.uow.session.flush()  # offer.id atanır, commit __aexit__'te yapılır

        logger.info(
            "[CreateListingOfferCommand] Teklif verildi | listing_id=%s user_id=%s amount=%s",
            listing_id, current_user.id, amount,
        )

        # Satıcıya bildirim + WS sinyali (commit sonrası)
        try:
            from app.services.notification_service import push_notification
            from app.core.ws_manager import ws_manager
            await push_notification(
                user_id=listing.user_id,
                notif={
                    "type": "listing_offer_received",
                    "title": "Yeni Teklif Aldınız!",
                    "body": f"{current_user.username} ilanınıza {amount:,.0f} TL teklif verdi.",
                    "related_id": listing_id,
                    "listing_id": listing_id,
                    "extra_data": {"offer_id": str(offer.id), "amount": str(amount)},
                },
                pref_key="new_offer",
            )
            await ws_manager.publish(
                "dm_broadcast",
                f"dm:{listing.user_id}",
                {"type": "new_listing_offer", "listing_id": listing_id, "amount": amount, "buyer": current_user.username},
            )
        except Exception as _ne:
            logger.warning("[CreateListingOfferCommand] Bildirim gönderilemedi: %s", _ne)

        return {"id": offer.id, "amount": offer.amount}
