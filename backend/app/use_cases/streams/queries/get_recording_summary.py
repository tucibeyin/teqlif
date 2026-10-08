from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class GetRecordingSummaryQuery:
    """
    Detay ekranını tek istekle dolduran birleşik sorgu.

    Döndürür:
      stream   — başlık, tarih, pik izleyici
      metrics  — toplam gelir, teklif sayısı, satış sayısı
      auctions — müzayedeler + kazanan + teklifler (auction_id üzerinden)
      direct_sales — direkt satışlar + siparişler
      gifts    — hediye özeti + olay listesi
    """

    def __init__(self, db: AsyncSession, uploads_host: str = ""):
        self._db = db
        self._uploads_host = uploads_host.rstrip("/")

    async def execute(self, stream_id: int) -> dict:
        stream = await self._fetch_stream(stream_id)
        if not stream:
            return {}

        auctions     = await self._fetch_auctions(stream_id)
        direct_sales = await self._fetch_direct_sales(stream_id)
        gifts        = await self._fetch_gifts(stream_id)
        metrics      = self._compute_metrics(auctions, direct_sales, gifts)

        return {
            "stream":       stream,
            "metrics":      metrics,
            "auctions":     auctions,
            "direct_sales": direct_sales,
            "gifts":        gifts,
        }

    # ── Stream meta ──────────────────────────────────────────────────────────

    async def _fetch_stream(self, stream_id: int) -> dict | None:
        row = (await self._db.execute(text("""
            SELECT id, title, started_at, ended_at, peak_viewer_count, thumbnail_url
            FROM live_streams
            WHERE id = :stream_id
        """), {"stream_id": stream_id})).mappings().first()
        return dict(row) if row else None

    # ── Müzayedeler ──────────────────────────────────────────────────────────

    async def _fetch_auctions(self, stream_id: int) -> list[dict]:
        auction_rows = (await self._db.execute(text("""
            SELECT
                a.id              AS auction_id,
                a.item_name,
                a.proof_image_url,
                a.start_price,
                a.final_price,
                a.buy_it_now_price,
                a.is_bought_it_now,
                a.bid_count,
                a.status,
                a.winner_id,
                a.winner_username,
                wu.profile_image_thumb_url AS winner_avatar_url,
                a.started_at,
                a.ended_at
            FROM auctions a
            LEFT JOIN users wu ON wu.id = a.winner_id
            WHERE a.stream_id = :stream_id
            ORDER BY a.started_at ASC
        """), {"stream_id": stream_id})).mappings().all()

        result = []
        for a in auction_rows:
            duration_minutes = None
            if a["started_at"] and a["ended_at"]:
                duration_minutes = int((a["ended_at"] - a["started_at"]).total_seconds() / 60)

            bids = await self._fetch_bids_for_auction(a["auction_id"])

            winner = None
            if a["winner_id"]:
                winner = {
                    "user_id":    a["winner_id"],
                    "username":   a["winner_username"],
                    "avatar_url": self._full_url(a["winner_avatar_url"]),
                }

            result.append({
                "auction_id":       a["auction_id"],
                "item_name":        a["item_name"],
                "proof_image_url":  a["proof_image_url"],
                "start_price":      float(a["start_price"]) if a["start_price"] else None,
                "final_price":      float(a["final_price"]) if a["final_price"] else None,
                "buy_it_now_price": float(a["buy_it_now_price"]) if a["buy_it_now_price"] else None,
                "is_bought_it_now": a["is_bought_it_now"],
                "bid_count":        a["bid_count"],
                "duration_minutes": duration_minutes,
                "sold":             a["status"] == "ended" and a["winner_id"] is not None,
                "winner":           winner,
                "bids":             bids,
            })
        return result

    async def _fetch_bids_for_auction(self, auction_id: int) -> list[dict]:
        rows = (await self._db.execute(text("""
            SELECT
                b.id, b.bidder_id AS user_id, b.bidder_username AS username,
                u.profile_image_thumb_url AS avatar_url,
                b.amount, b.created_at
            FROM bids b
            LEFT JOIN users u ON u.id = b.bidder_id
            WHERE b.auction_id = :auction_id
            ORDER BY b.created_at DESC
            LIMIT 50
        """), {"auction_id": auction_id})).mappings().all()

        return [
            {
                "user_id":    r["user_id"],
                "username":   r["username"],
                "avatar_url": self._full_url(r["avatar_url"]),
                "amount":     float(r["amount"]),
                "created_at": r["created_at"],
            }
            for r in rows
        ]

    # ── Direkt Satışlar ───────────────────────────────────────────────────────

    async def _fetch_direct_sales(self, stream_id: int) -> list[dict]:
        sale_rows = (await self._db.execute(text("""
            SELECT
                ds.id AS sale_id, ds.title, ds.product_image_url,
                ds.price, ds.total_stock, ds.remaining_stock,
                ds.viewer_count_at_start, ds.started_at, ds.ended_at
            FROM direct_sales ds
            WHERE ds.stream_id = :stream_id
            ORDER BY ds.started_at ASC
        """), {"stream_id": stream_id})).mappings().all()

        result = []
        for ds in sale_rows:
            orders = await self._fetch_orders_for_sale(ds["sale_id"])
            sold_count = sum(o["quantity"] for o in orders)

            result.append({
                "sale_id":               ds["sale_id"],
                "title":                 ds["title"],
                "product_image_url":     ds["product_image_url"],
                "price":                 float(ds["price"]) if ds["price"] else None,
                "total_stock":           ds["total_stock"],
                "sold_count":            sold_count,
                "viewer_count_at_start": ds["viewer_count_at_start"],
                "started_at":            ds["started_at"],
                "ended_at":              ds["ended_at"],
                "orders":                orders,
            })
        return result

    async def _fetch_orders_for_sale(self, sale_id: int) -> list[dict]:
        rows = (await self._db.execute(text("""
            SELECT
                dso.id, dso.buyer_id AS user_id, u.username,
                u.profile_image_thumb_url AS avatar_url,
                dso.quantity, dso.unit_price, dso.created_at
            FROM direct_sale_orders dso
            LEFT JOIN users u ON u.id = dso.buyer_id
            WHERE dso.sale_id = :sale_id
              AND dso.status = 'completed'
            ORDER BY dso.created_at ASC
        """), {"sale_id": sale_id})).mappings().all()

        return [
            {
                "user_id":    r["user_id"],
                "username":   r["username"],
                "avatar_url": self._full_url(r["avatar_url"]),
                "quantity":   r["quantity"],
                "unit_price": float(r["unit_price"]),
                "created_at": r["created_at"],
            }
            for r in rows
        ]

    # ── Hediyeler ─────────────────────────────────────────────────────────────

    async def _fetch_gifts(self, stream_id: int) -> dict:
        rows = (await self._db.execute(text("""
            SELECT
                ge.sender_id AS user_id, u.username,
                u.profile_image_thumb_url AS avatar_url,
                ge.gift_name, ge.cost_teqlik, ge.host_share, ge.sent_at
            FROM gift_events ge
            LEFT JOIN users u ON u.id = ge.sender_id
            WHERE ge.stream_id = :stream_id
            ORDER BY ge.sent_at ASC
        """), {"stream_id": stream_id})).mappings().all()

        if not rows:
            return {"total_teqlik": 0, "total_host_share": 0, "sender_count": 0, "events": []}

        total_teqlik    = sum(r["cost_teqlik"] for r in rows)
        total_host_share = sum(r["host_share"] for r in rows)
        sender_ids      = {r["user_id"] for r in rows}

        events = [
            {
                "user_id":    r["user_id"],
                "username":   r["username"],
                "avatar_url": self._full_url(r["avatar_url"]),
                "gift_name":  r["gift_name"],
                "cost_teqlik": r["cost_teqlik"],
                "sent_at":    r["sent_at"],
            }
            for r in rows
        ]

        return {
            "total_teqlik":     total_teqlik,
            "total_host_share": total_host_share,
            "sender_count":     len(sender_ids),
            "events":           events,
        }

    # ── Metrikler ─────────────────────────────────────────────────────────────

    @staticmethod
    def _compute_metrics(auctions: list, direct_sales: list, gifts: dict) -> dict:
        auction_revenue = sum(
            a["final_price"] for a in auctions
            if a["sold"] and a["final_price"]
        )
        ds_revenue = sum(
            o["quantity"] * o["unit_price"]
            for ds in direct_sales
            for o in ds["orders"]
        )
        total_revenue = auction_revenue + ds_revenue

        total_bids  = sum(a["bid_count"] for a in auctions)
        total_sales = sum(ds["sold_count"] for ds in direct_sales)

        return {
            "total_revenue": round(total_revenue, 2),
            "total_bids":    total_bids,
            "total_sales":   total_sales,
        }

    # ── Yardımcı ─────────────────────────────────────────────────────────────

    def _full_url(self, path: str | None) -> str | None:
        if not path:
            return None
        if path.startswith("http"):
            return path
        return f"{self._uploads_host}/{path.lstrip('/')}"
