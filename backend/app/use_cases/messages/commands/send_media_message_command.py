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
from app.services import storage_service as storage
from app.utils.redis_client import get_redis
from app.utils.media_processor import process_media
from app.constants.media_limits import (
    VOICE_MAX_BYTES,
    IMAGE_MAX_BYTES,
    VIDEO_MAX_BYTES,
    FILE_MAX_BYTES,
)

logger = get_logger(__name__)


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


def _media_payload(
    msg: DirectMessage,
    sender_username: str,
    media_url: str | None = None,
    thumbnail_url: str | None = None,
) -> dict:
    return {
        "type": "message",
        "id": msg.id,
        "sender_id": msg.sender_id,
        "receiver_id": msg.receiver_id,
        "sender_username": sender_username,
        "content": msg.content,
        "content_type": msg.content_type,
        "media_url": media_url if media_url is not None else msg.media_url,
        "thumbnail_url": thumbnail_url if thumbnail_url is not None else msg.thumbnail_url,
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

        # Upload before DB write; orphan cleanup on any subsequent failure
        processed = await process_media(
            content_type_field, data, file_content_type, original_filename, duration_secs
        )

        is_new_request = False
        auto_accepted = False
        is_pending_for_initiator = False
        initiator_id_for_notif: int | None = None

        try:
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
                    media_url=processed.media_url,
                    thumbnail_url=processed.thumbnail_url,
                    duration_secs=processed.duration_secs,
                    file_name=processed.file_name,
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
        except Exception:
            for key in processed.uploaded_dm_keys:
                storage.delete_object_dm(key)
            raise

        # commit sonrası — side effects
        if is_new_request:
            redis = await get_redis()
            await redis.incr(f"msg:unread:request:{receiver_id}")

        if auto_accepted:
            redis = await get_redis()
            await redis.decr(f"msg:unread:request:{sender_id}")

        # DM medyasını presign et — WS payload'u direkt URL içermeli
        presigned_media = msg.media_url
        presigned_thumb = msg.thumbnail_url
        try:
            if storage.is_dm_url(msg.media_url):
                presigned_media = storage.presign_get(storage.dm_url_to_key(msg.media_url))
            if storage.is_dm_url(msg.thumbnail_url):
                presigned_thumb = storage.presign_get(storage.dm_url_to_key(msg.thumbnail_url))
        except Exception as presign_exc:
            logger.warning("[SendMediaMessageCommand] Presign başarısız: %s", presign_exc)

        payload = _media_payload(msg, sender_username, presigned_media, presigned_thumb)
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
