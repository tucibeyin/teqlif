
from app.core.uow import AbstractUnitOfWork
from app.use_cases.auctions.auction_utils import auction_key
from app.utils.redis_client import get_redis
from app.models.bid import Bid
from app.models.user import User
from sqlalchemy import select

class GetBidsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, limit: int = 50) -> list:
        async with self.uow:
            query = (
                select(Bid, User)
                .join(User, User.id == Bid.bidder_id)
                .where(Bid.stream_id == stream_id)
                .order_by(Bid.created_at.desc())
                .limit(limit)
            )
            res = await self.uow.session.execute(query)
            out = []
            for bid, u in res.all():
                out.append({
                    "id": bid.id,
                    "bidder_id": u.id,
                    "bidder_username": u.username,
                    "bid_amount": bid.amount,
                    "created_at": bid.created_at.isoformat() if bid.created_at else None,
                })
            return out

class GetAuctionStateQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int) -> dict:
        redis = await get_redis()
        key = auction_key(stream_id)
        data = await redis.hgetall(key)
        
        if not data:
            return {
                "status": "idle",
                "item_name": None,
                "current_bid": 0.0,
                "current_bidder_name": None,
                "bid_count": 0,
                "buy_it_now_price": None
            }

        return {
            "status": data.get("status", "idle"),
            "item_name": data.get("item_name"),
            "current_bid": float(data.get("current_bid", 0)),
            "current_bidder_name": data.get("current_bidder_name"),
            "bid_count": int(data.get("bid_count", 0)),
            "buy_it_now_price": float(data.get("buy_it_now_price")) if data.get("buy_it_now_price") else None
        }
