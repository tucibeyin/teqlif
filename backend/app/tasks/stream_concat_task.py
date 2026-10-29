"""V2.1 Distributed Concat ARQ görev.

Her 2 dakikada bir çalışır; bitişik part'ları olan bitmiş yayınları
MinIO'dan indirir, ffmpeg ile birleştirir ve sonucu yeniden yükler.

Bulkhead: WorkerSettingsVideo — queue=video, job_timeout=1800, max_jobs=2.
Bu görev her çalışmasında LIMIT 2 yayın işler; cron başına 1800sn tavanı
tek yayına değil toplam işleme süresine uygulanır.
"""
from __future__ import annotations

from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

_LOCK_PREFIX = "lock:concat:"
_LOCK_TTL_SEC = 3600  # maks 1 saat — ffmpeg için yeterli
_MAX_RETRY = 3


async def stream_concat_task(ctx: dict) -> None:
    """Birden fazla part kaydı olan bitmiş yayınları concat eder."""
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text

        async with AsyncSessionLocal() as session:
            rows = (await session.execute(text("""
                SELECT sr.stream_id, COUNT(*) AS part_count
                FROM stream_recordings sr
                JOIN live_streams ls ON ls.id = sr.stream_id
                WHERE ls.status = 'ended'
                  AND sr.is_concat_result = FALSE
                  AND sr.part_number IS NOT NULL
                  AND sr.status = 'available'
                  AND sr.retry_count < :max_retry
                  AND NOT EXISTS (
                      SELECT 1 FROM stream_recordings pending
                      WHERE pending.stream_id = sr.stream_id
                        AND pending.is_concat_result = FALSE
                        AND pending.status IN ('recording', 'encoding', 'encoded', 'transferring')
                  )
                GROUP BY sr.stream_id
                HAVING COUNT(*) > 1
                ORDER BY sr.stream_id
                LIMIT 2
            """), {"max_retry": _MAX_RETRY})).mappings().all()

        for row in rows:
            stream_id = row["stream_id"]
            try:
                await _do_concat(stream_id)
            except Exception as exc:
                capture_exception(exc)
                logger.error("stream_concat_task: stream_id=%s hata: %s", stream_id, exc)

    except Exception as exc:
        capture_exception(exc)
        logger.error("stream_concat_task genel hata: %s", exc)
        raise


async def _do_concat(stream_id: int) -> None:
    """Tek bir stream için concat işlemi yapar.

    Dağıtık kilit ile aynı anda tek bir worker çalışır.
    """
    from app.utils.redis_client import get_redis

    redis = await get_redis()
    lock_key = f"{_LOCK_PREFIX}{stream_id}"

    acquired = await redis.set(lock_key, "1", nx=True, ex=_LOCK_TTL_SEC)
    if not acquired:
        logger.debug("_do_concat: stream_id=%s için kilit alınamadı, atlanıyor", stream_id)
        return

    try:
        await _run_concat(stream_id)
    finally:
        await redis.delete(lock_key)


async def _mark_retry(stream_id: int, error_msg: str) -> None:
    """FFmpeg veya MinIO hatalarında retry_count artır; limit aşılınca concat_failed yap."""
    from app.database import AsyncSessionLocal
    from sqlalchemy import text

    async with AsyncSessionLocal() as session:
        result = await session.execute(text("""
            UPDATE stream_recordings
            SET retry_count   = retry_count + 1,
                error_message = :error,
                updated_at    = NOW()
            WHERE stream_id        = :sid
              AND is_concat_result = FALSE
              AND part_number      IS NOT NULL
              AND status           = 'available'
            RETURNING retry_count
        """), {"sid": stream_id, "error": error_msg[:500]})
        max_retry = max((r[0] for r in result.fetchall()), default=0)

        if max_retry >= _MAX_RETRY:
            await session.execute(text("""
                UPDATE stream_recordings
                SET status     = 'concat_failed',
                    updated_at = NOW()
                WHERE stream_id        = :sid
                  AND is_concat_result = FALSE
                  AND part_number      IS NOT NULL
                  AND status           = 'available'
            """), {"sid": stream_id})
            logger.warning(
                "_run_concat: stream_id=%s kalıcı hata (%d deneme) → concat_failed",
                stream_id, max_retry,
            )
            capture_exception(
                RuntimeError(f"stream_concat kalıcı hata stream_id={stream_id}: {error_msg[:200]}")
            )
        await session.commit()


async def _ffprobe_streams(path: str) -> dict:
    """Part dosyasının video/audio stream parametrelerini döner."""
    import asyncio
    import json as _json

    proc = await asyncio.create_subprocess_exec(
        "ffprobe", "-v", "quiet", "-print_format", "json",
        "-show_streams", "-show_format", path,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    out, _ = await proc.communicate()
    info: dict = {
        "width": 0, "height": 0, "pix_fmt": "",
        "r_frame_rate": "", "time_base": "",
        "has_audio": False, "duration": 0.0,
        "sample_rate": 0, "channels": 0,
    }
    try:
        data = _json.loads(out)
        for s in data.get("streams", []):
            if s.get("codec_type") == "video":
                info["width"]        = s.get("width", 0)
                info["height"]       = s.get("height", 0)
                info["pix_fmt"]      = s.get("pix_fmt", "")
                info["r_frame_rate"] = s.get("r_frame_rate", "")
                info["time_base"]    = s.get("time_base", "")
                info["duration"]     = float(s.get("duration") or 0)
            elif s.get("codec_type") == "audio":
                info["has_audio"]   = True
                info["sample_rate"] = int(s.get("sample_rate") or 0)
                info["channels"]    = int(s.get("channels") or 0)
        # format.duration: stream-level duration 0 ise container süresini kullan
        if info["duration"] == 0.0:
            fmt_dur = data.get("format", {}).get("duration")
            if fmt_dur:
                info["duration"] = float(fmt_dur)
    except Exception:
        pass
    return info


async def _ffmpeg_concat(
    list_path: str,
    part_files: list[str],
    out_path: str,
) -> tuple[bool, str]:
    """ffmpeg ile concat uygular.

    Hızlı yol: tüm part'lar birebir aynı video/audio parametresinde → -c copy.
    Yavaş yol: farklı çözünürlük/FPS/audio → filter_complex concat ile normalize.
    """
    import asyncio
    import os

    probes = [await _ffprobe_streams(pf) for pf in part_files]
    ref = probes[0]

    all_same = all(
        p["width"] == ref["width"]
        and p["height"] == ref["height"]
        and p["pix_fmt"] == ref["pix_fmt"]
        and p["r_frame_rate"] == ref["r_frame_rate"]
        and p["time_base"] == ref["time_base"]
        and p["has_audio"] == ref["has_audio"]
        and p["sample_rate"] == ref["sample_rate"]
        and p["channels"] == ref["channels"]
        for p in probes[1:]
    )

    async def _run_proc(*cmd: str) -> tuple[int, str]:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            _, stderr = await proc.communicate()
        except (asyncio.CancelledError, Exception):
            try:
                proc.kill()
                await proc.wait()
            except Exception:
                pass
            raise
        return proc.returncode, (stderr or b"").decode(errors="replace")[-500:]

    if all_same and ref["has_audio"]:
        # Hızlı yol: aynı codec, çözünürlük, FPS, audio — doğrudan kopyala
        rc, err = await _run_proc(
            "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list_path,
            "-c", "copy", "-movflags", "+faststart", out_path,
        )
        if rc == 0:
            return True, ""
        logger.warning(
            "_ffmpeg_concat: -c copy başarısız, filter_complex yoluna geçiliyor | %s", err[-200:]
        )
        if os.path.exists(out_path):
            os.unlink(out_path)

    # Yavaş yol: filter_complex concat — mixed resolution / FPS / eksik audio
    # Hedef çözünürlük: 1. part boyutu (çift sayıya yuvarlanmış; dikey yayını korur)
    tw = ref["width"] + (ref["width"] % 2)
    th = ref["height"] + (ref["height"] % 2)
    n = len(part_files)

    filter_parts: list[str] = []
    for i, probe in enumerate(probes):
        filter_parts.append(
            f"[{i}:v]scale={tw}:{th}:force_original_aspect_ratio=decrease,"
            f"pad={tw}:{th}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v{i}]"
        )
        if probe["has_audio"]:
            filter_parts.append(
                f"[{i}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[a{i}]"
            )
        else:
            # Sessiz part: video süresi kadar anullsrc üret (d=3600 → 1 saatlik donma riski)
            dur = max(probe["duration"], 0.1)
            filter_parts.append(
                f"anullsrc=r=48000:cl=stereo:d={dur:.3f}[a{i}]"
            )

    stream_labels = "".join(f"[v{i}][a{i}]" for i in range(n))
    filter_complex = ";".join(filter_parts) + f";{stream_labels}concat=n={n}:v=1:a=1[vout][aout]"

    cmd: list[str] = ["ffmpeg", "-y"]
    for pf in part_files:
        cmd += ["-i", pf]
    cmd += [
        "-filter_complex", filter_complex,
        "-map", "[vout]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        out_path,
    ]

    rc, err = await _run_proc(*cmd)
    if rc == 0:
        return True, ""
    return False, err


async def _run_concat(stream_id: int) -> None:
    import asyncio
    import os
    import tempfile

    from app.database import AsyncSessionLocal
    from app.config import settings
    from app.services.storage_service import _get_client_for_internal_url
    from sqlalchemy import text

    async with AsyncSessionLocal() as session:
        parts = (await session.execute(text("""
            SELECT id, minio_key, part_number, host_id
            FROM stream_recordings
            WHERE stream_id        = :stream_id
              AND is_concat_result = FALSE
              AND part_number      IS NOT NULL
              AND status           = 'available'
              AND retry_count      < :max_retry
            ORDER BY part_number ASC
        """), {"stream_id": stream_id, "max_retry": _MAX_RETRY})).mappings().all()

    if len(parts) < 2:
        return

    host_id = parts[0]["host_id"]
    # cluster.yaml → minio_endpoint (127.0.0.1:9000 on node1)
    # Tüm part'lar encoder tarafından bu endpoint'e mc cp ile yüklenmektedir.
    minio = _get_client_for_internal_url(settings.minio_endpoint)

    with tempfile.TemporaryDirectory() as tmpdir:
        part_files: list[str] = []

        # Part'ları indir
        for p in parts:
            key = p["minio_key"]
            if not key:
                error = f"part={p['part_number']} minio_key yok"
                logger.warning("_run_concat: stream_id=%s %s", stream_id, error)
                await _mark_retry(stream_id, error)
                return
            local_path = os.path.join(tmpdir, f"part_{p['part_number']}.mp4")
            try:
                await asyncio.to_thread(
                    minio.fget_object, settings.minio_bucket, key, local_path
                )
            except Exception as exc:
                error = f"MinIO indirme hatası part={p['part_number']}: {exc}"
                logger.error("_run_concat: stream_id=%s %s", stream_id, error)
                await _mark_retry(stream_id, error)
                return
            part_files.append(local_path)

        # ffmpeg concat listesi (fast-path için; complex path part_files kullanır)
        list_path = os.path.join(tmpdir, "concat_list.txt")
        with open(list_path, "w") as f:
            for pf in part_files:
                f.write(f"file '{pf}'\n")

        out_path = os.path.join(tmpdir, "concat_output.mp4")
        success, error_msg = await _ffmpeg_concat(list_path, part_files, out_path)
        if not success:
            logger.error("_run_concat: ffmpeg hata stream_id=%s: %s", stream_id, error_msg)
            await _mark_retry(stream_id, f"ffmpeg: {error_msg}")
            return

        # Concat sonucunu aynı MinIO endpoint'ine yükle (orchestrator bypass — agent restart güveni)
        concat_key = f"recordings/{stream_id}/concat.mp4"
        try:
            await asyncio.to_thread(
                minio.fput_object,
                settings.minio_bucket, concat_key, out_path,
                content_type="video/mp4",
            )
        except Exception as exc:
            error = f"MinIO yükleme hatası: {exc}"
            logger.error("_run_concat: stream_id=%s %s", stream_id, error)
            await _mark_retry(stream_id, error)
            return

    # DB: concat sonucu kaydet, part'ları merged_and_purged yap
    async with AsyncSessionLocal() as session:
        part_ids = [p["id"] for p in parts]
        placeholders = ", ".join(f":id_{i}" for i in range(len(part_ids)))
        params = {f"id_{i}": pid for i, pid in enumerate(part_ids)}

        await session.execute(text(f"""
            UPDATE stream_recordings
            SET status = 'merged_and_purged', updated_at = NOW()
            WHERE id IN ({placeholders})
        """), params)

        await session.execute(text("""
            INSERT INTO stream_recordings
                (stream_id, host_id, minio_key, status, is_concat_result, available_at, created_at, updated_at)
            VALUES
                (:stream_id, :host_id, :minio_key, 'available', TRUE, NOW(), NOW(), NOW())
        """), {"stream_id": stream_id, "host_id": host_id, "minio_key": concat_key})

        await session.commit()

    # MinIO'dan part dosyalarını sil — DB commit sonrası, best-effort
    for p in parts:
        key = p["minio_key"]
        if not key:
            continue
        try:
            await asyncio.to_thread(minio.remove_object, settings.minio_bucket, key)
            logger.debug("_run_concat: part silindi | stream_id=%s key=%s", stream_id, key)
        except Exception as exc:
            logger.warning(
                "_run_concat: part silinemedi | stream_id=%s key=%s | %s", stream_id, key, exc
            )

    logger.info("_run_concat: stream_id=%s concat tamamlandı → %s", stream_id, concat_key)
