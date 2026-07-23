from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis

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
        return {"viewers": sorted(list(members))}
