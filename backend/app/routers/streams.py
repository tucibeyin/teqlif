import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, UploadFile, File, status, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from livekit.api import AccessToken, VideoGrants

from app.database import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.schemas.stream import StreamStart, StreamOut, StreamTokenOut, JoinTokenOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.utils.redis_client import get_redis
from app.config import settings
from app.routers.upload import _detect_image_type
from app.routers.chat import _publish_chat
from app.core.exceptions import NotFoundException, ForbiddenException, BadRequestException, DatabaseException, TooManyRequestsException, ConflictException
from app.core.action_guard import check_user_action_rate, acquire_action_lock, release_action_lock
from app.security.captcha import verify_captcha_token
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)
router = APIRouter(prefix="/api/streams", tags=["streams"])


async def _delete_livekit_room(room_name: str) -> None:
    """LiveKit odasını zorla sil (tüm katılımcıları çıkarır)."""
    try:
        import aiohttp
        from livekit.api.room_service import RoomService, DeleteRoomRequest
        async with aiohttp.ClientSession() as session:
            svc = RoomService(session, settings.livekit_api_base, settings.livekit_api_key, settings.livekit_api_secret)
            req = DeleteRoomRequest()
            req.room = room_name
            await svc.delete_room(req)
        logger.info("[STREAMS] LiveKit oda silindi | room=%s", room_name)
    except Exception as exc:
        logger.warning("[STREAMS] LiveKit oda silinemedi | room=%s | %s", room_name, exc)


def _make_token(room_name: str, user: User, can_publish: bool) -> str:
    try:
        grant = VideoGrants(
            room_join=True,
            room=room_name,
            can_publish=can_publish,
            can_subscribe=True,
            can_publish_data=can_publish,
        )
        token = (
            AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
            .with_identity(str(user.id))
            .with_name(user.username)
            .with_grants(grant)
        )
        return token.to_jwt()
    except Exception:
        logger.error(
            "LiveKit token oluşturulamadı | user_id=%s room=%s can_publish=%s",
            user.id, room_name, can_publish,
            exc_info=True,
        )
        raise


# SENTRY ÇÖZÜMÜ: Bağımsız ve kendi DB bağlantısını yöneten arka plan görevi
async def _notify_followers_task(user_id: int, username: str, stream_title: str | None, stream_id: int):
    import asyncio as _asyncio
    from app.models.follow import Follow
    from app.routers.notifications import push_notification

    try:
        # Arka plan görevi için taze bir DB oturumu açılır ve iş bitince güvenle kapatılır
        async with AsyncSessionLocal() as bg_db:
            followers = await bg_db.scalars(
                select(Follow.follower_id).where(Follow.followed_id == user_id)
            )
            for follower_id in followers:
                _asyncio.create_task(push_notification(
                    user_id=follower_id,
                    notif={
                        "type": "stream_started",
                        "title": f"@{username} canlı yayın açtı",
                        "body": stream_title or None,
                        "related_id": stream_id,
                    },
                    pref_key="stream_started",
                ))
    except Exception as e:
        logger.error("Takipçilere yayın bildirimi gönderilirken hata oluştu: %s", e, exc_info=True)


@router.post("/start", response_model=StreamTokenOut, status_code=status.HTTP_201_CREATED)
async def start_stream(
    data: StreamStart,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    _captcha: None = Depends(verify_captcha_token),
):
    uid = current_user.id

    # ── 1. Kullanıcı bazlı hız sınırı: 5 dakikada 1 yayın başlatma ──────────
    allowed, retry_after = await check_user_action_rate(uid, "stream_start", limit=1, window=300)
    if not allowed:
        logger.warning("[STREAMS] Hız sınırı aşıldı | user_id=%s | retry_after=%s", uid, retry_after)
        raise TooManyRequestsException(
            "5 dakika içinde yalnızca 1 yayın başlatabilirsiniz. Lütfen bekleyin.",
            retry_after=retry_after,
        )

    # ── 2. Idempotency kilidi: 5 saniyelik race condition koruması ───────────
    if not await acquire_action_lock(uid, "stream_start", ttl=5):
        logger.warning("[STREAMS] Çift istek engellendi | user_id=%s", uid)
        raise ConflictException("Yayın başlatma isteğiniz zaten işleniyor. Lütfen bekleyin.")

    result = await db.execute(
        select(LiveStream).where(
            LiveStream.host_id == current_user.id,
            LiveStream.is_live == True,  # noqa: E712
        )
    )
    if result.scalar_one_or_none():
        await release_action_lock(uid, "stream_start")
        logger.warning("Kullanıcının zaten aktif yayını var | user_id=%s", current_user.id)
        raise BadRequestException("Zaten aktif bir yayınınız var")

    room_name = f"stream_{current_user.id}_{uuid.uuid4().hex[:8]}"

    stream = LiveStream(
        room_name=room_name,
        title=data.title,
        category=data.category,
        host_id=current_user.id,
    )
    db.add(stream)
    try:
        await db.commit()
        await db.refresh(stream)
    except Exception as exc:
        await db.rollback()
        await release_action_lock(uid, "stream_start")
        logger.error(
            "Yayın DB'ye kaydedilemedi | user_id=%s room=%s",
            current_user.id, room_name,
            exc_info=True,
        )
        capture_exception(exc)
        raise DatabaseException("Yayın başlatılamadı")

    # İşlem başarılı — kilidi erkenden serbest bırak
    await release_action_lock(uid, "stream_start")

    token = _make_token(room_name, current_user, can_publish=True)
    logger.info("Yayın başlatıldı | stream_id=%s user_id=%s room=%s", stream.id, current_user.id, room_name)

    background_tasks.add_task(
        _notify_followers_task,
        user_id=current_user.id,
        username=current_user.username,
        stream_title=stream.title,
        stream_id=stream.id,
    )

    return StreamTokenOut(
        stream_id=stream.id,
        room_name=room_name,
        livekit_url=settings.livekit_url,
        token=token,
    )


@router.post("/{stream_id}/end", status_code=status.HTTP_200_OK)
async def end_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()

    if not stream:
        logger.warning("Yayın sonlandırma: bulunamadı | stream_id=%s user_id=%s", stream_id, current_user.id)
        raise NotFoundException("Yayın bulunamadı")
    if stream.host_id != current_user.id:
        logger.warning(
            "Yayın sonlandırma: yetkisiz erişim | stream_id=%s host_id=%s user_id=%s",
            stream_id, stream.host_id, current_user.id,
        )
        raise ForbiddenException("Bu yayını sonlandırma yetkiniz yok")
    if not stream.is_live:
        raise BadRequestException("Yayın zaten sonlanmış")

    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)

    try:
        await db.commit()
    except Exception as exc:
        await db.rollback()
        logger.error("Yayın sonlandırma DB hatası | stream_id=%s", stream_id, exc_info=True)
        capture_exception(exc)
        raise DatabaseException("Yayın sonlandırılamadı")

    # Redis temizliği — non-critical, başarısız olsa da yayın sonlandı sayılır
    try:
        redis = await get_redis()
        await redis.delete(f"live:viewers:{stream.room_name}")
        await redis.delete(f"live:viewer_set:{stream_id}")
    except Exception:
        logger.error("Redis viewer key silinemedi | room=%s", stream.room_name, exc_info=True)

    # Chat stream_ended eventi — non-critical
    try:
        await _publish_chat(stream_id, {"type": "stream_ended"})
    except Exception:
        logger.error("stream_ended yayınlanamadı | stream_id=%s", stream_id, exc_info=True)

    # LiveKit odasını kapat → tüm viewer'lar RoomDisconnectedEvent alır
    await _delete_livekit_room(stream.room_name)

    logger.info("Yayın sonlandırıldı | stream_id=%s user_id=%s", stream_id, current_user.id)
    return {"message": "Yayın sonlandırıldı"}


@router.get("/{stream_id}/viewers")
async def get_viewers(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if not stream or not stream.is_live:
        raise NotFoundException("Aktif yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise ForbiddenException("Sadece host görüntüleyebilir")
    redis = await get_redis()
    members = await redis.smembers(f"live:viewer_set:{stream_id}")
    return {"viewers": sorted(list(members))}


@router.post("/{stream_id}/join", response_model=JoinTokenOut)
async def join_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()

    if not stream or not stream.is_live:
        logger.warning("Yayına katılma: aktif yayın yok | stream_id=%s user_id=%s", stream_id, current_user.id)
        raise NotFoundException("Aktif yayın bulunamadı")

    if stream.host_id == current_user.id:
        raise BadRequestException("Kendi yayınınıza izleyici olarak katılamazsınız")

    # Kick kontrolü — bu yayından atılan kullanıcı tekrar giremez
    from app.routers.moderation import kick_key
    redis = await get_redis()
    if await redis.sismember(kick_key(stream_id), str(current_user.id)):
        raise ForbiddenException("Bu yayına erişiminiz kısıtlanmıştır")

    token = _make_token(stream.room_name, current_user, can_publish=False)
    logger.info("Yayına katılındı | stream_id=%s user_id=%s", stream_id, current_user.id)

    return JoinTokenOut(
        stream_id=stream.id,
        room_name=stream.room_name,
        livekit_url=settings.livekit_url,
        token=token,
        title=stream.title,
        host_username=stream.host.username,
    )


@router.delete("/{stream_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_stream(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()

    if stream:
        logger.info("Yayından ayrılındı | stream_id=%s user_id=%s", stream_id, current_user.id)


@router.patch("/{stream_id}/thumbnail")
async def update_thumbnail(
    stream_id: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if not stream:
        raise NotFoundException("Yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise ForbiddenException("Bu yayını düzenleme yetkiniz yok")
    if not stream.is_live:
        raise BadRequestException("Yayın aktif değil")

    data = await file.read()
    if len(data) > 10 * 1024 * 1024:
        raise BadRequestException("Dosya 10 MB'ı geçemez")

    ext = _detect_image_type(data)
    if ext is None:
        raise BadRequestException("Sadece JPEG, PNG veya WebP yüklenebilir")

    filename = f"thumb_{uuid.uuid4().hex}.{ext}"
    os.makedirs(settings.upload_dir, exist_ok=True)
    with open(os.path.join(settings.upload_dir, filename), "wb") as f:
        f.write(data)

    stream.thumbnail_url = f"/uploads/{filename}"
    await db.commit()
    logger.info("Stream thumbnail güncellendi | stream_id=%s", stream_id)
    return {"thumbnail_url": stream.thumbnail_url}


async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("/active", response_model=list[StreamOut])
async def get_active_streams(
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    query = (
        select(LiveStream)
        .where(LiveStream.is_live == True)  # noqa: E712
        .order_by(LiveStream.started_at.desc())
    )

    # Engelleme filtresi: engellediğin veya seni engelleyen hostların yayınlarını gizle
    if current_user_id:
        blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
        blocking_me = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
        query = query.where(
            LiveStream.host_id.not_in(blocked_by_me),
            LiveStream.host_id.not_in(blocking_me),
        )

    result = await db.execute(query)
    streams = result.scalars().all()

    # Redis viewer count — Redis erişilemese bile liste döner, graceful degrade
    try:
        redis = await get_redis()
        for stream in streams:
            count = await redis.get(f"live:viewers:{stream.room_name}")
            stream.viewer_count = int(count) if count else 0
    except Exception:
        logger.error("Redis viewer count okunamadı", exc_info=True)

    return streams
