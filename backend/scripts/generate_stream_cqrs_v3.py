import os

commands_dir = "backend/app/use_cases/streams/commands"
queries_dir = "backend/app/use_cases/streams/queries"
os.makedirs(commands_dir, exist_ok=True)
os.makedirs(queries_dir, exist_ok=True)

misc_commands = """from fastapi import UploadFile
from sqlalchemy import select, text
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException, DatabaseException
from app.models.stream import LiveStream
from app.models.user import User
from app.core.logger import get_logger, capture_exception
from app.use_cases.streams.stream_utils import delete_livekit_room
from app.services.chat_service import publish_chat
from app.constants import ws_types as WS
from app.config import settings

logger = get_logger(__name__)

class EndStreamCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream:
                raise NotFoundException("Yayın bulunamadı")
            if stream.host_id != user.id:
                raise ForbiddenException("Bu yayını sonlandırma yetkiniz yok")

            if stream.is_live:
                from datetime import datetime, timezone
                stream.is_live = False
                stream.ended_at = datetime.now(timezone.utc)
                await delete_livekit_room(stream.room_name)

                # Clear highlights and likes
                try:
                    await self.uow.session.execute(
                        text("DELETE FROM listings WHERE active_room_id = :rid AND is_highlight = TRUE"),
                        {"rid": stream_id},
                    )
                except Exception:
                    pass

                await self.uow.commit()

                try:
                    await publish_chat(stream_id, {"type": WS.STREAM_ENDED})
                    from app.core.ws_manager import ws_manager
                    await ws_manager.publish("chat_broadcast", "global", {"type": WS.STREAM_ENDED, "stream_id": stream_id})
                except Exception:
                    pass

        return {"message": "Yayın sonlandırıldı"}

class UpdateThumbnailCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, user: User, file: UploadFile) -> dict:
        from app.routers.upload import _detect_image_type
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream:
                raise NotFoundException("Yayın bulunamadı")
            if stream.host_id != user.id:
                raise ForbiddenException("Bu yayını düzenleme yetkiniz yok")
            if not stream.is_live:
                raise BadRequestException("Yayın aktif değil")

            data = await file.read()
            if len(data) > 10 * 1024 * 1024:
                raise BadRequestException("Dosya 10 MB'ı geçemez")

            ext = _detect_image_type(data)
            if ext is None:
                raise BadRequestException("Sadece JPEG, PNG veya WebP yüklenebilir")

            import uuid
            from app.services import storage_service as storage
            _CONTENT_TYPES = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
            filename = f"thumb_{uuid.uuid4().hex}.{ext}"
            thumbnail_url = storage.upload_bytes(filename, data, _CONTENT_TYPES[ext])

            stream.thumbnail_url = thumbnail_url
            await self.uow.commit()

        return {"thumbnail_url": thumbnail_url}
"""

misc_queries = """from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.stream import LiveStream
from app.models.user import User
from app.models.follow import Follow
from app.use_cases.streams.stream_utils import _fill_viewer_counts, _apply_block_filter
from app.services.like_service import LikeService

class GetFollowedLiveStreamsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user_id: int) -> list:
        async with self.uow:
            query = (
                select(LiveStream)
                .join(Follow, Follow.followed_id == LiveStream.host_id)
                .where(
                    Follow.follower_id == current_user_id,
                    LiveStream.is_live == True,
                )
                .order_by(LiveStream.started_at.desc())
            )
            result = await self.uow.session.execute(query)
            streams = result.scalars().all()

            await _fill_viewer_counts(streams, tag=f"followed user_id={current_user_id}")

            stream_ids = [s.id for s in streams]
            like_counts = await LikeService.batch_stream_likes(self.uow.session, stream_ids)
            for stream in streams:
                stream.likes_count = like_counts.get(stream.id, 0)

            return streams

class GetActiveStreamsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, current_user_id: int) -> list:
        async with self.uow:
            query = (
                select(LiveStream)
                .where(LiveStream.is_live == True)
                .order_by(LiveStream.started_at.desc())
                .limit(100)
            )
            if current_user_id:
                query = _apply_block_filter(query, LiveStream.host_id, current_user_id)
            
            result = await self.uow.session.execute(query)
            streams = result.scalars().all()

            await _fill_viewer_counts(streams, tag="active_streams")
            
            stream_ids = [s.id for s in streams]
            like_counts = await LikeService.batch_stream_likes(self.uow.session, stream_ids)
            for stream in streams:
                stream.likes_count = like_counts.get(stream.id, 0)
                
            return streams
"""

with open(f"{commands_dir}/misc_commands.py", "w") as f: f.write(misc_commands)
with open(f"{queries_dir}/misc_queries.py", "w") as f: f.write(misc_queries)
print("Generated misc stream files.")
