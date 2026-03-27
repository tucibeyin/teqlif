"""
Story router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db) alır
  2. StoryService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı tamamen app.services.story_service.StoryService'e taşınmıştır.
"""
from typing import List

from fastapi import APIRouter, Depends, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.story import UserStoryGroupResponse, StoryItemOut  # noqa: F401
from app.utils.auth import get_current_user
from app.services.story_service import StoryService
from app.core.logger import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/api/stories", tags=["stories"])


@router.get("/following", response_model=List[UserStoryGroupResponse])
async def get_following_stories(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Kullanıcının takip ettiği kişilerin aktif (süresi dolmamış) hikayelerini
    kullanıcı bazlı gruplayarak döner.

    Sıralama: En son hikaye atan kullanıcı başta; her kullanıcının
    kendi hikayeleri en eski → en yeni (created_at ASC).
    """
    return await StoryService(db).get_following_stories(current_user.id)


@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_story(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Sıkıştırılmış video dosyasını alır, diske kaydeder ve
    24 saat geçerliliğe sahip story kaydı oluşturur.
    """
    story = await StoryService(db).upload_story(current_user.id, file)
    return {"id": story.id, "video_url": story.video_url, "expires_at": story.expires_at}


@router.post("/cleanup", status_code=200)
async def cleanup_expired_stories(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Süresi dolan hikayeleri diskten ve DB'den siler.

    ⚠️  Bu endpoint yalnızca admin/internal kullanım içindir.
        Üretimde bir cron job veya ARQ task'e taşınması önerilir.
    """
    if current_user.email != (await _get_admin_email()):
        from app.core.exceptions import ForbiddenException
        raise ForbiddenException("Bu işlem için yetkiniz yok")

    deleted = await StoryService.cleanup_expired_stories(db)
    logger.info(
        "[STORY CLEANUP] Manuel tetikleme | tetikleyen=%s | silinen=%d",
        current_user.username,
        deleted,
    )
    return {"deleted": deleted, "message": f"{deleted} süresi dolmuş hikaye temizlendi"}


async def _get_admin_email() -> str:
    from app.config import settings
    return settings.admin_email
