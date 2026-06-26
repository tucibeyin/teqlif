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

async def calculate_user_budgets() -> int:
    """
    ClickHouse'dan p90 price_point değerlerini çeker,
    PostgreSQL users tablosundaki max_budget kolonunu günceller.

    auction_won olayları 3× ağırlıklı sayılır: gerçek ödeme = en güvenilir bütçe sinyali.
    Diğer olaylar (view, bid_hesitation, dwell) son 7 gün; auction_won son 90 gün.

    Döndürür: güncellenen kullanıcı sayısı
    """
    ch = await get_clickhouse_client()

    # auction_won: 90 günlük pencere, 3× ağırlık (UNION ALL ile çoğaltılır)
    # diğerleri: 7 günlük pencere, 1× ağırlık
    query = """
        SELECT
            user_id,
            quantiles(0.90)(price_point)[1] AS p90_budget
        FROM (
            SELECT user_id, price_point
            FROM user_events
            WHERE timestamp >= now() - INTERVAL 7 DAY
              AND event_type IN ('view', 'bid_hesitation', 'dwell')
              AND price_point > 0
              AND user_id IS NOT NULL
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id IS NOT NULL
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id IS NOT NULL
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id IS NOT NULL
        )
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
