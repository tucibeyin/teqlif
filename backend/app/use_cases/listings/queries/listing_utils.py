import json
import logging
from typing import Optional, Tuple

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.listing import Listing
from app.models.listing_impression import ListingImpression
from app.models.user import User

logger = logging.getLogger(__name__)

async def _fetch_unique_reach(db: AsyncSession, impression_map: dict[int, int], listing_ids: list[int]) -> None:
    """listing_impressions tablosundan her ilanı kaç farklı kişinin gördüğünü döndürür (unique reach)."""
    if not listing_ids:
        return
    try:
        result = await db.execute(
            select(ListingImpression.listing_id, func.count(func.distinct(ListingImpression.user_id)))
            .where(ListingImpression.listing_id.in_(listing_ids))
            .group_by(ListingImpression.listing_id)
        )
        for lid, count in result.all():
            impression_map[lid] = count
    except Exception as e:
        logger.warning("[ListingUtils] Unique reach fetch failed: %s", e)

async def _fetch_seller_meta(
    user_ids: list[int],
) -> Tuple[dict[int, str | None], set[str], set[int], dict[int, int | None], dict[int, int | None]]:
    """
    Batch olarak Redis'ten seller_badge, trending kategoriler, trending listing ID'leri,
    trust_score ve influence_rank çeker.
    Döner: (badge_map, trending_categories, trending_listing_ids, trust_map, influence_map)
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        badge_keys     = [f"seller:badge:{uid}"   for uid in user_ids]
        trust_keys     = [f"trust_score:{uid}"     for uid in user_ids]
        influence_keys = [f"influence_rank:{uid}"  for uid in user_ids]
        all_keys = badge_keys + trust_keys + influence_keys
        all_vals = await redis.mget(*all_keys) if all_keys else []
        n = len(user_ids)
        badge_vals, trust_vals, inf_vals = all_vals[:n], all_vals[n:2*n], all_vals[2*n:]
        badge_map    = {uid: (val or None) for uid, val in zip(user_ids, badge_vals)}
        trust_map    = {uid: (int(val) if val is not None else None) for uid, val in zip(user_ids, trust_vals)}
        influence_map= {uid: (int(val) if val is not None else None) for uid, val in zip(user_ids, inf_vals)}
        trending_cats = set(await redis.smembers("trending:categories") or [])
        trending_listing_ids = {int(v) for v in (await redis.smembers("trending:listings") or [])}
        return badge_map, trending_cats, trending_listing_ids, trust_map, influence_map
    except Exception as exc:
        logger.warning("[SellerMeta] Redis fetch başarısız — badge/trending boş dönüyor: %s", exc)
        return {}, set(), set(), {}, {}


def _parse_image_urls(image_urls_raw) -> list:
    """image_urls DB'de JSON string olarak saklanır, list olarak döndürür."""
    if image_urls_raw is None:
        return []
    if isinstance(image_urls_raw, list):
        return image_urls_raw
    try:
        parsed = json.loads(image_urls_raw)
        return parsed if isinstance(parsed, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


def _row_dict(

    listing: Listing,
    user: User,
    likes_count: int = 0,
    is_liked: bool = False,
    is_sponsored: bool = False,
    campaign_id: Optional[int] = None,
    seller_badge: Optional[str] = None,
    is_trending: bool = False,
    impression_count: int = 0,
    seller_trust_score: Optional[float] = None,
    seller_influence_rank: Optional[str] = None,
) -> dict:
    return {
        "id": listing.id,
        "title": listing.title,
        "description": listing.description,
        "price": listing.price,
        "category": listing.category,
        "brand": listing.brand,
        "condition": listing.condition,
        "image_url": listing.image_url,
        "image_urls": _parse_image_urls(listing.image_urls),
        "thumbnail_url": listing.thumbnail_url,
        "video_url": listing.video_url,
        "location": listing.location,
        "status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status),
        "created_at": listing.created_at,
        "updated_at": listing.updated_at,
        "deactivated_at": listing.deactivated_at,
        "expires_at": listing.expires_at,
        "is_highlight": listing.is_highlight,
        "buy_it_now_price": listing.buy_it_now_price,
        "likes_count": likes_count,
        "is_liked": is_liked,
        "impression_count": impression_count,
        "is_sponsored": is_sponsored,
        "campaign_id": campaign_id,
        "is_trending": is_trending,
        "user": {
            "id": user.id,
            "username": user.username,
            "full_name": user.full_name,
            "avatar_url": user.profile_image_url,
            "profile_image_url": user.profile_image_url,
            "profile_image_thumb_url": user.profile_image_thumb_url,
            "is_premium": user.is_premium,
            "is_verified": user.is_verified,
            "badge": seller_badge,
            "trust_score": seller_trust_score,
            "influence_rank": seller_influence_rank,
        },
    }
