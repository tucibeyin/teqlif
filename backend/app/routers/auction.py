import logging
from datetime import datetime, timezone
from typing import Dict, Set

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.models.auction import Auction
from app.schemas.auction import AuctionStart, BidIn, AuctionStateOut
from app.utils.auth import get_current_user, decode_token
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auction", tags=["auction"])

# ── Redis keys ──────────────────────────────────────────────────────────────
def _key(stream_id: int) -> str:
    return f"auction:{stream_id}"

# ── WebSocket bağlantı yöneticisi ────────────────────────────────────────────
class _Manager:
    def __init__(self):
        self._conns: Dict[int, Set[WebSocket]] = {}

    async def connect(self, ws: WebSocket, stream_id: int):
        await ws.accept()
        self._conns.setdefault(stream_id, set()).add(ws)
        total = len(self._conns[stream_id])
        client = getattr(ws, "client", None)
        origin = ws.headers.get("origin", "native/mobile")
        logger.info(
            "[WS] BAĞLANDI | stream_id=%s origin=%s client=%s | toplam=%s bağlı",
            stream_id, origin, client, total,
        )

    def disconnect(self, ws: WebSocket, stream_id: int):
        self._conns.get(stream_id, set()).discard(ws)
        total = len(self._conns.get(stream_id, set()))
        logger.info(
            "[WS] AYRILDI   | stream_id=%s | kalan=%s bağlı",
            stream_id, total,
        )

    async def broadcast(self, stream_id: int, payload: dict):
        targets = list(self._conns.get(stream_id, set()))
        logger.info(
            "[WS] BROADCAST | stream_id=%s status=%s | hedef=%s bağlantı",
            stream_id, payload.get("status"), len(targets),
        )
        dead = set()
        for ws in targets:
            try:
                await ws.send_json(payload)
            except Exception as exc:
                logger.warning(
                    "[WS] BROADCAST HATA | stream_id=%s | %s", stream_id, exc
                )
                dead.add(ws)
        if dead:
            logger.warning(
                "[WS] %s ölü bağlantı temizlendi | stream_id=%s", len(dead), stream_id
            )
        for ws in dead:
            self._conns.get(stream_id, set()).discard(ws)

    def conn_count(self, stream_id: int) -> int:
        return len(self._conns.get(stream_id, set()))


manager = _Manager()

# ── Yardımcı: Redis'ten state oku ───────────────────────────────────────────
async def _get_state(stream_id: int) -> dict:
    redis = await get_redis()
    data = await redis.hgetall(_key(stream_id))
    if not data:
        return {"status": "idle", "bid_count": 0}
    return {
        "status": data.get("status", "idle"),
        "item_name": data.get("item_name"),
        "start_price": float(data["start_price"]) if data.get("start_price") else None,
        "current_bid": float(data["current_bid"]) if data.get("current_bid") else None,
        "current_bidder": data.get("current_bidder_name") or None,
        "bid_count": int(data.get("bid_count", 0)),
    }

# ── Atomic bid Lua scripti ───────────────────────────────────────────────────
_BID_SCRIPT = """
local key = KEYS[1]
local amount = tonumber(ARGV[1])
local bidder_id = ARGV[2]
local bidder_name = ARGV[3]
local status = redis.call('hget', key, 'status')
if status ~= 'active' then return {0, 'not_active'} end
local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
if amount <= current then return {0, 'too_low'} end
redis.call('hset', key,
    'current_bid', tostring(amount),
    'current_bidder_id', bidder_id,
    'current_bidder_name', bidder_name)
redis.call('hincrby', key, 'bid_count', 1)
return {1, tostring(amount)}
"""

# ── Yardımcı: stream & host doğrulama ───────────────────────────────────────
async def _get_stream_as_host(stream_id: int, user: User, db: AsyncSession) -> LiveStream:
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if not stream:
        raise HTTPException(status_code=404, detail="Yayın bulunamadı")
    if stream.host_id != user.id:
        raise HTTPException(status_code=403, detail="Sadece host bu işlemi yapabilir")
    if not stream.is_live:
        raise HTTPException(status_code=400, detail="Yayın aktif değil")
    return stream


# ── REST endpoints ───────────────────────────────────────────────────────────

@router.get("/{stream_id}", response_model=AuctionStateOut)
async def get_auction_state(stream_id: int):
    return await _get_state(stream_id)


@router.post("/{stream_id}/start", response_model=AuctionStateOut)
async def start_auction(
    stream_id: int,
    data: AuctionStart,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _get_stream_as_host(stream_id, current_user, db)

    redis = await get_redis()
    key = _key(stream_id)

    existing_status = await redis.hget(key, "status")
    if existing_status == "active":
        raise HTTPException(status_code=400, detail="Zaten aktif bir açık artırma var")

    await redis.hset(key, mapping={
        "status": "active",
        "item_name": data.item_name,
        "start_price": str(data.start_price),
        "current_bid": str(data.start_price),
        "current_bidder_id": "",
        "current_bidder_name": "",
        "bid_count": "0",
        "host_id": str(current_user.id),
        "stream_id": str(stream_id),
    })
    await redis.expire(key, 24 * 3600)

    state = await _get_state(stream_id)
    await manager.broadcast(stream_id, {"type": "state", **state})
    logger.info(
        "[AÇIK ARTIRMA] BAŞLADI | stream_id=%s item=%r start_price=%s | ws_hedef=%s",
        stream_id, data.item_name, data.start_price, manager.conn_count(stream_id),
    )
    return state


@router.post("/{stream_id}/pause", response_model=AuctionStateOut)
async def pause_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _get_stream_as_host(stream_id, current_user, db)
    redis = await get_redis()
    key = _key(stream_id)

    if await redis.hget(key, "status") != "active":
        raise HTTPException(status_code=400, detail="Açık artırma aktif değil")

    await redis.hset(key, "status", "paused")
    state = await _get_state(stream_id)
    await manager.broadcast(stream_id, {"type": "state", **state})
    logger.info("[AÇIK ARTIRMA] DURAKLATILDI | stream_id=%s | ws_hedef=%s",
                stream_id, manager.conn_count(stream_id))
    return state


@router.post("/{stream_id}/resume", response_model=AuctionStateOut)
async def resume_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _get_stream_as_host(stream_id, current_user, db)
    redis = await get_redis()
    key = _key(stream_id)

    if await redis.hget(key, "status") != "paused":
        raise HTTPException(status_code=400, detail="Açık artırma duraklatılmamış")

    await redis.hset(key, "status", "active")
    state = await _get_state(stream_id)
    await manager.broadcast(stream_id, {"type": "state", **state})
    logger.info("[AÇIK ARTIRMA] DEVAM ETTİ | stream_id=%s | ws_hedef=%s",
                stream_id, manager.conn_count(stream_id))
    return state


@router.post("/{stream_id}/end", response_model=AuctionStateOut)
async def end_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    await _get_stream_as_host(stream_id, current_user, db)
    redis = await get_redis()
    key = _key(stream_id)

    data = await redis.hgetall(key)
    if not data or data.get("status") not in ("active", "paused"):
        raise HTTPException(status_code=400, detail="Aktif açık artırma yok")

    await redis.hset(key, "status", "ended")

    # DB'ye yaz (sadece burada)
    winner_id_str = data.get("current_bidder_id", "")
    final_price = float(data["current_bid"]) if data.get("current_bid") else float(data.get("start_price", 0))

    auction = Auction(
        stream_id=stream_id,
        item_name=data.get("item_name", ""),
        start_price=float(data.get("start_price", 0)),
        final_price=final_price if data.get("current_bidder_id") else None,
        winner_id=int(winner_id_str) if winner_id_str else None,
        winner_username=data.get("current_bidder_name") or None,
        bid_count=int(data.get("bid_count", 0)),
        status="completed",
        ended_at=datetime.now(timezone.utc),
    )
    db.add(auction)
    await db.commit()

    # Redis'i temizle
    await redis.delete(key)

    state = {"status": "ended", "item_name": data.get("item_name"), "bid_count": int(data.get("bid_count", 0)),
             "current_bid": final_price if data.get("current_bidder_id") else None,
             "current_bidder": data.get("current_bidder_name") or None, "start_price": float(data.get("start_price", 0))}
    await manager.broadcast(stream_id, {"type": "state", **state})
    logger.info(
        "[AÇIK ARTIRMA] BİTTİ | stream_id=%s winner=%s price=%s bid_count=%s",
        stream_id, state["current_bidder"], state["current_bid"], state["bid_count"],
    )
    return state


@router.post("/{stream_id}/bid", response_model=AuctionStateOut)
async def place_bid(
    stream_id: int,
    data: BidIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Host kendi açık artırmasına teklif veremez
    result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
    stream = result.scalar_one_or_none()
    if stream and stream.host_id == current_user.id:
        raise HTTPException(status_code=400, detail="Host kendi açık artırmasına teklif veremez")

    redis = await get_redis()
    # Atomic Lua scripti: bid validate + update
    result = await redis.eval(
        _BID_SCRIPT, 1, _key(stream_id),
        str(data.amount), str(current_user.id), current_user.username,
    )

    ok, msg = int(result[0]), result[1]
    if ok == 0:
        if msg == "not_active":
            raise HTTPException(status_code=400, detail="Açık artırma aktif değil")
        raise HTTPException(status_code=400, detail="Teklifiniz mevcut tekliften yüksek olmalı")

    state = await _get_state(stream_id)
    await manager.broadcast(stream_id, {"type": "state", **state})
    logger.info(
        "[TEKLİF] stream_id=%s user=%s amount=%s | ws_hedef=%s",
        stream_id, current_user.username, data.amount, manager.conn_count(stream_id),
    )
    return state


# ── WebSocket endpoint ───────────────────────────────────────────────────────

@router.websocket("/{stream_id}/ws")
async def auction_ws(stream_id: int, websocket: WebSocket):
    await manager.connect(websocket, stream_id)
    try:
        # Bağlanınca mevcut state'i gönder
        state = await _get_state(stream_id)
        logger.info(
            "[WS] İLK STATE GÖNDERİLDİ | stream_id=%s status=%s",
            stream_id, state.get("status"),
        )
        await websocket.send_json({"type": "state", **state})

        # Bağlantıyı açık tut; client'tan gelen ping mesajlarını yoksay
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.warning("[WS] BEKLENMEYEN HATA | stream_id=%s | %s", stream_id, exc)
    finally:
        manager.disconnect(websocket, stream_id)
