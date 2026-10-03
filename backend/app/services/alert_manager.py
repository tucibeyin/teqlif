"""
Alert Manager — V2.1

Tüm node metriklerini periyodik olarak denetler; eşik aşılırsa veya
servis düşerse Telegram üzerinden bildirim gönderir.
Servis ya da metrik düzeldiğinde "kurtardı" bildirimi de gönderir.

FastAPI lifespan'ında tek bir asyncio arka plan görevi olarak çalışır
(yalnızca node1 / Core API üzerinde).
"""

import asyncio
import logging

from app.config import settings

logger = logging.getLogger(__name__)

# ── Eşik değerleri ────────────────────────────────────────────────────────

_HW_THRESHOLDS: dict[str, float] = {
    "cpu_percent":  85.0,
    "ram_percent":  88.0,
    "disk_percent": 82.0,
    "net_rx_mbps":  900.0,
    "net_tx_mbps":  900.0,
}

_BACKUP_STALENESS: dict[str, tuple[str, int]] = {
    "pg_backup":    ("last_dump_min_ago",  25 * 60),
    "minio_backup": ("last_run_min_ago",   25 * 60),
    "redis_backup": ("last_run_min_ago",   25 * 60),
}

# ── İnsan okunabilir etiketler ────────────────────────────────────────────

_METRIC_LABELS: dict[str, tuple[str, str]] = {
    # metric_key: (görünen ad, birim)
    "cpu_percent":  ("CPU",      "%"),
    "ram_percent":  ("RAM",      "%"),
    "disk_percent": ("Disk",     "%"),
    "net_rx_mbps":  ("Ağ giriş", "Mbps"),
    "net_tx_mbps":  ("Ağ çıkış", "Mbps"),
}

_SVC_LABELS: dict[str, str] = {
    "postgresql":  "PostgreSQL",
    "redis":       "Redis",
    "minio":       "MinIO",
    "livekit":     "LiveKit",
    "clickhouse":  "ClickHouse",
    "haproxy":     "HAProxy",
    "alertmanager": "Alertmanager",
}

_BACKUP_LABELS: dict[str, str] = {
    "pg_backup":    "PostgreSQL yedeği",
    "minio_backup": "MinIO yedeği",
    "redis_backup": "Redis yedeği",
}

POLL_INTERVAL_SEC  = 60
ALERT_COOLDOWN_SEC = 30 * 60
_FIRING_TTL_SEC    = 4 * 60 * 60  # 4 saatte otomatik temizlenir


def _fmt_duration(mins: int) -> str:
    h, m = divmod(mins, 60)
    if h == 0:
        return f"{m} dk"
    if m == 0:
        return f"{h} saat"
    return f"{h} saat {m} dk"


class AlertManager:
    """Periyodik cluster denetimi ve Telegram bildirimleri."""

    async def run_forever(self) -> None:
        logger.info("AlertManager başlatıldı.")
        while True:
            try:
                await self._cycle()
            except Exception as e:
                logger.error(f"AlertManager döngü hatası: {e}", exc_info=True)
            await asyncio.sleep(POLL_INTERVAL_SEC)

    async def _cycle(self) -> None:
        from app.services.edge_orchestrator import orchestrator
        from app.utils.redis_client import get_redis

        all_metrics = await orchestrator.get_all_metrics()
        redis       = await get_redis()

        for node in all_metrics:
            nid = node.get("node_id", "?")

            # Donanım eşikleri
            for metric, threshold in _HW_THRESHOLDS.items():
                val   = node.get(metric)
                label, unit = _METRIC_LABELS.get(metric, (metric, ""))
                key   = f"hw:{metric}"

                if isinstance(val, (int, float)) and val > threshold:
                    if unit == "%":
                        msg = f"🔴 <b>{nid}</b> — {label} %{val:.0f} (limit %{threshold:.0f})"
                    else:
                        msg = f"🔴 <b>{nid}</b> — {label} {val:.0f} {unit} (limit {threshold:.0f})"
                    await self._fire(redis, nid, key, msg)
                elif isinstance(val, (int, float)):
                    suffix = f" (%{val:.0f})" if unit == "%" else f" ({val:.0f} {unit})"
                    await self._recover(redis, nid, key,
                                        f"✅ <b>{nid}</b> — {label} normale döndü{suffix}")

            # Servis sağlığı
            for svc, data in node.get("services", {}).items():
                if not isinstance(data, dict):
                    continue
                key       = f"svc:{svc}"
                svc_label = _SVC_LABELS.get(svc, svc)
                healthy   = data.get("healthy", True)

                if not healthy:
                    err = data.get("error", "")
                    msg = f"🔴 <b>{nid}</b> — {svc_label} çöktü"
                    if err:
                        msg += f"\n<code>{err[:120]}</code>"
                    await self._fire(redis, nid, key, msg)
                else:
                    await self._recover(redis, nid, key,
                                        f"✅ <b>{nid}</b> — {svc_label} kurtardı")

            # Yedek eskimesi
            svcs = node.get("services", {})
            for svc_name, (field, max_min) in _BACKUP_STALENESS.items():
                data  = svcs.get(svc_name, {})
                mins  = data.get(field)
                key   = f"stale:{svc_name}"
                label = _BACKUP_LABELS.get(svc_name, svc_name)

                if isinstance(mins, int) and mins > max_min:
                    await self._fire(
                        redis, nid, key,
                        f"⚠️ <b>{nid}</b> — {label} eski ({_fmt_duration(mins)})",
                    )
                elif isinstance(mins, int):
                    await self._recover(redis, nid, key,
                                        f"✅ <b>{nid}</b> — {label} tamamlandı")

    async def _fire(self, redis, node_id: str, key: str, message: str) -> None:
        cooldown_key = f"alert:cd:{node_id}:{key}"
        firing_key   = f"alert:firing:{node_id}:{key}"
        if await redis.exists(cooldown_key):
            return
        await redis.set(cooldown_key, "1", ex=ALERT_COOLDOWN_SEC)
        await redis.set(firing_key,   "1", ex=_FIRING_TTL_SEC)
        await self._telegram(message)
        logger.warning(f"Alert gönderildi: [{node_id}] {key}")

    async def _recover(self, redis, node_id: str, key: str, message: str) -> None:
        firing_key = f"alert:firing:{node_id}:{key}"
        if not await redis.exists(firing_key):
            return
        await redis.delete(firing_key)
        await redis.delete(f"alert:cd:{node_id}:{key}")
        await self._telegram(message)
        logger.info(f"Recovery gönderildi: [{node_id}] {key}")

    async def _telegram(self, text: str) -> None:
        from app.utils.telegram import send_telegram_message
        await send_telegram_message(text)


alert_manager = AlertManager()
