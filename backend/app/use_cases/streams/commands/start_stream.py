from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import BadRequestException, NotFoundException
from app.models.enums import StreamStatus
from app.models.stream import LiveStream
from app.services.subscription.tier import quality_profile, stream_limit_minutes

PENDING_STALE_MINUTES = 5

logger = get_logger(__name__)

class StartStreamCommand:
    """CQRS Command: Kullanıcı canlı yayın başlatır."""
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, user_id: int, title: str, category: str = None, subcategory: str = None, listing_id: int = None, thumbnail_url: str = None) -> dict:
        import uuid
        from app.config import settings
        from app.use_cases.streams.stream_utils import make_livekit_token
        from app.services.edge_orchestrator import orchestrator, ServiceType

        logger.info("[StartStreamCommand] Başlatıldı | user_id=%s title=%s", user_id, title)
        
        if not title.strip():
            logger.warning("[StartStreamCommand] Boş yayın başlığı | user_id=%s", user_id)
            raise BadRequestException(code="STREAM_TITLE_REQUIRED")

        async with self.uow:
            user = await self.uow.users.get(user_id)
            if not user:
                raise NotFoundException(code="USER_NOT_FOUND")

            # Aylık reset: yeni ay başladıysa sayacı sıfırla
            now_utc = datetime.now(timezone.utc)
            reset_at = user.monthly_stream_reset_at
            if reset_at is None or reset_at.year != now_utc.year or reset_at.month != now_utc.month:
                user.monthly_stream_minutes_used = 0
                user.monthly_stream_reset_at = now_utc
                await self.uow.session.flush()

            # Aylık yayın süresi kontrolü — bonus dakikalar aylık limite ek olarak sayılır
            limit = stream_limit_minutes(user.user_type)
            if limit is not None:
                effective_limit = limit + (user.stream_minutes_bonus or 0)
                if (user.monthly_stream_minutes_used or 0) >= effective_limit:
                    raise BadRequestException(code="STREAM_MONTHLY_LIMIT_REACHED")

            existing = await self.uow.session.scalar(
                select(LiveStream).where(
                    LiveStream.host_id == user_id,
                    LiveStream.ended_at.is_(None),
                )
            )
            if existing:
                stale_cutoff = datetime.now(timezone.utc) - timedelta(minutes=PENDING_STALE_MINUTES)
                is_stale_pending = (
                    not existing.is_live
                    and existing.status == "pending"
                    and existing.started_at < stale_cutoff
                )
                if is_stale_pending:
                    logger.warning(
                        "[StartStreamCommand] Takılı pending yayın temizlendi | user_id=%s stream_id=%s",
                        user_id, existing.id,
                    )
                    existing.status = "ended"
                    existing.ended_at = datetime.now(timezone.utc)
                    await self.uow.session.flush()
                else:
                    logger.warning(
                        "[StartStreamCommand] Aktif yayın zaten var | user_id=%s stream_id=%s",
                        user_id, existing.id,
                    )
                    raise BadRequestException(code="STREAM_ALREADY_ACTIVE")

            node = await orchestrator.allocate_node(ServiceType.MEDIA)

            room_name = str(uuid.uuid4())
            stream_data = {
                "room_name": room_name,
                "host_id": user_id,
                "title": title.strip(),
                "is_live": False,
                "category": category if category else "other",
                "subcategory": subcategory,
                "thumbnail_url": thumbnail_url,
                "livekit_url": node["livekit_url"],  # Edge node kalıcı olarak kayıt altına alınır
                "source_node_id": node.get("node_id"),
            }
            new_stream = await self.uow.streams.create(obj_in=stream_data)
            token = make_livekit_token(room_name, user, can_publish=True)

        from app.core.event_bus import event_bus
        from app.core.events import StreamStartedEvent

        event_bus.publish(
            StreamStartedEvent(
                stream_id=new_stream.id,
                user_id=user_id,
                title=title
            )
        )

        # Webhook'un stream_id ve host_id'yi room_name'den çözebilmesi için mapping
        try:
            from app.utils.redis_client import get_redis
            redis = await get_redis()
            await redis.set(
                f"live:room_to_stream:{room_name}",
                f"{new_stream.id}:{user_id}",
                ex=48 * 3600,
            )
        except Exception as exc:
            logger.warning("[StartStreamCommand] room_to_stream mapping yazılamadı: %s", exc)

        video_quality = quality_profile(user.user_type)
        logger.info("[StartStreamCommand] Başarılı | stream_id=%s node=%s quality=%s", new_stream.id, node.get("node_id"), video_quality)

        return {
            "stream_id": new_stream.id,
            "room_name": room_name,
            "livekit_url": node["livekit_url"],  # DB'ye yazılan node ile aynı
            "token": token,
            "category": category if category else "other",
            "video_quality_profile": video_quality,
        }
