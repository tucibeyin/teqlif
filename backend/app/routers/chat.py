import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Dict, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.utils.auth import decode_token
from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/chat", tags=["chat"])

_CHAT_CHANNEL = "chat_broadcast"
_MAX_HISTORY = 50


def _key(stream_id: int) -> str:
    return f"chat:{stream_id}:messages"


# ── WebSocket bağlantı yöneticisi ────────────────────────────────────────────
class _ChatManager:
    def __init__(self):
        self._conns: Dict[int, Set[WebSocket]] = {}
        # stream_id → {user_id → WebSocket}  (son bağlantıyı tutar)
        self._user_ws: Dict[int, Dict[int, WebSocket]] = {}

    async def connect(self, ws: WebSocket, stream_id: int, user_id: int):
        await ws.accept()
        self._conns.setdefault(stream_id, set()).add(ws)
        self._user_ws.setdefault(stream_id, {})[user_id] = ws
        total = len(self._conns[stream_id])
        logger.info("[CHAT WS] BAĞLANDI | stream_id=%s user_id=%s | bu_worker=%s bağlı", stream_id, user_id, total)

    def disconnect(self, ws: WebSocket, stream_id: int, user_id: int):
        self._conns.get(stream_id, set()).discard(ws)
        user_map = self._user_ws.get(stream_id, {})
        if user_map.get(user_id) is ws:
            user_map.pop(user_id, None)
        total = len(self._conns.get(stream_id, set()))
        logger.info("[CHAT WS] AYRILDI | stream_id=%s user_id=%s | bu_worker=%s bağlı", stream_id, user_id, total)

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

    async def send_to_user(self, stream_id: int, user_id: int, payload: dict):
        """Bu worker'daki belirli bir kullanıcıya doğrudan event gönder."""
        user_map = self._user_ws.get(stream_id, {})
        all_ids = list(user_map.keys())
        ws = user_map.get(user_id)
        logger.info(
            "[CHAT WS] send_to_user | stream_id=%s hedef_user_id=%s | "
            "bu_worker_kayitli_users=%s | bulunan_ws=%s",
            stream_id, user_id, all_ids, "VAR" if ws else "YOK",
        )
        if not ws:
            return
        try:
            await ws.send_json(payload)
            logger.info("[CHAT WS] send_to_user GÖNDERILDI | stream_id=%s user_id=%s payload=%s", stream_id, user_id, payload)
        except Exception as exc:
            logger.warning("[CHAT WS] send_to_user HATA | stream_id=%s user_id=%s | %s", stream_id, user_id, exc)


chat_manager = _ChatManager()


async def _update_viewer_count(room_name: str, stream_id: int, delta: int):
    """Redis'teki izleyici sayısını günceller ve tüm istemcilere yayınlar."""
    try:
        redis = await get_redis()
        key = f"live:viewers:{room_name}"
        if delta > 0:
            count = await redis.incr(key)
        else:
            count = await redis.decr(key)
            if count < 0:
                await redis.set(key, 0)
                count = 0
        await _publish_chat(stream_id, {"type": "viewer_count", "count": int(count)})
    except Exception:
        logger.error(
            "Viewer count güncellenemedi | room=%s stream_id=%s delta=%s",
            room_name, stream_id, delta, exc_info=True,
        )


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


async def moderation_pubsub_listener():
    """Her worker için moderasyon event dinleyicisi (muted/kicked/unmuted)."""
    import redis.asyncio as aioredis
    from app.config import settings
    from app.routers.moderation import MOD_CHANNEL

    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(MOD_CHANNEL)
    logger.info("[MOD PUBSUB] Dinleyici başladı (worker)")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
                stream_id = int(data["_stream_id"])
                user_id = int(data["user_id"])
                event_type = data["type"]
                logger.info(
                    "[MOD PUBSUB] EVENT ALINDI | type=%s stream_id=%s user_id=%s",
                    event_type, stream_id, user_id,
                )
                # Hedef kullanıcı bu worker'da bağlıysa doğrudan event gönder
                await chat_manager.send_to_user(stream_id, user_id, {"type": event_type})
            except Exception as exc:
                logger.warning("[MOD PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(MOD_CHANNEL)
        await r.aclose()


# ── WebSocket endpoint ────────────────────────────────────────────────────────
@router.websocket("/{stream_id}/ws")
async def chat_ws(stream_id: int, websocket: WebSocket, token: str = Query(...)):
    # Token doğrula ve kullanıcıyı al (DB session kısa tutulur)
    user_id = decode_token(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    is_host = False
    room_name = None

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user or not user.is_active:
            await websocket.close(code=4001)
            return
        username = user.username
        profile_image_url: str | None = user.profile_image_url if hasattr(user, "profile_image_url") else None

        stream_result = await db.execute(
            select(LiveStream).where(LiveStream.id == stream_id)
        )
        stream = stream_result.scalar_one_or_none()
        if stream:
            is_host = stream.host_id == user_id
            room_name = stream.room_name

    # Kick kontrolü — kicklenen kullanıcı WS'e giremez
    if not is_host:
        try:
            redis = await get_redis()
            from app.routers.moderation import kick_key
            if await redis.sismember(kick_key(stream_id), str(user_id)):
                await websocket.close(code=4003)
                logger.info("[CHAT WS] Kicklenen kullanıcı engellendi | stream_id=%s user_id=%s", stream_id, user_id)
                return
        except Exception as exc:
            logger.warning("[CHAT WS] Kick Redis kontrolü başarısız | stream_id=%s user_id=%s | %s", stream_id, user_id, exc)

    # WS kabul et
    await chat_manager.connect(websocket, stream_id, user_id)

    # İzleyiciyse sayacı artır, set'e ekle ve katılma duyurusu yap
    if not is_host and room_name:
        await _update_viewer_count(room_name, stream_id, +1)
        try:
            _r = await get_redis()
            await _r.sadd(f"live:viewer_set:{stream_id}", username)
        except Exception as exc:
            logger.warning("[CHAT WS] viewer_set sadd başarısız | stream_id=%s | %s", stream_id, exc)
        await _publish_chat(stream_id, {"type": "system_join", "username": username})

    try:
        redis = await get_redis()

        # Geçmiş mesajları gönder
        history_raw = await redis.lrange(_key(stream_id), -_MAX_HISTORY, -1)
        if history_raw:
            messages = [json.loads(m) for m in history_raw]
            await websocket.send_json({"type": "history", "messages": messages})

        # Güncel izleyici sayısını doğrudan gönder (pub/sub gecikmesini önler)
        if room_name:
            count_raw = await redis.get(f"live:viewers:{room_name}")
            await websocket.send_json({
                "type": "viewer_count",
                "count": int(count_raw) if count_raw else 0,
            })

        # Mesaj döngüsü
        while True:
            try:
                text = await websocket.receive_text()
            except WebSocketDisconnect:
                break
            if not text or text.strip() == "ping":
                continue
            try:
                payload = json.loads(text)
                if payload.get("type") == "message":
                    content = str(payload.get("content", "")).strip()[:500]
                    if not content:
                        continue

                    # Mute kontrolü
                    from app.routers.moderation import mute_key
                    redis = await get_redis()
                    if await redis.sismember(mute_key(stream_id), str(user_id)):
                        await websocket.send_json({
                            "type": "error",
                            "code": "muted",
                            "message": "Bu yayında susturuldunuz",
                        })
                        continue

                    chat_msg = {
                        "type": "message",
                        "id": str(uuid.uuid4())[:8],
                        "username": username,
                        "profile_image_url": profile_image_url,
                        "content": content,
                        "created_at": datetime.now(timezone.utc).isoformat(),
                    }
                    key = _key(stream_id)
                    await redis.rpush(key, json.dumps(chat_msg))
                    await redis.ltrim(key, -_MAX_HISTORY, -1)
                    await redis.expire(key, 24 * 3600)
                    await _publish_chat(stream_id, chat_msg)
                    logger.info(
                        "[CHAT] stream_id=%s user=%s | mesaj gönderildi",
                        stream_id, username,
                    )
            except Exception as exc:
                logger.warning("[CHAT WS] Mesaj işleme hatası | stream_id=%s | %s", stream_id, exc)
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[CHAT WS] BEKLENMEYEN HATA | stream_id=%s | %s", stream_id, exc)
    finally:
        chat_manager.disconnect(websocket, stream_id, user_id)
        # İzleyiciyse sayacı düşür ve set'ten çıkar
        if not is_host and room_name:
            await _update_viewer_count(room_name, stream_id, -1)
            try:
                _r = await get_redis()
                await _r.srem(f"live:viewer_set:{stream_id}", username)
            except Exception as exc:
                logger.warning("[CHAT WS] viewer_set srem başarısız | stream_id=%s | %s", stream_id, exc)
