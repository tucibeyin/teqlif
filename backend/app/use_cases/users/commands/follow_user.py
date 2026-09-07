from sqlalchemy import select, true
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.follow import Follow
from app.models.message_thread import MessageThread
from app.services.relationship_service import RelationshipStateService

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

            stmt = select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == followed_id)
            result = await self.uow.session.execute(stmt)
            follow = result.scalar_one_or_none()

            action = "followed"
            if follow:
                await self.uow.session.delete(follow)
                action = "unfollowed"
                logger.info("[FollowUserCommand] Takipten çıkarıldı | follower=%s followed=%s", follower_id, followed_id)

                # Unfollow'da call_allowed'ı sıfırla — karşı taraf isterse tekrar açar
                user_a, user_b = min(follower_id, followed_id), max(follower_id, followed_id)
                thread = await self.uow.session.scalar(
                    select(MessageThread).where(
                        MessageThread.user_a_id == user_a,
                        MessageThread.user_b_id == user_b,
                        MessageThread.call_allowed == true(),
                    )
                )
                if thread:
                    thread.call_allowed = False
                    logger.info("[FollowUserCommand] call_allowed sıfırlandı | user_a=%s user_b=%s", user_a, user_b)
            else:
                new_follow = Follow(follower_id=follower_id, followed_id=followed_id)
                self.uow.session.add(new_follow)
                logger.info("[FollowUserCommand] Takip edildi | follower=%s followed=%s", follower_id, followed_id)

            session = self.uow.session

        state = await RelationshipStateService.recompute_and_cache(follower_id, followed_id, session)
        RelationshipStateService.broadcast(state)

        return {"followed_id": followed_id, "action": action}
