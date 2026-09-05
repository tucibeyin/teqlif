from sqlalchemy import update
from app.core.uow import AbstractUnitOfWork
from app.models.message import DirectMessage
from app.services.dm_broadcast import broadcast_dm


class MarkMessagesReadCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_user_id: int) -> None:
        result = await self.uow.session.execute(
            update(DirectMessage)
            .where(
                DirectMessage.sender_id == other_user_id,
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,
            )
            .values(is_read=True)
            .returning(DirectMessage.id)
        )
        read_ids = [row[0] for row in result.fetchall()]
        await self.uow.session.commit()

        if read_ids:
            await broadcast_dm(other_user_id, {"type": "messages_read", "by_user_id": uid})
