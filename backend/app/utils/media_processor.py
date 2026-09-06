"""
Medya işleme — detection, validation, upload, thumbnail.
Strateji deseni: her içerik tipi için ayrı Processor sınıfı.
"""
import asyncio
import io
import os
import shutil
import tempfile
import uuid
from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

from PIL import Image

from app.core.exceptions import BadRequestException
from app.core.logger import get_logger
from app.services import storage_service as storage
from app.constants.media_limits import VIDEO_MAX_SECS, VOICE_MAX_SECS

logger = get_logger(__name__)

_THUMB_SIZE = (400, 400)

IMAGE_CONTENT_TYPES: dict[str, str] = {
    "jpg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
}


# ── Sonuç veri sınıfı ────────────────────────────────────────────────────────

@dataclass
class MediaProcessResult:
    media_url: str
    thumbnail_url: str | None = None
    file_name: str | None = None
    duration_secs: int | None = None
    uploaded_dm_keys: list[str] = field(default_factory=list)  # orphan cleanup için (DM bucket)


# ── Detection fonksiyonları ──────────────────────────────────────────────────

def detect_image_type(data: bytes) -> str | None:
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    return None


def detect_video_type(data: bytes) -> str | None:
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "mp4"
    if data[:4] == b"\x1a\x45\xdf\xa3":
        return "webm"
    return None


def detect_audio_type(data: bytes) -> str | None:
    if len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xF6) == 0xF0:
        return "aac"
    if data[:4] == b"OggS":
        return "ogg"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "m4a"
    if len(data) >= 3 and data[:3] == b"ID3":
        return "mp3"
    return None


def validate_file_magic(data: bytes, ext: str) -> str | None:
    """Magic byte + extension çapraz doğrulaması. Geçerliyse MIME döner, değilse None."""
    if data[:4] == b"%PDF":
        return "application/pdf"
    if data[:4] == b"PK\x03\x04":
        mime_map = {
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        }
        return mime_map.get(ext)
    if data[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        if ext == "doc":
            return "application/msword"
        if ext == "xls":
            return "application/vnd.ms-excel"
        return None
    if ext == "txt":
        try:
            data[:512].decode("utf-8")
            return "text/plain"
        except UnicodeDecodeError:
            return None
    return None


def make_thumbnail(data: bytes, ext: str) -> bytes:
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


async def get_video_duration(path: str) -> float | None:
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


# ── Strateji: Processor Protocol + Uygulamalar ──────────────────────────────

@runtime_checkable
class MediaProcessor(Protocol):
    async def process(
        self,
        data: bytes,
        file_content_type: str,
        original_filename: str,
        duration_secs: int | None,
    ) -> MediaProcessResult: ...


class VoiceProcessor:
    _EXT_MAP = {"aac": "aac", "ogg": "ogg", "m4a": "m4a", "mp3": "mp3"}
    _CT_MAP  = {"aac": "audio/aac", "ogg": "audio/ogg", "m4a": "audio/mp4", "mp3": "audio/mpeg"}
    _ALLOWED_CT = {"audio/aac", "audio/mp4", "audio/x-m4a", "audio/mpeg", "audio/ogg", "audio/webm", "audio/opus"}

    async def process(self, data, file_content_type, original_filename, duration_secs):
        audio_fmt = detect_audio_type(data)
        if audio_fmt is None:
            if not any(file_content_type.lower().startswith(ct) for ct in self._ALLOWED_CT):
                raise BadRequestException(code="UNSUPPORTED_AUDIO_FORMAT")
            audio_fmt = "aac"
        ext = self._EXT_MAP.get(audio_fmt, "aac")
        key = f"messages/voice/{uuid.uuid4().hex}.{ext}"
        url = storage.upload_bytes_dm(key, data, self._CT_MAP.get(audio_fmt, "audio/aac"))
        resolved = min(duration_secs, VOICE_MAX_SECS) if duration_secs is not None else None
        return MediaProcessResult(media_url=url, duration_secs=resolved, uploaded_dm_keys=[key])


class ImageProcessor:
    async def process(self, data, file_content_type, original_filename, duration_secs):
        ext = detect_image_type(data)
        if ext is None:
            raise BadRequestException(code="INVALID_IMAGE_FORMAT")
        key = f"messages/img/{uuid.uuid4().hex}.{ext}"
        url = storage.upload_bytes_dm(key, data, IMAGE_CONTENT_TYPES[ext])
        uploaded = [key]
        thumb_url = None
        try:
            thumb_data = make_thumbnail(data, ext)
            thumb_ext = "jpg" if ext != "png" else "png"
            thumb_key = f"messages/img/{uuid.uuid4().hex}_thumb.{thumb_ext}"
            thumb_url = storage.upload_bytes_dm(
                thumb_key, thumb_data,
                "image/jpeg" if thumb_ext == "jpg" else "image/png",
            )
            uploaded.append(thumb_key)
        except Exception as exc:
            logger.warning("[ImageProcessor] Thumbnail oluşturulamadı: %s", exc)
        return MediaProcessResult(media_url=url, thumbnail_url=thumb_url, uploaded_dm_keys=uploaded)


class VideoProcessor:
    async def process(self, data, file_content_type, original_filename, duration_secs):
        vid_fmt = detect_video_type(data)
        if vid_fmt is None:
            raise BadRequestException(code="INVALID_VIDEO_FORMAT")
        uploaded: list[str] = []
        with tempfile.TemporaryDirectory() as tmp_dir:
            src_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.{vid_fmt}")
            with open(src_path, "wb") as f:
                f.write(data)
            detected_dur = await get_video_duration(src_path)
            if detected_dur is not None and detected_dur > VIDEO_MAX_SECS:
                raise BadRequestException(code="VIDEO_TOO_LONG")
            resolved_duration = int(detected_dur) if detected_dur is not None else duration_secs
            key = f"messages/vid/{uuid.uuid4().hex}.{vid_fmt}"
            media_url = storage.upload_file_dm(key, src_path, "video/mp4")
            uploaded.append(key)
            thumb_url = None
            if shutil.which("ffmpeg"):
                thumb_path = os.path.join(tmp_dir, f"{uuid.uuid4().hex}_thumb.jpg")
                try:
                    proc = await asyncio.create_subprocess_exec(
                        "ffmpeg", "-y", "-i", src_path,
                        "-ss", "0", "-frames:v", "1", "-q:v", "2",
                        thumb_path,
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    await asyncio.wait_for(proc.communicate(), timeout=20)
                    if os.path.exists(thumb_path):
                        with open(thumb_path, "rb") as tf:
                            thumb_bytes = tf.read()
                        thumb_key = f"messages/vid/{uuid.uuid4().hex}_thumb.jpg"
                        thumb_url = storage.upload_bytes_dm(thumb_key, thumb_bytes, "image/jpeg")
                        uploaded.append(thumb_key)
                except Exception as exc:
                    logger.warning("[VideoProcessor] Thumbnail hatası: %s", exc)
        return MediaProcessResult(
            media_url=media_url,
            thumbnail_url=thumb_url,
            duration_secs=resolved_duration,
            uploaded_dm_keys=uploaded,
        )


class FileProcessor:
    async def process(self, data, file_content_type, original_filename, duration_secs):
        ext = (original_filename.rsplit(".", 1)[-1].lower() if "." in (original_filename or "") else "")
        mime = validate_file_magic(data, ext)
        if mime is None:
            raise BadRequestException(code="UNSUPPORTED_FILE_TYPE")
        file_name = (original_filename or f"dosya.{ext or 'bin'}")[:255]
        key = f"messages/file/{uuid.uuid4().hex}.{ext or 'bin'}"
        url = storage.upload_bytes_dm(key, data, mime)
        return MediaProcessResult(media_url=url, file_name=file_name, uploaded_dm_keys=[key])


PROCESSORS: dict[str, MediaProcessor] = {
    "voice": VoiceProcessor(),
    "image": ImageProcessor(),
    "video": VideoProcessor(),
    "file":  FileProcessor(),
}


async def process_media(
    content_type: str,
    data: bytes,
    file_content_type: str,
    original_filename: str,
    duration_secs: int | None,
) -> MediaProcessResult:
    processor = PROCESSORS.get(content_type)
    if processor is None:
        raise BadRequestException(code="UNSUPPORTED_FILE_TYPE")
    return await processor.process(data, file_content_type, original_filename, duration_secs)
