from datetime import datetime, timezone
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.message import DirectMessage
from app.services.dm_broadcast import broadcast_dm

_48H = 48 * 3600


class DeleteMessageCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, message_id: int, current_user_id: int, scope: str = "everyone") -> None:
        other_user_id: int | None = None
        broadcast_delete = False

        async with self.uow:
            result = await self.uow.session.execute(
                select(DirectMessage).where(DirectMessage.id == message_id)
            )
            msg = result.scalar_one_or_none()
            if not msg:
                raise NotFoundException(code="MESSAGE_NOT_FOUND")

            is_sender = msg.sender_id == current_user_id
            is_receiver = msg.receiver_id == current_user_id

            if not is_sender and not is_receiver:
                raise ForbiddenException(code="MESSAGE_DELETE_FORBIDDEN")

            if scope == "me":
                if is_sender:
                    msg.deleted_for_sender = True
                else:
                    msg.deleted_for_receiver = True
            else:
                # scope == "everyone": sender only, within 48 hours
                if not is_sender:
                    raise ForbiddenException(code="MESSAGE_DELETE_EVERYONE_FORBIDDEN")
                now = datetime.now(timezone.utc)
                created = msg.created_at if msg.created_at.tzinfo else msg.created_at.replace(tzinfo=timezone.utc)
                if (now - created).total_seconds() > _48H:
                    raise ForbiddenException(code="MESSAGE_DELETE_EXPIRED")
                other_user_id = msg.receiver_id
                await self.uow.session.delete(msg)
                broadcast_delete = True

        if broadcast_delete and other_user_id:
            await broadcast_dm(current_user_id, {"type": "message_deleted", "id": message_id})
            await broadcast_dm(other_user_id, {"type": "message_deleted", "id": message_id})
