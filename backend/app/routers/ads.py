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

from app.database import get_db
from app.models.ad_campaign import AdCampaign
from app.models.listing import Listing
from app.models.user import User
from app.utils.auth import bearer_scheme, decode_token, get_current_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ads", tags=["ads"])


# ── Şemalar ───────────────────────────────────────────────────────────────────

class CampaignCreate(BaseModel):
    listing_id: int
    total_budget: float = Field(gt=0)
    cpc_bid: float = Field(gt=0)


# ── Kampanya Oluştur ──────────────────────────────────────────────────────────

@router.post("/campaigns", status_code=201)
async def create_campaign(
    body: CampaignCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Satıcı kendi ilanı için reklam kampanyası başlatır.

    - İlanın sahibi olduğu doğrulanır.
    - AdCampaign kaydı oluşturulur (status='active').
    - Redis bütçe engine'ine yüklenir (anında aktif hale gelir).
    """
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
        spent_budget=0.0,
        cpc_bid=body.cpc_bid,
        status="active",
    )
    db.add(campaign)
    await db.commit()
    await db.refresh(campaign)

    # Redis'e anında yükle — cron'u beklemeye gerek yok
    try:
        from app.services.ad_service import load_active_campaigns_to_redis
        await load_active_campaigns_to_redis()
    except Exception as exc:
        logger.warning("[Ads] Redis yükleme atlandı: %s", exc)

    logger.info(
        "[Ads] Yeni kampanya oluşturuldu | id=%d listing_id=%d seller_id=%d budget=%.2f",
        campaign.id, body.listing_id, current_user.id, body.total_budget,
    )
    return {
        "id": campaign.id,
        "listing_id": campaign.listing_id,
        "status": campaign.status,
        "total_budget": campaign.total_budget,
        "cpc_bid": campaign.cpc_bid,
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

    # ClickHouse: gösterim + tıklama sayıları
    impressions = 0
    clicks = 0
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
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
    except Exception as exc:
        logger.warning("[Ads] ClickHouse rapor sorgusu başarısız: %s", exc)

    ctr = round(clicks / impressions * 100, 2) if impressions > 0 else 0.0

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
    }
