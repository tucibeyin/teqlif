"""
Açık artırma router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, uow, rate-limit) alır
  2. Command/Query'yi çağırır ve sonucu döner

İş mantığı, DB sorguları, Redis işlemleri ve WS yayınları tamamen
AuctionCommands ve ilgili Query sınıflarına taşınmıştır.
"""
from fastapi import APIRouter, Depends, Request, WebSocket, WebSocketDisconnect
from typing import Optional
import asyncio

from app.database import get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.user import User
from app.schemas.auction import AuctionStart, BidIn, AuctionStateOut, BidOut, EndAuctionIn, AcceptBidIn
from app.utils.auth import get_current_user, decode_token
from app.core.defender import register_ws_session, release_ws_session, MAX_CONCURRENT_SESSIONS
from app.core.logger import get_logger
from app.core.rate_limit import limiter, get_user_id_or_ip
from app.core.idempotency import idempotency_key, store_idempotency_result
from app.core.auction_outbox import outbox_replay
from app.database_clickhouse import buffer_user_event
from app.use_cases.auctions.commands.auction_commands import AuctionCommands
from app.use_cases.auctions.queries.auction_queries import GetBidsQuery, GetAuctionStateQuery
from app.use_cases.auctions.auction_utils import manager, pubsub_listener

from app.constants import ws_types as WS

_WS_AUTH_TIMEOUT_SECS    = 5.0
_WS_RECEIVE_TIMEOUT_SECS = 40.0
_WS_CODE_SESSION_LIMIT   = 4008

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auction", tags=["auction"])


# ── REST endpoints ────────────────────────────────────────────────────────────

@router.get("/{stream_id}", response_model=AuctionStateOut)
async def get_auction_state_endpoint(stream_id: int):
    # Redis-only query: DB session gerekmez
    return await GetAuctionStateQuery().execute(stream_id)


@router.get("/{stream_id}/bids", response_model=list[BidOut])
async def get_auction_bids(
    stream_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await GetBidsQuery(uow).execute(stream_id)


@router.post("/{stream_id}/start", response_model=AuctionStateOut)
async def start_auction(
    request: Request,
    stream_id: int,
    data: AuctionStart,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    host_ip = request.client.host if request.client else None
    return await AuctionCommands(uow).start(stream_id, data, current_user, host_ip=host_ip)


@router.post("/{stream_id}/pause", response_model=AuctionStateOut)
async def pause_auction(
    stream_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await AuctionCommands(uow).pause(stream_id, current_user)


@router.post("/{stream_id}/resume", response_model=AuctionStateOut)
async def resume_auction(
    stream_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await AuctionCommands(uow).resume(stream_id, current_user)


@router.post("/{stream_id}/end", response_model=AuctionStateOut)
async def end_auction(
    stream_id: int,
    data: Optional[EndAuctionIn] = None,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    proof_image_url = data.proof_image_url if data else None
    return await AuctionCommands(uow).end_auction(stream_id, current_user, proof_image_url=proof_image_url)


@router.post("/{stream_id}/bid", response_model=AuctionStateOut)
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def place_bid(
    request: Request,
    stream_id: int,
    data: BidIn,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
    _idem=Depends(idempotency_key("bid", ttl=30)),
):
    bidder_ip = request.client.host if request.client else None
    result = await AuctionCommands(uow).place_bid(stream_id, data, current_user, bidder_ip=bidder_ip)
    asyncio.create_task(buffer_user_event(
        event_type="bid_placed",
        item_id=result.get("listing_id") or stream_id,
        item_type="listing" if result.get("listing_id") else "stream",
        user_id=current_user.id,
        price_point=data.amount,
    ))
    await store_idempotency_result(request, result)
    return result


@router.post("/{stream_id}/buy-it-now", response_model=dict)
@limiter.limit("5/minute", key_func=get_user_id_or_ip)
async def buy_it_now_request(
    request: Request,
    stream_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await AuctionCommands(uow).request_buy_it_now(stream_id, current_user)


@router.post("/{stream_id}/buy-it-now/accept", response_model=AuctionStateOut)
async def buy_it_now_accept(
    stream_id: int,
    data: Optional[EndAuctionIn] = None,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    proof_image_url = data.proof_image_url if data else None
    return await AuctionCommands(uow).accept_buy_it_now(stream_id, current_user, proof_image_url=proof_image_url)


@router.post("/{stream_id}/buy-it-now/reject", response_model=AuctionStateOut)
async def buy_it_now_reject(
    stream_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await AuctionCommands(uow).reject_buy_it_now(stream_id, current_user)


@router.post("/{stream_id}/accept", response_model=AuctionStateOut)
async def accept_bid(
    stream_id: int,
    data: Optional[AcceptBidIn] = None,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    proof_image_url = data.proof_image_url if data else None
    return await AuctionCommands(uow).accept_bid(stream_id, current_user, proof_image_url=proof_image_url)


# ── WebSocket endpoint ────────────────────────────────────────────────────────

@router.websocket("/{stream_id}/ws")
async def auction_ws(stream_id: int, websocket: WebSocket):
    await websocket.accept()

    user_id: int | None = None
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=_WS_AUTH_TIMEOUT_SECS)
        token = raw.get("token", "") if isinstance(raw, dict) else ""
        if token:
            user_id = decode_token(token)
    except (asyncio.TimeoutError, Exception):
        pass

    if user_id:
        session_count = await register_ws_session(user_id)
        if session_count > MAX_CONCURRENT_SESSIONS:
            await release_ws_session(user_id)
            await websocket.close(code=_WS_CODE_SESSION_LIMIT)
            logger.warning(
                "[AUCTION WS] Eş zamanlı oturum limiti | stream_id=%s user_id=%s count=%s",
                stream_id, user_id, session_count,
            )
            return

    manager.connect(websocket, stream_id)
    logger.info("[AUCTION WS] BAĞLANDI | stream_id=%s user_id=%s", stream_id, user_id or "anonim")
    try:
        state = await GetAuctionStateQuery().execute(stream_id)
        logger.info("[WS] İLK STATE GÖNDERİLDİ | stream_id=%s status=%s", stream_id, state.get("status"))
        await websocket.send_json({"type": WS.AUCTION_STATE, **state})

        missed = await outbox_replay(stream_id, count=10)
        for event in reversed(missed):
            try:
                await websocket.send_json({**event, "replayed": True})
            except Exception:
                break

        while True:
            try:
                msg = await asyncio.wait_for(websocket.receive(), timeout=_WS_RECEIVE_TIMEOUT_SECS)
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
        if user_id:
            await release_ws_session(user_id)
