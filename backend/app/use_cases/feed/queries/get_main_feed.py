from typing import Optional
from app.core.uow import AbstractUnitOfWork
from app.use_cases.feed.feed_utils import get_user_interests
from app.services.feed_service import _score_and_rank, _popular_feed, _mark_impressions
from app.use_cases.listings.queries.listing_utils import _row_dict, _fetch_seller_meta
from app.services.like_service import LikeService
from app.utils.redis_client import get_redis
from app.models.listing import Listing
from app.models.user import User
from app.models.enums import ListingStatus
from sqlalchemy import select
import json

PAGE_SIZE = 20
FEED_CACHE_TTL = 300

class GetMainFeedQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: Optional[int], page: int, seed: str) -> list[dict]:
        async with self.uow:
            db = self.uow.session
            if user_id:
                cache_key = f"feed:{user_id}:{seed}:{page}"
                redis = await get_redis()
                cached = await redis.get(cache_key)
                if cached:
                    return json.loads(cached)

            offset = page * PAGE_SIZE

            if user_id:
                interests = await get_user_interests(user_id, db)
                redis = await get_redis()
                excluded_raw = await redis.smembers(f"not_interested:{user_id}")
                excluded_ids = [int(x) for x in excluded_raw] if excluded_raw else []
                _user = await db.scalar(select(User).where(User.id == user_id))
                user_embedding = _user.preference_embedding if _user else None
                max_budget = _user.max_budget if _user else None
                listing_ids = await _score_and_rank(
                    user_id, interests, offset, PAGE_SIZE, seed, db,
                    excluded_ids=excluded_ids,
                    user_embedding=user_embedding,
                    max_budget=max_budget,
                )
            else:
                listing_ids = await _popular_feed(offset, PAGE_SIZE, db)

            if not listing_ids:
                return []

            rows_result = await db.execute(
                select(Listing, User)
                .join(User, User.id == Listing.user_id)
                .where(Listing.id.in_(listing_ids), Listing.status == ListingStatus.ACTIVE)
            )
            rows = {listing.id: (listing, user) for listing, user in rows_result.all()}

            counts, liked_set = await LikeService.batch_listing_likes(db, listing_ids, user_id)

            impression_map = {}
            if user_id and listing_ids:
                from sqlalchemy import func
                from app.models.listing_impression import ListingImpression
                my_listing_ids = [lid for lid in listing_ids if lid in rows and rows[lid][1].id == user_id]
                if my_listing_ids:
                    imp_result = await db.execute(
                        select(ListingImpression.listing_id, func.count())
                        .select_from(ListingImpression)
                        .where(ListingImpression.listing_id.in_(my_listing_ids))
                        .group_by(ListingImpression.listing_id)
                    )
                    for lid, imp_count in imp_result.all():
                        impression_map[lid] = imp_count

            all_uids = list({rows[lid][1].id for lid in listing_ids if lid in rows})
            badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta(all_uids)

            result = []
            for lid in listing_ids:
                if lid not in rows:
                    continue
                listing, user = rows[lid]
                result.append(_row_dict(
                    listing, user, counts.get(lid, 0), lid in liked_set,
                    seller_badge=badge_map.get(user.id),
                    is_trending=listing.category in trending_cats or listing.id in trending_lids,
                    impression_count=impression_map.get(lid, 0) if user.id == user_id else None,
                    seller_trust_score=trust_map.get(user.id),
                    seller_influence_rank=influence_map.get(user.id),
                ))

            if user_id and result:
                try:
                    await _mark_impressions(user_id, [r["id"] for r in result], db)
                except Exception:
                    pass

            if user_id and result:
                redis = await get_redis()
                await redis.setex(cache_key, FEED_CACHE_TTL, json.dumps(result))

            return result
