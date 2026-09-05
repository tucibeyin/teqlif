from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.stream import LiveStream
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

    try:
        from app.core.uow import SqlAlchemyUnitOfWork
        auction_svc = AuctionCommands(SqlAlchemyUnitOfWork(session_factory=lambda: db))
        await auction_svc.end_auction(stream_id, force_system=True)
    except Exception:
        logger.error("force_close_stream: Auction kapatılamadı | stream_id=%s", stream_id, exc_info=True)

    try:
        from app.use_cases.streams.stream_finalizer import finalize_stream
        await finalize_stream(stream, db)
        logger.info("force_close_stream: Yayın sonlandırıldı | stream_id=%s room=%s", stream_id, room_name)
    except Exception:
        logger.error("force_close_stream: finalize başarısız | stream_id=%s", stream_id, exc_info=True)
