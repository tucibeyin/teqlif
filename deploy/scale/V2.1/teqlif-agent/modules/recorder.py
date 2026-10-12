"""teqlif-agent — LiveKit subscriber kayıt yöneticisi.

teqlif-livekit veya teqlif-livekit-staging servisi çalışan node'larda
otomatik yüklenir. Her aktif stream için livekit_subscriber.py'yi
subprocess olarak başlatır; WebRTC ile odaya gizli abone olarak girerek
ses/görüntüyü lokal MKV dosyasına kaydeder.

Tetikleme: Redis pub/sub (teqlif:recording:stream_started) → anında başlatma.
Fallback: 60 saniyelik döngü poll'u — event kaçırıldıysa yakalama garantisi.

Bant genişliği: subscriber 127.0.0.1 üzerinden bağlanır — dış trafik yok.
Encoder/transfer: MKV dosyası hazır olunca EncoderManager devralır.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from config import AgentConfig
from db import AgentDB

logger = logging.getLogger("teqlif-agent.recorder")

# livekit_subscriber.py agent dizininin bir üst klasöründe (prod: /opt/teqlif-agent/)
_SUBSCRIBER_SCRIPT = Path(__file__).parent.parent / "livekit_subscriber.py"
_PYTHON            = sys.executable
_PUBSUB_CHANNEL    = "teqlif:recording:stream_started"


class RecordingManager:
    def __init__(self, cfg: AgentConfig, db: AgentDB, service_name: str) -> None:
        self._cfg  = cfg
        self._db   = db
        self._svc  = service_name
        # rec_id → asyncio Process
        self._procs: dict[int, asyncio.subprocess.Process] = {}
        self._initialized    = False
        self._event_queue:   asyncio.Queue[dict] = asyncio.Queue()
        self._listener_task: asyncio.Task | None = None

    async def run(self, is_leader: bool) -> None:
        svc_cfg = self._cfg.recording_config_for(self._svc)
        if not svc_cfg:
            return

        dsn_env = svc_cfg.get("pg_dsn_env", "PG_DSN")
        dsn = os.environ.get(dsn_env, "")
        if not dsn:
            logger.warning("DSN env var tanımsız: %s", dsn_env)
            return

        if not self._initialized:
            await self._recover_orphaned(dsn)
            self._initialized = True
            redis_url = self._event_redis_url(svc_cfg)
            self._listener_task = asyncio.create_task(
                self._pubsub_loop(redis_url),
                name=f"recorder-pubsub-{self._svc}",
            )

        # Listener task çöktüyse yeniden başlat
        if self._listener_task and self._listener_task.done():
            exc = self._listener_task.exception() if not self._listener_task.cancelled() else None
            logger.warning("Pub/sub listener durdu (%s), yeniden başlatılıyor", exc)
            redis_url = self._event_redis_url(svc_cfg)
            self._listener_task = asyncio.create_task(
                self._pubsub_loop(redis_url),
                name=f"recorder-pubsub-{self._svc}",
            )

        # Pub/sub'dan gelen olayları anında işle
        await self._drain_event_queue(dsn, svc_cfg)

        # 60s fallback poll — event kaçırma güvencesi
        await self._sync_recordings(dsn, svc_cfg)
        await self._reap_finished(dsn)

    # ── Redis URL seçimi ──────────────────────────────────────────────────────

    def _event_redis_url(self, svc_cfg: dict) -> str:
        """Pub/sub için doğru Redis URL'sini döner.

        Staging servisi için cluster.yaml'daki redis_url_env env var'ını okur.
        Prod servisi için cfg.redis_url (Core Redis) kullanılır.
        """
        env_key = svc_cfg.get("redis_url_env")
        if env_key:
            url = os.environ.get(env_key, "")
            if url:
                return url
            logger.warning("redis_url_env '%s' boş — cfg.redis_url kullanılıyor", env_key)
        return self._cfg.redis_url

    # ── Redis pub/sub dinleyici ───────────────────────────────────────────────

    async def _pubsub_loop(self, redis_url: str) -> None:
        """Redis pub/sub kanalını dinler, gelen olayları kuyruğa ekler."""
        import aioredis

        while True:
            r: aioredis.Redis | None = None
            try:
                r = aioredis.from_url(redis_url, decode_responses=True)
                pubsub = r.pubsub()
                await pubsub.subscribe(_PUBSUB_CHANNEL)
                logger.info(
                    "Pub/sub dinleniyor | kanal=%s url=%s",
                    _PUBSUB_CHANNEL,
                    redis_url.split("@")[-1] if "@" in redis_url else redis_url,
                )
                async for message in pubsub.listen():
                    if message["type"] != "message":
                        continue
                    try:
                        data = json.loads(message["data"])
                        await self._event_queue.put(data)
                        logger.info(
                            "Kayıt eventi alındı | stream_id=%s room=%s",
                            data.get("stream_id"), data.get("room_name"),
                        )
                    except Exception as exc:
                        logger.warning("Pub/sub mesaj parse hatası: %s", exc)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                logger.warning("Pub/sub bağlantı hatası, 5s sonra yeniden: %s", exc)
                await asyncio.sleep(5)
            finally:
                if r is not None:
                    try:
                        await r.aclose()
                    except Exception:
                        pass

    # ── Pub/sub kuyruğunu boşalt ──────────────────────────────────────────────

    async def _drain_event_queue(self, dsn: str, svc_cfg: dict) -> None:
        """Kuyruktaki olayları işler — her stream için anında kayıt başlatır."""
        while not self._event_queue.empty():
            try:
                data = self._event_queue.get_nowait()
            except asyncio.QueueEmpty:
                break

            stream_id = data.get("stream_id")
            room_name = data.get("room_name")
            host_id   = data.get("host_id")

            if not all([stream_id, room_name, host_id]):
                logger.warning("Geçersiz kayıt eventi atlandı: %s", data)
                continue

            # Zaten kayıt varsa atla
            try:
                import asyncpg
                conn = await asyncpg.connect(dsn=dsn)
                exists = await conn.fetchval(
                    """SELECT 1 FROM stream_recordings
                       WHERE stream_id = $1
                         AND recording_node = $2
                         AND status IN ('recording','encoding','encoded','transferring','available')
                    """,
                    stream_id, self._cfg.node_id,
                )
                await conn.close()
            except Exception as exc:
                logger.error("Event queue DB kontrol hatası: %s", exc)
                continue

            if exists:
                logger.debug("Kayıt zaten mevcut, atlanıyor | stream_id=%d", stream_id)
                continue

            logger.info(
                "Pub/sub → kayıt başlatılıyor | stream_id=%d room=%s",
                stream_id, room_name,
            )
            await self._start_recording(dsn, svc_cfg, stream_id, room_name, host_id)

    # ── Agent restart: orphan kurtarma ───────────────────────────────────────

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
                logger.warning("Orphaned kayıt fail edildi: rec_id=%d", row["id"])
            await conn.close()
        except Exception as exc:
            logger.error("_recover_orphaned hatası: %s", exc)

    # ── Yeni kayıt başlatma ───────────────────────────────────────────────────

    async def _sync_recordings(self, dsn: str, svc_cfg: dict) -> None:
        """Canlı, bu node'da kaydı olmayan stream'ler için subscriber başlatır.

        Pub/sub event'i kaçırıldıysa bu poll yakalama garantisi sağlar.
        """
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
        api_key    = os.environ.get("LIVEKIT_API_KEY", "")
        api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
        ws_url     = svc_cfg.get("livekit_ws_url") or "ws://127.0.0.1:7880"

        if not api_key or not api_secret:
            logger.warning("LIVEKIT_API_KEY/SECRET tanımsız — kayıt başlatılamıyor: stream_id=%d", stream_id)
            return

        raw_dir = Path(svc_cfg["raw_dir"])
        raw_dir.mkdir(parents=True, exist_ok=True)

        ts       = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        raw_path = raw_dir / f"{stream_id}_{ts}.mkv"

        cmd = [
            _PYTHON, str(_SUBSCRIBER_SCRIPT),
            "--room",       room_name,
            "--ws-url",     ws_url,
            "--api-key",    api_key,
            "--api-secret", api_secret,
            "--output",     str(raw_path),
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            import asyncpg
            conn = await asyncpg.connect(dsn=dsn)
            row  = await conn.fetchrow(
                """INSERT INTO stream_recordings
                       (stream_id, host_id, status, recording_node, raw_path,
                        recording_started_at, updated_at)
                   VALUES ($1, $2, 'recording', $3, $4, NOW(), NOW())
                   RETURNING id""",
                stream_id, host_id, self._cfg.node_id, str(raw_path),
            )
            await conn.close()
            rec_id = row["id"]
            self._procs[rec_id] = proc
            logger.info(
                "Kayıt başladı | stream_id=%d rec_id=%d ws=%s path=%s",
                stream_id, rec_id, ws_url, raw_path.name,
            )
        except Exception as exc:
            logger.error("Kayıt başlatma hatası | stream_id=%d | %s", stream_id, exc)

    # ── Biten process'leri topla ──────────────────────────────────────────────

    async def _reap_finished(self, dsn: str) -> None:
        """Biten subscriber process'lerini toplar ve encoding statüsüne geçirir."""
        finished = [rid for rid, p in self._procs.items() if p.returncode is not None]
        for rec_id in finished:
            proc = self._procs.pop(rec_id)
            _, stderr_b = await proc.communicate()
            logger.info("Subscriber bitti | rec_id=%d returncode=%d", rec_id, proc.returncode)
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
                           SET status='encoding', raw_size_bytes=$1,
                               encoding_started_at=NOW(), updated_at=NOW()
                           WHERE id=$2""",
                        raw_size, rec_id,
                    )
                    logger.info(
                        "Kayıt encoding'e geçti | rec_id=%d raw_size=%.1fMB",
                        rec_id, raw_size / 1_048_576,
                    )
                else:
                    err = (stderr_b or b"").decode(errors="replace")[-400:].strip()
                    err_short = "\n".join(err.splitlines()[-3:])[:200]
                    await conn.execute(
                        "UPDATE stream_recordings SET status='failed', error_message=$1, updated_at=NOW() WHERE id=$2",
                        err_short or f"returncode={proc.returncode}", rec_id,
                    )
                    logger.error("Subscriber hata | rec_id=%d | %s", rec_id, err_short)
                await conn.close()
            except Exception as exc:
                logger.error("_reap_finished DB hatası | rec_id=%d | %s", rec_id, exc)
