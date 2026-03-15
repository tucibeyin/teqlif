import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Set

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.stream import LiveStream
from app.models.auction import Auction
from app.models.listing import Listing
from app.models.message import DirectMessage
from app.schemas.auction import AuctionStart, BidIn, AuctionStateOut
from app.utils.auth import get_current_user, decode_token
from app.utils.redis_client import get_redis
from app.routers.notifications import push_notification

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auction", tags=["auction"])

_PUBSUB_CHANNEL = "auction_broadcast"

# ── Redis keys ──────────────────────────────────────────────────────────────
def _key(stream_id: int) -> str:
    return f"auction:{stream_id}"

# ── WebSocket bağlantı yöneticisi (her worker'a özel) ───────────────────────
class _Manager:
    def __init__(self):
        self._conns: Dict[int, Set[WebSocket]] = {}

    async def connect(self, ws: WebSocket, stream_id: int):
        await ws.accept()
        self._conns.setdefault(stream_id, set()).add(ws)
        total = len(self._conns[stream_id])
        origin = ws.headers.get("origin", "native/mobile")
        logger.info(
            "[WS] BAĞLANDI | stream_id=%s origin=%s | bu_worker=%s bağlı",
            stream_id, origin, total,
        )

    def disconnect(self, ws: WebSocket, stream_id: int):
        self._conns.get(stream_id, set()).discard(ws)
        total = len(self._conns.get(stream_id, set()))
        logger.info("[WS] AYRILDI | stream_id=%s | bu_worker=%s bağlı", stream_id, total)

    async def local_broadcast(self, stream_id: int, payload: dict):
        """Sadece bu worker'daki WS bağlantılarına gönder."""
        targets = list(self._conns.get(stream_id, set()))
        if not targets:
            return
        dead = set()
        for ws in targets:
            try:
                await ws.send_json(payload)
            except Exception as exc:
                logger.warning("[WS] SEND HATA | stream_id=%s | %s", stream_id, exc)
                dead.add(ws)
        if dead:
            logger.warning("[WS] %s ölü bağlantı temizlendi | stream_id=%s", len(dead), stream_id)
            for ws in dead:
                self._conns.get(stream_id, set()).discard(ws)

    def conn_count(self, stream_id: int) -> int:
        return len(self._conns.get(stream_id, set()))

    def total_conns(self) -> int:
        return sum(len(v) for v in self._conns.values())


manager = _Manager()


async def _publish(stream_id: int, payload: dict):
    """Tüm worker'lara Redis pub/sub üzerinden yayınla."""
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.publish(_PUBSUB_CHANNEL, data)
    logger.info(
        "[PUBSUB] YAYINLANDI | stream_id=%s status=%s | bu_worker_ws=%s",
        stream_id, payload.get("status"), manager.conn_count(stream_id),
    )


async def pubsub_listener():
    """Her worker için tek seferlik başlatılan arka plan görevi."""
    import redis.asyncio as aioredis
    from app.config import settings
    # Pub/sub için ayrı bağlantı (subscribe modunda kalır)
    r = aioredis.from_url(settings.redis_url, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(_PUBSUB_CHANNEL)
    logger.info("[PUBSUB] Dinleyici başladı (worker)")
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
                stream_id = data.pop("_stream_id")
                await manager.local_broadcast(stream_id, data)
            except Exception as exc:
                logger.warning("[PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(_PUBSUB_CHANNEL)
        await r.aclose()

# ── Yardımcı: Redis'ten state oku ───────────────────────────────────────────
async def _get_state(stream_id: int) -> dict:
    redis = await get_redis()
    data = await redis.hgetall(_key(stream_id))
    if not data:
        return {"status": "idle", "bid_count": 0}
    listing_id_raw = data.get("listing_id")
    return {
        "status": data.get("status", "idle"),
        "item_name": data.get("item_name"),
        "start_price": float(data["start_price"]) if data.get("start_price") else None,
        "current_bid": float(data["current_bid"]) if data.get("current_bid") else None,
        "current_bidder": data.get("current_bidder_name") or None,
        "bid_count": int(data.get("bid_count", 0)),
        "listing_id": int(listing_id_raw) if listing_id_raw else None,
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

    # listing_id verilmişse başlığı oradan al, fiyat her zaman request'ten gelir
    listing_id_val = data.listing_id
    start_price = float(data.start_price)
    if listing_id_val:
        listing = await db.scalar(
            select(Listing).where(Listing.id == listing_id_val, Listing.is_deleted == False)  # noqa: E712
        )
        if not listing:
            raise HTTPException(status_code=404, detail="İlan bulunamadı")
        item_name = listing.title
    else:
        item_name = data.item_name
        listing_id_val = None

    await redis.hset(key, mapping={
        "status": "active",
        "item_name": item_name,
        "start_price": str(start_price),
        "current_bid": str(start_price),
        "current_bidder_id": "",
        "current_bidder_name": "",
        "bid_count": "0",
        "host_id": str(current_user.id),
        "stream_id": str(stream_id),
        "listing_id": str(listing_id_val) if listing_id_val else "",
    })
    await redis.expire(key, 24 * 3600)

    state = await _get_state(stream_id)
    await _publish(stream_id, {"type": "state", **state})
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
    await _publish(stream_id, {"type": "state", **state})
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
    await _publish(stream_id, {"type": "state", **state})
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

    lid_str = data.get("listing_id", "")
    auction = Auction(
        stream_id=stream_id,
        listing_id=int(lid_str) if lid_str else None,
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
    await _publish(stream_id, {"type": "state", **state})
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

    # Önceki teklif sahibini kaydet (outbid bildirimi için)
    prev_data = await redis.hgetall(_key(stream_id))
    prev_bidder_id_str = prev_data.get("current_bidder_id", "")
    prev_item_name = prev_data.get("item_name", "")

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
    await _publish(stream_id, {"type": "state", **state})
    logger.info(
        "[TEKLİF] stream_id=%s user=%s amount=%s | ws_hedef=%s",
        stream_id, current_user.username, data.amount, manager.conn_count(stream_id),
    )

    # Host'a new_bid bildirimi
    if stream and stream.host_id:
        asyncio.create_task(push_notification(
            user_id=stream.host_id,
            notif={
                "type": "new_bid",
                "title": f"@{current_user.username} teklif verdi",
                "body": f"{prev_item_name} — ₺{data.amount:,.0f}" if prev_item_name else f"₺{data.amount:,.0f}",
                "related_id": stream_id,
            },
            pref_key="new_bid",
        ))

    # Önceki teklif sahibine outbid bildirimi
    if prev_bidder_id_str and prev_bidder_id_str != str(current_user.id):
        try:
            prev_bidder_id = int(prev_bidder_id_str)
            asyncio.create_task(push_notification(
                user_id=prev_bidder_id,
                notif={
                    "type": "outbid",
                    "title": "Teklifiniz geçildi!",
                    "body": f"{prev_item_name} — yeni teklif: ₺{data.amount:,.0f}" if prev_item_name else f"Yeni teklif: ₺{data.amount:,.0f}",
                    "related_id": stream_id,
                },
                pref_key="outbid",
            ))
        except ValueError:
            pass

    return state


@router.post("/{stream_id}/accept", response_model=AuctionStateOut)
async def accept_bid(
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

    winner_name = data.get("current_bidder_name", "")
    if not winner_name:
        raise HTTPException(status_code=400, detail="Kabul edilecek teklif yok (henüz teklif verilmemiş)")

    # Auction'ı bitir — end ile aynı mantık
    winner_id_str = data.get("current_bidder_id", "")
    final_price = float(data["current_bid"])
    lid_str = data.get("listing_id", "")
    listing_id = int(lid_str) if lid_str else None
    item_name = data.get("item_name", "")

    await redis.hset(key, "status", "ended")

    auction = Auction(
        stream_id=stream_id,
        listing_id=listing_id,
        item_name=item_name,
        start_price=float(data.get("start_price", 0)),
        final_price=final_price,
        winner_id=int(winner_id_str) if winner_id_str else None,
        winner_username=winner_name,
        bid_count=int(data.get("bid_count", 0)),
        status="completed",
        ended_at=datetime.now(timezone.utc),
    )
    db.add(auction)
    await db.commit()
    await redis.delete(key)

    # Fiyat formatlama yardımcısı
    def _fmt_price(v: float) -> str:
        s = str(int(v))
        result, i = "", 0
        for ch in reversed(s):
            if i and i % 3 == 0:
                result = "." + result
            result = ch + result
            i += 1
        return f"₺{result}"

    listing_line = f"\n🔗 https://teqlif.com/ilan/{listing_id}" if listing_id else ""
    dm_content = (
        f"🏆 Tebrikler! Teklifiniz kabul edildi.\n"
        f"📦 Ürün: {item_name}\n"
        f"💰 Kazanan fiyat: {_fmt_price(final_price)}"
        f"{listing_line}"
    )

    # Kazanan kullanıcıya DM gönder (kalıcı + push notification)
    if winner_id_str:
        try:
            winner_user_id = int(winner_id_str)
            dm = DirectMessage(
                sender_id=current_user.id,
                receiver_id=winner_user_id,
                content=dm_content,
            )
            db.add(dm)
            await db.commit()
            await db.refresh(dm)
            # Push notification gönder
            await push_notification(
                winner_user_id,
                {
                    "type": "auction_won",
                    "title": "🏆 Teklifiniz kabul edildi!",
                    "body": f"{item_name} — {_fmt_price(final_price)}",
                    "related_id": listing_id or stream_id,
                },
                pref_key="auction_won",
            )
            logger.info(
                "[ACCEPT] DM gönderildi | winner_id=%s | item=%r | price=%s",
                winner_user_id, item_name, final_price,
            )
        except Exception as exc:
            logger.warning("[ACCEPT] DM gönderilemedi | winner_id=%s | %s", winner_id_str, exc)

    # Chat'e herkese görünür özet mesajı da yayınla
    chat_summary = (
        f"🏆 Teklif kabul edildi! "
        f"📦 {item_name} — {_fmt_price(final_price)} — 🏅 @{winner_name}"
    )
    chat_msg = {
        "type": "message",
        "id": str(uuid.uuid4())[:8],
        "username": current_user.username,
        "content": chat_summary,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    if listing_id:
        chat_msg["url"] = f"/ilan/{listing_id}"
    _CHAT_KEY = f"chat:{stream_id}:messages"
    _CHAT_PUBSUB = "chat_broadcast"
    await redis.rpush(_CHAT_KEY, json.dumps(chat_msg))
    await redis.ltrim(_CHAT_KEY, -50, -1)
    await redis.expire(_CHAT_KEY, 24 * 3600)
    await redis.publish(_CHAT_PUBSUB, json.dumps({"_stream_id": stream_id, **chat_msg}))

    state = {
        "status": "ended",
        "item_name": item_name,
        "bid_count": int(data.get("bid_count", 0)),
        "current_bid": final_price,
        "current_bidder": winner_name,
        "start_price": float(data.get("start_price", 0)),
        "listing_id": listing_id,
    }
    await _publish(stream_id, {"type": "state", **state})
    logger.info(
        "[AÇIK ARTIRMA] TEKLİF KABUL EDİLDİ | stream_id=%s winner=%s price=%s",
        stream_id, winner_name, final_price,
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
