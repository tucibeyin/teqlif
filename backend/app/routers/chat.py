"""
Chat router — Clean Router Pattern.

WebSocket endpoint protokol akışını (accept/close/receive döngüsü) yönetir.
Tüm iş mantığı operasyonları (viewer count, history, mesaj kalıcılığı, mute/mod kontrolleri)
app.services.chat_service.ChatService'e taşınmıştır.

Geriye dönük uyumluluk re-exportları:
  _publish_chat, chat_pubsub_listener, moderation_pubsub_listener
  → stream_service.py ve main.py bu isimleri buradan import eder.
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select
import asyncio

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.utils.auth import decode_token
from app.utils.redis_client import get_redis
from app.core.logger import get_logger
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager, safe_send_json
from app.services.chat_service import (
    ChatService,
    publish_chat,
    chat_pubsub_listener,        # noqa: F401 — main.py bu ismi buradan import eder
    moderation_pubsub_listener,  # noqa: F401 — main.py bu ismi buradan import eder
)

logger = get_logger(__name__)
router = APIRouter(prefix="/api/chat", tags=["chat"])

# Geriye dönük uyumluluk: streams.py / stream_service.py gibi modüller
# `from app.routers.chat import _publish_chat` şeklinde import edebilir.
_publish_chat = publish_chat  # noqa: F401


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
            from app.services.moderation_service import kick_key
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
            await publish_chat(stream_id, {"type": "system_join", "username": username})

        # ── 8. Geçmiş mesajlar, mevcut izleyici sayısı ve mod durumu ─────────
        try:
            history = await svc.load_history(stream_id)
            if history:
                await safe_send_json(websocket, {"type": "history", "messages": history})

            if room_name:
                count = await svc.get_viewer_count(room_name)
                await safe_send_json(websocket, {"type": "viewer_count", "count": count})

            if not is_host:
                is_mod = await svc.get_mod_status(stream_id, user_id)
                if is_mod:
                    await safe_send_json(websocket, {"type": "mod_status", "is_mod": True})
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
                    await safe_send_json(websocket, {"type": "host_pin", "content": _pin_str})
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
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
            except asyncio.TimeoutError:
                logger.warning("[CHAT WS] İstemci ping timeout | stream_id=%s user_id=%s", stream_id, user_id)
                break
            except WebSocketDisconnect:
                break
            if not text or text.strip() == "ping":
                continue
            try:
                import json as _json
                payload = _json.loads(text)
                if payload.get("type") == "message":
                    content = str(payload.get("content", "")).strip()[:500]
                    if not content:
                        continue

                    result = await svc.process_message(
                        stream_id=stream_id,
                        user_id=user_id,
                        username=username,
                        profile_image_url=profile_image_url,
                        is_host=is_host,
                        content=content,
                    )
                    if result is None:
                        # Mute durumu
                        await safe_send_json(websocket, {
                            "type": "error",
                            "code": "muted",
                            "message": "Bu yayında susturuldunuz",
                        })
                elif payload.get("type") == "host_pin" and is_host:
                    # Host'un sabitlediği mesaj — tüm izleyicilere yayınla.
                    # Boş string = sabiti kaldır komutu, o da yayınlanır.
                    pin_content = str(payload.get("content", "")).strip()[:200]
                    # Redis'e kalıcı olarak sakla (sonradan katılanlar için)
                    try:
                        _redis = await get_redis()
                        _pin_key = f"pin:{stream_id}"
                        if pin_content:
                            await _redis.set(_pin_key, pin_content, ex=86400)
                        else:
                            await _redis.delete(_pin_key)
                    except Exception as _exc:
                        logger.warning("[CHAT WS] Pin Redis yazma hatası | %s", _exc)
                    await publish_chat(stream_id, {
                        "type": "host_pin",
                        "content": pin_content,
                        "username": username,
                    })
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
