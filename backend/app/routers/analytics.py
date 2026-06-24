import json
import logging
import asyncio
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy import select, text as sql_text
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


# ── Yapay Zeka Fiyatlama Danışmanı ───────────────────────────────────────────

class PriceEstimateRequest(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    description: str = Field(default="", max_length=2000)
    category: str = Field(default="")  # category key (e.g. "elektronik")


@router.post("/price-estimate")
async def price_estimate(
    body: PriceEstimateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Başlık + açıklama metninden embedding üretir, pgvector ile satılmış benzer
    ilanları bulur ve istatistiksel fiyat tahmini üretir.
    """
    from app.services.ml_service import generate_embedding

    # 1. CPU-blocking embedding işini executor'da çalıştır
    combined = f"{body.title.strip()} {body.description.strip()}".strip()
    loop = asyncio.get_event_loop()
    embedding: list[float] = await loop.run_in_executor(None, generate_embedding, combined)

    # pgvector literal: '[0.1,0.2,...]'
    emb_str = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"

    # 2. Benzer satılmış ilanları bul (auction winner'ı olan = satıldı)
    q = sql_text("""
        WITH nearby AS (
            SELECT
                a.start_price,
                a.final_price,
                (l.embedding <=> CAST(:emb AS vector)) AS dist
            FROM listings l
            JOIN auctions a ON a.listing_id = l.id
            WHERE a.winner_username IS NOT NULL
              AND l.embedding IS NOT NULL
              AND (l.embedding <=> CAST(:emb AS vector)) < 0.4
            ORDER BY dist
            LIMIT 50
        )
        SELECT
            COUNT(*)                                                 AS cnt,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY start_price) AS median_start,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_price)  AS median_final,
            AVG(start_price)                                         AS avg_start,
            AVG(final_price)                                         AS avg_final,
            MIN(final_price)                                         AS min_final,
            MAX(final_price)                                         AS max_final
        FROM nearby
    """)

    result = await db.execute(q, {"emb": emb_str})
    row = result.fetchone()
    cnt = int(row.cnt or 0)

    if cnt == 0:
        return {
            "found_similar": 0,
            "suggested_start_price": None,
            "estimated_close_price": None,
            "min_close_price": None,
            "max_close_price": None,
            "confidence": "low",
            "advice": (
                "Henüz yeterli benzer ürün verisi bulunamadı. "
                "Platforma eklendikçe tahminler daha isabetli hale gelecek. "
                "Piyasa araştırması yaparak fiyatınızı belirleyebilirsiniz."
            ),
        }

    suggested_start = round(float(row.median_start or row.avg_start or 0), 2)
    estimated_close = round(float(row.median_final or row.avg_final or 0), 2)
    min_close = round(float(row.min_final), 2) if row.min_final else None
    max_close = round(float(row.max_final), 2) if row.max_final else None

    confidence = "high" if cnt >= 20 else ("medium" if cnt >= 5 else "low")

    # 3. Tavsiye metni üret
    cat = body.category.strip() or "ürün"
    close_fmt = f"{int(estimated_close):,}".replace(",", ".")
    start_fmt = f"{int(suggested_start):,}".replace(",", ".")

    advice = (
        f"Benzer {cnt} ürün satış verisi analiz edildi. "
        f"Önerilen başlangıç fiyatı {start_fmt} ₺, "
        f"nihai kapanış ortalama {close_fmt} ₺ bandında gerçekleşti."
    )
    if estimated_close > suggested_start * 1.35:
        advice += (
            " Bu kategoride teklif rekabeti yüksek — "
            "düşük başlangıç fiyatı daha fazla katılımcı çekebilir."
        )
    elif estimated_close < suggested_start * 0.9:
        advice += (
            " Başlangıç fiyatını biraz daha gerçekçi tutmak "
            "satış hızınızı artırabilir."
        )

    return {
        "found_similar": cnt,
        "suggested_start_price": suggested_start,
        "estimated_close_price": estimated_close,
        "min_close_price": min_close,
        "max_close_price": max_close,
        "confidence": confidence,
        "advice": advice,
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
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Son 30 günlük platform makro trendleri.
    - peak_hours: etkileşim yoğunluğu en yüksek 3 saat
    - trending_categories: teklif hacmi en çok artan 3 kategori
    - average_spend_growth: ortalama harcama değişim yüzdesi (önceki 30 güne göre)
    """
    # ── 1. Peak hours — ClickHouse ────────────────────────────────────────────
    peak_hours: list[dict] = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(
            """
            SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
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
                CASE WHEN COALESCE(p.cnt, 0) > 0
                    THEN ROUND(((r.cnt - p.cnt)::float / p.cnt) * 100, 1)
                    ELSE 100.0
                END AS growth_pct
            FROM recent r
            LEFT JOIN prev p ON p.category = r.category
            ORDER BY growth_pct DESC
            LIMIT 3
        """)
        cat_result = await db.execute(cat_q)
        for row in cat_result.fetchall():
            key = row.category or "diger"
            trending_categories.append({
                "key": key,
                "label": _CATEGORY_LABELS.get(key, key.capitalize()),
                "recent_count": int(row.recent_cnt),
                "prev_count": int(row.prev_cnt),
                "growth_pct": float(row.growth_pct),
            })
    except Exception as exc:
        logger.warning("[MarketTrends] trending_categories başarısız: %s", exc)

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

    return {
        "peak_hours": peak_hours,
        "trending_categories": trending_categories,
        "average_spend_growth": avg_spend_growth,
    }
