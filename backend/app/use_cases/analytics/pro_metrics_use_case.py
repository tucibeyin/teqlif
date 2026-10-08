import logging
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text as sql_text

logger = logging.getLogger(__name__)


class ProMetricsUseCase:
    """
    PRO gelişmiş metrikler — T-1 analitik (gece batch'te hesaplanır, node1 Redis'ten servis edilir).

    Metrikler:
    - avg_detail_dwell_seconds : ilan detay sayfasında ortalama kalış süresi (CH)
    - search_visibility        : kullanıcının ilan kategorilerindeki arama hacmi (CH)
    - best_posting_hour        : en yüksek CTR'a sahip ilan paylaşım saati (CH)
    - return_viewer_rate_pct   : en az 2 kez yayın izleyen kullanıcı oranı (PG)
    """

    def __init__(self, db: AsyncSession, uid: int):
        self.db = db
        self.uid = uid

    async def execute(self) -> dict:
        avg_dwell = None
        search_visibility: list[dict] = []
        best_hour = None
        return_viewer_rate = None
        return_viewer_count = 0
        total_viewer_count = 0

        # ── 1. Aktif ilanlar (PG) ──────────────────────────────────────────────
        listings_result = await self.db.execute(sql_text("""
            SELECT id, category, EXTRACT(HOUR FROM created_at) AS hr
            FROM listings
            WHERE user_id = :uid AND status = 'active'
        """), {"uid": self.uid})
        active_listings = listings_result.fetchall()

        listing_ids = [str(r.id) for r in active_listings]
        categories = list({r.category for r in active_listings if r.category})

        # ── 2. ClickHouse sorgular (listing varsa) ────────────────────────────
        if listing_ids:
            ids_str = ",".join(listing_ids)
            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()

                # avg_detail_dwell
                dwell = await ch.query(f"""
                    SELECT AVG(duration_seconds)
                    FROM user_events
                    WHERE item_type = 'listing'
                      AND item_id IN ({ids_str})
                      AND event_type = 'detail_dwell'
                      AND timestamp >= now() - INTERVAL 30 DAY
                """)
                if dwell.result_rows and dwell.result_rows[0][0] is not None:
                    avg_dwell = round(float(dwell.result_rows[0][0]), 1)

                # search_visibility
                if categories:
                    cats_str = ",".join(f"'{c}'" for c in categories)
                    search = await ch.query(f"""
                        SELECT category, count(*) AS search_count
                        FROM search_events
                        WHERE category IN ({cats_str})
                          AND timestamp >= now() - INTERVAL 30 DAY
                        GROUP BY category
                        ORDER BY search_count DESC
                        LIMIT 5
                    """)
                    search_visibility = [
                        {"category": r[0], "search_count": int(r[1])}
                        for r in search.result_rows
                    ]

                # best_posting_hour
                stats = await ch.query(f"""
                    SELECT item_id,
                           countIf(event_type = 'view')  AS views,
                           countIf(event_type = 'click') AS clicks
                    FROM user_events
                    WHERE item_type = 'listing'
                      AND item_id IN ({ids_str})
                      AND timestamp >= now() - INTERVAL 90 DAY
                    GROUP BY item_id
                """)
                item_hour_map = {int(r.id): int(r.hr) for r in active_listings}
                hour_stats: dict[int, dict] = {}
                for row in stats.result_rows:
                    hr = item_hour_map.get(int(row[0]))
                    if hr is None:
                        continue
                    bucket = hour_stats.setdefault(hr, {"views": 0, "clicks": 0})
                    bucket["views"] += int(row[1])
                    bucket["clicks"] += int(row[2])

                best_ctr = -1.0
                for hr, s in hour_stats.items():
                    if s["views"] >= 10:
                        ctr = s["clicks"] / s["views"]
                        if ctr > best_ctr:
                            best_ctr = ctr
                            best_hour = hr

            except Exception as exc:
                logger.warning("[ProMetricsUseCase] ClickHouse sorgusu başarısız uid=%d: %s", self.uid, exc)

        # ── 3. Geri dönen izleyici oranı (PG) ────────────────────────────────
        try:
            ret = await self.db.execute(sql_text("""
                WITH viewer_counts AS (
                    SELECT lsv.user_id, COUNT(DISTINCT ls.id) AS stream_count
                    FROM live_stream_viewers lsv
                    INNER JOIN live_streams ls ON ls.id = lsv.stream_id AND ls.host_id = :uid
                    WHERE lsv.user_id != :uid
                      AND lsv.joined_at >= NOW() - INTERVAL '180 days'
                    GROUP BY lsv.user_id
                )
                SELECT
                    COUNT(*) FILTER (WHERE stream_count >= 2)::float /
                        NULLIF(COUNT(*), 0)                        AS return_rate,
                    COUNT(*)                                        AS total_viewers,
                    COUNT(*) FILTER (WHERE stream_count >= 2)      AS return_viewers
                FROM viewer_counts
            """), {"uid": self.uid})
            row = ret.fetchone()
            if row and row[0] is not None:
                return_viewer_rate = round(float(row[0]) * 100, 1)
                total_viewer_count = int(row[1])
                return_viewer_count = int(row[2])
        except Exception as exc:
            logger.warning("[ProMetricsUseCase] PG return_viewer sorgusu başarısız uid=%d: %s", self.uid, exc)

        return {
            "avg_detail_dwell_seconds": avg_dwell,
            "search_visibility": search_visibility,
            "best_posting_hour": best_hour,
            "return_viewer_rate_pct": return_viewer_rate,
            "return_viewer_count": return_viewer_count,
            "total_viewer_count": total_viewer_count,
        }
