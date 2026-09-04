from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.user import User
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.block import UserBlock
from app.models.message_thread import MessageThread
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta
from app.use_cases.messages.queries.get_thread_status_query import _compute_can_call

class GetUserProfileQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: Optional[User]) -> dict:
        target = await self.uow.session.scalar(select(User).where(User.username == username))
        if not target:
            raise NotFoundException(code="USER_NOT_FOUND")

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
            "is_followed_by": False,
            "can_call": False,
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

                from app.models.follow import Follow as _Follow
                followed_by_row = await self.uow.session.scalar(
                    select(_Follow).where(
                        _Follow.follower_id == target.id,
                        _Follow.followed_id == current_user.id,
                        _Follow.status == "accepted",
                    )
                )
                is_followed_by = followed_by_row is not None
                profile_data["is_followed_by"] = is_followed_by

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
                    raise NotFoundException(code="USER_NOT_FOUND")

                # can_call: current_user → target araması mümkün mü?
                _user_a = min(current_user.id, target.id)
                _user_b = max(current_user.id, target.id)
                _thread = await self.uow.session.scalar(
                    select(MessageThread).where(
                        MessageThread.user_a_id == _user_a,
                        MessageThread.user_b_id == _user_b,
                    )
                )
                can_call, can_call_reason = _compute_can_call(
                    viewer_follows_target=profile_data["is_following"],
                    target_follows_viewer=is_followed_by,
                    thread_status=_thread.status if _thread else None,
                    call_allowed=_thread.call_allowed if _thread else False,
                )
                profile_data["can_call"] = can_call
                profile_data["can_call_reason"] = can_call_reason

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

        # Gizli hesap + takipçi olmayan → sosyal linkler gizlenir
        is_own = current_user and current_user.id == target.id
        if target.is_private and not is_own and not profile_data.get("is_following"):
            for _field in ("instagram_url", "kick_url", "twitch_url",
                           "facebook_url", "youtube_url", "tiktok_url", "website_url"):
                profile_data[_field] = None

        return profile_data
