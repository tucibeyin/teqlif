"""
Auto-Highlights — Hype skoru 90'ı aştığında canlı yayından 15 saniyelik kesit kaydeder.

Akış:
  1. DB'den odanın yetkili LiveKit URL'ini al (live_streams.livekit_url)
  2. livekit_subscriber.py'yi /opt/teqlif-agent/venv/bin/python ile subprocess olarak çalıştır
     — --stop-after 15 ile 15 saniye VP8+Opus MKV üretir
  3. FFmpeg ile MKV → libx264+AAC+faststart MP4 encode
  4. MinIO'ya yükle, geçici dosyaları sil
  5. Listings tablosuna geçici highlight kaydı ekle (expires_at = +2 saat)

ARQ video kuyruğunda çalışır (WorkerSettingsVideo, node1).
Tüm hatalar yumuşak yakalanır — yayın hiçbir zaman bu görev yüzünden etkilenmez.
"""

from __future__ import annotations

import asyncio
import os
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.core.logger import get_logger

logger = get_logger(__name__)

_CAPTURE_SECONDS    = 15
_SUBSCRIBER_TIMEOUT = _CAPTURE_SECONDS + 45   # bağlanma + kayıt + kapanış payı
_ENCODE_TIMEOUT     = 120
# teqlif-agent venv — livekit.rtc + av + numpy burada kurulu
_SUBSCRIBER_PYTHON  = "/opt/teqlif-agent/venv/bin/python"
_SUBSCRIBER_SCRIPT  = Path("/var/www/teqlif.com/deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py")


async def _get_stream_livekit_url(room_id: int) -> str | None:
    """DB'den odanın yetkili LiveKit node URL'ini döner (live_streams.livekit_url)."""
    from app.database import AsyncSessionLocal
    from sqlalchemy import text

    async with AsyncSessionLocal() as db:
        row = await db.execute(
            text("SELECT livekit_url FROM live_streams WHERE id = :id"),
            {"id": room_id},
        )
        r = row.fetchone()
        return r[0] if r else None


async def _run_livekit_subscriber(
    ws_url: str, room_name: str, room_id: int, mkv_path: str,
) -> bool:
    """livekit_subscriber.py'yi teqlif-agent venv ile subprocess olarak çalıştırır."""
    from app.config import settings

    if not _SUBSCRIBER_SCRIPT.is_file():
        logger.warning("[Highlight] livekit_subscriber.py bulunamadı: %s", _SUBSCRIBER_SCRIPT)
        return False

    cmd = [
        _SUBSCRIBER_PYTHON, str(_SUBSCRIBER_SCRIPT),
        "--room",       room_name,
        "--ws-url",     ws_url,
        "--api-key",    settings.livekit_api_key,
        "--api-secret", settings.livekit_api_secret,
        "--output",     mkv_path,
        "--stop-after", str(_CAPTURE_SECONDS),
    ]

    logger.info("[Highlight] Subscriber başlatılıyor | room_id=%s ws=%s", room_id, ws_url)
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await asyncio.wait_for(proc.communicate(), timeout=_SUBSCRIBER_TIMEOUT)
        if proc.returncode != 0:
            err = (stderr or b"").decode(errors="replace")[-500:]
            logger.warning(
                "[Highlight] Subscriber başarısız | room_id=%s rc=%s | %s",
                room_id, proc.returncode, err,
            )
            return False
    except asyncio.TimeoutError:
        logger.warning("[Highlight] Subscriber timeout | room_id=%s", room_id)
        try:
            proc.kill()
        except Exception:
            pass
        return False
    except Exception as exc:
        logger.warning("[Highlight] Subscriber hata | room_id=%s | %s", room_id, exc)
        return False

    if not Path(mkv_path).exists() or Path(mkv_path).stat().st_size < 1024:
        logger.warning("[Highlight] MKV dosyası boş veya yok | room_id=%s", room_id)
        return False

    logger.info("[Highlight] MKV kaydedildi | room_id=%s", room_id)
    return True


async def _encode_highlight(mkv_path: str, mp4_path: str, room_id: int) -> bool:
    """VP8+Opus MKV → libx264+AAC+faststart MP4 encode."""
    cmd = [
        "nice", "-n", "19",
        "ffmpeg", "-hide_banner", "-loglevel", "warning",
        "-i", mkv_path,
        "-vf", "scale=-2:720",
        "-c:v", "libx264", "-crf", "23", "-preset", "fast",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        "-y", mp4_path,
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr = await asyncio.wait_for(proc.communicate(), timeout=_ENCODE_TIMEOUT)
        if proc.returncode != 0:
            err = (stderr or b"").decode(errors="replace")[-300:]
            logger.warning(
                "[Highlight] FFmpeg encode başarısız | room_id=%s rc=%s | %s",
                room_id, proc.returncode, err,
            )
            return False
    except asyncio.TimeoutError:
        logger.warning("[Highlight] FFmpeg encode timeout | room_id=%s", room_id)
        try:
            proc.kill()
        except Exception:
            pass
        return False
    except Exception as exc:
        logger.warning("[Highlight] FFmpeg encode hata | room_id=%s | %s", room_id, exc)
        return False

    logger.info("[Highlight] MP4 encode tamam | room_id=%s", room_id)
    return True


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


async def capture_hype_highlight(ctx: dict, room_name: str, room_id: int, host_id: int) -> None:
    """
    LiveKit odasından 15 saniyelik kesit çeker, MinIO'ya yükler ve DB'ye kaydeder.

    ARQ video kuyruğunda (WorkerSettingsVideo, node1) çalışır.
    Herhangi bir adımda hata olursa sadece log bırakır, exception fırlatmaz.
    """
    from app.config import settings

    try:
        lk_url = await _get_stream_livekit_url(room_id)
        if not lk_url:
            lk_url = settings.edge_livekit_urls[0] if settings.edge_livekit_urls else ""
            logger.warning(
                "[Highlight] DB'de livekit_url yok, fallback | room_id=%s url=%s",
                room_id, lk_url,
            )
        if not lk_url:
            logger.warning("[Highlight] Yetkili LiveKit URL bulunamadı | room_id=%s", room_id)
            return
    except Exception as exc:
        logger.warning("[Highlight] URL elde edilemedi | room_id=%s | %s", room_id, exc)
        return

    mkv_fd, mkv_path = tempfile.mkstemp(suffix=".mkv", prefix=f"highlight_{room_id}_")
    os.close(mkv_fd)
    mp4_fd, mp4_path = tempfile.mkstemp(suffix=".mp4", prefix=f"highlight_{room_id}_")
    os.close(mp4_fd)

    try:
        if not await _run_livekit_subscriber(lk_url, room_name, room_id, mkv_path):
            return

        if not await _encode_highlight(mkv_path, mp4_path, room_id):
            return

        try:
            video_url = await _upload_highlight(mp4_path, room_id)
        except Exception as exc:
            logger.warning("[Highlight] MinIO yükleme başarısız | room_id=%s | %s", room_id, exc)
            return

        try:
            await _insert_highlight_record(room_id, host_id, video_url)
        except Exception as exc:
            logger.warning("[Highlight] DB kaydı başarısız | room_id=%s | %s", room_id, exc)
            try:
                from app.services import storage_service as storage
                await storage.delete_object(video_url)
            except Exception:
                pass
    finally:
        for p in (mkv_path, mp4_path):
            try:
                os.unlink(p)
            except OSError:
                pass
