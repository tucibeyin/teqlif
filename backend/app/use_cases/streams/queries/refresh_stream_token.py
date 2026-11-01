from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException, NodeUnavailableException
from app.models.stream import LiveStream
from app.models.enums import StreamStatus
from app.models.user import User
from app.use_cases.streams.stream_utils import make_livekit_token
from app.schemas.stream import StreamTokenOut
from app.services.edge_orchestrator import orchestrator
from app.core.logger import get_logger

logger = get_logger(__name__)


class RefreshStreamTokenQuery:
    """CQRS Query: Canlı yayın için yeni LiveKit token üretir.

    Host veya co-host (can_publish=True), izleyici (can_publish=False).
    """

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, current_user: User) -> StreamTokenOut:
        from app.utils.redis_client import get_redis

        async with self.uow:
            stream = await self.uow.session.scalar(
                select(LiveStream).where(LiveStream.id == stream_id)
            )
            if not stream or stream.status != StreamStatus.LIVE:
                raise NotFoundException(code="STREAM_NOT_FOUND")

            if not stream.livekit_url:
                raise BadRequestException(code="STREAM_NODE_MISSING")

            # Host reconnect sırasında kaynak node'un sağlığını kontrol et.
            # Node down ise 503/NODE_UNAVAILABLE dönerek Flutter'ın failover başlatmasını sağla.
            if stream.source_node_id and stream.host_id == current_user.id:
                if not await orchestrator.is_node_healthy(stream.source_node_id):
                    raise NodeUnavailableException()

            is_publisher = stream.host_id == current_user.id

            # Co-host kontrolü: co-host invite kabul ettiyse yayıncı olarak token alır
            if not is_publisher:
                redis = await get_redis()
                cohost_key = f"cohost_active:{stream_id}:{current_user.id}"
                if await redis.get(cohost_key):
                    is_publisher = True

            # İzleyiciler için relay aktifse relay node'una yönlendir (Kural 2 — JoinStream ile simetrik).
            # Token relay room_name'i ile üretilmeli; origin room_name'i ile üretilirse
            # izleyici relay odası yerine origin'e bağlanır → yük yığılması.
            room_name = stream.room_name
            livekit_url = stream.livekit_url
            if not is_publisher:
                endpoint = await orchestrator.resolve_stream_endpoint(stream)
                room_name = endpoint["room_name"]
                livekit_url = endpoint["livekit_url"]

            token = make_livekit_token(room_name, current_user, can_publish=is_publisher)

            logger.info(
                "[RefreshToken] stream_id=%s user_id=%s can_publish=%s room_name=%s",
                stream_id, current_user.id, is_publisher, room_name,
            )

            quality_profile = "pro" if (is_publisher and current_user.user_type == 'pro') else "standard"
            return StreamTokenOut(
                stream_id=stream.id,
                room_name=room_name,
                livekit_url=livekit_url,
                token=token,
                category=stream.category,
                video_quality_profile=quality_profile,
            )
