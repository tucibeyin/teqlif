import os

base = "backend/app/use_cases/users"
os.makedirs(f"{base}/commands", exist_ok=True)
os.makedirs(f"{base}/queries", exist_ok=True)

block = """from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.user import User
from app.models.block import UserBlock
from app.schemas.user import BlockStatusOut
from app.core.logger import get_logger

logger = get_logger(__name__)

class BlockUserCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: User) -> BlockStatusOut:
        async with self.uow:
            target = await self.uow.session.scalar(select(User).where(User.username == username))
            if not target:
                raise NotFoundException("Kullanıcı bulunamadı")
            if target.id == current_user.id:
                raise BadRequestException("Kendinizi engelleyemezsiniz")

            existing = await self.uow.session.scalar(
                select(UserBlock).where(
                    UserBlock.blocker_id == current_user.id,
                    UserBlock.blocked_id == target.id
                )
            )
            if existing:
                return BlockStatusOut(target_username=username, is_blocked=True)

            block_rec = UserBlock(blocker_id=current_user.id, blocked_id=target.id)
            self.uow.session.add(block_rec)
            await self.uow.commit()

        logger.info("[USER] Kullanıcı engellendi | blocker=%s blocked=%s", current_user.username, username)
        
        from app.core.task_queue import get_pool
        pool = get_pool()
        if pool:
            await pool.enqueue_job("clear_user_recommendations_cache_task", current_user.id)
            await pool.enqueue_job("clear_user_recommendations_cache_task", target.id)
            
        return BlockStatusOut(target_username=username, is_blocked=True)

class UnblockUserCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: User) -> BlockStatusOut:
        async with self.uow:
            target = await self.uow.session.scalar(select(User).where(User.username == username))
            if not target:
                raise NotFoundException("Kullanıcı bulunamadı")

            existing = await self.uow.session.scalar(
                select(UserBlock).where(
                    UserBlock.blocker_id == current_user.id,
                    UserBlock.blocked_id == target.id
                )
            )
            if not existing:
                return BlockStatusOut(target_username=username, is_blocked=False)

            await self.uow.session.delete(existing)
            await self.uow.commit()

        logger.info("[USER] Kullanıcı engeli kaldırıldı | blocker=%s blocked=%s", current_user.username, username)
        
        from app.core.task_queue import get_pool
        pool = get_pool()
        if pool:
            await pool.enqueue_job("clear_user_recommendations_cache_task", current_user.id)
            await pool.enqueue_job("clear_user_recommendations_cache_task", target.id)
            
        return BlockStatusOut(target_username=username, is_blocked=False)
"""

get_blocked = """from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.user import User
from app.models.block import UserBlock

class GetBlockedUsersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user: User) -> list[User]:
        async with self.uow:
            query = (
                select(User)
                .join(UserBlock, UserBlock.blocked_id == User.id)
                .where(UserBlock.blocker_id == current_user.id)
            )
            result = await self.uow.session.execute(query)
            return list(result.scalars().all())
"""

get_profile = """from typing import Optional
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
"""

with open(f"{base}/commands/block_commands.py", "w") as f: f.write(block)
with open(f"{base}/queries/get_blocked_users.py", "w") as f: f.write(get_blocked)
with open(f"{base}/queries/get_user_profile.py", "w") as f: f.write(get_profile)
print("Generated user cqrs")
