import logging
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text as sql_text

from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.use_cases.analytics.hot_leads_use_case import HotLeadsUseCase
from app.use_cases.analytics.price_intel_use_case import PriceIntelUseCase
from app.use_cases.analytics.tips_use_case import TipsUseCase

logger = logging.getLogger(__name__)


class ProInsightsUseCase:
    """
    Pro Insights orkestratörü — 7 bölümün iş mantığını koordine eder:
    KPI · Funnel · Sıcak Talepler · Fiyat Zekası · Yayın · Pik Saatler · İpuçları
    """

    def __init__(
        self,
        db: AsyncSession,
        uid: int,
        t: dict,
        sd=None,
        ed=None,
    ):
        self.db = db
        self.uid = uid
        self.t = t
        self.sd = sd
        self.ed = ed

    async def execute(self) -> dict:
        now = datetime.now(timezone.utc)
        d30 = now - timedelta(days=30)
        d60 = now - timedelta(days=60)

        # ── 1. KPI'lar ────────────────────────────────────────────────────────
        kpis: dict = {}
        try:
            rows = await self.db.execute(sql_text("""
                SELECT
                    COUNT(*)                                                         AS total_listings,
                    COUNT(*) FILTER (WHERE status = 'active')             AS active_listings,
                    COALESCE(AVG(price) FILTER (WHERE status != 'deleted'), 0)            AS avg_price,
                    COUNT(*) FILTER (WHERE created_at >= :d30 AND status != 'deleted')    AS new_last_30d
                FROM listings WHERE user_id = :uid
            """), {"uid": self.uid, "d30": d30})
            lrow = rows.fetchone()

            sales_rows = await self.db.execute(sql_text("""
                SELECT
                    COUNT(*)                                                            AS total_sales,
                    COALESCE(SUM(p.price), 0)                                             AS total_revenue,
                    COALESCE(SUM(p.price) FILTER (WHERE p.created_at >= :d30), 0)           AS revenue_30d,
                    COALESCE(SUM(p.price) FILTER (WHERE p.created_at >= :d60
                                                 AND p.created_at < :d30), 0)             AS revenue_prev_30d,
                    COUNT(*) FILTER (WHERE p.created_at >= :d30)                          AS sales_30d
                FROM purchases p
                JOIN listings l ON l.id = p.listing_id
                WHERE p.buyer_id != :uid
                  AND l.user_id = :uid
            """), {"uid": self.uid, "d30": d30, "d60": d60})
            srow = sales_rows.fetchone()

            rev_30 = float(srow.revenue_30d or 0)
            rev_prev = float(srow.revenue_prev_30d or 0)
            rev_growth = round(((rev_30 - rev_prev) / rev_prev) * 100, 1) if rev_prev > 0 else None

            bid_rows = await self.db.execute(sql_text("""
                SELECT COUNT(*) AS total_bids
                FROM bids b
                JOIN auctions a ON a.stream_id = b.stream_id
                JOIN listings l ON l.id = a.listing_id
                WHERE l.user_id = :uid AND b.created_at >= :d30
            """), {"uid": self.uid, "d30": d30})
            brow = bid_rows.fetchone()

            kpis = {
                "total_listings": int(lrow.total_listings or 0),
                "active_listings": int(lrow.active_listings or 0),
                "avg_listing_price": round(float(lrow.avg_price or 0), 2),
                "total_sales": int(srow.total_sales or 0),
                "total_revenue": round(float(srow.total_revenue or 0), 2),
                "revenue_30d": round(rev_30, 2),
                "revenue_growth_pct": rev_growth,
                "sales_30d": int(srow.sales_30d or 0),
                "bids_30d": int(brow.total_bids or 0),
            }
        except Exception as exc:
            logger.warning("[ProInsightsUseCase] kpis başarısız: %s", exc)
            await self.db.rollback()

        # ── 2. Dönüşüm Hunisi ─────────────────────────────────────────────────
        listing_ids: list[int] = []
        funnel: dict = {}
        try:
            listing_ids_result = await self.db.execute(
                select(Listing.id).where(
                    Listing.user_id == self.uid,
                    Listing.status != ListingStatus.DELETED,
                )
            )
            listing_ids = [r[0] for r in listing_ids_result.fetchall()]

            views_total = 0
            dwells_total = 0
            hesitations = 0

            if listing_ids:
                ids_str = ", ".join(str(i) for i in listing_ids)
                try:
                    from app.database_clickhouse import get_clickhouse_client
                    ch = await get_clickhouse_client()
                    ch_r = await ch.query(f"""
                        SELECT
                            countIf(event_type = 'view')              AS views,
                            countIf(event_type = 'detail_dwell')      AS dwells,
                            countDistinctIf(user_id, event_type = 'bid_hesitation') AS hesitations
                        FROM user_events
                        WHERE item_type = 'listing'
                          AND item_id IN ({ids_str})
                          AND timestamp >= now() - INTERVAL 30 DAY
                    """)
                    r = ch_r.result_rows[0] if ch_r.result_rows else (0, 0, 0)
                    views_total = int(r[0] or 0)
                    dwells_total = int(r[1] or 0)
                    hesitations = int(r[2] or 0)
                except Exception:
                    pass

            bids_count = kpis.get("bids_30d", 0)
            sales_count = kpis.get("sales_30d", 0)
            funnel = {
                "views": views_total,
                "dwells": dwells_total,
                "hesitations": hesitations,
                "bids": bids_count,
                "sales": sales_count,
                "view_to_bid_pct": round((bids_count / views_total) * 100, 1) if views_total > 0 else 0,
                "bid_to_sale_pct": round((sales_count / bids_count) * 100, 1) if bids_count > 0 else 0,
            }
        except Exception as exc:
            logger.warning("[ProInsightsUseCase] funnel başarısız: %s", exc)
            await self.db.rollback()

        # ── 3 & 4 — Sıcak Talepler + Fiyat Zekası ────────────────────────────
        # AsyncSession paylaşıldığı için sıralı çalıştırılıyor (concurrent güvenli değil)
        hot_leads = await HotLeadsUseCase(db=self.db, uid=self.uid, sd=self.sd, ed=self.ed, t=self.t).execute()
        price_intel = await PriceIntelUseCase(db=self.db, uid=self.uid, sd=self.sd, ed=self.ed).execute()

        # ── 5. Yayın Performansı ──────────────────────────────────────────────
        stream_stats: dict = {}
        try:
            s_rows = await self.db.execute(sql_text("""
                SELECT
                    COUNT(*)                                              AS total_streams,
                    COALESCE(AVG(viewer_count), 0)                       AS avg_viewers,
                    COALESCE(MAX(viewer_count), 0)                       AS peak_viewers,
                    COALESCE(AVG(EXTRACT(EPOCH FROM (ended_at - started_at))/60), 0) AS avg_duration_min,
                    COUNT(*) FILTER (WHERE started_at >= :d30)           AS streams_30d
                FROM live_streams
                WHERE host_id = :uid AND is_live = false AND ended_at IS NOT NULL
            """), {"uid": self.uid, "d30": d30})
            sr = s_rows.fetchone()

            best_r = await self.db.execute(sql_text("""
                SELECT ls.title, ls.viewer_count,
                       ROUND(EXTRACT(EPOCH FROM (ls.ended_at - ls.started_at))/60) AS dur_min,
                       COUNT(b.id) AS bid_count
                FROM live_streams ls
                LEFT JOIN auctions a ON a.stream_id = ls.id
                LEFT JOIN bids b ON b.stream_id = a.stream_id
                WHERE ls.host_id = :uid AND ls.is_live = false AND ls.ended_at IS NOT NULL
                GROUP BY ls.id, ls.title, ls.viewer_count, ls.started_at, ls.ended_at
                ORDER BY ls.viewer_count DESC, bid_count DESC
                LIMIT 3
            """), {"uid": self.uid})
            best_streams = [
                {"title": r.title, "viewers": r.viewer_count, "duration_min": int(r.dur_min or 0), "bids": r.bid_count}
                for r in best_r.fetchall()
            ]

            stream_stats = {
                "total_streams": int(sr.total_streams or 0),
                "streams_30d": int(sr.streams_30d or 0),
                "avg_viewers": round(float(sr.avg_viewers or 0), 1),
                "peak_viewers": int(sr.peak_viewers or 0),
                "avg_duration_min": round(float(sr.avg_duration_min or 0), 1),
                "best_streams": best_streams,
            }
        except Exception as exc:
            logger.warning("[ProInsightsUseCase] stream_stats başarısız: %s", exc)
            await self.db.rollback()

        # ── 6. Pik Saatler ────────────────────────────────────────────────────
        peak_hours: list[dict] = []
        try:
            if listing_ids:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                _ph_ids_str = ", ".join(str(i) for i in listing_ids)
                ph_r = await ch.query(f"""
                    SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
                    FROM user_events
                    WHERE timestamp >= now() - INTERVAL 30 DAY
                      AND event_type IN ('view','detail_dwell','bid_hesitation')
                      AND item_type = 'listing'
                      AND item_id IN ({_ph_ids_str})
                    GROUP BY hr ORDER BY cnt DESC LIMIT 5
                """)
                peak_hours = [
                    {"hour": int(r[0]), "count": int(r[1]),
                     "label": f"{int(r[0]):02d}:00–{int(r[0])+1:02d}:00"}
                    for r in ph_r.result_rows
                ]
        except Exception as exc:
            logger.warning("[ProInsightsUseCase] peak_hours başarısız: %s", exc)

        # ── 7. Akıllı Öneriler ────────────────────────────────────────────────
        tips = await TipsUseCase(
            hot_leads=hot_leads,
            price_intel=price_intel,
            funnel=funnel,
            peak_hours=peak_hours,
            t=self.t,
            db=self.db,
            uid=self.uid,
        ).execute()

        return {
            "kpis": kpis,
            "funnel": funnel,
            "hot_leads": hot_leads,
            "price_intel": price_intel,
            "stream_stats": stream_stats,
            "peak_hours": peak_hours,
            "tips": tips,
        }
