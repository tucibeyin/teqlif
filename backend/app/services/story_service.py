"""
Story servisi — Hybrid (Video + Canlı Yayın) paketleme.

Sağlanan metodlar:
  get_following_stories   — takip edilen kullanıcıların video hikayelerini ve
                            aktif canlı yayınlarını kullanıcı bazlı gruplar.
  upload_story            — video dosyasını diske kaydeder, DB kaydı oluşturur.
  cleanup_expired_stories — süresi dolan hikayeleri diskten ve DB'den siler.

Harmanlama Kuralı (get_following_stories):
  Her kullanıcı için items listesi:
    1. Video hikayeleri  → created_at ASC
    2. Live redirect     → listenin EN SONUNA (varsa), stream_id dolu

Hata Yönetimi:
  DB hataları   → logger.error + capture_exception → DatabaseException (500)
  Disk hataları → FileNotFoundError sessizce yutulur, OSError loglanır
"""
import asyncio
import os
import shutil
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text

from fastapi import UploadFile

from app.config import settings
from app.models.story import Story, StoryView
from app.models.user import User
from app.models.follow import Follow
from app.models.stream import LiveStream
from app.schemas.story import StoryAuthorOut, StoryItemOut, UserStoryGroupResponse, StoryViewerOut, StoryViewersResponse, MyStoriesResponse
from app.core.exceptions import DatabaseException, BadRequestException, NotFoundException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


async def _compress_video(src: str, out_dir: str, original_ext: str) -> tuple[str | None, str | None]:
    """
    ffmpeg ile 480p / libx264 / CRF 28 / AAC 128k sıkıştırma.
    Mobil VideoQuality.MediumQuality ile aynı hedef kalite.

    Dönüş:
      (compressed_path, compressed_filename)  — başarılı
      (None, None)                            — ffmpeg yok veya hata
    """
    if not shutil.which("ffmpeg"):
        logger.warning("[STORY COMPRESS] ffmpeg bulunamadı — sıkıştırma atlandı")
        return None, None

    out_name = f"{uuid.uuid4().hex}.mp4"
    out_path = os.path.join(out_dir, out_name)

    cmd = [
        "ffmpeg", "-y",
        "-i", src,
        "-vf", "scale=-2:480",
        "-c:v", "libx264",
        "-crf", "28",
        "-preset", "fast",
        "-c:a", "aac",
        "-b:a", "128k",
        "-movflags", "+faststart",
        out_path,
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await asyncio.wait_for(proc.communicate(), timeout=120)
        if proc.returncode == 0 and os.path.exists(out_path):
            return out_path, out_name
        if os.path.exists(out_path):
            os.remove(out_path)
        return None, None
    except Exception as exc:
        logger.warning("[STORY COMPRESS] ffmpeg başarısız, orijinal kullanılacak: %s", exc)
        if os.path.exists(out_path):
            try:
                os.remove(out_path)
            except OSError:
                pass
        return None, None


class StoryService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ── Hybrid: Video hikayeleri + Canlı yayın harmanlama ────────────────────

    async def get_following_stories(
        self, current_user_id: int
    ) -> List[UserStoryGroupResponse]:
        """
        Takip edilen kullanıcıların aktif video hikayelerini ve aktif canlı
        yayınlarını tek sorguda çekip kullanıcı bazlı birleştirir.

        Adım A — Video sorgusu:
          stories JOIN users JOIN follows WHERE expires_at > now()
          ORDER BY created_at ASC (her grubun içi kronolojik)

        Adım B — Canlı yayın sorgusu:
          live_streams JOIN users JOIN follows WHERE is_live = True

        Adım C — Python tarafı gruplama (defaultdict):
          Her user_id için ayrı bir grup tutulur.
          Videolar created_at ASC sırasında eklenir (Adım A zaten sıralı döner).
          Kullanıcı canlı yayındaysa, grubun sonuna story_type='live_redirect' eklenir.
          latest_activity_at = max(son video created_at, stream started_at)
          Gruplar latest_activity_at DESC sırasına sokulur.
        """
        # ── Adım A: Video hikayeleri ──────────────────────────────────────────
        try:
            video_query = (
                select(Story, User)
                .join(User, User.id == Story.user_id)
                .join(Follow, Follow.followed_id == Story.user_id)
                .where(
                    Follow.follower_id == current_user_id,
                    Story.expires_at > func.now(),
                )
                .order_by(Story.created_at.asc())
            )
            video_result = await self.db.execute(video_query)
            video_rows = video_result.all()
        except Exception as exc:
            logger.error(
                "[STORY] Video hikayeleri getirilemedi | user_id=%s | %s",
                current_user_id,
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Video hikayeleri yüklenemedi")

        # ── Adım B: Aktif canlı yayınlar ─────────────────────────────────────
        try:
            live_query = (
                select(LiveStream, User)
                .join(User, User.id == LiveStream.host_id)
                .join(Follow, Follow.followed_id == LiveStream.host_id)
                .where(
                    Follow.follower_id == current_user_id,
                    LiveStream.is_live == True,  # noqa: E712
                )
            )
            live_result = await self.db.execute(live_query)
            live_rows = live_result.all()
        except Exception as exc:
            logger.error(
                "[STORY] Canlı yayınlar getirilemedi | user_id=%s | %s",
                current_user_id,
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Canlı yayınlar yüklenemedi")

        # ── Adım C: Kullanıcı bazlı gruplama (defaultdict) ───────────────────
        # Yapı: { user_id: { "user": User, "video_stories": [Story,...],
        #                    "live_stream": LiveStream | None,
        #                    "latest_at": datetime | None } }
        groups: dict[int, dict] = defaultdict(
            lambda: {
                "user": None,
                "video_stories": [],
                "live_stream": None,
                "latest_at": None,
            }
        )

        # Videoları gruba ekle — sorgu zaten created_at ASC döndürdü
        for story, user in video_rows:
            g = groups[user.id]
            g["user"] = user
            g["video_stories"].append(story)
            if g["latest_at"] is None or story.created_at > g["latest_at"]:
                g["latest_at"] = story.created_at

        # Canlı yayınları gruba ekle — kullanıcı henüz video atmamış olabilir
        for stream, user in live_rows:
            g = groups[user.id]
            if g["user"] is None:
                g["user"] = user
            g["live_stream"] = stream
            # Canlı yayın başlangıcını da latest_at hesabına kat
            stream_start = stream.started_at
            if g["latest_at"] is None or (
                stream_start is not None and stream_start > g["latest_at"]
            ):
                g["latest_at"] = stream_start

        # Grupları latest_activity_at DESC sırala
        sorted_groups = sorted(
            [g for g in groups.values() if g["user"] is not None],
            key=lambda g: g["latest_at"] or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )

        # ── Response inşası ───────────────────────────────────────────────────
        response: List[UserStoryGroupResponse] = []
        for g in sorted_groups:
            user_obj: User = g["user"]
            items: List[StoryItemOut] = []

            # 1. Video hikayeleri (created_at ASC — sorgu sırası korundu)
            for story in g["video_stories"]:
                items.append(
                    StoryItemOut(
                        id=story.id,
                        story_type="video",
                        video_url=story.video_url,
                        thumbnail_url=story.thumbnail_url,
                        expires_at=story.expires_at,
                        created_at=story.created_at,
                        stream_id=None,
                    )
                )

            # 2. Canlı yayın yönlendirmesi — listenin EN SONUNA
            if g["live_stream"] is not None:
                stream = g["live_stream"]
                items.append(
                    StoryItemOut(
                        id=stream.id,
                        story_type="live_redirect",
                        stream_id=stream.id,
                    )
                )

            response.append(
                UserStoryGroupResponse(
                    user=StoryAuthorOut.model_validate(user_obj),
                    items=items,
                    latest_activity_at=g["latest_at"]
                    or datetime.min.replace(tzinfo=timezone.utc),
                )
            )

        logger.info(
            "[STORY] Hybrid hikayeler listelendi | user_id=%s | grup_sayısı=%d",
            current_user_id,
            len(response),
        )
        return response

    # ── Video yükleme ─────────────────────────────────────────────────────────

    async def upload_story(self, user_id: int, file: UploadFile) -> Story:
        """
        Gelen video dosyasını `uploads/stories/` altına kaydeder,
        24 saat geçerliliğe sahip Story DB kaydı oluşturur ve döner.

        Doğrulama:
          - Yalnızca video/* content-type kabul edilir.
          - Maksimum boyut: 100 MB (istemci tarafı sıkıştırma sonrası yeterli).
        """
        _MAX_BYTES = 20 * 1024 * 1024  # 20 MB

        # Mobil cihazlar (özellikle iOS) zaman zaman video/* yerine
        # application/octet-stream gönderebilir; her ikisini de kabul et.
        content_type = (file.content_type or "").lower()
        if not (content_type.startswith("video/") or content_type == "application/octet-stream"):
            raise BadRequestException("Geçersiz dosya formatı (yalnızca video kabul edilir)")

        raw = await file.read()
        if len(raw) > _MAX_BYTES:
            raise BadRequestException("Dosya çok büyük (Maks 20 MB)")

        # Diske yaz
        stories_dir = os.path.join(settings.upload_dir, "stories")
        os.makedirs(stories_dir, exist_ok=True)

        ext = os.path.splitext(file.filename or "video.mp4")[1] or ".mp4"
        filename = f"{uuid.uuid4().hex}{ext}"
        file_path = os.path.join(stories_dir, filename)

        try:
            with open(file_path, "wb") as f:
                f.write(raw)
        except OSError as exc:
            logger.error(
                "[STORY UPLOAD] Dosya yazılamadı: %s | user_id=%s | %s",
                file_path,
                user_id,
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Dosya kaydedilemedi")

        # ffmpeg sıkıştırma — 480p / CRF 28 / AAC 128k (VideoQuality.MediumQuality)
        # Sıkıştırılmış dosya aynı path'e yazılır; filename/video_url değişmez.
        compressed_path, _ = await _compress_video(file_path, stories_dir, ext)
        if compressed_path:
            try:
                os.replace(compressed_path, file_path)
                logger.info("[STORY UPLOAD] Sıkıştırıldı | %s", file_path)
            except OSError as exc:
                logger.warning("[STORY UPLOAD] Sıkıştırılmış dosya taşınamadı, orijinal kullanılıyor: %s", exc)

        video_url = f"/uploads/stories/{filename}"
        expires_at = datetime.now(timezone.utc) + timedelta(hours=24)

        story = Story(
            user_id=user_id,
            video_path=file_path,
            video_url=video_url,
            expires_at=expires_at,
        )
        try:
            self.db.add(story)
            await self.db.commit()
            await self.db.refresh(story)
        except Exception as exc:
            # Disk'teki dosyayı geri al
            try:
                os.remove(file_path)
            except OSError:
                pass
            logger.error(
                "[STORY UPLOAD] DB kaydı oluşturulamadı | user_id=%s | %s",
                user_id,
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Hikaye kaydedilemedi")

        logger.info(
            "[STORY UPLOAD] Yüklendi | story_id=%d | user_id=%s | path=%s",
            story.id,
            user_id,
            file_path,
        )
        return story

    # ── Kendi hikayelerim ─────────────────────────────────────────────────────

    async def get_my_stories(self, user_id: int) -> MyStoriesResponse:
        """
        Giriş yapan kullanıcının süresi dolmamış video hikayelerini döner.
        En yeniden en eskiye (created_at DESC) sıralar.
        """
        try:
            query = (
                select(Story)
                .where(Story.user_id == user_id, Story.expires_at > func.now())
                .order_by(Story.created_at.desc())
            )
            result = await self.db.execute(query)
            stories = result.scalars().all()
        except Exception as exc:
            logger.error(
                "[STORY] Kendi hikayeler getirilemedi | user_id=%s | %s",
                user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Hikayeler yüklenemedi")

        items = [
            StoryItemOut(
                id=s.id,
                story_type="video",
                video_url=s.video_url,
                thumbnail_url=s.thumbnail_url,
                expires_at=s.expires_at,
                created_at=s.created_at,
                stream_id=None,
            )
            for s in stories
        ]
        logger.info(
            "[STORY] Kendi hikayeler listelendi | user_id=%s | adet=%d",
            user_id, len(items),
        )
        return MyStoriesResponse(items=items, total=len(items))

    # ── Hikaye görüntüleme kaydı ──────────────────────────────────────────────

    async def record_story_view(self, story_id: int, viewer_id: int) -> None:
        """
        Hikayeyi görüntüleyen kullanıcıyı story_views tablosuna kaydeder.
        story_id + viewer_id UNIQUE — aynı kişi birden fazla kayıt üretmez.
        Hikaye sahibinin kendi görüntülemesi sessizce görmezden gelinir.
        """
        # Hikayenin var olup olmadığını ve sahibini kontrol et
        try:
            result = await self.db.execute(
                select(Story.user_id).where(Story.id == story_id)
            )
            row = result.scalar_one_or_none()
        except Exception as exc:
            logger.error(
                "[STORY VIEW] Hikaye sorgulanamadı | story_id=%s | %s",
                story_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Görüntüleme kaydedilemedi")

        if row is None:
            raise NotFoundException("Hikaye bulunamadı")

        # Kendi hikayesini görüntüleme → kayıt üretme
        if row == viewer_id:
            return

        try:
            await self.db.execute(
                # INSERT ... ON CONFLICT DO NOTHING — yarış güvenli tekil kayıt
                text(
                    "INSERT INTO story_views (story_id, viewer_id) "
                    "VALUES (:story_id, :viewer_id) "
                    "ON CONFLICT ON CONSTRAINT uq_story_viewer DO NOTHING"
                ),
                {"story_id": story_id, "viewer_id": viewer_id},
            )
            await self.db.commit()
        except Exception as exc:
            logger.error(
                "[STORY VIEW] Kayıt oluşturulamadı | story_id=%s | viewer_id=%s | %s",
                story_id, viewer_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Görüntüleme kaydedilemedi")

        logger.info(
            "[STORY VIEW] Kaydedildi | story_id=%s | viewer_id=%s",
            story_id, viewer_id,
        )

    # ── Hikaye görüntüleyenler listesi ────────────────────────────────────────

    async def get_story_viewers(
        self, story_id: int, owner_id: int
    ) -> StoryViewersResponse:
        """
        Belirtilen hikayeyi kimler gördü? Yalnızca hikaye sahibi görebilir.
        Görüntülemeleri en yeni → en eski (viewed_at DESC) sıralar.
        """
        # Sahiplik kontrolü
        try:
            result = await self.db.execute(
                select(Story.user_id).where(Story.id == story_id)
            )
            row = result.scalar_one_or_none()
        except Exception as exc:
            logger.error(
                "[STORY VIEWERS] Hikaye sorgulanamadı | story_id=%s | %s",
                story_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Görüntüleyenler yüklenemedi")

        if row is None:
            raise NotFoundException("Hikaye bulunamadı")

        if row != owner_id:
            from app.core.exceptions import ForbiddenException
            raise ForbiddenException("Bu hikayenin görüntüleyenlerini göremezsiniz")

        # Görüntüleyenleri çek
        try:
            query = (
                select(StoryView, User)
                .join(User, User.id == StoryView.viewer_id)
                .where(StoryView.story_id == story_id)
                .order_by(StoryView.viewed_at.desc())
            )
            result = await self.db.execute(query)
            rows = result.all()
        except Exception as exc:
            logger.error(
                "[STORY VIEWERS] Görüntüleyenler getirilemedi | story_id=%s | %s",
                story_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Görüntüleyenler yüklenemedi")

        viewers = [
            StoryViewerOut(
                user_id=user.id,
                username=user.username,
                full_name=user.full_name,
                profile_image_thumb_url=getattr(user, "profile_image_thumb_url", None),
                viewed_at=sv.viewed_at,
            )
            for sv, user in rows
        ]
        logger.info(
            "[STORY VIEWERS] Listelendi | story_id=%s | owner_id=%s | adet=%d",
            story_id, owner_id, len(viewers),
        )
        return StoryViewersResponse(story_id=story_id, viewers=viewers, total=len(viewers))

    # ── Hikaye silme (kullanıcı isteği) ───────────────────────────────────────

    async def delete_story(self, user_id: int, story_id: int) -> None:
        """
        Kullanıcının kendi hikayesini siler.
          - Sahiplik kontrolü: story.user_id != user_id → ForbiddenException
          - Disk: video + thumbnail dosyaları silinir (bulunamazsa sessizce geçer)
          - DB: story kaydı silinir; story_views CASCADE ile otomatik temizlenir
        """
        try:
            result = await self.db.execute(select(Story).where(Story.id == story_id))
            story = result.scalar_one_or_none()
        except Exception as exc:
            logger.error("[STORY DELETE] Sorgu hatası | story_id=%d | %s", story_id, exc, exc_info=True)
            capture_exception(exc)
            raise DatabaseException("Hikaye bulunamadı")

        if story is None:
            raise NotFoundException("Hikaye bulunamadı")
        if story.user_id != user_id:
            from app.core.exceptions import ForbiddenException
            raise ForbiddenException("Bu hikayeyi silme yetkiniz yok")

        # Disk dosyalarını sil
        files_to_delete: list[tuple[str, str]] = []
        if story.video_path:
            files_to_delete.append(("video", story.video_path))
        if story.thumbnail_url:
            thumb_path = settings.upload_dir + story.thumbnail_url[len("/uploads"):]
            files_to_delete.append(("thumbnail", thumb_path))

        for file_label, file_path in files_to_delete:
            try:
                os.remove(file_path)
                logger.info("[STORY DELETE] %s silindi: %s | story_id=%d", file_label, file_path, story_id)
            except FileNotFoundError:
                pass
            except OSError as os_err:
                logger.error("[STORY DELETE] %s silinemedi: %s | story_id=%d | %s", file_label, file_path, story_id, os_err)

        try:
            await self.db.delete(story)
            await self.db.commit()
        except Exception as exc:
            logger.error("[STORY DELETE] DB silme hatası | story_id=%d | %s", story_id, exc, exc_info=True)
            capture_exception(exc)
            raise DatabaseException("Hikaye silinemedi")

        logger.info("[STORY DELETE] Silindi | story_id=%d | user_id=%d", story_id, user_id)

    # ── Süresi dolan hikayelerin temizlenmesi ─────────────────────────────────

    @staticmethod
    async def cleanup_expired_stories(db: AsyncSession) -> int:
        """
        expires_at < now() olan tüm hikayeleri:
          1. Diskten fiziksel olarak siler (video_path üzerinden).
          2. Veritabanı kaydını siler.

        Dönüş: silinen hikaye sayısı (int).

        Dosya Silme Kuralları:
          - FileNotFoundError → sessizce geç (zaten silinmiş)
          - Diğer OSError    → logla ve devam et (DB kaydı yine de silinir)
        """
        try:
            query = select(Story).where(Story.expires_at < func.now())
            result = await db.execute(query)
            expired = result.scalars().all()
        except Exception as exc:
            logger.error(
                "[STORY CLEANUP] Süresi dolan hikayeler sorgulanamadı | %s",
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Temizlik sorgusu başarısız")

        deleted_count = 0
        for story in expired:
            # ── Fiziksel dosyaları sil (video + thumbnail) ────────────────
            files_to_delete: list[tuple[str, str]] = []
            if story.video_path:
                files_to_delete.append(("video", story.video_path))
            if story.thumbnail_url:
                # /uploads/stories/thumb_xxx.jpg → {upload_dir}/stories/thumb_xxx.jpg
                thumb_path = settings.upload_dir + story.thumbnail_url[len("/uploads"):]
                files_to_delete.append(("thumbnail", thumb_path))

            for file_label, file_path in files_to_delete:
                try:
                    os.remove(file_path)
                    logger.info(
                        "[STORY CLEANUP] %s silindi: %s | story_id=%d",
                        file_label,
                        file_path,
                        story.id,
                    )
                except FileNotFoundError:
                    logger.warning(
                        "[STORY CLEANUP] %s bulunamadı, atlandı: %s | story_id=%d",
                        file_label,
                        file_path,
                        story.id,
                    )
                except OSError as os_err:
                    logger.error(
                        "[STORY CLEANUP] %s silinemedi: %s | story_id=%d | hata: %s",
                        file_label,
                        file_path,
                        story.id,
                        os_err,
                        exc_info=True,
                    )

            # ── DB kaydını sil (story_views CASCADE ile otomatik silinir) ─
            try:
                await db.delete(story)
                deleted_count += 1
            except Exception as exc:
                logger.error(
                    "[STORY CLEANUP] DB kaydı silinemedi | story_id=%d | %s",
                    story.id,
                    exc,
                    exc_info=True,
                )
                capture_exception(exc)

        try:
            await db.commit()
        except Exception as exc:
            logger.error(
                "[STORY CLEANUP] Commit başarısız | %s", exc, exc_info=True
            )
            capture_exception(exc)
            raise DatabaseException("Temizlik commit başarısız")

        logger.info("[STORY CLEANUP] Tamamlandı | silinen=%d", deleted_count)
        return deleted_count
