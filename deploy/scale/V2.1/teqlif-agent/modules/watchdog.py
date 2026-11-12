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
# parents[1] = /opt/teqlif-agent/ (prod) veya deploy/scale/V2.1/teqlif-agent/ (dev)
_SCHEDULE_PATH = Path(__file__).parents[1] / "schedule.yaml"


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
    "retry_failed_chat_dumps_task":    30,
    # run_ml_training_pipeline_task alt adımları — haftalık pipeline içinde çalışır
    "train_feed_als_task":            10080,
    "compute_influence_scores_task":  10080,
}

_COOLDOWN_SEC = 2 * 60 * 60   # aynı job için 2 saatte bir uyarı


def _job_registry() -> dict[str, int]:
    """Her cycle'da schedule.yaml'ı yeniden okur — restart gerektirmez."""
    return {**_CONTINUOUS_REGISTRY, **_load_batch_registry()}


class JobWatchdog:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg     = cfg
        self._db      = db
        self._alerted: dict[str, float] = {}  # job_name → last_alert monotonic

    async def run(self, is_leader: bool) -> None:
        registry = _job_registry()
        # Her node Redis'ten job_ok ve job_fail sinyallerini çeker, DB'ye yazar
        await self._sync_from_redis(registry)

        # Sadece lider değerlendirir ve Telegram gönderir
        if is_leader:
            stale = await self._db.get_stale_jobs()
            for row in stale:
                await self._alert_stale(row, registry)

            failed = await self._db.get_failed_jobs()
            for row in failed:
                await self._alert_fail(row)

    async def _sync_from_redis(self, registry: dict[str, int]) -> None:
        try:
            import redis.asyncio as aioredis
            r = await aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            ok_data   = await r.hgetall("teqlif:agent:job_ok")
            fail_data = await r.hgetall("teqlif:agent:job_fail")
            await r.aclose()
        except Exception as exc:
            logger.debug("Redis job_ok/job_fail okunamadı: %s", exc)
            return

        for job_name, ts in ok_data.items():
            expected = registry.get(job_name)
            if expected is None:
                logger.debug("Registry'de tanımsız job atlandı: %s", job_name)
                continue
            await self._db.mark_ok(job_name, last_ok_at=ts, expected_every_m=expected)

        for job_name, payload in fail_data.items():
            expected = registry.get(job_name)
            if expected is None:
                continue
            # payload: "<iso_ts> | <reason>"
            parts   = payload.split(" | ", 1)
            fail_ts = parts[0].strip()
            reason  = parts[1].strip() if len(parts) > 1 else ""
            await self._db.mark_fail(
                job_name, expected_every_m=expected, last_fail_at=fail_ts, reason=reason
            )

    async def _alert_stale(self, row: dict, registry: dict[str, int]) -> None:
        job   = row["job_name"]
        mins  = registry.get(job, 60)
        last  = row.get("last_ok_at", "bilinmiyor")
        now   = time.monotonic()
        cooldown_key = f"stale:{job}"
        if now - self._alerted.get(cooldown_key, 0) < _COOLDOWN_SEC:
            return
        self._alerted[cooldown_key] = now
        await self._db.set_job_alert_sent(job)
        msg = (
            f"⚠️ <b>{self._cfg.node_id}</b> — Job yanıt vermiyor\n"
            f"<code>{job}</code>\n"
            f"Beklenen: her {mins} dk · Son OK: {last}"
        )
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, msg)
        logger.warning("Job stale: %s", job)

    async def _alert_fail(self, row: dict) -> None:
        job        = row["job_name"]
        fail_count = row.get("fail_count", 1)
        last_fail  = row.get("last_fail_at", "bilinmiyor")
        reason     = row.get("fail_reason") or ""
        now        = time.monotonic()
        cooldown_key = f"fail:{job}"
        if now - self._alerted.get(cooldown_key, 0) < _COOLDOWN_SEC:
            return
        self._alerted[cooldown_key] = now
        await self._db.set_job_alert_sent(job)
        reason_line = f"\nNeden: {reason}" if reason else ""
        msg = (
            f"🚨 <b>{self._cfg.node_id}</b> — Job hata verdi\n"
            f"<code>{job}</code>\n"
            f"Hata sayısı: {fail_count} · Son hata: {last_fail}"
            f"{reason_line}"
        )
        await tg.send(self._cfg.telegram_bot_token, self._cfg.telegram_chat_id, msg)
        logger.warning("Job fail aktif: %s (count=%s)", job, fail_count)
