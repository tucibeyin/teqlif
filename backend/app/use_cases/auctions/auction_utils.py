
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
        self._conns = {}

    def connect(self, ws, stream_id: int):
        self._conns.setdefault(stream_id, set()).add(ws)
        import logging
        logging.getLogger(__name__).info("[WS] BAĞLANDI | stream_id=%s | bu_worker=%s bağlı", stream_id, len(self._conns[stream_id]))

    def disconnect(self, ws, stream_id: int):
        s = self._conns.get(stream_id)
        if s is not None:
            s.discard(ws)
            if not s:
                del self._conns[stream_id]

    async def local_broadcast(self, stream_id: int, payload: dict):
        targets = list(self._conns.get(stream_id, set()))
        if not targets:
            return
        
        async def _send(ws):
            try:
                await ws.send_json(payload)
                return True
            except Exception:
                return False

        import asyncio
        results = await asyncio.gather(*[_send(ws) for ws in targets], return_exceptions=True)
        dead = {ws for ws, ok in zip(targets, results) if ok is not True}
        if dead:
            s = self._conns.get(stream_id)
            if s is not None:
                s -= dead
                if not s:
                    del self._conns[stream_id]

    def conn_count(self, stream_id: int) -> int:
        return len(self._conns.get(stream_id, set()))

    def total_conns(self) -> int:
        return sum(len(v) for v in self._conns.values())

manager = AuctionConnectionManager()
_PUBSUB_CHANNEL = "auction_broadcast"

async def pubsub_listener():
    from app.core.stream_listener import stream_listener
    async def _on_message(data: dict) -> None:
        stream_id = data.pop("_stream_id", None)
        if stream_id:
            await manager.local_broadcast(stream_id, data)
    await stream_listener(_PUBSUB_CHANNEL, _on_message)

async def publish_auction(stream_id: int, payload: dict):
    from app.core.auction_outbox import outbox_publish
    from app.core.stream_listener import STREAM_MAXLEN
    from app.utils.redis_client import get_redis
    import json
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.xadd(_PUBSUB_CHANNEL, {"data": data}, maxlen=STREAM_MAXLEN, approximate=True)
    await outbox_publish(stream_id, {"type": payload.get("type", "state"), **payload})


async def _require_host(uow, stream_id: int, user: User) -> LiveStream:
    stream = await uow.session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
    if not stream:
        raise NotFoundException("Yayın bulunamadı")
    if stream.host_id != user.id:
        raise ForbiddenException("Sadece yayın sahibi işlem yapabilir")
    return stream
