"""
MinIO object storage wrapper.

Tüm dosya yükleme/silme işlemleri bu modül üzerinden yapılır.
URL formatı: /uploads/{key}  — nginx MinIO'yu bu path altında proxy'ler.

Bucket politikası: public-read (nginx proxy erişebilmesi için).
"""
import io

from minio import Minio
from minio.error import S3Error

from app.config import settings
from app.core.logger import get_logger

logger = get_logger(__name__)

_client: Minio | None = None


def _get_client() -> Minio:
    global _client
    if _client is None:
        _client = Minio(
            settings.minio_endpoint,
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=settings.minio_secure,
        )
    return _client


def upload_bytes(key: str, data: bytes, content_type: str) -> str:
    """Bytes'ı MinIO'ya yükler. Dönüş: /uploads/{key} URL'si."""
    _get_client().put_object(
        settings.minio_bucket,
        key,
        io.BytesIO(data),
        length=len(data),
        content_type=content_type,
    )
    logger.debug("[STORAGE] Yüklendi: %s (%d bytes)", key, len(data))
    return f"/uploads/{key}"


def upload_file(key: str, path: str, content_type: str) -> str:
    """Disk'teki dosyayı MinIO'ya yükler. Dönüş: /uploads/{key} URL'si."""
    _get_client().fput_object(
        settings.minio_bucket,
        key,
        path,
        content_type=content_type,
    )
    logger.debug("[STORAGE] Dosya yüklendi: %s → %s", path, key)
    return f"/uploads/{key}"


def delete_object(key: str) -> None:
    """MinIO'dan nesneyi siler. Yoksa sessizce geçer."""
    try:
        _get_client().remove_object(settings.minio_bucket, key)
        logger.debug("[STORAGE] Silindi: %s", key)
    except S3Error as e:
        if e.code != "NoSuchKey":
            logger.error("[STORAGE] Nesne silinemedi: key=%s | %s", key, e)


def url_to_key(url: str) -> str:
    """/uploads/stories/foo.mp4  →  stories/foo.mp4"""
    prefix = "/uploads/"
    return url[len(prefix):] if url.startswith(prefix) else url
