import os
import re

base_dir = "backend/app/use_cases/auctions"
os.makedirs(f"{base_dir}/commands", exist_ok=True)
os.makedirs(f"{base_dir}/queries", exist_ok=True)

utils_code = """
import json
import logging
from datetime import datetime, timezone
from typing import Optional, Any

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text

from app.models.stream import LiveStream
from app.models.listing import Listing
from app.models.user import User
from app.models.auction import Auction, AuctionBid
from app.models.purchase import Purchase
from app.models.direct_message import DirectMessage
from app.models.enums import ListingStatus
from app.schemas.auction import AuctionStart, BidIn
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException, DatabaseException
from app.core.saga import Saga, SagaError
from app.core.logger import get_logger, capture_exception
from app.constants import ws_types as WS

logger = get_logger(__name__)

async def _log_fraud_attempt(stream_id: int, user_id: int, action: str, details: str):
    logger.warning("[FRAUD] stream=%s user=%s action=%s | %s", stream_id, user_id, action, details)
    try:
        from app.database import AsyncSessionLocal
        from app.models.analytics import UserInteraction
        async with AsyncSessionLocal() as bg_db:
            bg_db.add(UserInteraction(
                user_id=user_id,
                item_id=stream_id,
                item_type="stream",
                interaction_type="fraud_attempt",
                metadata={"action": action, "details": details}
            ))
            await bg_db.commit()
    except Exception:
        pass

def fmt_price(v: float) -> str:
    if v == int(v):
        return f"{int(v)} ₺"
    return f"{v:,.2f} ₺".replace(",", "X").replace(".", ",").replace("X", ".")

def auction_key(stream_id: int) -> str:
    return f"auction:{stream_id}"

class AuctionConnectionManager:
    def __init__(self):
        self.active_connections: dict[int, set[WebSocket]] = {}

    def connect(self, ws: WebSocket, stream_id: int):
        if stream_id not in self.active_connections:
            self.active_connections[stream_id] = set()
        self.active_connections[stream_id].add(ws)

    def disconnect(self, ws: WebSocket, stream_id: int):
        if stream_id in self.active_connections:
            self.active_connections[stream_id].discard(ws)
            if not self.active_connections[stream_id]:
                del self.active_connections[stream_id]

    async def local_broadcast(self, stream_id: int, payload: dict):
        if stream_id not in self.active_connections:
            return
        
        async def _send(ws: WebSocket) -> bool:
            try:
                await ws.send_json(payload)
                return True
            except WebSocketDisconnect:
                return False
            except Exception as e:
                logger.warning("local_broadcast: %s", e)
                return False

        import asyncio
        tasks = [_send(ws) for ws in list(self.active_connections[stream_id])]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        for ws, res in zip(list(self.active_connections[stream_id]), results):
            if res is False or isinstance(res, Exception):
                self.disconnect(ws, stream_id)

    def conn_count(self, stream_id: int) -> int:
        return len(self.active_connections.get(stream_id, []))

    def total_conns(self) -> int:
        return sum(len(c) for c in self.active_connections.values())

manager = AuctionConnectionManager()

async def pubsub_listener():
    from app.core.ws_manager import ws_manager
    async def _on_message(data: dict) -> None:
        sid = data.get("stream_id")
        if sid:
            await manager.local_broadcast(sid, data)
    await ws_manager.subscribe("auction_broadcast", _on_message)

async def publish_auction(stream_id: int, payload: dict):
    from app.core.ws_manager import ws_manager
    payload["stream_id"] = stream_id
    await manager.local_broadcast(stream_id, payload)
    await ws_manager.publish("auction_broadcast", "global", payload)

async def _require_host(uow, stream_id: int, user: User) -> LiveStream:
    stream = await uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
    if not stream:
        raise NotFoundException("Yayın bulunamadı")
    if stream.host_id != user.id:
        raise ForbiddenException("Sadece yayın sahibi işlem yapabilir")
    return stream
"""

queries_code = """
from app.core.uow import AbstractUnitOfWork
from app.use_cases.auctions.auction_utils import auction_key
from app.utils.redis_client import get_redis
from app.models.auction import AuctionBid
from app.models.user import User
from sqlalchemy import select

class GetBidsQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, stream_id: int, limit: int = 50) -> list:
        async with self.uow:
            query = (
                select(AuctionBid, User)
                .join(User, User.id == AuctionBid.bidder_id)
                .where(AuctionBid.stream_id == stream_id)
                .order_by(AuctionBid.created_at.desc())
                .limit(limit)
            )
            res = await self.uow.session.execute(query)
            out = []
            for bid, u in res.all():
                out.append({
                    "id": bid.id,
                    "bidder_id": u.id,
                    "bidder_username": u.username,
                    "bid_amount": bid.bid_amount,
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
"""

with open(f"{base_dir}/auction_utils.py", "w") as f: f.write(utils_code)
with open(f"{base_dir}/queries/auction_queries.py", "w") as f: f.write(queries_code)
print("Generated utils and queries")
