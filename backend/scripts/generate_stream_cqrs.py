import os

commands_dir = "backend/app/use_cases/streams/commands"
queries_dir = "backend/app/use_cases/streams/queries"
os.makedirs(commands_dir, exist_ok=True)
os.makedirs(queries_dir, exist_ok=True)

join_stream = """from sqlalchemy import select
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
            await self.uow.commit()

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
"""

get_viewers = """from sqlalchemy import select
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
"""

cohost_cmds = """from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.stream import LiveStream
from app.models.user import User
from app.utils.redis_client import get_redis
from app.services.chat_service import publish_chat
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
                raise NotFoundException("Aktif yayın bulunamadı")
            if stream.host_id != host.id:
                raise ForbiddenException("Sadece yayın sahibi davet gönderebilir")

            target = await self.uow.session.scalar(select(User).where(User.username == target_username))
            if not target:
                raise NotFoundException("Kullanıcı bulunamadı")
            if target.id == host.id:
                raise BadRequestException("Kendinizi davet edemezsiniz")

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
                raise NotFoundException("Aktif yayın bulunamadı")

            redis = await get_redis()
            invite_key = f"cohost_invite:{stream_id}:{current_user.id}"
            if not await redis.get(invite_key):
                raise ForbiddenException("Geçerli bir sahne davetiniz yok")

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
                raise NotFoundException("Aktif yayın bulunamadı")
            if stream.host_id != host.id:
                raise ForbiddenException("Sadece yayın sahibi yetkileri alabilir")

            target = await self.uow.session.scalar(select(User).where(User.username == target_username))
            if not target:
                raise NotFoundException("Kullanıcı bulunamadı")

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
                raise NotFoundException("Aktif yayın bulunamadı")

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
                "type": WS.COHOST_LEFT,
                "username": current_user.username,
            })
            return {"message": "Sahneden inildi, izleyici konumundasınız."}
"""

with open(f"{commands_dir}/join_stream.py", "w") as f: f.write(join_stream)
with open(f"{commands_dir}/cohost_commands.py", "w") as f: f.write(cohost_cmds)
with open(f"{queries_dir}/get_viewers.py", "w") as f: f.write(get_viewers)

print("Generated stream files.")
