"""teqlif-agent — Sabah raporu.

Her gün 07:00 UTC (10:00 TR) lider node'dan Telegram'a tek mesaj gönderir.
Node sağlığı · gece batch işleri · yedek durumu özetlenir.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.reporter")

_REPORT_UTC_HOUR = 7   # 10:00 TR

# Gece batch penceresi (01:50-06:30 UTC) — günlük job'lar
_DAILY_BATCH_JOBS: list[str] = [
    "sync_pg_to_clickhouse_task",
    "compute_analytics_cache_task",
    "precompute_premium_user_analytics_task",
    "cleanup_old_notifications_task",
    "cleanup_old_stream_likes_task",
    "compute_seller_badges_task",
    "calculate_user_budgets_task",
    "compute_trust_scores_task",
    "compute_user_interests_task",
    "compute_trending_categories_task",
    "compute_user_condition_preferences_task",
    "populate_foryou_feed_task",
    "compute_trending_listings_task",
    "process_churn_and_airdrop",
    "optimize_notification_timing_task",
    "deactivate_expired_listings_task",
    "delete_expired_inactive_listings_task",
    "cleanup_old_impressions_task",
    "rebuild_faiss_index_task",
    "nsfw_backfill_task",
    "backfill_listing_embeddings_task",
    "hesitation_retarget_task",
    "cleanup_old_media_messages_task",
    "cleanup_hidden_messages_task",
]

_BACKUP_JOBS: list[tuple[str, str]] = [
    ("pg_dump",           "PG dump"),
    ("clickhouse_backup", "ClickHouse"),
    ("redis_backup",      "Redis"),
    ("minio_backup",      "MinIO"),
    ("mail_backup",       "Mail"),
]

_TR_MONTHS = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
               "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]

_TR_TZ = timezone(timedelta(hours=3))


class MorningReporter:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg = cfg
        self._db  = db

    async def run(self, is_leader: bool) -> None:
        if not is_leader:
            return
        now_utc = datetime.now(timezone.utc)
        if now_utc.hour != _REPORT_UTC_HOUR:
            return
        today     = now_utc.date()
        redis_key = f"teqlif:agent:morning_reported:{today.isoformat()}"
        try:
            import redis.asyncio as _aioredis
            r = await _aioredis.from_url(self._cfg.redis_url, decode_responses=True)
            already_sent = await r.exists(redis_key)
            if already_sent:
                await r.aclose()
                return
            # SET NX: sadece ilk çağıran kazanır (birden fazla restart olsa da tek rapor)
            set_ok = await r.set(redis_key, "1", nx=True, ex=90000)  # 25 saat TTL
            await r.aclose()
            if not set_ok:
                return  # başka bir instance daha hızlı davrandı
        except Exception:
            logger.warning("Redis morning-lock kontrol edilemedi — tek seferlik fallback")
        try:
            await self._send_report(now_utc)
        except Exception:
            logger.exception("Sabah raporu gönderilemedi")

    async def _send_report(self, now_utc: datetime) -> None:
        node_states = await self._db.get_all_node_states()
        job_health  = await self._db.get_all_job_health()
        job_map     = {r["job_name"]: r for r in job_health}

        tr_dt   = now_utc.astimezone(_TR_TZ)
        tr_date = f"{tr_dt.day} {_TR_MONTHS[tr_dt.month - 1]} {tr_dt.year}"
        lines   = [f"🌅 <b>Sabah Raporu — {tr_date}</b>"]

        # ── Node'lar ──────────────────────────────────────────────────────────
        offline_nodes, node_lines = 0, []
        for ns in node_states:
            nid   = ns["node_id"]
            m     = ns.get("metrics", {})
            age_m = _age_minutes(ns.get("seen_at", ""))
            if age_m is None or age_m > 10:
                offline_nodes += 1
                since = f"{age_m} dk" if age_m is not None else "?"
                node_lines.append(f"  🔴 <code>{nid}</code> — yanıt yok ({since})")
            else:
                cpu  = m.get("cpu_percent",  "?")
                ram  = m.get("ram_percent",  "?")
                disk = m.get("disk_percent", "?")
                node_lines.append(
                    f"  ✅ <code>{nid}</code>  CPU {cpu}%  RAM {ram}%  Disk {disk}%"
                )
        online = len(node_states) - offline_nodes
        lines.append(f"\n📡 <b>Node'lar ({online}/{len(node_states)} aktif)</b>")
        lines.extend(node_lines)

        # ── Batch İşleri ─────────────────────────────────────────────────────
        ok_jobs, fail_jobs = [], []
        for jname in _DAILY_BATCH_JOBS:
            row   = job_map.get(jname)
            age_m = _age_minutes(row["last_ok_at"]) if row and row.get("last_ok_at") else None
            max_m = row["expected_every_m"] if row else 1440
            if age_m is not None and age_m < max_m:
                ok_jobs.append(jname)
            else:
                last = row["last_ok_at"] if row and row.get("last_ok_at") else None
                fail_jobs.append((jname, last))

        total_b = len(_DAILY_BATCH_JOBS)
        lines.append(f"\n⚙️ <b>Batch İşleri ({len(ok_jobs)}/{total_b} OK)</b>")
        if fail_jobs:
            for jname, last in fail_jobs:
                last_str = _fmt_ts(last) if last else "hiç çalışmadı"
                lines.append(f"  ⚠️ <code>{jname}</code> — son OK: {last_str}")
        else:
            lines.append("  Tüm batch işler tamamlandı ✔")

        # ── Yedekler ──────────────────────────────────────────────────────────
        lines.append("\n💾 <b>Yedekler</b>")
        for key, label in _BACKUP_JOBS:
            row   = job_map.get(key)
            age_m = _age_minutes(row["last_ok_at"]) if row and row.get("last_ok_at") else None
            max_m = row["expected_every_m"] if row else 1500
            if age_m is not None and age_m < max_m:
                lines.append(f"  ✅ {label} — {_fmt_ts(row['last_ok_at'])}")
            elif age_m is not None:
                lines.append(f"  ⚠️ {label} — eski ({_fmt_ts(row['last_ok_at'])})")
            else:
                lines.append(f"  ❓ {label} — kayıt yok")

        await tg.send(
            self._cfg.telegram_bot_token,
            self._cfg.telegram_chat_id,
            "\n".join(lines),
        )
        logger.info(
            "Sabah raporu: %d/%d node aktif, %d/%d batch OK",
            online, len(node_states), len(ok_jobs), total_b,
        )


def _age_minutes(ts: str | None) -> int | None:
    if not ts:
        return None
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return int((datetime.now(timezone.utc) - dt).total_seconds() / 60)
    except Exception:
        return None


def _fmt_ts(ts: str | None) -> str:
    if not ts:
        return "?"
    try:
        dt    = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        tr_dt = dt.astimezone(_TR_TZ)
        age_m = int((datetime.now(timezone.utc) - dt).total_seconds() / 60)
        if age_m < 60:
            age_str = f"{age_m}dk"
        elif age_m < 1440:
            age_str = f"{age_m // 60}s"
        else:
            age_str = f"{age_m // 1440}g"
        return f"{tr_dt.strftime('%H:%M')} ({age_str} önce)"
    except Exception:
        return ts
