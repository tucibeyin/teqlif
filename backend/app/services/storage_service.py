"""
MinIO object storage wrapper.

Tüm dosya yükleme/silme işlemleri bu modül üzerinden yapılır.
URL formatı: /uploads/{key}  — nginx MinIO'yu bu path altında proxy'ler.

Bucket politikası: public-read (nginx proxy erişebilmesi için).
DM bucket (teqlif-dm): private — presigned URL ile erişim (Faz 5).
"""
import io
from datetime import timedelta
from typing import Protocol, runtime_checkable

from minio import Minio
from minio.error import S3Error

from app.config import settings
from app.core.logger import get_logger


@runtime_checkable
class AbstractStorageService(Protocol):
    def upload_bytes(self, key: str, data: bytes, content_type: str) -> str: ...
    def upload_file(self, key: str, path: str, content_type: str) -> str: ...
    def delete_object(self, key: str) -> None: ...
    def url_to_key(self, url: str) -> str: ...
    def presign_get(self, key: str, expires: timedelta) -> str: ...

logger = get_logger(__name__)

# Module import sırasında bir kez oluşturulur — lazy singleton race condition yok.
_client = Minio(
    settings.minio_endpoint,
    access_key=settings.minio_access_key,
    secret_key=settings.minio_secret_key,
    secure=settings.minio_secure,
)


def _get_client() -> Minio:
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


# ── DM private bucket (Faz 5) ────────────────────────────────────────────────

def upload_bytes_dm(key: str, data: bytes, content_type: str) -> str:
    """Bytes'ı private DM bucket'a yükler. Dönüş: iç key (presign için)."""
    _get_client().put_object(
        settings.minio_dm_bucket,
        key,
        io.BytesIO(data),
        length=len(data),
        content_type=content_type,
    )
    logger.debug("[STORAGE_DM] Yüklendi: %s (%d bytes)", key, len(data))
    return key


def upload_file_dm(key: str, path: str, content_type: str) -> str:
    """Disk'teki dosyayı private DM bucket'a yükler. Dönüş: iç key."""
    _get_client().fput_object(
        settings.minio_dm_bucket,
        key,
        path,
        content_type=content_type,
    )
    logger.debug("[STORAGE_DM] Dosya yüklendi: %s → %s", path, key)
    return key


def delete_object_dm(key: str) -> None:
    """DM bucket'tan nesneyi siler."""
    try:
        _get_client().remove_object(settings.minio_dm_bucket, key)
        logger.debug("[STORAGE_DM] Silindi: %s", key)
    except S3Error as e:
        if e.code != "NoSuchKey":
            logger.error("[STORAGE_DM] Nesne silinemedi: key=%s | %s", key, e)


def presign_get(key: str, expires: timedelta = timedelta(days=7)) -> str:
    """DM bucket için presigned GET URL üretir."""
    return _get_client().presigned_get_object(
        settings.minio_dm_bucket,
        key,
        expires=expires,
    )
