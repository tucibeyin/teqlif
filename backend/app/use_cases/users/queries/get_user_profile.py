from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.user import User
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.block import UserBlock
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta

class GetUserProfileQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: Optional[User]) -> dict:
        target = await self.uow.session.scalar(select(User).where(User.username == username))
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")

        badge_map, _, _, trust_map, influence_map = await _fetch_seller_meta([target.id])

        profile_data = {
            "id": target.id,
            "username": target.username,
            "full_name": target.full_name,
            "bio": target.bio,
            "website_url": target.website_url,
            "avatar_url": target.profile_image_url,
            "profile_image_url": target.profile_image_url,
            "profile_image_thumb_url": target.profile_image_thumb_url,
            "is_premium": target.is_premium,
            "is_private": target.is_private,
            "is_verified": target.is_verified,
            "phone_verified": target.phone_verified,
            "trust_score": trust_map.get(target.id),
            "influence_rank": influence_map.get(target.id),
            "badge": badge_map.get(target.id),
            "created_at": target.created_at,
            "follower_count": 0,
            "following_count": 0,
            "is_following": False,
            "is_blocked": False,
            "active_listings_count": 0,
            "instagram_url": target.instagram_url,
            "kick_url": target.kick_url,
            "twitch_url": target.twitch_url,
            "facebook_url": target.facebook_url,
            "youtube_url": target.youtube_url,
            "tiktok_url": target.tiktok_url,
        }

        if current_user:
            if current_user.id != target.id:
                from app.models.follow import Follow
                follow_row = await self.uow.session.scalar(
                    select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == target.id)
                )
                follow_status = follow_row.status if follow_row else "none"
                profile_data["follow_status"] = follow_status
                profile_data["is_following"] = follow_status == "accepted"

                is_blocked = await self.uow.session.scalar(
                    select(UserBlock).where(UserBlock.blocker_id == current_user.id, UserBlock.blocked_id == target.id)
                )
                profile_data["is_blocked"] = is_blocked is not None

                # Eğer ben onu engellediysem profil detaylarını gizle
                if is_blocked:
                    profile_data["is_blocked"] = True
                    return profile_data

                # Eğer o beni engellediyse "Kullanıcı bulunamadı" gibi davran veya profil gizli
                is_blocked_by = await self.uow.session.scalar(
                    select(UserBlock).where(UserBlock.blocker_id == target.id, UserBlock.blocked_id == current_user.id)
                )
                if is_blocked_by:
                    raise NotFoundException("Kullanıcı bulunamadı")

        from sqlalchemy import func
        from app.models.follow import Follow

        follower_count = await self.uow.session.scalar(
            select(func.count(Follow.follower_id)).where(Follow.followed_id == target.id)
        )
        following_count = await self.uow.session.scalar(
            select(func.count(Follow.followed_id)).where(Follow.follower_id == target.id)
        )
        profile_data["follower_count"] = follower_count or 0
        profile_data["following_count"] = following_count or 0

        count_res = await self.uow.session.execute(
            select(func.count(Listing.id)).where(Listing.user_id == target.id, Listing.status == ListingStatus.ACTIVE)
        )
        profile_data["active_listings_count"] = count_res.scalar_one_or_none() or 0

        return profile_data
