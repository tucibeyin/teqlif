"""
Chat router — Clean Router Pattern.

WebSocket endpoint protokol akışını (accept/close/receive döngüsü) yönetir.
Tüm iş mantığı operasyonları (viewer count, history, mesaj kalıcılığı, mute/mod kontrolleri)
app.services.chat_service.ChatService'e taşınmıştır.

Geriye dönük uyumluluk re-exportları:
  _publish_chat, chat_pubsub_listener, moderation_pubsub_listener
  → stream_service.py ve main.py bu isimleri buradan import eder.
"""
import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.constants import ws_types as WS
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.logger import get_logger
from app.core.ws_manager import ws_manager, safe_send_json
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.services.chat_service import (
    ChatService,
    publish_chat,
    chat_pubsub_listener,        # noqa: F401 — main.py bu ismi buradan import eder
    moderation_pubsub_listener,  # noqa: F401 — main.py bu ismi buradan import eder
)
from app.services.moderation_service import kick_key
from app.utils.auth import decode_token
from app.utils.redis_client import get_redis

# ── WebSocket sabitleri ───────────────────────────────────────────────────────
_WS_AUTH_TIMEOUT_SECS    = 5.0   # ilk auth mesajı için bekleme süresi
_WS_RECEIVE_TIMEOUT_SECS = 40.0  # ping timeout — istemciden max bekleme
_MAX_MESSAGE_CHARS       = 500   # chat mesajı max karakter
_MAX_PIN_CHARS           = 200   # host pin max karakter
_PIN_TTL_SECS            = 86_400  # Redis'te pin saklama süresi (24 saat)

# ── WebSocket kapatma kodları ────────────────────────────────────────────────
_WS_CODE_UNAUTHORIZED    = 4001  # geçersiz token veya aktif olmayan kullanıcı
_WS_CODE_KICKED          = 4003  # yayından atılmış kullanıcı
_WS_CODE_SESSION_LIMIT   = 4008  # eş zamanlı oturum limiti aşıldı
_WS_CODE_SERVER_ERROR    = 1011  # beklenmeyen sunucu hatası

logger = get_logger(__name__)
router = APIRouter(prefix="/api/chat", tags=["chat"])


async def _handle_ws_message(
    *,
    websocket: WebSocket,
    payload: dict,
    svc: "ChatService",
    stream_id: int,
    user_id: int,
    username: str,
    profile_image_url: str | None,
    is_host: bool,
) -> None:
    """Gelen WS payload tipine göre message veya host_pin işleyicisine yönlendirir."""
    msg_type = payload.get("type")
    if msg_type == WS.MESSAGE:
        await _handle_chat_message(
            websocket=websocket, payload=payload, svc=svc,
            stream_id=stream_id, user_id=user_id, username=username,
            profile_image_url=profile_image_url, is_host=is_host,
        )
    elif msg_type == WS.HOST_PIN and is_host:
        await _handle_host_pin(stream_id=stream_id, payload=payload, username=username)


async def _handle_chat_message(
    *,
    websocket: WebSocket,
    payload: dict,
    svc: "ChatService",
    stream_id: int,
    user_id: int,
    username: str,
    profile_image_url: str | None,
    is_host: bool,
) -> None:
    """Sohbet mesajını işler: mute/shadowban kontrolleri yapılır, broadcast edilir."""
    content = str(payload.get("content", "")).strip()[:_MAX_MESSAGE_CHARS]
    if not content:
        return
    result = await svc.process_message(
        stream_id=stream_id,
        user_id=user_id,
        username=username,
        profile_image_url=profile_image_url,
        is_host=is_host,
        content=content,
    )
    if result is None:
        await safe_send_json(websocket, {
            "type": "error",
            "code": "muted",
            "message": "Bu yayında susturuldunuz",
        })
    elif result.get("is_hidden"):
        # Shadowban / küfür: mesajı sadece gönderene yolla (ghost)
        await safe_send_json(websocket, result)


async def _handle_host_pin(*, stream_id: int, payload: dict, username: str) -> None:
    """Host pin mesajını Redis'e kaydeder ve tüm izleyicilere yayınlar.

    Boş içerik = sabiti kaldır komutu; o da yayınlanır.
    """
    pin_content = str(payload.get("content", "")).strip()[:_MAX_PIN_CHARS]
    try:
        redis = await get_redis()
        pin_key = f"pin:{stream_id}"
        if pin_content:
            await redis.set(pin_key, pin_content, ex=_PIN_TTL_SECS)
        else:
            await redis.delete(pin_key)
    except Exception as exc:
        logger.warning("[CHAT WS] Pin Redis yazma hatası | %s", exc)
    await publish_chat(stream_id, {
        "type": WS.HOST_PIN,
        "content": pin_content,
        "username": username,
    })

# Geriye dönük uyumluluk: streams.py / stream_service.py gibi modüller
# `from app.routers.chat import _publish_chat` şeklinde import edebilir.
_publish_chat = publish_chat  # noqa: F401


# ── WebSocket endpoint ────────────────────────────────────────────────────────
@router.websocket("/{stream_id}/ws")
async def chat_ws(stream_id: int, websocket: WebSocket):
    # ── 1. Bağlantıyı kabul et (token URL'de taşınmaz) ───────────────────────
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error(
            "[CHAT WS] accept() başarısız | stream_id=%s | %s",
            stream_id, exc, exc_info=True,
        )
        return

    # ── 2. İlk mesajdan token al (5s timeout) ────────────────────────────────
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=_WS_AUTH_TIMEOUT_SECS)
        token = raw.get("token", "") if isinstance(raw, dict) else ""
    except (asyncio.TimeoutError, Exception):
        await websocket.close(code=_WS_CODE_UNAUTHORIZED)
        return

    user_id = decode_token(token)
    if not user_id:
        logger.warning("[CHAT WS] Geçersiz token, bağlantı kapatıldı | stream_id=%s", stream_id)
        await websocket.close(code=_WS_CODE_UNAUTHORIZED)
        return

    # ── 3. DB doğrulama ───────────────────────────────────────────────────────
    is_host = False
    room_name = None
    username: str | None = None
    profile_image_url: str | None = None

    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or not user.is_active:
                await websocket.close(code=_WS_CODE_UNAUTHORIZED)
                return
            username = user.username
            profile_image_url = user.profile_image_thumb_url or user.profile_image_url

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
            await websocket.close(code=_WS_CODE_SERVER_ERROR)
        except Exception:
            pass
        return

    # ── 4. Kick kontrolü ─────────────────────────────────────────────────────
    if not is_host:
        try:
            redis = await get_redis()
            if await redis.sismember(kick_key(stream_id), str(user_id)):
                await websocket.close(code=_WS_CODE_KICKED)
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
        await websocket.close(code=_WS_CODE_SESSION_LIMIT)
        logger.warning(
            "[CHAT WS] Eş zamanlı oturum limiti aşıldı | stream_id=%s user_id=%s | "
            "count=%s limit=%s",
            stream_id, user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    # ── 6. Tüm doğrulamalar geçti → Gateway'e kaydet ─────────────────────────
    chat_topic = f"chat:{stream_id}"
    user_topic = f"chat:{stream_id}:u{user_id}"
    ws_manager.connect(websocket, chat_topic)
    ws_manager.connect(websocket, user_topic)
    logger.info(
        "[CHAT WS] BAĞLANDI | stream_id=%s user_id=%s | oda_abonesi=%s",
        stream_id, user_id, ws_manager.subscriber_count(chat_topic),
    )

    svc = ChatService()

    try:
        # ── 7. İzleyici sayacı ve katılma bildirimi ───────────────────────────
        if not is_host and room_name:
            await svc.add_viewer(stream_id, room_name, username)
            await publish_chat(stream_id, {"type": WS.SYSTEM_JOIN, "username": username})

        # ── 8. Geçmiş mesajlar, mevcut izleyici sayısı ve mod durumu ─────────
        try:
            history_raw = await svc.load_history(stream_id)
            # Ghost mesajları filtrele: is_hidden=True olanları sadece kendi sahibi görür
            history = [
                m for m in history_raw
                if not m.get("is_hidden") or m.get("username") == username
            ]
            if history:
                await safe_send_json(websocket, {"type": WS.HISTORY, "messages": history})

            if room_name:
                count = await svc.get_viewer_count(room_name)
                await safe_send_json(websocket, {"type": WS.VIEWER_COUNT, "count": count})

            if not is_host:
                is_mod = await svc.get_mod_status(stream_id, user_id)
                if is_mod:
                    await safe_send_json(websocket, {"type": WS.MOD_STATUS, "is_mod": True})
                    logger.info(
                        "[CHAT WS] Moderatör bağlandı — mod_status gönderildi | stream_id=%s user_id=%s",
                        stream_id, user_id,
                    )

            # Aktif pin varsa yeni bağlanana gönder
            try:
                _redis = await get_redis()
                _saved_pin = await _redis.get(f"pin:{stream_id}")
                if _saved_pin:
                    _pin_str = _saved_pin.decode() if isinstance(_saved_pin, bytes) else _saved_pin
                    await safe_send_json(websocket, {"type": WS.HOST_PIN, "content": _pin_str})
            except Exception:
                pass

        except Exception as exc:
            logger.warning(
                "[CHAT WS] Geçmiş/sayaç/mod_status gönderilemedi | stream_id=%s | %s",
                stream_id, exc,
            )

        # ── 9. Mesaj döngüsü ─────────────────────────────────────────────────
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=_WS_RECEIVE_TIMEOUT_SECS)
            except asyncio.TimeoutError:
                logger.warning("[CHAT WS] İstemci ping timeout | stream_id=%s user_id=%s", stream_id, user_id)
                break
            except WebSocketDisconnect:
                break
            if not text or text.strip() == "ping":
                continue
            try:
                payload = json.loads(text)
                await _handle_ws_message(
                    websocket=websocket,
                    payload=payload,
                    svc=svc,
                    stream_id=stream_id,
                    user_id=user_id,
                    username=username,
                    profile_image_url=profile_image_url,
                    is_host=is_host,
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
            await svc.remove_viewer(stream_id, room_name, username)
