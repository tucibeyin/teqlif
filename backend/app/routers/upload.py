import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File
from app.config import settings
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException

router = APIRouter(prefix="/api/upload", tags=["upload"])

MAX_SIZE = 10 * 1024 * 1024  # 10 MB


def _detect_image_type(data: bytes) -> str | None:
    """Magic bytes ile gerçek resim türünü tespit et."""
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    return None


@router.post("")
async def upload_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    data = await file.read()
    if len(data) > MAX_SIZE:
        raise BadRequestException("Dosya boyutu 10 MB'ı geçemez")

    ext = _detect_image_type(data)
    if ext is None:
        raise BadRequestException("Sadece JPEG, PNG, WebP veya GIF yüklenebilir")
    filename = f"{uuid.uuid4().hex}.{ext}"

    os.makedirs(settings.upload_dir, exist_ok=True)
    dest = os.path.join(settings.upload_dir, filename)
    with open(dest, "wb") as f:
        f.write(data)

    return {"url": f"/uploads/{filename}"}
