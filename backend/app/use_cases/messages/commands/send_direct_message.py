from sqlalchemy import select, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, ForbiddenException
from app.core.auto_mod import analyze_text_all
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.block import UserBlock
from app.models.follow import Follow
from app.schemas.message import MessageOut
from app.services.dm_broadcast import broadcast_dm
from app.utils.redis_client import get_redis

logger = get_logger(__name__)


def _thread_pair(a: int, b: int) -> tuple[int, int]:
    return min(a, b), max(a, b)


class SendDirectMessageCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        sender_id: int,
        receiver_id: int,
        content: str,
        listing_id: int | None,
        sender_username: str,
    ) -> MessageOut:
        if sender_id == receiver_id:
            raise ForbiddenException(code="SELF_MESSAGE_FORBIDDEN")

        async with self.uow:
            receiver = await self.uow.users.get(receiver_id)
            if not receiver:
                raise NotFoundException(code="USER_NOT_FOUND")

            block = await self.uow.session.scalar(
                select(UserBlock).where(
                    or_(
                        and_(UserBlock.blocker_id == sender_id, UserBlock.blocked_id == receiver_id),
                        and_(UserBlock.blocker_id == receiver_id, UserBlock.blocked_id == sender_id),
                    )
                ).limit(1)
            )
            if block:
                raise ForbiddenException(code="MESSAGING_FORBIDDEN")

            is_shadowbanned = analyze_text_all(content)

            msg = DirectMessage(
                sender_id=sender_id,
                receiver_id=receiver_id,
                listing_id=listing_id,
                content=content,
                is_shadowbanned=is_shadowbanned,
            )
            self.uow.session.add(msg)

            # Thread kaydı — ilk mesajsa oluştur
            user_a, user_b = _thread_pair(sender_id, receiver_id)
            existing_thread = await self.uow.session.scalar(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a,
                    MessageThread.user_b_id == user_b,
                )
            )
            is_new_request = False
            if not existing_thread:
                is_req = False
                if receiver.is_private:
                    follow_accepted = await self.uow.session.scalar(
                        select(Follow).where(
                            Follow.follower_id == sender_id,
                            Follow.followed_id == receiver_id,
                            Follow.status == "accepted",
                        )
                    )
                    if not follow_accepted:
                        is_req = True
                self.uow.session.add(MessageThread(
                    user_a_id=user_a, user_b_id=user_b, is_request=is_req,
                ))
                is_new_request = is_req

            await self.uow.session.flush()  # msg.id alınır
            msg_id = msg.id

        # commit sonrası — side effects
        if is_new_request:
            redis = await get_redis()
            await redis.incr(f"msg:unread:request:{receiver_id}")

        out = MessageOut(
            id=msg_id,
            sender_id=sender_id,
            receiver_id=receiver_id,
            sender_username=sender_username,
            content=content,
            content_type="text",
            is_read=False,
            created_at=msg.created_at,
        )
        dm_payload = {
            "type": "message",
            "id": msg_id,
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "sender_username": sender_username,
            "content": content,
            "content_type": "text",
            "is_read": False,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
        }
        if not is_shadowbanned:
            await broadcast_dm(receiver_id, dm_payload)
        await broadcast_dm(sender_id, dm_payload)

        if is_shadowbanned:
            logger.info(
                "[AUTO_MOD] DM shadowban | sender_id=%s receiver_id=%s", sender_id, receiver_id,
            )
        elif not is_new_request:
            from app.routers.notifications import push_notification
            await push_notification(
                receiver_id,
                {
                    "type": "message",
                    "i18n": {
                        "title_key": "notifMessage",
                        "title_params": {"username": sender_username},
                    },
                    "body": content[:100],
                    "related_id": sender_id,
                    "sender_username": sender_username,
                },
                pref_key="messages",
            )

        logger.info("[SendDirectMessageCommand] Başarılı | msg_id=%s", msg_id)
        return out
