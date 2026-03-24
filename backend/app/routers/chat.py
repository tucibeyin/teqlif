import asyncio
import json
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.utils.auth import decode_token
from app.utils.redis_client import get_redis
from app.core.logger import get_logger
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager, safe_send_json

logger = get_logger(__name__)
router = APIRouter(prefix="/api/chat", tags=["chat"])

_CHAT_CHANNEL = "chat_broadcast"
_MAX_HISTORY = 50


def _key(stream_id: int) -> str:
    return f"chat:{stream_id}:messages"


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
    """
    Chat mesajını Redis Pub/Sub aracılığıyla tüm worker'lara yayar.
    ws_manager.publish() delegesi — streams.py gibi dış importlar bu wrapper'ı kullanır.
    """
    await ws_manager.publish(_CHAT_CHANNEL, f"chat:{stream_id}", payload)


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
                topic = data.pop("_topic")
                # Fire-and-forget: broadcast bir Task'a alınır, listener
                # Redis kuyruğunu okumaya hemen devam eder; event loop bloklanmaz.
                asyncio.create_task(ws_manager.broadcast_local(topic, data))
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
                if event_type == "mod_promoted":
                    # Tüm izleyicilere broadcast — user_id eklendi (integer karşılaştırma için)
                    await ws_manager.broadcast_local(
                        f"chat:{stream_id}",
                        {
                            "type": "mod_promoted",
                            "user_id": user_id,
                            "username": data.get("username"),
                            "promoted_by": data.get("promoted_by"),
                        },
                    )
                    await ws_manager.broadcast_local(
                        f"chat:{stream_id}:u{user_id}",
                        {"type": "mod_promoted_self", "promoted_by": data.get("promoted_by")},
                    )
                elif event_type == "mod_demoted":
                    await ws_manager.broadcast_local(
                        f"chat:{stream_id}",
                        {
                            "type": "mod_demoted",
                            "user_id": user_id,
                            "username": data.get("username"),
                            "demoted_by": data.get("demoted_by"),
                        },
                    )
                    await ws_manager.broadcast_local(
                        f"chat:{stream_id}:u{user_id}",
                        {"type": "mod_demoted_self", "demoted_by": data.get("demoted_by")},
                    )
                else:
                    # Kullanıcıya özel topic: sadece hedef kullanıcıya gönderilir
                    await ws_manager.broadcast_local(
                        f"chat:{stream_id}:u{user_id}",
                        {"type": event_type},
                    )
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

    # ── 4. Kick kontrolü ─────────────────────────────────────────────────────
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

    # ── 5. Token klonlama / eş zamanlı oturum koruması ──────────────────────
    session_count = await register_ws_session(user_id)
    if session_count > MAX_CONCURRENT_SESSIONS:
        await release_ws_session(user_id)
        await websocket.close(code=4008)
        logger.warning(
            "[CHAT WS] Eş zamanlı oturum limiti aşıldı | stream_id=%s user_id=%s | "
            "count=%s limit=%s",
            stream_id, user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    # ── 6. Tüm doğrulamalar geçti → Gateway'e kaydet ─────────────────────────
    # İki topic: oda broadcast + kullanıcıya özel moderasyon kanalı
    chat_topic = f"chat:{stream_id}"
    user_topic = f"chat:{stream_id}:u{user_id}"
    ws_manager.connect(websocket, chat_topic)
    ws_manager.connect(websocket, user_topic)
    logger.info(
        "[CHAT WS] BAĞLANDI | stream_id=%s user_id=%s | oda_abonesi=%s",
        stream_id, user_id, ws_manager.subscriber_count(chat_topic),
    )

    try:
        # ── 7. İzleyici sayacı ve katılma bildirimi ───────────────────────────
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

        # ── 8. Geçmiş mesajlar, mevcut izleyici sayısı ve mod durumu ─────────
        try:
            redis = await get_redis()
            history_raw = await redis.lrange(_key(stream_id), -_MAX_HISTORY, -1)
            if history_raw:
                messages = [json.loads(m) for m in history_raw]
                await safe_send_json(websocket, {"type": "history", "messages": messages})

            if room_name:
                count_raw = await redis.get(f"live:viewers:{room_name}")
                await safe_send_json(websocket, {
                    "type": "viewer_count",
                    "count": int(count_raw) if count_raw else 0,
                })

            # Moderatör durumu: yeniden bağlanan mod'lara sessizce bildir
            if not is_host:
                from app.routers.moderation import mod_key
                is_mod = await redis.sismember(mod_key(stream_id), str(user_id))
                if is_mod:
                    await safe_send_json(websocket, {"type": "mod_status", "is_mod": True})
                    logger.info(
                        "[CHAT WS] Moderatör bağlandı — mod_status gönderildi | stream_id=%s user_id=%s",
                        stream_id, user_id,
                    )
        except Exception as exc:
            logger.warning(
                "[CHAT WS] Geçmiş/sayaç/mod_status gönderilemedi | stream_id=%s | %s",
                stream_id, exc,
            )

        # ── 9. Mesaj döngüsü ─────────────────────────────────────────────────
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
                        await safe_send_json(websocket, {
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
        ws_manager.disconnect(websocket, chat_topic, user_topic)
        await release_ws_session(user_id)
        logger.info(
            "[CHAT WS] AYRILDI | stream_id=%s user_id=%s | oda_abonesi=%s",
            stream_id, user_id, ws_manager.subscriber_count(chat_topic),
        )
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
