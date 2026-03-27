"""
Story servisi — iş mantığını router'dan ayırır.

Sağlanan metodlar:
  get_following_stories   — takip edilen kullanıcıların aktif hikayelerini
                            kullanıcı bazlı gruplayarak döner.
  upload_story            — video dosyasını diske kaydeder, DB kaydı oluşturur.
  cleanup_expired_stories — süresi dolan hikayeleri diskten ve DB'den siler.

Hata Yönetimi:
  DB hataları   → logger.error + capture_exception → DatabaseException (500)
  Disk hataları → FileNotFoundError sessizce yutulur, OSError loglanır
"""
import os
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from fastapi import UploadFile

from app.config import settings
from app.models.story import Story
from app.models.user import User
from app.models.follow import Follow
from app.schemas.story import StoryAuthorOut, StoryOut, UserStoryGroupResponse
from app.core.exceptions import DatabaseException, BadRequestException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


class StoryService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ── Takip edilen kullanıcıların aktif hikayeleri ──────────────────────────

    async def get_following_stories(
        self, current_user_id: int
    ) -> List[UserStoryGroupResponse]:
        """
        Kullanıcının takip ettiği kişilerin süresi dolmamış hikayelerini
        kullanıcı bazlı gruplayarak döner.

        SQL mantığı:
          1. stories JOIN users (sahibi) JOIN follows (takip ilişkisi) — tek sorgu
          2. WHERE expires_at > now() AND follow.follower_id = current_user_id
          3. ORDER BY story.created_at ASC (her grubun içi kronolojik)
          4. Python tarafında user_id'ye göre grupla
          5. Grupları en son hikaye zamanına göre DESC sırala
        """
        try:
            query = (
                select(Story, User)
                .join(User, User.id == Story.user_id)
                .join(Follow, Follow.followed_id == Story.user_id)
                .where(
                    Follow.follower_id == current_user_id,
                    Story.expires_at > func.now(),
                )
                .order_by(Story.created_at.asc())
            )
            result = await self.db.execute(query)
            rows = result.all()
        except Exception as exc:
            logger.error(
                "[STORY] Takip edilen hikayeler getirilemedi | user_id=%s | %s",
                current_user_id,
                exc,
                exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Hikayeler yüklenemedi")

        # ── Python'da kullanıcı bazlı gruplama ───────────────────────────────
        # key: user_id → {"user": User, "stories": [Story, ...], "latest_at": datetime}
        groups: dict[int, dict] = defaultdict(lambda: {"user": None, "stories": [], "latest_at": None})

        for story, user in rows:
            g = groups[user.id]
            g["user"] = user
            g["stories"].append(story)
            if g["latest_at"] is None or story.created_at > g["latest_at"]:
                g["latest_at"] = story.created_at

        # En son hikaye atan kullanıcı başta (DESC)
        sorted_groups = sorted(
            groups.values(),
            key=lambda g: g["latest_at"] or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )

        response: List[UserStoryGroupResponse] = []
        for g in sorted_groups:
            user_obj: User = g["user"]
            response.append(
                UserStoryGroupResponse(
                    user=StoryAuthorOut.model_validate(user_obj),
                    stories=[StoryOut.model_validate(s) for s in g["stories"]],
                    latest_story_at=g["latest_at"],
                )
            )

        logger.info(
            "[STORY] Takip edilen hikayeler listelendi | user_id=%s | grup_sayısı=%d",
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
        _MAX_BYTES = 100 * 1024 * 1024  # 100 MB

        content_type = file.content_type or ''
        if not content_type.startswith('video/'):
            raise BadRequestException("Yalnızca video dosyası yüklenebilir")

        raw = await file.read()
        if len(raw) > _MAX_BYTES:
            raise BadRequestException("Video dosyası 100 MB sınırını aşıyor")

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
                file_path, user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Dosya kaydedilemedi")

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
                user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Hikaye kaydedilemedi")

        logger.info(
            "[STORY UPLOAD] Yüklendi | story_id=%d | user_id=%s | path=%s",
            story.id, user_id, file_path,
        )
        return story

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
            # ── Fiziksel dosyayı sil ──────────────────────────────────────
            if story.video_path:
                try:
                    os.remove(story.video_path)
                    logger.info(
                        "[STORY CLEANUP] Dosya silindi: %s | story_id=%d",
                        story.video_path,
                        story.id,
                    )
                except FileNotFoundError:
                    # Dosya zaten yok — sessizce geç
                    logger.warning(
                        "[STORY CLEANUP] Dosya bulunamadı, atlandı: %s | story_id=%d",
                        story.video_path,
                        story.id,
                    )
                except OSError as os_err:
                    logger.error(
                        "[STORY CLEANUP] Dosya silinemedi: %s | story_id=%d | hata: %s",
                        story.video_path,
                        story.id,
                        os_err,
                        exc_info=True,
                    )

            # ── DB kaydını sil ────────────────────────────────────────────
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

        logger.info(
            "[STORY CLEANUP] Tamamlandı | silinen=%d", deleted_count
        )
        return deleted_count
