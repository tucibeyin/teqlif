from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis
from app.services.moderation_service import mute_key


class GetViewersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> dict:
        result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException(code="STREAM_NOT_FOUND")
        if stream.host_id != user.id:
            raise ForbiddenException(code="HOST_ONLY_VIEW")

        redis = await get_redis()
        members = await redis.smembers(f"live:viewer_set:{stream_id}")
        muted_ids = await redis.smembers(mute_key(stream_id))

        muted_usernames: set[str] = set()
        if muted_ids:
            try:
                uid_ints = [int(uid) for uid in muted_ids]
                rows = await self.uow.session.execute(
                    select(User.id, User.username).where(User.id.in_(uid_ints))
                )
                muted_usernames = {row.username for row in rows.all()}
            except Exception:
                pass

        viewers = [
            {"username": uname, "is_muted": uname in muted_usernames}
            for uname in sorted(members)
        ]
        return {"viewers": viewers}
