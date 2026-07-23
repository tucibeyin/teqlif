import asyncio
import io
import os
import shutil
import tempfile
import uuid

from fastapi import APIRouter, Depends, Request, UploadFile, File
from PIL import Image

from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter
from app.services import storage_service as storage

logger = get_logger(__name__)

router = APIRouter(prefix="/api/upload", tags=["upload"])

MAX_SIZE = 10 * 1024 * 1024
MAX_VIDEO_SIZE = 200 * 1024 * 1024
MAX_VIDEO_DURATION = 15.0
_THUMB_SIZE = (400, 400)

_IMAGE_CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
}


def _detect_image_type(data: bytes) -> str | None:
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
    img = Image.open(io.BytesIO(data))
    try:
        from PIL import ImageOps
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass

    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    img.thumbnail(_THUMB_SIZE, Image.LANCZOS)
    w, h = img.size
    tw, th = _THUMB_SIZE
    left = max((w - tw) // 2, 0)
    top = max((h - th) // 2, 0)
    img = img.crop((left, top, min(left + tw, w), min(top + th, h)))

    buf = io.BytesIO()
    fmt = "JPEG" if ext in ("jpg", "webp", "gif") else "PNG"
    img.save(buf, format=fmt, quality=85, optimize=True)
    return buf.getvalue()


def _detect_video_type(data: bytes) -> str | None:
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
    """ffmpeg ile remux + thumbnail. Dönüş: (video_local_path, thumb_local_path|None)."""
    video_path = os.path.join(out_dir, f"{uuid.uuid4().hex}.mp4")
    thumb_path = os.path.join(out_dir, f"{uuid.uuid4().hex}_vthumb.jpg")

    if shutil.which("ffmpeg"):
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
            await asyncio.wait_for(proc.communicate(), timeout=60)
            if proc.returncode != 0 or not os.path.exists(video_path):
                raise RuntimeError("ffmpeg_failed")
        except Exception:
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

    return video_path, thumb_path if os.path.exists(thumb_path) else None


@router.post("/listing-video")
@limiter.limit("10/minute")
async def upload_listing_video(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    data = await file.read()
    if len(data) > MAX_VIDEO_SIZE:
        raise BadRequestException(code="VIDEO_TOO_LARGE")

    if _detect_video_type(data) is None:
        raise BadRequestException(code="INVALID_VIDEO_FORMAT_MOV")

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.mp4")
        with open(tmp_path, "wb") as f:
            f.write(data)

        duration = await _get_video_duration(tmp_path)
        if duration is not None and duration > MAX_VIDEO_DURATION:
            raise BadRequestException(code="VIDEO_TOO_LONG")

        video_local, thumb_local = await _process_listing_video(tmp_path, tmp_dir)

        video_key = f"{uuid.uuid4().hex}.mp4"
        video_url = storage.upload_file(video_key, video_local, "video/mp4")

        thumb_url = None
        if thumb_local:
            thumb_key = f"{uuid.uuid4().hex}_vthumb.jpg"
            thumb_url = storage.upload_file(thumb_key, thumb_local, "image/jpeg")

    logger.info("[UPLOAD] İlan videosu yüklendi | user_id=%s | video=%s", current_user.id, video_url)
    return {"video_url": video_url, "thumb_url": thumb_url}


@router.post("")
@limiter.limit("20/minute")
async def upload_image(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    data = await file.read()
    if len(data) > MAX_SIZE:
        raise BadRequestException(code="FILE_TOO_LARGE")

    ext = _detect_image_type(data)
    if ext is None:
        raise BadRequestException(code="INVALID_IMAGE_FORMAT_GIF")

    base_name = uuid.uuid4().hex
    filename = f"{base_name}.{ext}"
    thumb_ext = "jpg" if ext in ("jpg", "webp", "gif") else "png"
    thumb_filename = f"{base_name}_thumb.{thumb_ext}"

    url = storage.upload_bytes(filename, data, _IMAGE_CONTENT_TYPES[ext])

    try:
        thumb_data = _make_thumbnail(data, ext)
        thumb_url = storage.upload_bytes(
            thumb_filename,
            thumb_data,
            "image/jpeg" if thumb_ext == "jpg" else "image/png",
        )
    except Exception as e:
        logger.error("Thumbnail oluşturulamadı: %s", str(e), exc_info=True)
        capture_exception(e)
        return {"url": url, "thumb_url": None}

    logger.info("[UPLOAD] Resim yüklendi | user_id=%s | url=%s", current_user.id, url)
    return {"url": url, "thumb_url": thumb_url}
