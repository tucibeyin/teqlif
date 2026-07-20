import os

get_my_listings_content = """from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.listing import Listing, ListingStatus
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.services.like_service import LikeService
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta, _fetch_unique_reach, _row_dict

class GetMyListingsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user: User, active: Optional[bool] = None, q: Optional[str] = None, category: Optional[str] = None, limit: int = 50, offset: int = 0, start_date: Optional[str] = None, end_date: Optional[str] = None) -> list:
        async with self.uow:
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
"""

get_listing_content = """from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.listing import Listing, ListingStatus, ListingImpression
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.services.like_service import LikeService
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta, _fetch_unique_reach, _row_dict
from app.core.logger import get_logger

logger = get_logger(__name__)

class GetListingQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int, current_user_id: Optional[int], ip_address: Optional[str] = None) -> dict:
        async with self.uow:
            query = (
                select(Listing, User)
                .join(User, User.id == Listing.user_id)
                .where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED)
            )
            result = await self.uow.session.execute(query)
            row = result.first()

            if not row:
                raise NotFoundException("İlan bulunamadı")
            
            listing, seller = row

            if current_user_id and listing.user_id != current_user_id:
                try:
                    imp = ListingImpression(listing_id=listing.id, user_id=current_user_id, ip_address=ip_address)
                    self.uow.session.add(imp)
                    await self.uow.commit()
                except Exception as exc:
                    logger.warning("[GetListingQuery] İzlenme kaydedilemedi: %s", exc)

            counts, liked_set = await LikeService.batch_listing_likes(
                self.uow.session, [listing.id], current_user_id
            )
            
            camp_result = await self.uow.session.execute(
                select(AdCampaign.id)
                .where(
                    AdCampaign.listing_id == listing.id,
                    AdCampaign.status.in_(["active", "paused"]),
                )
            )
            cid = camp_result.scalar_one_or_none()

            badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta([seller.id])
            impression_map: dict[int, int] = {}
            await _fetch_unique_reach(self.uow.session, impression_map, [listing.id])

            return _row_dict(
                listing, seller,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=bool(cid),
                campaign_id=cid,
                seller_badge=badge_map.get(seller.id),
                is_trending=listing.category in trending_cats or listing.id in trending_lids,
                impression_count=impression_map.get(listing.id, 0),
                seller_trust_score=trust_map.get(seller.id),
                seller_influence_rank=influence_map.get(seller.id),
            )
"""

get_listing_offers_content = """from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.listing import ListingOffer
from app.models.user import User

class GetListingOffersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, listing_id: int) -> list:
        async with self.uow:
            query = (
                select(ListingOffer, User)
                .join(User, User.id == ListingOffer.user_id)
                .where(ListingOffer.listing_id == listing_id)
                .order_by(ListingOffer.created_at.desc())
            )
            result = await self.uow.session.execute(query)
            rows = result.all()
            
            return [
                {
                    "id": offer.id,
                    "amount": offer.amount,
                    "created_at": offer.created_at,
                    "user": {
                        "id": user.id,
                        "username": user.username,
                        "avatar_url": user.avatar_url
                    }
                }
                for offer, user in rows
            ]
"""

base_dir = "backend/app/use_cases/listings/queries"
os.makedirs(base_dir, exist_ok=True)
with open(f"{base_dir}/get_my_listings.py", "w") as f: f.write(get_my_listings_content)
with open(f"{base_dir}/get_listing.py", "w") as f: f.write(get_listing_content)
with open(f"{base_dir}/get_listing_offers.py", "w") as f: f.write(get_listing_offers_content)
