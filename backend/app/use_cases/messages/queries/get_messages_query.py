from sqlalchemy import select, update, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.user import User
from app.schemas.message import MessageOut
from app.services.dm_broadcast import broadcast_dm


class GetMessagesQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_user_id: int) -> list[MessageOut]:
        other_result = await self.uow.session.execute(
            select(User).where(User.id == other_user_id)
        )
        other_user = other_result.scalar_one_or_none()
        if not other_user:
            raise NotFoundException(code="USER_NOT_FOUND")

        # Fetch thread to determine per-user deletion cutoff
        user_a_id = min(uid, other_user_id)
        user_b_id = max(uid, other_user_id)
        thread_result = await self.uow.session.execute(
            select(MessageThread.deleted_at_a, MessageThread.deleted_at_b).where(
                MessageThread.user_a_id == user_a_id,
                MessageThread.user_b_id == user_b_id,
            )
        )
        thread_row = thread_result.first()
        deleted_at_x = None
        if thread_row:
            deleted_at_x = thread_row.deleted_at_a if uid == user_a_id else thread_row.deleted_at_b

        base_where = [
            or_(
                and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_user_id),
                and_(
                    DirectMessage.sender_id == other_user_id,
                    DirectMessage.receiver_id == uid,
                    DirectMessage.is_shadowbanned == False,
                ),
            ),
            # Exclude messages soft-deleted for this user
            ~and_(DirectMessage.sender_id == uid, DirectMessage.deleted_for_sender == True),
            ~and_(DirectMessage.receiver_id == uid, DirectMessage.deleted_for_receiver == True),
        ]
        if deleted_at_x:
            base_where.append(DirectMessage.created_at > deleted_at_x)

        result = await self.uow.session.execute(
            select(DirectMessage)
            .where(*base_where)
            .order_by(DirectMessage.created_at.desc())
            .limit(100)
        )
        messages = list(reversed(result.scalars().all()))

        # Mark received messages as read
        result_update = await self.uow.session.execute(
            update(DirectMessage)
            .where(
                DirectMessage.sender_id == other_user_id,
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,
            )
            .values(is_read=True)
            .returning(DirectMessage.id)
        )
        read_ids = [row[0] for row in result_update.fetchall()]
        await self.uow.session.commit()

        if read_ids:
            await broadcast_dm(other_user_id, {"type": "messages_read", "by_user_id": uid})

        sender_ids = {m.sender_id for m in messages}
        users_result = await self.uow.session.execute(
            select(User).where(User.id.in_(sender_ids))
        )
        users_map = {u.id: u for u in users_result.scalars().all()}

        output = []
        for msg in messages:
            sender = users_map.get(msg.sender_id)
            output.append(
                MessageOut(
                    id=msg.id,
                    sender_id=msg.sender_id,
                    receiver_id=msg.receiver_id,
                    sender_username=sender.username if sender else "",
                    content=msg.content,
                    content_type=msg.content_type,
                    media_url=msg.media_url,
                    thumbnail_url=msg.thumbnail_url,
                    duration_secs=msg.duration_secs,
                    file_name=msg.file_name,
                    file_size=msg.file_size,
                    is_read=msg.is_read,
                    created_at=msg.created_at,
                )
            )
        return output
