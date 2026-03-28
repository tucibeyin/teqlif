"""
Canlı yayın servisi — iş mantığını router'dan ayırır.

StreamService sınıfı; yayın başlatma/sonlandırma, LiveKit token üretimi,
thumbnail güncelleme, viewer listesi ve aktif yayın sorguları gibi tüm
iş mantığını yönetir. Router katmanı sadece HTTP protokol detaylarını
(bağımlılıklar, dosya okuma) alır ve servisi çağırır.

Dependency Injection:
    db: AsyncSession — constructor üzerinden alınır (FastAPI Depends ile inject edilir)
    background_tasks: BackgroundTasks — start() metoduna geçirilir

Hata Yönetimi:
    DB hataları  → logger.error + capture_exception → DatabaseException (500)
    LiveKit      → logger.warning (non-critical, yayın sonlandı sayılır)
    İş kuralları → BadRequest / Forbidden / NotFound / TooManyRequests / Conflict
"""
import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import BackgroundTasks, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.schemas.stream import StreamStart, StreamTokenOut, JoinTokenOut
from app.utils.redis_client import get_redis
from app.config import settings
from app.core.exceptions import (
    NotFoundException,
    ForbiddenException,
    BadRequestException,
    DatabaseException,
    TooManyRequestsException,
    ConflictException,
)
from app.core.action_guard import check_user_action_rate, acquire_action_lock, release_action_lock
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


# ── LiveKit yardımcıları ─────────────────────────────────────────────────────

async def delete_livekit_room(room_name: str) -> None:
    """LiveKit odasını zorla sil (tüm katılımcıları çıkarır)."""
    try:
        import aiohttp
        from livekit.api.room_service import RoomService, DeleteRoomRequest
        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret,
            )
            req = DeleteRoomRequest()
            req.room = room_name
            await svc.delete_room(req)
        logger.info("[STREAMS] LiveKit oda silindi | room=%s", room_name)
    except Exception as exc:
        logger.warning("[STREAMS] LiveKit oda silinemedi | room=%s | %s", room_name, exc)


def make_livekit_token(room_name: str, user: User, can_publish: bool) -> str:
    """LiveKit JWT token üretir. Hata durumunda yeniden fırlatır (caller yakalar)."""
    try:
        from livekit.api import AccessToken, VideoGrants
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
            "[STREAMS] LiveKit token oluşturulamadı | user_id=%s room=%s can_publish=%s",
            user.id, room_name, can_publish,
            exc_info=True,
        )
        raise


# ── Takipçi bildirimi (arka plan görevi) ─────────────────────────────────────

async def notify_followers_task(
    user_id: int,
    username: str,
    stream_title: str | None,
    stream_id: int,
) -> None:
    """
    Yayın başladığında takipçilere push bildirim gönderir.
    Kendi DB oturumunu yönetir (background task olarak çağrılır).
    """
    import asyncio as _asyncio
    from app.models.follow import Follow
    from app.routers.notifications import push_notification

    try:
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
    except Exception as exc:
        logger.error(
            "[STREAMS] Takipçilere yayın bildirimi gönderilemedi: %s",
            exc, exc_info=True,
        )


# ── Servis sınıfı ────────────────────────────────────────────────────────────

class StreamService:
    """
    Tüm canlı yayın iş mantığını barındıran servis sınıfı.

    Kullanım:
        svc = StreamService(db)
        result = await svc.start(data, current_user, background_tasks)
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Yayın Başlat ─────────────────────────────────────────────────────────
    async def start(
        self,
        data: StreamStart,
        user: User,
        background_tasks: BackgroundTasks,
    ) -> StreamTokenOut:
        uid = user.id

        # 1. Kullanıcı bazlı hız sınırı: 5 dakikada 3 yayın başlatma
        allowed, retry_after = await check_user_action_rate(uid, "stream_start", limit=3, window=300)
        if not allowed:
            logger.warning("[STREAMS] Hız sınırı aşıldı | user_id=%s | retry_after=%s", uid, retry_after)
            raise TooManyRequestsException(
                "Çok hızlı işlem yapıyorsunuz. Lütfen biraz bekleyin.",
                retry_after=retry_after,
            )

        # 2. Idempotency kilidi: 5 saniyelik race condition koruması
        if not await acquire_action_lock(uid, "stream_start", ttl=5):
            logger.warning("[STREAMS] Çift istek engellendi | user_id=%s", uid)
            raise ConflictException("Yayın başlatma isteğiniz zaten işleniyor. Lütfen bekleyin.")

        result = await self.db.execute(
            select(LiveStream).where(
                LiveStream.host_id == uid,
                LiveStream.is_live == True,  # noqa: E712
            )
        )
        if result.scalar_one_or_none():
            await release_action_lock(uid, "stream_start")
            logger.warning("[STREAMS] Zaten aktif yayın var | user_id=%s", uid)
            raise BadRequestException("Zaten aktif bir yayınınız var")

        room_name = f"stream_{uid}_{uuid.uuid4().hex[:8]}"
        stream = LiveStream(
            room_name=room_name,
            title=data.title,
            category=data.category,
            host_id=uid,
        )
        self.db.add(stream)
        try:
            await self.db.commit()
            await self.db.refresh(stream)
        except Exception as exc:
            await self.db.rollback()
            await release_action_lock(uid, "stream_start")
            logger.error(
                "[STREAMS] Yayın DB'ye kaydedilemedi | user_id=%s room=%s | %s",
                uid, room_name, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Yayın başlatılamadı")

        # Commit başarılı — kilidi serbest bırak
        await release_action_lock(uid, "stream_start")

        token = make_livekit_token(room_name, user, can_publish=True)
        logger.info("[STREAMS] Yayın başlatıldı | stream_id=%s user_id=%s room=%s",
                    stream.id, uid, room_name)

        background_tasks.add_task(
            notify_followers_task,
            user_id=uid,
            username=user.username,
            stream_title=stream.title,
            stream_id=stream.id,
        )

        return StreamTokenOut(
            stream_id=stream.id,
            room_name=room_name,
            livekit_url=settings.livekit_url,
            token=token,
        )

    # ── Yayın Sonlandır ──────────────────────────────────────────────────────
    async def end(self, stream_id: int, user: User) -> dict:
        from app.services.moderation_service import mod_key
        from app.services.chat_service import publish_chat as _publish_chat

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()

        if not stream:
            logger.warning("[STREAMS] Sonlandırma: bulunamadı | stream_id=%s user_id=%s",
                           stream_id, user.id)
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id != user.id:
            logger.warning(
                "[STREAMS] Sonlandırma: yetkisiz | stream_id=%s host_id=%s user_id=%s",
                stream_id, stream.host_id, user.id,
            )
            raise ForbiddenException("Bu yayını sonlandırma yetkiniz yok")
        if not stream.is_live:
            raise BadRequestException("Yayın zaten sonlanmış")

        stream.is_live = False
        stream.ended_at = datetime.now(timezone.utc)
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[STREAMS] Sonlandırma DB hatası | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Yayın sonlandırılamadı")

        # Redis temizliği — non-critical
        try:
            redis = await get_redis()
            await redis.delete(f"live:viewers:{stream.room_name}")
            await redis.delete(f"live:viewer_set:{stream_id}")
            await redis.delete(mod_key(stream_id))
            await redis.delete(f"pin:{stream_id}")
            # Rate limit sayacını sıfırla; normal sonlandırmada hemen yeni yayın açılabilsin
            await redis.delete(f"act_rate:{stream.host_id}:stream_start")
        except Exception:
            logger.error("[STREAMS] Redis temizliği başarısız | room=%s", stream.room_name, exc_info=True)

        # Chat stream_ended eventi — non-critical
        try:
            await _publish_chat(stream_id, {"type": "stream_ended"})
        except Exception:
            logger.error("[STREAMS] stream_ended yayınlanamadı | stream_id=%s", stream_id, exc_info=True)

        # LiveKit odasını kapat → tüm viewer'lar RoomDisconnectedEvent alır
        await delete_livekit_room(stream.room_name)

        logger.info("[STREAMS] Yayın sonlandırıldı | stream_id=%s user_id=%s", stream_id, user.id)
        return {"message": "Yayın sonlandırıldı"}

    # ── Yayına Katıl ─────────────────────────────────────────────────────────
    async def join(self, stream_id: int, user: User) -> JoinTokenOut:
        from app.services.moderation_service import kick_key

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()

        if not stream or not stream.is_live:
            logger.warning("[STREAMS] Katılma: aktif yayın yok | stream_id=%s user_id=%s",
                           stream_id, user.id)
            raise NotFoundException("Aktif yayın bulunamadı")

        if stream.host_id == user.id:
            raise BadRequestException("Kendi yayınınıza izleyici olarak katılamazsınız")

        redis = await get_redis()
        if await redis.sismember(kick_key(stream_id), str(user.id)):
            raise ForbiddenException("Bu yayına erişiminiz kısıtlanmıştır")

        token = make_livekit_token(stream.room_name, user, can_publish=False)
        logger.info("[STREAMS] Yayına katılındı | stream_id=%s user_id=%s", stream_id, user.id)

        return JoinTokenOut(
            stream_id=stream.id,
            room_name=stream.room_name,
            livekit_url=settings.livekit_url,
            token=token,
            title=stream.title,
            host_username=stream.host.username,
        )

    # ── İzleyici Listesi ─────────────────────────────────────────────────────
    async def get_viewers(self, stream_id: int, user: User) -> dict:
        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")
        if stream.host_id != user.id:
            raise ForbiddenException("Sadece host görüntüleyebilir")

        redis = await get_redis()
        members = await redis.smembers(f"live:viewer_set:{stream_id}")
        return {"viewers": sorted(list(members))}

    # ── Thumbnail Güncelle ───────────────────────────────────────────────────
    async def update_thumbnail(
        self,
        stream_id: int,
        user: User,
        file: UploadFile,
    ) -> dict:
        from app.routers.upload import _detect_image_type

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id != user.id:
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
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[STREAMS] Thumbnail DB güncellemesi başarısız | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Thumbnail kaydedilemedi")

        logger.info("[STREAMS] Thumbnail güncellendi | stream_id=%s", stream_id)
        return {"thumbnail_url": stream.thumbnail_url}

    # ── Takip Edilen Canlı Yayınlar ──────────────────────────────────────────
    async def get_followed_live_streams(self, current_user_id: int) -> list:
        """
        Kullanıcının takip ettiği hesapların aktif yayınlarını döner.

        Sorgu optimizasyonu:
        - Follow.followed_id üzerinde index mevcut (follows tablosu) → JOIN hızlı
        - LiveStream.host: lazy="joined" → host User bilgisi ayrı N+1 sorgusu olmadan gelir
        - is_live filtresi + host_id JOIN tek seferde uygulanır
        """
        from app.models.follow import Follow

        try:
            query = (
                select(LiveStream)
                .join(Follow, Follow.followed_id == LiveStream.host_id)
                .where(
                    Follow.follower_id == current_user_id,
                    LiveStream.is_live == True,  # noqa: E712
                )
                .order_by(LiveStream.started_at.desc())
            )
            result = await self.db.execute(query)
            streams = result.scalars().all()

            # Redis viewer count — graceful degrade
            try:
                redis = await get_redis()
                for stream in streams:
                    count = await redis.get(f"live:viewers:{stream.room_name}")
                    stream.viewer_count = int(count) if count else 0
            except Exception:
                logger.error(
                    "[STREAMS] Redis viewer count okunamadı (followed) | user_id=%s",
                    current_user_id, exc_info=True,
                )

            logger.info(
                "[STREAMS] Takip edilen yayınlar listelendi | user_id=%s count=%s",
                current_user_id, len(streams),
            )
            return streams
        except Exception as exc:
            logger.error(
                "[STREAMS] Takip edilen yayınlar getirilemedi | user_id=%s | %s",
                current_user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Takip edilen yayınlar yüklenemedi")

    # ── Aktif Yayınlar ───────────────────────────────────────────────────────
    async def get_active_streams(self, current_user_id: Optional[int]) -> list:
        query = (
            select(LiveStream)
            .where(LiveStream.is_live == True)  # noqa: E712
            .order_by(LiveStream.started_at.desc())
        )

        if current_user_id:
            blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
            blocking_me = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
            query = query.where(
                LiveStream.host_id.not_in(blocked_by_me),
                LiveStream.host_id.not_in(blocking_me),
            )

        result = await self.db.execute(query)
        streams = result.scalars().all()

        # Redis viewer count — Redis erişilemese bile liste döner (graceful degrade)
        try:
            redis = await get_redis()
            for stream in streams:
                count = await redis.get(f"live:viewers:{stream.room_name}")
                stream.viewer_count = int(count) if count else 0
        except Exception:
            logger.error("[STREAMS] Redis viewer count okunamadı", exc_info=True)

        return streams
