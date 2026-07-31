import logging
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text as sql_text
from app.models.listing import Listing
from app.models.enums import ListingStatus

logger = logging.getLogger(__name__)


class PriceIntelUseCase:
    """
    Satıcının ilanlarını pgvector ile benzer ilanlarla karşılaştırır.
    Sinyal: pahalı / ucuz / uygun
    """

    def __init__(self, db: AsyncSession, uid: int, sd=None, ed=None):
        self.db = db
        self.uid = uid
        self.sd = sd
        self.ed = ed

    async def execute(self) -> list[dict]:
        price_intel: list[dict] = []
        try:
            _pi_q = (
                select(Listing.id, Listing.title, Listing.price, Listing.category, Listing.embedding)
                .where(
                    Listing.user_id == self.uid,
                    Listing.status == ListingStatus.ACTIVE,
                    Listing.price.is_not(None),
                )
            )
            if self.sd:
                _pi_q = _pi_q.where(Listing.created_at >= self.sd)
            if self.ed:
                _pi_q = _pi_q.where(Listing.created_at < self.ed)
            my_listings_r = await self.db.execute(_pi_q.order_by(Listing.price.desc()).limit(10))
            my_listings = my_listings_r.fetchall()

            for ml in my_listings:
                market_avg: float | None = None
                price_stddev: float | None = None
                price_lo = float(ml.price) * 0.4
                price_hi = float(ml.price) * 2.5

                if ml.embedding is not None:
                    try:
                        emb_str = "[" + ",".join(f"{x:.6f}" for x in ml.embedding) + "]"
                        sim_r = await self.db.execute(sql_text("""
                            SELECT AVG(price), STDDEV(price) FROM (
                                SELECT price FROM listings
                                WHERE user_id != :uid
                                  AND category = :cat
                                  AND status = 'active'
                                  AND price > :lo AND price < :hi
                                  AND embedding IS NOT NULL
                                ORDER BY embedding <=> CAST(:emb AS vector)
                                LIMIT 10
                            ) sub
                        """), {"uid": self.uid, "emb": emb_str, "cat": ml.category,
                               "lo": price_lo, "hi": price_hi})
                        _sim_row = sim_r.fetchone()
                        market_avg = _sim_row[0] if _sim_row else None
                        price_stddev = _sim_row[1] if _sim_row else None
                    except Exception:
                        await self.db.rollback()

                if market_avg is None:
                    cat_r = await self.db.execute(sql_text("""
                        SELECT AVG(price), STDDEV(price) FROM listings
                        WHERE category = :cat AND user_id != :uid
                          AND status = 'active'
                          AND price > :lo AND price < :hi
                    """), {"cat": ml.category, "uid": self.uid,
                           "lo": price_lo, "hi": price_hi})
                    _cat_row = cat_r.fetchone()
                    market_avg = _cat_row[0] if _cat_row else None
                    price_stddev = _cat_row[1] if _cat_row else None

                if market_avg and market_avg > 0:
                    diff_pct = round(((ml.price - market_avg) / market_avg) * 100, 1)
                    _threshold = (
                        max(min((price_stddev / market_avg) * 100, 40.0), 10.0)
                        if price_stddev else 15.0
                    )
                    signal = "pahalı" if diff_pct > _threshold else ("ucuz" if diff_pct < -_threshold else "uygun")
                    price_intel.append({
                        "listing_id": ml.id,
                        "title": ml.title,
                        "your_price": ml.price,
                        "market_avg": round(float(market_avg), 2),
                        "diff_pct": diff_pct,
                        "signal": signal,
                    })
        except Exception as exc:
            logger.warning("[PriceIntelUseCase] başarısız: %s", exc)
            await self.db.rollback()
        return price_intel
