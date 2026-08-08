from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.models.bid import Bid
from app.models.direct_sale import DirectSale, DirectSaleOrder
from app.models.user import User


class GetCommerceActivityQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, limit: int = 100) -> list[dict]:
        bids = await self._fetch_bids(stream_id, limit)
        purchases = await self._fetch_ds_purchases(stream_id, limit)

        merged = sorted(bids + purchases, key=lambda x: x["created_at"], reverse=True)
        return merged[:limit]

    async def _fetch_bids(self, stream_id: int, limit: int) -> list[dict]:
        q = (
            select(Bid, User)
            .join(User, User.id == Bid.bidder_id)
            .where(Bid.stream_id == stream_id)
            .order_by(Bid.created_at.desc())
            .limit(limit)
        )
        res = await self.uow.session.execute(q)
        out = []
        for bid, u in res.all():
            out.append({
                "event_type": "bid",
                "actor": u.username,
                "value": float(bid.amount),
                "quantity": 1,
                "group_title": None,
                "created_at": bid.created_at,
            })
        return out

    async def _fetch_ds_purchases(self, stream_id: int, limit: int) -> list[dict]:
        q = (
            select(DirectSaleOrder, User, DirectSale.title)
            .join(DirectSale, DirectSale.id == DirectSaleOrder.sale_id)
            .join(User, User.id == DirectSaleOrder.buyer_id)
            .where(DirectSale.stream_id == stream_id)
            .order_by(DirectSaleOrder.created_at.desc())
            .limit(limit)
        )
        res = await self.uow.session.execute(q)
        out = []
        for order, u, title in res.all():
            out.append({
                "event_type": "ds_purchase",
                "actor": u.username,
                "value": float(order.unit_price),
                "quantity": order.quantity,
                "group_title": title,
                "created_at": order.created_at,
            })
        return out
