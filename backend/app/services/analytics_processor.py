"""
Analytics Processor — ClickHouse → PostgreSQL bütçe hesabı.

calculate_user_budgets():
  Son 7 günün 'view' ve 'bid_hesitation' event'lerinden
  her kullanıcının 90. yüzdelik (p90) price_point değerini çeker
  ve PostgreSQL'deki User.max_budget kolonunu toplu günceller.

Çalıştırma zamanı: ARQ cron, her gece 02:00'da.
"""

import logging
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import AsyncSessionLocal
from app.database_clickhouse import get_clickhouse_client

logger = logging.getLogger(__name__)

# Bu event tipleri "kullanıcının bütçesiyle ilgilendiği" fiyatları temsil eder
_RELEVANT_EVENTS = ("view", "bid_hesitation", "dwell")


async def calculate_user_budgets() -> int:
    """
    ClickHouse'dan son 7 günün p90 price_point değerlerini çeker,
    PostgreSQL users tablosundaki max_budget kolonunu günceller.

    Döndürür: güncellenen kullanıcı sayısı
    """
    ch = await get_clickhouse_client()

    # Son 7 gün içinde anlamlı price_point içeren event'leri grupla
    query = """
        SELECT
            user_id,
            quantiles(0.90)(price_point)[1] AS p90_budget
        FROM user_events
        WHERE
            timestamp >= now() - INTERVAL 7 DAY
            AND event_type IN ('view', 'bid_hesitation', 'dwell')
            AND price_point > 0
            AND user_id IS NOT NULL
        GROUP BY user_id
        HAVING count() >= 3
        ORDER BY user_id
    """

    result = await ch.query(query)
    rows = result.result_rows  # list of (user_id, p90_budget)

    if not rows:
        logger.info("[BudgetCalc] ClickHouse'da uygun veri bulunamadı, atlandı.")
        return 0

    logger.info("[BudgetCalc] %d kullanıcı için p90 bütçe hesaplandı.", len(rows))

    # Bulk update PostgreSQL
    updated = 0
    async with AsyncSessionLocal() as db:
        for user_id_raw, p90 in rows:
            try:
                uid = int(user_id_raw)
                budget = float(p90)
                await db.execute(
                    text(
                        "UPDATE users SET max_budget = :budget WHERE id = :uid"
                    ),
                    {"budget": budget, "uid": uid},
                )
                updated += 1
            except Exception as row_exc:
                logger.warning(
                    "[BudgetCalc] user_id=%s güncellenemedi: %s", user_id_raw, row_exc
                )

        await db.commit()

    logger.info(
        "[BudgetCalc] Tamamlandı. PostgreSQL'de %d kullanıcı güncellendi.", updated
    )
    return updated
