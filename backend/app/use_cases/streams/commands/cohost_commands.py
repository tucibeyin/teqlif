from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.models.stream import LiveStream
from app.models.enums import StreamStatus
from app.models.user import User
from app.utils.redis_client import get_redis
from app.use_cases.chat.chat_utils import publish_chat
from app.constants import ws_types as WS
from app.core.logger import get_logger
from app.services.edge_orchestrator import orchestrator, ServiceType

logger = get_logger(__name__)

class InviteCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, target_username: str, host: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or stream.status != StreamStatus.LIVE:
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
            if not stream or stream.status != StreamStatus.LIVE:
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

            if not stream.livekit_url:
                logger.error("[COHOST] Yayının livekit_url'i yok! stream_id=%s", stream.id)
                raise BadRequestException(code="STREAM_NODE_MISSING")
            api_url = stream.livekit_url

            from app.use_cases.streams.stream_utils import make_livekit_token
            from app.schemas.stream import StreamTokenOut

            # İzleyici relay'deyse UpdateParticipant çalışmaz (ParticipantNotFound).
            # Relay durumunda direkt source node token'ı döneriz; Flutter disconnect+reconnect yapar.
            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    api_url,
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
                    err = str(e).lower()
                    if "not found" in err or "participant" in err:
                        # İzleyici relay node'undaydı — source node token'ı ver
                        relay_used = True
                        logger.info(
                            "[COHOST] Relay→source geçişi yapılıyor | stream=%s user=%s",
                            stream_id, current_user.id,
                        )
                    else:
                        logger.error("[COHOST] Yetki yükseltilirken hata: %s", str(e), exc_info=True)
                        raise BadRequestException(code="COHOST_GRANT_FAILED")

            await publish_chat(stream_id, {
                "type": WS.COHOST_ACCEPTED,
                "username": current_user.username,
            })

            # live:cohost:joined → relay agent ikinci subprocess başlatır
            try:
                redis2 = await get_redis()
                import json as _json
                await redis2.publish(
                    f"live:cohost:joined:{stream_id}",
                    _json.dumps({"user_id": current_user.id, "identity": str(current_user.id)}),
                )
            except Exception as exc:
                logger.warning("[COHOST] cohost:joined pub/sub başarısız: %s", exc)

            token = make_livekit_token(stream.room_name, current_user, can_publish=True)
            quality_profile = "pro" if current_user.is_premium else "standard"
            return StreamTokenOut(
                stream_id=stream.id,
                room_name=stream.room_name,
                livekit_url=api_url,  # source node URL — Flutter relay varsa reconnect yapar
                token=token,
                category=stream.category,
                video_quality_profile=quality_profile,
            )

class RemoveCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, target_username: str, host: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or stream.status != StreamStatus.LIVE:
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

            if not stream.livekit_url:
                raise BadRequestException(code="STREAM_NODE_MISSING")
            api_url = stream.livekit_url

            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    api_url,
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
                    logger.error(
                        "[COHOST] UpdateParticipant başarısız (remove) | stream=%s user=%s | %s",
                        stream_id, target.id, e,
                    )
                    raise BadRequestException(code="COHOST_REMOVE_FAILED")

            await publish_chat(stream_id, {
                "type": WS.COHOST_REMOVED,
                "target_username": target.username,
                "host_username": host.username,
            })

            # live:cohost:left → relay agent co-host subprocess'ini sonlandırır
            try:
                import json as _json2
                redis3 = await get_redis()
                await redis3.publish(
                    f"live:cohost:left:{stream_id}",
                    _json2.dumps({"user_id": target.id, "identity": str(target.id)}),
                )
            except Exception as exc:
                logger.warning("[COHOST] cohost:left pub/sub başarısız: %s", exc)

            return {"message": f"@{target.username} sahneden alındı"}

class LeaveCohostCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, current_user: User) -> dict:
        async with self.uow:
            stream = await self.uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if not stream or stream.status != StreamStatus.LIVE:
                raise NotFoundException(code="STREAM_NOT_FOUND")

            import aiohttp
            from app.config import settings
            from livekit.api.room_service import RoomService, UpdateParticipantRequest
            from livekit.protocol.models import ParticipantPermission

            if not stream.livekit_url:
                raise BadRequestException(code="STREAM_NODE_MISSING")
            api_url = stream.livekit_url

            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    api_url,
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

            # live:cohost:left → relay agent co-host subprocess'ini sonlandırır
            try:
                import json as _json3
                redis4 = await get_redis()
                await redis4.publish(
                    f"live:cohost:left:{stream_id}",
                    _json3.dumps({"user_id": current_user.id, "identity": str(current_user.id)}),
                )
            except Exception as exc:
                logger.warning("[COHOST] cohost:left pub/sub başarısız: %s", exc)

            return {"message": "Sahneden inildi, izleyici konumundasınız."}
