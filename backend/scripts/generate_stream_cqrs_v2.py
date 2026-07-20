import os

commands_dir = "backend/app/use_cases/streams/commands"
queries_dir = "backend/app/use_cases/streams/queries"
os.makedirs(commands_dir, exist_ok=True)
os.makedirs(queries_dir, exist_ok=True)

# 1. JoinStreamCommand
with open(f"{commands_dir}/join_stream.py", "w") as f:
    f.write("""from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.user import User
from app.use_cases.streams.stream_utils import make_livekit_token
from app.utils.redis_client import get_redis
from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

class JoinStreamCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> dict:
        from app.services.moderation_service import kick_key
        async with self.uow:
            result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
            stream = result.scalar_one_or_none()

            if not stream or not stream.is_live:
                raise NotFoundException("Aktif yayın bulunamadı")

            if stream.host_id == user.id:
                raise BadRequestException("Kendi yayınınıza izleyici olarak katılamazsınız")

            redis = await get_redis()
            if await redis.sismember(kick_key(stream_id), str(user.id)):
                raise ForbiddenException("Bu yayına erişiminiz kısıtlanmıştır")

            token = make_livekit_token(stream.room_name, user, can_publish=False)

            await self.uow.session.execute(
                pg_insert(LiveStreamViewer)
                .values(stream_id=stream_id, user_id=user.id)
                .on_conflict_do_nothing()
            )
            await self.uow.commit()

            return {
                "stream_id": stream.id,
                "room_name": stream.room_name,
                "livekit_url": settings.livekit_url,
                "token": token,
                "title": stream.title,
                "category": stream.category,
                "host_username": stream.host.username,
                "host_livekit_identity": str(stream.host_id),
            }
""")

# 2. GetViewersQuery
with open(f"{queries_dir}/get_viewers.py", "w") as f:
    f.write("""from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis

class GetViewersQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> dict:
        async with self.uow:
            result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
            stream = result.scalar_one_or_none()
            if not stream or not stream.is_live:
                raise NotFoundException("Aktif yayın bulunamadı")
            if stream.host_id != user.id:
                raise ForbiddenException("Sadece host görüntüleyebilir")

            redis = await get_redis()
            members = await redis.smembers(f"live:viewer_set:{stream_id}")
            return {"viewers": sorted(list(members))}
""")
