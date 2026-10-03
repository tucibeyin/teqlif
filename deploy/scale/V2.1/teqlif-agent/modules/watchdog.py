"""teqlif-agent — ARQ job watchdog + dead letter izleme.

Tüm kritik ARQ cron job'larının çalışıp çalışmadığını denetler.
Beklenen interval'den %50 fazla süre geçmişse Telegram uyarısı.

ARQ worker'lar, görev tamamlandığında:
  Redis → HSET teqlif:agent:job_ok <job_name> <iso_timestamp>
Agent bu key'i okur, gossip DB'ye yazar, watchdog değerlendirir.
"""
from __future__ import annotations

import logging
import time

import aiohttp

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.watchdog")

# job_name → beklenen interval (dakika)
# Bu değerler worker.py cron tanımlarıyla örtüşmeli
_JOB_REGISTRY: dict[str, int] = {
    # Temizlik görevleri
    "cleanup_expired_stories_task":         60,
    "cleanup_old_notifications_task":       24 * 60,
    "cleanup_old_stream_likes_task":        24 * 60,
    "cleanup_ghost_calls_task":             15,
    "cleanup_hype_highlights_task":         60,
    "cleanup_stale_streams_task":           2,
    "cleanup_old_media_messages_task":      7 * 24 * 60,
    "cleanup_hidden_messages_task":         24 * 60,
    "cleanup_old_impressions_task":         24 * 60,
    "deactivate_expired_listings_task":     24 * 60,
    "delete_expired_inactive_listings_task": 24 * 60,
    # ML / analitik
    "compute_user_interests_task":          6 * 60,
    "populate_foryou_feed_task":            6 * 60,
    "rebuild_faiss_index_task":             12 * 60,
    "flush_interactions_to_db":             5,
    "sync_ad_campaigns_task":               10,
    "compute_seller_badges_task":           24 * 60,
    "compute_trust_scores_task":            24 * 60,
    "compute_trending_listings_task":       6 * 60,
    "check_search_alerts_task":             15,
    "hesitation_retarget_task":             24 * 60,
    "process_churn_and_airdrop":            24 * 60,
    "calculate_user_budgets_task":          24 * 60,
    # Haftalık (7 günde bir — 10080 dk toleranslı)
    "train_feed_als_task":                  7 * 24 * 60,
    "train_swipe_live_als_task":            7 * 24 * 60,
    "train_item2vec_task":                  7 * 24 * 60,
    "train_kmeans_cold_start_task":         4 * 24 * 60,
    "train_bpr_task":                       3 * 24 * 60,
    "train_listing_quality_model_task":     7 * 24 * 60,
    "train_churn_model_task":               7 * 24 * 60,
    "compute_influence_scores_task":        7 * 24 * 60,
}

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
