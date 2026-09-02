from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.message import DirectMessage
from app.services.dm_broadcast import broadcast_dm


class DeleteMessageCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, message_id: int, current_user_id: int) -> None:
        async with self.uow:
            result = await self.uow.session.execute(
                select(DirectMessage).where(DirectMessage.id == message_id)
            )
            msg = result.scalar_one_or_none()
            if not msg:
                raise NotFoundException(code="MESSAGE_NOT_FOUND")
            if msg.sender_id != current_user_id:
                raise ForbiddenException(code="MESSAGE_DELETE_FORBIDDEN")
            other_user_id = msg.receiver_id
            await self.uow.session.delete(msg)

        await broadcast_dm(current_user_id, {"type": "message_deleted", "id": message_id})
        await broadcast_dm(other_user_id, {"type": "message_deleted", "id": message_id})
