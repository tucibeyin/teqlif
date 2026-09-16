"""
MinIO object storage wrapper with dynamic Media Routing (V1.4).

Public bucket  (teqlif)    → DNS Only URL → /uploads/{key}
Private bucket (teqlif-dm) → DNS Only URL → /dm/{key}
"""
import asyncio
import io
import urllib.parse
from datetime import timedelta
from typing import Protocol, runtime_checkable

from minio import Minio
from minio.error import S3Error

from app.config import settings
from app.core.logger import get_logger
from app.services.edge_orchestrator import orchestrator, ServiceType

logger = get_logger(__name__)

# Minio Connection Pool (Key: internal minio_url)
_clients_pool: dict[str, Minio] = {}


def _clean_endpoint(url: str) -> str:
    """Minio client requires host:port without scheme or paths."""
    cleaned = url.replace("https://", "").replace("http://", "")
    return cleaned.split("/")[0]


def _get_client_for_internal_url(internal_url: str) -> Minio:
    if internal_url not in _clients_pool:
        _clients_pool[internal_url] = Minio(
            _clean_endpoint(internal_url),
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=False,  # Internal IP uses HTTP
            region=settings.minio_region,
        )
    return _clients_pool[internal_url]


async def _get_client_from_public_url(public_url: str) -> Minio:
    """URL'i parse edip hangi MinIO sunucusunda olduğunu bulur (Media Routing)."""
    parsed = urllib.parse.urlparse(public_url)
    domain = parsed.netloc

    # Fallback to default internal edge if not absolute
    if not domain:
        if settings.edge_minio_urls:
            return _get_client_for_internal_url(settings.edge_minio_urls[0])
        raise ValueError("No Edge MinIO URLs configured")

    metrics = await orchestrator.get_edge_metrics()
    for m in metrics:
        nid = m.get("node_id", "")
        # Either exact match or live1.teqlif.com match
        expected_nid = domain.replace("minio", "live")
        if nid == expected_nid or nid == domain:
            return _get_client_for_internal_url(m["minio_url"])
    
    # Fallback if node offline / deleted
    if settings.edge_minio_urls:
        return _get_client_for_internal_url(settings.edge_minio_urls[0])
    raise ValueError(f"Could not route media for domain: {domain}")


def _build_public_url(node_id: str, path: str) -> str:
    """live1.teqlif.com -> https://minio1.teqlif.com/path"""
    domain = node_id.replace("live", "minio")
    return f"https://{domain}{path}"


# ── Public bucket ─────────────────────────────────────────────────────────────

async def upload_bytes(key: str, data: bytes, content_type: str) -> str:
    node = await orchestrator.allocate_node(ServiceType.STORAGE)
    client = _get_client_for_internal_url(node["minio_url"])
    
    def _upload():
        client.put_object(
            settings.minio_bucket,
            key,
            io.BytesIO(data),
            length=len(data),
            content_type=content_type,
        )
    
    await asyncio.to_thread(_upload)
    logger.debug("[STORAGE] Yüklendi: %s (%d bytes) -> %s", key, len(data), node["node_id"])
    return _build_public_url(node["node_id"], f"/uploads/{key}")


async def upload_file(key: str, path: str, content_type: str) -> str:
    node = await orchestrator.allocate_node(ServiceType.STORAGE)
    client = _get_client_for_internal_url(node["minio_url"])
    
    def _upload():
        client.fput_object(
            settings.minio_bucket,
            key,
            path,
            content_type=content_type,
        )
    
    await asyncio.to_thread(_upload)
    logger.debug("[STORAGE] Dosya yüklendi: %s → %s", path, key)
    return _build_public_url(node["node_id"], f"/uploads/{key}")


async def delete_object(url_or_key: str) -> None:
    """Public bucket'tan nesneyi siler (Media Routing)."""
    try:
        client = await _get_client_from_public_url(url_or_key)
        key = url_to_key(url_or_key)
        await asyncio.to_thread(client.remove_object, settings.minio_bucket, key)
        logger.debug("[STORAGE] Silindi: %s", key)
    except S3Error as e:
        if e.code != "NoSuchKey":
            logger.error("[STORAGE] Nesne silinemedi: key=%s | %s", url_or_key, e)
    except Exception as exc:
        logger.error("[STORAGE] Silme hatası: %s", exc)


def url_to_key(url: str) -> str:
    """https://minio1.teqlif.com/uploads/stories/foo.mp4  →  stories/foo.mp4"""
    parsed = urllib.parse.urlparse(url)
    path = parsed.path
    prefix = "/uploads/"
    return path[len(prefix):] if path.startswith(prefix) else path


# ── Eski sync alias (Backward compat'ı kapattığımız için asyncio wrap) ─────────
# Tüm codebase async'e çevrileceği için *_async metodları deprecated yerine standart
async def upload_bytes_async(key: str, data: bytes, content_type: str) -> str:
    return await upload_bytes(key, data, content_type)

async def upload_file_async(key: str, path: str, content_type: str) -> str:
    return await upload_file(key, path, content_type)


# ── Private DM bucket ─────────────────────────────────────────────────────────

_DM_PREFIX = "/dm/"


async def upload_bytes_dm(key: str, data: bytes, content_type: str) -> str:
    node = await orchestrator.allocate_node(ServiceType.STORAGE)
    client = _get_client_for_internal_url(node["minio_url"])
    
    def _upload():
        client.put_object(
            settings.minio_dm_bucket,
            key,
            io.BytesIO(data),
            length=len(data),
            content_type=content_type,
        )
    
    await asyncio.to_thread(_upload)
    logger.debug("[STORAGE_DM] Yüklendi: %s (%d bytes)", key, len(data))
    return _build_public_url(node["node_id"], f"{_DM_PREFIX}{key}")


async def upload_file_dm(key: str, path: str, content_type: str) -> str:
    node = await orchestrator.allocate_node(ServiceType.STORAGE)
    client = _get_client_for_internal_url(node["minio_url"])
    
    def _upload():
        client.fput_object(
            settings.minio_dm_bucket,
            key,
            path,
            content_type=content_type,
        )
    
    await asyncio.to_thread(_upload)
    logger.debug("[STORAGE_DM] Dosya yüklendi: %s → %s", path, key)
    return _build_public_url(node["node_id"], f"{_DM_PREFIX}{key}")


async def delete_object_dm(url_or_key: str) -> None:
    try:
        client = await _get_client_from_public_url(url_or_key)
        key = dm_url_to_key(url_or_key)
        await asyncio.to_thread(client.remove_object, settings.minio_dm_bucket, key)
        logger.debug("[STORAGE_DM] Silindi: %s", key)
    except S3Error as e:
        if e.code != "NoSuchKey":
            logger.error("[STORAGE_DM] Nesne silinemedi: key=%s | %s", url_or_key, e)
    except Exception as exc:
        logger.error("[STORAGE_DM] Silme hatası: %s", exc)


async def presign_get(url_or_key: str, expires: timedelta = timedelta(days=7)) -> str:
    """Private DM bucket için presigned GET URL üretir (Media Routing ile)."""
    client = await _get_client_from_public_url(url_or_key)
    key = dm_url_to_key(url_or_key)
    return await asyncio.to_thread(
        client.presigned_get_object,
        settings.minio_dm_bucket,
        key,
        expires=expires,
    )


def is_dm_url(url: str | None) -> bool:
    return bool(url and url.startswith(_DM_PREFIX))


def dm_url_to_key(url: str) -> str:
    """https://minio1.teqlif.com/dm/messages/img/xxx.jpg  →  messages/img/xxx.jpg"""
    parsed = urllib.parse.urlparse(url)
    path = parsed.path
    return path[len(_DM_PREFIX):] if path.startswith(_DM_PREFIX) else path
