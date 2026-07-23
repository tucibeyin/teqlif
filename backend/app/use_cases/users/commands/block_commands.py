from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.user import User
from app.models.block import UserBlock
from app.schemas.block import BlockStatusOut
from app.core.logger import get_logger

logger = get_logger(__name__)

class BlockUserCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, username: str, current_user: User) -> BlockStatusOut:
        async with self.uow:
            target = await self.uow.session.scalar(select(User).where(User.username == username))
            if not target:
                raise NotFoundException(code="USER_NOT_FOUND")
            if target.id == current_user.id:
                raise ForbiddenException(code="SELF_BLOCK_FORBIDDEN")

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
                raise NotFoundException(code="USER_NOT_FOUND")

            existing = await self.uow.session.scalar(
                select(UserBlock).where(
                    UserBlock.blocker_id == current_user.id,
                    UserBlock.blocked_id == target.id
                )
            )
            if not existing:
                return BlockStatusOut(target_username=username, is_blocked=False)

            await self.uow.session.delete(existing)

        logger.info("[USER] Kullanıcı engeli kaldırıldı | blocker=%s blocked=%s", current_user.username, username)
        
        from app.core.task_queue import get_pool
        pool = get_pool()
        if pool:
            await pool.enqueue_job("clear_user_recommendations_cache_task", current_user.id)
            await pool.enqueue_job("clear_user_recommendations_cache_task", target.id)
            
        return BlockStatusOut(target_username=username, is_blocked=False)
