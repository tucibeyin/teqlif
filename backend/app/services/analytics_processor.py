"""
Analytics Processor — ClickHouse → PostgreSQL bütçe hesabı.

calculate_user_budgets():
  Son 7 günün 'view' ve 'bid_hesitation' event'lerinden
  her kullanıcının 90. yüzdelik (p90) price_point değerini çeker
  ve PostgreSQL'deki User.max_budget kolonunu toplu günceller.

Çalıştırma zamanı: ARQ cron, her gece 02:00'da.

Mimari not: tek uzun transaction yerine 500'lük bağımsız chunk'lar.
  - Her chunk: tek SET-BASED UPDATE (500 round-trip → 1 round-trip)
  - Her chunk kendi transaction'ını commit eder (lock süresi <1ms)
  - Bir chunk hata alırsa geri kalanlar çalışmaya devam eder
"""

import logging
import math

from sqlalchemy import text

from app.database import AsyncSessionLocal
from app.database_clickhouse import get_clickhouse_client

logger = logging.getLogger(__name__)

_CHUNK_SIZE = 500
_MAX_BUDGET_CAP = 9_999_999_999.99   # NUMERIC(12, 2) tavanı
_MAX_USER_ID    = 2_147_483_647       # 32-bit INT üst sınırı


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
              AND user_id != 0
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id != 0
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id != 0
            UNION ALL
            SELECT user_id, price_point FROM user_events
            WHERE timestamp >= now() - INTERVAL 90 DAY
              AND event_type = 'auction_won'
              AND price_point > 0 AND user_id != 0
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

    updated = 0
    total_chunks = math.ceil(len(rows) / _CHUNK_SIZE)

    for chunk_idx in range(total_chunks):
        chunk = rows[chunk_idx * _CHUNK_SIZE : (chunk_idx + 1) * _CHUNK_SIZE]

        # Geçersiz değerleri filtrele: NaN/Inf, taşma ve 32-bit INT dışı uid
        valid: list[tuple[int, float]] = []
        for uid_raw, p90_raw in chunk:
            try:
                uid = int(uid_raw)
                budget = float(p90_raw)
                if (
                    0 < uid <= _MAX_USER_ID
                    and math.isfinite(budget)
                    and budget > 0
                ):
                    valid.append((uid, min(round(budget, 2), _MAX_BUDGET_CAP)))
            except (ValueError, TypeError) as e:
                logger.warning("[BudgetCalc] Geçersiz satır atlandı | uid=%s p90=%s | %s", uid_raw, p90_raw, e)

        if not valid:
            continue

        # SET-BASED UPDATE: 500 satır → tek round-trip, tek kısa transaction
        # int() ve float() cast SQL injection'ı engeller
        values_str = ", ".join(f"({uid}, {budget:.2f})" for uid, budget in valid)
        try:
            async with AsyncSessionLocal() as db:
                res = await db.execute(text(f"""
                    UPDATE users AS u
                    SET max_budget = v.budget
                    FROM (VALUES {values_str}) AS v(id, budget)
                    WHERE u.id = v.id
                """))
                await db.commit()
            # rowcount: PG'den silinmiş uid'leri düşerek gerçek güncellenen satırı sayar
            updated += res.rowcount if (res.rowcount or -1) >= 0 else len(valid)
        except Exception as chunk_exc:
            logger.error(
                "[BudgetCalc] Chunk %d/%d güncellenemedi (offset=%d): %s",
                chunk_idx + 1, total_chunks, chunk_idx * _CHUNK_SIZE, chunk_exc,
            )

    logger.info(
        "[BudgetCalc] Tamamlandı. PostgreSQL'de %d/%d kullanıcı güncellendi.",
        updated, len(rows),
    )
    return updated
