from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.services.like_service import LikeService
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta, _fetch_unique_reach, _row_dict

class GetMyListingsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user: User, active: Optional[bool] = None, q: Optional[str] = None, category: Optional[str] = None, limit: int = 50, offset: int = 0, start_date: Optional[str] = None, end_date: Optional[str] = None) -> list:
        query = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.user_id == current_user.id, Listing.status != ListingStatus.DELETED)
        )
        if active is not None:
            query = query.where(Listing.status == ListingStatus.ACTIVE if active else Listing.status != ListingStatus.ACTIVE)
        if category:
            query = query.where(Listing.category == category)
        if q:
            query = query.where(Listing.title.ilike(f"%{q}%"))
        if start_date:
            from datetime import datetime
            try:
                sd = datetime.strptime(start_date, '%Y-%m-%d')
                query = query.where(Listing.created_at >= sd)
            except ValueError:
                pass
        if end_date:
            from datetime import datetime, timedelta
            try:
                ed = datetime.strptime(end_date, '%Y-%m-%d') + timedelta(days=1)
                query = query.where(Listing.created_at < ed)
            except ValueError:
                pass

        query = query.order_by(Listing.created_at.desc()).limit(limit).offset(offset)
        result = await self.uow.session.execute(query)
        rows = result.all()

        listing_ids = [listing.id for listing, _ in rows]
        counts, liked_set = await LikeService.batch_listing_likes(
            self.uow.session, listing_ids, current_user.id
        )
        campaign_map: dict[int, int] = {}
        if listing_ids:
            camp_result = await self.uow.session.execute(
                select(AdCampaign.listing_id, AdCampaign.id)
                .where(
                    AdCampaign.listing_id.in_(listing_ids),
                    AdCampaign.status.in_(["active", "paused"]),
                )
            )
            for lid, cid in camp_result.all():
                campaign_map.setdefault(lid, cid)
        badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta([current_user.id])

        impression_map: dict[int, int] = {}
        if listing_ids:
            await _fetch_unique_reach(self.uow.session, impression_map, listing_ids)

        return [
            _row_dict(
                listing, user,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=listing.id in campaign_map,
                campaign_id=campaign_map.get(listing.id),
                seller_badge=badge_map.get(user.id),
                is_trending=listing.category in trending_cats or listing.id in trending_lids,
                impression_count=impression_map.get(listing.id, 0),
                seller_trust_score=trust_map.get(user.id),
                seller_influence_rank=influence_map.get(user.id),
            )
            for listing, user in rows
        ]
