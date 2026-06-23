import json
import logging
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Any, Dict, Optional

from app.database import get_db
from app.models.analytics import AnalyticsEvent
from app.models.auction import Auction
from app.models.stream import LiveStream
from app.models.user import User
from app.schemas.analytics import AnalyticsEventCreate
from app.utils.auth import decode_token, get_current_user
from app.utils.redis_client import get_redis

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
    user_id = None
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        try:
            user_id = decode_token(auth_header.split(" ")[1])
        except Exception:
            pass

    record = {
        "user_id": user_id,
        "item_id": payload.item_id,
        "item_type": payload.item_type,
        "interaction_type": payload.interaction_type,
        "duration_seconds": payload.duration_seconds,
        "price_point": payload.price_point,
        "metadata": payload.metadata,
    }

    try:
        redis = await get_redis()
        await redis.rpush(INTERACTION_QUEUE, json.dumps(record))
    except Exception as exc:
        logger.error("[ANALYTICS] Redis rpush başarısız: %s", exc)

    return {"status": "queued"}


# ── Satıcı Yayın Raporu ───────────────────────────────────────────────────────

def _build_recommendation(avg_budget: float | None, hesitation_count: int, unique_users: int) -> str:
    """
    Metriklere göre kişiselleştirilmiş öneri metni üretir.
    Kural tabanlı 'makul AI' — harici API gerektirmez.
    """
    if avg_budget is None or avg_budget <= 0:
        if hesitation_count > 5:
            return (
                f"Bugün {hesitation_count} izleyici teklif vermekle ilgilendi ama tereddüt etti. "
                "Bir dahaki yayında daha düşük başlangıç fiyatıyla başlayarak ilgiyi satışa dönüştürebilirsiniz."
            )
        return (
            "Henüz yeterli bütçe verisi yok. Yayınlarınızı düzenli tutarak "
            "kitle profili oluştururken fiyat aralıklarını deneyebilirsiniz."
        )

    budget_fmt = f"{int(avg_budget):,}".replace(",", ".")

    if hesitation_count >= 10:
        low = int(avg_budget * 0.7)
        low_fmt = f"{low:,}".replace(",", ".")
        return (
            f"İzleyicilerinizin ortalama bütçesi {budget_fmt} TL. "
            f"Bugün {hesitation_count} kişi teklif vermek istedi ama vazgeçti — "
            f"bir dahaki yayında {low_fmt} TL gibi düşük başlangıç fiyatları deneyerek "
            "bu kararsız kitleyi satışa çevirebilirsiniz."
        )
    elif hesitation_count >= 3:
        return (
            f"İzleyicilerinizin ortalama bütçesi {budget_fmt} TL. "
            f"{hesitation_count} izleyici tekliften vazgeçti — "
            "ürün açıklamalarını ve fiyat adımlarını netleştirerek dönüşüm oranınızı artırabilirsiniz."
        )
    elif unique_users >= 10:
        high = int(avg_budget * 1.15)
        high_fmt = f"{high:,}".replace(",", ".")
        return (
            f"İzleyicilerinizin ortalama bütçesi {budget_fmt} TL. "
            f"Kitle profiliniz güçlü görünüyor. Bir dahaki yayında "
            f"{high_fmt} TL'ye kadar premium ürünler sunarak geliri artırabilirsiniz."
        )
    else:
        return (
            f"İzleyicilerinizin ortalama bütçesi {budget_fmt} TL. "
            "Bu fiyat bandında ürünler getirerek satışlarınızı artırabilirsiniz."
        )


@router.get("/seller-report/{stream_id}")
async def get_seller_report(
    stream_id: int,
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
    stream = await db.scalar(select(LiveStream).where(LiveStream.id == stream_id))
    if stream is None:
        raise HTTPException(status_code=404, detail="Yayın bulunamadı")
    if stream.host_id != current_user.id:
        raise HTTPException(status_code=403, detail="Bu rapora erişim yetkiniz yok")

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

    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()

        if listing_ids:
            ids_str = ", ".join(str(i) for i in listing_ids)
            ts_start = stream.started_at.strftime("%Y-%m-%d %H:%M:%S")
            ts_end = ended.strftime("%Y-%m-%d %H:%M:%S")

            result = await ch.query(f"""
                SELECT
                    countDistinct(user_id)                          AS unique_viewers,
                    avgIf(price_point, price_point > 0)             AS avg_budget,
                    countIf(event_type = 'bid_hesitation')          AS hesitation_count
                FROM user_events
                WHERE item_id IN ({ids_str})
                  AND item_type = 'listing'
                  AND timestamp BETWEEN '{ts_start}' AND '{ts_end}'
            """)
            row = result.result_rows[0] if result.result_rows else (0, None, 0)
            unique_viewers = int(row[0] or 0)
            avg_budget = float(row[1]) if row[1] else None
            hesitation_count = int(row[2] or 0)
        else:
            # Açık artırma ilanı yoksa sadece 'view'/'dwell' sinyallerini kullan
            ts_start = stream.started_at.strftime("%Y-%m-%d %H:%M:%S")
            ts_end = ended.strftime("%Y-%m-%d %H:%M:%S")
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
    recommendation = _build_recommendation(avg_budget, hesitation_count, unique_viewers)

    return {
        "stream_id": stream_id,
        "stream_title": stream.title,
        "duration_minutes": duration_minutes,
        "peak_viewers": stream.viewer_count,
        "unique_viewers": unique_viewers,
        "avg_budget": round(avg_budget, 2) if avg_budget else None,
        "hesitation_count": hesitation_count,
        "recommendation": recommendation,
        "auction_summary": auction_summary,
    }
