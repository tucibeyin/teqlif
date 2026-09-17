import logging
from datetime import timedelta
import aiohttp
from livekit.api.room_service import RoomService, DeleteRoomRequest
from sqlalchemy import select

from app.config import settings
from app.models.user import User
from app.models.block import UserBlock
from app.services.edge_orchestrator import orchestrator, ServiceType

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
        keys = [f"live:viewers:{s.id}" for s in streams]
        counts = await redis.mget(*keys)
        for stream, count in zip(streams, counts):
            stream.viewer_count = int(count) if count else 0
    except Exception:
        logger.error("[STREAMS] Redis viewer count okunamadı%s", f" | {tag}" if tag else "", exc_info=True)

async def delete_livekit_room(room_name: str, api_url: str = None) -> None:
    """LiveKit odasını zorla sil — Verilen URL'den veya tüm Edge node'lardan silmeyi dener."""
    urls_to_try = [api_url] if api_url else settings.edge_livekit_urls
    
    async with aiohttp.ClientSession() as session:
        for url in urls_to_try:
            if not url:
                continue
            try:
                svc = RoomService(
                    session,
                    url,
                    settings.livekit_api_key,
                    settings.livekit_api_secret,
                )
                req = DeleteRoomRequest()
                req.room = room_name
                await svc.delete_room(req)
                logger.info("[STREAMS] LiveKit oda silindi | room=%s node=%s", room_name, url)
                if api_url:
                    break
            except Exception as exc:
                err_str = str(exc).lower()
                if "not found" not in err_str and "does not exist" not in err_str and "not_found" not in err_str:
                    logger.warning("[STREAMS] LiveKit oda silinemedi | room=%s node=%s | %s", room_name, url, exc)

_LIVEKIT_TOKEN_TTL = timedelta(hours=24)

def make_livekit_token(room_name: str, user: User, can_publish: bool) -> str:
    """
    LiveKit JWT token üretir.
    API key/secret tüm Edge node'larda ortaktır — token içeriği Node bağımsızdır.
    """
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
