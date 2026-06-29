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
import asyncio
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import aiohttp
from fastapi import BackgroundTasks, UploadFile
from livekit.api.room_service import RoomService, DeleteRoomRequest
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_

from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.services.like_service import LikeService
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
from app.core.task_queue import get_pool
from app.constants import ws_types as WS

logger = get_logger(__name__)

_MAX_THUMBNAIL_BYTES = 10 * 1024 * 1024   # 10 MB
_ROOM_NAME_PREFIX    = "stream"            # oda adı biçimi: stream_{user_id}_{uuid8}
_ROOM_UUID_LENGTH    = 8                   # room_name içindeki UUID kısaltma uzunluğu


def _apply_block_filter(query, host_id_col, current_user_id: int):
    """Engelleme filtrelerini verilen SQLAlchemy query'ye uygular."""
    blocked_by_me = select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    blocking_me   = select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    return query.where(
        host_id_col.not_in(blocked_by_me),
        host_id_col.not_in(blocking_me),
    )


async def _fill_viewer_counts(streams: list, tag: str = "") -> None:
    """
    Redis MGET ile tüm yayınların izleyici sayısını tek sorguda doldurur.
    Redis erişilemezse izleyici sayıları 0 kalır (graceful degrade).
    """
    if not streams:
        return
    try:
        redis = await get_redis()
        keys = [f"live:viewers:{s.room_name}" for s in streams]
        counts = await redis.mget(*keys)
        for stream, count in zip(streams, counts):
            stream.viewer_count = int(count) if count else 0  # type: ignore[attr-defined]
    except Exception:
        logger.error("[STREAMS] Redis viewer count okunamadı%s",
                     f" | {tag}" if tag else "", exc_info=True)


# ── LiveKit yardımcıları ─────────────────────────────────────────────────────

async def delete_livekit_room(room_name: str) -> None:
    """LiveKit odasını zorla sil (tüm katılımcıları çıkarır)."""
    try:
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


_LIVEKIT_TOKEN_TTL = timedelta(hours=24)  # Uzun yayınlar için yeterli süre


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
            .with_ttl(_LIVEKIT_TOKEN_TTL)
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
                        "stream_id": stream_id,
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

        # Aktif VEYA son 3 dakikada oluşturulmuş beklemedeki yayın kontrolü
        recent_threshold = datetime.now(timezone.utc) - timedelta(minutes=3)
        result = await self.db.execute(
            select(LiveStream).where(
                LiveStream.host_id == uid,
                or_(
                    LiveStream.is_live == True,  # noqa: E712
                    and_(
                        LiveStream.is_live == False,  # noqa: E712
                        LiveStream.ended_at.is_(None),  # Gerçekten bitmiş değil, ghost pending
                        LiveStream.started_at >= recent_threshold,
                    ),
                ),
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            if existing.is_live:
                await release_action_lock(uid, "stream_start")
                logger.warning("[STREAMS] Zaten aktif yayın var | user_id=%s stream_id=%s", uid, existing.id)
                raise BadRequestException("Zaten aktif bir yayınınız var")
            # Beklemedeki ghost kayıt — LiveKit bağlantısı kurulamadan kalmış, temizle
            logger.info("[STREAMS] Ghost pending stream temizlendi | user_id=%s stream_id=%s", uid, existing.id)
            await self.db.delete(existing)
            await self.db.commit()

        room_name = f"{_ROOM_NAME_PREFIX}_{uid}_{uuid.uuid4().hex[:_ROOM_UUID_LENGTH]}"
        stream = LiveStream(
            room_name=room_name,
            title=data.title,
            category=data.category,
            host_id=uid,
            is_live=False,   # LiveKit bağlantısı kurulana kadar gizli
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
        logger.info("[STREAMS] Yayın hazırlandı (beklemede) | stream_id=%s user_id=%s room=%s",
                    stream.id, uid, room_name)

        # Bildirimler confirm_live() içinde gönderilir — LiveKit bağlantısı başarıyla kurulduktan sonra

        return StreamTokenOut(
            stream_id=stream.id,
            room_name=room_name,
            livekit_url=settings.livekit_url,
            token=token,
            category=data.category,
        )

    # ── Yayını Canlıya Al ────────────────────────────────────────────────────
    async def confirm_live(
        self,
        stream_id: int,
        user: User,
        background_tasks: BackgroundTasks,
    ) -> dict:
        """LiveKit bağlantısı kurulduktan sonra çağrılır. is_live=True yapar ve bildirimleri gönderir."""
        result = await self.db.execute(
            select(LiveStream).where(
                LiveStream.id == stream_id,
                LiveStream.host_id == user.id,
                LiveStream.is_live == False,  # noqa: E712
            )
        )
        stream = result.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Beklemedeki yayın bulunamadı")

        stream.is_live = True
        await self.db.commit()

        from app.database_clickhouse import track_user_event
        asyncio.create_task(track_user_event(
            event_type="stream_start",
            item_id=stream.id,
            item_type="stream",
            user_id=user.id,
        ))

        background_tasks.add_task(
            notify_followers_task,
            user_id=user.id,
            username=user.username,
            stream_title=stream.title,
            stream_id=stream.id,
        )
        pool = get_pool()
        if pool:
            await pool.enqueue_job("send_smart_auction_alerts", stream.id)
        else:
            logger.warning("[STREAMS] ARQ pool yok — send_smart_auction_alerts kuyruğa alınamadı")

        logger.info("[STREAMS] Yayın canlıya alındı | stream_id=%s user_id=%s", stream.id, user.id)
        return {"ok": True}

    # ── Beklemedeki Yayını İptal Et ───────────────────────────────────────────
    async def cancel_pending(self, stream_id: int, user: User) -> None:
        """LiveKit bağlantısı kurulamazsa çağrılır. Pending kaydı siler, iz bırakmaz."""
        result = await self.db.execute(
            select(LiveStream).where(
                LiveStream.id == stream_id,
                LiveStream.host_id == user.id,
                LiveStream.is_live == False,  # noqa: E712
            )
        )
        stream = result.scalar_one_or_none()
        if not stream:
            return  # Zaten silinmiş, sorun yok

        await self.db.delete(stream)
        await self.db.commit()

        # Rate limit sayacını sıfırla — bağlanamayan yayın limiti tüketmemeli
        redis = await get_redis()
        if redis:
            await redis.delete(f"act_rate:{user.id}:stream_start")

        logger.info("[STREAMS] Beklemedeki yayın iptal edildi | stream_id=%s user_id=%s", stream_id, user.id)

    # ── Yayın Sonlandır ──────────────────────────────────────────────────────
    async def end(self, stream_id: int, user: User) -> dict:
        from app.services.moderation_service import mod_key
        from app.services.chat_service import publish_chat as _publish_chat

        stream = await self._fetch_stream_for_end(stream_id, user)
        await self._mark_stream_ended(stream, stream_id)
        await self._cleanup_redis(stream, stream_id, mod_key)
        await self._cleanup_stream_likes(stream_id)
        await self._cleanup_highlights(stream_id)
        await self._broadcast_stream_ended(stream_id, _publish_chat)
        await delete_livekit_room(stream.room_name)

        from app.core.hype_manager import hype_manager
        hype_manager.remove_stream(stream_id)

        logger.info("[STREAMS] Yayın sonlandırıldı | stream_id=%s user_id=%s", stream_id, user.id)
        return {"message": "Yayın sonlandırıldı"}

    async def _fetch_stream_for_end(self, stream_id: int, user: User) -> "LiveStream":
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
        return stream

    async def _mark_stream_ended(self, stream: "LiveStream", stream_id: int) -> None:
        stream.is_live = False
        stream.ended_at = datetime.now(timezone.utc)
        duration = (stream.ended_at - stream.started_at).total_seconds() if stream.started_at else None
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

        from app.database_clickhouse import track_user_event
        asyncio.create_task(track_user_event(
            event_type="stream_end",
            item_id=stream_id,
            item_type="stream",
            user_id=stream.host_id,
            duration_seconds=duration,
        ))

    async def _cleanup_redis(self, stream: "LiveStream", stream_id: int, mod_key) -> None:
        try:
            redis = await get_redis()
            # Yayın süresince ulaşılan en yüksek izleyici sayısını DB'ye kaydet
            peak_raw = await redis.get(f"live:peak_viewers:{stream.room_name}")
            if peak_raw:
                peak = int(peak_raw)
                if peak > (stream.viewer_count or 0):
                    stream.viewer_count = peak
                    try:
                        await self.db.commit()
                    except Exception:
                        await self.db.rollback()
                        logger.error(
                            "[STREAMS] Peak viewer_count DB kaydedilemedi | stream_id=%s",
                            stream_id, exc_info=True,
                        )
            await redis.delete(f"live:viewers:{stream.room_name}")
            await redis.delete(f"live:peak_viewers:{stream.room_name}")
            await redis.delete(f"live:viewer_set:{stream_id}")
            await redis.delete(mod_key(stream_id))
            await redis.delete(f"pin:{stream_id}")
            # Rate limit sayacını sıfırla; hemen yeni yayın açılabilsin
            await redis.delete(f"act_rate:{stream.host_id}:stream_start")
        except Exception:
            logger.error("[STREAMS] Redis temizliği başarısız | room=%s",
                         stream.room_name, exc_info=True)

    async def _cleanup_stream_likes(self, stream_id: int) -> None:
        try:
            from sqlalchemy import text
            await self.db.execute(
                text("DELETE FROM stream_likes WHERE stream_id = :sid"),
                {"sid": stream_id},
            )
            await self.db.commit()
        except Exception:
            logger.warning("[STREAMS] stream_likes temizlenemedi | stream_id=%s",
                           stream_id, exc_info=True)

    async def _cleanup_highlights(self, stream_id: int) -> None:
        """Yayın bitince o odaya ait highlight kaydını ve disk dosyasını sil."""
        import os
        import pathlib
        try:
            from sqlalchemy import text
            await self.db.execute(
                text("DELETE FROM listings WHERE active_room_id = :rid AND is_highlight = TRUE"),
                {"rid": stream_id},
            )
            await self.db.commit()
        except Exception:
            logger.warning("[STREAMS] Highlight DB temizliği başarısız | stream_id=%s",
                           stream_id, exc_info=True)

        try:
            highlight_file = (
                pathlib.Path(__file__).resolve().parents[2]
                / "static" / "highlights" / f"highlight_{stream_id}.mp4"
            )
            if highlight_file.exists():
                os.remove(highlight_file)
                logger.info("[STREAMS] Highlight dosyası silindi | %s", highlight_file)
        except Exception:
            logger.warning("[STREAMS] Highlight dosyası silinemedi | stream_id=%s",
                           stream_id, exc_info=True)

    async def _broadcast_stream_ended(self, stream_id: int, publish_chat) -> None:
        try:
            # İzleyicilere (chat odasına) bildir
            await publish_chat(stream_id, {"type": WS.STREAM_ENDED})
            # Tüm bağlı istemcilere (ana ekran) bildir — global topic
            from app.core.ws_manager import ws_manager
            await ws_manager.publish(
                "chat_broadcast", "global",
                {"type": WS.STREAM_ENDED, "stream_id": stream_id},
            )
        except Exception:
            logger.error("[STREAMS] stream_ended yayınlanamadı | stream_id=%s",
                         stream_id, exc_info=True)

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
            category=stream.category,
            host_username=stream.host.username,
            host_livekit_identity=str(stream.host_id),
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
        if len(data) > _MAX_THUMBNAIL_BYTES:
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

            # Redis viewer count — MGET ile tek sorguda (graceful degrade)
            await _fill_viewer_counts(streams, tag=f"followed user_id={current_user_id}")

            # Batch likes count
            stream_ids = [s.id for s in streams]
            like_counts = await LikeService.batch_stream_likes(self.db, stream_ids)
            for stream in streams:
                stream.likes_count = like_counts.get(stream.id, 0)  # type: ignore[attr-defined]

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

    # ── Co-Host: Sahneye Davet Et ────────────────────────────────────────────
    async def invite_cohost(self, stream_id: int, target_username: str, host: User) -> dict:
        """Host, bir izleyiciyi sahneye davet eder.

        1. Host yetkisi doğrulanır.
        2. Hedef kullanıcı bulunur.
        3. Redis'te `cohost_invite:{stream_id}:{target.id}` anahtarı 60s TTL ile oluşturulur.
        4. Odaya `cohost_invite` WS sinyali yayınlanır (sadece target_username eşleşen client pop-up gösterir).
        """
        from app.services.chat_service import publish_chat

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")
        if stream.host_id != host.id:
            raise ForbiddenException("Sadece yayın sahibi davet gönderebilir")

        target_res = await self.db.execute(select(User).where(User.username == target_username))
        target = target_res.scalar_one_or_none()
        if not target:
            raise NotFoundException("Kullanıcı bulunamadı")
        if target.id == host.id:
            raise BadRequestException("Kendinizi davet edemezsiniz")

        redis = await get_redis()
        invite_key = f"cohost_invite:{stream_id}:{target.id}"
        await redis.set(invite_key, "1", ex=60)

        await publish_chat(stream_id, {
            "type": WS.COHOST_INVITE,
            "target_username": target.username,
            "host_username": host.username,
        })
        logger.info(
            "[COHOST] Davet gönderildi | stream_id=%s host=%s target=%s",
            stream_id, host.username, target.username,
        )
        return {"message": f"@{target.username} sahneye davet edildi"}

    # ── Co-Host: Daveti Kabul Et ─────────────────────────────────────────────
    async def accept_cohost_invite(self, stream_id: int, current_user: User) -> StreamTokenOut:
        """Davet edilen izleyici sahneye çıkmak için can_publish=True token alır.

        1. Redis'teki davet anahtarı kontrol edilir (yoksa 403).
        2. Anahtar silinir (tek kullanım).
        3. `can_publish=True` yeni token üretilir ve döndürülür.
        4. Odaya `cohost_accepted` WS sinyali yayınlanır.
        """
        from app.services.chat_service import publish_chat

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")

        redis = await get_redis()
        invite_key = f"cohost_invite:{stream_id}:{current_user.id}"
        exists = await redis.get(invite_key)
        if not exists:
            raise ForbiddenException("Geçerli bir sahne davetiniz yok")

        await redis.delete(invite_key)

        import aiohttp
        from app.config import settings
        from livekit.api.room_service import RoomService, UpdateParticipantRequest
        from livekit.protocol.models import ParticipantPermission
        
        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret
            )
            try:
                req = UpdateParticipantRequest(
                    room=stream.room_name,
                    identity=str(current_user.id),
                    permission=ParticipantPermission(
                        can_publish=True,
                        can_subscribe=True,
                        can_publish_data=True
                    )
                )
                await svc.update_participant(req)
            except Exception as e:
                logger.error("[COHOST] Yetki yükseltilirken hata: %s", str(e))

        await publish_chat(stream_id, {
            "type": WS.COHOST_ACCEPTED,
            "username": current_user.username,
        })
        logger.info(
            "[COHOST] Davet kabul edildi ve yetki anlık yükseltildi | stream_id=%s user=%s",
            stream_id, current_user.username,
        )
        # Token döndürmemize gerek yok ama mobil taraf geriye StreamTokenOut bekliyorsa boş veya eski token dönebiliriz.
        # En temizi, mevcut token yapısını bozmamak için can_publish=True ile token döndürebiliriz ama mobil taraf bunu kullanıp reconnect yapmayacak.
        token = make_livekit_token(stream.room_name, current_user, can_publish=True)
        return StreamTokenOut(
            stream_id=stream.id,
            room_name=stream.room_name,
            livekit_url=settings.livekit_url,
            token=token,
            category=stream.category,
        )

    # ── Co-Host: Sahneden Kaldır ─────────────────────────────────────────────
    async def remove_cohost(self, stream_id: int, target_username: str, host: User) -> dict:
        """Host, sahneye çıkan konuğu sahneden kaldırır.

        Sadece `cohost_removed` WS sinyali yayınlanır.
        İstemci bu sinyali alınca kamerasını kapatıp viewer token'ına döner.
        """
        from app.services.chat_service import publish_chat

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")
        if stream.host_id != host.id:
            raise ForbiddenException("Sadece yayın sahibi sahne konuğunu kaldırabilir")

        import aiohttp
        from app.config import settings
        from livekit.api.room_service import RoomService, UpdateParticipantRequest
        from livekit.protocol.models import ParticipantPermission
        from app.models.user import User as UserModel
        
        target_user_result = await self.db.execute(select(UserModel).where(UserModel.username == target_username))
        target_user = target_user_result.scalar_one_or_none()
        
        if target_user:
            async with aiohttp.ClientSession() as session:
                svc = RoomService(
                    session,
                    settings.livekit_api_base,
                    settings.livekit_api_key,
                    settings.livekit_api_secret
                )
                try:
                    req = UpdateParticipantRequest(
                        room=stream.room_name,
                        identity=str(target_user.id),
                        permission=ParticipantPermission(
                            can_publish=False,
                            can_subscribe=True,
                            can_publish_data=False
                        )
                    )
                    await svc.update_participant(req)
                except Exception as e:
                    logger.error("[COHOST] Konuk yetkisi düşürülürken hata: %s", str(e))

        await publish_chat(stream_id, {
            "type": WS.COHOST_REMOVED,
            "target_username": target_username,
        })
        logger.info(
            "[COHOST] Konuk yetkisi düşürüldü ve sahneden kaldırıldı | stream_id=%s host=%s target=%s",
            stream_id, host.username, target_username,
        )
        return {"message": f"@{target_username} sahneden kaldırıldı"}

    # ── Co-Host: Gönüllü Ayrılma ────────────────────────────────────────────
    async def leave_cohost(self, stream_id: int, current_user: User) -> dict:
        """Co-host kendi isteğiyle sahneden ayrılır — cohost_removed WS yayınlanır."""
        from app.services.chat_service import publish_chat

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream or not stream.is_live:
            raise NotFoundException("Aktif yayın bulunamadı")

        import aiohttp
        from app.config import settings
        from livekit.api.room_service import RoomService, UpdateParticipantRequest
        from livekit.protocol.models import ParticipantPermission

        async with aiohttp.ClientSession() as session:
            svc = RoomService(
                session,
                settings.livekit_api_base,
                settings.livekit_api_key,
                settings.livekit_api_secret
            )
            try:
                req = UpdateParticipantRequest(
                    room=stream.room_name,
                    identity=str(current_user.id),
                    permission=ParticipantPermission(
                        can_publish=False,
                        can_subscribe=True,
                        can_publish_data=False
                    )
                )
                await svc.update_participant(req)
            except Exception as e:
                logger.error("[COHOST] Konuk yetkisi düşürülürken hata: %s", str(e))

        await publish_chat(stream_id, {
            "type": WS.COHOST_REMOVED,
            "target_username": current_user.username,
        })
        logger.info(
            "[COHOST] Konuk sahneden kendi isteğiyle ayrıldı | stream_id=%s user=%s",
            stream_id, current_user.username,
        )
        return {"message": "Sahneden ayrıldınız"}

    # ── Aktif Yayınlar ───────────────────────────────────────────────────────
    async def get_recommended_streams(self, user_id: int) -> list:
        """
        Kullanıcının category affinity + preference_embedding'ine göre sıralanmış aktif yayınlar (max 8).
        Sıralama kriterleri:
          60% — kullanıcının üst 4 kategorisiyle eşleşme
          20% — anlık izleyici yoğunluğu (normalize)
          20% — beğeni/hype skoruna göre popülerlik
        """
        from app.services.feed_service import get_user_interests
        from app.models.user import User as UserModel

        all_streams = await self.get_active_streams(user_id)
        if not all_streams:
            return []

        interests = await get_user_interests(user_id, self.db)
        top_cats: set[str] = set(list(interests.keys())[:4]) if interests else set()

        # Maksimum izleyici sayısı (normalize için)
        max_viewers = max((s.viewer_count for s in all_streams), default=1) or 1
        max_likes = max((getattr(s, "likes_count", 0) for s in all_streams), default=1) or 1

        def _score(stream) -> float:
            cat_score = 0.6 if (top_cats and stream.category in top_cats) else 0.0
            viewer_score = (stream.viewer_count / max_viewers) * 0.2
            likes_score = (getattr(stream, "likes_count", 0) / max_likes) * 0.2
            return cat_score + viewer_score + likes_score

        all_streams.sort(key=_score, reverse=True)
        return all_streams[:8]

    async def get_active_streams(self, current_user_id: Optional[int]) -> list:
        query = (
            select(LiveStream)
            .where(LiveStream.is_live == True)  # noqa: E712
            .order_by(LiveStream.started_at.desc())
        )

        if current_user_id:
            query = _apply_block_filter(query, LiveStream.host_id, current_user_id)

        result = await self.db.execute(query)
        streams = result.scalars().all()

        # Redis viewer count — MGET ile tek sorguda (graceful degrade)
        await _fill_viewer_counts(streams, tag="active")

        # Batch likes count
        stream_ids = [s.id for s in streams]
        like_counts = await LikeService.batch_stream_likes(self.db, stream_ids)
        for stream in streams:
            stream.likes_count = like_counts.get(stream.id, 0)  # type: ignore[attr-defined]

        return streams
