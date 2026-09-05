from datetime import datetime, timezone

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stream import LiveStream, LiveStreamViewer
from app.models.enums import StreamStatus
from app.constants import ws_types as WS
from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)


async def finalize_stream(stream: LiveStream, db: AsyncSession) -> None:
    """Tüm stream kapatma yollarının ortak cleanup helper'ı.
    Çağıranlar: EndStreamCommand, force_close_stream, admin_end_stream.
    """
    redis = await get_redis()
    now = datetime.now(timezone.utc)

    # 1. İstatistik snapshot — Redis silinmeden önce
    live_count = await redis.get(f"live:viewers:{stream.id}")
    peak_count = await redis.get(f"live:peak_viewers:{stream.id}")
    if live_count is not None:
        stream.viewer_count = max(stream.viewer_count or 0, int(live_count))
    if peak_count is not None:
        stream.peak_viewer_count = int(peak_count)

    # 2. DB: stream kapat
    stream.is_live = False
    stream.status = StreamStatus.ENDED
    stream.ended_at = now

    # 3. DB: açık kalan viewer seanslarını kapat
    await db.execute(
        update(LiveStreamViewer)
        .where(
            LiveStreamViewer.stream_id == stream.id,
            LiveStreamViewer.left_at.is_(None),
        )
        .values(left_at=now)
    )

    await db.commit()

    # 4. LiveKit room sil (idempotent — 404 sessizce geçilir)
    try:
        from app.use_cases.streams.stream_utils import delete_livekit_room
        await delete_livekit_room(stream.room_name)
    except Exception:
        pass

    # 5. Redis temizle — Faz 8 canonical şeması: stream_id bazlı key'ler
    try:
        await redis.delete(
            f"live:viewers:{stream.id}",
            f"live:peak_viewers:{stream.id}",
            f"live:viewer_set:{stream.id}",
            f"live:room_to_stream:{stream.room_name}",
            f"live:pip_viewer_set:{stream.id}",
            f"live:host_reconnect:{stream.id}",
            f"stream:stats:{stream.id}",
        )
    except Exception:
        logger.error("finalize_stream: Redis temizliği başarısız | stream_id=%s", stream.id, exc_info=True)

    # 6. WS bildirimi
    try:
        from app.use_cases.chat.chat_utils import publish_chat
        from app.core.ws_manager import ws_manager
        await publish_chat(stream.id, {"type": WS.STREAM_ENDED})
        await ws_manager.publish(
            "chat_broadcast", "global",
            {"type": WS.STREAM_ENDED, "stream_id": stream.id},
        )
    except Exception:
        logger.warning("finalize_stream: WS yayınlanamadı | stream_id=%s", stream.id, exc_info=True)
