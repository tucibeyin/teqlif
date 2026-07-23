from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from fastapi import HTTPException

from app.models.listing import Listing
from app.models.user import User
from app.services import credit_service


class GetReactivationCostQuery:
    def __init__(self, uow):
        self.uow = uow

    async def execute(self, listing_id: int, current_user: User) -> dict:
        listing = await self.uow.session.scalar(select(Listing).where(Listing.id == listing_id))
        if not listing:
            raise HTTPException(status_code=404, detail="İlan bulunamadı")

        created_at = listing.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)

        within_window = created_at > (datetime.now(timezone.utc) - timedelta(days=30))

        reactivation_cost = credit_service.cost_tuci("reactivation")

        if current_user.is_premium:
            used = await credit_service.get_used("reactivation", current_user.id, current_user.premium_since)
            free_limit = credit_service.free_limit("reactivation", is_premium=True)
            remaining = max(0, free_limit - used)
            renewal_date: str | None = (
                credit_service.next_billing_date(current_user.premium_since).isoformat()
                if current_user.premium_since else None
            )
        else:
            free_limit = 0
            remaining = 0
            renewal_date = None

        is_free = within_window or (remaining > 0)
        cost = 0 if is_free else reactivation_cost
        can_afford = is_free or current_user.tuci_balance >= reactivation_cost

        return {
            "is_premium": current_user.is_premium,
            "free_remaining": remaining,
            "free_limit": free_limit,
            "cost": cost,
            "balance": current_user.tuci_balance,
            "can_afford": can_afford,
            "renewal_date": renewal_date,
            "within_window": within_window,
        }
