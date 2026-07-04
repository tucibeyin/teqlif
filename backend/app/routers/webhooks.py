import asyncio
import aiohttp
import logging
import time
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, BackgroundTasks
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from livekit.api import WebhookReceiver, TokenVerifier
from livekit.api.room_service import RoomService, ListRoomsRequest

from app.database import get_db, AsyncSessionLocal
from app.models.stream import LiveStream
from app.utils.redis_client import get_redis
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/webhooks", tags=["webhooks"])

_receiver = WebhookReceiver(TokenVerifier(settings.livekit_api_key, settings.livekit_api_secret))


@router.get("/livekit", include_in_schema=False)
async def livekit_webhook_probe():
    return {"status": "ok"}


@router.post("/livekit", include_in_schema=False)
async def livekit_webhook(request: Request, background_tasks: BackgroundTasks):
    body = await request.body()
    auth_header = request.headers.get("Authorization", "")

    try:
        event = _receiver.receive(body.decode(), auth_header)
    except Exception:
        logger.error("LiveKit webhook imza doğrulaması başarısız", exc_info=True)
        raise HTTPException(status_code=401, detail="Geçersiz webhook imzası")

    event_type = event.event
    room_name = event.room.name if event.room else None

    logger.info("LiveKit webhook alındı | event=%s room=%s", event_type, room_name)

    if event_type == "room_finished" and room_name:
        background_tasks.add_task(_delayed_close_stream, room_name)

    # Host görüntüsü kesilince (internet kopukluğu vb.) 2 dk içinde geri dönmezse yayını kapat
    if room_name and event.participant:
        identity = event.participant.identity or ""
        if event_type == "participant_left":
            background_tasks.add_task(_on_host_left, room_name, identity, time.time())
        elif event_type == "participant_joined":
            background_tasks.add_task(_on_host_rejoined, room_name, identity)

    return {"ok": True}


_HOST_GRACE_SECONDS = 120  # 2 dakika bekleme süresi


async def _on_host_left(room_name: str, identity: str, disconnected_at: float) -> None:
    """
    Host LiveKit odasından ayrıldığında çağrılır.
    2 dakika bekler; host bu sürede geri dönmezse yayını otomatik kapatır.
    """
    # Katılımcı bu odanın host'u mu?
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

    await asyncio.sleep(_HOST_GRACE_SECONDS)

    # Grace period boyunca host geri döndü mü?
    try:
        redis = await get_redis()
        reconnect_raw = await redis.get(f"live:host_reconnect:{stream_id}")
        if reconnect_raw:
            reconnect_ts = float(reconnect_raw)
            if reconnect_ts > disconnected_at:
                logger.info(
                    "[STREAMS] Host grace period içinde geri döndü — kapatma iptal | stream_id=%s",
                    stream_id,
                )
                return
    except Exception as exc:
        logger.warning("[STREAMS] Redis host_reconnect okunamadı | stream_id=%s | %s", stream_id, exc)

    # Yayın hâlâ aktif mi?
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(LiveStream).where(
                LiveStream.id == stream_id,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        if not result.scalar_one_or_none():
            return  # Yayın zaten kapatılmış

        logger.warning(
            "[STREAMS] Host %d sn görüntü göndermedi — yayın otomatik kapatılıyor | stream_id=%s",
            _HOST_GRACE_SECONDS, stream_id,
        )
        await _close_stream(db, room_name)


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


async def _delayed_close_stream(room_name: str) -> None:
    await asyncio.sleep(60)  # Grace period: Wait 60 seconds
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
        await _close_stream(db, room_name)

async def _close_stream(db: AsyncSession, room_name: str) -> None:
    from app.services.auction_service import AuctionService

    result = await db.execute(
        select(LiveStream).where(
            LiveStream.room_name == room_name,
            LiveStream.is_live == True,  # noqa: E712
        )
    )
    stream = result.scalar_one_or_none()
    if not stream:
        return

    stream_id = stream.id
    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)

    # Yetim açık artırmayı sistem zorlamasıyla bitir
    try:
        auction_svc = AuctionService(db)
        await auction_svc.end_auction(stream_id, force_system=True)
    except Exception as exc:
        logger.error("Webhook: Yetim Müzayede kapatılamadı | stream_id=%s", stream_id, exc_info=True)

    try:
        await db.commit()
        logger.info("Yayın otomatik sonlandırıldı | stream_id=%s room=%s", stream_id, room_name)
    except Exception:
        logger.error("Webhook: yayın DB güncellenemedi | stream_id=%s", stream_id, exc_info=True)
        return

    # Tüm izleyicilere yayın kapandı sinyali gönder
    try:
        from app.constants import ws_types as WS
        from app.core.ws_manager import ws_manager
        from app.services.chat_service import publish_chat
        await publish_chat(stream_id, {"type": WS.STREAM_ENDED})
        await ws_manager.publish(
            "chat_broadcast", "global",
            {"type": WS.STREAM_ENDED, "stream_id": stream_id},
        )
    except Exception:
        logger.warning("Webhook: stream_ended WS yayınlanamadı | room=%s", room_name, exc_info=True)

    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{room_name}")
        await redis.delete(f"live:host_reconnect:{stream_id}")
    except Exception:
        logger.error("Webhook: Redis temizliği başarısız | room=%s", room_name, exc_info=True)
