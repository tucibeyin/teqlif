from datetime import datetime, timezone, timedelta, date
from typing import Optional
from sqlalchemy import select
from fastapi import HTTPException

from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing
from app.models.user import User

_REACTIVATION_FREE_MONTHLY = 3
_REACTIVATION_COST_TUCI = 10.0

def _reactivation_billing_start(premium_since: datetime) -> date:
    today = datetime.now(timezone.utc).date()
    ps = premium_since.date()
    if today.day >= ps.day:
        try:
            return date(today.year, today.month, ps.day)
        except ValueError:
            return date(today.year, today.month + 1, 1) - timedelta(days=1)
    else:
        if today.month == 1:
            y, m = today.year - 1, 12
        else:
            y, m = today.year, today.month - 1
        try:
            return date(y, m, ps.day)
        except ValueError:
            return date(y, m + 1, 1) - timedelta(days=1)

def _reactivation_next_billing(premium_since: datetime) -> date:
    start = _reactivation_billing_start(premium_since)
    if start.month == 12:
        y, m = start.year + 1, 1
    else:
        y, m = start.year, start.month + 1
    try:
        return date(y, m, start.day)
    except ValueError:
        return date(y, m + 1, 1) - timedelta(days=1)

async def _get_reactivation_used(user_id: int, premium_since: Optional[datetime], uow: AbstractUnitOfWork) -> int:
    if not premium_since:
        return 0
    # Placeholder for Redis fetch
    return 0

class GetReactivationCostQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, current_user: User) -> dict:
        listing = await self.uow.session.scalar(select(Listing).where(Listing.id == listing_id))
        if not listing:
            raise HTTPException(status_code=404, detail="İlan bulunamadı")

        created_at = listing.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)

        within_window = created_at > (datetime.now(timezone.utc) - timedelta(days=30))

        if current_user.is_premium:
            used = await _get_reactivation_used(current_user.id, current_user.premium_since, self.uow)
            remaining = max(0, _REACTIVATION_FREE_MONTHLY - used)
            renewal_date: str | None = None
            if current_user.premium_since:
                renewal_date = _reactivation_next_billing(current_user.premium_since).isoformat()
        else:
            remaining = 0
            renewal_date = None

        is_free = within_window or (remaining > 0)
        cost = 0 if is_free else _REACTIVATION_COST_TUCI
        can_afford = is_free or current_user.tuci_balance >= _REACTIVATION_COST_TUCI

        return {
            "is_premium": current_user.is_premium,
            "free_remaining": remaining,
            "free_limit": _REACTIVATION_FREE_MONTHLY,
            "cost": cost,
            "balance": current_user.tuci_balance,
            "can_afford": can_afford,
            "renewal_date": renewal_date,
            "within_window": within_window,
        }
