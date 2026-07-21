
import asyncio
import json
import uuid
from datetime import datetime, timezone
from sqlalchemy import select
from app.core.auto_mod import auto_mod, analyze_text_all
from app.core.rate_limit import check_chat_rate_limit
from app.core.logger import get_logger
from app.core.ws_manager import ws_manager, safe_send_json
from app.constants import ws_types as WS
from app.database import AsyncSessionLocal
from app.models.user import User
from app.services.moderation_service import mute_key, mod_key, MOD_CHANNEL
from app.utils.redis_client import get_redis

logger = get_logger(__name__)

_CHAT_CHANNEL = "chat_broadcast"
_MAX_HISTORY = 50
_VIEWER_TTL = 12 * 3600

def chat_key(stream_id: int) -> str:
    return f"chat:{stream_id}:messages"

async def publish_chat(stream_id: int, payload: dict) -> None:
    await ws_manager.publish(_CHAT_CHANNEL, f"chat:{stream_id}", payload)

async def update_viewer_count(room_name: str, stream_id: int, delta: int) -> None:
    try:
        redis = await get_redis()
        key = f"live:viewers:{room_name}"
        peak_key = f"live:peak_viewers:{room_name}"
        if delta > 0:
            count = await redis.incr(key)
            await redis.expire(key, _VIEWER_TTL)
            peak_raw = await redis.get(peak_key)
            current_peak = int(peak_raw) if peak_raw else 0
            if count > current_peak:
                await redis.setex(peak_key, _VIEWER_TTL, count)
        else:
            count = await redis.decr(key)
            if count < 0:
                await redis.set(key, 0)
                count = 0
            await redis.expire(key, _VIEWER_TTL)
        await publish_chat(stream_id, {"type": WS.VIEWER_COUNT, "count": int(count)})
    except Exception:
        logger.error("[CHAT] Viewer count güncellenemedi | room=%s stream_id=%s delta=%s", room_name, stream_id, delta, exc_info=True)

async def chat_pubsub_listener() -> None:
    from app.core.stream_listener import stream_listener
    async def _on_message(data: dict) -> None:
        topic = data.pop("_topic")
        asyncio.create_task(ws_manager.broadcast_local(topic, data))
    await stream_listener(_CHAT_CHANNEL, _on_message)

async def moderation_pubsub_listener() -> None:
    from app.core.stream_listener import stream_listener
    async def _on_message(data: dict) -> None:
        await _dispatch_mod_event(data)
    await stream_listener(MOD_CHANNEL, _on_message)

async def _dispatch_mod_event(data: dict) -> None:
    sid = data.pop("_stream_id", None)
    if not sid: return
    await ws_manager.broadcast_local(f"chat:{sid}", data)
