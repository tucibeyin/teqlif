import json
from datetime import datetime, timezone

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.models.stream import LiveStream, LiveStreamViewer
from app.models.stream_chat_message import StreamChatMessage
from app.models.enums import StreamStatus
from app.constants import ws_types as WS
from app.utils.redis_client import get_redis
from app.core.logger import get_logger
from app.use_cases.chat.chat_utils import chat_key

logger = get_logger(__name__)


async def _dump_chat_to_db(stream: LiveStream, db: AsyncSession) -> None:
    """Redis'teki chat geçmişini stream_chat_messages tablosuna dump eder."""
    try:
        redis = await get_redis()
        key = chat_key(stream.id)
        raw_messages = await redis.lrange(key, 0, -1)
        if not raw_messages:
            return

        rows = []
        for raw in raw_messages:
            try:
                msg = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                logger.warning("[Finalizer] stream_id=%s bozuk chat JSON atlandı", stream.id)
                continue
            content = (msg.get("content") or "").strip()
            if not content:
                continue
            rows.append({
                "stream_id":  stream.id,
                "user_id":    msg.get("user_id"),
                "username":   msg.get("username", ""),
                "avatar_url": msg.get("profile_image_url"),
                "content":    content,
                "is_host":    msg.get("is_host", False),
                "is_mod":     msg.get("is_mod", False),
                "is_hidden":  msg.get("is_hidden", False),
                "created_at": msg.get("created_at"),
            })

        if not rows:
            return

        await db.execute(
            pg_insert(StreamChatMessage).values(rows).on_conflict_do_nothing()
        )
        await db.commit()
        logger.info("[Finalizer] Chat dump tamamlandı | stream_id=%s mesaj=%d", stream.id, len(rows))
    except Exception:
        logger.error("[Finalizer] Chat dump başarısız | stream_id=%s", stream.id, exc_info=True)


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

    # 4. Chat dump — Redis'teki mesajları DB'ye yaz
    await _dump_chat_to_db(stream, db)

    # 5. LiveKit room sil (idempotent — 404 sessizce geçilir)
    try:
        from app.use_cases.streams.stream_utils import delete_livekit_room
        await delete_livekit_room(stream.room_name)
    except Exception:
        pass

    # 6. Redis temizle — Faz 8 canonical şeması: stream_id bazlı key'ler
    try:
        await redis.delete(
            f"live:viewers:{stream.id}",
            f"live:peak_viewers:{stream.id}",
            f"live:viewer_set:{stream.id}",
            f"live:room_to_stream:{stream.room_name}",
            f"live:pip_viewer_set:{stream.id}",
            f"live:host_reconnect:{stream.id}",
            f"stream:stats:{stream.id}",
            f"stream:likes:{stream.id}",
            chat_key(stream.id),  # dump sonrası chat geçmişini temizle
        )
    except Exception:
        logger.error("finalize_stream: Redis temizliği başarısız | stream_id=%s", stream.id, exc_info=True)

    # 7. pro_insights ve pro_metrics cache'i invalidate et (yayıncı raporunu güncel görsün)
    try:
        keys = await redis.keys(f"cache:pro_insights:{stream.host_id}:*")
        to_delete = list(keys) + [f"cache:pro_metrics:{stream.host_id}"]
        if to_delete:
            await redis.delete(*to_delete)
    except Exception:
        pass

    # 8. WS bildirimi
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
