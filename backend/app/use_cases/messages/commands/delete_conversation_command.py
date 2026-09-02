from sqlalchemy import delete, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.models.message import DirectMessage


class DeleteConversationCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_user_id: int) -> None:
        async with self.uow:
            await self.uow.session.execute(
                delete(DirectMessage).where(
                    or_(
                        and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_user_id),
                        and_(DirectMessage.sender_id == other_user_id, DirectMessage.receiver_id == uid),
                    )
                )
            )
