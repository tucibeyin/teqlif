from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, NotFoundException, ForbiddenException
from app.models.follow import Follow

logger = get_logger(__name__)

class FollowUserCommand:
    """CQRS Command: Bir kullanıcıyı takip eder veya takipten çıkar (Toggle)."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, follower_id: int, followed_id: int) -> dict:
        logger.info("[FollowUserCommand] Başlatıldı | follower=%s followed=%s", follower_id, followed_id)

        if follower_id == followed_id:
            logger.warning("[FollowUserCommand] Kendini takip etme hatası | user_id=%s", follower_id)
            raise ForbiddenException(code="SELF_FOLLOW_FORBIDDEN")

        async with self.uow:
            target_user = await self.uow.users.get(followed_id)
            if not target_user:
                logger.warning("[FollowUserCommand] Hedef kullanıcı bulunamadı | followed_id=%s", followed_id)
                raise NotFoundException(code="USER_NOT_FOUND")

            # Mevcut takip durumu
            from sqlalchemy import select
            stmt = select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == followed_id)
            result = await self.uow.session.execute(stmt)
            follow = result.scalar_one_or_none()

            action = "followed"
            if follow:
                await self.uow.session.delete(follow)
                action = "unfollowed"
                logger.info("[FollowUserCommand] Takipten çıkarıldı | follower=%s followed=%s", follower_id, followed_id)
            else:
                new_follow = Follow(follower_id=follower_id, followed_id=followed_id)
                self.uow.session.add(new_follow)
                logger.info("[FollowUserCommand] Takip edildi | follower=%s followed=%s", follower_id, followed_id)

            # TODO: EventBus publish UserFollowedEvent

        return {"followed_id": followed_id, "action": action}
