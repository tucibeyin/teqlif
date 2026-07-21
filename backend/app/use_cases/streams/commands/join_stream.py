from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.stream import LiveStream, LiveStreamViewer
from app.models.user import User
from app.use_cases.streams.stream_utils import make_livekit_token
from app.utils.redis_client import get_redis
from app.config import settings
from app.core.logger import get_logger
from app.schemas.stream import JoinTokenOut

logger = get_logger(__name__)

class JoinStreamCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> JoinTokenOut:
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

            return JoinTokenOut(
                stream_id=stream.id,
                room_name=stream.room_name,
                livekit_url=settings.livekit_url,
                token=token,
                title=stream.title,
                category=stream.category,
                host_username=stream.host.username,
                host_livekit_identity=str(stream.host_id),
            )
