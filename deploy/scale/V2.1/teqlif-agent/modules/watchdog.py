"""teqlif-agent — ARQ job watchdog + dead letter izleme.

Tüm kritik ARQ cron job'larının çalışıp çalışmadığını denetler.
Beklenen interval'den %50 fazla süre geçmişse Telegram uyarısı.

ARQ worker'lar, görev tamamlandığında:
  Redis → HSET teqlif:agent:job_ok <job_name> <iso_timestamp>
Agent bu key'i okur, gossip DB'ye yazar, watchdog değerlendirir.

Batch job interval'ları deploy/scale/V2.1/schedule.yaml'dan okunur.
Sürekli görevler (flush_interactions, vb.) burada sabit kalır.
"""
from __future__ import annotations

import logging
import time
from pathlib import Path

import aiohttp
import yaml

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.watchdog")

# deploy/scale/V2.1/teqlif-agent/modules/watchdog.py
# parents[2] = deploy/scale/V2.1/
_SCHEDULE_PATH = Path(__file__).parents[2] / "schedule.yaml"


def _load_batch_registry() -> dict[str, int]:
    """schedule.yaml batch bölümünden {job_name: watchdog_m} okur."""
    try:
        with open(_SCHEDULE_PATH) as f:
            cfg = yaml.safe_load(f)
        return {
            entry["name"]: int(entry["watchdog_m"])
            for entry in cfg.get("batch", [])
            if "watchdog_m" in entry
        }
    except Exception as exc:
        logger.warning("schedule.yaml okunamadı, varsayılan registry kullanılıyor: %s", exc)
        return {}


# Sürekli görevler — schedule.yaml dışında, burada sabit
_CONTINUOUS_REGISTRY: dict[str, int] = {
    "cleanup_expired_stories_task":    60,
    "cleanup_hype_highlights_task":    60,
    "cleanup_ghost_calls_task":        15,
    "flush_interactions_to_db":        5,
    "sync_ad_campaigns_task":          10,
    "invalidate_swipe_live_configs_task": 15,
    "sync_swipelive_interests_task":   20,
    "check_search_alerts_task":        15,
    "backfill_listing_quality_scores_task": 60,
    "cleanup_stale_streams_task":      2,
}

# Birleşik registry: sürekli (sabit) + batch (schedule.yaml'dan)
_JOB_REGISTRY: dict[str, int] = {**_CONTINUOUS_REGISTRY, **_load_batch_registry()}

_COOLDOWN_SEC = 2 * 60 * 60   # aynı job için 2 saatte bir uyarı


class JobWatchdog:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg     = cfg
        self._db      = db
        self._alerted: dict[str, float] = {}  # job_name → last_alert monotonic

    async def run(self, is_leader: bool) -> None:
        # Her node Redis'ten job_ok sinyallerini çeker ve DB'ye yazar
        await self._sync_from_redis()

        # Sadece lider değerlendirir ve Telegram gönderir
        if is_leader:
            stale = await self._db.get_stale_jobs()
            for row in stale:
                await self._alert(row)

    async def _sync_from_redis(self) -> None:
        try:
            import aioredis
            redis = await aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            data  = await redis.hgetall("teqlif:agent:job_ok")
            await redis.aclose()
        except Exception as exc:
            logger.debug("Redis job_ok okunamadı: %s", exc)
            return

        for job_name, ts in data.items():
            expected = _JOB_REGISTRY.get(job_name, 60)
            await self._db.mark_ok(job_name, expected_every_m=expected)
            # Eğer yeni job varsa registry'e ekle
            if job_name not in _JOB_REGISTRY:
                logger.debug("Yeni job tespit edildi: %s", job_name)

    async def _alert(self, row: dict) -> None:
        job   = row["job_name"]
        mins  = _JOB_REGISTRY.get(job, 60)
        last  = row.get("last_ok_at", "bilinmiyor")
        now   = time.monotonic()
        if now - self._alerted.get(job, 0) < _COOLDOWN_SEC:
            return
        self._alerted[job] = now
        await self._db.set_job_alert_sent(job)
        msg = (
            f"⚠️ <b>{self._cfg.node_id}</b> — Job yanıt vermiyor\n"
            f"<code>{job}</code>\n"
            f"Beklenen: her {mins} dk · Son OK: {last}"
        )
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, msg)
        logger.warning("Job stale: %s", job)
