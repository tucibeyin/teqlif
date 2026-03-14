import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.user import User
from app.utils.auth import decode_token
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/chat", tags=["chat"])

_CHAT_CHANNEL = "chat_broadcast"
_MAX_HISTORY = 50


def _key(stream_id: int) -> str:
    return f"chat:{stream_id}:messages"


# ── WebSocket bağlantı yöneticisi ────────────────────────────────────────────
class _ChatManager:
    def __init__(self):
        self._conns: Dict[int, Set[WebSocket]] = {}

    async def connect(self, ws: WebSocket, stream_id: int):
        await ws.accept()
        self._conns.setdefault(stream_id, set()).add(ws)
        total = len(self._conns[stream_id])
        logger.info("[CHAT WS] BAĞLANDI | stream_id=%s | bu_worker=%s bağlı", stream_id, total)

    def disconnect(self, ws: WebSocket, stream_id: int):
        self._conns.get(stream_id, set()).discard(ws)
        total = len(self._conns.get(stream_id, set()))
        logger.info("[CHAT WS] AYRILDI | stream_id=%s | bu_worker=%s bağlı", stream_id, total)

    async def local_broadcast(self, stream_id: int, payload: dict):
        targets = list(self._conns.get(stream_id, set()))
        if not targets:
            return
        dead = set()
        for ws in targets:
            try:
                await ws.send_json(payload)
            except Exception as exc:
                logger.warning("[CHAT WS] SEND HATA | stream_id=%s | %s", stream_id, exc)
                dead.add(ws)
        for ws in dead:
            self._conns.get(stream_id, set()).discard(ws)


chat_manager = _ChatManager()


async def _publish_chat(stream_id: int, payload: dict):
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.publish(_CHAT_CHANNEL, data)


async def chat_pubsub_listener():
    """Her worker için tek seferlik başlatılan chat pub/sub dinleyicisi."""
    import redis.asyncio as aioredis
    from app.config import settings
    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(_CHAT_CHANNEL)
    logger.info("[CHAT PUBSUB] Dinleyici başladı (worker)")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
                stream_id = data.pop("_stream_id")
                await chat_manager.local_broadcast(stream_id, data)
            except Exception as exc:
                logger.warning("[CHAT PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(_CHAT_CHANNEL)
        await r.aclose()


# ── WebSocket endpoint ────────────────────────────────────────────────────────
@router.websocket("/{stream_id}/ws")
async def chat_ws(stream_id: int, websocket: WebSocket, token: str = Query(...)):
    # Token doğrula ve kullanıcıyı al (DB session kısa tutulur)
    user_id = decode_token(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            await websocket.close(code=4001)
            return
        username = user.username

    # WS kabul et
    await chat_manager.connect(websocket, stream_id)
    try:
        # Geçmiş mesajları gönder
        redis = await get_redis()
        history_raw = await redis.lrange(_key(stream_id), -_MAX_HISTORY, -1)
        if history_raw:
            messages = [json.loads(m) for m in history_raw]
            await websocket.send_json({"type": "history", "messages": messages})

        # Mesaj döngüsü
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            data = msg.get("text") or msg.get("bytes")
            if not data:
                continue
            try:
                payload = json.loads(data)
                if payload.get("type") == "message":
                    content = str(payload.get("content", "")).strip()[:500]
                    if not content:
                        continue
                    chat_msg = {
                        "type": "message",
                        "id": str(uuid.uuid4())[:8],
                        "username": username,
                        "content": content,
                        "created_at": datetime.now(timezone.utc).isoformat(),
                    }
                    key = _key(stream_id)
                    redis = await get_redis()
                    await redis.rpush(key, json.dumps(chat_msg))
                    await redis.ltrim(key, -_MAX_HISTORY, -1)
                    await redis.expire(key, 24 * 3600)
                    await _publish_chat(stream_id, chat_msg)
                    logger.info(
                        "[CHAT] stream_id=%s user=%s | mesaj gönderildi",
                        stream_id, username,
                    )
            except Exception:
                pass
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[CHAT WS] BEKLENMEYEN HATA | stream_id=%s | %s", stream_id, exc)
    finally:
        chat_manager.disconnect(websocket, stream_id)
