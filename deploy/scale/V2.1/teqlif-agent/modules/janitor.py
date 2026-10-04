"""teqlif-agent — TTL Janitor (merkezi temizlik orkestratörü).

Lider bu modülü çalıştırır. Her TTL politikası için:
  - Süresi dolmuş kayıtları tespit eder
  - Sıradaki eylemi belirler ve cleanup_log'a yazar

Stream kayıt yaşam döngüsü (DB status sütunu):
  recording → encoding → encoded → transferring → available → expired → archived → deleted
"""
from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.janitor")

# ── TTL Politikaları ──────────────────────────────────────────────────────────

_DEFAULT_POLICIES = [
    {
        "name":        "notifications_30d",
        "description": "30 günden eski okunmuş bildirimler",
        "config": {
            "table": "notifications", "expires_col": "created_at",
            "max_age_days": 30, "condition": "is_read = true",
        },
    },
    {
        "name":        "stream_recordings_15d",
        "description": "15 günden eski arşivlenmiş yayın kayıtları",
        "config": {
            "table": "stream_recordings", "expires_col": "archived_at",
            "max_age_days": 15, "status_col": "status", "ready_status": "archived",
        },
    },
    {
        "name":        "analytics_events_90d",
        "description": "90 günden eski analytics event'leri",
        "config": {
            "table": "analytics_events", "expires_col": "created_at", "max_age_days": 90,
        },
    },
    {
        "name":        "user_interactions_90d",
        "description": "90 günden eski kullanıcı etkileşim kayıtları",
        "config": {
            "table": "user_interactions", "expires_col": "created_at", "max_age_days": 90,
        },
    },
    {
        "name":        "listing_offers_60d",
        "description": "60 günden eski reddedilmiş teklifler",
        "config": {
            "table": "listing_offers", "expires_col": "updated_at",
            "max_age_days": 60, "condition": "status IN ('declined', 'expired')",
        },
    },
    {
        "name":        "calls_90d",
        "description": "90 günden eski arama kayıtları",
        "config": {
            "table": "calls", "expires_col": "created_at", "max_age_days": 90,
        },
    },
    {
        "name":        "search_alerts_90d",
        "description": "90 gündür eşleşmemiş arama alarmları",
        "config": {
            "table": "search_alerts", "expires_col": "last_match_at",
            "max_age_days": 90, "condition": "last_match_at IS NOT NULL",
        },
    },
    {
        "name":        "live_streams_180d",
        "description": "6 aydan eski tamamlanmış yayın meta kayıtları",
        "config": {
            "table": "live_streams", "expires_col": "ended_at",
            "max_age_days": 180, "condition": "status = 'ended'",
        },
    },
    {
        "name":        "exchange_rates_365d",
        "description": "1 yıldan eski döviz kuru kayıtları",
        "config": {
            "table": "exchange_rates", "expires_col": "fetched_at", "max_age_days": 365,
        },
    },
    {
        "name":        "stream_recording_encode_queue",
        "description": "Encode bekleyen yayın kayıtları (stream bitti, encode başlamamış)",
        "config": {
            "table": "stream_recordings", "action_type": "trigger_encode",
            "status_col": "status", "ready_status": "encoding",
        },
    },
    {
        "name":        "stream_recording_transfer_queue",
        "description": "node1 MinIO'ya transfer bekleyen encode edilmiş kayıtlar",
        "config": {
            "table": "stream_recordings", "action_type": "trigger_transfer",
            "status_col": "status", "ready_status": "encoded",
        },
    },
]


class TTLJanitor:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg         = cfg
        self._db          = db
        self._initialized = False

    async def run(self, is_leader: bool) -> None:
        if not is_leader:
            return
        if not self._initialized:
            await self._seed_policies()
            self._initialized = True

        policies = await self._db.get_policies()
        for policy in policies:
            try:
                await self._eval_policy(policy)
            except Exception as exc:
                logger.error("Policy değerlendirme hatası | %s | %s", policy["name"], exc)

    async def _seed_policies(self) -> None:
        for p in _DEFAULT_POLICIES:
            await self._db.upsert_policy(p["name"], p["description"], p["config"])

    async def _eval_policy(self, policy: dict) -> None:
        cfg         = policy["config"]
        action_type = cfg.get("action_type")

        if action_type == "trigger_encode":
            await self._trigger_encode()
        elif action_type == "trigger_transfer":
            await self._trigger_transfer_check()
        else:
            await self._count_expired(policy)

    async def _count_expired(self, policy: dict) -> None:
        """Süresi dolmuş kayıt sayısını loglar. Gerçek silme cleanup_actions.sh ile."""
        cfg      = policy["config"]
        table    = cfg.get("table")
        col      = cfg.get("expires_col")
        max_days = cfg.get("max_age_days", 30)
        cond     = cfg.get("condition")

        if not table or (not col and not cond):
            return

        where_parts = []
        if col and max_days > 0:
            where_parts.append(f"{col} < NOW() - INTERVAL '{max_days} days'")
        if cond:
            where_parts.append(cond)
        where = " AND ".join(where_parts)

        try:
            import asyncpg
            dsn  = os.environ.get("PG_DSN", "")
            if not dsn:
                return
            conn = await asyncpg.connect(dsn=dsn)
            row  = await conn.fetchrow(f"SELECT COUNT(*) as cnt FROM {table} WHERE {where}")
            await conn.close()
            count = row["cnt"] if row else 0
            if count > 0:
                await self._db.log_cleanup(
                    policy["name"], table, "pending_delete",
                    f"{count} satır temizlenmeyi bekliyor", self._cfg.node_id,
                )
                logger.info("TTL bekleyen: %s — %d satır", policy["name"], count)
        except Exception as exc:
            logger.debug("TTL count başarısız | %s | %s", policy["name"], exc)

    async def _trigger_encode(self) -> None:
        """status='encoding' olan kayıtlar için encode sinyali yayınlar.
        encoder.py modülü (streaming node'da) bu sinyali dinler.
        Janitor fallback olarak çalışır — encoder.py zaten Redis'ten tetiklenir."""
        try:
            import aioredis
            r = await aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            await r.publish("teqlif:agent:encode_trigger", "1")
            await r.aclose()
            logger.info("Encode fallback trigger yayınlandı.")
        except Exception as exc:
            logger.debug("Encode trigger başarısız: %s", exc)

    async def _trigger_transfer_check(self) -> None:
        """status='encoded' kayıt varsa transfer sinyali yayınlar.
        Transfer penceresi (02:00-08:00 UTC) ve disk guard kontrolü
        encoder.py'nin transfer aşamasında yapılır."""
        try:
            import asyncpg
            dsn = os.environ.get("PG_DSN", "")
            if not dsn:
                return
            conn  = await asyncpg.connect(dsn=dsn)
            count = await conn.fetchval(
                "SELECT COUNT(*) FROM stream_recordings WHERE status = 'encoded'"
            )
            await conn.close()
            if not count:
                return
            import aioredis
            r = await aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            await r.publish("teqlif:agent:transfer_trigger", str(count))
            await r.aclose()
            logger.info("Transfer trigger: %d kayıt hazır.", count)
        except Exception as exc:
            logger.debug("Transfer trigger başarısız: %s", exc)
