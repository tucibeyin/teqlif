import json

from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.stream import LiveStream
from app.models.enums import StreamStatus
from app.core.logger import get_logger
from app.schemas.stream import StreamTokenOut

logger = get_logger(__name__)

_PART_SEPARATOR = "_p"


class FailoverStreamCommand:
    """Kural 3: Source node çöktüğünde yayını yeni node'a taşır.

    Host bu endpoint'i NODE_UNAVAILABLE hatasında çağırır.
    Yeni room adı: {base_room}_p{part_number}
    """

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, host_id: int) -> StreamTokenOut:
        from app.services.edge_orchestrator import orchestrator, ServiceType
        from app.use_cases.streams.stream_utils import make_livekit_token
        from app.utils.redis_client import get_redis

        async with self.uow:
            stream = await self.uow.session.scalar(
                select(LiveStream).where(
                    LiveStream.id == stream_id,
                    LiveStream.host_id == host_id,
                    LiveStream.status == StreamStatus.LIVE,
                )
            )
            if not stream:
                raise NotFoundException(code="STREAM_NOT_FOUND")

            old_node_id = stream.source_node_id

            # Yeni node — çöken node dışında
            node = await orchestrator.allocate_node(
                ServiceType.MEDIA,
                exclude_node_id=old_node_id,
            )
            if not node.get("livekit_url"):
                raise BadRequestException(code="NO_AVAILABLE_NODE")

            # Yeni room adı: base_p<N>
            base_room = _base_room(stream.room_name)
            part_number = _next_part_number(stream.room_name)
            new_room = f"{base_room}{_PART_SEPARATOR}{part_number}"

            stream.room_name    = new_room
            stream.livekit_url  = node["livekit_url"]
            stream.source_node_id = node.get("node_id")
            await self.uow.session.commit()

        # room_to_stream + stream:meta güncelle; izleyicileri yeni odaya yönlendir
        try:
            redis = await get_redis()
            pipe = redis.pipeline()
            pipe.set(f"live:room_to_stream:{new_room}", f"{stream_id}:{host_id}", ex=48 * 3600)
            pipe.hset(f"stream:meta:{stream_id}", mapping={
                "room_name": new_room,
                "livekit_url": node["livekit_url"],
                "source_node_id": node.get("node_id", ""),
            })
            failover_msg = json.dumps({
                "type": "stream_failover",
                "stream_id": stream_id,
                "new_room_name": new_room,
                "new_livekit_url": node["livekit_url"],
            })
            pipe.publish(f"chat:{stream_id}", failover_msg)
            await pipe.execute()
        except Exception as exc:
            logger.warning("[Failover] Redis metadata ve broadcast güncellenemedi: %s", exc)

        logger.info(
            "[Failover] stream_id=%s old_node=%s new_node=%s new_room=%s",
            stream_id, old_node_id, node.get("node_id"), new_room,
        )

        user = stream.host
        token = make_livekit_token(new_room, user, can_publish=True)
        quality_profile = "pro" if user.user_type == 'pro' else "standard"
        return StreamTokenOut(
            stream_id=stream_id,
            room_name=new_room,
            livekit_url=node["livekit_url"],
            token=token,
            category=stream.category,
            video_quality_profile=quality_profile,
        )


def _base_room(room_name: str) -> str:
    """room_name içindeki _p<N> suffix'ini atar, base'i döner."""
    idx = room_name.rfind(_PART_SEPARATOR)
    if idx == -1:
        return room_name
    suffix = room_name[idx + len(_PART_SEPARATOR):]
    if suffix.isdigit():
        return room_name[:idx]
    return room_name


def _next_part_number(room_name: str) -> int:
    idx = room_name.rfind(_PART_SEPARATOR)
    if idx == -1:
        return 2
    suffix = room_name[idx + len(_PART_SEPARATOR):]
    if suffix.isdigit():
        return int(suffix) + 1
    return 2
