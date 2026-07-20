from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.stream import LiveStream
from app.constants import ws_types as WS
from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

async def force_close_stream(db: AsyncSession, room_name: str) -> None:
    from app.use_cases.auctions.commands.auction_commands import AuctionCommands

    result = await db.execute(
        select(LiveStream).where(
            LiveStream.room_name == room_name,
            LiveStream.is_live == True,
        )
    )
    stream = result.scalar_one_or_none()
    if not stream:
        return

    stream_id = stream.id
    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)

    try:
        from app.core.uow import SqlAlchemyUnitOfWork
        auction_svc = AuctionCommands(SqlAlchemyUnitOfWork(session_factory=lambda: db))
        await auction_svc.end_auction(stream_id, force_system=True)
    except Exception:
        logger.error("force_close_stream: Auction kapatılamadı | stream_id=%s", stream_id, exc_info=True)

    try:
        await db.commit()
        logger.info("force_close_stream: Yayın sonlandırıldı | stream_id=%s room=%s", stream_id, room_name)
    except Exception:
        logger.error("force_close_stream: DB güncellenemedi | stream_id=%s", stream_id, exc_info=True)
        return

    try:
        from app.core.ws_manager import ws_manager
        from app.use_cases.chat.chat_utils import publish_chat
        await publish_chat(stream_id, {"type": WS.STREAM_ENDED})
        await ws_manager.publish(
            "chat_broadcast", "global",
            {"type": WS.STREAM_ENDED, "stream_id": stream_id},
        )
    except Exception:
        logger.warning("force_close_stream: WS yayınlanamadı | room=%s", room_name, exc_info=True)

    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{room_name}")
        await redis.delete(f"live:host_reconnect:{stream_id}")
    except Exception:
        logger.error("force_close_stream: Redis temizliği başarısız | room=%s", room_name, exc_info=True)
