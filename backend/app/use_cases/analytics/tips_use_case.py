import logging
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text as sql_text

logger = logging.getLogger(__name__)


class TipsUseCase:
    """
    Kural motoru — hot_leads, price_intel, funnel ve peak_hours verilerinden
    satıcıya özel akıllı öneriler üretir.
    """

    def __init__(
        self,
        hot_leads: list[dict],
        price_intel: list[dict],
        funnel: dict,
        peak_hours: list[dict],
        t: dict,
        db: AsyncSession,
        uid: int,
    ):
        self.hot_leads = hot_leads
        self.price_intel = price_intel
        self.funnel = funnel
        self.peak_hours = peak_hours
        self.t = t
        self.db = db
        self.uid = uid

    async def execute(self) -> list[dict]:
        tips: list[dict] = []
        try:
            t = self.t

            overpriced = [p for p in self.price_intel if p["signal"] == "pahalı"]
            underpriced = [p for p in self.price_intel if p["signal"] == "ucuz"]

            if overpriced:
                _body = t.get("proTipPriceDownBody", "")
                if _body:
                    tips.append({
                        "icon": "💰", "type": "price",
                        "title": t.get("proTipPriceDownTitle", ""),
                        "body": _body.format(
                            title=overpriced[0]["title"],
                            diff=abs(overpriced[0]["diff_pct"]),
                            avg=int(overpriced[0]["market_avg"]),
                        ),
                    })

            if underpriced:
                _body = t.get("proTipPriceUpBody", "")
                if _body:
                    tips.append({
                        "icon": "🚀", "type": "price_up",
                        "title": t.get("proTipPriceUpTitle", ""),
                        "body": _body.format(
                            title=underpriced[0]["title"],
                            diff=abs(underpriced[0]["diff_pct"]),
                            avg=int(underpriced[0]["market_avg"]),
                        ),
                    })

            if self.hot_leads and self.hot_leads[0].get("hesitations_30d", 0) > 0:
                _body = t.get("proTipLeadBody", "")
                if _body:
                    tips.append({
                        "icon": "🎯", "type": "lead",
                        "title": t.get("proTipLeadTitle", ""),
                        "body": _body.format(
                            title=self.hot_leads[0]["title"],
                            count=self.hot_leads[0]["hesitations_30d"],
                        ),
                    })

            # Tereddüt fiyat noktası önerisi
            try:
                seller_lid_rows = await self.db.execute(sql_text(
                    "SELECT id, title, price FROM listings WHERE user_id = :uid AND status = 'active' LIMIT 20"
                ), {"uid": self.uid})
                seller_listings = {
                    r.id: {"title": r.title, "price": float(r.price or 0)}
                    for r in seller_lid_rows.fetchall()
                }
                if seller_listings:
                    ids_str = ",".join(str(i) for i in seller_listings)
                    from app.database_clickhouse import get_clickhouse_client as _get_ch
                    ch2 = await _get_ch()
                    if ch2 is not None:
                        hes_price_r = await ch2.query(f"""
                            SELECT item_id, AVG(price_point) AS avg_pp, COUNT() AS cnt
                            FROM user_events
                            WHERE event_type = 'bid_hesitation'
                              AND item_type  = 'listing'
                              AND item_id IN ({ids_str})
                              AND price_point > 0
                              AND timestamp >= now() - INTERVAL 30 DAY
                            GROUP BY item_id
                            HAVING cnt >= 2
                        """)
                        for row in hes_price_r.result_rows:
                            lid_h, avg_pp, _ = int(row[0]), float(row[1]), int(row[2])
                            sl = seller_listings.get(lid_h)
                            if sl and sl["price"] > 0 and avg_pp < sl["price"] * 0.85:
                                suggested = int(round(avg_pp / 50) * 50) or int(avg_pp)
                                _hes_body = t.get("proTipHesPriceBody", "")
                                if _hes_body:
                                    tips.append({
                                        "icon": "💡", "type": "hesitation_price",
                                        "title": t.get("proTipHesPriceTitle", ""),
                                        "body": _hes_body.format(title=sl["title"], suggested=suggested),
                                    })
                                break
            except Exception as hes_exc:
                logger.warning("[TipsUseCase] hesitation_price tip başarısız: %s", hes_exc)

            if self.peak_hours:
                best_hour = self.peak_hours[0]["label"]
                tips.append({
                    "icon": "📡", "type": "stream",
                    "title": t.get("proTipStreamTitle", ""),
                    "body": t.get("proTipStreamBody", "").format(hour=best_hour),
                })

            if self.funnel.get("view_to_bid_pct", 0) < 5 and self.funnel.get("views", 0) > 10:
                tips.append({
                    "icon": "📸", "type": "listing_quality",
                    "title": t.get("proTipQualityTitle", ""),
                    "body": t.get("proTipQualityBody", "").format(pct=self.funnel["view_to_bid_pct"]),
                })

            if not tips:
                tips.append({
                    "icon": "✅", "type": "general",
                    "title": t.get("proTipAllGoodTitle", ""),
                    "body": t.get("proTipAllGoodBody", ""),
                })
        except Exception as exc:
            logger.warning("[TipsUseCase] başarısız: %s", exc)
        return tips
