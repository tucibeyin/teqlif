"""teqlif-agent — Kayıt encode ve MinIO transfer yöneticisi.

teqlif-livekit (veya staging) çalışan node'larda otomatik yüklenir.

İş akışı:
  1. status='encoding' → FFmpeg ile H.264/AAC encode, raw sil, 'encoded'
  2. status='encoded'  → Transfer penceresi kontrolü → mc cp → 'available'

Transfer penceresi (UTC):
  free_gb ≥  15GB : 03:00–08:00 (normal)
  free_gb  10–15GB : 02:00–08:00 (erken tetik)
  free_gb < 10GB  : her an (acil)
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.encoder")

_ENCODE_CRF      = 23
_ENCODE_PRESET   = "veryfast"
_MAX_PARALLEL    = 1   # aynı anda en fazla 1 encode (CPU koruma)


class EncoderManager:
    def __init__(self, cfg: AgentConfig, db: AgentDB, service_name: str) -> None:
        self._cfg         = cfg
        self._db          = db
        self._svc         = service_name
        self._encoding:   set[int] = set()    # aktif encode job'ları
        self._transferring: set[int] = set()  # aktif transfer job'ları
        self._mc_ready    = False

    async def run(self, is_leader: bool) -> None:
        svc_cfg = self._cfg.recording_config_for(self._svc)
        if not svc_cfg:
            return

        dsn = os.environ.get("PG_DSN", "")
        if not dsn:
            return

        rec_cfg = self._cfg.cluster_recording

        # mc alias'ını ilk çalışmada kur
        if not self._mc_ready:
            await self._setup_mc_alias(svc_cfg)
            self._mc_ready = True

        await self._run_encodes(dsn, svc_cfg)
        await self._run_transfers(dsn, svc_cfg, rec_cfg)

    # ── Encode ───────────────────────────────────────────────────────────────

    async def _run_encodes(self, dsn: str, svc_cfg: dict) -> None:
        if len(self._encoding) >= _MAX_PARALLEL:
            return
        try:
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            rows = await conn.fetch(
                """SELECT id, raw_path FROM stream_recordings
                   WHERE status = 'encoding' AND recording_node = $1
                   ORDER BY encoding_started_at ASC
                   LIMIT $2""",
                self._cfg.node_id, _MAX_PARALLEL - len(self._encoding),
            )
            await conn.close()
        except Exception as exc:
            logger.error("Encode sorgu hatası: %s", exc)
            return

        for row in rows:
            if row["id"] in self._encoding:
                continue
            self._encoding.add(row["id"])
            asyncio.create_task(
                self._encode_one(dsn, svc_cfg, row["id"], row["raw_path"]),
                name=f"encode-{row['id']}",
            )

    async def _encode_one(self, dsn: str, svc_cfg: dict, rec_id: int, raw_path: str) -> None:
        try:
            raw  = Path(raw_path)
            enc_dir = Path(svc_cfg["encoded_dir"])
            enc_dir.mkdir(parents=True, exist_ok=True)
            enc_path = enc_dir / (raw.stem + ".mp4")

            cmd = [
                "ffmpeg", "-hide_banner", "-loglevel", "warning",
                "-i", str(raw),
                "-vf", "scale=-2:720",
                "-c:v", "libx264", "-crf", str(_ENCODE_CRF), "-preset", _ENCODE_PRESET,
                "-c:a", "aac", "-b:a", "128k",
                "-movflags", "+faststart",
                "-y", str(enc_path),
            ]
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr_b = await proc.communicate()

            if proc.returncode != 0:
                err = (stderr_b or b"").decode(errors="replace")[-200:].strip()
                await _pg_exec(dsn,
                    "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                    err or f"ffmpeg encode returncode={proc.returncode}", rec_id)
                logger.error("Encode hata | rec_id=%d | %s", rec_id, err)
                return

            enc_size = enc_path.stat().st_size
            duration_secs = await _probe_duration(enc_path)

            # Raw sil
            try:
                raw.unlink(missing_ok=True)
            except Exception as exc:
                logger.warning("Raw silme hatası | rec_id=%d | %s", rec_id, exc)

            await _pg_exec(dsn,
                """UPDATE stream_recordings
                   SET status='encoded', encoded_path=$1, encoded_size_bytes=$2,
                       duration_secs=$3, raw_path=NULL, encoded_at=NOW(), updated_at=NOW()
                   WHERE id=$4""",
                str(enc_path), enc_size, duration_secs, rec_id)
            logger.info("Encode tamamlandı | rec_id=%d size=%.1fMB", rec_id, enc_size / 1_048_576)

        except Exception as exc:
            logger.error("_encode_one hata | rec_id=%d | %s", rec_id, exc)
            await _pg_exec(dsn,
                "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                str(exc)[:200], rec_id)
        finally:
            self._encoding.discard(rec_id)

    # ── Transfer ──────────────────────────────────────────────────────────────

    async def _run_transfers(self, dsn: str, svc_cfg: dict, rec_cfg: dict) -> None:
        enc_dir = Path(svc_cfg.get("encoded_dir", "/var/recordings/encoded"))
        if not _can_transfer_now(rec_cfg, enc_dir):
            return

        try:
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            rows = await conn.fetch(
                """SELECT id, stream_id, encoded_path FROM stream_recordings
                   WHERE status = 'encoded' AND recording_node = $1
                   ORDER BY encoded_at ASC""",
                self._cfg.node_id,
            )
            await conn.close()
        except Exception as exc:
            logger.error("Transfer sorgu hatası: %s", exc)
            return

        for row in rows:
            if row["id"] in self._transferring:
                continue
            self._transferring.add(row["id"])
            asyncio.create_task(
                self._transfer_one(dsn, svc_cfg, rec_cfg, row["id"], row["stream_id"], row["encoded_path"]),
                name=f"transfer-{row['id']}",
            )

    async def _transfer_one(
        self, dsn: str, svc_cfg: dict, rec_cfg: dict,
        rec_id: int, stream_id: int, encoded_path: str,
    ) -> None:
        try:
            enc = Path(encoded_path)
            if not enc.exists():
                logger.warning("Encoded dosya bulunamadı | rec_id=%d path=%s", rec_id, encoded_path)
                await _pg_exec(dsn,
                    "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                    "encoded file missing before transfer", rec_id)
                return

            bucket     = svc_cfg["minio_bucket"]
            alias      = svc_cfg["minio_alias"]
            minio_key  = f"recordings/{stream_id}/{enc.name}"
            minio_dest = f"{alias}/{bucket}/{minio_key}"

            # Mark transferring
            await _pg_exec(dsn,
                "UPDATE stream_recordings SET status='transferring', updated_at=NOW() WHERE id=$1", rec_id)

            free_gb      = _free_gb(enc.parent)
            emergency_gb = float(rec_cfg.get("disk_emergency_gb", 10))
            mc_cmd = ["mc", "cp"]
            if free_gb < emergency_gb:
                mc_cmd += ["--limit-upload", "30M"]  # acil: LiveKit bant genişliğini koru
            mc_cmd += [str(enc), minio_dest]

            proc = await asyncio.create_subprocess_exec(
                *mc_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr_b = await proc.communicate()

            if proc.returncode != 0:
                err = (stderr_b or b"").decode(errors="replace")[-200:].strip()
                await _pg_exec(dsn,
                    "UPDATE stream_recordings SET status='encoded', updated_at=NOW() WHERE id=$1", rec_id)
                logger.error("mc cp hata | rec_id=%d | %s", rec_id, err)
                await tg.send(
                    self._cfg.telegram_bot_token, self._cfg.telegram_chat_id,
                    f"⚠️ <b>{self._cfg.node_id}</b> — Transfer hata: rec_id={rec_id}\n<code>{err[:120]}</code>",
                )
                return

            # Encoded lokal dosyayı sil
            try:
                enc.unlink(missing_ok=True)
            except Exception as exc:
                logger.warning("Encoded sil hatası | rec_id=%d | %s", rec_id, exc)

            access_hours = int(rec_cfg.get("user_access_hours", 24))
            now_utc      = datetime.now(timezone.utc)
            available_at = now_utc
            expires_at   = now_utc + timedelta(hours=access_hours)

            await _pg_exec(dsn,
                """UPDATE stream_recordings
                   SET status='available', minio_key=$1, encoded_path=NULL,
                       transferred_at=NOW(), available_at=$2, expires_at=$3, updated_at=NOW()
                   WHERE id=$4""",
                minio_key, available_at, expires_at, rec_id)
            logger.info(
                "Transfer tamam | rec_id=%d minio=%s expires=%s",
                rec_id, minio_key, expires_at.strftime("%Y-%m-%d %H:%M UTC"),
            )

        except Exception as exc:
            logger.error("_transfer_one hata | rec_id=%d | %s", rec_id, exc)
            await _pg_exec(dsn,
                "UPDATE stream_recordings SET status='encoded', updated_at=NOW() WHERE id=$1", rec_id)
        finally:
            self._transferring.discard(rec_id)

    # ── mc alias kurulumu ─────────────────────────────────────────────────────

    async def _setup_mc_alias(self, svc_cfg: dict) -> None:
        alias      = svc_cfg.get("minio_alias", "")
        minio_host = svc_cfg.get("minio_host", "")
        access_key = os.environ.get("MINIO_ACCESS_KEY", "")
        secret_key = os.environ.get("MINIO_SECRET_KEY", "")
        if not all([alias, minio_host, access_key, secret_key]):
            logger.debug("mc alias kurulumu atlandı — eksik config veya env")
            return
        try:
            proc = await asyncio.create_subprocess_exec(
                "mc", "alias", "set", alias,
                f"http://{minio_host}", access_key, secret_key,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            if proc.returncode == 0:
                logger.info("mc alias kuruldu: %s → %s", alias, minio_host)
        except Exception as exc:
            logger.warning("mc alias kurma hatası: %s", exc)


# ── Yardımcılar ───────────────────────────────────────────────────────────────

def _free_gb(path: Path) -> float:
    try:
        usage = shutil.disk_usage(str(path) if path.exists() else "/")
        return usage.free / 1_073_741_824
    except Exception:
        return 999.0  # bilinmiyorsa serbest say


def _can_transfer_now(rec_cfg: dict, enc_dir: Path) -> bool:
    """Transfer penceresi ve disk guard kontrolü."""
    free_gb      = _free_gb(enc_dir)
    emergency_gb = float(rec_cfg.get("disk_emergency_gb", 10))
    warn_gb      = float(rec_cfg.get("disk_warn_gb", 15))
    start_utc    = int(rec_cfg.get("transfer_window_start_utc", 2))
    end_utc      = int(rec_cfg.get("transfer_window_end_utc", 8))

    if free_gb < emergency_gb:
        return True  # acil: pencere yok

    now_h = datetime.now(timezone.utc).hour
    # disk warn: start_utc kullan; normal: start_utc + 1 saat
    effective_start = start_utc if free_gb < warn_gb else start_utc + 1
    return effective_start <= now_h < end_utc


async def _probe_duration(path: Path) -> int | None:
    """ffprobe ile video süresini saniye cinsinden döner; hata varsa None."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", str(path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout_b, _ = await proc.communicate()
        if proc.returncode != 0 or not stdout_b:
            return None
        data = json.loads(stdout_b)
        duration_str = data.get("format", {}).get("duration")
        if duration_str:
            return int(float(duration_str))
    except Exception as exc:
        logger.warning("ffprobe hata | path=%s | %s", path, exc)
    return None


async def _pg_exec(dsn: str, sql: str, *args) -> None:
    import asyncpg
    conn = await asyncpg.connect(dsn=dsn)
    await conn.execute(sql, *args)
    await conn.close()
