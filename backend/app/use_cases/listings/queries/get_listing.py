from typing import Optional
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
