import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Request, HTTPException, BackgroundTasks
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from livekit.api import WebhookReceiver, TokenVerifier

from app.database import get_db
from app.models.stream import LiveStream
from app.utils.redis_client import get_redis
from app.config import settings
import asyncio
import aiohttp
from livekit.api import RoomService, ListRoomsRequest

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

    return {"ok": True}


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

    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)

    # Yetim açık artırmayı sistem zorlamasıyla bitir
    try:
        auction_svc = AuctionService(db)
        await auction_svc.end_auction(stream.id, force_system=True)
    except Exception as exc:
        logger.error("Webhook: Yetim Müzayede kapatılamadı | stream_id=%s", stream.id, exc_info=True)

    try:
        await db.commit()
        logger.info("Oda kapandı, yayın otomatik sonlandırıldı | stream_id=%s room=%s", stream.id, room_name)
    except Exception:
        logger.error("Webhook: yayın DB güncellenemedi | stream_id=%s", stream.id, exc_info=True)
        return

    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{room_name}")
    except Exception:
        logger.error("Webhook: Redis viewer key silinemedi | room=%s", room_name, exc_info=True)
