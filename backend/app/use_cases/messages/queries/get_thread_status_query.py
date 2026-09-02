from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.message_thread import MessageThread


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
        if not thread:
            return {"status": None, "is_initiator": False}
        return {
            "status": thread.status,
            "is_initiator": thread.initiator_id == uid,
        }
