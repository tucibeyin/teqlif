from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.message_thread import MessageThread
from app.services.relationship_service import RelationshipStateService
from app.utils.redis_client import get_redis


class DeclineMessageRequestCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, requester_id: int) -> None:
        user_a, user_b = min(uid, requester_id), max(uid, requester_id)

        async with self.uow:
            thread = await self.uow.session.scalar(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a,
                    MessageThread.user_b_id == user_b,
                    MessageThread.status == "pending",
                )
            )
            if not thread:
                raise NotFoundException(code="MESSAGE_REQUEST_NOT_FOUND")

            thread.status = "declined"
            thread.call_allowed = False
            session = self.uow.session

        redis = await get_redis()
        await redis.decr(f"msg:unread:request:{uid}")

        state = await RelationshipStateService.recompute_and_cache(user_a, user_b, session)
        RelationshipStateService.broadcast(state)
