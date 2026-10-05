#!/usr/bin/env python3
"""
Edge Metrics Agent — V2.1

Her node'da çalışır; donanım + servis metriklerini Core Redis'e yazar.
EdgeOrchestrator Redis'ten okuyarak routing kararları verir.
AlertManager servis/kaynak anormalliklerini tespit edince Telegram bildirim gönderir.

Gerekli ortam değişkenleri:
  CORE_REDIS_URL, EDGE_NODE_ID, EDGE_NODE_TYPE, NODE_SERVICES
  (Opsiyonel) EDGE_LIVEKIT_URL, EDGE_MINIO_URL, EDGE_AI_PROXY_URL,
               EDGE_AI_PROXY_PRIORITY, LIVEKIT_API_KEY, LIVEKIT_API_SECRET,
               EDGE_NODE_REGION, DISK_PATH, EDGE_METRICS_INTERVAL_SEC,
               TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
"""

import json
import logging
import os
import socket
import subprocess
import time
from datetime import datetime, timezone
from typing import Any, Optional

import psutil
import redis as redis_lib
import requests
from jose import jwt

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("EdgeMetrics")


# ── Env helpers ───────────────────────────────────────────────────────────

def _env(key: str, default: str = "") -> str:
    return os.getenv(key, default)


def _require(key: str) -> str:
    v = os.getenv(key)
    if not v:
        logger.error(f"Required env var missing: {key}")
        raise SystemExit(1)
    return v


# ── AlertManager ──────────────────────────────────────────────────────────

class AlertManager:
    """
    Servis sağlık değişikliklerini ve kaynak eşiklerini izler.
    Durum geçişlerinde Telegram bildirimi gönderir.
    """

    _SVC_COOLDOWN_SEC      = 300   # Aynı servis için tekrar uyarı aralığı (5 dk)
    _RESOURCE_COOLDOWN_SEC = 1800  # Kaynak uyarısı tekrar aralığı (30 dk)
    _CPU_THRESHOLD         = 90.0
    _RAM_THRESHOLD         = 90.0
    _DISK_THRESHOLD        = 85.0

    def __init__(self, node_id: str, token: str, chat_id: str) -> None:
        self._node_id        = node_id
        self._token          = token
        self._chat_id        = chat_id
        self._enabled        = bool(token and chat_id)
        self._prev_health:  dict[str, bool]  = {}
        self._last_alert_ts: dict[str, float] = {}
        self._initialized    = False  # İlk döngüde baseline al, alert gönderme

        if not self._enabled:
            logger.info("AlertManager: TELEGRAM_BOT_TOKEN veya TELEGRAM_CHAT_ID yok — alert devre dışı")

    # ── Internal ──────────────────────────────────────────────────────────

    def _send(self, text: str) -> None:
        if not self._enabled:
            return
        try:
            requests.post(
                f"https://api.telegram.org/bot{self._token}/sendMessage",
                json={"chat_id": self._chat_id, "text": text, "parse_mode": "HTML"},
                timeout=5,
            )
        except Exception as exc:
            logger.warning(f"AlertManager: Telegram gönderimi başarısız: {exc}")

    def _alert(self, key: str, text: str, cooldown: float) -> None:
        """Cooldown kontrolüyle alert gönderir."""
        now = time.time()
        if now - self._last_alert_ts.get(key, 0) < cooldown:
            return
        logger.warning(f"ALERT: {text.replace('<b>', '').replace('</b>', '').replace('<code>', '').replace('</code>', '')}")
        self._send(text)
        self._last_alert_ts[key] = now

    # ── Servis health ──────────────────────────────────────────────────────

    def check_services(self, svc_results: dict[str, Any]) -> None:
        """Servis sonuçlarını önceki döngüyle karşılaştırır, geçişlerde alert atar."""
        for svc, result in svc_results.items():
            healthy = result.get("healthy", False)
            prev    = self._prev_health.get(svc)

            if not self._initialized or prev is None:
                # İlk döngü: sadece baseline yaz
                self._prev_health[svc] = healthy
                continue

            if healthy == prev:
                continue  # Durum değişmedi

            error = result.get("error", "")
            if not healthy:
                msg = f"🔴 <b>{self._node_id}</b> | <code>{svc}</code> — DOWN"
                if error:
                    msg += f"\n<code>{error[:200]}</code>"
            else:
                msg = f"✅ <b>{self._node_id}</b> | <code>{svc}</code> — kurtarıldı"

            self._alert(f"svc:{svc}", msg, self._SVC_COOLDOWN_SEC)
            self._prev_health[svc] = healthy

        self._initialized = True

    # ── Kaynak eşikleri ────────────────────────────────────────────────────

    def check_resources(self, cpu: float, ram_pct: float, disk_pct: float) -> None:
        """CPU / RAM / Disk eşik aşımlarında alert atar."""
        checks = [
            ("cpu",  cpu,      self._CPU_THRESHOLD,  f"CPU %{cpu:.0f}"),
            ("ram",  ram_pct,  self._RAM_THRESHOLD,  f"RAM %{ram_pct:.0f}"),
            ("disk", disk_pct, self._DISK_THRESHOLD, f"Disk %{disk_pct:.0f}"),
        ]
        for key, value, threshold, label in checks:
            if value < threshold:
                continue
            msg = (
                f"⚠️ <b>{self._node_id}</b> | {label} "
                f"(eşik: %{threshold:.0f})"
            )
            self._alert(f"resource:{key}", msg, self._RESOURCE_COOLDOWN_SEC)


# ── Service health checks ─────────────────────────────────────────────────

def _livekit_jwt(api_key: str, api_secret: str) -> str:
    return jwt.encode(
        {
            "iss": api_key,
            "sub": api_key,
            "exp": int(time.time()) + 60,
            "nbf": 0,
            "video": {"roomList": True, "roomAdmin": True},
        },
        api_secret,
        algorithm="HS256",
    )


def svc_livekit(cfg: dict) -> dict:
    try:
        token = _livekit_jwt(cfg["livekit_api_key"], cfg["livekit_api_secret"])
        resp = requests.post(
            "http://localhost:7880/twirp/livekit.RoomService/ListRooms",
            json={},
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            timeout=3,
        )
        if resp.status_code == 200:
            rooms = resp.json().get("rooms", [])
            participants = sum(r.get("numParticipants", 0) for r in rooms)
            return {"healthy": True, "rooms": len(rooms), "participants": participants}
        return {"healthy": False, "error": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


def svc_minio(cfg: dict) -> dict:
    port = int(cfg.get("minio_port", 9000))
    try:
        r = requests.get(f"http://localhost:{port}/minio/health/live", timeout=2)
        return {"healthy": r.status_code == 200}
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


def svc_redis(cfg: dict) -> dict:
    url = cfg.get("redis_url", "redis://127.0.0.1:6379/0")
    try:
        r = redis_lib.Redis.from_url(url, socket_connect_timeout=2, socket_timeout=2)
        r.ping()
        mem_info    = r.info("memory")
        client_info = r.info("clients")
        return {
            "healthy":   True,
            "memory_mb": round(mem_info.get("used_memory", 0) / 1024 / 1024, 1),
            "clients":   client_info.get("connected_clients", 0),
        }
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


def svc_postgres(cfg: dict) -> dict:
    host = cfg.get("postgres_host", "127.0.0.1")
    port = int(cfg.get("postgres_port", 5432))
    try:
        with socket.create_connection((host, port), timeout=2):
            return {"healthy": True}
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


def svc_clickhouse(cfg: dict) -> dict:
    host = cfg.get("clickhouse_host", "127.0.0.1")
    port = int(cfg.get("clickhouse_port", 8123))
    try:
        r = requests.get(f"http://{host}:{port}/ping", timeout=2)
        return {"healthy": r.text.strip() == "Ok."}
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


def svc_ai_proxy(cfg: dict) -> dict:
    port = int(cfg.get("ai_proxy_port", 8001))
    try:
        r = requests.get(f"http://localhost:{port}/health", timeout=3)
        return {"healthy": r.status_code < 500}
    except Exception as e:
        return {"healthy": False, "error": str(e)[:120]}


# ── Backup checks (node2 only) ────────────────────────────────────────────

def _systemd_active(service: str) -> bool:
    try:
        r = subprocess.run(
            ["systemctl", "is-active", service],
            capture_output=True, text=True, timeout=3,
        )
        return r.stdout.strip() == "active"
    except Exception:
        return False


def _last_inactive_minutes(service: str) -> Optional[int]:
    """Servisin en son inaktif olduğu zamandan bu yana geçen dakika sayısı."""
    try:
        r = subprocess.run(
            ["systemctl", "show", service, "--property=InactiveEnterTimestamp"],
            capture_output=True, text=True, timeout=3,
        )
        ts = r.stdout.strip().split("=", 1)[-1].strip()
        if not ts or ts in ("n/a", ""):
            return None
        dt = datetime.strptime(ts, "%a %Y-%m-%d %H:%M:%S %Z").replace(tzinfo=timezone.utc)
        return int((datetime.now(timezone.utc) - dt).total_seconds() / 60)
    except Exception:
        return None


def svc_pg_backup(cfg: dict) -> dict:
    last_dump    = _last_inactive_minutes("teqlif-pg-dump.service")
    last_offsite = _last_inactive_minutes("teqlif-offsite-sync.service")
    # healthy = dump ran within last 25 hours (WAL streaming removed, pg_dump only)
    healthy = last_dump is not None and last_dump < 25 * 60
    return {
        "healthy":              healthy,
        "last_dump_min_ago":    last_dump,
        "last_offsite_min_ago": last_offsite,
    }


def svc_minio_backup(cfg: dict) -> dict:
    last = _last_inactive_minutes("teqlif-minio-backup.service")
    return {"healthy": True, "last_run_min_ago": last}


def svc_redis_backup(cfg: dict) -> dict:
    last = _last_inactive_minutes("teqlif-redis-backup.service")
    return {"healthy": True, "last_run_min_ago": last}


CHECKERS: dict[str, Any] = {
    "livekit":        svc_livekit,
    "minio":          svc_minio,
    "redis":          svc_redis,
    "postgres":       svc_postgres,
    "clickhouse":     svc_clickhouse,
    "ai_proxy":       svc_ai_proxy,
    "pg_backup":      svc_pg_backup,
    "minio_backup":   svc_minio_backup,
    "redis_backup":   svc_redis_backup,
}


# ── Real-time network rate ────────────────────────────────────────────────

class NetRate:
    def __init__(self) -> None:
        snap = psutil.net_io_counters()
        self._rx, self._tx, self._ts = snap.bytes_recv, snap.bytes_sent, time.monotonic()

    def mbps(self) -> tuple[float, float]:
        snap = psutil.net_io_counters()
        now  = time.monotonic()
        dt   = max(now - self._ts, 0.001)
        rx   = max((snap.bytes_recv - self._rx) * 8 / 1e6 / dt, 0.0)
        tx   = max((snap.bytes_sent - self._tx) * 8 / 1e6 / dt, 0.0)
        self._rx, self._tx, self._ts = snap.bytes_recv, snap.bytes_sent, now
        return round(rx, 2), round(tx, 2)


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    logger.info("Edge Metrics Agent starting…")

    core_redis_url = _require("CORE_REDIS_URL")
    node_id        = _require("EDGE_NODE_ID")
    node_type      = [t.strip() for t in _env("EDGE_NODE_TYPE").split(",") if t.strip()]
    services       = [s.strip() for s in _env("NODE_SERVICES").split(",")  if s.strip()]
    interval       = int(_env("EDGE_METRICS_INTERVAL_SEC", "5"))
    disk_path      = _env("DISK_PATH", "/")

    livekit_url      = _env("EDGE_LIVEKIT_URL")
    minio_url        = _env("EDGE_MINIO_URL")
    ai_proxy_url     = _env("EDGE_AI_PROXY_URL")
    ai_proxy_priority = int(_env("EDGE_AI_PROXY_PRIORITY", "100"))
    region           = _env("EDGE_NODE_REGION")

    svc_cfg = {
        "livekit_api_key":    _env("LIVEKIT_API_KEY"),
        "livekit_api_secret": _env("LIVEKIT_API_SECRET"),
        "redis_url":          _env("REDIS_URL", "redis://127.0.0.1:6379/0"),
        "postgres_host":      "127.0.0.1",
        "postgres_port":      "5432",
        "clickhouse_host":    _env("CLICKHOUSE_HOST", "127.0.0.1"),
        "clickhouse_port":    _env("CLICKHOUSE_PORT", "8123"),
    }

    alerter = AlertManager(
        node_id    = node_id,
        token      = _env("TELEGRAM_BOT_TOKEN"),
        chat_id    = _env("TELEGRAM_CHAT_ID"),
    )

    logger.info(f"Node={node_id}  Type={node_type}  Services={services}  Interval={interval}s")

    r = redis_lib.Redis.from_url(core_redis_url, decode_responses=True)
    try:
        r.ping()
        logger.info("Core Redis: connected.")
    except Exception as e:
        logger.error(f"Core Redis connect failed: {e}")
        raise SystemExit(1)

    redis_key = f"edge:metrics:{node_id}"
    ttl       = interval * 4  # ajan ölürse 4 döngü sonra expire
    net       = NetRate()

    while True:
        loop_start = time.monotonic()
        try:
            cpu  = psutil.cpu_percent(interval=1)
            mem  = psutil.virtual_memory()
            load = psutil.getloadavg()
            boot = psutil.boot_time()

            try:
                disk = psutil.disk_usage(disk_path)
                disk_pct   = disk.percent
                disk_used  = round(disk.used  / 1e9, 2)
                disk_total = round(disk.total / 1e9, 2)
            except Exception:
                disk_pct = disk_used = disk_total = 0.0

            rx_mbps, tx_mbps = net.mbps()

            svc_results: dict[str, Any] = {}
            for svc in services:
                fn = CHECKERS.get(svc)
                if fn:
                    try:
                        svc_results[svc] = fn(svc_cfg)
                    except Exception as e:
                        svc_results[svc] = {"healthy": False, "error": str(e)[:120]}

            metrics: dict[str, Any] = {
                # Kimlik
                "node_id":     node_id,
                "node_type":   node_type,
                "region":      region,
                "hostname":    socket.gethostname(),
                "uptime_sec":  int(time.time() - boot),
                # CPU
                "cpu_percent":  round(cpu, 1),
                "cpu_count":    psutil.cpu_count(),
                "load_avg_1m":  round(load[0], 2),
                "load_avg_5m":  round(load[1], 2),
                "load_avg_15m": round(load[2], 2),
                # RAM
                "ram_total_gb": round(mem.total / 1e9, 2),
                "ram_used_gb":  round(mem.used  / 1e9, 2),
                "ram_percent":  mem.percent,
                # Disk
                "disk_total_gb": disk_total,
                "disk_used_gb":  disk_used,
                "disk_percent":  round(disk_pct, 1),
                # Ağ (anlık Mbps)
                "net_rx_mbps": rx_mbps,
                "net_tx_mbps": tx_mbps,
                # Servisler
                "services": svc_results,
                # Routing URL'leri
                "livekit_url":       livekit_url,
                "minio_url":         minio_url,
                "ai_proxy_url":      ai_proxy_url,
                "ai_proxy_priority": ai_proxy_priority,
                # Zaman damgası
                "timestamp": int(time.time()),
            }

            r.set(redis_key, json.dumps(metrics), ex=ttl)
            logger.debug(
                f"{node_id}  CPU={cpu:.1f}%  RAM={mem.percent:.1f}%  "
                f"DISK={disk_pct:.1f}%  RX={rx_mbps}Mbps  TX={tx_mbps}Mbps"
            )

            alerter.check_services(svc_results)
            alerter.check_resources(cpu, mem.percent, disk_pct)

        except Exception as e:
            logger.error(f"Metrics loop error: {e}", exc_info=True)

        elapsed = time.monotonic() - loop_start
        time.sleep(max(0.1, interval - elapsed))


if __name__ == "__main__":
    main()
