from datetime import timedelta

from sqlalchemy import select, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.user import User
from app.schemas.message import MessageOut
from app.constants.media_limits import MSG_PAGE_SIZE
from app.services import storage_service as storage
from app.utils.redis_client import get_redis

_PRESIGN_TTL = timedelta(days=7)
_CACHE_TTL_SECS = 6 * 24 * 3600  # 6 gün — 1 gün buffer


class GetMessagesQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    @staticmethod
    async def _presign_if_dm(url: str | None, viewer_id: int) -> str | None:
        """DM media URL'ini presigned URL'e çevirir (Redis cache'li)."""
        if not storage.is_dm_url(url):
            return url
        key = storage.dm_url_to_key(url)  # type: ignore[arg-type]
        redis = await get_redis()
        cache_key = f"presign:{viewer_id}:{key}"
        cached = await redis.get(cache_key)
        if cached:
            return cached
        try:
            signed = storage.presign_get(key, expires=_PRESIGN_TTL)
            await redis.set(cache_key, signed, ex=_CACHE_TTL_SECS)
            return signed
        except Exception:
            return url  # presign başarısız → DB URL'ini döndür

    async def execute(
        self, uid: int, other_user_id: int, before_id: int | None = None
    ) -> list[MessageOut]:
        other_result = await self.uow.session.execute(
            select(User).where(User.id == other_user_id)
        )
        other_user = other_result.scalar_one_or_none()
        if not other_user:
            raise NotFoundException(code="USER_NOT_FOUND")

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
            ~and_(DirectMessage.sender_id == uid, DirectMessage.deleted_for_sender == True),
            ~and_(DirectMessage.receiver_id == uid, DirectMessage.deleted_for_receiver == True),
        ]
        if deleted_at_x:
            base_where.append(DirectMessage.created_at > deleted_at_x)
        if before_id is not None:
            base_where.append(DirectMessage.id < before_id)

        result = await self.uow.session.execute(
            select(DirectMessage)
            .where(*base_where)
            .order_by(DirectMessage.created_at.desc())
            .limit(MSG_PAGE_SIZE)
        )
        messages = list(reversed(result.scalars().all()))

        sender_ids = {m.sender_id for m in messages}
        users_result = await self.uow.session.execute(
            select(User).where(User.id.in_(sender_ids))
        )
        users_map = {u.id: u for u in users_result.scalars().all()}

        result_list = []
        for msg in messages:
            media_url = await self._presign_if_dm(msg.media_url, uid)
            thumbnail_url = await self._presign_if_dm(msg.thumbnail_url, uid)
            result_list.append(
                MessageOut(
                    id=msg.id,
                    sender_id=msg.sender_id,
                    receiver_id=msg.receiver_id,
                    sender_username=users_map[msg.sender_id].username if msg.sender_id in users_map else "",
                    content=msg.content,
                    content_type=msg.content_type,
                    media_url=media_url,
                    thumbnail_url=thumbnail_url,
                    duration_secs=msg.duration_secs,
                    file_name=msg.file_name,
                    file_size=msg.file_size,
                    is_read=msg.is_read,
                    created_at=msg.created_at,
                )
            )
        return result_list
