import json
import logging
import math
import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, func, text as sql_text
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Any, Dict, Optional, List

from app.models.enums import ListingStatus
from app.database import get_db
from app.models.analytics import AnalyticsEvent
from app.models.auction import Auction
from app.models.listing import Listing
from app.models.purchase import Purchase
from app.models.stream import LiveStream
from app.models.tuci_transaction import TuciTransaction
from app.models.user import User
from app.schemas.analytics import AnalyticsEventCreate, FeedEventBatch, SearchEventCreate
from app.utils.auth import decode_token, get_current_user
from app.utils.redis_client import get_redis
from app.core.exceptions import AppException, InsufficientFundsException, ServiceException, ForbiddenException
from app.database_clickhouse import get_clickhouse_client
from app.models.market_index import ExchangeRates
from app.services.ml.ner_service import extract_ner
from app.utils.i18n import _get_t, get_locale

AI_PRICE_ESTIMATE_COST = 5   # TUCi (standart kullanıcılar ve PRO limit aşınca)
AI_PRICE_LIMIT_PRO    = 6  # PRO kullanıcılar ayda 6 ücretsiz sorgu

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/analytics", tags=["analytics"])

INTERACTION_QUEUE = "interaction_queue"


class InteractionPayload(BaseModel):
    item_id: int
    item_type: str = Field(max_length=20)
    interaction_type: str = Field(max_length=30)
    duration_seconds: Optional[float] = None
    price_point: Optional[float] = None
    metadata: Optional[Dict[str, Any]] = None
    user_id: Optional[int] = None  # mobil fallback — JWT expire olduğunda kullanılır

async def _save_event_async(data: AnalyticsEventCreate, user_id: int | None, ip_address: str | None, db: AsyncSession):
    try:
        event = AnalyticsEvent(
            session_id=data.session_id,
            user_id=user_id,
            event_type=data.event_type,
            url=data.url,
            device_type=data.device_type,
            os=data.os,
            browser=data.browser,
            ip_address=ip_address,
            event_metadata=data.event_metadata,
        )
        db.add(event)
        await db.commit()
    except Exception as exc:
        logger.error("[ANALYTICS] Error saving event: %s", exc)

@router.post("/track", status_code=202)
async def track_event(
    data: AnalyticsEventCreate,
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
):
    """
    Receives tracking events from web or mobile clients.
    Uses BackgroundTasks for latency-free responses.
    """
    # Try to extract user_id if token is present in Authorization header
    user_id = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split(" ")[1]
        try:
            user_id = decode_token(token)
        except Exception:
            pass

    # Extract IP address safely
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        ip_address = forwarded.split(",")[0].strip()
    else:
        ip_address = request.client.host if request.client else None

    # Save to database asynchronously in the background
    background_tasks.add_task(_save_event_async, data, user_id, ip_address, db)

    return {"status": "queued"}


@router.post("/interaction", status_code=202)
async def track_interaction(
    payload: InteractionPayload,
    request: Request,
):
    """
    Mobil/web istemciden implicit sinyal alır (görüntüleme süresi, swipe vb.).
    DB'ye yazmaz — Redis kuyruğuna (interaction_queue) ekler.
    Worker periyodik olarak kuyruğu boşaltır ve bulk-insert yapar.
    """
    # JWT decode: sunucu imzası güvenilir → öncelikli kaynak
    # Fallback: mobil istemcinin body'ye gömdüğü user_id (JWT expire durumu)
    user_id = payload.user_id  # fallback
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            user_id = decode_token(auth_header.split(" ")[1])  # JWT her zaman kazanır
        except Exception:
            pass  # fallback (payload.user_id) korunur

    from datetime import datetime, timezone
    record = {
        "user_id": user_id,
        "item_id": payload.item_id,
        "item_type": payload.item_type,
        "interaction_type": payload.interaction_type,
        "duration_seconds": payload.duration_seconds,
        "price_point": payload.price_point,
        "metadata": payload.metadata,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    try:
        redis = await get_redis()
        await redis.rpush(INTERACTION_QUEUE, json.dumps(record))

        # Cold start tetikleyici: ilk 3/5/10/20 etkileşimde embedding + interests hemen yenile
        if user_id and payload.item_type == "listing":
            count_key = f"interaction_count:{user_id}"
            count = await redis.incr(count_key)
            if count == 1:
                await redis.expire(count_key, 86400)  # 24h TTL
            if count in {3, 5, 10, 20}:
                try:
                    from arq import create_pool
                    from app.worker import WorkerSettings
                    pool = await create_pool(WorkerSettings.redis_settings)
                    # Interaction queue'yu hemen flush et, ardından embedding hesapla
                    await pool.enqueue_job("flush_interactions_to_db")
                    await pool.enqueue_job(
                        "update_user_preference_embedding",
                        user_id,
                        _job_id=f"pref_emb:{user_id}",
                    )
                    await pool.enqueue_job("compute_user_interests_task")
                    await pool.aclose()
                except Exception as arq_exc:
                    logger.warning("[ANALYTICS] Cold start trigger başarısız: %s", arq_exc)

        # Sıcak ilan spike dedektörü: 24 saat içinde 3. bid_hesitation → satıcıya bildirim
        if payload.interaction_type == "bid_hesitation" and payload.item_type == "listing":
            try:
                # Feed geri beslemesi: bu ilan tekrar feed'de gösterilmeli (seen_decay sıfırla)
                hes_key = f"hesitated:{user_id}"
                await redis.sadd(hes_key, str(payload.item_id))
                await redis.expire(hes_key, 7 * 86400)  # 7 gün TTL

                spike_key = f"hes_spike:{payload.item_id}"
                spike_count = await redis.incr(spike_key)
                if spike_count == 1:
                    await redis.expire(spike_key, 86400)  # 24h TTL
                if spike_count == 3:
                    from app.core.task_queue import get_pool as _get_pool
                    _pool = _get_pool()
                    if _pool:
                        await _pool.enqueue_job(
                            "notify_hot_listing_task",
                            payload.item_id,
                            spike_count,
                            _job_id=f"hot_listing:{payload.item_id}",
                            _queue_name="critical",
                        )
            except Exception as spike_exc:
                logger.warning("[ANALYTICS] Hesitation spike check başarısız: %s", spike_exc)

    except Exception as exc:
        logger.error("[ANALYTICS] Redis rpush başarısız: %s", exc)

    return {"status": "queued"}


# ── Satıcı Yayın Raporu ───────────────────────────────────────────────────────

def _build_recommendation(avg_budget: float | None, hesitation_count: int, unique_users: int, t: dict) -> str:
    """
    Metriklere göre kişiselleştirilmiş öneri metni üretir.
    Kural tabanlı 'makul AI' — harici API gerektirmez.
    """
    if avg_budget is None or avg_budget <= 0:
        if hesitation_count > 5:
            return t.get("recNoBudgetHighHesitation", "Bugün {count} izleyici teklif vermekle ilgilendi ama tereddüt etti. Bir dahaki yayında daha düşük başlangıç fiyatıyla başlayarak ilgiyi satışa dönüştürebilirsiniz.").format(count=hesitation_count)
        return t.get("recNoBudgetDefault", "Henüz yeterli bütçe verisi yok. Yayınlarınızı düzenli tutarak kitle profili oluştururken fiyat aralıklarını deneyebilirsiniz.")

    budget_fmt = f"{int(avg_budget):,}".replace(",", ".")

    if hesitation_count >= 10:
        low = int(avg_budget * 0.7)
        low_fmt = f"{low:,}".replace(",", ".")
        return t.get("recHighHesitation", "İzleyicilerinizin ortalama bütçesi {budget} TL. Bugün {count} kişi teklif vermek istedi ama vazgeçti — bir dahaki yayında {low} TL gibi düşük başlangıç fiyatları deneyerek bu kararsız kitleyi satışa çevirebilirsiniz.").format(budget=budget_fmt, count=hesitation_count, low=low_fmt)
    elif hesitation_count >= 3:
        return t.get("recMedHesitation", "İzleyicilerinizin ortalama bütçesi {budget} TL. {count} izleyici tekliften vazgeçti — ürün açıklamalarını ve fiyat adımlarını netleştirerek dönüşüm oranınızı artırabilirsiniz.").format(budget=budget_fmt, count=hesitation_count)
    elif unique_users >= 10:
        high = int(avg_budget * 1.15)
        high_fmt = f"{high:,}".replace(",", ".")
        return t.get("recHighReach", "İzleyicilerinizin ortalama bütçesi {budget} TL. Kitle profiliniz güçlü görünüyor. Bir dahaki yayında {high} TL'ye kadar premium ürünler sunarak geliri artırabilirsiniz.").format(budget=budget_fmt, high=high_fmt)
    else:
        return t.get("recDefault", "İzleyicilerinizin ortalama bütçesi {budget} TL. Bu fiyat bandında ürünler getirerek satışlarınızı artırabilirsiniz.").format(budget=budget_fmt)


@router.get("/seller-report/{stream_id}")
async def get_seller_report(
    stream_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Yayın sonu satıcı analiz raporu.

    Yalnızca yayının host'u erişebilir.
    ClickHouse'dan o yayının açık artırma ilanlarına ait metrikler çekilir:
      - unique_viewers: etkileşimde bulunan tekil kullanıcı sayısı
      - avg_budget: ortalama price_point (TL)
      - hesitation_count: 'bid_hesitation' event sayısı
      - stream_duration_minutes: yayın süresi
      - recommendation: kural tabanlı öneri metni
    """
    # ── 1. Yayını getir ve host doğrula ──────────────────────────────────────
    t = _get_t(get_locale(current_user, request))
    
    stream = await db.scalar(select(LiveStream).where(LiveStream.id == stream_id))
    if stream is None:
        raise HTTPException(status_code=404, detail=t.get("errStreamNotFound", "Yayın bulunamadı"))
    if stream.host_id != current_user.id:
        raise HTTPException(status_code=403, detail=t.get("errAccessDenied", "Bu rapora erişim yetkiniz yok"))

    # Yayın süresi (dakika)
    from datetime import datetime, timezone
    ended = stream.ended_at or datetime.now(timezone.utc)
    duration_minutes = max(0, int((ended - stream.started_at).total_seconds() / 60))

    # ── 2. Bu yayındaki tüm açık artırmaları çek ─────────────────────────────
    auctions_result = await db.execute(
        select(Auction).where(Auction.stream_id == stream_id).order_by(Auction.started_at)
    )
    auctions = auctions_result.scalars().all()

    listing_ids = [a.listing_id for a in auctions if a.listing_id is not None]

    # Açık artırma özeti
    successful = [a for a in auctions if a.winner_username is not None]
    total_revenue = sum(a.final_price or 0 for a in successful)
    total_bids = sum(a.bid_count for a in auctions)

    auction_items = []
    for a in auctions:
        dur = 0
        if a.ended_at and a.started_at:
            dur = max(0, int((a.ended_at - a.started_at).total_seconds() / 60))
        auction_items.append({
            "item_name": a.item_name,
            "start_price": a.start_price,
            "final_price": a.final_price,
            "winner_username": a.winner_username,
            "bid_count": a.bid_count,
            "is_bought_it_now": a.is_bought_it_now,
            "duration_minutes": dur,
            "sold": a.winner_username is not None,
        })

    auction_summary = {
        "total_auctions": len(auctions),
        "successful_auctions": len(successful),
        "total_bids": total_bids,
        "total_revenue": round(total_revenue, 2),
        "items": auction_items,
    }

    # ── 3. ClickHouse sorgusu ─────────────────────────────────────────────────
    unique_viewers = 0
    avg_budget: float | None = None
    hesitation_count = 0
    swipe_impressions = 0
    swipe_reach = 0

    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()

        ts_start = stream.started_at.strftime("%Y-%m-%d %H:%M:%S")
        ts_end = ended.strftime("%Y-%m-%d %H:%M:%S")

        if listing_ids:
            ids_str = ", ".join(str(i) for i in listing_ids)

            # user_events: detay ekranı etkileşimleri
            result = await ch.query(f"""
                SELECT
                    countDistinct(user_id)                                   AS unique_viewers,
                    avgIf(price_point, price_point > 0)                      AS avg_budget,
                    countDistinctIf(user_id, event_type = 'bid_hesitation')  AS hesitation_count
                FROM user_events
                WHERE item_id IN ({ids_str})
                  AND item_type = 'listing'
                  AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
            """)
            row = result.result_rows[0] if result.result_rows else (0, None, 0)
            ue_unique = int(row[0] or 0)
            avg_budget = float(row[1]) if row[1] else None
            hesitation_count = int(row[2] or 0)

            # feed_analytics: swipe feed görüntülemeleri (listing_id String olarak saklanır)
            feed_result = await ch.query(f"""
                SELECT
                    count()                AS total_impressions,
                    countDistinct(user_id) AS swipe_reach
                FROM feed_analytics
                WHERE toUInt64OrZero(listing_id) IN ({ids_str})
                  AND event_type = 'impression'
                  AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
            """)
            feed_row = feed_result.result_rows[0] if feed_result.result_rows else (0, 0)
            swipe_impressions = int(feed_row[0] or 0)
            swipe_reach = int(feed_row[1] or 0)

            # unique_viewers = listing events + feed impressions + stream swipe viewers
            union_result = await ch.query(f"""
                SELECT countDistinct(uid) FROM (
                    SELECT toString(user_id) AS uid FROM user_events
                    WHERE item_id IN ({ids_str}) AND item_type = 'listing'
                      AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
                      AND user_id IS NOT NULL
                    UNION ALL
                    SELECT user_id AS uid FROM feed_analytics
                    WHERE toUInt64OrZero(listing_id) IN ({ids_str})
                      AND event_type = 'impression'
                      AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
                      AND user_id IS NOT NULL AND user_id != ''
                    UNION ALL
                    SELECT toString(user_id) AS uid FROM user_events
                    WHERE item_type = 'stream' AND item_id = {stream_id}
                      AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
                      AND user_id IS NOT NULL
                )
            """)
            union_row = union_result.result_rows[0] if union_result.result_rows else (0,)
            unique_viewers = int(union_row[0] or 0)
        else:
            # Açık artırma ilanı yoksa stream-level swipe impression'ları say
            result = await ch.query(f"""
                SELECT countDistinct(user_id), avgIf(price_point, price_point > 0), 0
                FROM user_events
                WHERE item_type = 'stream'
                  AND item_id = {stream_id}
                  AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
            """)
            row = result.result_rows[0] if result.result_rows else (0, None, 0)
            unique_viewers = int(row[0] or 0)
            avg_budget = float(row[1]) if row[1] else None

    except Exception as ch_exc:
        logger.warning("[SellerReport] ClickHouse sorgusu başarısız: %s", ch_exc)

    # ── 4. Öneri metni ────────────────────────────────────────────────────────
    t = _get_t(get_locale(current_user, request))
    recommendation = _build_recommendation(avg_budget, hesitation_count, unique_viewers, t)

    return {
        "stream_id": stream_id,
        "stream_title": stream.title,
        "duration_minutes": duration_minutes,
        "peak_viewers": stream.viewer_count,
        "unique_viewers": unique_viewers,
        "avg_budget": round(avg_budget, 2) if avg_budget else None,
        "hesitation_count": hesitation_count,
        "swipe_impressions": swipe_impressions,
        "swipe_reach": swipe_reach,
        "recommendation": recommendation,
        "auction_summary": auction_summary,
    }


# ── Yapay Zeka Fiyatlama Danışmanı ───────────────────────────────────────────

import calendar as _calendar
from datetime import datetime as _datetime, date as _date

def _ai_billing_start(premium_since: _datetime) -> _date:
    today = _date.today()
    day   = premium_since.day
    last_this = _calendar.monthrange(today.year, today.month)[1]
    ann_this  = _date(today.year, today.month, min(day, last_this))
    if today >= ann_this:
        return ann_this
    prev_m = today.month - 1 if today.month > 1 else 12
    prev_y = today.year if today.month > 1 else today.year - 1
    return _date(prev_y, prev_m, min(day, _calendar.monthrange(prev_y, prev_m)[1]))

def _ai_next_billing(premium_since: _datetime) -> _date:
    p   = _ai_billing_start(premium_since)
    day = premium_since.day
    nm  = p.month + 1 if p.month < 12 else 1
    ny  = p.year if p.month < 12 else p.year + 1
    return _date(ny, nm, min(day, _calendar.monthrange(ny, nm)[1]))

def _ai_redis_key(user_id: int, premium_since: _datetime | None = None) -> str:
    if premium_since:
        period = _ai_billing_start(premium_since)
        return f"ai_price_credits:{user_id}:{period.isoformat()}"
    month = _datetime.now().strftime("%Y-%m")
    return f"ai_price_credits:{user_id}:{month}"

async def _get_ai_used(user_id: int, premium_since: _datetime | None = None) -> int:
    try:
        redis = await get_redis()
        val = await redis.get(_ai_redis_key(user_id, premium_since))
        return int(val) if val else 0
    except Exception:
        return 0

async def _increment_ai_atomic(user_id: int, premium_since: _datetime | None = None) -> int:
    try:
        redis = await get_redis()
        key   = _ai_redis_key(user_id, premium_since)
        count = await redis.incr(key)
        if count == 1:
            now = _datetime.now()
            if premium_since:
                nxt      = _ai_next_billing(premium_since)
                end_dt   = _datetime(nxt.year, nxt.month, nxt.day, 0, 0, 0)
            else:
                last_day = _calendar.monthrange(now.year, now.month)[1]
                end_dt   = _datetime(now.year, now.month, last_day, 23, 59, 59)
            ttl_secs = int((end_dt - now).total_seconds()) + 1
            await redis.expire(key, ttl_secs)
        return count
    except Exception:
        return 0


@router.get("/ai-price-credits")
async def ai_price_credits(current_user: User = Depends(get_current_user)):
    """PRO kullanıcının bu ayki AI fiyat danışmanı kredi durumunu döndürür."""
    if not current_user.is_premium:
        return {"used": 0, "limit": 0, "remaining": 0, "is_premium": False, "renewal_date": None}
    used = await _get_ai_used(current_user.id, current_user.premium_since)
    remaining = max(0, AI_PRICE_LIMIT_PRO - used)
    renewal_date: str | None = None
    if current_user.premium_since:
        renewal_date = _ai_next_billing(current_user.premium_since).isoformat()
    return {
        "used": used,
        "limit": AI_PRICE_LIMIT_PRO,
        "remaining": remaining,
        "is_premium": True,
        "renewal_date": renewal_date,
    }


@router.get("/reactivation-credits")
async def reactivation_credits(current_user: User = Depends(get_current_user)):
    """PRO kullanıcının bu ayki reaktivasyon kredi durumunu döndürür."""
    from app.use_cases.listings.queries.get_reactivation_cost import (
        _get_reactivation_used,
        _reactivation_next_billing,
        _REACTIVATION_FREE_MONTHLY,
        _REACTIVATION_COST_TUCI,
    )
    if not current_user.is_premium:
        can_afford = current_user.tuci_balance >= _REACTIVATION_COST_TUCI
        return {
            "used": 0,
            "limit": 0,
            "remaining": 0,
            "free_remaining": 0,
            "is_premium": False,
            "renewal_date": None,
            "cost": _REACTIVATION_COST_TUCI,
            "balance": current_user.tuci_balance,
            "can_afford": can_afford,
        }
    used      = await _get_reactivation_used(current_user.id, current_user.premium_since)
    remaining = max(0, _REACTIVATION_FREE_MONTHLY - used)
    is_free   = remaining > 0
    cost      = 0 if is_free else _REACTIVATION_COST_TUCI
    can_afford = is_free or current_user.tuci_balance >= _REACTIVATION_COST_TUCI
    renewal_date: str | None = None
    if current_user.premium_since:
        renewal_date = _reactivation_next_billing(current_user.premium_since).isoformat()
    return {
        "used": used,
        "limit": _REACTIVATION_FREE_MONTHLY,
        "remaining": remaining,
        "free_remaining": remaining,
        "is_premium": True,
        "renewal_date": renewal_date,
        "cost": cost,
        "balance": current_user.tuci_balance,
        "can_afford": can_afford,
    }


_PRICE_CAT_LABELS: dict[str, str] = {
    "elektronik": "Elektronik ve Teknoloji",
    "vasita": "Araç ve Taşıt",
    "emlak": "Emlak ve Konut",
    "giyim": "Giyim ve Moda",
    "spor": "Spor ve Outdoor",
    "kitap": "Kitap ve Eğitim",
    "ev": "Ev ve Yaşam",
    "diger": "Diğer",
}


class PriceEstimateRequest(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(default="", max_length=2000)
    category: str = Field(default="")
    city: str = Field(default="")
    condition: str = Field(default="")
    image_url: str = Field(default="")
    image_phash: str | None = Field(default=None)
    exclude_listing_id: int = Field(default=0)


@router.post("/price-estimate")
async def price_estimate(
    request: Request,
    body: PriceEstimateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Multi-sinyal AI fiyat tahmini.
    Sinyal ağırlıkları: semantik embedding × kategori (x2) × şehir (x1.3) × güncellik × pHash (x1.5)
    IQR aykırı değer temizleme + ağırlıklı fiyat ortalaması + kategori bazlı güven seviyesi.
    """
    from datetime import datetime as _dt2, timezone as _tz2

    # ── Limit / bakiye kontrolü (Sadece bakiye yeterliliği test edilir) ──
    # Not: Limit düşümü işlemin sonunda atomik olarak yapılacak.
    if current_user.is_premium:
        # Ön kontrol (atomik değil ama sadece bilgilendirme amaçlı)
        ai_used = await _get_ai_used(current_user.id, current_user.premium_since)
        if ai_used >= AI_PRICE_LIMIT_PRO and current_user.tuci_balance < AI_PRICE_ESTIMATE_COST:
            raise InsufficientFundsException("Aylık ücretsiz kullanım hakkınız doldu ve yeterli TUCi bakiyeniz yok.")
    else:
        if current_user.tuci_balance < AI_PRICE_ESTIMATE_COST:
            raise InsufficientFundsException()

    from app.services.ml.ml_service import generate_embedding

    # 1. Embedding: kategori etiketi + başlık + açıklama (Redis Caching)
    import hashlib
    cat_label = _PRICE_CAT_LABELS.get(body.category.strip(), body.category.strip())
    combined = " ".join(filter(None, [
        cat_label,
        body.title.strip(),
        body.description.strip()[:500],
    ]))
    combined_hash = hashlib.md5(combined.encode("utf-8")).hexdigest()
    emb_cache_key = f"cache:embedding:{combined_hash}"
    
    redis = await get_redis()
    cached_emb = await redis.get(emb_cache_key)
    if cached_emb:
        emb_str = cached_emb.decode("utf-8") if isinstance(cached_emb, bytes) else cached_emb
    else:
        # FastAPI'nin bloklanmaması için işlemi ARQ worker'a atıyoruz.
        job = await request.app.state.arq_pool.enqueue_job("generate_embedding_task", combined)
        if not job:
            raise ServiceException("Yapay zeka servisi şu an meşgul. Lütfen tekrar deneyin.")

        try:
            # Worker'dan sonucu en fazla 15 saniye bekliyoruz.
            embedding: list[float] = await job.result(timeout=15.0)
        except Exception:
            raise ServiceException("Yapay zeka servisi yanıt vermedi. Lütfen tekrar deneyin.")
        
        emb_str = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"
        await redis.setex(emb_cache_key, 7 * 24 * 3600, emb_str)  # 7 gün cache

    # 2. Opsiyonel: yüklenmiş görselin pHash'i (Ağ gecikmesi önlendi)
    body_phash: str | None = body.image_phash

    # 3. NER Extraction
    ner_data = extract_ner(body.title, body.description, body.category)
    t_brand = ner_data.get("brand") or ""
    t_model = ner_data.get("model_name") or ""
    # Explicit condition field takes priority over NER-extracted one
    t_condition = body.condition.strip() or ner_data.get("condition") or ""

    # 4. Fetch today's rate for inflation adjustment
    from datetime import date
    today_rate_res = await db.execute(select(ExchangeRates.usd_try).where(ExchangeRates.date == date.today()))
    today_usd = today_rate_res.scalar_one_or_none() or 33.0

    # 5. pgvector aday havuzu
    candidates_q = sql_text("""
        SELECT
            l.category,
            l.location,
            l.image_phash,
            l.created_at,
            l.last_start_price AS start_price,
            l.last_sold_price AS final_price,
            (l.embedding <=> CAST(:emb AS vector)) AS dist,
            er.usd_try AS historical_usd,
            l.brand,
            l.model_name,
            l.condition
        FROM listings l
        LEFT JOIN exchange_rates er ON er.date = DATE(l.created_at)
        WHERE l.embedding IS NOT NULL
          AND l.last_sold_price IS NOT NULL
          AND l.last_sold_price > 0
          AND (:excl = 0 OR l.id != :excl)
          AND (:cat = '' OR l.category = :cat)
        ORDER BY l.embedding <=> CAST(:emb AS vector)
        LIMIT 150
    """)
    result = await db.execute(candidates_q, {
        "emb": emb_str, "excl": body.exclude_listing_id,
        "cat": body.category.strip(),
    })
    rows = result.fetchall()

    _t = _get_t(get_locale(current_user, request))
    _no_data = {
        "found_similar": 0,
        "suggested_start_price": None,
        "estimated_close_price": None,
        "min_close_price": None,
        "max_close_price": None,
        "confidence": "low",
        "category_match_count": 0,
        "advice": _t.get(
            "aiAdviceNoData",
            "Henüz yeterli benzer ürün verisi bulunamadı. "
            "Platforma eklendikçe tahminler daha isabetli hale gelecek. "
            "Piyasa araştırması yaparak fiyatınızı belirleyebilirsiniz."
        ),
        "tuci_spent": 0,
    }

    if not rows:
        return _no_data

    # 4. Çok sinyalli skorlama
    now = _dt2.now(_tz2.utc)
    body_category = body.category.strip().lower()
    body_city = body.city.strip().lower()

    scored: list[tuple[float, Any, float]] = []
    for row in rows:
        hist_usd = float(row.historical_usd) if row.historical_usd else today_usd
        adj_final_price = float(row.final_price) * (today_usd / hist_usd)
        
        sem_sim = max(0.0, 1.0 - float(row.dist))
        cat_mult = 2.0 if (body_category and (row.category or "").lower() == body_category) else 1.0
        city_mult = 1.0
        if body_city and row.location:
            loc = row.location.lower()
            if body_city in loc or loc in body_city:
                city_mult = 1.3
        age_days = 365
        if row.created_at:
            created = row.created_at
            if created.tzinfo is None:
                created = created.replace(tzinfo=_tz2.utc)
            age_days = max(0, (now - created).days)
        recency = math.exp(-age_days / 180.0)
        phash_mult = 1.0
        if body_phash and row.image_phash:
            try:
                hamming = bin(int(body_phash, 16) ^ int(row.image_phash, 16)).count("1")
                phash_mult = 1.5 if hamming <= 8 else (1.2 if hamming <= 16 else 1.0)
            except Exception:
                pass
                
        # NER Score (Soft Filter)
        ner_mult = 1.0
        if t_brand and row.brand:
            if t_brand == row.brand: ner_mult *= 1.5
            else: ner_mult *= 0.3
        if t_model and row.model_name:
            if t_model == row.model_name: ner_mult *= 2.0
            else: ner_mult *= 0.2
        if t_condition and row.condition:
            if t_condition == row.condition: ner_mult *= 1.5
            else: ner_mult *= 0.4
            
        composite = sem_sim * cat_mult * city_mult * recency * phash_mult * ner_mult
        scored.append((composite, row, adj_final_price))

    scored.sort(key=lambda x: x[0], reverse=True)

    # 5. IQR aykırı değer temizleme (>=10 veri noktasında) — Tukey Q1/Q3 ± 1.5×IQR
    if len(scored) >= 10:
        prices_s = sorted(float(p) for _, _, p in scored)
        n_p = len(prices_s)
        q1 = prices_s[n_p // 4]
        q3 = prices_s[(3 * n_p) // 4]
        iqr = q3 - q1
        lo = q1 - 1.5 * iqr
        hi = q3 + 1.5 * iqr
        scored = [(s, r, p) for s, r, p in scored if lo <= float(p) <= hi]

    top = scored[:30]
    cnt = len(top)
    if cnt == 0:
        return _no_data

    # 6. Agirlikli fiyat hesaplama
    total_w = sum(s for s, _, _ in top)
    w_final = sum(s * float(p) for s, _, p in top) / total_w
    start_rows = [(s, r, p) for s, r, p in top if r.start_price and float(r.start_price) > 0]
    if start_rows:
        sw = sum(s for s, _, _ in start_rows)
        # Adjust start price by the same inflation ratio (p / final_price)
        w_start = sum(s * float(r.start_price) * (float(p) / float(r.final_price)) for s, r, p in start_rows) / sw
    else:
        w_start = w_final * 0.72
    all_finals = sorted(float(p) for _, _, p in top)
    n = len(all_finals)
    min_price = all_finals[max(0, n // 10)]
    max_price = all_finals[min(n - 1, max(0, n - n // 10 - 1))]

    # 7. Bimodal Dağılım Tespiti (KDE)
    import numpy as np
    from scipy.stats import gaussian_kde
    alert_msg = None
    prices_for_kde = [float(p) for _, _, p in top]
    if len(prices_for_kde) >= 10:
        try:
            kde = gaussian_kde(prices_for_kde)
            x_grid = np.linspace(min(prices_for_kde), max(prices_for_kde), 100)
            y_kde = kde(x_grid)
            peaks = []
            for i in range(1, 99):
                if y_kde[i] > y_kde[i-1] and y_kde[i] > y_kde[i+1]:
                    peaks.append(x_grid[i])
            if len(peaks) > 1 and (peaks[-1] - peaks[0]) > (min(prices_for_kde) * 0.3):
                alert_msg = _t.get(
                    "aiAdviceBimodal",
                    "Bu ürün grubunda iki farklı piyasa fiyatı (Bimodal) tespit edildi. "
                    "Ürününüzün varyasyonuna veya garantisine göre fiyat farklılaşabilir."
                )
        except Exception as e:
            logger.warning(f"KDE analysis failed: {e}")

    # 8. Guven seviyesi: kategori eslesme sayisina gore
    cat_matched = sum(1 for _, r, _ in top if (r.category or "").lower() == body_category)
    if cat_matched >= 10 or (cat_matched >= 5 and body_category):
        confidence = "high"
    elif cat_matched >= 3 or cnt >= 10:
        confidence = "medium"
    else:
        confidence = "low"

    suggested_start = round(w_start, 0)
    estimated_close = round(w_final, 0)
    min_close = round(min_price, 0)
    max_close = round(max_price, 0)

    # 9. Time to Sell & Likidite
    fast_sell = round(estimated_close * 0.85, 0)
    market_sell = estimated_close
    slow_sell = round(estimated_close * 1.15, 0)

    close_fmt = f"{int(estimated_close):,}".replace(",", ".")
    start_fmt = f"{int(suggested_start):,}".replace(",", ".")
    signals = []
    if cat_matched > 0:
        signals.append(
            _t.get("aiAdviceSameCategory", "{count} aynı kategori").replace("{count}", str(cat_matched))
        )
    if body_city and any(body_city in (r.location or "").lower() for _, r, _ in top):
        signals.append(_t.get("aiAdviceCityBased", "şehir bazlı"))
    signal_str = f" ({', '.join(signals)})" if signals else ""

    advice = _t.get("aiAdviceSimilarCount", "{count} benzer ürün satış verisi analiz edildi").replace("{count}", str(cnt))
    advice += signal_str + ". "
    if alert_msg:
        advice += alert_msg
    else:
        advice += _t.get("aiAdviceMarketClose", "Ortalama piyasa kapanışı: {price} ₺.").replace("{price}", close_fmt)

    # ── TUCi düş + sayaç güncelle (Atomik) ────────────────────────────────────
    tuci_spent = 0
    if current_user.is_premium:
        ai_used_new = await _increment_ai_atomic(current_user.id, current_user.premium_since)
        if ai_used_new <= AI_PRICE_LIMIT_PRO:
            pass  # Limit içi, TUCi düşme
        else:
            await db.execute(
                sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                {"cost": AI_PRICE_ESTIMATE_COST, "uid": current_user.id},
            )
            db.add(TuciTransaction(
                user_id=current_user.id,
                amount=-AI_PRICE_ESTIMATE_COST,
                transaction_type="spend_ai",
                reference_id=body.exclude_listing_id if body.exclude_listing_id else None,
                reference_type="listing" if body.exclude_listing_id else None,
            ))
            await db.commit()
            tuci_spent = AI_PRICE_ESTIMATE_COST
    else:
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": AI_PRICE_ESTIMATE_COST, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-AI_PRICE_ESTIMATE_COST,
            transaction_type="spend_ai",
            reference_id=body.exclude_listing_id if body.exclude_listing_id else None,
            reference_type="listing" if body.exclude_listing_id else None,
        ))
        await db.commit()
        tuci_spent = AI_PRICE_ESTIMATE_COST

    return {
        "found_similar": cnt,
        "suggested_start_price": suggested_start,
        "estimated_close_price": estimated_close,
        "fast_sell_price": fast_sell,
        "market_sell_price": market_sell,
        "slow_sell_price": slow_sell,
        "min_close_price": min_price,
        "max_close_price": max_price,
        "confidence": confidence,
        "category_match_count": cat_matched,
        "advice": advice,
        "alert": alert_msg,
        "tuci_spent": tuci_spent,
    }


# ── Sektörel Pazar Trendleri ──────────────────────────────────────────────────

_CATEGORY_LABELS: dict[str, str] = {
    "elektronik": "Elektronik",
    "giyim": "Giyim & Moda",
    "ev": "Ev & Yaşam",
    "vasita": "Vasıta",
    "spor": "Spor & Hobi",
    "kitap": "Kitap & Kültür",
    "emlak": "Emlak",
    "diger": "Diğer",
    "sohbet": "Sohbet",
}


@router.get("/market-trends")
async def market_trends(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Son 30 günlük platform makro trendleri.
    - peak_hours: etkileşim yoğunluğu en yüksek 3 saat
    - trending_categories: teklif hacmi en çok artan 3 kategori
    - average_spend_growth: ortalama harcama değişim yüzdesi (önceki 30 güne göre)
    """
    try:
        t = _get_t(get_locale(current_user, request))
        
        redis = await get_redis()
        cache_key = f"cache:market_trends_global_{get_locale(current_user, request)}"
        cached_data = await redis.get(cache_key)
        if cached_data:
            import json
            return json.loads(cached_data)
    except Exception:
        redis = None
        cache_key = None

    # ── 1. Peak hours — ClickHouse ────────────────────────────────────────────
    peak_hours: list[dict] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(
            """
            SELECT toHour(toTimeZone(timestamp, 'Europe/Istanbul')) AS hr, COUNT(*) AS cnt
            FROM user_events
            WHERE timestamp >= now() - INTERVAL 30 DAY
            GROUP BY hr
            ORDER BY cnt DESC
            LIMIT 3
            """
        )
        for row in ch_result.result_rows:
            hr = int(row[0])
            peak_hours.append({"hour": hr, "label": f"{hr:02d}:00–{hr:02d}:59", "count": int(row[1])})
    except Exception as ch_exc:
        logger.warning("[MarketTrends] ClickHouse peak_hours başarısız: %s", ch_exc)

    # ── 2. Trending categories — PostgreSQL ───────────────────────────────────
    trending_categories: list[dict] = []
    try:
        cat_q = sql_text("""
            WITH recent AS (
                SELECT l.category, COUNT(*) AS cnt
                FROM purchases p
                JOIN auctions a ON a.id = p.auction_id
                JOIN listings  l ON l.id = a.listing_id
                WHERE p.created_at >= NOW() - INTERVAL '15 days'
                  AND p.auction_id IS NOT NULL
                  AND l.category IS NOT NULL
                GROUP BY l.category
            ),
            prev AS (
                SELECT l.category, COUNT(*) AS cnt
                FROM purchases p
                JOIN auctions a ON a.id = p.auction_id
                JOIN listings  l ON l.id = a.listing_id
                WHERE p.created_at >= NOW() - INTERVAL '30 days'
                  AND p.created_at  < NOW() - INTERVAL '15 days'
                  AND p.auction_id IS NOT NULL
                  AND l.category IS NOT NULL
                GROUP BY l.category
            )
            SELECT
                r.category,
                r.cnt AS recent_cnt,
                COALESCE(p.cnt, 0) AS prev_cnt,
                CASE WHEN COALESCE(p.cnt, 0) > 0 AND r.cnt >= 3
                    THEN ROUND(((((r.cnt - p.cnt)::float / p.cnt) * 100))::numeric, 1)
                    ELSE NULL
                END AS growth_pct
            FROM recent r
            LEFT JOIN prev p ON p.category = r.category
            WHERE r.cnt >= 3
            ORDER BY COALESCE(
                CASE WHEN COALESCE(p.cnt, 0) > 0 AND r.cnt >= 3
                    THEN ((r.cnt - p.cnt)::float / p.cnt) * 100
                    ELSE NULL
                END, 0) DESC
            LIMIT 3
        """)
        cat_result = await db.execute(cat_q)
        for row in cat_result.fetchall():
            key = row.category or "diger"
            trending_categories.append({
                "key": key,
                "label": t.get(f"cat_{key}", _CATEGORY_LABELS.get(key, key.capitalize())),
                "recent_count": int(row.recent_cnt),
                "prev_count": int(row.prev_cnt),
                "growth_pct": float(row.growth_pct) if row.growth_pct is not None else None,
            })
    except Exception as exc:
        logger.warning("[MarketTrends] trending_categories başarısız: %s", exc)
        await db.rollback()

    # ── 3. Average spend growth — PostgreSQL ──────────────────────────────────
    avg_spend_growth: float | None = None
    try:
        spend_q = sql_text("""
            SELECT
                AVG(price) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')  AS recent_avg,
                AVG(price) FILTER (WHERE created_at >= NOW() - INTERVAL '60 days'
                                    AND created_at <  NOW() - INTERVAL '30 days')  AS prev_avg
            FROM purchases
        """)
        spend_result = await db.execute(spend_q)
        row = spend_result.fetchone()
        if row and row.recent_avg and row.prev_avg and float(row.prev_avg) > 0:
            avg_spend_growth = round(
                ((float(row.recent_avg) - float(row.prev_avg)) / float(row.prev_avg)) * 100, 1
            )
        elif row and row.recent_avg:
            avg_spend_growth = 0.0
    except Exception as exc:
        logger.warning("[MarketTrends] avg_spend_growth başarısız: %s", exc)

    response_data = {
        "peak_hours": peak_hours,
        "trending_categories": trending_categories,
        "average_spend_growth": avg_spend_growth,
    }

    if redis and cache_key:
        try:
            import json
            await redis.setex(cache_key, 300, json.dumps(response_data))
        except Exception as e:
            logger.warning("[MarketTrends] Redis cache set hatası: %s", e)

    return response_data


_CAT_LABELS: dict[str, str] = {
    "elektronik": "📱 Elektronik", "giyim": "👗 Giyim", "ev": "🏠 Ev & Yaşam",
    "spor": "⚽ Spor", "kitap": "📚 Kitap", "oyun": "🎮 Oyun", "diger": "📦 Diğer",
    "sohbet": "🗣 Sohbet",
}


@router.get("/pro-insights")
async def pro_insights(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
):
    """
    Pro satıcıya özel kapsamlı analitik paketi.
    7 bölüm: KPI özeti · dönüşüm hunisi · sıcak talepler · fiyat zekası ·
             yayın performansı · pazar trendleri · akıllı öneriler
    """
    from datetime import datetime as _dt, timedelta as _td
    uid = current_user.id
    _t = _get_t(get_locale(current_user, request))

    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None

    # ── Cache Check (skip when date filters applied) ─────────────────────────
    try:
        redis = await get_redis()
        _locale = get_locale(current_user, request)
        cache_key = f"cache:pro_insights:{uid}:{_locale}:{start_date or ''}:{end_date or ''}"
        cached_data = await redis.get(cache_key) if not (start_date or end_date) else None
        if cached_data:
            import json
            return json.loads(cached_data)
    except Exception:
        redis = None
        cache_key = None

    # ── 1. Satıcı KPI'ları — PostgreSQL ─────────────────────────────────────
    kpis: dict = {}
    try:
        from datetime import datetime, timedelta, timezone
        now = datetime.now(timezone.utc)
        d30 = now - timedelta(days=30)
        d60 = now - timedelta(days=60)

        rows = await db.execute(sql_text("""
            SELECT
                COUNT(*)                                                         AS total_listings,
                COUNT(*) FILTER (WHERE status = 'active')             AS active_listings,
                COALESCE(AVG(price) FILTER (WHERE status != 'deleted'), 0)            AS avg_price,
                COUNT(*) FILTER (WHERE created_at >= :d30 AND status != 'deleted')    AS new_last_30d
            FROM listings WHERE user_id = :uid
        """), {"uid": uid, "d30": d30})
        lrow = rows.fetchone()

        sales_rows = await db.execute(sql_text("""
            SELECT
                COUNT(*)                                                            AS total_sales,
                COALESCE(SUM(p.price), 0)                                             AS total_revenue,
                COALESCE(SUM(p.price) FILTER (WHERE p.created_at >= :d30), 0)           AS revenue_30d,
                COALESCE(SUM(p.price) FILTER (WHERE p.created_at >= :d60
                                             AND p.created_at < :d30), 0)             AS revenue_prev_30d,
                COUNT(*) FILTER (WHERE p.created_at >= :d30)                          AS sales_30d
            FROM purchases p
            JOIN listings l ON l.id = p.listing_id
            WHERE p.buyer_id != :uid
              AND l.user_id = :uid
        """), {"uid": uid, "d30": d30, "d60": d60})
        srow = sales_rows.fetchone()

        rev_30 = float(srow.revenue_30d or 0)
        rev_prev = float(srow.revenue_prev_30d or 0)
        rev_growth = round(((rev_30 - rev_prev) / rev_prev) * 100, 1) if rev_prev > 0 else None

        bid_rows = await db.execute(sql_text("""
            SELECT COUNT(*) AS total_bids
            FROM bids b
            JOIN auctions a ON a.stream_id = b.stream_id
            JOIN listings l ON l.id = a.listing_id
            WHERE l.user_id = :uid AND b.created_at >= :d30
        """), {"uid": uid, "d30": d30})
        brow = bid_rows.fetchone()

        kpis = {
            "total_listings": int(lrow.total_listings or 0),
            "active_listings": int(lrow.active_listings or 0),
            "avg_listing_price": round(float(lrow.avg_price or 0), 2),
            "total_sales": int(srow.total_sales or 0),
            "total_revenue": round(float(srow.total_revenue or 0), 2),
            "revenue_30d": round(rev_30, 2),
            "revenue_growth_pct": rev_growth,
            "sales_30d": int(srow.sales_30d or 0),
            "bids_30d": int(brow.total_bids or 0),
        }
    except Exception as exc:
        logger.warning("[ProInsights] kpis başarısız: %s", exc)
        await db.rollback()

    # ── 2. Dönüşüm Hunisi — ClickHouse + PostgreSQL ──────────────────────────
    funnel: dict = {}
    try:
        listing_ids_result = await db.execute(
            select(Listing.id).where(Listing.user_id == uid, Listing.status != ListingStatus.DELETED)  # noqa: E712
        )
        listing_ids = [r[0] for r in listing_ids_result.fetchall()]

        views_total = 0
        hesitations = 0

        if listing_ids:
            ids_str = ", ".join(str(i) for i in listing_ids)
            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                ch_r = await ch.query(f"""
                    SELECT
                        countIf(event_type = 'view')              AS views,
                        countIf(event_type = 'dwell')             AS dwells,
                        countDistinctIf(user_id, event_type = 'bid_hesitation') AS hesitations
                    FROM user_events
                    WHERE item_type = 'listing'
                      AND item_id IN ({ids_str})
                      AND timestamp >= now() - INTERVAL 30 DAY
                """)
                r = ch_r.result_rows[0] if ch_r.result_rows else (0, 0, 0)
                views_total = int(r[0] or 0)
                hesitations = int(r[2] or 0)
            except Exception:
                pass

        bids_count = kpis.get("bids_30d", 0)
        sales_count = kpis.get("sales_30d", 0)
        funnel = {
            "views": views_total,
            "hesitations": hesitations,
            "bids": bids_count,
            "sales": sales_count,
            "view_to_bid_pct": round((bids_count / views_total) * 100, 1) if views_total > 0 else 0,
            "bid_to_sale_pct": round((sales_count / bids_count) * 100, 1) if bids_count > 0 else 0,
        }
    except Exception as exc:
        logger.warning("[ProInsights] funnel başarısız: %s", exc)
        await db.rollback()

    # ── 3. Sıcak Talepler — En çok ilgi gören ama satılmayan ilanlar ─────────
    hot_leads: list[dict] = []
    try:
        _hl_q = (
            select(Listing.id, Listing.title, Listing.price, Listing.category)
            .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE)  # noqa: E712
        )
        if _sd: _hl_q = _hl_q.where(Listing.created_at >= _sd)
        if _ed: _hl_q = _hl_q.where(Listing.created_at < _ed)
        active_ids_r = await db.execute(_hl_q.limit(20))
        active_listings = active_ids_r.fetchall()
        if active_listings:
            ids_str = ", ".join(str(r.id) for r in active_listings)
            import time as _time_mod
            view_map: dict[int, int] = {r.id: 0 for r in active_listings}
            hes_map: dict[int, int] = {r.id: 0 for r in active_listings}
            ts_map: dict[int, float] = {}
            like_map: dict[int, int] = {}
            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                ch_r2 = await ch.query(f"""
                    SELECT item_id,
                           countIf(event_type = 'view') AS views,
                           countDistinctIf(user_id, event_type = 'bid_hesitation') AS hes,
                           toUnixTimestamp(max(timestamp)) AS last_event_ts
                    FROM user_events
                    WHERE item_type = 'listing' AND item_id IN ({ids_str})
                      AND timestamp >= now() - INTERVAL 30 DAY
                    GROUP BY item_id
                """)
                view_map = {int(r[0]): int(r[1]) for r in ch_r2.result_rows}
                hes_map  = {int(r[0]): int(r[2]) for r in ch_r2.result_rows}
                ts_map   = {int(r[0]): float(r[3]) for r in ch_r2.result_rows}
            except Exception:
                pass
            try:
                like_r = await db.execute(sql_text("""
                    SELECT listing_id, COUNT(*)::int FROM listing_likes
                    WHERE listing_id = ANY(:ids) AND created_at >= NOW() - INTERVAL '30 days'
                    GROUP BY listing_id
                """), {"ids": [r.id for r in active_listings]})
                like_map = {row[0]: row[1] for row in like_r.fetchall()}
            except Exception:
                await db.rollback()

            _now_ts = _time_mod.time()

            def _heat(lid: int) -> float:
                age_h = max((_now_ts - ts_map.get(lid, _now_ts)) / 3600, 0.0)
                raw = view_map.get(lid, 0) * 1 + like_map.get(lid, 0) * 2 + hes_map.get(lid, 0) * 3
                return raw / (age_h + 2) ** 1.2

            scored = sorted(active_listings, key=lambda r: _heat(r.id), reverse=True)[:5]
            hot_leads = [
                {
                    "listing_id": r.id,
                    "title": r.title,
                    "price": r.price,
                    "category": _t.get(f"cat_{r.category or 'diger'}", _CAT_LABELS.get(r.category or "diger", r.category or "Diğer")),
                    "views_30d": view_map.get(r.id, 0),
                    "hesitations_30d": hes_map.get(r.id, 0),
                    "heat_score": round(_heat(r.id), 2),
                }
                for r in scored
            ]
    except Exception as exc:
        logger.warning("[ProInsights] hot_leads başarısız: %s", exc)
        await db.rollback()

    # ── 4. Fiyat Zekası — pgvector + PostgreSQL piyasa ortalaması ────────────
    price_intel: list[dict] = []
    try:
        _pi_q = (
            select(Listing.id, Listing.title, Listing.price, Listing.category, Listing.embedding)
            .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE,  # noqa: E712
                   Listing.price.is_not(None))
        )
        if _sd: _pi_q = _pi_q.where(Listing.created_at >= _sd)
        if _ed: _pi_q = _pi_q.where(Listing.created_at < _ed)
        my_listings_r = await db.execute(_pi_q.limit(5))
        my_listings = my_listings_r.fetchall()
        for ml in my_listings:
            market_avg: float | None = None
            price_stddev: float | None = None
            # Fiyat aralığı: ilanın fiyatının 0.05x–20x arası (test verisi ve aykırı değerleri eler)
            price_lo = float(ml.price) * 0.05
            price_hi = float(ml.price) * 20.0
            if ml.embedding is not None:
                try:
                    emb_str = "[" + ",".join(f"{x:.6f}" for x in ml.embedding) + "]"
                    sim_r = await db.execute(sql_text("""
                        SELECT AVG(price), STDDEV(price) FROM (
                            SELECT price FROM listings
                            WHERE user_id != :uid
                              AND category = :cat
                              AND status = 'active'
                              AND price > :lo AND price < :hi
                              AND embedding IS NOT NULL
                            ORDER BY embedding <=> CAST(:emb AS vector)
                            LIMIT 10
                        ) sub
                    """), {"uid": uid, "emb": emb_str, "cat": ml.category,
                           "lo": price_lo, "hi": price_hi})
                    _sim_row = sim_r.fetchone()
                    market_avg = _sim_row[0] if _sim_row else None
                    price_stddev = _sim_row[1] if _sim_row else None
                except Exception:
                    await db.rollback()

            if market_avg is None:
                cat_r = await db.execute(sql_text("""
                    SELECT AVG(price), STDDEV(price) FROM listings
                    WHERE category = :cat AND user_id != :uid
                      AND status = 'active'
                      AND price > :lo AND price < :hi
                """), {"cat": ml.category, "uid": uid,
                       "lo": price_lo, "hi": price_hi})
                _cat_row = cat_r.fetchone()
                market_avg = _cat_row[0] if _cat_row else None
                price_stddev = _cat_row[1] if _cat_row else None

            if market_avg and market_avg > 0:
                diff_pct = round(((ml.price - market_avg) / market_avg) * 100, 1)
                _threshold = max(min((price_stddev / market_avg) * 100, 40.0), 10.0) if price_stddev else 15.0
                signal = "pahalı" if diff_pct > _threshold else ("ucuz" if diff_pct < -_threshold else "uygun")
                price_intel.append({
                    "listing_id": ml.id,
                    "title": ml.title,
                    "your_price": ml.price,
                    "market_avg": round(float(market_avg), 2),
                    "diff_pct": diff_pct,
                    "signal": signal,
                })
    except Exception as exc:
        logger.warning("[ProInsights] price_intel başarısız: %s", exc)
        await db.rollback()

    # ── 5. Yayın Performansı — PostgreSQL ────────────────────────────────────
    stream_stats: dict = {}
    try:
        s_rows = await db.execute(sql_text("""
            SELECT
                COUNT(*)                                              AS total_streams,
                COALESCE(AVG(viewer_count), 0)                       AS avg_viewers,
                COALESCE(MAX(viewer_count), 0)                       AS peak_viewers,
                COALESCE(AVG(EXTRACT(EPOCH FROM (ended_at - started_at))/60), 0) AS avg_duration_min,
                COUNT(*) FILTER (WHERE started_at >= :d30)           AS streams_30d
            FROM live_streams
            WHERE host_id = :uid AND is_live = false AND ended_at IS NOT NULL
        """), {"uid": uid, "d30": now - timedelta(days=30)})
        sr = s_rows.fetchone()

        best_r = await db.execute(sql_text("""
            SELECT ls.title, ls.viewer_count,
                   ROUND(EXTRACT(EPOCH FROM (ls.ended_at - ls.started_at))/60) AS dur_min,
                   COUNT(b.id) AS bid_count
            FROM live_streams ls
            LEFT JOIN auctions a ON a.stream_id = ls.id
            LEFT JOIN bids b ON b.stream_id = a.stream_id
            WHERE ls.host_id = :uid AND ls.is_live = false AND ls.ended_at IS NOT NULL
            GROUP BY ls.id, ls.title, ls.viewer_count, ls.started_at, ls.ended_at
            ORDER BY ls.viewer_count DESC, bid_count DESC
            LIMIT 3
        """), {"uid": uid})
        best_streams = [
            {"title": r.title, "viewers": r.viewer_count, "duration_min": int(r.dur_min or 0), "bids": r.bid_count}
            for r in best_r.fetchall()
        ]

        stream_stats = {
            "total_streams": int(sr.total_streams or 0),
            "streams_30d": int(sr.streams_30d or 0),
            "avg_viewers": round(float(sr.avg_viewers or 0), 1),
            "peak_viewers": int(sr.peak_viewers or 0),
            "avg_duration_min": round(float(sr.avg_duration_min or 0), 1),
            "best_streams": best_streams,
        }
    except Exception as exc:
        logger.warning("[ProInsights] stream_stats başarısız: %s", exc)
        await db.rollback()

    # ── 6. Pazar Trendleri — özet (market-trends'den alınır) ─────────────────
    peak_hours: list[dict] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ph_r = await ch.query("""
            SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
            FROM user_events
            WHERE timestamp >= now() - INTERVAL 30 DAY
              AND event_type IN ('view','dwell','bid_hesitation')
            GROUP BY hr ORDER BY cnt DESC LIMIT 5
        """)
        peak_hours = [
            {"hour": int(r[0]), "count": int(r[1]),
             "label": f"{int(r[0]):02d}:00–{int(r[0])+1:02d}:00"}
            for r in ph_r.result_rows
        ]
    except Exception as exc:
        logger.warning("[ProInsights] peak_hours başarısız: %s", exc)
        # ClickHouse down ise boş dön — sahte veri gösterme

    # ── 7. Akıllı Öneriler — kural motoru ────────────────────────────────────
    tips: list[dict] = []
    try:
        t = _get_t(get_locale(current_user, request))

        # Fiyat sinyali
        overpriced = [p for p in price_intel if p["signal"] == "pahalı"]
        underpriced = [p for p in price_intel if p["signal"] == "ucuz"]
        if overpriced:
            tips.append({
                "icon": "💰", "type": "price",
                "title": t.get("proTipPriceDownTitle", "Fiyat Ayarı Önerisi"),
                "body": t.get("proTipPriceDownBody", '"{title}" piyasa ortalamasının %{diff} üzerinde. Fiyatı {avg} ₺ civarına çekersen satış hızlanabilir.').format(
                    title=overpriced[0]["title"], diff=abs(overpriced[0]["diff_pct"]), avg=int(overpriced[0]["market_avg"])
                ),
            })
        if underpriced:
            tips.append({
                "icon": "🚀", "type": "price_up",
                "title": t.get("proTipPriceUpTitle", "Fiyat Artırma Fırsatı"),
                "body": t.get("proTipPriceUpBody", '"{title}" benzer ilanların %{diff} altında. Piyasa fiyatı {avg} ₺ — artırma fırsatı var.').format(
                    title=underpriced[0]["title"], diff=abs(underpriced[0]["diff_pct"]), avg=int(underpriced[0]["market_avg"])
                ),
            })
        # Sıcak talep
        if hot_leads and hot_leads[0].get("hesitations_30d", 0) > 0:
            tips.append({
                "icon": "🎯", "type": "lead",
                "title": t.get("proTipLeadTitle", "Sıcak Alıcı Var"),
                "body": t.get("proTipLeadBody", '"{title}" için son 30 günde {count} kişi inceledi ama teklif vermedi. Fiyatı küçük düşür veya açıklama güçlendir.').format(
                    title=hot_leads[0]["title"], count=hot_leads[0]["hesitations_30d"]
                ),
            })
        # Tereddüt fiyat noktası: alıcıların yazdığı fiyat lisans fiyatının çok altındaysa somut öneri
        try:
            seller_lid_rows = await db.execute(sql_text(
                "SELECT id, title, price FROM listings WHERE user_id = :uid AND status = 'active' LIMIT 20"
            ), {"uid": uid})
            seller_listings = {r.id: {"title": r.title, "price": float(r.price or 0)} for r in seller_lid_rows.fetchall()}
            if seller_listings:
                ids_str = ",".join(str(i) for i in seller_listings)
                from app.database_clickhouse import get_clickhouse_client as _get_ch
                ch2 = await _get_ch()
                if ch2 is not None:
                    hes_price_r = await ch2.query(f"""
                        SELECT item_id, AVG(price_point) AS avg_pp, COUNT() AS cnt
                        FROM user_events
                        WHERE event_type = 'bid_hesitation'
                          AND item_type  = 'listing'
                          AND item_id IN ({ids_str})
                          AND price_point > 0
                          AND timestamp >= now() - INTERVAL 30 DAY
                        GROUP BY item_id
                        HAVING cnt >= 2
                    """)
                    for row in hes_price_r.result_rows:
                        lid_h, avg_pp, _ = int(row[0]), float(row[1]), int(row[2])
                        sl = seller_listings.get(lid_h)
                        if sl and sl["price"] > 0 and avg_pp < sl["price"] * 0.85:
                            suggested = int(round(avg_pp / 50) * 50) or int(avg_pp)
                            tips.append({
                                "icon": "💡", "type": "hesitation_price",
                                "title": t.get("proTipHesPriceTitle", "Alıcı Fiyat Sinyali"),
                                "body": t.get(
                                    "proTipHesPriceBody",
                                    '"{title}" için birden fazla kişi ≈{suggested} ₺ yazdı ama teklif göndermedi. Bu fiyata yaklaştırmak dönüşümü artırabilir.'
                                ).format(title=sl["title"], suggested=suggested),
                            })
                            break
        except Exception as hes_tip_exc:
            logger.warning("[ProInsights] hesitation_price tip başarısız: %s", hes_tip_exc)
        # Yayın önerisi
        if peak_hours:
            best_hour = peak_hours[0]["label"]
            tips.append({
                "icon": "📡", "type": "stream",
                "title": t.get("proTipStreamTitle", "En İyi Yayın Saati"),
                "body": t.get("proTipStreamBody", "Platform genelinde en yoğun saat {hour}. Canlı yayını bu saatte başlatırsan daha fazla izleyiciye ulaşırsın.").format(
                    hour=best_hour
                ),
            })
        # Dönüşüm
        if funnel.get("view_to_bid_pct", 0) < 5 and funnel.get("views", 0) > 10:
            tips.append({
                "icon": "📸", "type": "listing_quality",
                "title": t.get("proTipQualityTitle", "Görsel & Açıklama İyileştir"),
                "body": t.get("proTipQualityBody", "İlanlarının görüntülenme → teklif oranı %{pct}. Daha iyi fotoğraf ve detaylı açıklama bu oranı 3–5x artırabilir.").format(
                    pct=funnel["view_to_bid_pct"]
                ),
            })
        if not tips:
            tips.append({
                "icon": "✅", "type": "general",
                "title": t.get("proTipAllGoodTitle", "Her Şey Yolunda"),
                "body": t.get("proTipAllGoodBody", "İlan ve satış verilerin sağlıklı görünüyor. Daha fazla veri biriktiğinde özel öneriler burada belirecek."),
            })
    except Exception as exc:
        logger.warning("[ProInsights] tips başarısız: %s", exc)

    response_data = {
        "kpis": kpis,
        "funnel": funnel,
        "hot_leads": hot_leads,
        "price_intel": price_intel,
        "stream_stats": stream_stats,
        "peak_hours": peak_hours,
        "tips": tips,
    }
    
    if redis and cache_key:
        try:
            import json
            await redis.setex(cache_key, 300, json.dumps(response_data)) # 5 mins TTL
        except Exception as e:
            logger.warning("[ProInsights] Redis cache set hatası: %s", e)

    return response_data


@router.get("/pro/best-stream-time")
async def best_stream_time(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcının geçmiş yayın verilerine göre en yüksek dönüşüm sağlayan gün/saat dilimlerini döner.
    Son 90 günlük yayın geçmişini 3'er saatlik bloklara bölerek kategori bazlı analiz eder.
    """
    uid = current_user.id
    t = _get_t(get_locale(current_user, request))
    
    _DAYS = [
        t.get("day0", "Pazar"),
        t.get("day1", "Pazartesi"),
        t.get("day2", "Salı"),
        t.get("day3", "Çarşamba"),
        t.get("day4", "Perşembe"),
        t.get("day5", "Cuma"),
        t.get("day6", "Cumartesi"),
    ]

    result = await db.execute(sql_text("""
        WITH stream_auctions AS (
            SELECT
                ls.id                                                                     AS stream_id,
                EXTRACT(DOW FROM ls.started_at AT TIME ZONE 'UTC')::int                  AS utc_dow,
                FLOOR(EXTRACT(HOUR FROM ls.started_at AT TIME ZONE 'UTC') / 3) * 3       AS utc_hour,
                COUNT(a.id)                                                               AS total_auctions,
                COUNT(a.winner_id)                                                        AS won_auctions
            FROM live_streams ls
            LEFT JOIN auctions a ON a.stream_id = ls.id
            WHERE ls.host_id = :uid
              AND ls.started_at >= NOW() - INTERVAL '90 days'
              AND ls.ended_at IS NOT NULL
            GROUP BY ls.id, ls.started_at
        )
        SELECT
            utc_dow,
            utc_hour::int,
            COUNT(*)                                                                       AS stream_count,
            COALESCE(SUM(won_auctions)::float / NULLIF(SUM(total_auctions), 0), 0)        AS conv_rate,
            SUM(won_auctions)                                                              AS total_wins
        FROM stream_auctions
        GROUP BY utc_dow, utc_hour
        HAVING COUNT(*) >= 2
        ORDER BY conv_rate DESC, total_wins DESC
        LIMIT 5
    """), {"uid": uid})

    rows = result.fetchall()
    slots = []
    for r in rows:
        utc_dow = int(r.utc_dow)
        utc_hour = int(r.utc_hour)
        
        # Legacy values corresponding to Istanbul timezone (UTC+3)
        tr_hour = (utc_hour + 3) % 24
        tr_dow = utc_dow
        if utc_hour + 3 >= 24:
            tr_dow = (utc_dow + 1) % 7

        slots.append({
            "day": _DAYS[tr_dow],
            "hour_range": f"{tr_hour:02d}:00 - {tr_hour+3:02d}:00",
            "utc_day_of_week": utc_dow,
            "utc_hour_start": utc_hour,
            "stream_count": int(r.stream_count),
            "conversion_rate": round(float(r.conv_rate) * 100, 1),
            "total_wins": int(r.total_wins),
            "confidence": "high" if int(r.stream_count) >= 5 else ("medium" if int(r.stream_count) >= 3 else "low"),
        })
    if not slots:
        return {"slots": [], "recommendation": t.get("proNotEnoughStreamData", "Henüz yeterli yayın verisi yok (min. 2 yayın gerekli).")}

    best = slots[0]
    return {
        "slots": slots,
        "recommendation": t.get(
            "proBestStreamRec", 
            "{day} {hours} saatlerinde %{rate} dönüşüm oranıyla en iyi performansı gösteriyorsunuz."
        ).replace("{day}", best['day']).replace("{hours}", best['hour_range']).replace("{rate}", f"{best['conversion_rate']:.1f}"),
    }


@router.get("/pro/conversion-breakdown")
async def conversion_breakdown(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcının kategori bazlı açık artırma dönüşüm analizi (son 90 gün).
    Her kategori için: toplam müzayede sayısı, kazanılan, ortalama fiyat, dönüşüm oranı.
    """
    uid = current_user.id
    t = _get_t(get_locale(current_user, request))

    _CAT_LABELS_MAP = {
        "elektronik": "Elektronik", "giyim": "Giyim", "ev": "Ev & Yaşam",
        "spor": "Spor", "kitap": "Kitap", "oyun": "Oyun",
        "diger": "Diğer", "sohbet": "Sohbet",
    }

    result = await db.execute(sql_text("""
        SELECT
            COALESCE(l.category, 'diger')                                              AS category,
            COUNT(a.id)                                                                AS total_auctions,
            COUNT(a.winner_id)                                                         AS won_auctions,
            COALESCE(AVG(a.final_price) FILTER (WHERE a.winner_id IS NOT NULL), 0)    AS avg_final_price,
            COALESCE(COUNT(a.winner_id)::float / NULLIF(COUNT(a.id), 0), 0)           AS conv_rate
        FROM listings l
        INNER JOIN auctions a ON a.listing_id = l.id
            AND a.ended_at >= NOW() - INTERVAL '90 days'
            AND a.status = 'completed'
        WHERE l.user_id = :uid
          AND l.status != 'deleted'
        GROUP BY l.category
        HAVING COUNT(a.id) > 0
        ORDER BY conv_rate DESC, total_auctions DESC
    """), {"uid": uid})

    rows = result.fetchall()
    return [
        {
            "category": r.category,
            "label": t.get(f"cat_{r.category}", _CAT_LABELS_MAP.get(r.category, r.category or "Diğer")),
            "total_auctions": int(r.total_auctions),
            "won_auctions": int(r.won_auctions),
            "avg_final_price": round(float(r.avg_final_price), 2),
            "conversion_rate": round(float(r.conv_rate) * 100, 1),
        }
        for r in rows
    ]


# ── Feed Telemetri ────────────────────────────────────────────────────────────

@router.post("/feed-events", status_code=204)
async def ingest_feed_events(
    batch: FeedEventBatch,
    current_user: User = Depends(get_current_user),
):
    """
    Video ilan akışındaki kullanıcı davranışlarını (skip/impression/click +
    dwell_time_ms) tek bir batch insert ile feed_analytics tablosuna yazar.
    Boş liste sessizce kabul edilir. ClickHouse kapalıysa graceful degradation.
    """
    if not batch.events:
        return

    try:
        ch = await get_clickhouse_client()
    except Exception as exc:
        logger.warning("[feed-events] ClickHouse bağlantı hatası, olaylar atlandı: %s", exc)
        return

    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    uid = str(current_user.id)

    rows = [
        [now, uid, e.listing_id, e.event_type, e.dwell_time_ms,
         e.content_type, e.slot_index, e.stream_category, e.listing_condition]
        for e in batch.events
    ]

    try:
        await ch.insert(
            "feed_analytics",
            rows,
            column_names=["timestamp", "user_id", "listing_id", "event_type", "dwell_time_ms",
                          "content_type", "slot_index", "stream_category", "listing_condition"],
        )
        logger.debug("[feed-events] %d olay yazıldı | user_id=%s", len(rows), uid)
    except Exception as exc:
        logger.error("[feed-events] ClickHouse insert hatası: %s", exc, exc_info=True)


# ── SwipeLive Davranış Eventleri ─────────────────────────────────────────────

class SwipeLiveEventItem(BaseModel):
    stream_id: int = 0
    listing_id: int = 0
    event_type: str = Field(max_length=40)
    dwell_ms: int = 0
    stream_category: str = Field(default="", max_length=30)
    listing_category: str = Field(default="", max_length=30)
    listing_condition: str = Field(default="", max_length=20)
    listings_seen: int = 0
    slot_index: int = 0
    session_id: str = Field(default="", max_length=64)


class SwipeLiveEventBatch(BaseModel):
    events: list[SwipeLiveEventItem] = Field(max_length=200)


@router.post("/swipe-live-events", status_code=204)
async def ingest_swipe_live_events(
    batch: SwipeLiveEventBatch,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    SwipeLive'daki yayın ve ilan davranışlarını (dwell/skip/listing_tap/listing_impression)
    swipe_live_events ClickHouse tablosuna batch insert yapar.
    Yayın sıralama ve ilan sayısı kararlarını besler.
    """
    if not batch.events:
        return

    from app.database_clickhouse import batch_insert_swipe_live_events
    from app.models.listing import Listing

    # listing_condition'ı server-side resolve et (mobile her zaman bilmeyebilir)
    listing_ids = {e.listing_id for e in batch.events if e.listing_id and not e.listing_condition}
    condition_map: dict[int, str] = {}
    if listing_ids:
        rows_cond = await db.execute(
            select(Listing.id, Listing.condition).where(Listing.id.in_(listing_ids))
        )
        condition_map = {r.id: (r.condition or "") for r in rows_cond}

    events = [
        {
            "user_id": current_user.id,
            "stream_id": e.stream_id,
            "listing_id": e.listing_id,
            "event_type": e.event_type,
            "dwell_ms": e.dwell_ms,
            "stream_category": e.stream_category,
            "listing_category": e.listing_category,
            "listing_condition": e.listing_condition or condition_map.get(e.listing_id, ""),
            "listings_seen": e.listings_seen,
            "slot_index": e.slot_index,
            "session_id": e.session_id,
        }
        for e in batch.events
    ]
    import asyncio
    asyncio.create_task(batch_insert_swipe_live_events(events))


# ── Feed Performans İstatistikleri (Pro) ──────────────────────────────────────

@router.get("/my-feed-stats")
async def my_feed_stats(
    request: Request,
    days: int = Query(default=7, ge=1, le=90),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Pro satıcıya özel feed performans istatistikleri.
    Kullanıcının kendi ilanlarının impression/click/skip/CTR/dwell verilerini döndürür.
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "Bu özellik Pro kullanıcılara özeldir"))

    # Kullanıcının aktif ilan ID'lerini al
    result = await db.execute(
        select(Listing.id, Listing.title).where(
            Listing.user_id == current_user.id,
            Listing.status != ListingStatus.DELETED,  # noqa: E712
        )
    )
    listings = result.fetchall()
    if not listings:
        return {"stats": [], "totals": {"impressions": 0, "clicks": 0, "skips": 0, "ctr": 0.0, "avg_dwell_ms": 0}}

    listing_map = {str(r.id): r.title for r in listings}
    listing_ids = list(listing_map.keys())

    # ClickHouse'dan feed istatistiklerini çek
    try:
        ch = await get_clickhouse_client()
        placeholders = ", ".join(f"'{lid}'" for lid in listing_ids)
        query = f"""
            SELECT
                listing_id,
                countIf(event_type = 'impression')                              AS impressions,
                countIf(event_type = 'click')                                   AS clicks,
                countIf(event_type = 'skip')                                    AS skips,
                if(impressions > 0, round(clicks / impressions * 100, 1), 0)   AS ctr,
                round(avgIf(dwell_time_ms, event_type IN ('impression','skip')), 0) AS avg_dwell_ms
            FROM feed_analytics
            WHERE timestamp >= now() - INTERVAL {days} DAY
              AND listing_id IN ({placeholders})
            GROUP BY listing_id
            ORDER BY impressions DESC
        """
        rows = await ch.query(query)
        stats: List[Dict] = []
        for row in rows.result_rows:
            lid, impressions, clicks, skips, ctr, avg_dwell = row
            stats.append({
                "listing_id": lid,
                "title": listing_map.get(lid, "—"),
                "impressions": impressions,
                "clicks": clicks,
                "skips": skips,
                "ctr": float(ctr),
                "avg_dwell_ms": int(avg_dwell),
            })
    except Exception as exc:
        logger.error("[my-feed-stats] ClickHouse sorgu hatası: %s", exc, exc_info=True)
        return {"stats": [], "totals": {"impressions": 0, "clicks": 0, "skips": 0, "ctr": 0.0, "avg_dwell_ms": 0}}

    total_imp = sum(s["impressions"] for s in stats)
    total_clk = sum(s["clicks"] for s in stats)
    total_skp = sum(s["skips"] for s in stats)
    return {
        "stats": stats,
        "totals": {
            "impressions": total_imp,
            "clicks": total_clk,
            "skips": total_skp,
            "ctr": round(total_clk / total_imp * 100, 1) if total_imp > 0 else 0.0,
            "avg_dwell_ms": round(sum(s["avg_dwell_ms"] for s in stats) / len(stats)) if stats else 0,
        },
    }


# ── A6: Arama Intent Sınıflandırması ─────────────────────────────────────────

_TRANSACTIONAL_TOKENS = frozenset({
    "al", "sat", "alıyorum", "satıyorum", "acil", "acilen", "tl", "fiyat",
    "fiyatı", "ikinci", "el", "sıfır", "kutusunda", "indirim", "kampanya",
    "ucuz", "uygun", "pazarlık", "takas",
})


def _classify_search_intent(query: str, category: str, result_count: int) -> str:
    """
    Arama sorgusunu 4 kategoriden birine atar:
      navigational  — marka veya model adı içeriyor (hedefli arama)
      transactional — satın alma / fiyat sinyali var
      no_supply     — sonuç sıfır (arz açığı)
      exploratory   — genel keşif
    """
    try:
        from app.services.ml.ner_service import extract_ner
        ner = extract_ner(query, "", category or "")
        if ner.get("brand") or ner.get("model_name"):
            return "navigational"
    except Exception:
        pass

    tokens = set(query.lower().split())
    if tokens & _TRANSACTIONAL_TOKENS:
        return "transactional"

    if result_count == 0:
        return "no_supply"

    return "exploratory"


# ── Arama Olayı Kayıt ─────────────────────────────────────────────────────────

@router.post("/track-search", status_code=204)
async def track_search(
    body: SearchEventCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Arama sorgularını search_events tablosuna yazar (Talep Radar için).
    Kategori varsa analytics_events'e de yazar → compute_user_interests feed döngüsünü kapatır.
    """
    user_id = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            user_id = decode_token(auth_header.split(" ")[1])
        except Exception:
            pass

    intent = _classify_search_intent(
        query=body.query.strip(),
        category=body.category,
        result_count=body.result_count,
    )

    try:
        from app.database_clickhouse import buffer_search_event
        await buffer_search_event(
            user_id=user_id,
            query=body.query.strip(),
            category=body.category,
            result_count=body.result_count,
            intent=intent,
        )
    except Exception as exc:
        logger.warning("[track-search] ClickHouse buffer başarısız: %s", exc)

    # Kategori varsa analytics_events'e yaz → feed kişiselleştirme döngüsünü kapatır
    if user_id and body.category:
        try:
            event = AnalyticsEvent(
                user_id=user_id,
                event_type="search",
                event_metadata={"category": body.category, "result_count": body.result_count},
            )
            db.add(event)
            await db.commit()
        except Exception as exc:
            logger.warning("[track-search] PostgreSQL analytics_events yazılamadı: %s", exc)


# ── Video ROI (video vs fotoğraf CTR) ─────────────────────────────────────────

@router.get("/video-roi")
async def video_roi(
    request: Request,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Pro: Kullanıcının video ilanları ile fotoğraf ilanlarının CTR karşılaştırması.
    content_type='video' vs 'photo' segmentinde impression/click/CTR ayrımı.
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "Bu özellik Pro kullanıcılara özeldir"))

    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None
    _ts_cond = (f"AND timestamp >= '{_sd.strftime('%Y-%m-%d %H:%M:%S')}' AND timestamp < '{_ed.strftime('%Y-%m-%d %H:%M:%S')}'"
                if (_sd and _ed) else "AND timestamp >= now() - INTERVAL 30 DAY")

    listing_q = select(Listing.id, Listing.title, Listing.video_url, Listing.image_urls, Listing.image_url).where(
        Listing.user_id == current_user.id,
        Listing.status != ListingStatus.DELETED,  # noqa: E712
    )
    if category:
        listing_q = listing_q.where(Listing.category == category)
    result = await db.execute(listing_q)
    listings = result.fetchall()
    if not listings:
        return {"video": {}, "photo": {}, "by_listing": []}

    def _first_image(r) -> str:
        try:
            import json as _json
            imgs = _json.loads(r.image_urls) if r.image_urls else []
            return imgs[0] if imgs else (r.image_url or "")
        except Exception:
            return r.image_url or ""

    listing_map = {str(r.id): {"title": r.title, "has_video": bool(r.video_url), "image_url": _first_image(r)} for r in listings}
    listing_ids = list(listing_map.keys())

    try:
        ch = await get_clickhouse_client()
        placeholders = ", ".join(f"'{lid}'" for lid in listing_ids)
        rows = await ch.query(f"""
            SELECT
                content_type,
                countIf(event_type = 'impression')                                        AS impressions,
                countIf(event_type = 'click')                                             AS clicks,
                if(impressions > 0, round(toFloat64(clicks) / impressions * 100, 2), 0)  AS ctr,
                round(avgIf(dwell_time_ms, event_type IN ('impression','skip')), 0)       AS avg_dwell_ms
            FROM feed_analytics
            WHERE 1=1 {_ts_cond}
              AND listing_id IN ({placeholders})
            GROUP BY content_type
        """)
        segment: dict[str, dict] = {}
        for row in rows.result_rows:
            ct, imp, clk, ctr, dwell = row
            segment[ct] = {"impressions": imp, "clicks": clk, "ctr": float(ctr), "avg_dwell_ms": int(dwell)}

        per_listing = await ch.query(f"""
            SELECT
                listing_id,
                content_type,
                countIf(event_type = 'impression')                                        AS impressions,
                countIf(event_type = 'click')                                             AS clicks,
                if(impressions > 0, round(toFloat64(clicks) / impressions * 100, 2), 0)  AS ctr
            FROM feed_analytics
            WHERE 1=1 {_ts_cond}
              AND listing_id IN ({placeholders})
            GROUP BY listing_id, content_type
            ORDER BY impressions DESC
            LIMIT 20
        """)
        by_listing = []
        for row in per_listing.result_rows:
            lid, ct, imp, clk, ctr = row
            info = listing_map.get(lid, {})
            
            by_listing.append({
                "listing_id": lid,
                "title": info.get("title", "—"),
                "image_url": info.get("image_url", ""),
                "content_type": ct,
                "impressions": imp,
                "clicks": clk,
                "ctr": float(ctr),
            })
    except Exception as exc:
        logger.error("[video-roi] ClickHouse sorgu hatası: %s", exc, exc_info=True)
        return {"video": {}, "photo": {}, "by_listing": []}

    return {
        "video": segment.get("video", {"impressions": 0, "clicks": 0, "ctr": 0.0, "avg_dwell_ms": 0}),
        "photo": segment.get("photo", {"impressions": 0, "clicks": 0, "ctr": 0.0, "avg_dwell_ms": 0}),
        "by_listing": by_listing,
    }


# ── Galeri Analizi (fotoğraf swipe derinliği) ─────────────────────────────────

@router.get("/gallery-stats")
async def gallery_stats(
    request: Request,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Pro: İlan galerisinde kullanıcıların kaç fotoğrafa kadar ilerlediği.
    user_events tablosundaki listing_photo_swipe olayları kullanılır;
    duration_seconds alanı max_page_reached değerini taşır.
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "Bu özellik Pro kullanıcılara özeldir"))

    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None
    _ts_cond = (f"AND timestamp >= '{_sd.strftime('%Y-%m-%d %H:%M:%S')}' AND timestamp < '{_ed.strftime('%Y-%m-%d %H:%M:%S')}'"
                if (_sd and _ed) else "AND timestamp >= now() - INTERVAL 30 DAY")

    listing_q = select(Listing.id, Listing.title, Listing.image_urls).where(
        Listing.user_id == current_user.id,
        Listing.status != ListingStatus.DELETED,  # noqa: E712
    )
    if category:
        listing_q = listing_q.where(Listing.category == category)
    result = await db.execute(listing_q)
    listings = result.fetchall()
    if not listings:
        return {"stats": []}

    import json as _json
    listing_map = {r.id: r.title for r in listings}
    listing_ids = [r.id for r in listings]
    photo_count_map: dict[int, int] = {}
    for r in listings:
        try:
            urls = _json.loads(r.image_urls) if r.image_urls else []
            photo_count_map[r.id] = max(1, len(urls))
        except Exception:
            photo_count_map[r.id] = 1

    try:
        ch = await get_clickhouse_client()
        ids_str = ", ".join(str(i) for i in listing_ids)
        rows = await ch.query(f"""
            SELECT
                item_id,
                COUNT(*)                                  AS views,
                round(avg(duration_seconds), 1)           AS avg_swipe_depth,
                max(duration_seconds)                     AS max_swipe_depth
            FROM user_events
            WHERE item_type = 'listing'
              AND event_type = 'listing_photo_swipe'
              AND item_id IN ({ids_str})
              {_ts_cond}
            GROUP BY item_id
            ORDER BY avg_swipe_depth DESC
            LIMIT 20
        """)
        stats = []
        for row in rows.result_rows:
            lid, views, avg_depth, max_depth = row
            total_photos = photo_count_map.get(int(lid), 1)
            avg_d = float(avg_depth or 0)
            depth_pct = round(min(100.0, avg_d / total_photos * 100), 1) if total_photos > 0 else 0.0
            stats.append({
                "listing_id": lid,
                "title": listing_map.get(int(lid), "—"),
                "views": int(views),
                "avg_swipe_depth": avg_d,
                "max_swipe_depth": int(max_depth or 0),
                "total_photos": total_photos,
                "depth_pct": depth_pct,
            })
    except Exception as exc:
        logger.error("[gallery-stats] ClickHouse sorgu hatası: %s", exc, exc_info=True)
        return {"stats": []}

    return {"stats": stats}


# ── Video Performansı (tamamlanma oranı) ──────────────────────────────────────

@router.get("/video-performance")
async def video_performance(
    request: Request,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Pro: İlan videolarının ortalama tamamlanma yüzdesi ve tam izlenme oranı.
    user_events tablosundaki listing_video_watch olayları kullanılır;
    duration_seconds alanı watch_pct (0.0–1.0) değerini taşır.
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "Bu özellik Pro kullanıcılara özeldir"))

    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None
    _ts_cond = (f"AND timestamp >= '{_sd.strftime('%Y-%m-%d %H:%M:%S')}' AND timestamp < '{_ed.strftime('%Y-%m-%d %H:%M:%S')}'"
                if (_sd and _ed) else "AND timestamp >= now() - INTERVAL 30 DAY")

    listing_q = select(Listing.id, Listing.title).where(
        Listing.user_id == current_user.id,
        Listing.status != ListingStatus.DELETED,  # noqa: E712
        Listing.video_url.isnot(None),
    )
    if category:
        listing_q = listing_q.where(Listing.category == category)
    result = await db.execute(listing_q)
    listings = result.fetchall()
    if not listings:
        return {"stats": []}

    listing_map = {r.id: r.title for r in listings}
    listing_ids = [r.id for r in listings]

    try:
        ch = await get_clickhouse_client()
        ids_str = ", ".join(str(i) for i in listing_ids)
        rows = await ch.query(f"""
            SELECT
                item_id,
                COUNT(*)                                              AS play_count,
                round(avg(duration_seconds) * 100, 1)                AS avg_completion_pct,
                countIf(duration_seconds >= 0.8) / COUNT(*) * 100    AS full_watch_rate
            FROM user_events
            WHERE item_type = 'listing'
              AND event_type = 'listing_video_watch'
              AND item_id IN ({ids_str})
              {_ts_cond}
            GROUP BY item_id
            ORDER BY avg_completion_pct DESC
            LIMIT 20
        """)
        stats = []
        for row in rows.result_rows:
            lid, plays, avg_pct, full_rate = row
            stats.append({
                "listing_id": lid,
                "title": listing_map.get(int(lid), "—"),
                "play_count": int(plays),
                "avg_completion_pct": float(avg_pct or 0),
                "full_watch_rate_pct": round(float(full_rate or 0), 1),
            })
    except Exception as exc:
        logger.error("[video-performance] ClickHouse sorgu hatası: %s", exc, exc_info=True)
        return {"stats": []}

    return {"stats": stats}


# ── Talep Radar (arama trendleri) ─────────────────────────────────────────────

@router.get("/demand-radar")
async def demand_radar(
    request: Request,
    days: int = Query(default=7, ge=1, le=30),
    current_user: User = Depends(get_current_user),
):
    """
    Pro: Platform genelindeki arama trendleri.
    En çok aranan kelimeler ve kategori bazlı arama hacmi.
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "Bu özellik Pro kullanıcılara özeldir"))

    try:
        redis = await get_redis()
        cache_key = f"cache:demand_radar:{days}"
        cached = await redis.get(cache_key)
        if cached:
            import json
            return json.loads(cached)
    except Exception:
        redis = None
        cache_key = None

    try:
        ch = await get_clickhouse_client()

        q_top = f"""
            SELECT query, COUNT(*) AS cnt
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {days} DAY
              AND length(query) >= 2
            GROUP BY query
            HAVING cnt >= 2
            ORDER BY cnt DESC
            LIMIT 20
        """

        q_cat = f"""
            SELECT category, COUNT(*) AS cnt
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {days} DAY
              AND category != ''
            GROUP BY category
            HAVING cnt >= 2
            ORDER BY cnt DESC
            LIMIT 10
        """

        q_vol = f"""
            SELECT toDate(timestamp) AS day, COUNT(*) AS cnt
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {days} DAY
            GROUP BY day
            ORDER BY day
        """

        # asyncio.gather ile eşzamanlı sorgular
        top_queries, by_category, daily_volume = await asyncio.gather(
            ch.query(q_top),
            ch.query(q_cat),
            ch.query(q_vol)
        )

        response_data = {
            "top_queries": [{"query": r[0], "count": int(r[1])} for r in top_queries.result_rows],
            "by_category": [{"category": r[0] or "diğer", "count": int(r[1])} for r in by_category.result_rows],
            "daily_volume": [{"day": str(r[0]), "count": int(r[1])} for r in daily_volume.result_rows],
        }

        if redis and cache_key:
            try:
                import json
                await redis.setex(cache_key, 300, json.dumps(response_data))
            except Exception:
                pass

        return response_data
    except Exception as exc:
        logger.error("[demand-radar] ClickHouse sorgu hatası: %s", exc, exc_info=True)
        return {"top_queries": [], "by_category": [], "daily_volume": []}


# ── PRO Metrik Endpointleri ───────────────────────────────────────────────────

@router.get("/pro/metrics")
async def get_pro_metrics(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    PRO kullanıcılar için gelişmiş metrikler:
    - avg_detail_dwell: ilan detay sayfasında ortalama geçirilen süre (saniye)
    - search_visibility: kullanıcının ilanlarının arama sonuçlarında toplam görünüm sayısı (son 30 gün)
    - best_posting_hour: kullanıcının en yüksek CTR'a sahip ilan paylaşım saati
    - return_viewer_rate: en az 2 kez yayınını izleyen kullanıcı oranı
    """
    t = _get_t(get_locale(current_user, request))
    if not current_user.is_premium:
        raise HTTPException(status_code=403, detail=t.get("errProRequired", "PRO üyelik gerekli"))

    uid = current_user.id

    # 0. Kullanıcının aktif ilanlarını ve saatlerini çek
    listings_result = await db.execute(sql_text("""
        SELECT id, category, EXTRACT(HOUR FROM created_at) AS hr 
        FROM listings 
        WHERE user_id = :uid AND status = 'active'
    """), {"uid": uid})
    active_listings = listings_result.fetchall()
    
    listing_ids = [str(r.id) for r in active_listings]
    categories = list(set([r.category for r in active_listings if r.category]))
    
    avg_dwell = None
    search_visibility = []
    best_hour = None

    if listing_ids:
        ids_str = ",".join(listing_ids)
        try:
            from app.database_clickhouse import get_clickhouse_client
            ch = await get_clickhouse_client()

            # 1. Ortalama detay inceleme süresi (avg_detail_dwell)
            dwell_ch = await ch.query(f"""
                SELECT AVG(duration_seconds)
                FROM user_events
                WHERE item_type = 'listing'
                  AND item_id IN ({ids_str})
                  AND event_type = 'dwell'
                  AND timestamp >= now() - INTERVAL 30 DAY
            """)
            if dwell_ch.result_rows and dwell_ch.result_rows[0][0] is not None:
                avg_dwell = round(float(dwell_ch.result_rows[0][0]), 1)

            # 2. Arama görünürlüğü (search_visibility)
            if categories:
                cats_str = ",".join([f"'{c}'" for c in categories])
                search_ch = await ch.query(f"""
                    SELECT category, count(*) AS search_count
                    FROM search_events
                    WHERE category IN ({cats_str})
                      AND timestamp >= now() - INTERVAL 30 DAY
                    GROUP BY category
                    ORDER BY search_count DESC
                    LIMIT 5
                """)
                search_visibility = [{"category": r[0], "search_count": int(r[1])} for r in search_ch.result_rows]

            # 3. En iyi paylaşım saati (best_posting_hour)
            stats_ch = await ch.query(f"""
                SELECT item_id, 
                       countIf(event_type = 'view') AS views,
                       countIf(event_type = 'click') AS clicks
                FROM user_events
                WHERE item_type = 'listing'
                  AND item_id IN ({ids_str})
                  AND timestamp >= now() - INTERVAL 90 DAY
                GROUP BY item_id
            """)
            
            hour_stats = {}
            item_hour_map = {int(r.id): int(r.hr) for r in active_listings}
            
            for row in stats_ch.result_rows:
                item_id = int(row[0])
                views = int(row[1])
                clicks = int(row[2])
                hr = item_hour_map.get(item_id)
                
                if hr is not None:
                    if hr not in hour_stats:
                        hour_stats[hr] = {"views": 0, "clicks": 0}
                    hour_stats[hr]["views"] += views
                    hour_stats[hr]["clicks"] += clicks
            
            best_ctr = -1.0
            for hr, stats in hour_stats.items():
                if stats["views"] >= 10:
                    ctr = stats["clicks"] / stats["views"]
                    if ctr > best_ctr:
                        best_ctr = ctr
                        best_hour = hr
                        
        except Exception as exc:
            logger.warning("[ProMetrics] ClickHouse analitiği başarısız: %s", exc)

    # 4. Geri dönen izleyici oranı (yayın stream'lerinden)
    return_viewer_rate = None
    return_viewer_count = 0
    total_viewer_count = 0
    return_result = await db.execute(sql_text("""
        WITH viewer_counts AS (
            SELECT lsv.user_id, COUNT(DISTINCT ls.id) AS stream_count
            FROM live_stream_viewers lsv
            INNER JOIN live_streams ls ON ls.id = lsv.stream_id AND ls.host_id = :uid
            WHERE lsv.user_id != :uid
              AND lsv.joined_at >= NOW() - INTERVAL '180 days'
            GROUP BY lsv.user_id
        )
        SELECT
            COUNT(*) FILTER (WHERE stream_count >= 2)::float /
            NULLIF(COUNT(*), 0) AS return_rate,
            COUNT(*) AS total_viewers,
            COUNT(*) FILTER (WHERE stream_count >= 2) AS return_viewers
        FROM viewer_counts
    """), {"uid": uid})
    ret_row = return_result.fetchone()
    if ret_row and ret_row[0] is not None:
        return_viewer_rate = round(float(ret_row[0]) * 100, 1)
        total_viewer_count = int(ret_row[1])
        return_viewer_count = int(ret_row[2])

    return {
        "avg_detail_dwell_seconds": avg_dwell,
        "search_visibility": search_visibility,
        "best_posting_hour": best_hour,
        "return_viewer_rate_pct": return_viewer_rate,
        "return_viewer_count": return_viewer_count,
        "total_viewer_count": total_viewer_count,
    }


# ── Rakip Fiyat Radarı ───────────────────────────────────────────────────────

@router.get("/competitor-radar/{listing_id}")
async def competitor_radar(
    listing_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    PRO: Kullanıcının ilanını pgvector ile benzer aktif ilanlarla karşılaştırır.
    Fiyat dağılımı, rakip sayısı ve pozisyon sinyali döner.
    """
    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id)
    )
    t = _get_t(get_locale(current_user, request))
    if not listing:
        raise HTTPException(404, t.get("errListingNotFound", "İlan bulunamadı"))

    if listing.price is None:
        return {"signal": "no_price", "competitors": [], "stats": {}}

    if listing.embedding is None:
        # Embedding yoksa kategori bazlı karşılaştırmaya dön
        rows = (await db.execute(sql_text("""
            SELECT id, title, price, user_id
            FROM listings
            WHERE status = 'active'
              AND category = :cat AND id != :lid AND user_id != :uid
              AND price IS NOT NULL
            ORDER BY ABS(price - :price) ASC
            LIMIT 20
        """), {"cat": listing.category, "lid": listing_id,
               "uid": current_user.id, "price": float(listing.price)})).fetchall()
    else:
        emb_str = "[" + ",".join(f"{v:.6f}" for v in listing.embedding) + "]"
        rows = (await db.execute(sql_text("""
            SELECT l.id, l.title, l.price, l.user_id
            FROM listings l
            WHERE l.status = 'active'
              AND l.embedding IS NOT NULL
              AND l.id != :lid AND l.user_id != :uid
              AND l.price IS NOT NULL
              AND (l.embedding <=> CAST(:emb AS vector)) < 0.45
            ORDER BY l.embedding <=> CAST(:emb AS vector)
            LIMIT 20
        """), {"lid": listing_id, "uid": current_user.id, "emb": emb_str})).fetchall()

    if not rows:
        return {"signal": "no_data", "competitors": [], "stats": {}}

    prices = [float(r[2]) for r in rows]
    my_price = float(listing.price)
    avg_price = sum(prices) / len(prices)
    min_price = min(prices)
    max_price = max(prices)
    cheaper_count = sum(1 for p in prices if p < my_price)
    pct_rank = round((cheaper_count / len(prices)) * 100)  # 0=en ucuz, 100=en pahalı
    t = _get_t(get_locale(current_user, request))

    if pct_rank >= 75:
        signal = "pahalı"
        signal_detail = t.get("radarExpensive", "Rakiplerin %{pct_rank}'inden pahalısın").replace("{pct_rank}", str(pct_rank))
    elif pct_rank <= 25:
        signal = "ucuz"
        signal_detail = t.get("radarCheap", "Rakiplerin %{pct_rank}'inden ucuzsun — fiyat artırabilirsin").replace("{pct_rank}", str(100 - pct_rank))
    else:
        signal = "uygun"
        signal_detail = t.get("radarFair", "Fiyatın piyasa ortalamasına yakın")

    if signal == "pahalı":
        suggested_price = round(avg_price * 0.95)
    elif signal == "ucuz":
        suggested_price = round(avg_price * 1.03)
    else:
        suggested_price = round(avg_price * 0.97)
    diff_pct = round(((my_price - avg_price) / avg_price) * 100, 1)

    competitors = [
        {"id": r[0], "title": r[1][:40], "price": float(r[2])}
        for r in rows[:8]
    ]

    return {
        "signal": signal,
        "signal_detail": signal_detail,
        "my_price": my_price,
        "avg_price": round(avg_price, 2),
        "min_price": min_price,
        "max_price": max_price,
        "diff_pct": diff_pct,
        "pct_rank": pct_rank,
        "competitor_count": len(rows),
        "suggested_price": suggested_price,
        "competitors": competitors,
    }


# ── Satış Hızı ───────────────────────────────────────────────────────────────

@router.get("/category-velocity")
async def category_velocity(
    request: Request,
    category: str = Query(..., min_length=1),
    listing_id: Optional[int] = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    PRO: Kategoride son 90 günde satılan ilanların ortalama satış süresi,
    fiyat hassasiyeti ve en iyi fiyat aralığı.
    """
    from app.models.bid import Bid

    # Ortalama satış süresi (oluşturma → kazanılan auction)
    velocity_row = (await db.execute(sql_text("""
        SELECT
            COUNT(*) AS total_sold,
            ROUND(AVG(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS avg_days,
            ROUND(MIN(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS min_days,
            ROUND(MAX(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS max_days,
            ROUND(AVG(l.price)::numeric, 0) AS avg_price,
            ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY l.price)::numeric, 0) AS p25_price,
            ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY l.price)::numeric, 0) AS p75_price
        FROM auctions a
        INNER JOIN listings l ON l.id = a.listing_id
        WHERE a.status = 'completed'
          AND a.winner_username IS NOT NULL
          AND a.ended_at IS NOT NULL
          AND l.category = :cat
          AND a.ended_at > NOW() - INTERVAL '90 days'
          AND l.price IS NOT NULL
    """), {"cat": category})).fetchone()

    # Fiyat hassasiyeti — ucuz vs pahalı ilanların satış hızı farkı
    price_sens = (await db.execute(sql_text("""
        SELECT
            CASE WHEN l.price <= pct.p50 THEN 'ucuz' ELSE 'pahalı' END AS bucket,
            ROUND(AVG(EXTRACT(EPOCH FROM (a.ended_at - l.created_at)) / 86400.0)::numeric, 1) AS avg_days,
            COUNT(*) AS count
        FROM auctions a
        INNER JOIN listings l ON l.id = a.listing_id
        INNER JOIN (
            SELECT category,
                   PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS p50
            FROM listings WHERE category = :cat AND status != 'deleted'
            GROUP BY category
        ) pct ON pct.category = l.category
        WHERE a.status = 'completed'
          AND a.winner_username IS NOT NULL
          AND a.ended_at IS NOT NULL
          AND l.category = :cat
          AND a.ended_at > NOW() - INTERVAL '90 days'
          AND l.price IS NOT NULL
        GROUP BY bucket
    """), {"cat": category})).fetchall()

    # Mevcut aktif rakip sayısı
    active_count = await db.scalar(sql_text("""
        SELECT COUNT(*) FROM listings
        WHERE category = :cat AND status = 'active'
          AND id != COALESCE(:lid, 0)
    """), {"cat": category, "lid": listing_id or 0})

    total_sold = int(velocity_row[0]) if velocity_row and velocity_row[0] else 0
    avg_days = float(velocity_row[1]) if velocity_row and velocity_row[1] else None
    min_days = float(velocity_row[2]) if velocity_row and velocity_row[2] else None
    max_days = float(velocity_row[3]) if velocity_row and velocity_row[3] else None
    avg_price = float(velocity_row[4]) if velocity_row and velocity_row[4] else None
    p25 = float(velocity_row[5]) if velocity_row and velocity_row[5] else None
    p75 = float(velocity_row[6]) if velocity_row and velocity_row[6] else None

    price_sensitivity = [
        {"bucket": r[0], "avg_days": float(r[1]), "count": int(r[2])}
        for r in price_sens
    ] if price_sens else []

    # Öneri metni
    t = _get_t(get_locale(current_user, request))
    tip = None
    if avg_days and avg_days > 0:
        if price_sensitivity:
            ucuz = next((p for p in price_sensitivity if p["bucket"] == "ucuz"), None)
            pahali = next((p for p in price_sensitivity if p["bucket"] == "pahalı"), None)
            if ucuz and pahali and pahali["avg_days"] > 0 and ucuz["avg_days"] > 0:
                speed_ratio = round(pahali["avg_days"] / ucuz["avg_days"], 1)
                if speed_ratio >= 1.5:
                    tip = t.get("proSalesSpeedTip", "Piyasa ortalamasının altında fiyatlanan ilanlar {ratio}× daha hızlı satılıyor").replace("{ratio}", str(speed_ratio))

    return {
        "category": t.get(f"cat_{category}", category),
        "total_sold_90d": total_sold,
        "avg_days_to_sell": avg_days,
        "min_days_to_sell": min_days,
        "max_days_to_sell": max_days,
        "avg_sold_price": avg_price,
        "sweet_spot_min": p25,
        "sweet_spot_max": p75,
        "active_competitor_count": int(active_count or 0),
        "price_sensitivity": price_sensitivity,
        "tip": tip,
    }


# ── A5: Kategori Talep Tahmini ────────────────────────────────────────────────

@router.get("/demand-trends")
async def demand_trends(
    weeks: int = Query(default=8, ge=4, le=16),
    current_user: User = Depends(get_current_user),
):
    """
    PRO: Son N haftanın search_events verisinden kategori bazlı talep trendi.
    Döner: kategori, haftalık arama sayısı, trend yönü, momentum, arz açığı oranı.
    """
    if not current_user.is_premium:
        raise ForbiddenException("Bu özellik PRO üyelere özeldir.", code="PRO_REQUIRED")

    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        if ch is None:
            raise ServiceException("Analitik servisi geçici olarak kullanılamıyor.")

        result = await ch.query(f"""
            SELECT
                category,
                toStartOfWeek(timestamp, 1)  AS week,
                count()                       AS search_count,
                countIf(result_count = 0)     AS zero_result_count
            FROM search_events
            WHERE timestamp >= now() - INTERVAL {weeks} WEEK
              AND category   != ''
            GROUP BY category, week
            ORDER BY category, week
        """)

        from collections import defaultdict
        cat_weeks: dict[str, list[dict]] = defaultdict(list)
        for cat, week, cnt, zero in result.result_rows:
            cat_weeks[str(cat)].append({
                "week": str(week)[:10],
                "count": int(cnt),
                "zero": int(zero),
            })

        trends = []
        for cat, weekly in cat_weeks.items():
            if len(weekly) < 2:
                continue
            weekly.sort(key=lambda x: x["week"])
            counts = [w["count"] for w in weekly]
            zeros  = [w["zero"] for w in weekly]

            first, last = counts[0], counts[-1]
            prev  = counts[-2] if len(counts) >= 2 else last

            pct_change = round((last - first) / max(first, 1) * 100, 1)
            momentum   = round(last / max(prev, 1), 2)
            avg_zero_ratio = round(sum(zeros) / max(sum(counts), 1) * 100, 1)

            if pct_change >= 20:
                direction = "up"
            elif pct_change <= -20:
                direction = "down"
            else:
                direction = "stable"

            trends.append({
                "category": cat,
                "weekly": weekly,
                "pct_change_8w": pct_change,
                "momentum": momentum,
                "direction": direction,
                "zero_result_pct": avg_zero_ratio,
                "supply_gap": avg_zero_ratio >= 30,
            })

        trends.sort(key=lambda x: abs(x["pct_change_8w"]), reverse=True)
        return {"weeks": weeks, "trends": trends}

    except AppException:
        raise
    except Exception as exc:
        logger.warning("[DemandTrends] Hata: %s", exc)
        raise ServiceException("Talep verisi alınamadı.")
