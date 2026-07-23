from sqlalchemy import select
from fastapi import BackgroundTasks
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, DatabaseException
from app.models.stream import LiveStream
from app.models.user import User
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

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

            stream.is_live = True

        from app.use_cases.streams.stream_utils import notify_followers_task
        background_tasks.add_task(
            notify_followers_task,
            user.id, user.username, stream.title, stream.id
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
