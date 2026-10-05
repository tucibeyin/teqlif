"""teqlif-agent — Donanım + servis sağlığı izleme.

AlertManager'ın yerini alır. Her node kendi sağlığını ölçer,
gossip ile yayar. Lider tüm node'ları toplayıp alert verir.

İzlenen:
  Donanım : CPU · RAM · Disk · Net RX/TX
  Systemd : teqlif-app · teqlif-worker-* · teqlif-ai-proxy ·
             livekit · postgresql · redis · minio · clickhouse ·
             haproxy · stalwart · teqlif-agent
  Süreçler: uvicorn · arq · livekit-server · minio
  Portlar : 8000(API) · 8001(AI) · 6379(Redis) · 5432(PG) ·
             9000(MinIO) · 7880(LiveKit) · 9000(CH) · 19100(Gossip)
  Yedek   : pg_backup · minio_backup · redis_backup eskimesi
  Redis   : ping · memory · keyspace
  i18n    : pack:tr/en/ar/ru Redis'te taze mi?
"""
from __future__ import annotations

import asyncio
import logging
import re
import time
from pathlib import Path

import aiohttp

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.health")

# ── Eşikler ──────────────────────────────────────────────────────────────────

_HW_THRESHOLDS = {
    "cpu_percent":  85.0,
    "ram_percent":  88.0,
    "disk_percent": 82.0,
    "net_rx_mbps":  900.0,
    "net_tx_mbps":  900.0,
}

_BACKUP_MAX_MIN = {
    "pg_backup":    25 * 60,
    "minio_backup": 25 * 60,
    "redis_backup": 25 * 60,
}

# Servisler her node'un rolüne göre farklıdır; her node sadece kendi
# /etc/systemd/system/ içinde bulunanları denetler.
_ALL_SERVICES = [
    "teqlif-app",
    "teqlif-worker-default",
    "teqlif-worker-critical",
    "teqlif-ai-proxy",
    "teqlif-agent",
    "livekit",
    "postgresql",
    "redis-server",
    "minio",
    "clickhouse-server",
    "haproxy",
    "stalwart-mail",
]

# Cooldown: aynı alert 30 dk içinde tekrar gitmez
_COOLDOWN_SEC = 30 * 60
_FIRING_TTL   = 4 * 60 * 60   # 4 saat — recovery tespiti için


class HealthMonitor:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg     = cfg
        self._db      = db
        self._firing:  dict[str, float] = {}   # key → fired_at
        self._cooldown: dict[str, float] = {}  # key → last_alert_at

    async def run(self, is_leader: bool) -> None:
        metrics  = await _collect_hw_metrics()
        services = await _collect_services()

        # Recording disk guard: /var/recordings/ varsa kontrol et
        rec_disk = _recording_disk_status()
        if rec_disk is not None:
            metrics["rec_free_gb"] = rec_disk

        await self._db.upsert_node_state(
            node_id=self._cfg.node_id,
            metrics=metrics,
            services=services,
            is_leader=is_leader,
        )

        # Lider cluster genelinde değerlendirir
        if is_leader:
            all_states = await self._db.get_all_node_states()
            for state in all_states:
                nid = state["node_id"]
                await self._eval_hw(nid, state["metrics"])
                await self._eval_services(nid, state["services"])
                await self._eval_recording_disk(nid, state["metrics"])

    # ── Değerlendirme ─────────────────────────────────────────────────────────

    async def _eval_hw(self, node_id: str, metrics: dict) -> None:
        labels = {
            "cpu_percent":  ("CPU",      "%"),
            "ram_percent":  ("RAM",      "%"),
            "disk_percent": ("Disk",     "%"),
            "net_rx_mbps":  ("Ağ giriş", "Mbps"),
            "net_tx_mbps":  ("Ağ çıkış", "Mbps"),
        }
        for key, threshold in _HW_THRESHOLDS.items():
            val = metrics.get(key)
            if not isinstance(val, (int, float)):
                continue
            label, unit = labels[key]
            fkey = f"{node_id}:hw:{key}"
            if val > threshold:
                if unit == "%":
                    msg = f"🔴 <b>{node_id}</b> — {label} %{val:.0f} (limit %{threshold:.0f})"
                else:
                    msg = f"🔴 <b>{node_id}</b> — {label} {val:.0f} {unit} (limit {threshold:.0f})"
                await self._fire(fkey, msg)
            else:
                suffix = f" (%{val:.0f})" if unit == "%" else f" ({val:.0f} {unit})"
                await self._recover(fkey, f"✅ <b>{node_id}</b> — {label} normale döndü{suffix}")

    async def _eval_recording_disk(self, node_id: str, metrics: dict) -> None:
        """Recording disk guard: free GB eşiklerine göre uyarı verir."""
        free_gb = metrics.get("rec_free_gb")
        if not isinstance(free_gb, (int, float)):
            return
        from config import load_cluster_config
        rec_cfg      = load_cluster_config().get("recording", {})
        warn_gb      = float(rec_cfg.get("disk_warn_gb", 15))
        emergency_gb = float(rec_cfg.get("disk_emergency_gb", 10))
        fkey = f"{node_id}:rec_disk"
        if free_gb < emergency_gb:
            await self._fire(fkey,
                f"🚨 <b>{node_id}</b> — Recording disk kritik: {free_gb:.1f}GB boş (<{emergency_gb}GB) — acil transfer!")
        elif free_gb < warn_gb:
            await self._fire(fkey,
                f"⚠️ <b>{node_id}</b> — Recording disk düşük: {free_gb:.1f}GB boş (<{warn_gb}GB) — erken transfer aktif")
        else:
            await self._recover(fkey,
                f"✅ <b>{node_id}</b> — Recording disk normale döndü: {free_gb:.1f}GB boş")

    async def _eval_services(self, node_id: str, services: dict) -> None:
        svc_labels = {
            "teqlif-app":             "teqlif API",
            "teqlif-worker-default":  "ARQ Worker (default)",
            "teqlif-worker-critical": "ARQ Worker (critical)",
            "teqlif-ai-proxy":        "AI Proxy",
            "teqlif-agent":           "teqlif Agent",
            "livekit":                "LiveKit",
            "postgresql":             "PostgreSQL",
            "redis-server":           "Redis",
            "minio":                  "MinIO",
            "clickhouse-server":      "ClickHouse",
            "haproxy":                "HAProxy",
            "stalwart-mail":          "Stalwart Mail",
        }
        for svc, data in services.items():
            if not isinstance(data, dict):
                continue
            label   = svc_labels.get(svc, svc)
            healthy = data.get("healthy", True)
            fkey    = f"{node_id}:svc:{svc}"
            if not healthy:
                err = data.get("error", "")
                msg = f"🔴 <b>{node_id}</b> — {label} çöktü"
                if err:
                    msg += f"\n<code>{err[:120]}</code>"
                await self._fire(fkey, msg)
            else:
                await self._recover(fkey, f"✅ <b>{node_id}</b> — {label} kurtardı")

        # Yedek eskimesi
        for bkey, max_min in _BACKUP_MAX_MIN.items():
            bdata = services.get(bkey, {})
            mins  = bdata.get("age_min")
            fkey  = f"{node_id}:backup:{bkey}"
            blabel = {"pg_backup": "PostgreSQL yedeği", "minio_backup": "MinIO yedeği",
                      "redis_backup": "Redis yedeği"}.get(bkey, bkey)
            if isinstance(mins, int) and mins > max_min:
                await self._fire(fkey, f"⚠️ <b>{node_id}</b> — {blabel} eski ({_fmt(mins)})")
            elif isinstance(mins, int):
                await self._recover(fkey, f"✅ <b>{node_id}</b> — {blabel} tamamlandı")

    # ── Fire / Recover ────────────────────────────────────────────────────────

    async def _fire(self, key: str, message: str) -> None:
        now = time.monotonic()
        if now - self._cooldown.get(key, 0) < _COOLDOWN_SEC:
            return
        self._cooldown[key] = now
        self._firing[key]   = now
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, message)
        logger.warning("ALERT: %s", message.replace("\n", " "))

    async def _recover(self, key: str, message: str) -> None:
        if key not in self._firing:
            return
        del self._firing[key]
        self._cooldown.pop(key, None)
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, message)
        logger.info("RECOVER: %s", message)


# ── Metrik Toplama ────────────────────────────────────────────────────────────

async def _collect_hw_metrics() -> dict:
    """CPU/RAM/Disk/Net — /proc ve /sys üzerinden, sıfır bağımlılık."""
    return {
        "cpu_percent":  await _cpu_percent(),
        "ram_percent":  _ram_percent(),
        "disk_percent": _disk_percent("/"),
        **_net_mbps(),
    }


async def _cpu_percent() -> float:
    def _read():
        with open("/proc/stat") as f:
            line = f.readline()
        parts = list(map(int, line.split()[1:]))
        idle  = parts[3]
        total = sum(parts)
        return idle, total

    idle1, total1 = _read()
    await asyncio.sleep(0.5)
    idle2, total2 = _read()
    dt = total2 - total1
    if dt == 0:
        return 0.0
    return round((1 - (idle2 - idle1) / dt) * 100, 1)


def _ram_percent() -> float:
    info: dict[str, int] = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k.strip()] = int(v.split()[0])
    total    = info.get("MemTotal", 1)
    free     = info.get("MemAvailable", 0)
    used_pct = (1 - free / total) * 100
    return round(used_pct, 1)


def _disk_percent(mount: str = "/") -> float:
    import shutil
    usage = shutil.disk_usage(mount)
    return round(usage.used / usage.total * 100, 1)


def _net_mbps() -> dict:
    """Son 1s örneklemesi. Mevcut interface'i otomatik bulur."""
    def _read_iface() -> tuple[str, int, int]:
        with open("/proc/net/dev") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 10:
                    continue
                iface = parts[0].rstrip(":")
                if iface in ("lo", "wg0") or not iface:
                    continue
                if re.match(r"^(eth|ens|eno|enp|eno)\d", iface):
                    return iface, int(parts[1]), int(parts[9])
        return "", 0, 0

    iface, rx1, tx1 = _read_iface()
    time.sleep(1)
    _, rx2, tx2 = _read_iface()
    rx_mbps = round((rx2 - rx1) * 8 / 1_000_000, 2)
    tx_mbps = round((tx2 - tx1) * 8 / 1_000_000, 2)
    return {"net_rx_mbps": rx_mbps, "net_tx_mbps": tx_mbps}


async def _collect_services() -> dict:
    """Sistemde mevcut olan servislerin durumunu denetler."""
    result: dict = {}

    for svc in _ALL_SERVICES:
        # Servis sisteme kurulu mu?
        unit_path = Path(f"/etc/systemd/system/{svc}.service")
        if not unit_path.exists():
            # Bazı servisler /lib/systemd içinde
            lib_path = Path(f"/lib/systemd/system/{svc}.service")
            if not lib_path.exists():
                continue

        try:
            proc = await asyncio.create_subprocess_exec(
                "systemctl", "is-active", "--quiet", svc,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            healthy = (proc.returncode == 0)
            error   = "" if healthy else await _systemctl_error(svc)
            result[svc] = {"healthy": healthy, "error": error}
        except Exception as exc:
            result[svc] = {"healthy": False, "error": str(exc)[:80]}

    # Yedek yaşları
    result.update(await _backup_ages())

    return result


async def _systemctl_error(svc: str) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "status", svc, "--no-pager", "-n", "3",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await proc.communicate()
        lines = out.decode(errors="replace").strip().splitlines()
        # Son 3 satırı al
        return " | ".join(l.strip() for l in lines[-3:])[:200]
    except Exception:
        return "status alınamadı"


async def _backup_ages() -> dict:
    """node2'deki yedek dizinlerinin yaşını dakika cinsinden döner."""
    backup_dirs = {
        "pg_backup":    "/project/teqlif/backups/pg_dump",
        "minio_backup": "/project/teqlif/backups/minio",
        "redis_backup": "/project/teqlif/backups/redis",
    }
    result = {}
    for key, path in backup_dirs.items():
        p = Path(path)
        if not p.exists():
            continue
        try:
            files = sorted(p.iterdir(), key=lambda f: f.stat().st_mtime, reverse=True)
            if files:
                age_sec = time.time() - files[0].stat().st_mtime
                result[key] = {"age_min": int(age_sec / 60)}
        except Exception:
            pass
    return result


def _recording_disk_status() -> float | None:
    """/var/recordings/ mount noktasının boş alanını GB cinsinden döner."""
    rec_path = Path("/var/recordings")
    if not rec_path.exists():
        return None
    try:
        import shutil
        usage = shutil.disk_usage(str(rec_path))
        return round(usage.free / 1_073_741_824, 2)
    except Exception:
        return None


def _fmt(mins: int) -> str:
    h, m = divmod(mins, 60)
    if h == 0:
        return f"{m} dk"
    if m == 0:
        return f"{h} saat"
    return f"{h} saat {m} dk"
