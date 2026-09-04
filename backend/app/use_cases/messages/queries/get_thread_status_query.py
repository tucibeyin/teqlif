from sqlalchemy import select, and_
from app.core.uow import AbstractUnitOfWork
from app.models.message_thread import MessageThread
from app.models.follow import Follow


class GetThreadStatusQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_id: int) -> dict:
        user_a, user_b = min(uid, other_id), max(uid, other_id)
        thread = await self.uow.session.scalar(
            select(MessageThread).where(
                MessageThread.user_a_id == user_a,
                MessageThread.user_b_id == user_b,
            )
        )

        # Mutual follow check: both uid→other_id and other_id→uid must exist
        follows_other = await self.uow.session.scalar(
            select(Follow).where(
                and_(Follow.follower_id == uid, Follow.followed_id == other_id)
            )
        )
        followed_by_other = await self.uow.session.scalar(
            select(Follow).where(
                and_(Follow.follower_id == other_id, Follow.followed_id == uid)
            )
        )
        can_call = follows_other is not None and followed_by_other is not None

        if not thread:
            return {"status": None, "is_initiator": False, "can_call": can_call}
        return {
            "status": thread.status,
            "is_initiator": thread.initiator_id == uid,
            "can_call": can_call,
        }
