"""
Reklam İzleme Endpointleri.

POST /api/ads/click/{campaign_id}      — tıklama → bütçe düşer
POST /api/ads/impression/{campaign_id} — gösterim → ClickHouse'a log
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Request

from app.utils.auth import bearer_scheme, decode_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ads", tags=["ads"])


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

@router.post("/click/{campaign_id}", status_code=202)
async def record_click(campaign_id: int, request: Request):
    """
    Kullanıcı sponsored ilana tıkladığında çağrılır.

    - ad_service.record_ad_click() → Redis'ten atomik bütçe düşer.
    - Bütçe tükenirse kampanya PostgreSQL'de 'completed' yapılır.
    - Fire-and-forget: 202 hemen döner, iş arka planda biter.
    """
    user_id = _user_id_from_request(request) or 0

    try:
        from app.services.ad_service import record_ad_click
        recorded = await record_ad_click(campaign_id, user_id)
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
