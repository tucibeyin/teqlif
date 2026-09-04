import asyncio
from sqlalchemy import select, func, or_, and_, tuple_
from app.core.uow import AbstractUnitOfWork
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.user import User
from app.schemas.message import ConversationOut


class GetConversationsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int) -> list[ConversationOut]:
        conv_subq = (
            select(
                func.least(DirectMessage.sender_id, DirectMessage.receiver_id).label("min_uid"),
                func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id).label("max_uid"),
                func.max(DirectMessage.created_at).label("max_at"),
            )
            .where(
                or_(
                    DirectMessage.sender_id == uid,
                    and_(DirectMessage.receiver_id == uid, DirectMessage.is_shadowbanned == False),
                )
            )
            .group_by(
                func.least(DirectMessage.sender_id, DirectMessage.receiver_id),
                func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id),
            )
            .subquery()
        )

        msgs_result = await self.uow.session.execute(
            select(DirectMessage)
            .join(
                conv_subq,
                and_(
                    func.least(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.min_uid,
                    func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.max_uid,
                    DirectMessage.created_at == conv_subq.c.max_at,
                ),
            )
            .where(
                or_(
                    DirectMessage.sender_id == uid,
                    and_(DirectMessage.receiver_id == uid, DirectMessage.is_shadowbanned == False),
                )
            )
            .order_by(DirectMessage.created_at.desc())
        )
        latest_msgs = msgs_result.scalars().all()

        if not latest_msgs:
            return []

        # Exclude pending requests, soft-declined, and user-deleted threads from main inbox
        pairs = [(min(m.sender_id, m.receiver_id), max(m.sender_id, m.receiver_id)) for m in latest_msgs]
        thread_result = await self.uow.session.execute(
            select(
                MessageThread.user_a_id,
                MessageThread.user_b_id,
                MessageThread.status,
                MessageThread.initiator_id,
                MessageThread.deleted_at_a,
                MessageThread.deleted_at_b,
            )
            .where(tuple_(MessageThread.user_a_id, MessageThread.user_b_id).in_(pairs))
        )
        thread_rows = thread_result.all()
        hidden_pairs = {
            (row.user_a_id, row.user_b_id)
            for row in thread_rows
            if row.status == "declined"
            or (row.status == "pending" and row.initiator_id != uid)
        }
        deleted_map = {
            (row.user_a_id, row.user_b_id): (row.deleted_at_a, row.deleted_at_b)
            for row in thread_rows
        }
        filtered = []
        for m in latest_msgs:
            pair = (min(m.sender_id, m.receiver_id), max(m.sender_id, m.receiver_id))
            if pair in hidden_pairs:
                continue
            del_a, del_b = deleted_map.get(pair, (None, None))
            deleted_at_x = del_a if uid == pair[0] else del_b
            if deleted_at_x and m.created_at <= deleted_at_x:
                continue  # latest message predates or equals deletion — nothing new to show
            filtered.append(m)
        latest_msgs = filtered

        if not latest_msgs:
            return []

        other_ids = [m.receiver_id if m.sender_id == uid else m.sender_id for m in latest_msgs]

        users_result, unread_result = await asyncio.gather(
            self.uow.session.execute(select(User).where(User.id.in_(other_ids))),
            self.uow.session.execute(
                select(DirectMessage.sender_id, func.count().label("cnt"))
                .where(
                    DirectMessage.receiver_id == uid,
                    DirectMessage.is_read == False,
                    DirectMessage.is_shadowbanned == False,
                )
                .group_by(DirectMessage.sender_id)
            ),
        )
        users_map = {u.id: u for u in users_result.scalars().all()}
        unread_map = {row.sender_id: row.cnt for row in unread_result}

        conversations = []
        for msg in latest_msgs:
            other_id = msg.receiver_id if msg.sender_id == uid else msg.sender_id
            other_user = users_map.get(other_id)
            if not other_user:
                continue
            conversations.append(
                ConversationOut(
                    user_id=other_id,
                    username=other_user.username,
                    full_name=other_user.full_name,
                    last_message=msg.content,
                    last_message_type=msg.content_type,
                    last_at=msg.created_at,
                    unread_count=unread_map.get(other_id, 0),
                )
            )

        return conversations
