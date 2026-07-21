from fastapi import UploadFile
from sqlalchemy import select, text
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException, DatabaseException
from app.models.stream import LiveStream
from app.models.user import User
from app.core.logger import get_logger, capture_exception
from app.use_cases.streams.stream_utils import delete_livekit_room
from app.use_cases.chat.chat_utils import publish_chat
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

        return {"thumbnail_url": thumbnail_url}
