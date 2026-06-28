"""
Reklam Ağı Endpointleri.

POST /api/ads/campaigns               — kampanya oluştur (satıcı)
POST /api/ads/click/{campaign_id}     — tıklama → bütçe düşer
POST /api/ads/impression/{campaign_id} — gösterim → ClickHouse'a log
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from sqlalchemy import text as sql_text

from app.database import get_db
from app.models.ad_campaign import AdCampaign
from app.models.listing import Listing
from app.models.tuci_transaction import TuciTransaction
from app.models.user import User
from app.utils.auth import bearer_scheme, decode_token, get_current_user
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ads", tags=["ads"])

# ── Boost Kredi Sabitleri ─────────────────────────────────────────────────────

_BOOST_LIMIT_FREE = 0   # Ücretsiz hesap: boost yapamaz
_BOOST_LIMIT_PRO  = 20  # Pro hesap: ayda 20 boost


def _boost_redis_key(user_id: int) -> str:
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    return f"boost_credits:{user_id}:{month}"


async def _get_boost_used(user_id: int) -> int:
    redis = await get_redis()
    val = await redis.get(_boost_redis_key(user_id))
    return int(val) if val else 0


async def _increment_boost(user_id: int) -> None:
    redis = await get_redis()
    key = _boost_redis_key(user_id)
    count = await redis.incr(key)
    if count == 1:
        # İlk boost — ayın sonuna kadar TTL
        now = datetime.now(timezone.utc)
        import calendar
        last_day = calendar.monthrange(now.year, now.month)[1]
        end_of_month = now.replace(day=last_day, hour=23, minute=59, second=59)
        ttl = int((end_of_month - now).total_seconds()) + 1
        await redis.expire(key, ttl)


# ── Şemalar ───────────────────────────────────────────────────────────────────

class CampaignCreate(BaseModel):
    listing_id: int
    total_budget: int = Field(gt=0)
    cpc_bid: int = Field(gt=0)


# ── Kampanya Oluştur ──────────────────────────────────────────────────────────

_BOOST_PAID_COST = 50  # Aylık ücretsiz hak bitince ücretli boost maliyeti (TUCi)


@router.post("/campaigns", status_code=201)
async def create_campaign(
    body: CampaignCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcı kendi ilanı için reklam kampanyası başlatır.

    - Pro kullanıcılar ayda 20 boost hakkına sahiptir (ücretsiz).
    - Aylık hak biterse TUCi bakiyesinden 50 TUCi düşürülerek boost yapılır.
    - Ücretsiz hesaplar boost yapamaz.
    - İlanın sahibi olduğu doğrulanır.
    - AdCampaign kaydı oluşturulur (status='active').
    - Redis bütçe engine'ine yüklenir (anında aktif hale gelir).
    """
    # Aylık boost kredi kontrolü
    boost_limit = _BOOST_LIMIT_PRO if current_user.is_premium else _BOOST_LIMIT_FREE
    if boost_limit == 0:
        raise HTTPException(
            status_code=403,
            detail="İlan öne çıkarma yalnızca Pro hesaplara özeldir. Pro'ya geçerek ayda 20 boost hakkı kazanabilirsin.",
        )
    boost_used = await _get_boost_used(current_user.id)

    # Aylık ücretsiz hak kaldı mı?
    is_free = boost_used < boost_limit

    # Ücretli modda: TUCi bakiyesi yeterli mi?
    if not is_free:
        if current_user.tuci_balance < _BOOST_PAID_COST:
            raise HTTPException(
                status_code=402,
                detail=f"Bu ay {boost_limit} ücretsiz boost hakkını kullandın. Ücretli boost için {_BOOST_PAID_COST} TUCi gerekmekte, ancak bakiyeniz: {current_user.tuci_balance} TUCi.",
            )

    # İlanın bu kullanıcıya ait olduğunu doğrula
    listing = await db.scalar(
        select(Listing).where(
            Listing.id == body.listing_id,
            Listing.user_id == current_user.id,
            Listing.is_deleted == False,  # noqa: E712
        )
    )
    if not listing:
        raise HTTPException(status_code=404, detail="İlan bulunamadı veya size ait değil")

    campaign = AdCampaign(
        listing_id=body.listing_id,
        seller_id=current_user.id,
        total_budget=body.total_budget,
        spent_budget=0,
        cpc_bid=body.cpc_bid,
        status="active",
    )
    db.add(campaign)

    # TUCi düşme: yalnızca ücretli modda
    tuci_cost = 0
    if not is_free:
        tuci_cost = _BOOST_PAID_COST
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_boost_paid",
        ))

    await db.commit()
    await db.refresh(campaign)

    # Boost kredi sayacını artır (ücretsiz hak kullanıldıysa)
    if is_free:
        await _increment_boost(current_user.id)

    # Redis'e anında yükle — cron'u beklemeye gerek yok
    try:
        from app.services.ad_service import load_active_campaigns_to_redis
        await load_active_campaigns_to_redis()
    except Exception as exc:
        logger.warning("[Ads] Redis yükleme atlandı: %s", exc)

    logger.info(
        "[Ads] Yeni kampanya oluşturuldu | id=%d listing_id=%d seller_id=%d is_free=%s tuci_cost=%d",
        campaign.id, body.listing_id, current_user.id, is_free, tuci_cost,
    )
    return {
        "id": campaign.id,
        "listing_id": campaign.listing_id,
        "status": campaign.status,
        "total_budget": campaign.total_budget,
        "cpc_bid": campaign.cpc_bid,
        "is_free": is_free,
        "tuci_cost": tuci_cost,
    }


@router.get("/boost-credits")
async def boost_credits(current_user: User = Depends(get_current_user)):
    """Kullanıcının bu ayki boost kredi durumunu döndürür."""
    limit = _BOOST_LIMIT_PRO if current_user.is_premium else _BOOST_LIMIT_FREE
    used  = await _get_boost_used(current_user.id)
    return {
        "used": used,
        "limit": limit,
        "remaining": max(0, limit - used),
        "is_pro": current_user.is_premium,
    }


def _user_id_from_request(request: Request) -> int | None:
    """Authorization header'dan user_id çıkarır; yoksa None döner."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        try:
            return decode_token(auth.split(" ", 1)[1])
        except Exception:
            pass
    return None


# ── Tıklama ───────────────────────────────────────────────────────────────────

async def _log_click_to_clickhouse(campaign_id: int, user_id: int) -> None:
    """ClickHouse'a ad_click event'i yazar. BackgroundTask olarak çalışır."""
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        await ch.insert(
            "user_events",
            [[user_id, campaign_id, "ad_campaign", "ad_click", None, None, now]],
            column_names=[
                "user_id", "item_id", "item_type",
                "event_type", "price_point", "duration_seconds", "timestamp",
            ],
        )
    except Exception as exc:
        logger.warning("[Ads] ClickHouse click log başarısız | campaign=%d | %s", campaign_id, exc)


@router.post("/click/{campaign_id}", status_code=202)
async def record_click(campaign_id: int, request: Request, background_tasks: BackgroundTasks):
    """
    Kullanıcı sponsored ilana tıkladığında çağrılır.

    - ad_service.record_ad_click() → Redis'ten atomik bütçe düşer.
    - Bütçe tükenirse kampanya PostgreSQL'de 'completed' yapılır.
    - ClickHouse'a ad_click logu atılır (rapor için).
    """
    user_id = _user_id_from_request(request) or 0

    try:
        from app.services.ad_service import record_ad_click
        recorded = await record_ad_click(campaign_id, user_id)
        if recorded:
            background_tasks.add_task(_log_click_to_clickhouse, campaign_id, user_id)
        return {"recorded": recorded}
    except Exception as exc:
        logger.error("[Ads] click kaydı başarısız | campaign=%d | %s", campaign_id, exc)
        return {"recorded": False}


# ── Gösterim ──────────────────────────────────────────────────────────────────

async def _log_impression_to_clickhouse(
    campaign_id: int,
    user_id: int | None,
) -> None:
    """ClickHouse'a ad_impression event'i yazar. BackgroundTask olarak çalışır."""
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        await ch.insert(
            "user_events",
            [[user_id, campaign_id, "ad_campaign", "ad_impression", None, None, now]],
            column_names=[
                "user_id", "item_id", "item_type",
                "event_type", "price_point", "duration_seconds", "timestamp",
            ],
        )
    except Exception as exc:
        logger.warning("[Ads] ClickHouse impression log başarısız | campaign=%d | %s", campaign_id, exc)


@router.post("/impression/{campaign_id}", status_code=202)
async def record_impression(
    campaign_id: int,
    request: Request,
    background_tasks: BackgroundTasks,
):
    """
    Kullanıcı sponsored ilanı ekranda gördüğünde çağrılır.

    - Bütçe düşürmez; sadece istatistik kaydeder.
    - ClickHouse'a event_type='ad_impression' logu atılır.
    - BackgroundTasks ile response geciktirilmez.
    """
    user_id = _user_id_from_request(request)
    background_tasks.add_task(_log_impression_to_clickhouse, campaign_id, user_id)
    return {"status": "queued"}


# ── Sponsorlu İlanlar ────────────────────────────────────────────────────────

@router.get("/sponsored")
async def get_sponsored_listings(
    db: AsyncSession = Depends(get_db),
):
    """
    Aktif kampanyalardan sponsorlu ilanları döndürür.
    Web feed'ine enjekte etmek için kullanılır.
    """
    from app.services.feed_service import _get_sponsored_listings
    return await _get_sponsored_listings(db)


# ── Kampanya Performans Raporu ─────────────────────────────────────────────────

@router.get("/campaigns/{campaign_id}/report")
async def get_campaign_report(
    campaign_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcıya ait kampanyanın performans raporunu döndürür.

    PostgreSQL: bütçe, durum, cpc
    Redis:      gerçek zamanlı kalan bütçe (aktif kampanyalar için)
    ClickHouse: gösterim (ad_impression) + tıklama (ad_click) sayıları
    Hesaplama:  CTR = clicks / impressions × 100
    """
    campaign = await db.scalar(
        select(AdCampaign).where(
            AdCampaign.id == campaign_id,
            AdCampaign.seller_id == current_user.id,
        )
    )
    if not campaign:
        raise HTTPException(status_code=404, detail="Kampanya bulunamadı")

    # Redis: aktif kampanya için gerçek zamanlı kalan bütçe
    remaining_budget = max(0.0, campaign.total_budget - campaign.spent_budget)
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        budget_str = await redis.get(f"ad_campaign_budget:{campaign_id}")
        if budget_str is not None:
            remaining_budget = max(0.0, float(budget_str))
    except Exception as exc:
        logger.warning("[Ads] Redis bütçe okuması başarısız: %s", exc)

    actual_spent = round(max(0.0, campaign.total_budget - remaining_budget), 2)

    # ClickHouse: gösterim + tıklama sayıları + zengin metrikler
    impressions = 0
    clicks = 0
    daily_trend: list[dict] = []
    best_hour: int | None = None
    category_avg_ctr: float | None = None
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()

        # Toplam
        result = await ch.query(f"""
            SELECT
                countIf(event_type = 'ad_impression') AS impressions,
                countIf(event_type = 'ad_click')      AS clicks
            FROM user_events
            WHERE item_id    = {campaign_id}
              AND item_type  = 'ad_campaign'
        """)
        row = result.result_rows[0] if result.result_rows else (0, 0)
        impressions = int(row[0] or 0)
        clicks = int(row[1] or 0)

        # Günlük CTR trendi (son 30 gün)
        trend_result = await ch.query(f"""
            SELECT
                toDate(timestamp) AS day,
                countIf(event_type = 'ad_impression') AS impr,
                countIf(event_type = 'ad_click')      AS clks
            FROM user_events
            WHERE item_id   = {campaign_id}
              AND item_type = 'ad_campaign'
              AND timestamp >= now() - INTERVAL 30 DAY
            GROUP BY day
            ORDER BY day
        """)
        daily_trend = [
            {
                "day": str(r[0]),
                "impressions": int(r[1]),
                "clicks": int(r[2]),
                "ctr": round(int(r[2]) / max(int(r[1]), 1) * 100, 2),
            }
            for r in trend_result.result_rows
        ]

        # En iyi saat
        hour_result = await ch.query(f"""
            SELECT
                toHour(timestamp) AS hr,
                countIf(event_type = 'ad_impression') AS impr,
                countIf(event_type = 'ad_click')      AS clks
            FROM user_events
            WHERE item_id   = {campaign_id}
              AND item_type = 'ad_campaign'
            GROUP BY hr
            HAVING impr > 0
            ORDER BY (clks / impr) DESC
            LIMIT 1
        """)
        if hour_result.result_rows:
            best_hour = int(hour_result.result_rows[0][0])

    except Exception as exc:
        logger.warning("[Ads] ClickHouse rapor sorgusu başarısız: %s", exc)

    # Kategori ortalama CTR (PostgreSQL)
    try:
        cat_result = await db.execute(
            select(Listing.category)
            .where(Listing.id == campaign.listing_id)
        )
        listing_cat_row = cat_result.fetchone()
        if listing_cat_row and listing_cat_row[0]:
            cat_ctr_result = await db.execute(
                sql_text("""
                    SELECT
                        AVG(CASE WHEN ac.impressions > 0 THEN ac.clicks::float / ac.impressions ELSE 0 END) * 100
                    FROM ad_campaigns ac
                    INNER JOIN listings l ON l.id = ac.listing_id
                    WHERE l.category = :cat
                      AND ac.impressions > 0
                      AND ac.status IN ('active', 'ended')
                """),
                {"cat": listing_cat_row[0]},
            )
            cat_row = cat_ctr_result.fetchone()
            if cat_row and cat_row[0]:
                category_avg_ctr = round(float(cat_row[0]), 2)
    except Exception as exc:
        logger.warning("[Ads] Kategori CTR sorgusu başarısız: %s", exc)

    ctr = round(clicks / impressions * 100, 2) if impressions > 0 else 0.0

    # Bütçe tükenme hızı: günlük ortalama harcama ve tahmini kalan gün
    days_active = 0
    daily_spend = 0.0
    estimated_days_left: float | None = None
    if campaign.created_at:
        from datetime import datetime, timezone
        now_utc = datetime.now(timezone.utc)
        created = campaign.created_at
        if created.tzinfo is None:
            from datetime import timezone as tz
            created = created.replace(tzinfo=tz.utc)
        days_active = max(1, (now_utc - created).days)
        daily_spend = round(actual_spent / days_active, 2)
        if daily_spend > 0 and remaining_budget > 0:
            estimated_days_left = round(remaining_budget / daily_spend, 1)

    return {
        "campaign_id": campaign.id,
        "listing_id": campaign.listing_id,
        "status": campaign.status,
        "total_budget": campaign.total_budget,
        "spent_budget": actual_spent,
        "remaining_budget": round(remaining_budget, 2),
        "cpc_bid": campaign.cpc_bid,
        "impressions": impressions,
        "clicks": clicks,
        "ctr": ctr,
        "created_at": campaign.created_at.isoformat() if campaign.created_at else None,
        # Zengin metrikler
        "daily_trend": daily_trend,
        "best_hour": best_hour,
        "category_avg_ctr": category_avg_ctr,
        "daily_spend": daily_spend,
        "estimated_days_left": estimated_days_left,
    }
