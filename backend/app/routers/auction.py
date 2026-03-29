"""
Açık artırma router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db, rate-limit) alır
  2. AuctionService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, DB sorguları, Redis işlemleri ve WS yayınları tamamen
app.services.auction_service.AuctionService'e taşınmıştır.
"""
from fastapi import APIRouter, Depends, Request, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
import asyncio

from app.database import get_db
from app.models.user import User
from app.schemas.auction import AuctionStart, BidIn, AuctionStateOut
from app.utils.auth import get_current_user
from app.core.logger import get_logger
from app.core.rate_limit import limiter
from app.services.auction_service import (
    AuctionService,
    manager,
    pubsub_listener,  # noqa: F401 — main.py bu ismi buradan import eder
    get_auction_state,
)

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auction", tags=["auction"])


# ── REST endpoints ────────────────────────────────────────────────────────────

@router.get("/{stream_id}", response_model=AuctionStateOut)
async def get_auction_state_endpoint(stream_id: int):
    return await get_auction_state(stream_id)


@router.post("/{stream_id}/start", response_model=AuctionStateOut)
async def start_auction(
    stream_id: int,
    data: AuctionStart,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).start(stream_id, data, current_user)


@router.post("/{stream_id}/pause", response_model=AuctionStateOut)
async def pause_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).pause(stream_id, current_user)


@router.post("/{stream_id}/resume", response_model=AuctionStateOut)
async def resume_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).resume(stream_id, current_user)


@router.post("/{stream_id}/end", response_model=AuctionStateOut)
async def end_auction(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).end_auction(stream_id, current_user)


@router.post("/{stream_id}/bid", response_model=AuctionStateOut)
@limiter.limit("30/minute")
async def place_bid(
    request: Request,
    stream_id: int,
    data: BidIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).place_bid(stream_id, data, current_user)


@router.post("/{stream_id}/buy-it-now", response_model=dict)
@limiter.limit("10/minute")
async def buy_it_now_request(
    request: Request,
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Viewer Hemen Al talebi gönderir. Host onayına kadar bekler."""
    return await AuctionService(db).request_buy_it_now(stream_id, current_user)


@router.post("/{stream_id}/buy-it-now/accept", response_model=AuctionStateOut)
async def buy_it_now_accept(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Host Hemen Al talebini kabul eder. Satın alma tamamlanır."""
    return await AuctionService(db).accept_buy_it_now(stream_id, current_user)


@router.post("/{stream_id}/buy-it-now/reject", response_model=AuctionStateOut)
async def buy_it_now_reject(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Host Hemen Al talebini reddeder. Artırma kaldığı yerden devam eder."""
    return await AuctionService(db).reject_buy_it_now(stream_id, current_user)


@router.post("/{stream_id}/accept", response_model=AuctionStateOut)
async def accept_bid(
    stream_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await AuctionService(db).accept_bid(stream_id, current_user)


# ── WebSocket endpoint ────────────────────────────────────────────────────────

@router.websocket("/{stream_id}/ws")
async def auction_ws(stream_id: int, websocket: WebSocket):
    await manager.connect(websocket, stream_id)
    try:
        state = await get_auction_state(stream_id)
        logger.info(
            "[WS] İLK STATE GÖNDERİLDİ | stream_id=%s status=%s",
            stream_id, state.get("status"),
        )
        await websocket.send_json({"type": "state", **state})

        # Bağlantıyı açık tut; client'tan gelen ping mesajlarını yoksay
        while True:
            try:
                msg = await asyncio.wait_for(websocket.receive(), timeout=40.0)
            except asyncio.TimeoutError:
                logger.warning("[AUCTION WS] İstemci ping timeout | stream_id=%s", stream_id)
                break
            except WebSocketDisconnect:
                break
                
            if msg.get("type") == "websocket.disconnect":
                break
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.error("[WS] BEKLENMEYEN HATA | stream_id=%s | %s", stream_id, exc)
    finally:
        manager.disconnect(websocket, stream_id)
