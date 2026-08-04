import logging
import time as _time_mod
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text as sql_text
from app.models.listing import Listing
from app.models.enums import ListingStatus
from app.models.ad_campaign import AdCampaign
from sqlalchemy import func

logger = logging.getLogger(__name__)


class HotLeadsUseCase:
    """
    Satıcının aktif ilanları arasından en sıcak talepleri hesaplar.
    Heat score = (views*1 + likes*2 + dwells*2 + hesitations*3) / (age_hours+2)^1.2
    """

    def __init__(self, db: AsyncSession, uid: int, sd=None, ed=None, t: dict | None = None):
        self.db = db
        self.uid = uid
        self.sd = sd
        self.ed = ed
        self.t = t or {}

    async def execute(self) -> list[dict]:
        hot_leads: list[dict] = []
        try:
            _hl_q = (
                select(Listing.id, Listing.title, Listing.price, Listing.category)
                .where(Listing.user_id == self.uid, Listing.status == ListingStatus.ACTIVE)
            )
            if self.sd:
                _hl_q = _hl_q.where(Listing.created_at >= self.sd)
            if self.ed:
                _hl_q = _hl_q.where(Listing.created_at < self.ed)
            active_ids_r = await self.db.execute(
                _hl_q.order_by(func.coalesce(Listing.reactivated_at, Listing.created_at).desc()).limit(50)
            )
            active_listings = active_ids_r.fetchall()
            if not active_listings:
                return []

            ids_str = ", ".join(str(r.id) for r in active_listings)
            view_map: dict[int, int] = {r.id: 0 for r in active_listings}
            dwell_map: dict[int, int] = {r.id: 0 for r in active_listings}
            hes_map: dict[int, int] = {r.id: 0 for r in active_listings}
            ts_map: dict[int, float] = {}
            like_map: dict[int, int] = {}

            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                ch_r = await ch.query(f"""
                    SELECT item_id,
                           countIf(event_type = 'view') AS views,
                           countIf(event_type = 'detail_dwell') AS dwells,
                           countDistinctIf(user_id, event_type = 'bid_hesitation') AS hes,
                           toUnixTimestamp(max(timestamp)) AS last_event_ts
                    FROM user_events
                    WHERE item_type = 'listing' AND item_id IN ({ids_str})
                      AND timestamp >= now() - INTERVAL 30 DAY
                    GROUP BY item_id
                """)
                view_map  = {int(r[0]): int(r[1]) for r in ch_r.result_rows}
                dwell_map = {int(r[0]): int(r[2]) for r in ch_r.result_rows}
                hes_map   = {int(r[0]): int(r[3]) for r in ch_r.result_rows}
                ts_map    = {int(r[0]): float(r[4]) for r in ch_r.result_rows}
            except Exception:
                pass

            try:
                like_r = await self.db.execute(sql_text("""
                    SELECT listing_id, COUNT(*)::int FROM listing_likes
                    WHERE listing_id = ANY(:ids) AND created_at >= NOW() - INTERVAL '30 days'
                    GROUP BY listing_id
                """), {"ids": [r.id for r in active_listings]})
                like_map = {row[0]: row[1] for row in like_r.fetchall()}
            except Exception:
                await self.db.rollback()

            boost_ids: set[int] = set()
            try:
                boost_r = await self.db.execute(
                    select(AdCampaign.listing_id).where(
                        AdCampaign.listing_id.in_([r.id for r in active_listings]),
                        AdCampaign.status == "active",
                    )
                )
                boost_ids = {row[0] for row in boost_r.fetchall()}
            except Exception:
                pass

            _now_ts = _time_mod.time()

            def _heat(lid: int) -> float:
                age_h = max((_now_ts - ts_map.get(lid, _now_ts)) / 3600, 0.0)
                raw = (
                    view_map.get(lid, 0)  * 1 +
                    like_map.get(lid, 0)  * 2 +
                    dwell_map.get(lid, 0) * 2 +
                    hes_map.get(lid, 0)   * 3
                )
                return raw / (age_h + 2) ** 1.2

            scored = sorted(active_listings, key=lambda r: _heat(r.id), reverse=True)[:5]
            hot_leads = [
                {
                    "listing_id": r.id,
                    "title": r.title,
                    "price": r.price,
                    "category": r.category or "other",
                    "views_30d": view_map.get(r.id, 0),
                    "hesitations_30d": hes_map.get(r.id, 0),
                    "heat_score": round(_heat(r.id), 2),
                    "is_boosted": r.id in boost_ids,
                }
                for r in scored
            ]
        except Exception as exc:
            logger.warning("[HotLeadsUseCase] başarısız: %s", exc)
            await self.db.rollback()
        return hot_leads
