from sqlalchemy import select, delete, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
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
                    MessageThread.is_request == True,
                )
            )
            if not thread:
                raise NotFoundException(code="MESSAGE_REQUEST_NOT_FOUND")

            # Delete thread + all messages in the conversation
            await self.uow.session.execute(
                delete(DirectMessage).where(
                    or_(
                        and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == requester_id),
                        and_(DirectMessage.sender_id == requester_id, DirectMessage.receiver_id == uid),
                    )
                )
            )
            await self.uow.session.delete(thread)

        redis = await get_redis()
        await redis.decr(f"msg:unread:request:{uid}")
