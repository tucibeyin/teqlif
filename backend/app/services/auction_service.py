"""
Açık artırma servisi — iş mantığını router'dan ayırır.

AuctionService sınıfı tüm DB işlemlerini, Redis/Lua atomik güncellemelerini,
WebSocket yayınlarını ve bildirim gönderimlerini yönetir. Router katmanı
sadece HTTP/WS bağlantısını alır, AuctionService'i instantiate eder ve
sonucu döner.

Dependency Injection:
    db: AsyncSession — constructor üzerinden alınır (FastAPI Depends ile inject edilir)

Hata Yönetimi:
    DB hataları  → logger.error + capture_exception → DatabaseException (500)
    İş kuralları → BadRequestException (400) / ForbiddenException (403) / NotFoundException (404)
"""
import asyncio
import json
import uuid
from datetime import datetime, timezone
from typing import Dict, Set

from fastapi import WebSocket
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.user import User
from app.models.stream import LiveStream
from app.models.auction import Auction
from app.models.bid import Bid
from app.models.listing import Listing
from app.models.message import DirectMessage
from app.models.purchase import Purchase
from app.schemas.auction import AuctionStart, BidIn
from app.utils.redis_client import get_redis
from app.core.exceptions import (
    NotFoundException,
    ForbiddenException,
    BadRequestException,
    DatabaseException,
)
from app.core.logger import get_logger, capture_exception
from app.constants import ws_types as WS

logger = get_logger(__name__)

_PUBSUB_CHANNEL = "auction_broadcast"


# ── Fiyat formatlama yardımcısı ──────────────────────────────────────────────
def fmt_price(v: float) -> str:
    s = str(int(v))
    r, i = "", 0
    for ch in reversed(s):
        if i and i % 3 == 0:
            r = "." + r
        r = ch + r
        i += 1
    return f"₺{r}"


# ── Redis key ────────────────────────────────────────────────────────────────
def auction_key(stream_id: int) -> str:
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
                logger.error("[WS] SEND HATA | stream_id=%s | %s", stream_id, exc)
                dead.add(ws)
        if dead:
            logger.error("[WS] %s ölü bağlantı temizlendi | stream_id=%s", len(dead), stream_id)
            for ws in dead:
                self._conns.get(stream_id, set()).discard(ws)

    def conn_count(self, stream_id: int) -> int:
        return len(self._conns.get(stream_id, set()))

    def total_conns(self) -> int:
        return sum(len(v) for v in self._conns.values())


manager = _Manager()


async def pubsub_listener():
    """Her worker için tek seferlik başlatılan arka plan görevi."""
    import redis.asyncio as aioredis
    from app.config import settings

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
                logger.error("[PUBSUB] Mesaj işleme hatası: %s", exc)
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe(_PUBSUB_CHANNEL)
        await r.aclose()


async def publish_auction(stream_id: int, payload: dict):
    """Tüm worker'lara Redis pub/sub üzerinden yayınla."""
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.publish(_PUBSUB_CHANNEL, data)
    logger.info(
        "[PUBSUB] YAYINLANDI | stream_id=%s status=%s | bu_worker_ws=%s",
        stream_id, payload.get("status"), manager.conn_count(stream_id),
    )


async def get_auction_state(stream_id: int) -> dict:
    """Redis'ten mevcut açık artırma durumunu okur."""
    redis = await get_redis()
    data = await redis.hgetall(auction_key(stream_id))
    if not data:
        return {"status": "idle", "bid_count": 0}
    listing_id_raw = data.get("listing_id")
    bin_raw = data.get("buy_it_now_price")
    result = {
        "status": data.get("status", "idle"),
        "item_name": data.get("item_name"),
        "start_price": float(data["start_price"]) if data.get("start_price") else None,
        "buy_it_now_price": float(bin_raw) if bin_raw else None,
        "current_bid": float(data["current_bid"]) if data.get("current_bid") else None,
        "current_bidder": data.get("current_bidder_name") or None,
        "bid_count": int(data.get("bid_count", 0)),
        "listing_id": int(listing_id_raw) if listing_id_raw else None,
    }
    if data.get("status") == "buy_it_now_pending":
        result["bin_buyer_username"] = data.get("bin_buyer_username") or None
    return result


# ── Lua scriptleri ───────────────────────────────────────────────────────────

# Sadece okuma — Redis'te hiçbir şey değiştirmez.
# DB commit'ten ÖNCE fiyat/durum kontrolü için kullanılır.
_VALIDATE_BID_SCRIPT = """
local key = KEYS[1]
local amount = tonumber(ARGV[1])
local status = redis.call('hget', key, 'status')
if status ~= 'active' then return {0, 'not_active'} end
local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
if amount <= current then return {0, 'too_low'} end
return {1, tostring(current)}
"""

# DB commit başarılı olduktan SONRA Redis'i günceller.
# Re-validate içerir: DB ile Redis arasındaki küçük zaman penceresinde
# başka bir teklif geldiyse güvenli şekilde reddeder.
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

# Viewer isteği: active → buy_it_now_pending (atomik)
_BUY_IT_NOW_REQUEST_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'active' and status ~= 'paused' then
    return {0, 'not_active'}
end
local bin_raw = redis.call('hget', key, 'buy_it_now_price')
if not bin_raw or bin_raw == '' then
    return {0, 'no_bin_price'}
end
local bin = tonumber(bin_raw)
local current = tonumber(redis.call('hget', key, 'current_bid')) or 0
if current >= bin then
    return {0, 'bid_exceeds_bin'}
end
redis.call('hset', key, 'pre_pending_status', status)
redis.call('hset', key, 'status', 'buy_it_now_pending')
redis.call('hset', key, 'bin_buyer_id', ARGV[1])
redis.call('hset', key, 'bin_buyer_username', ARGV[2])
return {1, bin_raw}
"""

# Host kabulü: buy_it_now_pending → buy_it_now_locked (atomik)
_BUY_IT_NOW_ACCEPT_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'buy_it_now_pending' then
    return {0, 'not_pending'}
end
local bin_raw = redis.call('hget', key, 'buy_it_now_price')
if not bin_raw or bin_raw == '' then
    return {0, 'no_bin_price'}
end
local buyer_id = redis.call('hget', key, 'bin_buyer_id') or ''
local buyer_username = redis.call('hget', key, 'bin_buyer_username') or ''
redis.call('hset', key, 'status', 'buy_it_now_locked')
return {1, bin_raw, buyer_id, buyer_username}
"""

# Host reddi: buy_it_now_pending → önceki status'e dön (atomik)
_BUY_IT_NOW_REJECT_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'buy_it_now_pending' then
    return {0, 'not_pending'}
end
local prev = redis.call('hget', key, 'pre_pending_status') or 'active'
local buyer_username = redis.call('hget', key, 'bin_buyer_username') or ''
redis.call('hset', key, 'status', prev)
redis.call('hdel', key, 'bin_buyer_id', 'bin_buyer_username', 'pre_pending_status')
return {1, prev, buyer_username}
"""


# ── Servis sınıfı ────────────────────────────────────────────────────────────
class AuctionService:
    """
    Tüm açık artırma iş mantığını barındıran servis sınıfı.

    Kullanım:
        service = AuctionService(db)
        state = await service.start(stream_id, data, current_user)
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Yardımcı: stream & host doğrulama ───────────────────────────────────
    async def _require_host(self, stream_id: int, user: User) -> LiveStream:
        from app.services.moderation_service import mod_key
        from app.utils.redis_client import get_redis

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id != user.id:
            # Moderatör de bu işlemi yapabilir
            redis = await get_redis()
            is_mod = await redis.sismember(mod_key(stream_id), str(user.id))
            if not is_mod:
                raise ForbiddenException("Sadece host veya moderatör bu işlemi yapabilir")
        if not stream.is_live:
            raise BadRequestException("Yayın aktif değil")
        return stream

    # ── Durum ────────────────────────────────────────────────────────────────
    @staticmethod
    async def get_state(stream_id: int) -> dict:
        return await get_auction_state(stream_id)

    # ── Başlat ───────────────────────────────────────────────────────────────
    async def start(self, stream_id: int, data: AuctionStart, user: User) -> dict:
        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        existing_status = await redis.hget(key, "status")
        if existing_status == "active":
            raise BadRequestException("Zaten aktif bir açık artırma var")

        listing_id_val = data.listing_id
        start_price = float(data.start_price)
        if listing_id_val:
            listing = await self.db.scalar(
                select(Listing).where(Listing.id == listing_id_val, Listing.is_deleted == False)  # noqa: E712
            )
            if not listing:
                raise NotFoundException("İlan bulunamadı")
            item_name = listing.title
        else:
            item_name = data.item_name
            listing_id_val = None

        bin_price = float(data.buy_it_now_price) if data.buy_it_now_price else None
        await redis.hset(key, mapping={
            "status": "active",
            "item_name": item_name,
            "start_price": str(start_price),
            "buy_it_now_price": str(bin_price) if bin_price else "",
            "current_bid": str(start_price),
            "current_bidder_id": "",
            "current_bidder_name": "",
            "bid_count": "0",
            "host_id": str(user.id),
            "stream_id": str(stream_id),
            "listing_id": str(listing_id_val) if listing_id_val else "",
        })
        await redis.expire(key, 24 * 3600)

        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info(
            "[AÇIK ARTIRMA] BAŞLADI | stream_id=%s item=%r start_price=%s | ws_hedef=%s",
            stream_id, data.item_name, data.start_price, manager.conn_count(stream_id),
        )
        return state

    # ── Duraklat ─────────────────────────────────────────────────────────────
    async def pause(self, stream_id: int, user: User) -> dict:
        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        if await redis.hget(key, "status") != "active":
            raise BadRequestException("Açık artırma aktif değil")

        await redis.hset(key, "status", "paused")
        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info("[AÇIK ARTIRMA] DURAKLATILDI | stream_id=%s | ws_hedef=%s",
                    stream_id, manager.conn_count(stream_id))
        return state

    # ── Devam Ettir ──────────────────────────────────────────────────────────
    async def resume(self, stream_id: int, user: User) -> dict:
        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        if await redis.hget(key, "status") != "paused":
            raise BadRequestException("Açık artırma duraklatılmamış")

        await redis.hset(key, "status", "active")
        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info("[AÇIK ARTIRMA] DEVAM ETTİ | stream_id=%s | ws_hedef=%s",
                    stream_id, manager.conn_count(stream_id))
        return state

    # ── Bitir ────────────────────────────────────────────────────────────────
    async def end_auction(self, stream_id: int, user: User) -> dict:
        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        data = await redis.hgetall(key)
        if not data or data.get("status") not in ("active", "paused"):
            raise BadRequestException("Aktif açık artırma yok")

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
        self.db.add(auction)
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[AÇIK ARTIRMA] end DB commit HATASI | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Açık artırma sonucu kaydedilemedi")

        # Commit başarılı → şimdi Redis'i güncelle ve temizle
        await redis.hset(key, "status", "ended")
        await redis.delete(key)

        state = {
            "status": "ended",
            "item_name": data.get("item_name"),
            "bid_count": int(data.get("bid_count", 0)),
            "current_bid": final_price if data.get("current_bidder_id") else None,
            "current_bidder": data.get("current_bidder_name") or None,
            "start_price": float(data.get("start_price", 0)),
        }
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info(
            "[AÇIK ARTIRMA] BİTTİ | stream_id=%s winner=%s price=%s bid_count=%s",
            stream_id, state["current_bidder"], state["current_bid"], state["bid_count"],
        )
        return state

    # ── Teklif Ver ───────────────────────────────────────────────────────────
    async def place_bid(self, stream_id: int, data: BidIn, user: User) -> dict:
        from app.routers.notifications import push_notification
        from app.routers.moderation import mute_key

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if stream and stream.host_id == user.id:
            raise BadRequestException("Host kendi açık artırmasına teklif veremez")

        redis = await get_redis()

        # Mute kontrolü
        if await redis.sismember(mute_key(stream_id), str(user.id)):
            raise ForbiddenException("Bu yayında susturuldunuz. Teklif veremezsiniz.")

        # Önceki teklif sahibini kaydet (outbid bildirimi için)
        prev_data = await redis.hgetall(auction_key(stream_id))
        prev_bidder_id_str = prev_data.get("current_bidder_id", "")
        prev_item_name = prev_data.get("item_name", "")

        # Fiyat & durum doğrulama (read-only, Redis değişmez)
        val = await redis.eval(_VALIDATE_BID_SCRIPT, 1, auction_key(stream_id), str(data.amount))
        ok, msg = int(val[0]), val[1]
        if ok == 0:
            if msg == "not_active":
                raise BadRequestException("Açık artırma aktif değil")
            raise BadRequestException("Teklifiniz mevcut tekliften yüksek olmalı")

        # PostgreSQL'e KESİN YAZ — commit başarılı olana kadar Redis'e dokunma
        new_bid = Bid(
            stream_id=stream_id,
            bidder_id=user.id,
            bidder_username=user.username,
            amount=data.amount,
        )
        self.db.add(new_bid)
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[TEKLİF] DB commit HATASI | stream_id=%s user=%s amount=%s | %s",
                stream_id, user.username, data.amount, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Teklif kaydedilemedi, lütfen tekrar deneyin")

        # Redis atomik güncelle (re-validate + update)
        result = await redis.eval(
            _BID_SCRIPT, 1, auction_key(stream_id),
            str(data.amount), str(user.id), user.username,
        )
        ok, msg = int(result[0]), result[1]
        if ok == 0:
            # Nadir race condition: DB commit ile Redis update arasında başka bir
            # teklif geldi. DB kaydı audit trail olarak kalır, publish yapılmaz.
            logger.warning(
                "[TEKLİF] Race condition (eş zamanlı teklif) | stream_id=%s user=%s amount=%s reason=%s",
                stream_id, user.username, data.amount, msg,
            )
            if msg == "not_active":
                raise BadRequestException("Açık artırma aktif değil")
            raise BadRequestException("Eş zamanlı teklif: teklifiniz geçildi, lütfen tekrar deneyin")

        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info(
            "[TEKLİF] KAYDEDILDI+YAYINLANDI | stream_id=%s user=%s amount=%s | ws_hedef=%s",
            stream_id, user.username, data.amount, manager.conn_count(stream_id),
        )

        # Push bildirimler (arka planda, non-blocking)
        if stream and stream.host_id:
            asyncio.create_task(push_notification(
                user_id=stream.host_id,
                notif={
                    "type": "new_bid",
                    "title": f"@{user.username} teklif verdi",
                    "body": f"{prev_item_name} — ₺{data.amount:,.0f}" if prev_item_name else f"₺{data.amount:,.0f}",
                    "related_id": stream_id,
                },
                pref_key="new_bid",
            ))

        if prev_bidder_id_str and prev_bidder_id_str != str(user.id):
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
                logger.warning(
                    "[TEKLİF] Geçersiz prev_bidder_id formatı, outbid bildirimi atlandı | stream_id=%s prev_bidder_id_str=%r",
                    stream_id, prev_bidder_id_str,
                )

        return state

    # ── Hemen Al Talebi ──────────────────────────────────────────────────────
    async def request_buy_it_now(self, stream_id: int, user: User) -> dict:
        from app.routers.moderation import mute_key

        result = await self.db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id == user.id:
            raise ForbiddenException("Host kendi açık artırmasını satın alamaz")
        if not stream.is_live:
            raise BadRequestException("Yayın aktif değil")

        redis = await get_redis()
        key = auction_key(stream_id)

        if await redis.sismember(mute_key(stream_id), str(user.id)):
            raise ForbiddenException("Bu yayında susturuldunuz. Satın alma yapamazsınız.")

        val = await redis.eval(
            _BUY_IT_NOW_REQUEST_SCRIPT, 1, key,
            str(user.id), user.username,
        )
        ok, msg = int(val[0]), val[1]
        if ok == 0:
            if msg == "not_active":
                raise BadRequestException("Açık artırma aktif değil")
            if msg == "no_bin_price":
                raise BadRequestException("Bu ürün hemen alıma kapalı")
            if msg == "bid_exceeds_bin":
                raise BadRequestException("Teklifler hemen al fiyatını aştığı için artık kullanılamaz")
            raise BadRequestException("Hemen Al isteği gönderilemedi")

        bin_price = float(msg)
        redis_data = await redis.hgetall(key)
        item_name = redis_data.get("item_name", "")

        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        await publish_auction(stream_id, {
            "type": WS.BUY_IT_NOW_REQUESTED,
            "buyer": {"id": user.id, "username": user.username},
            "price": bin_price,
            "item_name": item_name,
        })

        logger.info(
            "[HEMEN AL] TALEP | stream_id=%s buyer=%s price=%s",
            stream_id, user.username, bin_price,
        )
        return {"detail": "Talebiniz iletildi, host onayı bekleniyor"}

    # ── Hemen Al Kabul ───────────────────────────────────────────────────────
    async def accept_buy_it_now(self, stream_id: int, user: User) -> dict:
        from app.routers.notifications import push_notification

        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        val = await redis.eval(_BUY_IT_NOW_ACCEPT_SCRIPT, 1, key)
        ok = int(val[0])
        if ok == 0:
            msg = val[1]
            if msg == "not_pending":
                raise BadRequestException("Bekleyen Hemen Al talebi yok")
            if msg == "no_bin_price":
                raise BadRequestException("Bu ürün hemen alıma kapalı")
            raise BadRequestException("Hemen Al kabul edilemedi")

        bin_price = float(val[1])
        buyer_id_str = val[2]
        buyer_username = val[3]

        if not buyer_id_str:
            await redis.hset(key, "status", "active")
            raise BadRequestException("Alıcı bilgisi bulunamadı")

        buyer_id = int(buyer_id_str)
        redis_data = await redis.hgetall(key)
        item_name   = redis_data.get("item_name", "")
        lid_str     = redis_data.get("listing_id", "")
        listing_id  = int(lid_str) if lid_str else None
        bid_count   = int(redis_data.get("bid_count", 0))
        start_price = float(redis_data.get("start_price", bin_price))

        listing_line = f"\n🔗 https://teqlif.com/ilan/{listing_id}" if listing_id else ""
        dm_content = (
            f"🛒 Hemen Al tamamlandı! Tebrikler!\n"
            f"📦 Ürün: {item_name}\n"
            f"💰 Fiyat: {fmt_price(bin_price)}"
            f"{listing_line}"
        )

        try:
            listing: Listing | None = None
            if listing_id:
                listing_result = await self.db.execute(
                    select(Listing).where(Listing.id == listing_id).with_for_update()
                )
                listing = listing_result.scalar_one_or_none()

            auction = Auction(
                stream_id=stream_id,
                listing_id=listing_id,
                item_name=item_name,
                start_price=start_price,
                buy_it_now_price=bin_price,
                final_price=bin_price,
                winner_id=buyer_id,
                winner_username=buyer_username,
                bid_count=bid_count,
                status="completed",
                is_bought_it_now=True,
                ended_at=datetime.now(timezone.utc),
            )
            self.db.add(auction)
            await self.db.flush()

            if listing:
                listing.is_active = False

            purchase = Purchase(
                buyer_id=buyer_id,
                listing_id=listing_id,
                auction_id=auction.id,
                price=bin_price,
                purchase_type="BUY_IT_NOW",
            )
            self.db.add(purchase)

            dm = DirectMessage(
                sender_id=user.id,
                receiver_id=buyer_id,
                content=dm_content,
            )
            self.db.add(dm)
            await self.db.commit()

        except Exception as exc:
            await self.db.rollback()
            await redis.hset(key, "status", "buy_it_now_pending")
            logger.error(
                "[HEMEN AL KABUL] DB commit HATASI | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Satın alma işlemi kaydedilemedi, lütfen tekrar deneyin")

        # Commit sonrası bildirim (non-blocking)
        try:
            await push_notification(
                buyer_id,
                {
                    "type": "auction_won",
                    "title": "🛒 Hemen Al tamamlandı!",
                    "body": f"{item_name} — {fmt_price(bin_price)}",
                    "related_id": listing_id or stream_id,
                },
                pref_key="auction_won",
            )
            logger.info(
                "[HEMEN AL KABUL] DM+bildirim gönderildi | buyer_id=%s | item=%r | price=%s",
                buyer_id, item_name, bin_price,
            )
        except Exception as exc:
            logger.error("[HEMEN AL KABUL] Bildirim gönderilemedi | buyer_id=%s | %s", buyer_id, exc)

        await redis.delete(key)

        state = {
            "status": "ended",
            "item_name": item_name,
            "bid_count": bid_count,
            "current_bid": bin_price,
            "current_bidder": buyer_username,
            "start_price": start_price,
            "buy_it_now_price": bin_price,
            "listing_id": listing_id,
        }
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        await publish_auction(stream_id, {
            "type": WS.AUCTION_ENDED_BY_BUY_IT_NOW,
            "listing_id": listing_id,
            "buyer": {"id": buyer_id, "username": buyer_username},
            "price": bin_price,
            "item_name": item_name,
        })

        # Chat'e herkese görünür özet mesajı
        chat_msg = {
            "type": WS.MESSAGE,
            "id": str(uuid.uuid4())[:8],
            "username": buyer_username,
            "content": (
                f"🛒 Hemen Alındı! "
                f"📦 {item_name} — {fmt_price(bin_price)} — "
                f"🏅 @{buyer_username}"
            ),
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

        logger.info(
            "[HEMEN AL KABUL] TAMAMLANDI | stream_id=%s buyer=%s price=%s",
            stream_id, buyer_username, bin_price,
        )
        return state

    # ── Hemen Al Red ─────────────────────────────────────────────────────────
    async def reject_buy_it_now(self, stream_id: int, user: User) -> dict:
        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        val = await redis.eval(_BUY_IT_NOW_REJECT_SCRIPT, 1, key)
        ok = int(val[0])
        if ok == 0:
            raise BadRequestException("Bekleyen Hemen Al talebi yok")

        prev_status = val[1]
        buyer_username = val[2]

        state = await get_auction_state(stream_id)
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        await publish_auction(stream_id, {
            "type": WS.BUY_IT_NOW_REJECTED,
            "buyer_username": buyer_username,
        })

        logger.info(
            "[HEMEN AL RED] | stream_id=%s host=%s buyer=%s restored_status=%s",
            stream_id, user.username, buyer_username, prev_status,
        )
        return state

    # ── Teklif Kabul ─────────────────────────────────────────────────────────
    async def accept_bid(self, stream_id: int, user: User) -> dict:
        from app.routers.notifications import push_notification

        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)

        data = await redis.hgetall(key)
        if not data or data.get("status") not in ("active", "paused"):
            raise BadRequestException("Aktif açık artırma yok")

        winner_name = data.get("current_bidder_name", "")
        if not winner_name:
            raise BadRequestException("Kabul edilecek teklif yok (henüz teklif verilmemiş)")

        winner_id_str = data.get("current_bidder_id", "")
        final_price = float(data["current_bid"])
        lid_str = data.get("listing_id", "")
        listing_id = int(lid_str) if lid_str else None
        item_name = data.get("item_name", "")

        listing_line = f"\n🔗 https://teqlif.com/ilan/{listing_id}" if listing_id else ""
        dm_content = (
            f"🏆 Tebrikler! Teklifiniz kabul edildi.\n"
            f"📦 Ürün: {item_name}\n"
            f"💰 Kazanan fiyat: {fmt_price(final_price)}"
            f"{listing_line}"
        )

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
        self.db.add(auction)

        winner_user_id: int | None = None
        if winner_id_str:
            try:
                winner_user_id = int(winner_id_str)
                dm = DirectMessage(
                    sender_id=user.id,
                    receiver_id=winner_user_id,
                    content=dm_content,
                )
                self.db.add(dm)
            except ValueError:
                logger.warning(
                    "[ACCEPT] Geçersiz winner_id_str formatı, DM atlandı | stream_id=%s winner_id_str=%r",
                    stream_id, winner_id_str,
                )
                winner_user_id = None

        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[ACCEPT] DB commit HATASI | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Teklif kabul sonucu kaydedilemedi")

        # Commit başarılı → şimdi Redis'i güncelle ve temizle
        await redis.hset(key, "status", "ended")
        await redis.delete(key)

        # Kazanana push notification (commit sonrası, non-blocking)
        if winner_user_id:
            try:
                await push_notification(
                    winner_user_id,
                    {
                        "type": "auction_won",
                        "title": "🏆 Teklifiniz kabul edildi!",
                        "body": f"{item_name} — {fmt_price(final_price)}",
                        "related_id": listing_id or stream_id,
                    },
                    pref_key="auction_won",
                )
                logger.info(
                    "[ACCEPT] DM+bildirim gönderildi | winner_id=%s | item=%r | price=%s",
                    winner_user_id, item_name, final_price,
                )
            except Exception as exc:
                logger.error("[ACCEPT] Bildirim gönderilemedi | winner_id=%s | %s", winner_user_id, exc)

        # Chat'e herkese görünür özet mesajı
        chat_summary = (
            f"🏆 Teklif kabul edildi! "
            f"📦 {item_name} — {fmt_price(final_price)} — 🏅 @{winner_name}"
        )
        chat_msg = {
            "type": WS.MESSAGE,
            "id": str(uuid.uuid4())[:8],
            "username": user.username,
            "content": chat_summary,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "is_host": True,
            "is_auction_result": True,
        }
        if listing_id:
            chat_msg["url"] = f"/ilan/{listing_id}"
        from app.services.chat_service import publish_chat
        _CHAT_KEY = f"chat:{stream_id}:messages"
        # History'ye is_auction_result bayrağı olmadan kaydet —
        # servis yeniden başlayıp history replay edildiğinde tekrar
        # gold highlight tetiklenmemesi için.
        history_msg = {k: v for k, v in chat_msg.items() if k != "is_auction_result"}
        await redis.rpush(_CHAT_KEY, json.dumps(history_msg))
        await redis.ltrim(_CHAT_KEY, -50, -1)
        await redis.expire(_CHAT_KEY, 24 * 3600)
        # Gerçek zamanlı yayına publish_chat ile gönder —
        # _topic formatını doğru paketler; direkt redis.publish değil.
        await publish_chat(stream_id, chat_msg)

        state = {
            "status": "ended",
            "item_name": item_name,
            "bid_count": int(data.get("bid_count", 0)),
            "current_bid": final_price,
            "current_bidder": winner_name,
            "start_price": float(data.get("start_price", 0)),
            "listing_id": listing_id,
        }
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info(
            "[AÇIK ARTIRMA] TEKLİF KABUL EDİLDİ | stream_id=%s winner=%s price=%s",
            stream_id, winner_name, final_price,
        )
        return state
