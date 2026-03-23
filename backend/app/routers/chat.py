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


# ── Güvenli gönderim helper'ı ─────────────────────────────────────────────────
async def _safe_send_json(ws: WebSocket, payload: dict) -> bool:
    """
    Bağlantı durumundan bağımsız güvenli JSON gönderimi.

    'Cannot call send once close message sent' ve 'WebSocketDisconnect' gibi
    kapanma sürecine ait hataları sessizce yakalar; çağıranı kirletmez.
    Dönüş: True = gönderim başarılı, False = bağlantı kapalıydı / hata oluştu.
    """
    try:
        await ws.send_json(payload)
        return True
    except WebSocketDisconnect:
        return False
    except RuntimeError as exc:
        # "Cannot call send once close message sent" vb. durum hataları
        logger.debug("[CHAT WS] RuntimeError send sırasında (bağlantı kapanıyor): %s", exc)
        return False
    except Exception as exc:
        logger.warning("[CHAT WS] send_json beklenmeyen hata: %s", exc)
        return False


# ── WebSocket bağlantı yöneticisi ────────────────────────────────────────────
class _ChatManager:
    def __init__(self):
        self._conns: Dict[int, Set[WebSocket]] = {}
        # stream_id → {user_id → WebSocket}  (son bağlantıyı tutar)
        self._user_ws: Dict[int, Dict[int, WebSocket]] = {}

    def connect(self, ws: WebSocket, stream_id: int, user_id: int) -> None:
        """
        Bağlantıyı state'e ekler.
        accept() çağrısının dışarıda — endpoint içinde — yapılmış olması gerekir.
        Bu metot artık senkron: state güncellemesi I/O beklemiyor.
        """
        self._conns.setdefault(stream_id, set()).add(ws)
        self._user_ws.setdefault(stream_id, {})[user_id] = ws
        total = len(self._conns[stream_id])
        logger.info(
            "[CHAT WS] BAĞLANDI | stream_id=%s user_id=%s | bu_worker=%s bağlı",
            stream_id, user_id, total,
        )

    def disconnect(self, ws: WebSocket, stream_id: int, user_id: int) -> None:
        self._conns.get(stream_id, set()).discard(ws)
        user_map = self._user_ws.get(stream_id, {})
        if user_map.get(user_id) is ws:
            user_map.pop(user_id, None)
        total = len(self._conns.get(stream_id, set()))
        logger.info(
            "[CHAT WS] AYRILDI | stream_id=%s user_id=%s | bu_worker=%s bağlı",
            stream_id, user_id, total,
        )

    async def local_broadcast(self, stream_id: int, payload: dict) -> None:
        # Snapshot → iterasyon sırasında set boyutu değişmez (RuntimeError önlenir)
        targets = list(self._conns.get(stream_id, set()))
        if not targets:
            return
        dead: Set[WebSocket] = set()
        for ws in targets:
            ok = await _safe_send_json(ws, payload)
            if not ok:
                dead.add(ws)
        # Ölü bağlantıları temizle (snapshot dışı mutasyon — güvenli)
        live_set = self._conns.get(stream_id, set())
        for ws in dead:
            live_set.discard(ws)

    async def send_to_user(
        self, stream_id: int, user_id: int, payload: dict
    ) -> None:
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
        ok = await _safe_send_json(ws, payload)
        if ok:
            logger.info(
                "[CHAT WS] send_to_user GÖNDERILDI | stream_id=%s user_id=%s payload=%s",
                stream_id, user_id, payload,
            )
        else:
            logger.warning(
                "[CHAT WS] send_to_user BAŞARISIZ (bağlantı kapalı) | stream_id=%s user_id=%s",
                stream_id, user_id,
            )


chat_manager = _ChatManager()


async def _update_viewer_count(room_name: str, stream_id: int, delta: int) -> None:
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


async def _publish_chat(stream_id: int, payload: dict) -> None:
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.publish(_CHAT_CHANNEL, data)


async def chat_pubsub_listener() -> None:
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


async def moderation_pubsub_listener() -> None:
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
    # ── 1. Hızlı senkron token kontrolü (accept() ÖNCESİ — DB yükü sıfır) ────
    # close() accept() öncesinde çağrılırsa Starlette "Need to call accept first"
    # hatası fırlatır. Geçersiz token için sadece return — bağlantı drop edilir.
    user_id = decode_token(token)
    if not user_id:
        logger.warning("[CHAT WS] Geçersiz token, bağlantı reddedildi | stream_id=%s", stream_id)
        return

    # ── 2. Bağlantıyı kabul et (bu noktadan sonra close() güvenle çağrılabilir) ─
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error(
            "[CHAT WS] accept() başarısız | stream_id=%s user_id=%s | %s",
            stream_id, user_id, exc, exc_info=True,
        )
        return

    # ── 3. DB doğrulama (accept() sonrası — artık close(code=...) güvenli) ────
    is_host = False
    room_name = None
    username: str | None = None
    profile_image_url: str | None = None

    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or not user.is_active:
                await websocket.close(code=4001)
                return
            username = user.username
            profile_image_url = (
                user.profile_image_thumb_url or user.profile_image_url
            ) if hasattr(user, "profile_image_url") else None

            stream_result = await db.execute(
                select(LiveStream).where(LiveStream.id == stream_id)
            )
            stream = stream_result.scalar_one_or_none()
            if stream:
                is_host = stream.host_id == user_id
                room_name = stream.room_name
    except Exception as exc:
        logger.error(
            "[CHAT WS] DB doğrulama hatası | stream_id=%s user_id=%s | %s",
            stream_id, user_id, exc, exc_info=True,
        )
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
        return

    # ── 4. Kick kontrolü (accept() sonrası — close(code=4003) güvenli) ─────────
    if not is_host:
        try:
            redis = await get_redis()
            from app.routers.moderation import kick_key
            if await redis.sismember(kick_key(stream_id), str(user_id)):
                await websocket.close(code=4003)
                logger.info(
                    "[CHAT WS] Kicklenen kullanıcı engellendi | stream_id=%s user_id=%s",
                    stream_id, user_id,
                )
                return
        except Exception as exc:
            logger.warning(
                "[CHAT WS] Kick Redis kontrolü başarısız | stream_id=%s user_id=%s | %s",
                stream_id, user_id, exc,
            )

    # ── 5. Tüm doğrulamalar geçti → state'e kaydet ───────────────────────────
    # connect() senkron: accept() + doğrulama tamamlandıktan SONRA çağrılır.
    # Bu sayede yarım bağlantılar hiçbir zaman broadcast hedefi olmaz.
    chat_manager.connect(websocket, stream_id, user_id)

    try:
        # ── 6. İzleyici sayacı ve katılma bildirimi ───────────────────────────
        if not is_host and room_name:
            await _update_viewer_count(room_name, stream_id, +1)
            try:
                _r = await get_redis()
                await _r.sadd(f"live:viewer_set:{stream_id}", username)
            except Exception as exc:
                logger.warning(
                    "[CHAT WS] viewer_set sadd başarısız | stream_id=%s | %s",
                    stream_id, exc,
                )
            await _publish_chat(stream_id, {"type": "system_join", "username": username})

        # ── 7. Geçmiş mesajlar ve mevcut izleyici sayısı ─────────────────────
        try:
            redis = await get_redis()
            history_raw = await redis.lrange(_key(stream_id), -_MAX_HISTORY, -1)
            if history_raw:
                messages = [json.loads(m) for m in history_raw]
                await _safe_send_json(websocket, {"type": "history", "messages": messages})

            if room_name:
                count_raw = await redis.get(f"live:viewers:{room_name}")
                await _safe_send_json(websocket, {
                    "type": "viewer_count",
                    "count": int(count_raw) if count_raw else 0,
                })
        except Exception as exc:
            logger.warning(
                "[CHAT WS] Geçmiş/sayaç gönderilemedi | stream_id=%s | %s",
                stream_id, exc,
            )

        # ── 8. Mesaj döngüsü ─────────────────────────────────────────────────
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
                        await _safe_send_json(websocket, {
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
                logger.warning(
                    "[CHAT WS] Mesaj işleme hatası | stream_id=%s | %s",
                    stream_id, exc,
                )

    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning(
            "[CHAT WS] BEKLENMEYEN HATA | stream_id=%s user_id=%s | %s",
            stream_id, user_id, exc,
        )
    finally:
        # connect() çağrıldıktan sonra buraya girilmesi garantilenmiştir.
        # Early return'ler (adım 1-4) try bloğu dışında olduğundan bu finally
        # yalnızca gerçekten bağlanmış kullanıcılar için çalışır.
        chat_manager.disconnect(websocket, stream_id, user_id)
        if not is_host and room_name:
            await _update_viewer_count(room_name, stream_id, -1)
            try:
                _r = await get_redis()
                await _r.srem(f"live:viewer_set:{stream_id}", username)
            except Exception as exc:
                logger.warning(
                    "[CHAT WS] viewer_set srem başarısız | stream_id=%s | %s",
                    stream_id, exc,
                )
