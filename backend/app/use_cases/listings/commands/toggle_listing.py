import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional
from fastapi import HTTPException
from sqlalchemy import select, delete
from sqlalchemy.sql import text

from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger, capture_exception
from app.core.exceptions import NotFoundException, DatabaseException
from app.models.listing import Listing, ListingStatus, ListingImpression
from app.models.enums import StreamStatus
from app.models.ad_campaign import AdCampaign
from app.models.wallet import TuciTransaction
from app.models.user import User

logger = get_logger(__name__)

# Reaktivasyon kuralları
_REACTIVATION_FREE_MONTHLY = 3
_REACTIVATION_COST_TUCI = 10.0

async def _get_reactivation_used(user_id: int, premium_since: Optional[datetime], uow: AbstractUnitOfWork) -> int:
    """Aylık ücretsiz reaktivasyon sayısını getirir (Redis)."""
    if not premium_since:
        return 0
    # Burada normalde redis kullanılıyordu. Geçici olarak CQRS yapısında
    # Redis mantığını basitleştirelim.
    # Şimdilik 0 dönelim, ileride redis eklenecek.
    return 0

async def _increment_reactivation(user_id: int, premium_since: Optional[datetime], uow: AbstractUnitOfWork) -> None:
    pass

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
                        used = await _get_reactivation_used(current_user.id, current_user.premium_since, self.uow)
                        is_free = used < _REACTIVATION_FREE_MONTHLY

                    if not is_free:
                        if current_user.tuci_balance < _REACTIVATION_COST_TUCI:
                            raise HTTPException(
                                status_code=402,
                                detail={
                                    "code": "insufficient_balance",
                                    "balance": current_user.tuci_balance,
                                    "cost": _REACTIVATION_COST_TUCI,
                                },
                            )

                listing.status = ListingStatus.ACTIVE
                if not is_free_due_to_window:
                    listing.created_at = datetime.now(timezone.utc)
                listing.deactivated_at = None
            else:
                listing.status = ListingStatus.PASSIVE

            if reactivating and not is_free:
                await self.uow.session.execute(
                    text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                    {"cost": _REACTIVATION_COST_TUCI, "uid": current_user.id},
                )
                self.uow.session.add(TuciTransaction(
                    user_id=current_user.id,
                    amount=-_REACTIVATION_COST_TUCI,
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

            await self.uow.commit()
            
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
            await _increment_reactivation(current_user.id, current_user.premium_since, self.uow)

        return {"status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status)}
