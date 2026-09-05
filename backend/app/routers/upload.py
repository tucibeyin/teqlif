import asyncio
import os
import shutil
import tempfile
import uuid

from fastapi import APIRouter, Depends, Request, UploadFile, File

from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter
from app.services import storage_service as storage
from app.constants.media_limits import IMAGE_MAX_BYTES, LISTING_VIDEO_MAX_BYTES, VIDEO_MAX_SECS
from app.utils.media_processor import (
    detect_image_type as _detect_image_type,
    detect_video_type as _detect_video_type,
    get_video_duration as _get_video_duration,
    make_thumbnail as _make_thumbnail,
    IMAGE_CONTENT_TYPES as _IMAGE_CONTENT_TYPES,
)

logger = get_logger(__name__)

router = APIRouter(prefix="/api/upload", tags=["upload"])

_CHUNK = 65536  # 64 KB


async def _read_streaming(file: UploadFile, max_bytes: int) -> bytes:
    """Chunk okuyarak max_bytes kontrolü yapar — tam dosyayı belleğe almadan."""
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await file.read(_CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise BadRequestException(code="FILE_TOO_LARGE")
        chunks.append(chunk)
    return b"".join(chunks)


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
            "-t", str(int(VIDEO_MAX_SECS)),
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
    # Content-Length early rejection
    cl = request.headers.get("content-length")
    if cl and int(cl) > LISTING_VIDEO_MAX_BYTES:
        raise BadRequestException(code="VIDEO_TOO_LARGE")

    data = await _read_streaming(file, LISTING_VIDEO_MAX_BYTES)

    if _detect_video_type(data) is None:
        raise BadRequestException(code="INVALID_VIDEO_FORMAT")

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.mp4")
        with open(tmp_path, "wb") as f:
            f.write(data)

        duration = await _get_video_duration(tmp_path)
        if duration is not None and duration > VIDEO_MAX_SECS:
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
    # Content-Length early rejection
    cl = request.headers.get("content-length")
    if cl and int(cl) > IMAGE_MAX_BYTES:
        raise BadRequestException(code="FILE_TOO_LARGE")

    data = await _read_streaming(file, IMAGE_MAX_BYTES)

    ext = _detect_image_type(data)
    if ext is None:
        raise BadRequestException(code="INVALID_IMAGE_FORMAT")

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
