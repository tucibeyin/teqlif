"""teqlif-agent — WHEP kayıt yöneticisi.

teqlif-livekit veya teqlif-livekit-staging servisi çalışan node'larda
otomatik yüklenir. Her aktif stream için FFmpeg WHEP bağlantısı açar
ve ham video dosyasına (MKV) kaydeder.

Lider'e bağlı değil — her recording node kendi stream'lerini kaydeder.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from config import AgentConfig
from db import AgentDB

logger = logging.getLogger("teqlif-agent.recorder")

_LIVEKIT_PORT = 7880


class RecordingManager:
    def __init__(self, cfg: AgentConfig, db: AgentDB, service_name: str) -> None:
        self._cfg   = cfg
        self._db    = db
        self._svc   = service_name
        # stream_recording_id → asyncio Process
        self._procs: dict[int, asyncio.subprocess.Process] = {}
        self._initialized = False

    async def run(self, is_leader: bool) -> None:
        svc_cfg = self._cfg.recording_config_for(self._svc)
        if not svc_cfg:
            return

        dsn = os.environ.get("PG_DSN", "")
        if not dsn:
            return

        # Agent restart sonrası orphaned kayıtları bir kez temizle
        if not self._initialized:
            await self._recover_orphaned(dsn)
            self._initialized = True

        await self._sync_recordings(dsn, svc_cfg)
        await self._reap_finished(dsn)

    async def _recover_orphaned(self, dsn: str) -> None:
        """Agent yeniden başladığında bu node'a ait 'recording' kayıtları fail'e çeker."""
        try:
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            rows = await conn.fetch(
                "SELECT id FROM stream_recordings WHERE status = 'recording' AND recording_node = $1",
                self._cfg.node_id,
            )
            for row in rows:
                await conn.execute(
                    "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                    "agent restart: kayıt kesildi", row["id"],
                )
                logger.warning("Orphaned kayıt fail edildi: id=%d", row["id"])
            await conn.close()
        except Exception as exc:
            logger.error("Orphaned recovery hatası: %s", exc)

    async def _sync_recordings(self, dsn: str, svc_cfg: dict) -> None:
        """Canlı, bu node'da kaydı olmayan stream'ler için kayıt başlatır. Tüm yayınlar kaydedilir."""
        try:
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            streams = await conn.fetch("""
                SELECT ls.id, ls.room_name, ls.host_id
                FROM live_streams ls
                WHERE ls.status = 'live'
                  AND NOT EXISTS (
                      SELECT 1 FROM stream_recordings sr
                      WHERE sr.stream_id = ls.id
                        AND sr.recording_node = $1
                        AND sr.status IN ('recording','encoding','encoded','transferring','available')
                  )
            """, self._cfg.node_id)
            await conn.close()
        except Exception as exc:
            logger.error("Stream sorgu hatası: %s", exc)
            return

        for s in streams:
            await self._start_recording(dsn, svc_cfg, s["id"], s["room_name"], s["host_id"])

    async def _start_recording(
        self, dsn: str, svc_cfg: dict,
        stream_id: int, room_name: str, host_id: int,
    ) -> None:
        """FFmpeg'i başlatır ve DB'ye stream_recordings kaydı ekler."""
        raw_dir = Path(svc_cfg["raw_dir"])
        raw_dir.mkdir(parents=True, exist_ok=True)

        ts       = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        raw_path = raw_dir / f"{stream_id}_{ts}.mkv"

        token = _make_livekit_token(room_name)
        if not token:
            logger.warning("LiveKit token üretilemiyor — kayıt başlatılamıyor: stream_id=%d", stream_id)
            return

        whep_url = f"http://127.0.0.1:{_LIVEKIT_PORT}/rooms/{room_name}/whep"
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "warning",
            "-headers", f"Authorization: Bearer {token}",
            "-i", whep_url,
            "-c", "copy", "-f", "matroska", str(raw_path),
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.PIPE,
            )
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            row  = await conn.fetchrow(
                """INSERT INTO stream_recordings
                       (stream_id, host_id, status, recording_node, raw_path, recording_started_at, updated_at)
                   VALUES ($1, $2, 'recording', $3, $4, NOW(), NOW())
                   RETURNING id""",
                stream_id, host_id, self._cfg.node_id, str(raw_path),
            )
            await conn.close()
            rec_id = row["id"]
            self._procs[rec_id] = proc
            logger.info("Kayıt başladı | stream_id=%d rec_id=%d path=%s", stream_id, rec_id, raw_path.name)
        except Exception as exc:
            logger.error("Kayıt başlatma hatası | stream_id=%d | %s", stream_id, exc)

    async def _reap_finished(self, dsn: str) -> None:
        """Biten FFmpeg process'lerini toplar ve encoding statüsüne geçirir."""
        finished = [rid for rid, p in self._procs.items() if p.returncode is not None]
        for rec_id in finished:
            proc = self._procs.pop(rec_id)
            logger.info("FFmpeg bitti | rec_id=%d returncode=%d", rec_id, proc.returncode)
            try:
                import asyncpg
                conn = await asyncpg.connect(dsn=dsn)
                if proc.returncode == 0:
                    row = await conn.fetchrow(
                        "SELECT raw_path FROM stream_recordings WHERE id = $1", rec_id
                    )
                    raw_size = 0
                    if row and row["raw_path"]:
                        try:
                            raw_size = Path(row["raw_path"]).stat().st_size
                        except Exception:
                            pass
                    await conn.execute(
                        """UPDATE stream_recordings
                           SET status='encoding', raw_size_bytes=$1, encoding_started_at=NOW(), updated_at=NOW()
                           WHERE id=$2""",
                        raw_size, rec_id,
                    )
                    logger.info("Kayıt encoding'e geçti | rec_id=%d raw_size=%.1fMB",
                                rec_id, raw_size / 1_048_576)
                else:
                    _, stderr_b = await proc.communicate()
                    err = (stderr_b or b"").decode(errors="replace")[-200:].strip()
                    await conn.execute(
                        "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                        err or f"ffmpeg returncode={proc.returncode}", rec_id,
                    )
                    logger.error("FFmpeg hata | rec_id=%d | %s", rec_id, err)
                await conn.close()
            except Exception as exc:
                logger.error("reap_finished DB hatası | rec_id=%d | %s", rec_id, exc)


def _make_livekit_token(room_name: str) -> str | None:
    """LIVEKIT_API_KEY + LIVEKIT_API_SECRET kullanarak WHEP için JWT üretir."""
    api_key    = os.environ.get("LIVEKIT_API_KEY", "")
    api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
    if not api_key or not api_secret:
        logger.debug("LIVEKIT_API_KEY / LIVEKIT_API_SECRET tanımsız")
        return None
    try:
        now = int(time.time())

        def _b64(data: bytes) -> bytes:
            return base64.urlsafe_b64encode(data).rstrip(b"=")

        header  = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
        payload = _b64(json.dumps({
            "iss": api_key,
            "sub": f"agent-rec-{room_name}",
            "iat": now,
            "exp": now + 86400,
            "video": {"room": room_name, "roomJoin": True, "hidden": True, "recorder": True},
        }, separators=(",", ":")).encode())

        signing_input = header + b"." + payload
        sig = _b64(hmac.new(api_secret.encode(), signing_input, hashlib.sha256).digest())
        return (signing_input + b"." + sig).decode()
    except Exception as exc:
        logger.error("Token üretme hatası: %s", exc)
        return None
