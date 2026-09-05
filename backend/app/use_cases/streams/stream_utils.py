import logging
from datetime import timedelta
import aiohttp
from livekit.api.room_service import RoomService, DeleteRoomRequest
from sqlalchemy import select

from app.config import settings
from app.models.user import User
from app.models.block import UserBlock

logger = logging.getLogger(__name__)

def _apply_block_filter(query, host_id_col, current_user_id: int):
    """Engelleme filtrelerini verilen SQLAlchemy query'ye uygular."""
    blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    blocking_me   = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    return query.where(
        host_id_col.not_in(blocked_by_me),
        host_id_col.not_in(blocking_me),
    )

async def _fill_viewer_counts(streams: list, tag: str = "") -> None:
    """
    Redis MGET ile tüm yayınların izleyici sayısını tek sorguda doldurur.
    Redis erişilemezse izleyici sayıları 0 kalır (graceful degrade).
    """
    if not streams:
        return
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        keys = [f"live:viewers:{s.room_name}" for s in streams]
        counts = await redis.mget(*keys)
        for stream, count in zip(streams, counts):
            stream.viewer_count = int(count) if count else 0
    except Exception:
        logger.error("[STREAMS] Redis viewer count okunamadı%s", f" | {tag}" if tag else "", exc_info=True)

async def delete_livekit_room(room_name: str) -> None:
    """LiveKit odasını zorla sil (tüm katılımcıları çıkarır)."""
    try:
        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret,
            )
            req = DeleteRoomRequest()
            req.room = room_name
            await svc.delete_room(req)
        logger.info("[STREAMS] LiveKit oda silindi | room=%s", room_name)
    except Exception as exc:
        logger.warning("[STREAMS] LiveKit oda silinemedi | room=%s | %s", room_name, exc)

_LIVEKIT_TOKEN_TTL = timedelta(hours=24)

def make_livekit_token(room_name: str, user: User, can_publish: bool) -> str:
    """LiveKit JWT token üretir."""
    try:
        from livekit.api import AccessToken, VideoGrants
        grant = VideoGrants(
            room_join=True,
            room=room_name,
            can_publish=can_publish,
            can_subscribe=True,
            can_publish_data=can_publish,
        )
        token = (
            AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
            .with_identity(str(user.id))
            .with_name(user.username)
            .with_grants(grant)
            .with_ttl(_LIVEKIT_TOKEN_TTL)
        )
        return token.to_jwt()
    except Exception:
        logger.error(
            "[STREAMS] LiveKit token oluşturulamadı | user_id=%s room=%s can_publish=%s",
            user.id, room_name, can_publish,
            exc_info=True,
        )
        raise

async def notify_followers_task(user_id: int, username: str, stream_title: str | None, stream_id: int) -> None:
    """Takipçi bildirimlerini tek ARQ job olarak kuyruğa alır — asyncio.create_task döngüsü yerine."""
    try:
        from app.core.task_queue import get_pool
        pool = get_pool()
        if not pool:
            logger.warning("[STREAMS] ARQ pool yok — takipçi bildirimi atlandı | stream=%d", stream_id)
            return
        await pool.enqueue_job(
            "send_stream_started_notifications",
            host_id=user_id,
            username=username,
            stream_title=stream_title,
            stream_id=stream_id,
            _queue_name="critical",
        )
    except Exception as exc:
        logger.error(
            "[STREAMS] Takipçi bildirim job'u kuyruğa alınamadı: %s",
            exc, exc_info=True,
        )
