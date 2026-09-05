import asyncio
import os
import shutil
import tempfile
import uuid
from sqlalchemy import select, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException
from app.models.message import DirectMessage
from app.models.message_thread import MessageThread
from app.models.block import UserBlock
from app.models.follow import Follow
from app.schemas.message import MessageOut
from app.services.dm_broadcast import broadcast_dm
from app.services.notification_service import send_message_push
from app.utils.redis_client import get_redis
from app.services import storage_service as storage
from app.routers.upload import (
    _detect_image_type,
    _detect_video_type,
    _make_thumbnail,
    _get_video_duration,
    _IMAGE_CONTENT_TYPES,
)
from app.constants.media_limits import (
    VOICE_MAX_BYTES,
    IMAGE_MAX_BYTES,
    VIDEO_MAX_BYTES,
    FILE_MAX_BYTES,
    VIDEO_MAX_SECS,
    VOICE_MAX_SECS,
)

logger = get_logger(__name__)

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


def _validate_file_magic(data: bytes, ext: str) -> str | None:
    """Magic byte + extension çapraz doğrulaması. Geçerliyse MIME döner, değilse None."""
    # PDF: %PDF
    if data[:4] == b"%PDF":
        return "application/pdf"
    # ZIP tabanlı (DOCX, XLSX): PK\x03\x04
    if data[:4] == b"PK\x03\x04":
        if ext in ("docx", "xlsx"):
            _OFFICE_MIME = {
                "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            }
            return _OFFICE_MIME[ext]
        return None
    # DOC: Compound Document (D0CF11E0)
    if data[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        if ext == "doc":
            return "application/msword"
        if ext == "xls":
            return "application/vnd.ms-excel"
        return None
    # TXT: UTF-8 BOM veya printable ASCII başlangıcı
    if ext == "txt":
        try:
            sample = data[:512]
            sample.decode("utf-8")
            return "text/plain"
        except UnicodeDecodeError:
            return None
    return None


def _detect_audio_type(data: bytes) -> str | None:
    if len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xF6) == 0xF0:
        return "aac"
    if data[:4] == b"OggS":
        return "ogg"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "m4a"
    if len(data) >= 3 and data[:3] == b"ID3":
        return "mp3"
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


def _media_payload(msg: DirectMessage, sender_username: str) -> dict:
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


def _thread_pair(a: int, b: int) -> tuple[int, int]:
    return min(a, b), max(a, b)


class SendMediaMessageCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        sender_id: int,
        receiver_id: int,
        content_type_field: str,
        data: bytes,
        file_content_type: str,
        original_filename: str,
        duration_secs: int | None,
        sender_username: str,
    ) -> MessageOut:
        if sender_id == receiver_id:
            raise ForbiddenException(code="SELF_MESSAGE_FORBIDDEN")

        file_size = len(data)
        if file_size == 0:
            raise BadRequestException(code="MEDIA_EMPTY")

        _SIZE_LIMITS = {
            "voice": (VOICE_MAX_BYTES, "AUDIO_TOO_LARGE"),
            "video": (VIDEO_MAX_BYTES, "DM_VIDEO_TOO_LARGE"),
            "image": (IMAGE_MAX_BYTES, "FILE_TOO_LARGE"),
            "file":  (FILE_MAX_BYTES,  "FILE_TOO_LARGE"),
        }
        max_size, size_err_code = _SIZE_LIMITS.get(content_type_field, (FILE_MAX_BYTES, "FILE_TOO_LARGE"))
        if file_size > max_size:
            raise BadRequestException(code=size_err_code)

        # Validate media and upload (before DB write)
        media_url, thumbnail_url, file_name, resolved_duration = await self._process_media(
            content_type_field, data, file_content_type, original_filename, duration_secs
        )

        async with self.uow:
            receiver = await self.uow.users.get(receiver_id)
            if not receiver:
                raise NotFoundException(code="USER_NOT_FOUND")

            block = await self.uow.session.scalar(
                select(UserBlock).where(
                    or_(
                        and_(UserBlock.blocker_id == sender_id, UserBlock.blocked_id == receiver_id),
                        and_(UserBlock.blocker_id == receiver_id, UserBlock.blocked_id == sender_id),
                    )
                ).limit(1)
            )
            if block:
                raise ForbiddenException(code="MESSAGING_FORBIDDEN")

            msg = DirectMessage(
                sender_id=sender_id,
                receiver_id=receiver_id,
                content="",
                content_type=content_type_field,
                media_url=media_url,
                thumbnail_url=thumbnail_url,
                duration_secs=resolved_duration,
                file_name=file_name,
                file_size=file_size,
            )
            self.uow.session.add(msg)

            user_a, user_b = _thread_pair(sender_id, receiver_id)
            existing_thread = await self.uow.session.scalar(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a,
                    MessageThread.user_b_id == user_b,
                )
            )
            is_new_request = False
            auto_accepted = False
            is_pending_for_initiator = False
            initiator_id_for_notif: int | None = None

            if existing_thread and existing_thread.status == "declined":
                raise ForbiddenException(code="MESSAGING_FORBIDDEN")

            if not existing_thread:
                is_req = False
                if receiver.is_private:
                    follow_accepted = await self.uow.session.scalar(
                        select(Follow).where(
                            Follow.follower_id == sender_id,
                            Follow.followed_id == receiver_id,
                            Follow.status == "accepted",
                        )
                    )
                    if not follow_accepted:
                        is_req = True
                self.uow.session.add(MessageThread(
                    user_a_id=user_a,
                    user_b_id=user_b,
                    initiator_id=sender_id,
                    status="pending" if is_req else "accepted",
                ))
                is_new_request = is_req

            elif existing_thread.status == "pending":
                if existing_thread.initiator_id != sender_id:
                    existing_thread.status = "accepted"
                    auto_accepted = True
                    initiator_id_for_notif = existing_thread.initiator_id
                else:
                    is_pending_for_initiator = True

            await self.uow.session.flush()

        # commit sonrası — side effects
        if is_new_request:
            redis = await get_redis()
            await redis.incr(f"msg:unread:request:{receiver_id}")

        if auto_accepted:
            redis = await get_redis()
            await redis.decr(f"msg:unread:request:{sender_id}")

        payload = _media_payload(msg, sender_username)
        await broadcast_dm(receiver_id, payload)
        await broadcast_dm(sender_id, payload)

        _notif_key_map = {
            "voice": "notifMessageVoice",
            "image": "notifMessageImage",
            "video": "notifMessageVideo",
            "file": "notifMessageFile",
        }
        if auto_accepted and initiator_id_for_notif:
            await send_message_push(
                initiator_id_for_notif,
                {
                    "type": "message",
                    "i18n": {
                        "title_key": "notifMsgRequestAccepted",
                        "title_params": {"username": sender_username},
                    },
                    "related_id": sender_id,
                    "sender_username": sender_username,
                },
            )
        elif not is_new_request and not is_pending_for_initiator:
            await send_message_push(
                receiver_id,
                {
                    "type": "message",
                    "i18n": {
                        "title_key": "notifMessage",
                        "title_params": {"username": sender_username},
                        "body_key": _notif_key_map.get(content_type_field, "notifMessage"),
                    },
                    "related_id": sender_id,
                    "sender_username": sender_username,
                },
            )

        logger.info(
            "[SendMediaMessageCommand] Başarılı | sender=%s receiver=%s type=%s size=%d",
            sender_id, receiver_id, content_type_field, file_size,
        )
        return _msg_out(msg, sender_username)

    async def _process_media(
        self,
        content_type_field: str,
        data: bytes,
        file_content_type: str,
        original_filename: str,
        duration_secs: int | None,
    ) -> tuple[str, str | None, str | None, int | None]:
        """Validates, uploads media. Returns (media_url, thumbnail_url, file_name, duration_secs)."""
        media_url: str
        thumbnail_url: str | None = None
        file_name: str | None = None
        resolved_duration: int | None = duration_secs

        if content_type_field == "voice":
            audio_fmt = _detect_audio_type(data)
            if audio_fmt is None:
                client_ct = file_content_type.lower()
                if not any(client_ct.startswith(ct) for ct in _AUDIO_CONTENT_TYPES):
                    raise BadRequestException(code="UNSUPPORTED_AUDIO_FORMAT")
                audio_fmt = "aac"
            ext_map = {"aac": "aac", "ogg": "ogg", "m4a": "m4a", "mp3": "mp3"}
            ct_map = {"aac": "audio/aac", "ogg": "audio/ogg", "m4a": "audio/mp4", "mp3": "audio/mpeg"}
            ext = ext_map.get(audio_fmt, "aac")
            key = f"messages/voice/{uuid.uuid4().hex}.{ext}"
            media_url = storage.upload_bytes(key, data, ct_map.get(audio_fmt, "audio/aac"))
            if resolved_duration is not None:
                resolved_duration = min(resolved_duration, 60)

        elif content_type_field == "image":
            img_ext = _detect_image_type(data)
            if img_ext is None:
                raise BadRequestException(code="INVALID_IMAGE_FORMAT")
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
                logger.warning("[SendMediaMessageCommand] Thumbnail oluşturulamadı: %s", exc)

        elif content_type_field == "video":
            vid_fmt = _detect_video_type(data)
            if vid_fmt is None:
                raise BadRequestException(code="INVALID_VIDEO_FORMAT")
            with tempfile.TemporaryDirectory() as tmp_dir:
                src_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.{vid_fmt}")
                with open(src_path, "wb") as f:
                    f.write(data)
                detected_dur = await _get_video_duration(src_path)
                if detected_dur is not None and detected_dur > VIDEO_MAX_SECS:
                    raise BadRequestException(code="VIDEO_TOO_LONG")
                if detected_dur is not None:
                    resolved_duration = int(detected_dur)
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
                        logger.warning("[SendMediaMessageCommand] Video thumbnail hatası: %s", exc)
                key = f"messages/vid/{uuid.uuid4().hex}.{vid_fmt}"
                media_url = storage.upload_file(key, src_path, "video/mp4")
                if thumb_local:
                    with open(thumb_local, "rb") as tf:
                        thumb_bytes = tf.read()
                    thumb_key = f"messages/vid/{uuid.uuid4().hex}_thumb.jpg"
                    thumbnail_url = storage.upload_bytes(thumb_key, thumb_bytes, "image/jpeg")

        else:  # file
            ext = (original_filename.rsplit(".", 1)[-1].lower() if "." in (original_filename or "") else "")
            client_ct = _validate_file_magic(data, ext)
            if client_ct is None:
                raise BadRequestException(code="UNSUPPORTED_FILE_TYPE")
            original_name = original_filename or f"dosya.{ext or 'bin'}"
            file_name = original_name[:255]
            key = f"messages/file/{uuid.uuid4().hex}.{ext or 'bin'}"
            media_url = storage.upload_bytes(key, data, client_ct)

        return media_url, thumbnail_url, file_name, resolved_duration
