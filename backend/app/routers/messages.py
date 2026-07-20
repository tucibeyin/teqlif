from typing import List

import asyncio
import io
import json
import os
import shutil
import tempfile
import uuid
from fastapi import APIRouter, Depends, Form, Request, UploadFile, File, WebSocket, WebSocketDisconnect
from app.models.enums import UserStatus
from app.core.rate_limit import limiter, get_user_id_or_ip
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func, or_, and_, delete
from app.config import settings
from app.database import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.message import DirectMessage
from app.models.block import UserBlock
from app.schemas.message import MessageOut, ConversationOut, SendMessageIn, MediaContentType
from app.schemas.notification import UnreadCountOut
from app.utils.auth import get_current_user, decode_token
from app.routers.notifications import push_notification
from app.core.auto_mod import analyze_text_all
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.ws_manager import ws_manager
from app.core.logger import get_logger
from app.services import storage_service as storage
from app.routers.upload import (
    _detect_image_type,
    _detect_video_type,
    _make_thumbnail,
    _get_video_duration,
    _IMAGE_CONTENT_TYPES,
)
from PIL import Image

logger = get_logger(__name__)
router = APIRouter(prefix="/api/messages", tags=["messages"])

_DM_CHANNEL = "dm_broadcast"


async def _broadcast_dm(user_id: int, payload: dict) -> None:
    """Push a DM payload to all workers via Redis pub/sub."""
    await ws_manager.publish(_DM_CHANNEL, f"dm:{user_id}", payload)


async def dm_pubsub_listener() -> None:
    """Per-worker background task that delivers DM broadcasts from Redis Stream."""
    from app.core.stream_listener import stream_listener

    async def _on_message(data: dict) -> None:
        topic = data.pop("_topic")
        asyncio.create_task(ws_manager.broadcast_local(topic, data))

    await stream_listener(_DM_CHANNEL, _on_message)




@router.get("/conversations", response_model=List[ConversationOut])
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # SQL ile konuşma başına en son mesajı bul (tüm mesajları Python'a çekmez)
    conv_subq = (
        select(
            func.least(DirectMessage.sender_id, DirectMessage.receiver_id).label("min_uid"),
            func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id).label("max_uid"),
            func.max(DirectMessage.created_at).label("max_at"),
        )
        .where(
            or_(
                DirectMessage.sender_id == uid, 
                and_(DirectMessage.receiver_id == uid, DirectMessage.is_shadowbanned == False)
            )
        )
        .group_by(
            func.least(DirectMessage.sender_id, DirectMessage.receiver_id),
            func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id),
        )
        .subquery()
    )

    msgs_result = await db.execute(
        select(DirectMessage)
        .join(
            conv_subq,
            and_(
                func.least(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.min_uid,
                func.greatest(DirectMessage.sender_id, DirectMessage.receiver_id) == conv_subq.c.max_uid,
                DirectMessage.created_at == conv_subq.c.max_at,
            ),
        )
        .where(
            or_(
                DirectMessage.sender_id == uid, 
                and_(DirectMessage.receiver_id == uid, DirectMessage.is_shadowbanned == False)
            )
        )
        .order_by(DirectMessage.created_at.desc())
    )
    latest_msgs = msgs_result.scalars().all()

    if not latest_msgs:
        return []

    other_ids = [m.receiver_id if m.sender_id == uid else m.sender_id for m in latest_msgs]

    # Kullanıcı bilgileri ve okunmamış sayıları paralel çek
    users_result, unread_result = await asyncio.gather(
        db.execute(select(User).where(User.id.in_(other_ids))),
        db.execute(
            select(DirectMessage.sender_id, func.count().label("cnt"))
            .where(
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,  # noqa: E712
                DirectMessage.is_shadowbanned == False,
            )
            .group_by(DirectMessage.sender_id)
        ),
    )
    users_map = {u.id: u for u in users_result.scalars().all()}
    unread_map = {row.sender_id: row.cnt for row in unread_result}

    conversations = []
    for msg in latest_msgs:
        other_id = msg.receiver_id if msg.sender_id == uid else msg.sender_id
        other_user = users_map.get(other_id)
        if not other_user:
            continue
        conversations.append(
            ConversationOut(
                user_id=other_id,
                username=other_user.username,
                full_name=other_user.full_name,
                last_message=msg.content,
                last_message_type=msg.content_type,
                last_at=msg.created_at,
                unread_count=unread_map.get(other_id, 0),
            )
        )

    return conversations


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_dm_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(func.count()).where(
            DirectMessage.receiver_id == current_user.id,
            DirectMessage.is_read == False,  # noqa: E712
            DirectMessage.is_shadowbanned == False,
        )
    )
    count = result.scalar_one()
    return UnreadCountOut(count=count)


@router.delete("/{message_id}", status_code=204)
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def delete_message(
    request: Request,
    message_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(DirectMessage).where(DirectMessage.id == message_id))
    msg = result.scalar_one_or_none()
    if not msg:
        raise NotFoundException("Mesaj bulunamadı")
    if msg.sender_id != current_user.id:
        raise ForbiddenException("Bu mesajı silemezsiniz")

    other_user_id = msg.receiver_id
    await db.delete(msg)
    await db.commit()

    payload = {"type": "message_deleted", "id": message_id}
    await _broadcast_dm(current_user.id, payload)
    await _broadcast_dm(other_user_id, payload)


@router.delete("/conversation/{other_user_id}", status_code=204)
@limiter.limit("5/minute", key_func=get_user_id_or_ip)
async def delete_conversation(
    request: Request,
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id
    await db.execute(
        delete(DirectMessage).where(
            or_(
                and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_user_id),
                and_(DirectMessage.sender_id == other_user_id, DirectMessage.receiver_id == uid),
            )
        )
    )
    await db.commit()


@router.get("/{other_user_id}", response_model=List[MessageOut])
async def get_messages(
    other_user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # Check other user exists
    other_result = await db.execute(select(User).where(User.id == other_user_id))
    other_user = other_result.scalar_one_or_none()
    if not other_user:
        raise NotFoundException("Kullanıcı bulunamadı")

    # Fetch last 100 messages between the two users (newest first, then reverse for chronological order)
    result = await db.execute(
        select(DirectMessage)
        .where(
            or_(
                and_(DirectMessage.sender_id == uid, DirectMessage.receiver_id == other_user_id),
                and_(
                    DirectMessage.sender_id == other_user_id, 
                    DirectMessage.receiver_id == uid,
                    DirectMessage.is_shadowbanned == False
                ),
            )
        )
        .order_by(DirectMessage.created_at.desc())
        .limit(100)
    )
    messages = list(reversed(result.scalars().all()))

    # Mark received messages as read and notify the sender
    result_update = await db.execute(
        update(DirectMessage)
        .where(
            DirectMessage.sender_id == other_user_id,
            DirectMessage.receiver_id == uid,
            DirectMessage.is_read == False,  # noqa: E712
        )
        .values(is_read=True)
        .returning(DirectMessage.id)
    )
    read_ids = [row[0] for row in result_update.fetchall()]
    await db.commit()
    if read_ids:
        await _broadcast_dm(other_user_id, {"type": "messages_read", "by_user_id": uid})

    # Build sender username map
    sender_ids = {m.sender_id for m in messages}
    users_result = await db.execute(select(User).where(User.id.in_(sender_ids)))
    users_map = {u.id: u for u in users_result.scalars().all()}

    output = []
    for msg in messages:
        sender = users_map.get(msg.sender_id)
        output.append(
            MessageOut(
                id=msg.id,
                sender_id=msg.sender_id,
                receiver_id=msg.receiver_id,
                sender_username=sender.username if sender else "",
                content=msg.content,
                content_type=msg.content_type,
                media_url=msg.media_url,
                thumbnail_url=msg.thumbnail_url,
                duration_secs=msg.duration_secs,
                file_name=msg.file_name,
                file_size=msg.file_size,
                is_read=msg.is_read,
                created_at=msg.created_at,
            )
        )
    return output


@router.post("/send", response_model=MessageOut)
async def send_message(
    data: SendMessageIn,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # Check receiver exists
    recv_result = await db.execute(select(User).where(User.id == data.receiver_id))
    receiver = recv_result.scalar_one_or_none()
    if not receiver:
        raise NotFoundException("Alıcı bulunamadı")

    if data.receiver_id == uid:
        raise BadRequestException("Kendinize mesaj gönderemezsiniz")

    # Engelleme kontrolü (iki yönlü)
    block_exists = await db.scalar(
        select(UserBlock).where(
            or_(
                and_(UserBlock.blocker_id == uid, UserBlock.blocked_id == data.receiver_id),
                and_(UserBlock.blocker_id == data.receiver_id, UserBlock.blocked_id == uid),
            )
        )
    )
    if block_exists:
        raise ForbiddenException("Bu kullanıcıyla mesajlaşamazsınız")

    # Auto-mod: içerik tüm dillerde kontrol edilir (zero-latency, DB öncesi)
    is_shadowbanned = analyze_text_all(data.content)

    msg = DirectMessage(
        sender_id=uid,
        receiver_id=data.receiver_id,
        listing_id=data.listing_id,
        content=data.content,
        is_shadowbanned=is_shadowbanned,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    out = MessageOut(
        id=msg.id,
        sender_id=msg.sender_id,
        receiver_id=msg.receiver_id,
        sender_username=current_user.username,
        content=msg.content,
        content_type="text",
        is_read=msg.is_read,
        created_at=msg.created_at,
    )

    dm_payload = {
        "type": "message",
        "id": msg.id,
        "sender_id": msg.sender_id,
        "receiver_id": msg.receiver_id,
        "sender_username": current_user.username,
        "content": msg.content,
        "content_type": "text",
        "is_read": msg.is_read,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }
    # Shadowbanned mesaj sadece gönderene görünür; alıcıya broadcast yapılmaz
    if not is_shadowbanned:
        await _broadcast_dm(data.receiver_id, dm_payload)
    await _broadcast_dm(uid, dm_payload)

    if is_shadowbanned:
        logger.info(
            "[AUTO_MOD] DM shadowban | sender_id=%s receiver_id=%s msg_id=%s",
            uid, data.receiver_id, msg.id,
        )

    # Create notification for receiver
    if not is_shadowbanned:
        await push_notification(
            data.receiver_id,
            {
                "type": "message",
                "i18n": {
                    "title_key": "notifMessage",
                    "title_params": {"username": current_user.username},
                },
                "body": data.content[:100],
                "related_id": uid,
                "sender_username": current_user.username,
                "sender_image_url": current_user.profile_image_thumb_url,
            },
            pref_key="messages",
        )

    return out


# ── Medya boyut ve MIME limitleri ─────────────────────────────────────────────
_MAX_VOICE  = 512 * 1024           # 10s AAC ≈ 80KB; 512KB güvenli üst sınır
_MAX_MEDIA  = 5 * 1024 * 1024     # görsel / dosya / video (client önceden sıkıştırır)

_AUDIO_CONTENT_TYPES = {
    "audio/aac", "audio/mp4", "audio/x-m4a",
    "audio/mpeg", "audio/ogg", "audio/webm",
}
_FILE_CONTENT_TYPES = {
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "text/plain",
}
_VIDEO_MAX_SECS = 15


def _detect_audio_type(data: bytes) -> str | None:
    """Magic bytes ile ses formatını belirle."""
    if len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xF6) == 0xF0:
        return "aac"                    # ADTS AAC (Android)
    if data[:4] == b"OggS":
        return "ogg"                    # OGG/Opus (Android)
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "m4a"                    # M4A / AAC-in-MP4 (iOS)
    if len(data) >= 3 and data[:3] == b"ID3":
        return "mp3"                    # MP3 with ID3 tag
    return None


def _msg_out(msg: DirectMessage, sender_username: str) -> MessageOut:
    return MessageOut(
        id=msg.id,
        sender_id=msg.sender_id,
        receiver_id=msg.receiver_id,
        sender_username=sender_username,
        content=msg.content,
        content_type=msg.content_type,
        media_url=msg.media_url,
        thumbnail_url=msg.thumbnail_url,
        duration_secs=msg.duration_secs,
        file_name=msg.file_name,
        file_size=msg.file_size,
        is_read=msg.is_read,
        created_at=msg.created_at,
    )


def _media_dm_payload(msg: DirectMessage, sender_username: str) -> dict:
    return {
        "type": "message",
        "id": msg.id,
        "sender_id": msg.sender_id,
        "receiver_id": msg.receiver_id,
        "sender_username": sender_username,
        "content": msg.content,
        "content_type": msg.content_type,
        "media_url": msg.media_url,
        "thumbnail_url": msg.thumbnail_url,
        "duration_secs": msg.duration_secs,
        "file_name": msg.file_name,
        "file_size": msg.file_size,
        "is_read": msg.is_read,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }


@router.post("/upload", response_model=MessageOut)
@limiter.limit("30/minute", key_func=get_user_id_or_ip)
async def upload_media_message(
    request: Request,
    receiver_id: int = Form(...),
    content_type_field: MediaContentType = Form(..., alias="content_type"),
    duration_secs: int | None = Form(None),
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uid = current_user.id

    # ── Alıcı ve engelleme kontrolü ───────────────────────────────────────────
    recv_result = await db.execute(select(User).where(User.id == receiver_id))
    receiver = recv_result.scalar_one_or_none()
    if not receiver:
        raise NotFoundException("Alıcı bulunamadı")
    if receiver_id == uid:
        raise BadRequestException("Kendinize mesaj gönderemezsiniz")

    block_exists = await db.scalar(
        select(UserBlock).where(
            or_(
                and_(UserBlock.blocker_id == uid, UserBlock.blocked_id == receiver_id),
                and_(UserBlock.blocker_id == receiver_id, UserBlock.blocked_id == uid),
            )
        )
    )
    if block_exists:
        raise ForbiddenException("Bu kullanıcıyla mesajlaşamazsınız")

    data = await file.read()
    file_size = len(data)

    # ── Boyut kontrolü ────────────────────────────────────────────────────────
    max_size = _MAX_VOICE if content_type_field == "voice" else _MAX_MEDIA
    if file_size > max_size:
        mb = max_size // (1024 * 1024)
        raise BadRequestException(f"Dosya boyutu {mb} MB'ı geçemez" if mb >= 1 else "Ses dosyası çok büyük")

    media_url: str
    thumbnail_url: str | None = None
    file_name: str | None = None
    resolved_duration: int | None = duration_secs

    # ── SES ───────────────────────────────────────────────────────────────────
    if content_type_field == "voice":
        audio_fmt = _detect_audio_type(data)
        if audio_fmt is None:
            # Content-type'a fallback yap — desteklenen listede mi?
            client_ct = (file.content_type or "").lower()
            if not any(client_ct.startswith(ct) for ct in _AUDIO_CONTENT_TYPES):
                raise BadRequestException("Desteklenmeyen ses formatı")
            audio_fmt = "aac"

        ext_map = {"aac": "aac", "ogg": "ogg", "m4a": "m4a", "mp3": "mp3"}
        ct_map = {"aac": "audio/aac", "ogg": "audio/ogg", "m4a": "audio/mp4", "mp3": "audio/mpeg"}
        ext = ext_map.get(audio_fmt, "aac")
        key = f"messages/voice/{uuid.uuid4().hex}.{ext}"
        media_url = storage.upload_bytes(key, data, ct_map.get(audio_fmt, "audio/aac"))

        if resolved_duration is not None:
            resolved_duration = min(resolved_duration, 10)

    # ── GÖRSEL ────────────────────────────────────────────────────────────────
    elif content_type_field == "image":
        img_ext = _detect_image_type(data)
        if img_ext is None:
            raise BadRequestException("Sadece JPEG, PNG veya WebP yüklenebilir")

        key = f"messages/img/{uuid.uuid4().hex}.{img_ext}"
        media_url = storage.upload_bytes(key, data, _IMAGE_CONTENT_TYPES[img_ext])

        try:
            thumb_data = _make_thumbnail(data, img_ext)
            thumb_ext = "jpg" if img_ext != "png" else "png"
            thumb_key = f"messages/img/{uuid.uuid4().hex}_thumb.{thumb_ext}"
            thumbnail_url = storage.upload_bytes(
                thumb_key, thumb_data,
                "image/jpeg" if thumb_ext == "jpg" else "image/png",
            )
        except Exception as exc:
            logger.warning("[DM UPLOAD] Thumbnail oluşturulamadı: %s", exc)

    # ── VİDEO ─────────────────────────────────────────────────────────────────
    elif content_type_field == "video":
        vid_fmt = _detect_video_type(data)
        if vid_fmt is None:
            raise BadRequestException("Sadece MP4 veya WebM video yüklenebilir")

        with tempfile.TemporaryDirectory() as tmp_dir:
            src_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.{vid_fmt}")
            with open(src_path, "wb") as f:
                f.write(data)

            # Süre kontrolü
            detected_dur = await _get_video_duration(src_path)
            if detected_dur is not None and detected_dur > _VIDEO_MAX_SECS:
                raise BadRequestException(f"Video {_VIDEO_MAX_SECS} saniyeyi geçemez")
            if detected_dur is not None:
                resolved_duration = int(detected_dur)

            # Thumbnail (ffmpeg varsa)
            thumb_local = None
            if shutil.which("ffmpeg"):
                thumb_path = os.path.join(tmp_dir, f"{uuid.uuid4().hex}_vthumb.jpg")
                try:
                    proc = await asyncio.create_subprocess_exec(
                        "ffmpeg", "-y", "-i", src_path,
                        "-ss", "0", "-frames:v", "1", "-q:v", "2",
                        thumb_path,
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    await asyncio.wait_for(proc.communicate(), timeout=20)
                    if os.path.exists(thumb_path):
                        thumb_local = thumb_path
                except Exception as exc:
                    logger.warning("[DM UPLOAD] Video thumbnail hatası: %s", exc)

            key = f"messages/vid/{uuid.uuid4().hex}.{vid_fmt}"
            media_url = storage.upload_file(key, src_path, "video/mp4")

            if thumb_local:
                with open(thumb_local, "rb") as tf:
                    thumb_bytes = tf.read()
                thumb_key = f"messages/vid/{uuid.uuid4().hex}_thumb.jpg"
                thumbnail_url = storage.upload_bytes(thumb_key, thumb_bytes, "image/jpeg")

    # ── DOSYA ─────────────────────────────────────────────────────────────────
    else:
        client_ct = (file.content_type or "").lower()
        if client_ct not in _FILE_CONTENT_TYPES:
            # PDF magic bytes fallback
            if not data[:4] == b"%PDF":
                raise BadRequestException("Desteklenmeyen dosya türü")
            client_ct = "application/pdf"

        original_name = file.filename or f"dosya.{client_ct.split('/')[-1]}"
        file_name = original_name[:255]
        ext = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else "bin"
        key = f"messages/file/{uuid.uuid4().hex}.{ext}"
        media_url = storage.upload_bytes(key, data, client_ct)

    # ── DB kaydı ──────────────────────────────────────────────────────────────
    msg = DirectMessage(
        sender_id=uid,
        receiver_id=receiver_id,
        content="",
        content_type=content_type_field,
        media_url=media_url,
        thumbnail_url=thumbnail_url,
        duration_secs=resolved_duration,
        file_name=file_name,
        file_size=file_size,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    # ── WS broadcast ──────────────────────────────────────────────────────────
    payload = _media_dm_payload(msg, current_user.username)
    await _broadcast_dm(receiver_id, payload)
    await _broadcast_dm(uid, payload)

    # ── Bildirim ──────────────────────────────────────────────────────────────
    _notif_key_map = {
        "voice": "notifMessageVoice",
        "image": "notifMessageImage",
        "video": "notifMessageVideo",
        "file":  "notifMessageFile",
    }
    await push_notification(
        receiver_id,
        {
            "type": "message",
            "i18n": {
                "title_key": "notifMessage",
                "title_params": {"username": current_user.username},
                "body_key": _notif_key_map[content_type_field],
            },
            "related_id": uid,
            "sender_username": current_user.username,
            "sender_image_url": current_user.profile_image_thumb_url,
        },
        pref_key="messages",
    )

    logger.info(
        "[DM UPLOAD] Medya mesajı | sender=%s receiver=%s type=%s size=%d",
        uid, receiver_id, content_type_field, file_size,
    )
    return _msg_out(msg, current_user.username)


@router.websocket("/ws")
async def messages_ws(websocket: WebSocket):
    # ── 1. Bağlantıyı kabul et (token URL'de taşınmaz) ───────────────────────
    try:
        await websocket.accept()
    except Exception as exc:
        logger.error("[DM WS] accept() başarısız | %s", exc, exc_info=True)
        return

    # ── 2. İlk mesajdan token + since_ts al (5s timeout) ───────────────────
    since_ts: float | None = None
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        token = raw.get("token", "") if isinstance(raw, dict) else ""
        # since_ts: son alınan call event'in Unix timestamp'i (float).
        # Yeniden bağlanmada kaçırılan call eventleri replay edilir.
        if isinstance(raw, dict) and "since_ts" in raw:
            try:
                since_ts = float(raw["since_ts"])
            except (ValueError, TypeError):
                since_ts = None
    except WebSocketDisconnect:
        return
    except (asyncio.TimeoutError, Exception):
        try:
            await websocket.close(code=4001)
        except Exception:
            pass
        return

    user_id = decode_token(token)
    if not user_id:
        logger.warning("[DM WS] Geçersiz token, bağlantı kapatıldı")
        try:
            await websocket.close(code=4001)
        except Exception:
            pass
        return

    # ── 3. DB doğrulama ───────────────────────────────────────────────────────
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if not user or user.status != UserStatus.ACTIVE:
                try:
                    await websocket.close(code=4001)
                except Exception:
                    pass
                return
    except Exception as exc:
        logger.error("[DM WS] DB doğrulama hatası | user_id=%s | %s", user_id, exc, exc_info=True)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass
        return

    # ── 4. Eş zamanlı oturum koruması ─────────────────────────────────────────
    session_count = await register_ws_session(user_id)
    if session_count > MAX_CONCURRENT_SESSIONS:
        await release_ws_session(user_id)
        try:
            await websocket.close(code=4008)
        except Exception:
            pass
        logger.warning(
            "[DM WS] Eş zamanlı oturum limiti aşıldı | user_id=%s | count=%s limit=%s",
            user_id, session_count, MAX_CONCURRENT_SESSIONS,
        )
        return

    ws_manager.connect(websocket, f"dm:{user_id}")
    ws_manager.connect(websocket, "global")   # feed eventleri (stream_ended vb.)
    await ws_manager.mark_dm_online(user_id)
    logger.info("[DM WS] BAĞLANDI | user_id=%s since_ts=%s", user_id, since_ts)

    # Call event replay: yeniden bağlanmada kaçırılan call eventlerini gönder
    if since_ts is not None:
        try:
            replayed = await ws_manager.replay_call_events(websocket, user_id, since_ts)
            if replayed > 0:
                logger.info("[CALL_PROCESS][STATE] WS event replay | user_id=%s since_ts=%s replayed=%s", user_id, since_ts, replayed)
        except Exception as _replay_exc:
            logger.warning("[DM WS] call event replay failed | user_id=%s | %s", user_id, _replay_exc)

    try:
        while True:
            try:
                text = await asyncio.wait_for(websocket.receive_text(), timeout=40.0)
                if text.strip() == "ping":
                    await websocket.send_text("pong")
                else:
                    try:
                        import json as _json
                        msg = _json.loads(text)
                        if isinstance(msg, dict) and msg.get("type") == "typing":
                            target_id = msg.get("target_user_id")
                            if isinstance(target_id, int):
                                await _broadcast_dm(target_id, {
                                    "type": "typing",
                                    "sender_id": user_id,
                                })
                    except (ValueError, TypeError):
                        pass
            except asyncio.TimeoutError:
                logger.warning("[DM WS] İstemci ping timeout | user_id=%s", user_id)
                break
            except WebSocketDisconnect:
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[DM WS] HATA | user_id=%s | %s", user_id, exc)
    finally:
        ws_manager.disconnect(websocket, f"dm:{user_id}", "global")
        await ws_manager.mark_dm_offline(user_id)
        await release_ws_session(user_id)
        logger.info("[DM WS] AYRILDI | user_id=%s", user_id)
