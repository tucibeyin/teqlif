"""
Reklam Ağı Endpointleri.

POST /api/ads/campaigns               — kampanya oluştur (satıcı)
POST /api/ads/click/{campaign_id}     — tıklama → bütçe düşer
POST /api/ads/impression/{campaign_id} — gösterim → ClickHouse'a log
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from sqlalchemy import text as sql_text

from app.models.enums import ListingStatus
from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.core.exceptions import ForbiddenException, InsufficientFundsException, NotFoundException, ConflictException
from app.services import credit_service
from app.models.ad_campaign import AdCampaign
from app.models.listing import Listing
from app.models.tuci_transaction import TuciTransaction
from app.models.user import User
from app.utils.auth import bearer_scheme, decode_token, get_current_user
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ads", tags=["ads"])

# ── Şemalar ───────────────────────────────────────────────────────────────────

class CampaignCreate(BaseModel):
    listing_id: int
    total_budget: int = Field(gt=0)
    cpc_bid: int = Field(gt=0)


# ── Kampanya Oluştur ──────────────────────────────────────────────────────────

@router.post("/campaigns", status_code=201)
async def create_campaign(
    body: CampaignCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcı kendi ilanı için reklam kampanyası başlatır.

    - Pro kullanıcılar ayda 3 boost hakkına sahiptir (ücretsiz).
    - Aylık hak biterse TUCi bakiyesinden 50 TUCi düşürülerek boost yapılır.
    - Ücretsiz hesaplar boost yapamaz.
    - İlanın sahibi olduğu doğrulanır.
    - AdCampaign kaydı oluşturulur (status='active').
    - Redis bütçe engine'ine yüklenir (anında aktif hale gelir).
    """
    # Aylık boost kredi kontrolü
    boost_limit = credit_service.free_limit("boost", current_user.is_premium)
    if boost_limit == 0:
        raise ForbiddenException(
            "İlan öne çıkarma yalnızca Pro hesaplara özeldir.",
            code="PRO_REQUIRED",
        )
    boost_used = await credit_service.get_used("boost", current_user.id, current_user.premium_since)

    # Aylık ücretsiz hak kaldı mı?
    is_free = boost_used < boost_limit

    # Ücretli modda: TUCi bakiyesi yeterli mi?
    if not is_free:
        if current_user.tuci_balance < credit_service.cost_tuci("boost"):
            raise InsufficientFundsException("Bu ay ücretsiz boost hakkınız doldu ve yeterli TUCi bakiyeniz yok.")

    # İlanın bu kullanıcıya ait olduğunu doğrula
    listing = await db.scalar(
        select(Listing).where(
            Listing.id == body.listing_id,
            Listing.user_id == current_user.id,
            Listing.status != ListingStatus.DELETED,  # noqa: E712
        )
    )
    if not listing:
        raise NotFoundException("İlan bulunamadı veya size ait değil.")

    # Zaten aktif/duraklatılmış bir kampanya varsa ikinci kampanya açılamaz
    existing = await db.scalar(
        select(AdCampaign.id).where(
            AdCampaign.listing_id == body.listing_id,
            AdCampaign.status.in_(["active", "paused"]),
        )
    )
    if existing:
        raise ConflictException("Bu ilan için zaten aktif bir kampanya var.")

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
        tuci_cost = credit_service.cost_tuci("boost")
        await db.execute(
            sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_boost_paid",
            reference_id=body.listing_id,
            reference_type="listing",
        ))
    else:
        # PRO ücretsiz boost hakkı kullanıldı — işlem geçmişine kaydet
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=0,
            transaction_type="spend_boost",
            reference_id=body.listing_id,
            reference_type="listing",
        ))

    await db.commit()
    await db.refresh(campaign)

    # Boost kredi sayacını artır (ücretsiz hak kullanıldıysa)
    if is_free:
        await credit_service.increment("boost", current_user.id, current_user.premium_since)

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
    limit = credit_service.free_limit("boost", current_user.is_premium)
    used  = await credit_service.get_used("boost", current_user.id, current_user.premium_since)
    renewal_date: str | None = None
    if current_user.premium_since:
        renewal_date = credit_service.next_billing_date(current_user.premium_since).isoformat()
    return {
        "used": used,
        "limit": limit,
        "remaining": max(0, limit - used),
        "is_pro": current_user.is_premium,
        "renewal_date": renewal_date,
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
    """ad_click event'ini Redis buffer'a ekler."""
    from app.database_clickhouse import buffer_user_event
    await buffer_user_event(
        event_type="ad_click",
        item_id=campaign_id,
        item_type="ad_campaign",
        user_id=user_id,
    )


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
    """ad_impression event'ini Redis buffer'a ekler."""
    from app.database_clickhouse import buffer_user_event
    await buffer_user_event(
        event_type="ad_impression",
        item_id=campaign_id,
        item_type="ad_campaign",
        user_id=user_id,
    )


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
    - Redis'te ad_freq:{user_id}:{campaign_id} sayacını artırır (frekans kısıtı için).
    """
    user_id = _user_id_from_request(request)

    if user_id:
        try:
            from app.utils.redis_client import get_redis as _get_redis
            _redis = await _get_redis()
            freq_key = f"ad_freq:{user_id}:{campaign_id}"
            count = await _redis.incr(freq_key)
            if count == 1:
                await _redis.expire(freq_key, 86400)  # 24 saat TTL ilk artışta set edilir
        except Exception as exc:
            logger.warning("[Ads] Frekans sayacı yazılamadı | campaign=%d | %s", campaign_id, exc)

    background_tasks.add_task(_log_impression_to_clickhouse, campaign_id, user_id)
    return {"status": "queued"}


# ── Sponsorlu İlanlar ────────────────────────────────────────────────────────

@router.get("/sponsored")
async def get_sponsored_listings(
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    """
    Aktif kampanyalardan sponsorlu ilanları döndürür.
    Web feed'ine enjekte etmek için kullanılır.
    """
    from app.use_cases.feed.queries.feed_queries import FeedQueries
    return await FeedQueries(uow)._get_sponsored_listings()


# ── Kampanya Performans Raporu ─────────────────────────────────────────────────

@router.get("/campaigns/{campaign_id}/report")
async def get_campaign_report(
    request: Request,
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
        raise NotFoundException("Kampanya bulunamadı.")

    # Redis: aktif kampanya için gerçek zamanlı kalan bütçe
    remaining_budget = max(0.0, campaign.total_budget - campaign.spent_budget)
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        budget_str = await redis.get(f"ad_campaign_budget:{campaign_id}")
        if budget_str is not None:
            remaining_budget = max(0.0, float(budget_str))
    except Exception as exc:
        client = f"{request.client.host}:{request.client.port}" if request.client else "unknown:0"
        logger.error(f'[Ads] Redis bütçe okuması başarısız: {client} - "{request.method} {request.url.path} HTTP/1.1" 500 Internal Server Error - {exc}')

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
        client = f"{request.client.host}:{request.client.port}" if request.client else "unknown:0"
        logger.error(f'[Ads] ClickHouse rapor sorgusu başarısız: {client} - "{request.method} {request.url.path} HTTP/1.1" 500 Internal Server Error - {exc}')

    # Kategori ortalama CTR (PostgreSQL + ClickHouse)
    try:
        # 1. PostgreSQL'den ilanın kategorisini bul
        cat_result = await db.execute(
            select(Listing.category)
            .where(Listing.id == campaign.listing_id)
        )
        listing_cat_row = cat_result.fetchone()
        
        if listing_cat_row and listing_cat_row[0]:
            category_name = listing_cat_row[0]
            
            # 2. Bu kategoriye ait aktif veya bitmiş tüm kampanyaların ID'lerini çek
            campaigns_query = await db.execute(
                sql_text("""
                    SELECT ac.id 
                    FROM ad_campaigns ac
                    INNER JOIN listings l ON l.id = ac.listing_id
                    WHERE l.category = :cat
                      AND ac.status IN ('active', 'ended')
                """),
                {"cat": category_name},
            )
            cat_campaign_ids = [row[0] for row in campaigns_query.fetchall()]
            
            # 3. Eğer bu kategoride reklamı yapılan kampanya varsa, CTR'ı ClickHouse'dan hesapla
            if cat_campaign_ids:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                
                # ID'leri SQL IN formatına uygun hale getir (ör: "1,2,3")
                id_list = ",".join(map(str, cat_campaign_ids))
                
                # ClickHouse üzerinden bu kampanyaların ortalama CTR'ını al
                cat_ctr_result = await ch.query(f"""
                    SELECT 
                        AVG(
                            CASE WHEN impr > 0 THEN clks / impr ELSE 0 END
                        ) * 100 AS avg_ctr
                    FROM (
                        SELECT 
                            item_id,
                            countIf(event_type = 'ad_impression') AS impr,
                            countIf(event_type = 'ad_click') AS clks
                        FROM user_events
                        WHERE item_id IN ({id_list})
                          AND item_type = 'ad_campaign'
                        GROUP BY item_id
                    )
                    WHERE impr > 0
                """)
                
                if cat_ctr_result.result_rows and cat_ctr_result.result_rows[0][0] is not None:
                    category_avg_ctr = round(float(cat_ctr_result.result_rows[0][0]), 2)
                    
    except Exception as exc:
        client = f"{request.client.host}:{request.client.port}" if request.client else "unknown:0"
        logger.error(f'[Ads] Kategori CTR sorgusu başarısız: {client} - "{request.method} {request.url.path} HTTP/1.1" 500 Internal Server Error - {exc}')

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
