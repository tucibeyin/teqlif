
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
from app.models.auction import Auction
from app.models.purchase import Purchase
from app.models.message import DirectMessage
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
