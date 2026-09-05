import asyncio
import aiohttp
import logging
import time
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Request, BackgroundTasks
from app.core.exceptions import UnauthorizedException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from livekit.api import WebhookReceiver, TokenVerifier
from livekit.api.room_service import RoomService, ListRoomsRequest

from app.database import get_db, AsyncSessionLocal
from app.models.stream import LiveStream
from app.utils.redis_client import get_redis
from app.config import settings
from app.core.task_queue import get_pool

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/webhooks", tags=["webhooks"])

_receiver = WebhookReceiver(TokenVerifier(settings.livekit_api_key, settings.livekit_api_secret))


@router.api_route("/livekit", methods=["GET", "POST"], include_in_schema=False)
async def livekit_webhook(request: Request, background_tasks: BackgroundTasks):
    body = await request.body()

    # LiveKit bazen GET ile gönderir; body yoksa probe (sağlık kontrolü)
    if not body:
        return {"status": "ok"}

    auth_header = request.headers.get("Authorization", "")
    try:
        event = _receiver.receive(body.decode(), auth_header)
    except Exception:
        logger.error("LiveKit webhook imza doğrulaması başarısız | method=%s", request.method, exc_info=True)
        raise UnauthorizedException()

    event_type = event.event
    room_name = event.room.name if event.room else None

    logger.info("LiveKit webhook alındı | method=%s event=%s room=%s", request.method, event_type, room_name)

    if event_type == "room_finished" and room_name:
        if room_name.startswith("call_"):
            background_tasks.add_task(_on_call_room_finished, room_name)
        else:
            background_tasks.add_task(_delayed_close_stream, room_name)

    # Katılımcı olayları — host grace period / reconnect yönetimi
    if room_name and event.participant and not room_name.startswith("call_"):
        identity = event.participant.identity or ""
        if event_type == "participant_left":
            background_tasks.add_task(_on_host_left, room_name, identity, time.time())
        elif event_type == "participant_joined":
            background_tasks.add_task(_on_host_rejoined, room_name, identity)

    return {"ok": True}


_HOST_GRACE_SECONDS = 120  # 2 dakika bekleme süresi

async def _on_call_room_finished(room_name: str) -> None:
    """Ghost call cleanup from LiveKit webhook for calls."""
    try:
        from app.database import AsyncSessionLocal
        from app.models.call import Call
        from sqlalchemy import select
        from app.core.ws_manager import ws_manager
        from datetime import datetime, timezone

        async with AsyncSessionLocal() as db:
            result = await db.execute(select(Call).where(Call.room_name == room_name))
            call = result.scalar_one_or_none()
            if not call or call.status in ("ended", "missed", "rejected"):
                return
            
            logger.info("Call %s closed via Webhook (room_finished)", room_name)
            call.status = "ended"
            call.ended_at = datetime.now(timezone.utc)
            call_id = call.id
            caller_id = call.caller_id
            callee_id = call.callee_id
            await db.commit()

            # NX lock: if end_call API already set this key, skip — avoids 182ms duplicate delivery.
            from app.utils.redis_client import get_redis as _get_redis
            _redis = await _get_redis()
            if not await _redis.set(f"call_ended_sent:{call_id}", "webhook", ex=60, nx=True):
                logger.info("[CALL_PROCESS][END] Webhook: call_ended already sent by API, skipping | call_id=%s", call_id)
                return

            logger.info("[CALL_PROCESS][END] Webhook room_finished: sending call_ended to caller %s and callee %s", caller_id, callee_id)
            _DM = "dm_broadcast"
            await ws_manager.publish(_DM, f"dm:{caller_id}", {"type": "call_ended", "call_id": call_id})
            await ws_manager.publish(_DM, f"dm:{callee_id}", {"type": "call_ended", "call_id": call_id})
            
    except Exception as exc:
        logger.error(f"Error closing ghost call {room_name} via webhook: {exc}", exc_info=True)


async def _on_host_left(room_name: str, identity: str, disconnected_at: float) -> None:
    """
    Host LiveKit odasından ayrıldığında çağrılır.
    ARQ job olarak planlanır; restart-safe. ARQ yoksa asyncio.sleep fallback.
    """
    stream_id: int | None = None
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(LiveStream).where(
                LiveStream.room_name == room_name,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        stream = result.scalar_one_or_none()
        if not stream or str(stream.host_id) != identity:
            return  # Yayıncı değil, izleyici ayrıldı — işlem yok
        stream_id = stream.id

    logger.warning(
        "[STREAMS] Host ayrıldı — %d sn grace period başladı | stream_id=%s room=%s",
        _HOST_GRACE_SECONDS, stream_id, room_name,
    )

    pool = get_pool()
    if pool:
        await pool.enqueue_job(
            "auto_close_stream_if_host_absent_task",
            stream_id,
            room_name,
            disconnected_at,
            _defer_by=timedelta(seconds=_HOST_GRACE_SECONDS),
            _job_id=f"close_stream_{stream_id}_{int(disconnected_at)}",
        )
        return

    # Fallback: ARQ pool yok (geliştirme ortamı vb.)
    await asyncio.sleep(_HOST_GRACE_SECONDS)

    try:
        redis = await get_redis()
        reconnect_raw = await redis.get(f"live:host_reconnect:{stream_id}")
        if reconnect_raw and float(reconnect_raw) > disconnected_at:
            logger.info("[STREAMS] Host grace period içinde geri döndü — kapatma iptal | stream_id=%s", stream_id)
            return
    except Exception as exc:
        logger.warning("[STREAMS] Redis host_reconnect okunamadı | stream_id=%s | %s", stream_id, exc)

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(LiveStream).where(
                LiveStream.id == stream_id,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        if not result.scalar_one_or_none():
            return
        logger.warning(
            "[STREAMS] Host %d sn görüntü göndermedi — yayın otomatik kapatılıyor | stream_id=%s",
            _HOST_GRACE_SECONDS, stream_id,
        )
        from app.use_cases.streams.commands.force_close_stream import force_close_stream
        await force_close_stream(db, room_name)


async def _on_host_rejoined(room_name: str, identity: str) -> None:
    """Host LiveKit odasına geri dönünce zaman damgasını Redis'e yazar."""
    stream_id: int | None = None
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(LiveStream).where(
                LiveStream.room_name == room_name,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        stream = result.scalar_one_or_none()
        if not stream or str(stream.host_id) != identity:
            return
        stream_id = stream.id

    try:
        redis = await get_redis()
        await redis.set(f"live:host_reconnect:{stream_id}", str(time.time()), ex=600)
        logger.info("[STREAMS] Host geri döndü | stream_id=%s room=%s", stream_id, room_name)
    except Exception as exc:
        logger.warning("[STREAMS] Redis host_reconnect yazılamadı | stream_id=%s | %s", stream_id, exc)


_VIEWER_TTL = 48 * 3600  # 48 saat


async def _resolve_stream_and_host(room_name: str) -> tuple[int, int] | None:
    """room_to_stream Redis mapping'inden (stream_id, host_id) döner. Yoksa None."""
    try:
        redis = await get_redis()
        val = await redis.get(f"live:room_to_stream:{room_name}")
        if not val:
            return None
        raw = val.decode() if isinstance(val, bytes) else val
        parts = raw.split(":")
        if len(parts) != 2:
            return None
        return int(parts[0]), int(parts[1])
    except Exception as exc:
        logger.debug("[WEBHOOK] room_to_stream lookup başarısız | room=%s | %s", room_name, exc)
        return None


async def _on_viewer_joined(room_name: str, identity: str) -> None:
    """Viewer (non-host) LiveKit'e katıldığında sayacı artırır."""
    mapping = await _resolve_stream_and_host(room_name)
    if not mapping:
        return
    stream_id, host_id = mapping
    if identity == str(host_id):
        return  # host is not a viewer

    try:
        from app.use_cases.chat.chat_utils import publish_chat
        from app.constants import ws_types as WS
        redis = await get_redis()
        key = f"live:viewers:{stream_id}"
        peak_key = f"live:peak_viewers:{stream_id}"
        count = await redis.incr(key)
        await redis.expire(key, _VIEWER_TTL)
        peak_raw = await redis.get(peak_key)
        current_peak = int(peak_raw) if peak_raw else 0
        if count > current_peak:
            await redis.setex(peak_key, _VIEWER_TTL, count)
        await publish_chat(stream_id, {"type": WS.VIEWER_COUNT, "count": int(count)})
    except Exception as exc:
        logger.warning("[WEBHOOK] viewer_joined INCR başarısız | stream=%s | %s", stream_id, exc)


async def _on_viewer_left(room_name: str, identity: str) -> None:
    """Viewer (non-host) LiveKit'ten ayrıldığında sayacı azaltır."""
    mapping = await _resolve_stream_and_host(room_name)
    if not mapping:
        return
    stream_id, host_id = mapping
    if identity == str(host_id):
        return  # host is not a viewer

    try:
        from app.use_cases.chat.chat_utils import publish_chat
        from app.constants import ws_types as WS
        redis = await get_redis()
        key = f"live:viewers:{stream_id}"
        count = await redis.decr(key)
        if count < 0:
            await redis.set(key, 0)
            count = 0
        await redis.expire(key, _VIEWER_TTL)
        await publish_chat(stream_id, {"type": WS.VIEWER_COUNT, "count": int(count)})
    except Exception as exc:
        logger.warning("[WEBHOOK] viewer_left DECR başarısız | stream=%s | %s", stream_id, exc)


async def _delayed_close_stream(room_name: str) -> None:
    """room_finished webhook'tan 60sn sonra oda hâlâ aktifse kapatır. ARQ yoksa asyncio.sleep fallback."""
    pool = get_pool()
    if pool:
        await pool.enqueue_job(
            "delayed_close_stream_task",
            room_name,
            _defer_by=timedelta(seconds=60),
            _job_id=f"delayed_close_{room_name}",
        )
        return

    # Fallback: ARQ pool yok
    await asyncio.sleep(60)
    try:
        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret,
            )
            res = await svc.list_rooms(ListRoomsRequest())
            if any(r.name == room_name for r in res.rooms):
                logger.info("LiveKit webhook: %s odası hala/yeniden aktif, kapatma iptal edildi.", room_name)
                return
    except Exception:
        logger.warning("LiveKit API check failed for %s, proceeding to close stream", room_name)

    async for db in get_db():
        from app.use_cases.streams.commands.force_close_stream import force_close_stream
        await force_close_stream(db, room_name)


async def _close_stream(db: AsyncSession, room_name: str) -> None:
    """Geriye dönük uyumluluk için ince sarmalayıcı."""
    from app.use_cases.streams.commands.force_close_stream import force_close_stream
    await force_close_stream(db, room_name)
