"""
Alert Manager — V2.1

Tüm node metriklerini periyodik olarak denetler; eşik aşılırsa veya
servis düşerse Telegram üzerinden bildirim gönderir.

FastAPI lifespan'ında tek bir asyncio arka plan görevi olarak çalışır
(yalnızca node1 / Core API üzerinde).
"""

import asyncio
import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

# ── Eşik değerleri ────────────────────────────────────────────────────────

_HW_THRESHOLDS: dict[str, float] = {
    "cpu_percent":  85.0,   # %
    "ram_percent":  88.0,   # %
    "disk_percent": 82.0,   # %
    "net_rx_mbps":  900.0,  # Mbps (gateway throttle riski)
    "net_tx_mbps":  900.0,
}

# Backup job'ları bu dakikadan uzun süre önce çalıştıysa uyarı ver
_BACKUP_STALENESS: dict[str, tuple[str, int]] = {
    "pg_backup":    ("last_dump_min_ago",  25 * 60),
    "minio_backup": ("last_run_min_ago",   25 * 60),
    "redis_backup": ("last_run_min_ago",   25 * 60),
}

POLL_INTERVAL_SEC  = 60
ALERT_COOLDOWN_SEC = 30 * 60  # aynı alarm 30 dakika tekrar tetiklenmez


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
                val = node.get(metric)
                if isinstance(val, (int, float)) and val > threshold:
                    await self._fire(
                        redis, nid, f"hw:{metric}",
                        f"*{nid}* `{metric}` = {val:.1f} (eşik: {threshold})",
                    )

            # Servis sağlığı
            for svc, data in node.get("services", {}).items():
                if isinstance(data, dict) and not data.get("healthy", True):
                    err = data.get("error", "")
                    msg = f"*{nid}* servis `{svc}` DOWN" + (f": _{err}_" if err else "")
                    await self._fire(redis, nid, f"svc:{svc}", msg)

            # Backup eskimesi
            svcs = node.get("services", {})
            for svc_name, (field, max_min) in _BACKUP_STALENESS.items():
                data = svcs.get(svc_name, {})
                mins = data.get(field)
                if isinstance(mins, int) and mins > max_min:
                    h, m = divmod(mins, 60)
                    await self._fire(
                        redis, nid, f"stale:{svc_name}",
                        f"*{nid}* `{svc_name}` son çalışma: {h}s {m}d önce",
                    )

    async def _fire(self, redis, node_id: str, key: str, message: str) -> None:
        cooldown_key = f"alert:cd:{node_id}:{key}"
        if await redis.exists(cooldown_key):
            return
        await redis.set(cooldown_key, "1", ex=ALERT_COOLDOWN_SEC)
        await self._telegram(f"🚨 {message}")
        logger.warning(f"Alert gönderildi: [{node_id}] {key}")

    async def _telegram(self, text: str) -> None:
        if not settings.telegram_bot_token or not settings.telegram_chat_id:
            return
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                await client.post(
                    f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage",
                    json={
                        "chat_id":    settings.telegram_chat_id,
                        "text":       text,
                        "parse_mode": "Markdown",
                    },
                )
        except Exception as e:
            logger.error(f"Telegram gönderim hatası: {e}")


alert_manager = AlertManager()
