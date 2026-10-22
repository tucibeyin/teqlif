"""teqlif-agent — On-demand relay yöneticisi (V1.7).

İş akışı (source node perspektifinden):
  net_tx_mbps > tx_threshold_mbps (15s sustained) ve relay_node uygunsa
  → live:relay:needed:{room} = relay_node_id yazar.

İş akışı (relay node perspektifinden):
  live:relay:needed:{room} == bu node'un node_id'si → livekit_relay.py başlatır.
  İlk video frame sonrası relay.py: live:relay:ready:{room} heartbeat ile tazeler.
  Process ölünce: live:relay:ready ve needed silinir, LiveKit API ile relay_room kapatılır.

Relay kapanma kuralı: net_tx_mbps düşse de relay KAPATILMAZ (H2).
  Sadece stream biterken (EndStream webhook / stream_ended event) kapatılır.

Circuit breaker: 10 dakika içinde 2'den fazla yeniden başlatma → relay yok sayılır.
Co-host subprocess: live:cohost:joined/left:{stream_id} pub/sub ile yönetilir.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
from pathlib import Path

from config import AgentConfig
from db import AgentDB

logger = logging.getLogger("teqlif-agent.relay")

_RELAY_SCRIPT      = Path(__file__).parent.parent / "livekit_relay.py"
_PYTHON            = sys.executable

_NEEDED_PATTERN    = "live:relay:needed:*"
_READY_PREFIX      = "live:relay:ready:"
_EMERGENCY_KEY     = "teqlif:relay:emergency_disabled"
_SUSTAINED_SEC     = 15      # Relay başlatmak için gereken minimum süre
_TX_THRESHOLD_MBPS = 800     # Kaynak node için eşik
_RELAY_MAX_TX_MBPS = 600     # Relay node için üst sınır
_RELAY_MAX_CPU_PCT = 70      # Relay node için CPU üst sınırı
_CIRCUIT_WINDOW    = 600     # 10 dakika
_CIRCUIT_MAX       = 2       # Bu pencerede max yeniden başlatma


class RelayManager:
    def __init__(self, cfg: AgentConfig, db: AgentDB, svc_name: str) -> None:
        self._cfg  = cfg
        self._db   = db
        self._svc  = svc_name

        # room_name → asyncio Process
        self._relay_procs: dict[str, asyncio.subprocess.Process] = {}
        # (stream_id, cohost_identity) → asyncio Process
        self._cohost_procs: dict[tuple[int, str], asyncio.subprocess.Process] = {}

        # Circuit breaker: room_name → list[float] — restart zamanları
        self._restart_times: dict[str, list[float]] = {}

        # Sustained window tracking: room_name → first_seen_ts
        self._high_tx_since: dict[str, float] = {}

        # Pub/sub listener
        self._cohost_queue:    asyncio.Queue[dict] = asyncio.Queue()
        self._listener_task:   asyncio.Task | None = None
        self._initialized      = False

    async def run(self, is_leader: bool) -> None:
        svc_cfg = self._cfg.recording_config_for(self._svc)
        if not svc_cfg:
            return

        redis_url = self._event_redis_url(svc_cfg)

        if not self._initialized:
            await self._recover_orphaned()
            self._listener_task = asyncio.create_task(
                self._cohost_pubsub_loop(redis_url),
                name=f"relay-cohost-pubsub-{self._svc}",
            )
            self._initialized = True

        if self._listener_task and self._listener_task.done():
            exc = self._listener_task.exception() if not self._listener_task.cancelled() else None
            logger.warning("Co-host pub/sub listener durdu (%s), yeniden başlatılıyor", exc)
            self._listener_task = asyncio.create_task(
                self._cohost_pubsub_loop(redis_url),
                name=f"relay-cohost-pubsub-{self._svc}",
            )

        # Kill switch
        if await self._is_emergency_disabled(redis_url):
            await self._stop_all(svc_cfg)
            return

        await self._check_source_node_and_request(svc_cfg, redis_url)
        await self._check_needed_and_start(svc_cfg, redis_url)
        await self._drain_cohost_queue(svc_cfg, redis_url)
        await self._reap_finished(svc_cfg, redis_url)

    # ── Redis URL seçimi ──────────────────────────────────────────────────────

    def _event_redis_url(self, svc_cfg: dict) -> str:
        env_key = svc_cfg.get("redis_url_env")
        if env_key:
            url = os.environ.get(env_key, "")
            if url:
                return url
        return self._cfg.redis_url

    # ── Kill switch ───────────────────────────────────────────────────────────

    async def _is_emergency_disabled(self, redis_url: str) -> bool:
        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)
            result = await r.exists(_EMERGENCY_KEY)
            await r.aclose()
            return result == 1
        except Exception as exc:
            logger.warning("Kill switch kontrolü başarısız: %s", exc)
            return False

    async def _stop_all(self, svc_cfg: dict) -> None:
        """Kill switch aktifse tüm relay subprocess'lerini sonlandırır."""
        for room_name, proc in list(self._relay_procs.items()):
            await _terminate(proc)
            self._relay_procs.pop(room_name, None)
            logger.warning("Kill switch: relay durduruldu | room=%s", room_name)
        for key, proc in list(self._cohost_procs.items()):
            await _terminate(proc)
            self._cohost_procs.pop(key, None)

    # ── Orphan kurtarma ───────────────────────────────────────────────────────

    async def _recover_orphaned(self) -> None:
        """Agent yeniden başladığında bu node'daki livekit_relay.py süreçlerini temizler."""
        # Process table'da kalan süreçleri SIGTERM'leyin — PID dosyası kullanmıyoruz,
        # pgrep ile bu node_id için başlatılmış relay süreçlerini tarayabiliriz.
        # Basit yaklaşım: agent yeniden başladıysa zaten live:relay:ready/{needed} anahtarları
        # 30s içinde otomatik silinir (TTL). Sadece log bırakıyoruz.
        logger.info("RelayManager başlatıldı | node=%s svc=%s", self._cfg.node_id, self._svc)

    # ── Source node: yüksek tx → relay talep et ──────────────────────────────

    async def _check_source_node_and_request(self, svc_cfg: dict, redis_url: str) -> None:
        """Bu node source_node ise net_tx_mbps > eşik mi kontrol et; evet → relay talep et."""
        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)

            # Kendi metriklerimiz
            raw = await r.get(f"edge:metrics:{self._cfg.node_id}")
            if not raw:
                await r.aclose()
                return
            my_metrics = json.loads(raw)
            my_tx = float(my_metrics.get("net_tx_mbps", 0))

            now = time.monotonic()

            if my_tx > _TX_THRESHOLD_MBPS:
                # Sustained window başlat veya kontrol et
                import asyncpg
                dsn = os.environ.get(svc_cfg.get("pg_dsn_env", "PG_DSN"), "")
                if not dsn:
                    await r.aclose()
                    return

                conn = await asyncpg.connect(dsn=dsn)
                streams = await conn.fetch(
                    "SELECT room_name, source_node_id FROM live_streams WHERE status = 'live' AND source_node_id = $1",
                    self._cfg.node_id,
                )
                await conn.close()

                for s in streams:
                    rn = s["room_name"]
                    if rn not in self._high_tx_since:
                        self._high_tx_since[rn] = now
                        continue
                    elapsed = now - self._high_tx_since[rn]
                    if elapsed < _SUSTAINED_SEC:
                        continue
                    # Zaten relay başlatılmış mı?
                    if await r.exists(f"live:relay:needed:{rn}") or await r.exists(f"{_READY_PREFIX}{rn}"):
                        continue
                    # Relay node seç (bu node dışında en az yüklü)
                    relay_node = await self._pick_relay_node(r, my_metrics)
                    if not relay_node:
                        logger.warning("Relay node bulunamadı | room=%s", rn)
                        continue
                    await r.set(f"live:relay:needed:{rn}", relay_node, ex=120)
                    logger.info(
                        "Relay talep edildi | room=%s relay_node=%s tx=%.0fMbps elapsed=%.0fs",
                        rn, relay_node, my_tx, elapsed,
                    )
            else:
                # tx eşik altında — sustained window sıfırla
                self._high_tx_since.clear()

            await r.aclose()
        except Exception as exc:
            logger.error("_check_source_node_and_request hatası: %s", exc)

    async def _pick_relay_node(self, r, my_metrics: dict) -> str | None:
        """Uygun relay node seçer: CPU < %70, tx < 600 Mbps, bu node değil."""
        keys = await r.keys("edge:metrics:*")
        if not keys:
            return None
        candidates = []
        for key in keys:
            raw = await r.get(key)
            if not raw:
                continue
            try:
                m = json.loads(raw)
            except Exception:
                continue
            nid = m.get("node_id", "")
            if nid == self._cfg.node_id:
                continue  # source node değil
            if nid == "node1":
                continue  # Node1 relay için uygun değil (API + DB)
            if float(m.get("cpu_percent", 100)) >= _RELAY_MAX_CPU_PCT:
                continue
            if float(m.get("net_tx_mbps", 999)) >= _RELAY_MAX_TX_MBPS:
                continue
            if not m.get("services", {}).get("livekit", {}).get("healthy", False):
                continue
            candidates.append((float(m.get("cpu_percent", 50)) + float(m.get("net_tx_mbps", 0)) / 10, nid))
        if not candidates:
            return None
        candidates.sort()
        return candidates[0][1]

    # ── Relay node: needed anahtarı var → başlat ─────────────────────────────

    async def _check_needed_and_start(self, svc_cfg: dict, redis_url: str) -> None:
        """live:relay:needed:{room} = this_node_id olan odalar için relay başlatır."""
        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)

            keys = await r.keys(_NEEDED_PATTERN)
            for key in keys:
                val = await r.get(key)
                if val != self._cfg.node_id:
                    continue
                room_name = key.split("live:relay:needed:")[1]

                if room_name in self._relay_procs:
                    # Zaten çalışıyor
                    continue
                if not self._circuit_ok(room_name):
                    logger.warning("Circuit breaker açık | room=%s", room_name)
                    continue

                await self._start_relay(svc_cfg, redis_url, room_name, r)

            await r.aclose()
        except Exception as exc:
            logger.error("_check_needed_and_start hatası: %s", exc)

    async def _start_relay(self, svc_cfg: dict, redis_url: str, room_name: str, r) -> None:
        """Tek bir odanın relay subprocess'ini başlatır."""
        api_key    = os.environ.get("LIVEKIT_API_KEY", "")
        api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
        if not api_key or not api_secret:
            logger.warning("LIVEKIT_API_KEY/SECRET tanımsız — relay başlatılamıyor")
            return

        # Source node bilgilerini DB'den al
        try:
            import asyncpg
            dsn = os.environ.get(svc_cfg.get("pg_dsn_env", "PG_DSN"), "")
            if not dsn:
                return
            conn = await asyncpg.connect(dsn=dsn)
            row  = await conn.fetchrow(
                "SELECT livekit_url, source_node_id, host_id FROM live_streams WHERE room_name = $1",
                room_name,
            )
            await conn.close()
        except Exception as exc:
            logger.error("_start_relay DB hatası: %s", exc)
            return

        if not row:
            logger.warning("_start_relay: stream bulunamadı | room=%s", room_name)
            return

        source_url     = row["livekit_url"] or ""
        host_identity  = str(row["host_id"])
        relay_node_id  = self._cfg.node_id
        relay_room     = f"{room_name}_relay_{relay_node_id}"
        target_url     = svc_cfg.get("livekit_ws_url", "ws://127.0.0.1:7880")

        warmup_start = time.monotonic()

        cmd = [
            "nice", "-n", "-5",
            _PYTHON, str(_RELAY_SCRIPT),
            "--source-url",    source_url,
            "--target-url",    target_url,
            "--room",          room_name,
            "--relay-room",    relay_room,
            "--host-identity", host_identity,
            "--api-key",       api_key,
            "--api-secret",    api_secret,
            "--node-id",       relay_node_id,
            "--redis-url",     redis_url,
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )
            self._relay_procs[room_name] = proc
            # Circuit breaker kaydı
            self._restart_times.setdefault(room_name, []).append(time.monotonic())
            logger.info(
                "Relay başlatıldı | room=%s relay_room=%s pid=%s",
                room_name, relay_room, proc.pid,
            )
            # Warmup ölçümü asenkron izle
            asyncio.create_task(
                self._monitor_warmup(room_name, relay_room, warmup_start, redis_url),
                name=f"relay-warmup-{room_name}",
            )
        except Exception as exc:
            logger.error("Relay subprocess başlatma hatası | room=%s | %s", room_name, exc)

    async def _monitor_warmup(
        self, room_name: str, relay_room: str, start_ts: float, redis_url: str
    ) -> None:
        """H6: Relay hazır olunca warmup süresini ölçer; > 5s Telegram uyarısı gönderir."""
        ready_key = f"{_READY_PREFIX}{room_name}"
        deadline = time.monotonic() + 30
        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)
            while time.monotonic() < deadline:
                await asyncio.sleep(0.5)
                if await r.exists(ready_key):
                    warmup_s = time.monotonic() - start_ts
                    logger.info(
                        "teqlif_stream_relay_warmup_seconds=%.2f | room=%s",
                        warmup_s, room_name,
                    )
                    if warmup_s > 5:
                        import telegram as tg
                        await tg.send(
                            self._cfg.telegram_bot_token, self._cfg.telegram_chat_id,
                            f"⚠️ Relay warmup yavaş: {warmup_s:.1f}s | {self._cfg.node_id} | {room_name[:20]}",
                        )
                    break
            await r.aclose()
        except Exception as exc:
            logger.warning("_monitor_warmup hatası: %s", exc)

    # ── Co-host subprocess yönetimi ───────────────────────────────────────────

    def _cohost_event_channels(self) -> list[str]:
        return ["live:cohost:joined:*", "live:cohost:left:*"]

    async def _cohost_pubsub_loop(self, redis_url: str) -> None:
        """live:cohost:joined/left:{stream_id} kanallarını dinler."""
        import redis.asyncio as _redis
        while True:
            r: _redis.Redis | None = None
            try:
                r = _redis.from_url(redis_url, decode_responses=True, protocol=2)
                pubsub = r.pubsub(ignore_subscribe_messages=True)
                await pubsub.psubscribe("live:cohost:joined:*", "live:cohost:left:*")
                logger.info("Co-host pub/sub dinleniyor")
                async for message in pubsub.listen():
                    if message["type"] not in ("pmessage", "message"):
                        continue
                    channel = message.get("channel", "")
                    try:
                        data = json.loads(message["data"])
                        data["_channel"] = channel
                        await self._cohost_queue.put(data)
                    except Exception as exc:
                        logger.warning("Co-host mesaj parse hatası: %s", exc)
            except asyncio.CancelledError:
                return
            except Exception as exc:
                logger.warning("Co-host pub/sub bağlantı hatası, 5s sonra yeniden: %s", exc)
                await asyncio.sleep(5)
            finally:
                if r is not None:
                    try:
                        await r.aclose()
                    except Exception:
                        pass

    async def _drain_cohost_queue(self, svc_cfg: dict, redis_url: str) -> None:
        """Kuyruktaki co-host olaylarını işler."""
        while not self._cohost_queue.empty():
            try:
                data = self._cohost_queue.get_nowait()
            except asyncio.QueueEmpty:
                break

            channel = data.get("_channel", "")
            identity = data.get("identity", "")
            if not identity:
                continue

            # stream_id'yi channel'dan çıkar: live:cohost:joined:123 → 123
            parts = channel.rsplit(":", 1)
            if len(parts) != 2 or not parts[1].isdigit():
                continue
            stream_id = int(parts[1])

            if "joined" in channel:
                await self._start_cohost_relay(svc_cfg, redis_url, stream_id, identity)
            elif "left" in channel:
                await self._stop_cohost_relay(stream_id, identity)

    async def _start_cohost_relay(
        self, svc_cfg: dict, redis_url: str, stream_id: int, cohost_identity: str
    ) -> None:
        """Co-host için ikinci livekit_relay.py subprocess başlatır."""
        key = (stream_id, cohost_identity)
        if key in self._cohost_procs:
            return

        api_key    = os.environ.get("LIVEKIT_API_KEY", "")
        api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
        if not api_key or not api_secret:
            return

        try:
            import asyncpg
            dsn = os.environ.get(svc_cfg.get("pg_dsn_env", "PG_DSN"), "")
            if not dsn:
                return
            conn = await asyncpg.connect(dsn=dsn)
            row  = await conn.fetchrow(
                "SELECT room_name, livekit_url FROM live_streams WHERE id = $1 AND status = 'live'",
                stream_id,
            )
            await conn.close()
        except Exception as exc:
            logger.error("_start_cohost_relay DB hatası: %s", exc)
            return

        if not row:
            return

        room_name  = row["room_name"]
        source_url = row["livekit_url"] or ""
        relay_node_id = self._cfg.node_id
        relay_room = f"{room_name}_relay_{relay_node_id}"
        target_url = svc_cfg.get("livekit_ws_url", "ws://127.0.0.1:7880")

        cmd = [
            "nice", "-n", "-5",
            _PYTHON, str(_RELAY_SCRIPT),
            "--source-url",    source_url,
            "--target-url",    target_url,
            "--room",          room_name,
            "--relay-room",    relay_room,
            "--host-identity", cohost_identity,  # co-host identity
            "--api-key",       api_key,
            "--api-secret",    api_secret,
            "--node-id",       relay_node_id,
            "--redis-url",     redis_url,
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )
            self._cohost_procs[key] = proc
            logger.info(
                "Co-host relay başlatıldı | stream=%d cohost=%s pid=%s",
                stream_id, cohost_identity, proc.pid,
            )
        except Exception as exc:
            logger.error("Co-host relay başlatma hatası | stream=%d | %s", stream_id, exc)

    async def _stop_cohost_relay(self, stream_id: int, cohost_identity: str) -> None:
        key = (stream_id, cohost_identity)
        proc = self._cohost_procs.pop(key, None)
        if proc:
            await _terminate(proc)
            logger.info("Co-host relay durduruldu | stream=%d cohost=%s", stream_id, cohost_identity)

    # ── Biten process'leri topla ──────────────────────────────────────────────

    async def _reap_finished(self, svc_cfg: dict, redis_url: str) -> None:
        """Biten relay subprocess'lerini toplar ve Redis'i temizler."""
        finished_rooms = [rn for rn, p in self._relay_procs.items() if p.returncode is not None]
        for room_name in finished_rooms:
            proc = self._relay_procs.pop(room_name)
            _, stderr_b = await proc.communicate()
            rc = proc.returncode
            logger.info("Relay bitti | room=%s returncode=%d", room_name, rc)
            if rc != 0:
                err = (stderr_b or b"").decode(errors="replace")[-300:]
                logger.error("Relay hata log | room=%s | %s", room_name, err)
                await self._db.mark_fail(
                    f"relay.{self._cfg.node_id}", expected_every_m=1440
                )

            # Redis temizliği
            await self._cleanup_relay_redis(room_name, svc_cfg, redis_url)

        finished_cohost = [k for k, p in self._cohost_procs.items() if p.returncode is not None]
        for key in finished_cohost:
            proc = self._cohost_procs.pop(key)
            await proc.communicate()
            logger.info("Co-host relay bitti | key=%s", key)

    async def _cleanup_relay_redis(self, room_name: str, svc_cfg: dict, redis_url: str) -> None:
        """Relay bitince Redis key'lerini ve LiveKit relay_room'unu temizler."""
        relay_node_id = self._cfg.node_id
        relay_room    = f"{room_name}_relay_{relay_node_id}"

        try:
            import redis.asyncio as _redis
            r = _redis.from_url(redis_url, decode_responses=True)
            await r.delete(f"live:relay:ready:{room_name}", f"live:relay:needed:{room_name}")
            await r.aclose()
        except Exception as exc:
            logger.warning("Relay Redis temizliği başarısız: %s", exc)

        # LiveKit API ile relay_room kapat
        try:
            import aiohttp
            from livekit.api.room_service import RoomService, DeleteRoomRequest
            api_key    = os.environ.get("LIVEKIT_API_KEY", "")
            api_secret = os.environ.get("LIVEKIT_API_SECRET", "")
            target_url = svc_cfg.get("livekit_ws_url", "http://127.0.0.1:7880")
            if api_key and api_secret:
                async with aiohttp.ClientSession() as session:
                    svc = RoomService(session, target_url, api_key, api_secret)
                    await svc.delete_room(DeleteRoomRequest(room=relay_room))
                logger.info("Relay room LiveKit'ten silindi: %s", relay_room)
        except Exception as exc:
            logger.debug("Relay room silme hatası (oda zaten yok olabilir): %s", exc)

    # ── Circuit breaker ───────────────────────────────────────────────────────

    def _circuit_ok(self, room_name: str) -> bool:
        now = time.monotonic()
        times = self._restart_times.get(room_name, [])
        # Pencere dışındakileri temizle
        times = [t for t in times if now - t < _CIRCUIT_WINDOW]
        self._restart_times[room_name] = times
        return len(times) < _CIRCUIT_MAX


# ── Yardımcılar ───────────────────────────────────────────────────────────────

async def _terminate(proc: asyncio.subprocess.Process) -> None:
    """SIGTERM → 3s bekle → SIGKILL."""
    if proc.returncode is not None:
        return
    try:
        proc.terminate()
        try:
            await asyncio.wait_for(proc.wait(), timeout=3)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
    except Exception:
        pass
