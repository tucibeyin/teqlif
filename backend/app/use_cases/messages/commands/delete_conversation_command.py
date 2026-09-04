from datetime import datetime, timezone
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.message_thread import MessageThread


class DeleteConversationCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_user_id: int) -> None:
        user_a_id = min(uid, other_user_id)
        user_b_id = max(uid, other_user_id)
        async with self.uow:
            result = await self.uow.session.execute(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a_id,
                    MessageThread.user_b_id == user_b_id,
                )
            )
            thread = result.scalar_one_or_none()
            if not thread:
                return
            now = datetime.now(timezone.utc)
            if uid == thread.user_a_id:
                thread.deleted_at_a = now
            else:
                thread.deleted_at_b = now
