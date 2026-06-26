import asyncio
import io
import os
import shutil
import uuid
from fastapi import APIRouter, Depends, UploadFile, File
from PIL import Image
from app.config import settings
from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

router = APIRouter(prefix="/api/upload", tags=["upload"])

MAX_SIZE = 10 * 1024 * 1024          # 10 MB (resim)
MAX_VIDEO_SIZE = 200 * 1024 * 1024  # 200 MB (video)
MAX_VIDEO_DURATION = 15.0            # saniye
_THUMB_SIZE = (400, 400)             # Hem profil hem ilan için yeterli


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
        logger.debug("EXIF yönlendirme uygulanamadı — atlanıyor")

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


def _detect_video_type(data: bytes) -> str | None:
    """Magic bytes ile gerçek video türünü tespit et."""
    if len(data) >= 12 and data[4:8] == b'ftyp':
        return 'mp4'
    if data[:4] == b'\x1a\x45\xdf\xa3':
        return 'webm'
    return None


async def _get_video_duration(path: str) -> float | None:
    if not shutil.which("ffprobe"):
        return None
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
        return float(stdout.decode().strip())
    except Exception:
        return None


async def _process_listing_video(src: str, out_dir: str) -> tuple[str, str | None]:
    """ffmpeg ile sıkıştır + ilk kareden thumbnail üret. Sıkıştırma başarısız olursa orijinali kullanır."""
    video_name = f"{uuid.uuid4().hex}.mp4"
    thumb_name = f"{uuid.uuid4().hex}_vthumb.jpg"
    video_path = os.path.join(out_dir, video_name)
    thumb_path = os.path.join(out_dir, thumb_name)

    if shutil.which("ffmpeg"):
        # Stream copy: video yeniden encode edilmez (anlık tamamlanır).
        # iPhone H.264 / HEVC MOV → MP4 remux için yeterli.
        # -c:a aac: ses varsa AAC'ye normalize et (sessiz video sorun olmaz).
        # -t: 15 sn'yi aşan videoları kes.
        compress_cmd = [
            "ffmpeg", "-y", "-i", src,
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            "-t", str(int(MAX_VIDEO_DURATION)),
            video_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *compress_cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await asyncio.wait_for(proc.communicate(), timeout=30)
            if proc.returncode != 0 or not os.path.exists(video_path):
                raise RuntimeError("ffmpeg başarısız")
        except Exception:
            # Remux başarısız — orijinali doğrudan kullan
            shutil.copy2(src, video_path)

        thumb_cmd = [
            "ffmpeg", "-y", "-i", video_path,
            "-ss", "0", "-frames:v", "1", "-q:v", "2",
            thumb_path,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *thumb_cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await asyncio.wait_for(proc.communicate(), timeout=30)
        except Exception:
            pass
    else:
        shutil.copy2(src, video_path)

    thumb_url = f"/uploads/{thumb_name}" if os.path.exists(thumb_path) else None
    return f"/uploads/{video_name}", thumb_url


@router.post("/listing-video")
async def upload_listing_video(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    data = await file.read()
    if len(data) > MAX_VIDEO_SIZE:
        raise BadRequestException("Video boyutu 200 MB'ı geçemez")

    if _detect_video_type(data) is None:
        raise BadRequestException("Sadece MP4, MOV veya WebM video yüklenebilir")

    os.makedirs(settings.upload_dir, exist_ok=True)

    # Geçici dosyaya yaz (ffprobe okumak için)
    tmp_name = f"tmp_{uuid.uuid4().hex}.mp4"
    tmp_path = os.path.join(settings.upload_dir, tmp_name)
    try:
        with open(tmp_path, "wb") as f:
            f.write(data)

        duration = await _get_video_duration(tmp_path)
        if duration is not None and duration > MAX_VIDEO_DURATION:
            raise BadRequestException(f"Video süresi {MAX_VIDEO_DURATION:.0f} saniyeyi geçemez (süre: {duration:.1f}s)")

        video_url, thumb_url = await _process_listing_video(tmp_path, settings.upload_dir)
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    logger.info("[UPLOAD] İlan videosu yüklendi | user_id=%s | video=%s", current_user.id, video_url)
    return {"video_url": video_url, "thumb_url": thumb_url}


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
        capture_exception(e)
        # Thumbnail başarısız olsa bile orijinali döndür; thumb_url None
        return {"url": f"/uploads/{filename}", "thumb_url": None}

    return {
        "url": f"/uploads/{filename}",
        "thumb_url": f"/uploads/{thumb_filename}",
    }
