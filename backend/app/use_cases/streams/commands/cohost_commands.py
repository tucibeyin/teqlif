from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis
from app.use_cases.chat.chat_utils import publish_chat
from app.constants import ws_types as WS
from app.core.logger import get_logger

logger = get_logger(__name__)

class InviteCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, target_username: str, host: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or not stream.is_live:
                raise NotFoundException(code="STREAM_NOT_FOUND")
            if stream.host_id != host.id:
                raise ForbiddenException(code="STREAM_HOST_ONLY_INVITE")

            target = await self.uow.session.scalar(select(User).where(User.username == target_username))
            if not target:
                raise NotFoundException(code="USER_NOT_FOUND")
            if target.id == host.id:
                raise ForbiddenException(code="SELF_INVITE_FORBIDDEN")

            redis = await get_redis()
            invite_key = f"cohost_invite:{stream_id}:{target.id}"
            await redis.set(invite_key, "1", ex=60)

            await publish_chat(stream_id, {
                "type": WS.COHOST_INVITE,
                "target_username": target.username,
                "host_username": host.username,
            })
            return {"message": f"@{target.username} sahneye davet edildi"}

class AcceptCohostInviteCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, current_user: User):
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or not stream.is_live:
                raise NotFoundException(code="STREAM_NOT_FOUND")

            redis = await get_redis()
            invite_key = f"cohost_invite:{stream_id}:{current_user.id}"
            if not await redis.get(invite_key):
                raise ForbiddenException(code="NO_STAGE_INVITATION")

            await redis.delete(invite_key)

            import aiohttp
            from app.config import settings
            from livekit.api.room_service import RoomService, UpdateParticipantRequest
            from livekit.protocol.models import ParticipantPermission

            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    settings.livekit_api_base,
                    settings.livekit_api_key,
                    settings.livekit_api_secret
                )
                try:
                    req = UpdateParticipantRequest(
                        room=stream.room_name,
                        identity=str(current_user.id),
                        permission=ParticipantPermission(
                            can_publish=True,
                            can_subscribe=True,
                            can_publish_data=True
                        )
                    )
                    await svc.update_participant(req)
                except Exception as e:
                    logger.error("[COHOST] Yetki yükseltilirken hata: %s", str(e))

            await publish_chat(stream_id, {
                "type": WS.COHOST_ACCEPTED,
                "username": current_user.username,
            })

            from app.use_cases.streams.stream_utils import make_livekit_token
            from app.schemas.stream import StreamTokenOut

            token = make_livekit_token(stream.room_name, current_user, can_publish=True)
            return StreamTokenOut(
                stream_id=stream.id,
                room_name=stream.room_name,
                livekit_url=settings.livekit_url,
                token=token,
                category=stream.category,
            )

class RemoveCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, target_username: str, host: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or not stream.is_live:
                raise NotFoundException(code="STREAM_NOT_FOUND")
            if stream.host_id != host.id:
                raise ForbiddenException(code="STREAM_HOST_ONLY_PERMISSIONS")

            target = await self.uow.session.scalar(select(User).where(User.username == target_username))
            if not target:
                raise NotFoundException(code="USER_NOT_FOUND")

            import aiohttp
            from app.config import settings
            from livekit.api.room_service import RoomService, UpdateParticipantRequest
            from livekit.protocol.models import ParticipantPermission

            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    settings.livekit_api_base,
                    settings.livekit_api_key,
                    settings.livekit_api_secret
                )
                try:
                    req = UpdateParticipantRequest(
                        room=stream.room_name,
                        identity=str(target.id),
                        permission=ParticipantPermission(
                            can_publish=False,
                            can_subscribe=True,
                            can_publish_data=False
                        )
                    )
                    await svc.update_participant(req)
                except Exception as e:
                    pass

            await publish_chat(stream_id, {
                "type": WS.COHOST_REMOVED,
                "target_username": target.username,
                "host_username": host.username,
            })
            return {"message": f"@{target.username} sahneden alındı"}

class LeaveCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, current_user: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or not stream.is_live:
                raise NotFoundException(code="STREAM_NOT_FOUND")

            import aiohttp
            from app.config import settings
            from livekit.api.room_service import RoomService, UpdateParticipantRequest
            from livekit.protocol.models import ParticipantPermission

            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    settings.livekit_api_base,
                    settings.livekit_api_key,
                    settings.livekit_api_secret
                )
                try:
                    req = UpdateParticipantRequest(
                        room=stream.room_name,
                        identity=str(current_user.id),
                        permission=ParticipantPermission(
                            can_publish=False,
                            can_subscribe=True,
                            can_publish_data=False
                        )
                    )
                    await svc.update_participant(req)
                except Exception as e:
                    pass

            await publish_chat(stream_id, {
                "type": WS.COHOST_REMOVED,
                "username": current_user.username,
            })
            return {"message": "Sahneden inildi, izleyici konumundasınız."}
