"""
Auto-Highlights — Hype skoru 90'ı aştığında canlı yayından 15 saniyelik kesit kaydeder.

Akış:
  1. LiveKit WHEP endpoint'inden 15 saniye FFmpeg ile çek
  2. Geçici yerel dosyaya yaz, MinIO'ya yükle, geçici dosyayı sil
  3. Listings tablosuna geçici highlight kaydı ekle (expires_at = +2 saat)

Tüm hatalar yumuşak yakalanır — yayın hiçbir zaman bu görev yüzünden etkilenmez.
Requires FFmpeg 6+ (WHEP input support).
"""

from __future__ import annotations

import asyncio
import os
import tempfile
from datetime import datetime, timedelta, timezone

from app.core.logger import get_logger

logger = get_logger(__name__)

_CAPTURE_SECONDS = 15
_FFMPEG_TIMEOUT = 60   # saniye — 15s çekim + buffer


def _make_livekit_recorder_token(room_name: str, room_id: int) -> str:
    """Yalnızca abone olan (can_publish=False) geçici bir LiveKit token üretir."""
    from livekit.api import AccessToken, VideoGrants
    from app.config import settings

    grant = VideoGrants(
        room_join=True,
        room=room_name,
        can_publish=False,
        can_subscribe=True,
        can_publish_data=False,
    )
    token = (
        AccessToken(settings.livekit_api_key, settings.livekit_api_secret)
        .with_identity(f"recorder-{room_id}")
        .with_name("Auto-Highlight Recorder")
        .with_grants(grant)
        .with_ttl(timedelta(minutes=5))
    )
    return token.to_jwt()


async def _upload_highlight(local_path: str, room_id: int) -> str:
    """Yerel MP4 dosyasını MinIO'ya yükler ve public URL döner."""
    from app.services import storage_service as storage
    key = f"highlights/highlight_{room_id}.mp4"
    url = await storage.upload_file(key, local_path, "video/mp4")
    logger.info("[Highlight] MinIO'ya yüklendi | room_id=%s key=%s", room_id, key)
    return url


async def _insert_highlight_record(room_id: int, host_id: int, video_url: str) -> None:
    """Listings tablosuna geçici highlight satırı ekler."""
    from app.database import AsyncSessionLocal
    from sqlalchemy import text

    expires = datetime.now(timezone.utc) + timedelta(hours=2)
    async with AsyncSessionLocal() as db:
        await db.execute(
            text("""
                INSERT INTO listings
                    (user_id, title, video_url, status,
                     is_highlight, active_room_id, expires_at, created_at)
                VALUES
                    (:uid, :title, :vurl, 'active',
                     TRUE, :rid, :exp, NOW())
                ON CONFLICT DO NOTHING
            """),
            {
                "uid": host_id,
                "title": f"Live Stream Highlight — Room {room_id}",
                "vurl": video_url,
                "rid": room_id,
                "exp": expires,
            },
        )
        await db.commit()
    logger.info("[Highlight] DB kaydı eklendi | room_id=%s expires=%s", room_id, expires)


async def capture_hype_highlight(room_name: str, room_id: int, host_id: int) -> None:
    """
    LiveKit odasından 15 saniyelik kesit çeker, MinIO'ya yükler ve DB'ye kaydeder.

    Herhangi bir adımda hata olursa sadece log bırakır, exception fırlatmaz.
    Bu fonksiyon asyncio.create_task() ile arka planda çağrılır.
    """
    try:
        from app.services.edge_orchestrator import orchestrator, ServiceType
        from app.config import settings
        node = await orchestrator.allocate_node(ServiceType.MEDIA)
        lk_http = node["livekit_url"] if node else (settings.edge_livekit_urls[0] if settings.edge_livekit_urls else "")
        whep_url = f"{lk_http}/rooms/{room_name}/whep"
        token = _make_livekit_recorder_token(room_name, room_id)
    except Exception as exc:
        logger.warning("[Highlight] Token/URL oluşturulamadı | room_id=%s | %s", room_id, exc)
        return

    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".mp4", prefix=f"highlight_{room_id}_")
    os.close(tmp_fd)
    try:
        cmd = [
            "ffmpeg", "-y",
            "-headers", f"Authorization: Bearer {token}\r\n",
            "-i", whep_url,
            "-t", str(_CAPTURE_SECONDS),
            "-c", "copy",
            tmp_path,
        ]

        logger.info("[Highlight] FFmpeg başlatıldı | room_id=%s whep=%s", room_id, whep_url)
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=_FFMPEG_TIMEOUT)
            if proc.returncode != 0:
                err = (stderr or b"").decode(errors="replace")[-500:]
                logger.warning(
                    "[Highlight] FFmpeg başarısız | room_id=%s rc=%s | %s",
                    room_id, proc.returncode, err,
                )
                return
        except asyncio.TimeoutError:
            logger.warning("[Highlight] FFmpeg timeout | room_id=%s", room_id)
            try:
                proc.kill()
            except Exception:
                pass
            return
        except FileNotFoundError:
            logger.warning("[Highlight] FFmpeg bulunamadı — kurulu mu? | room_id=%s", room_id)
            return
        except Exception as exc:
            logger.warning("[Highlight] FFmpeg beklenmeyen hata | room_id=%s | %s", room_id, exc)
            return

        logger.info("[Highlight] Video kaydedildi (geçici) | room_id=%s", room_id)

        try:
            video_url = await _upload_highlight(tmp_path, room_id)
        except Exception as exc:
            logger.warning("[Highlight] MinIO yükleme başarısız | room_id=%s | %s", room_id, exc)
            return

        try:
            await _insert_highlight_record(room_id, host_id, video_url)
        except Exception as exc:
            logger.warning("[Highlight] DB kaydı başarısız | room_id=%s | %s", room_id, exc)
            # MinIO rollback: DB yoksa nesne yetim kalır (GC DB kayıtlarından gezdiği için göremez)
            try:
                from app.services import storage_service as storage
                await storage.delete_object(video_url)
            except Exception:
                pass
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
