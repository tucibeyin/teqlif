import uuid

from fastapi import APIRouter, Depends, Request, UploadFile, File

from app.models.user import User
from app.utils.auth import get_current_user
from app.core.exceptions import BadRequestException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter
from app.core.task_queue import get_pool
from app.services import storage_service as storage
from app.constants.media_limits import IMAGE_MAX_BYTES, LISTING_VIDEO_MAX_BYTES
from app.utils.media_processor import (
    detect_image_type as _detect_image_type,
    detect_video_type as _detect_video_type,
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

    # Ham videoyu MinIO'ya yükle — FFmpeg işlemi HTTP bağlantısını tutmaz
    video_key = f"listings/video/{uuid.uuid4().hex}.mp4"
    video_url = await storage.upload_bytes_async(video_key, data, "video/mp4")

    # ARQ video kuyruğuna devret: remux + thumbnail arka planda işlenir
    pool = get_pool()
    if pool:
        await pool.enqueue_job(
            "process_listing_video_task",
            video_key,
            _queue_name="video",
            _job_id=f"proc_video:{video_key}",
        )

    logger.info(
        "[UPLOAD] İlan videosu yüklendi (ham) | user_id=%s | key=%s",
        current_user.id, video_key,
    )
    return {"video_url": video_url, "thumb_url": None}


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

    url = await storage.upload_bytes_async(filename, data, _IMAGE_CONTENT_TYPES[ext])

    try:
        thumb_data = _make_thumbnail(data, ext)
        thumb_url = await storage.upload_bytes_async(
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
