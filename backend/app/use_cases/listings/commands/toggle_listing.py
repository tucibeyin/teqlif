import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional
from sqlalchemy import select, delete
from sqlalchemy.sql import text

from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import NotFoundException, DatabaseException, InsufficientFundsException
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.listing_impression import ListingImpression
from app.models.enums import StreamStatus
from app.models.ad_campaign import AdCampaign
from app.models.tuci_transaction import TuciTransaction
from app.models.user import User
from app.services import credit_service

logger = get_logger(__name__)

class ToggleListingCommand:
    """CQRS Command: Kullanıcı ilanını aktif veya pasif yapar."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, current_user: User) -> dict:
        logger.info("[ToggleListingCommand] Başlatıldı | listing_id=%s user_id=%s", listing_id, current_user.id)
        
        async with self.uow:
            result = await self.uow.session.execute(
                select(Listing).where(
                    Listing.id == listing_id,
                    Listing.user_id == current_user.id,
                    Listing.status != ListingStatus.DELETED,
                )
            )
            listing = result.scalar_one_or_none()
            
            if not listing:
                raise NotFoundException("İlan bulunamadı")

            reactivating = listing.status != ListingStatus.ACTIVE
            is_free = False
            is_free_due_to_window = False
            reactivation_cost = credit_service.cost_tuci("reactivation")

            if reactivating:
                created_at = listing.created_at
                if created_at.tzinfo is None:
                    created_at = created_at.replace(tzinfo=timezone.utc)
                within_window = created_at > (datetime.now(timezone.utc) - timedelta(days=30))
                
                if within_window:
                    is_free = True
                    is_free_due_to_window = True
                else:
                    if current_user.is_premium:
                        used = await credit_service.get_used("reactivation", current_user.id, current_user.premium_since)
                        is_free = used < credit_service.free_limit("reactivation", is_premium=True)

                    if not is_free:
                        if current_user.tuci_balance < reactivation_cost:
                            raise InsufficientFundsException(code="insufficient_balance")

                listing.status = ListingStatus.ACTIVE
                if not is_free_due_to_window:
                    listing.created_at = datetime.now(timezone.utc)
                listing.deactivated_at = None
            else:
                listing.status = ListingStatus.PASSIVE

            if reactivating and not is_free:
                await self.uow.session.execute(
                    text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                    {"cost": reactivation_cost, "uid": current_user.id},
                )
                self.uow.session.add(TuciTransaction(
                    user_id=current_user.id,
                    amount=-reactivation_cost,
                    transaction_type="spend_reactivation",
                    reference_id=listing_id,
                    reference_type="listing",
                ))

            if not reactivating:
                await self.uow.session.execute(
                    delete(AdCampaign).where(AdCampaign.listing_id == listing_id)
                )

            await self.uow.session.execute(
                delete(ListingImpression).where(ListingImpression.listing_id == listing_id)
            )

        try:
            from app.utils.listing_cleanup import cleanup_listing_redis
            asyncio.create_task(cleanup_listing_redis(listing_id))
        except Exception:
            pass

        if not reactivating:
            try:
                from app.services.ad_service import load_active_campaigns_to_redis
                asyncio.create_task(load_active_campaigns_to_redis())
            except Exception:
                pass

        if reactivating and is_free and not is_free_due_to_window:
            await credit_service.increment("reactivation", current_user.id, current_user.premium_since)

        return {"status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status)}
