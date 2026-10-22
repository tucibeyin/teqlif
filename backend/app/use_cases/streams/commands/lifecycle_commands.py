import json

from sqlalchemy import select
from fastapi import BackgroundTasks
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, DatabaseException
from app.models.stream import LiveStream
from app.models.enums import StreamStatus
from app.models.user import User
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

_RECORDING_CHANNEL = "teqlif:recording:stream_started"


async def _publish_recording_event(
    stream_id: int,
    room_name: str,
    host_id: int,
    source_node_id: str | None = None,
) -> None:
    """Agent'a kayıt başlat sinyali gönderir (fire-and-forget)."""
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        payload = json.dumps({
            "stream_id": stream_id,
            "room_name": room_name,
            "host_id": host_id,
            "source_node_id": source_node_id,
        })
        await redis.publish(_RECORDING_CHANNEL, payload)
        logger.info("[STREAMS] Recording eventi yayınlandı | stream_id=%d", stream_id)
    except Exception as exc:
        logger.warning("[STREAMS] Recording eventi yayınlanamadı | stream_id=%d | %s", stream_id, exc)

class ConfirmLiveCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User, background_tasks: BackgroundTasks) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(
                select(LiveStream).where(
                    LiveStream.id == stream_id,
                    LiveStream.host_id == user.id,
                    LiveStream.is_live == False,
                    LiveStream.ended_at.is_(None),
                )
            )
            if not stream:
                raise NotFoundException(code="PENDING_STREAM_NOT_FOUND")

            try:
                stream.is_live = True
                stream.status = StreamStatus.LIVE
                await self.uow.session.commit()
            except Exception as exc:
                try:
                    from app.use_cases.streams.stream_utils import delete_livekit_room
                    await delete_livekit_room(stream.room_name)
                    await self.uow.session.delete(stream)
                    await self.uow.session.commit()
                except Exception:
                    pass  # webhook 2dk'da temizler
                raise DatabaseException(code="CONFIRM_LIVE_FAILED") from exc

        from app.use_cases.streams.stream_utils import notify_followers_task
        background_tasks.add_task(
            notify_followers_task,
            user.id, user.username, stream.title, stream.id
        )
        background_tasks.add_task(
            _publish_recording_event,
            stream.id, stream.room_name, stream.host_id, stream.source_node_id,
        )
        logger.info("[STREAMS] Yayın yayına alındı ve bildirimler tetiklendi | stream_id=%s", stream_id)
        return {"message": "Yayın canlıya alındı"}


class CancelPendingStreamCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(
                select(LiveStream).where(
                    LiveStream.id == stream_id,
                    LiveStream.host_id == user.id,
                    LiveStream.is_live == False,
                    LiveStream.ended_at.is_(None),
                )
            )
            if not stream:
                raise NotFoundException(code="PENDING_STREAM_NOT_FOUND")

            from app.use_cases.streams.stream_utils import delete_livekit_room
            await delete_livekit_room(stream.room_name)

            await self.uow.session.delete(stream)

        logger.info("[STREAMS] Beklemedeki yayın iptal edildi | stream_id=%s", stream_id)
        return {"message": "Yayın iptal edildi"}
