
from app.core.uow import AbstractUnitOfWork
from app.use_cases.auctions.auction_utils import manager, _log_fraud_attempt, fmt_price, auction_key, publish_auction, _require_host
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
from typing import Dict, Set, Optional

from app.models.enums import ListingStatus
from app.core.logger import fire_and_forget

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
from app.core.saga import Saga, SagaError
from app.core.logger import get_logger, capture_exception
from app.core.ws_manager import ws_manager
from app.constants import ws_types as WS

_DM_CHANNEL = "dm_broadcast"

logger = get_logger(__name__)

_PUBSUB_CHANNEL = "auction_broadcast"

# Telefon doğrulaması gerektiren mutlak teklif eşiği (TL)
_HIGH_BID_THRESHOLD_TL = 10_000
# Katlama kontrolü: mevcut teklif bu değerin üzerindeyken geçerli
_MULTIPLIER_MIN_BASE_TL = 500
# Mevcut fiyatın kaç katını aşarsa yüksek teklif sayılır (sadece base >= 500 TL)
_HIGH_BID_MULTIPLIER = 10


async def _log_fraud_attempt(
    fraud_type: str,
    stream_id: int,
    user_id: int,
    username: str,
    extra: dict | None = None,
) -> None:
    """
    Dolandırıcılık girişimini logger + Redis'e kaydeder.

    - Logger: Grafana/log-alert ile gerçek zamanlı izlenebilir.
    - Redis ZADD fraud_log: score=timestamp → son 30 günü tutar,
      admin sorgusu veya banlama scripti için kullanılır.
    """
    import json as _json
    import time

    payload = {
        "fraud_type": fraud_type,
        "stream_id": stream_id,
        "user_id": user_id,
        "username": username,
        **(extra or {}),
    }
    logger.warning(
        "[FRAUD_ATTEMPT] type=%s stream_id=%s user_id=%s username=%s extra=%s",
        fraud_type, stream_id, user_id, username, extra,
    )
    try:
        redis = await get_redis()
        score = time.time()
        value = _json.dumps(payload)
        await redis.zadd("fraud_log", {value: score})
        # 30 günden eski kayıtları temizle
        cutoff = score - 30 * 24 * 3600
        await redis.zremrangebyscore("fraud_log", "-inf", cutoff)
    except Exception as exc:
        logger.error("[FRAUD_ATTEMPT] Redis log yazılamadı | %s", exc)


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

    def connect(self, ws: WebSocket, stream_id: int):
        self._conns.setdefault(stream_id, set()).add(ws)
        total = len(self._conns[stream_id])
        origin = ws.headers.get("origin", "native/mobile")
        logger.info(
            "[WS] BAĞLANDI | stream_id=%s origin=%s | bu_worker=%s bağlı",
            stream_id, origin, total,
        )

    def disconnect(self, ws: WebSocket, stream_id: int):
        s = self._conns.get(stream_id)
        if s is not None:
            s.discard(ws)
            if not s:
                del self._conns[stream_id]
        total = len(self._conns.get(stream_id, set()))
        logger.info("[WS] AYRILDI | stream_id=%s | bu_worker=%s bağlı", stream_id, total)

    async def local_broadcast(self, stream_id: int, payload: dict):
        """Sadece bu worker'daki WS bağlantılarına paralel fan-out."""
        targets = list(self._conns.get(stream_id, set()))
        if not targets:
            return

        async def _send(ws: WebSocket) -> bool:
            try:
                await ws.send_json(payload)
                return True
            except Exception as exc:
                logger.error("[WS] SEND HATA | stream_id=%s | %s", stream_id, exc)
                return False

        results = await asyncio.gather(*[_send(ws) for ws in targets], return_exceptions=True)
        dead = {ws for ws, ok in zip(targets, results) if ok is not True}
        if dead:
            logger.info("[WS] %s ölü bağlantı temizlendi | stream_id=%s", len(dead), stream_id)
            s = self._conns.get(stream_id)
            if s is not None:
                s -= dead
                if not s:
                    del self._conns[stream_id]

    def conn_count(self, stream_id: int) -> int:
        return len(self._conns.get(stream_id, set()))

    def total_conns(self) -> int:
        return sum(len(v) for v in self._conns.values())


manager = _Manager()


async def pubsub_listener():
    """Her worker için tek seferlik başlatılan arka plan görevi (Redis Stream)."""
    from app.core.stream_listener import stream_listener

    async def _on_message(data: dict) -> None:
        stream_id = data.pop("_stream_id")
        await manager.local_broadcast(stream_id, data)

    await stream_listener(_PUBSUB_CHANNEL, _on_message)


async def publish_auction(stream_id: int, payload: dict):
    """Tüm worker'lara Redis Stream üzerinden yayınla + client replay için outbox'a yaz."""
    from app.core.auction_outbox import outbox_publish
    from app.core.stream_listener import STREAM_MAXLEN
    redis = await get_redis()
    data = json.dumps({"_stream_id": stream_id, **payload})
    await redis.xadd(_PUBSUB_CHANNEL, {"data": data}, maxlen=STREAM_MAXLEN, approximate=True)
    # Outbox: WebSocket reconnect'te client-side replay için ayrı per-auction stream
    await outbox_publish(stream_id, {"type": WS.AUCTION_STATE, **payload})
    logger.info(
        "[PUBSUB] YAYINLANDI | stream_id=%s status=%s | bu_worker_ws=%s",
        stream_id, payload.get("status"), manager.conn_count(stream_id),
    )


async def get_bids(stream_id: int, db: AsyncSession, limit: int = 50) -> list:
    """Bir stream'in son [limit] teklifini DB'den döner (en yeniden eskiye)."""
    result = await db.execute(
        select(Bid)
        .where(Bid.stream_id == stream_id)
        .order_by(Bid.created_at.desc())
        .limit(limit)
    )
    return result.scalars().all()



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

local increment = 1
if current >= 1000 then increment = 50
elseif current >= 500 then increment = 25
elseif current >= 100 then increment = 10 end

if amount < current + increment then return {0, 'too_low'} end
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
local increment = 1
if current >= 1000 then increment = 50
elseif current >= 500 then increment = 25
elseif current >= 100 then increment = 10 end

if amount < current + increment then return {0, 'too_low'} end

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
local buyer_id = redis.call('hget', key, 'bin_buyer_id') or ''
redis.call('hset', key, 'status', prev)
redis.call('hdel', key, 'bin_buyer_id', 'bin_buyer_username', 'pre_pending_status')
return {1, prev, buyer_username, buyer_id}
"""


# ── Servis sınıfı ────────────────────────────────────────────────────────────
class AuctionCommands:
    """
    Tüm açık artırma iş mantığını barındıran servis sınıfı.

    Kullanım:
        service = AuctionService(db)
        state = await service.start(stream_id, data, current_user)
    """

    def __init__(self, uow):
        self.uow = uow

    # ── Yardımcı: stream & host doğrulama ───────────────────────────────────
    async def _require_host(self, stream_id: int, user: User) -> LiveStream:
        from app.services.moderation_service import mod_key
        from app.utils.redis_client import get_redis

        result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
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
     # Sistem çağırdıysa sessizce dön
            raise BadRequestException("Aktif açık artırma yok")

        winner_id_str = data.get("current_bidder_id", "")
        final_price = float(data["current_bid"]) if data.get("current_bid") else float(data.get("start_price", 0))
        lid_str = data.get("listing_id", "")

        bid_count = int(data.get("bid_count", 0))

        if bid_count > 0:
            auction = Auction(
                stream_id=stream_id,
                listing_id=int(lid_str) if lid_str else None,
                item_name=data.get("item_name", ""),
                start_price=float(data.get("start_price", 0)),
                final_price=final_price if data.get("current_bidder_id") else None,
                winner_id=int(winner_id_str) if winner_id_str else None,
                winner_username=data.get("current_bidder_name") or None,
                bid_count=bid_count,
                status="completed",
                ended_at=datetime.now(timezone.utc),
                proof_image_url=proof_image_url,
            )
            self.uow.session.add(auction)

            if lid_str and data.get("current_bidder_id"):
                from sqlalchemy import update
                from app.models.listing import Listing
                await self.uow.session.execute(
                    update(Listing).where(Listing.id == int(lid_str)).values(
                        last_sold_price=final_price,
                        last_start_price=float(data.get("start_price", 0))
                    )
                )
            try:
                await self.uow.session.commit()
            except Exception as exc:
                await self.uow.session.rollback()
                logger.error(
                    "[AÇIK ARTIRMA] end DB commit HATASI | stream_id=%s | %s",
                    stream_id, exc, exc_info=True,
                )
                capture_exception(exc)
                raise DatabaseException("Açık artırma sonucu kaydedilemedi")

        # Kazananlar listesini Redis'ten al, ardından key'leri temizle
        _bidder_set_key = f"auction:bidders:{stream_id}"
        _raw_bidders = await redis.smembers(_bidder_set_key)
        _bidder_ids = [int(x) for x in _raw_bidders] if _raw_bidders else []
        await redis.delete(_bidder_set_key)
        await redis.delete(key)

        if bid_count > 0:
            from app.database_clickhouse import track_user_event
            _host_id = user.id if user else None
            _track_lid = int(lid_str) if lid_str else stream_id
            _track_type = "listing" if lid_str else "stream"
            fire_and_forget(track_user_event(
                event_type="auction_ended",
                item_id=_track_lid,
                item_type=_track_type,
                user_id=_host_id,
                price_point=final_price if data.get("current_bidder_id") else None,
            ))

        state = {
            "status": "ended",
            "winner_accepted": False,  # bitir/kes — kazanan onaylanmadı
            "item_name": data.get("item_name"),
            "bid_count": bid_count,
            "current_bid": final_price if data.get("current_bidder_id") else None,
            "current_bidder": data.get("current_bidder_name") or None,
            "start_price": float(data.get("start_price", 0)),
        }
        await publish_auction(stream_id, {"type": WS.AUCTION_STATE, **state})
        logger.info(
            "[AÇIK ARTIRMA] BİTTİ | stream_id=%s winner=%s price=%s bid_count=%s",
            stream_id, state["current_bidder"], state["current_bid"], state["bid_count"],
        )

        # Teklif verenlere artırma sona erdi bildirimi
        from app.core.task_queue import get_pool as _get_pool
        _pool = _get_pool()
        if _pool and bid_count > 0:
            await _pool.enqueue_job(
                "notify_auction_losers_task",
                stream_id,
                None,
                data.get("item_name", ""),
                final_price if data.get("current_bidder_id") else None,
                False,
                _bidder_ids,
                _queue_name="critical",
            )

        return state

    # ── Teklif Ver ───────────────────────────────────────────────────────────
    async def place_bid(self, stream_id: int, data: BidIn, user: User, bidder_ip: str | None = None) -> dict:
        from app.routers.notifications import push_notification
        from app.routers.moderation import mute_key
        from app.core.action_guard import check_user_action_rate
        from app.core.exceptions import TooManyRequestsException

        # Hız sınırı: 3 saniyede 1 teklif kuralı (Bot Spam Koruması)
        allowed, _ = await check_user_action_rate(user.id, "place_bid", limit=1, window=3)
        if not allowed:
            raise TooManyRequestsException("Teklif hızınız çok yüksek. Lütfen bekleyin.")

        result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
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

        # ── Shill Bidding Sinyali (IP Eşleşme) ───────────────────────────────
        # Aynı IP'den host ve farklı kullanıcı teklif verebilir (paylaşımlı ağ,
        # ev/ofis ortamı). Hard-block yerine sadece sinyal kaydedilir.
        host_ip_stored = prev_data.get("host_ip", "")
        if bidder_ip and host_ip_stored and bidder_ip == host_ip_stored:
            await _log_fraud_attempt(
                "shill_bidding",
                stream_id=stream_id,
                user_id=user.id,
                username=user.username,
                extra={"bidder_ip": bidder_ip, "amount": float(data.amount)},
            )

        # ── Troll Teklif Koruması (Telefon Doğrulama) ────────────────────────
        current_bid_raw = prev_data.get("current_bid")
        current_bid = float(current_bid_raw) if current_bid_raw else 0.0
        is_high_bid = (
            float(data.amount) > _HIGH_BID_THRESHOLD_TL
            or (
                current_bid >= _MULTIPLIER_MIN_BASE_TL
                and float(data.amount) > current_bid * _HIGH_BID_MULTIPLIER
            )
        )
        if is_high_bid and (not user.phone or not user.phone_verified):
            await _log_fraud_attempt(
                "troll_bid_no_phone",
                stream_id=stream_id,
                user_id=user.id,
                username=user.username,
                extra={"amount": float(data.amount), "current_bid": current_bid},
            )
            raise ForbiddenException(
                "Yüksek tutarlı teklifler için lütfen Profilinizden telefon numaranızı doğrulayın."
            )

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
        self.uow.session.add(new_bid)
        try:
            await self.uow.session.commit()
        except Exception as exc:
            await self.uow.session.rollback()
            logger.error(
                "[TEKLİF] DB commit HATASI | stream_id=%s user=%s amount=%s | %s",
                stream_id, user.username, data.amount, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Teklif kaydedilemedi, lütfen tekrar deneyin")

        await redis.sadd(f"auction:bidders:{stream_id}", str(user.id))

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
        _price_str = f"₺{data.amount:,.0f}".replace(",", ".")
        if stream and stream.host_id:
            fire_and_forget(push_notification(
                user_id=stream.host_id,
                notif={
                    "type": "new_bid",
                    "i18n": {
                        "title_key": "notifNewBid",
                        "title_params": {"username": user.username},
                        "body_key": "notifNewBidBody" if prev_item_name else "notifNewBidBodyNoItem",
                        "body_params": ({"item": prev_item_name, "price": _price_str}
                                        if prev_item_name else {"price": _price_str}),
                    },
                    "related_id": stream_id,
                    "stream_id": stream_id,
                },
                pref_key="new_bid",
                amount=float(data.amount),
            ))

        if prev_bidder_id_str and prev_bidder_id_str != str(user.id):
            try:
                prev_bidder_id = int(prev_bidder_id_str)
                from app.core.task_queue import get_pool as _get_pool
                _pool = _get_pool()
                if _pool:
                    await _pool.enqueue_job(
                        "notify_outbid_task",
                        prev_bidder_id,
                        stream_id,
                        prev_item_name,
                        float(data.amount),
                        _queue_name="critical",
                        # Bid ID bazlı job_id: ARQ aynı teklif için iki kez
                        # retry'da bile kullanıcıya tek push gönderir.
                        _job_id=f"outbid:{stream_id}:{prev_bidder_id}:{int(data.amount)}",
                    )
                else:
                    fire_and_forget(push_notification(
                        user_id=prev_bidder_id,
                        notif={
                            "type": "outbid",
                            "i18n": {
                                "title_key": "notifOutbid",
                                "body_key": "notifOutbidBody" if prev_item_name else "notifOutbidBodyNoItem",
                                "body_params": ({"item": prev_item_name, "price": _price_str}
                                                if prev_item_name else {"price": _price_str}),
                            },
                            "related_id": stream_id,
                            "stream_id": stream_id,
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

        result = await self.uow.session.execute(select(LiveStream).where(LiveStream.id == stream_id))
        stream = result.scalar_one_or_none()
        if not stream:
            raise NotFoundException("Yayın bulunamadı")
        if stream.host_id == user.id:
            raise ForbiddenException("Host kendi açık artırmasını satın alamaz")
        if not stream.is_live:
            raise BadRequestException("Yayın aktif değil")

        from app.core.exceptions import TooManyRequestsException
        
        redis = await get_redis()
        key = auction_key(stream_id)

        # DoS Koruması: Önceki talebi reddedildiyse 60 saniyelik cooldown bloğu.
        cooldown_key = f"bin_cooldown:{stream_id}:{user.id}"
        if await redis.get(cooldown_key):
            raise TooManyRequestsException("Hemen Al talebiniz reddedildiği için kısa bir süre yeni istek gönderemezsiniz.")

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
    async def accept_buy_it_now(self, stream_id: int, user: User, proof_image_url: Optional[str] = None) -> dict:
        from app.routers.notifications import push_notification

        await self._require_host(stream_id, user)
        redis = await get_redis()
        key = auction_key(stream_id)
        
        logger.info(f"[DEBUG_PROOF] accept_buy_it_now called for stream {stream_id}. proof_image_url={proof_image_url}")

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
                listing_result = await self.uow.session.execute(
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
                proof_image_url=proof_image_url,
            )
            self.uow.session.add(auction)
            await self.uow.session.flush()

            if listing:
                listing.status = ListingStatus.PASSIVE

            purchase = Purchase(
                buyer_id=buyer_id,
                listing_id=listing_id,
                auction_id=auction.id,
                price=bin_price,
                purchase_type="BUY_IT_NOW",
            )
            self.uow.session.add(purchase)

            winner_dm_content = dm_content + f"\n📋 teqlif://auction/{auction.id}"
            dm = DirectMessage(
                sender_id=user.id,
                receiver_id=buyer_id,
                content=winner_dm_content,
            )
            self.uow.session.add(dm)
            await self.uow.session.commit()

        except Exception as exc:
            await self.uow.session.rollback()
            await redis.hset(key, "status", "buy_it_now_pending")
            logger.error(
                "[HEMEN AL KABUL] DB commit HATASI | stream_id=%s | %s",
                stream_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Satın alma işlemi kaydedilemedi, lütfen tekrar deneyin")

        # DM WS broadcast (satıcı→alıcı mesajı her iki tarafa bildir)
        try:
            now_iso = datetime.now(timezone.utc).isoformat()
            buyer_dm_payload = {
                "type": "message",
                "id": dm.id,
                "sender_id": user.id,
                "receiver_id": buyer_id,
                "sender_username": user.username,
                "content": winner_dm_content,
                "is_read": False,
                "created_at": now_iso,
            }
            fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{buyer_id}", buyer_dm_payload))
            fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{user.id}", buyer_dm_payload))
        except Exception as exc:
            logger.error("[HEMEN AL KABUL] DM WS broadcast başarısız | %s", exc)

        # Commit sonrası bildirim (non-blocking)
        try:
            await push_notification(
                buyer_id,
                {
                    "type": "auction_won",
                    "i18n": {
                        "title_key": "notifBuyItNow",
                        "body_key": "notifBuyItNowBody",
                        "body_params": {"item": item_name, "price": fmt_price(bin_price)},
                    },
                    "related_id": listing_id or stream_id,
                    **({"listing_id": listing_id} if listing_id else {"stream_id": stream_id}),
                },
                pref_key="auction_won",
            )
            logger.info(
                "[HEMEN AL KABUL] DM+bildirim gönderildi | buyer_id=%s | item=%r | price=%s",
                buyer_id, item_name, bin_price,
            )
        except Exception as exc:
            logger.error("[HEMEN AL KABUL] Bildirim gönderilemedi | buyer_id=%s | %s", buyer_id, exc)

        _bidder_set_key = f"auction:bidders:{stream_id}"
        _raw_bidders = await redis.smembers(_bidder_set_key)
        _bidder_ids = [int(x) for x in _raw_bidders] if _raw_bidders else []
        await redis.delete(_bidder_set_key)
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

        # Teklif verip kaybedenlere bildirim (hemen al ile bitti)
        if bid_count > 0:
            from app.core.task_queue import get_pool as _get_pool
            _pool = _get_pool()
            if _pool:
                await _pool.enqueue_job(
                    "notify_auction_losers_task",
                    stream_id,
                    buyer_id,
                    item_name,
                    bin_price,
                    True,
                    _bidder_ids,
                    _queue_name="critical",
                )

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
        await redis.rpush(_CHAT_KEY, json.dumps(chat_msg))
        await redis.ltrim(_CHAT_KEY, -50, -1)
        await redis.expire(_CHAT_KEY, 24 * 3600)
        from app.use_cases.chat.chat_utils import publish_chat
        await publish_chat(stream_id, chat_msg)

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
        buyer_id = val[3] if len(val) > 3 else None
        
        # Hemen al talebini reddettik, kötü niyetli döngü saldırılarını kırmak için
        # reddedilen kişiye 60 saniye cooldown (işlem engeli) koyuyoruz.
        if buyer_id and buyer_id != '':
            await redis.set(f"bin_cooldown:{stream_id}:{buyer_id}", "1", ex=60)

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
    async def accept_bid(self, stream_id: int, user: User, proof_image_url: Optional[str] = None) -> dict:
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
        original_status = data.get("status", "active")  # kompanzasyon için

        listing_line = f"\n🔗 https://teqlif.com/ilan/{listing_id}" if listing_id else ""
        dm_content = (
            f"🏆 Tebrikler! Teklifiniz kabul edildi.\n"
            f"📦 Ürün: {item_name}\n"
            f"💰 Kazanan fiyat: {fmt_price(final_price)}"
            f"{listing_line}"
        )

        listing: Listing | None = None
        if listing_id:
            listing_result = await self.uow.session.execute(
                select(Listing).where(Listing.id == listing_id).with_for_update()
            )
            listing = listing_result.scalar_one_or_none()

        # ── Saga: her adımda kompanzasyon tanımlı ────────────────────────────
        saga = Saga("accept_bid")
        auction: Auction | None = None
        dm: DirectMessage | None = None
        winner_user_id: int | None = None

        async def _create_auction():
            nonlocal auction
            _a = Auction(
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
                proof_image_url=proof_image_url,
            )
            self.uow.session.add(_a)
            await self.uow.session.flush()
            auction = _a
            return _a

        async def _compensate_auction():
            if auction and auction.id:
                await self.uow.session.delete(auction)
                await self.uow.session.flush()
            # Redis state'i geri yükle
            await redis.hset(key, "status", original_status)

        await saga.step("create_auction", do=_create_auction, compensate=_compensate_auction)

        if listing:
            _prev_active = (listing.status == ListingStatus.ACTIVE)
            async def _deactivate_listing():
                listing.status = ListingStatus.PASSIVE
            async def _reactivate_listing():
                listing.status = ListingStatus.ACTIVE if _prev_active else ListingStatus.PASSIVE
            await saga.step("deactivate_listing", do=_deactivate_listing, compensate=_reactivate_listing)

        async def _create_purchase_and_dm():
            nonlocal winner_user_id, dm
            if not winner_id_str:
                return
            try:
                _winner_user_id = int(winner_id_str)
            except ValueError:
                return
            winner_user_id = _winner_user_id
            if listing_id:
                purchase = Purchase(
                    buyer_id=winner_user_id,
                    listing_id=listing_id,
                    auction_id=auction.id,
                    price=final_price,
                    purchase_type="AUCTION_WIN",
                )
                self.uow.session.add(purchase)
            from app.models.analytics import UserInteraction
            if listing_id:
                self.uow.session.add(UserInteraction(
                    user_id=winner_user_id,
                    item_id=listing_id,
                    item_type="listing",
                    interaction_type="auction_won",
                ))
            _winner_dm_content = dm_content + f"\n📋 teqlif://auction/{auction.id}"
            _dm = DirectMessage(
                sender_id=user.id,
                receiver_id=winner_user_id,
                content=_winner_dm_content,
            )
            self.uow.session.add(_dm)
            dm = _dm

        await saga.step("create_purchase_dm", do=_create_purchase_and_dm, compensate=None)

        try:
            await self.uow.session.commit()
        except Exception as exc:
            await self.uow.session.rollback()
            # Redis state'i geri yükle (DB commit başarısız oldu)
            await redis.hset(key, "status", original_status)
            logger.error("[ACCEPT] DB commit HATASI | stream_id=%s | %s", stream_id, exc, exc_info=True)
            capture_exception(exc)
            raise DatabaseException("Teklif kabul sonucu kaydedilemedi")

        winner_dm_content = dm_content + (f"\n📋 teqlif://auction/{auction.id}" if auction else "")

        # Commit başarılı → kazananlar listesini al, Redis key'leri temizle
        _bidder_set_key = f"auction:bidders:{stream_id}"
        _raw_bidders = await redis.smembers(_bidder_set_key)
        _bidder_ids = [int(x) for x in _raw_bidders] if _raw_bidders else []
        await redis.delete(_bidder_set_key)
        await redis.delete(key)

        # DM WS broadcast (satıcı→kazanan mesajı her iki tarafa bildir)
        if winner_user_id and dm:
            try:
                now_iso = datetime.now(timezone.utc).isoformat()
                winner_dm_payload = {
                    "type": "message",
                    "id": dm.id,
                    "sender_id": user.id,
                    "receiver_id": winner_user_id,
                    "sender_username": user.username,
                    "content": winner_dm_content,
                    "is_read": False,
                    "created_at": now_iso,
                }
                fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{winner_user_id}", winner_dm_payload))
                fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{user.id}", winner_dm_payload))
            except Exception as exc:
                logger.error("[ACCEPT] DM WS broadcast başarısız | %s", exc)

        # Kazananın preference_embedding'ini kuyruğa al
        if winner_user_id:
            try:
                from app.core.task_queue import get_pool
                pool = get_pool()
                if pool:
                    await pool.enqueue_job(
                        "update_user_preference_embedding",
                        winner_user_id,
                        _job_id=f"pref_emb:{winner_user_id}",
                    )
            except Exception as exc:
                logger.warning("[ACCEPT] preference_embedding kuyruğa alınamadı | winner_id=%s | %s", winner_user_id, exc)

        from app.database_clickhouse import track_user_event
        if winner_user_id and listing_id:
            fire_and_forget(track_user_event(
                event_type="auction_won",
                item_id=listing_id,
                item_type="listing",
                user_id=winner_user_id,
                price_point=final_price,
            ))

        # Kazanana push notification (commit sonrası, non-blocking)
        if winner_user_id:
            try:
                await push_notification(
                    winner_user_id,
                    {
                        "type": "auction_won",
                        "i18n": {
                            "title_key": "notifAuctionWon",
                            "body_key": "notifAuctionWonBody",
                            "body_params": {"item": item_name, "price": fmt_price(final_price)},
                        },
                        "related_id": listing_id or stream_id,
                        **({"listing_id": listing_id} if listing_id else {"stream_id": stream_id}),
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
        from app.use_cases.chat.chat_utils import publish_chat
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
            "winner_accepted": True,   # accept_bid → kazanan onaylandı
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

        # Kaybedenlere bildirim (kazanan hariç tüm teklif verenler)
        from app.core.task_queue import get_pool as _get_pool
        _pool = _get_pool()
        if _pool and int(data.get("bid_count", 0)) > 1:
            await _pool.enqueue_job(
                "notify_auction_losers_task",
                stream_id,
                winner_user_id,
                item_name,
                final_price,
                True,
                _bidder_ids,
                _queue_name="critical",
            )

        return state
