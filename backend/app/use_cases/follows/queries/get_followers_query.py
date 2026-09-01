from typing import Optional

from sqlalchemy import select

from app.core.exceptions import ForbiddenException
from app.core.uow import AbstractUnitOfWork
from app.models.enums import UserStatus
from app.models.follow import Follow
from app.models.user import User


class GetFollowersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: int, current_user: Optional[User]) -> list[dict]:
        target = await self.uow.session.scalar(
            select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)
        )

        if target and target.is_private:
            is_own = current_user and current_user.id == user_id
            if not is_own:
                is_accepted_follower = False
                if current_user:
                    follow = await self.uow.session.scalar(
                        select(Follow).where(
                            Follow.follower_id == current_user.id,
                            Follow.followed_id == user_id,
                            Follow.status == "accepted",
                        )
                    )
                    is_accepted_follower = follow is not None
                if not is_accepted_follower:
                    raise ForbiddenException(code="FOLLOWERS_LIST_PRIVATE")

        rows = await self.uow.session.execute(
            select(User)
            .join(Follow, Follow.follower_id == User.id)
            .where(
                Follow.followed_id == user_id,
                Follow.status == "accepted",
                User.status == UserStatus.ACTIVE,
            )
            .order_by(Follow.created_at.desc())
        )
        users = rows.scalars().all()

        following_ids: set[int] = set()
        if current_user and users:
            ids = [u.id for u in users]
            res = await self.uow.session.execute(
                select(Follow.followed_id).where(
                    Follow.follower_id == current_user.id,
                    Follow.followed_id.in_(ids),
                )
            )
            following_ids = set(res.scalars())

        return [
            {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "avatar": u.profile_image_thumb_url or u.profile_image_url,
                "is_following": u.id in following_ids,
                "is_me": current_user is not None and u.id == current_user.id,
            }
            for u in users
        ]
