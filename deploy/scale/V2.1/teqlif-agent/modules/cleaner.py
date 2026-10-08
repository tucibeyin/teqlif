"""teqlif-agent — Zamanlı PG Temizlik (Scheduled Cleaner).

Lider, UTC saat tablosuna göre her görevi günde bir kez çalıştırır.
Süresi dolmuş satırları siler; büyük temizliklerde Telegram bildirir.

Zamanlama (UTC — Türkiye UTC+3):
  00:00 → bildirimler 30d, hikayeler
  00:05 → analytics 90d, user_interactions 90d
  01:00 → listing_offers 60d, calls 90d, stream_viewers 90d
  02:00 → exchange_rates 1y, live_streams 6mo, search_alerts 90d
"""
from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone

from config import AgentConfig
from db import AgentDB
import telegram as tg

logger = logging.getLogger("teqlif-agent.cleaner")

# (utc_hour, utc_min, table, where_clause, label)
_SCHEDULE: list[tuple[int, int, str, str, str]] = [
    (0,  0,  "notifications",
     "created_at < NOW() - INTERVAL '30 days' AND is_read = true",
     "Bildirimler 30d"),

    (0,  2,  "stories",
     "expires_at < NOW()",
     "Hikayeler"),

    (0,  5,  "analytics_events",
     "created_at < NOW() - INTERVAL '90 days'",
     "Analytics 90d"),

    (0,  7,  "user_interactions",
     "created_at < NOW() - INTERVAL '90 days'",
     "User interactions 90d"),

    (1,  0,  "listing_offers",
     "updated_at < NOW() - INTERVAL '60 days' AND status IN ('declined','expired')",
     "Listing offers 60d"),

    (1, 10,  "live_stream_viewers",
     "left_at IS NOT NULL AND joined_at < NOW() - INTERVAL '3650 days'",
     "Stream viewers 10y"),

    (2,  0,  "exchange_rates",
     "fetched_at < NOW() - INTERVAL '365 days'",
     "Exchange rates 1y"),

    (2,  5,  "live_streams",
     "ended_at < NOW() - INTERVAL '180 days' AND status = 'ended'",
     "Live streams 6mo"),

    (2, 10,  "search_alerts",
     "last_match_at < NOW() - INTERVAL '90 days' AND last_match_at IS NOT NULL",
     "Search alerts 90d"),

    (2, 15,  "message_threads",
     "updated_at < NOW() - INTERVAL '180 days' AND message_count = 0",
     "Boş mesaj thread'leri 6mo"),

    (2, 20,  "listing_impressions",
     "seen_at < NOW() - INTERVAL '30 days'",
     "İlan gösterimleri 30d"),

    (3,  0,  "stream_recordings",
     "archived_at < NOW() - INTERVAL '15 days' AND status = 'archived'",
     "Yayın kayıtları 15d"),
]

_LARGE_BATCH = 5_000   # bu sayıyı geçen temizliklerde Telegram bildirir


class ScheduledCleaner:
    def __init__(self, cfg: AgentConfig, db: AgentDB) -> None:
        self._cfg  = cfg
        self._db   = db
        self._done: set[tuple[int, int]] = set()
        self._last_day: int = -1

    async def run(self, is_leader: bool) -> None:
        if not is_leader:
            return

        dsn = os.environ.get("PG_DSN", "")
        if not dsn:
            return

        now  = datetime.now(timezone.utc)
        day  = now.timetuple().tm_yday

        # Gün değişince tamamlanan slotları sıfırla
        if day != self._last_day:
            self._done.clear()
            self._last_day = day

        for utc_h, utc_m, table, where, label in _SCHEDULE:
            slot = (utc_h, utc_m)
            if slot in self._done:
                continue
            # Slot zamanı geçti mi?
            if now.hour > utc_h or (now.hour == utc_h and now.minute >= utc_m):
                await self._run_slot(dsn, table, where, label)
                self._done.add(slot)

    async def _run_slot(self, dsn: str, table: str, where: str, label: str) -> None:
        try:
            import asyncpg
            conn   = await asyncpg.connect(dsn=dsn)
            result = await conn.execute(f"DELETE FROM {table} WHERE {where}")
            await conn.close()

            count = int(result.split()[-1]) if result else 0
            if count == 0:
                return

            await self._db.log_cleanup(
                label, table, "scheduled_delete",
                f"{count} satır silindi", self._cfg.node_id,
            )
            logger.info("Cleaner: %s → %d satır silindi", label, count)

            if count >= _LARGE_BATCH:
                await tg.send(
                    self._cfg.telegram_bot_token,
                    self._cfg.telegram_chat_id,
                    f"🧹 <b>{self._cfg.node_id}</b> — {label}: {count:,} satır temizlendi",
                )

        except Exception as exc:
            logger.error("Cleaner hata | %s | %s", label, exc)
            await tg.send(
                self._cfg.telegram_bot_token,
                self._cfg.telegram_chat_id,
                f"❌ <b>{self._cfg.node_id}</b> — Cleaner hatası: {label}\n<code>{str(exc)[:120]}</code>",
            )
