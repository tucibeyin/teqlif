import io
import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File
from PIL import Image
from app.config import settings
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/api/upload", tags=["upload"])

MAX_SIZE = 10 * 1024 * 1024  # 10 MB
_THUMB_SIZE = (400, 400)      # Hem profil hem ilan için yeterli


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


def _make_thumbnail(data: bytes, ext: str) -> bytes:
    """
    Görüntüyü merkeze göre kırparak _THUMB_SIZE boyutuna küçültür.
    PIL LANCZOS filtresiyle yeniden örnekler; çıktıyı bytes olarak döner.
    """
    img = Image.open(io.BytesIO(data))
    # EXIF yönlendirmesini uygula (döndürülmüş fotoğraflar)
    try:
        from PIL import ImageOps
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass

    # RGBA / P modunu RGB'ye çevir (JPEG kaydetmek için gerekli)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    # Oranı koruyarak en küçük kenar _THUMB_SIZE'a sığacak şekilde ölçekle
    img.thumbnail(_THUMB_SIZE, Image.LANCZOS)

    # Merkeze göre kırp (nesne sığıyor, küçük boyuttaysa kırpmaya gerek yok)
    w, h = img.size
    tw, th = _THUMB_SIZE
    left = max((w - tw) // 2, 0)
    top = max((h - th) // 2, 0)
    right = min(left + tw, w)
    bottom = min(top + th, h)
    img = img.crop((left, top, right, bottom))

    buf = io.BytesIO()
    fmt = "JPEG" if ext in ("jpg", "webp", "gif") else "PNG"
    img.save(buf, format=fmt, quality=85, optimize=True)
    return buf.getvalue()


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

    base_name = uuid.uuid4().hex
    filename = f"{base_name}.{ext}"
    thumb_ext = "jpg" if ext in ("jpg", "webp", "gif") else "png"
    thumb_filename = f"{base_name}_thumb.{thumb_ext}"

    os.makedirs(settings.upload_dir, exist_ok=True)

    # Orijinal resmi kaydet
    dest = os.path.join(settings.upload_dir, filename)
    try:
        with open(dest, "wb") as f:
            f.write(data)
    except OSError as e:
        logger.error("Orijinal resim kaydedilemedi: %s", str(e), exc_info=True)
        raise BadRequestException("Dosya kaydedilemedi")

    # Thumbnail üret ve kaydet
    try:
        thumb_data = _make_thumbnail(data, ext)
        thumb_dest = os.path.join(settings.upload_dir, thumb_filename)
        with open(thumb_dest, "wb") as f:
            f.write(thumb_data)
    except Exception as e:
        logger.error("Thumbnail oluşturulamadı: %s", str(e), exc_info=True)
        # Thumbnail başarısız olsa bile orijinali döndür; thumb_url None
        return {"url": f"/uploads/{filename}", "thumb_url": None}

    return {
        "url": f"/uploads/{filename}",
        "thumb_url": f"/uploads/{thumb_filename}",
    }
