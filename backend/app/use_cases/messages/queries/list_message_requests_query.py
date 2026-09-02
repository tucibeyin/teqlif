from sqlalchemy import select, func, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.user import User
from app.schemas.message import ConversationOut


class ListMessageRequestsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int) -> list[ConversationOut]:
        threads_result = await self.uow.session.execute(
            select(MessageThread).where(
                or_(MessageThread.user_a_id == uid, MessageThread.user_b_id == uid),
                MessageThread.is_request == True,
            )
        )
        threads = threads_result.scalars().all()
        if not threads:
            return []

        other_ids = [t.user_b_id if t.user_a_id == uid else t.user_a_id for t in threads]

        users_result = await self.uow.session.execute(
            select(User).where(User.id.in_(other_ids))
        )
        users_map = {u.id: u for u in users_result.scalars().all()}

        # Latest message + unread count per thread
        conversations = []
        for thread in threads:
            other_id = thread.user_b_id if thread.user_a_id == uid else thread.user_a_id
            other_user = users_map.get(other_id)
            if not other_user:
                continue

            msg_result = await self.uow.session.execute(
                select(DirectMessage)
                .where(
                    or_(
                        and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_id),
                        and_(DirectMessage.sender_id == other_id, DirectMessage.receiver_id == uid),
                    )
                )
                .order_by(DirectMessage.created_at.desc())
                .limit(1)
            )
            latest = msg_result.scalar_one_or_none()
            if not latest:
                continue

            unread_result = await self.uow.session.execute(
                select(func.count()).where(
                    DirectMessage.sender_id == other_id,
                    DirectMessage.receiver_id == uid,
                    DirectMessage.is_read == False,
                    DirectMessage.is_shadowbanned == False,
                )
            )
            unread = unread_result.scalar_one()

            conversations.append(
                ConversationOut(
                    user_id=other_id,
                    username=other_user.username,
                    full_name=other_user.full_name,
                    last_message=latest.content,
                    last_message_type=latest.content_type,
                    last_at=latest.created_at,
                    unread_count=unread,
                    is_request=True,
                )
            )

        return sorted(conversations, key=lambda c: c.last_at, reverse=True)
