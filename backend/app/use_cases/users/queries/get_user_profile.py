from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.user import User
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.block import UserBlock

class GetUserProfileQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: Optional[User]) -> dict:
        target = await self.uow.session.scalar(select(User).where(User.username == username))
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")

        profile_data = {
            "id": target.id,
            "username": target.username,
            "full_name": target.full_name,
            "bio": target.bio,
            "avatar_url": target.profile_image_url,
            "profile_image_url": target.profile_image_url,
            "profile_image_thumb_url": target.profile_image_thumb_url,
            "is_premium": target.is_premium,
            "is_private": target.is_private,
            "created_at": target.created_at,
            "follower_count": 0,
            "following_count": 0,
            "is_following": False,
            "is_blocked": False,
            "active_listings_count": 0,
        }

        if current_user:
            if current_user.id != target.id:
                from app.models.follow import Follow
                is_following = await self.uow.session.scalar(
                    select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == target.id)
                )
                profile_data["is_following"] = is_following is not None

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
