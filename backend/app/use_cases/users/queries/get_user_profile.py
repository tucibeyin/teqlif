from typing import Optional
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.user import User
from app.models.listing import Listing, ListingStatus
from app.models.block import UserBlock

class GetUserProfileQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: Optional[User]) -> dict:
        async with self.uow:
            target = await self.uow.session.scalar(select(User).where(User.username == username))
            if not target:
                raise NotFoundException("Kullanıcı bulunamadı")

            profile_data = {
                "id": target.id,
                "username": target.username,
                "bio": target.bio,
                "avatar_url": target.avatar_url,
                "created_at": target.created_at,
                "follower_count": target.follower_count,
                "following_count": target.following_count,
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
            count_res = await self.uow.session.execute(
                select(func.count(Listing.id)).where(Listing.user_id == target.id, Listing.status == ListingStatus.ACTIVE)
            )
            profile_data["active_listings_count"] = count_res.scalar_one_or_none() or 0

            return profile_data
