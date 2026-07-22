import asyncio
import calendar as _calendar
import logging
from datetime import datetime, timezone, date as _date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Query as FastApiQuery
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import text

from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.enums import ListingStatus
from app.models.listing import Listing
from app.models.mass_notification import MassNotificationCampaign
from app.models.tuci_transaction import TuciTransaction
from app.models.user import User
from app.utils.auth import get_current_user, get_current_user_optional, bearer_scheme, decode_token
from app.use_cases.listings.commands.create_listing import CreateListingCommand
from app.use_cases.listings.commands.update_listing import UpdateListingCommand
from app.use_cases.listings.commands.delete_listing import DeleteListingCommand
from app.use_cases.listings.commands.toggle_listing import ToggleListingCommand
from app.use_cases.listings.commands.create_offer import CreateListingOfferCommand
from app.use_cases.listings.queries.search_listings_query import SearchListingsQuery
from app.use_cases.listings.queries.get_my_listings import GetMyListingsQuery
from app.use_cases.listings.queries.get_listing import GetListingQuery
from app.use_cases.listings.queries.get_video_feed import GetVideoFeedQuery
from app.use_cases.listings.queries.get_swipe_feed import GetSwipeFeedQuery
from app.use_cases.listings.queries.get_listing_offers import GetListingOffersQuery
from app.use_cases.listings.queries.get_reactivation_cost import GetReactivationCostQuery
from app.use_cases.listings.queries.listing_utils import _parse_image_urls
from app.services.like_service import LikeService
from app.schemas.listing import ListingOfferCreate
from app.core.task_queue import get_pool
from app.core.rate_limit import limiter
from app.core.read_cache import cache_get, cache_set, invalidate_cache
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/listings", tags=["listings"])

# ── Opsiyonel token çözümleyici ─────────────────────────────────────────────
async def _optional_user_id(
    credentials=Depends(bearer_scheme),
) -> Optional[int]:
    if not credentials:
        return None
    return decode_token(credentials.credentials)


@router.get("")
async def get_listings(
    request: Request,
    user_id: Optional[int] = None,
    category: Optional[str] = None,
    location: Optional[str] = None,
    q: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    if user_id and current_user and user_id == current_user.id:
        active_str = request.query_params.get("active")
        is_active = (active_str.lower() == "true") if active_str else None
        return await GetMyListingsQuery(uow).execute(
            current_user=current_user,
            active=is_active,
            q=q,
            category=category,
            limit=limit,
            offset=offset,
            start_date=start_date,
            end_date=end_date,
        )
    else:
        return await SearchListingsQuery().execute(
            db_session=uow.session,
            user_id=user_id,
            category=category,
            location=location,
            q=q,
            limit=limit,
            offset=offset,
            current_user_id=current_user.id if current_user else None,
        )


@router.get("/video-feed")
async def get_video_feed(
    limit: int = 8,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetVideoFeedQuery(uow).execute(limit=limit)


@router.get("/swipe-feed")
async def get_swipe_feed(
    limit: int = 10,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetSwipeFeedQuery(uow).execute(limit=limit)


@router.get("/my")
async def get_my_listings(
    request: Request,
    active: Optional[str] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
    limit: int = 1000,
    offset: int = 0,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    is_active = (active.lower() == "true") if active else None
    return await GetMyListingsQuery(uow).execute(
        current_user=current_user,
        active=is_active,
        q=q,
        category=category,
        limit=limit,
        offset=offset,
        start_date=start_date,
        end_date=end_date,
    )


@router.get("/{listing_id:int}")
async def get_listing(
    request: Request,
    listing_id: int,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    ip_address = request.client.host if request.client else None
    return await GetListingQuery(uow).execute(listing_id, current_user_id, ip_address=ip_address)


@router.post("")
@limiter.limit("20/minute")
async def create_listing(
    request: Request,
    payload: dict,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    result = await CreateListingCommand(uow).execute(
        user_id=current_user.id,
        title=payload.get("title", ""),
        description=payload.get("description"),
        price=payload.get("price"),
        category=payload.get("category", "diger"),
        condition=payload.get("condition"),
        location=payload.get("location"),
        image_url=payload.get("image_url"),
        image_urls=payload.get("image_urls"),
        thumbnail_url=payload.get("thumbnail_url"),
        video_url=payload.get("video_url"),
    )

    pool = get_pool()
    if pool:
        await pool.enqueue_job("generate_listing_embedding_task", result["id"])
    await invalidate_cache("listings:search")
    return result


@router.put("/{listing_id}")
async def update_listing(
    listing_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    result = await UpdateListingCommand(uow).execute(
        listing_id=listing_id,
        user_id=current_user.id,
        title=payload.get("title"),
        description=payload.get("description"),
        price=payload.get("price"),
    )
    await invalidate_cache("listings:search")
    return result


@router.get("/{listing_id}/reactivation-cost")
async def reactivation_cost(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetReactivationCostQuery(uow).execute(listing_id, current_user)


@router.patch("/{listing_id}/toggle")
async def toggle_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await ToggleListingCommand(uow).execute(listing_id, current_user)


@router.delete("/{listing_id}")
async def delete_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await DeleteListingCommand(uow).execute(listing_id=listing_id, user_id=current_user.id)


@router.post("/{listing_id}/offers")
async def create_offer(
    listing_id: int,
    payload: ListingOfferCreate,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await CreateListingOfferCommand(uow).execute(listing_id, current_user, payload.amount)


@router.post("/{listing_id}/view", status_code=204)
async def record_listing_view(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Doğrudan raw SQL impression kaydı — UoW gerektirmez
    await db.execute(
        text("""
            INSERT INTO listing_impressions (user_id, listing_id)
            VALUES (:uid, :lid)
            ON CONFLICT DO NOTHING
        """),
        {"uid": current_user.id, "lid": listing_id},
    )
    await db.commit()


@router.post("/{listing_id}/like")
async def toggle_listing_like(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    from app.use_cases.listings.commands.like_listing import LikeListingCommand
    return await LikeListingCommand(uow).execute(listing_id, current_user.id)


@router.get("/{listing_id}/offers")
async def get_listing_offers(
    listing_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetListingOffersQuery(uow).execute(listing_id)


# ── Similar Listings ──────────────────────────────────────────────────────────

@router.get("/{listing_id}/similar")
async def similar_listings(
    listing_id: int,
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import case as sa_case
    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id)
    )
    if not listing:
        return []
    result = await db.execute(
        select(Listing)
        .where(
            Listing.id != listing_id,
            Listing.category == listing.category,
            Listing.status == ListingStatus.ACTIVE,
        )
        .order_by(
            # Aynı condition → önce göster; condition yoksa nötr
            sa_case(
                (Listing.condition == listing.condition, 0),
                else_=1,
            ),
            Listing.created_at.desc(),
        )
        .limit(limit)
    )
    items = result.scalars().all()
    return [
        {
            "id": item.id,
            "title": item.title,
            "price": item.price,
            "image_url": item.image_url,
            "image_urls": _parse_image_urls(item.image_urls),
            "thumbnail_url": item.thumbnail_url,
            "category": item.category,
            "condition": item.condition,
            "location": item.location,
            "status": item.status.value if hasattr(item.status, "value") else str(item.status),
        }
        for item in items
    ]


# ── Notification Cooldown ─────────────────────────────────────────────────────

_BLAST_COOLDOWN_SECS = 86400  # 24 saat


@router.get("/{listing_id}/notification-cooldown")
async def notification_cooldown(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    last_sent = await db.scalar(
        select(MassNotificationCampaign.created_at)
        .where(
            MassNotificationCampaign.listing_id == listing_id,
            MassNotificationCampaign.user_id == current_user.id,
        )
        .order_by(MassNotificationCampaign.created_at.desc())
        .limit(1)
    )
    if last_sent:
        aware = last_sent.replace(tzinfo=timezone.utc) if last_sent.tzinfo is None else last_sent
        elapsed = int((datetime.now(timezone.utc) - aware).total_seconds())
        remaining = max(0, _BLAST_COOLDOWN_SECS - elapsed)
        return {"seconds_remaining": remaining}
    return {"seconds_remaining": 0}


# ── Audience Estimate ─────────────────────────────────────────────────────────

async def _build_listing_audience(
    listing_id: int,
    listing_category: str,
    owner_id: int,
    db: AsyncSession,
    cap: int = 500,
) -> list[int]:
    """
    İlan için potansiyel hedef kitleyi iki sinyalden oluşturur:
    1. Doğrudan görüntüleyenler  — ClickHouse user_events → listing_impressions fallback
    2. Kategori ilgisi olanlar   — user_interests WHERE category = listing.category AND score >= 0.3

    İkisi birleştirilip (union) owner_id filtresi uygulanır.
    """
    audience: set[int] = set()

    # ── Sinyal 1: Doğrudan görüntüleyenler ───────────────────────────────────
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        vid_result = await ch.query("""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_id = %(lid)s
              AND event_type IN ('view', 'dwell', 'detail_dwell', 'click')
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id != %(uid)s
              AND user_id != 0
            LIMIT 500
        """, parameters={"lid": listing_id, "uid": owner_id})
        audience.update(int(r[0]) for r in vid_result.result_rows)
    except Exception as exc:
        logging.getLogger(__name__).warning("[AudienceEstimate] ClickHouse başarısız: %s", exc)
        # ClickHouse yoksa listing_impressions'dan doğrudan görüntüleyenleri al
        rows = await db.execute(
            text("SELECT DISTINCT user_id FROM listing_impressions WHERE listing_id = :lid AND user_id != :uid LIMIT 500"),
            {"lid": listing_id, "uid": owner_id},
        )
        audience.update(r[0] for r in rows.fetchall())

    # ── Sinyal 2: Kategori ilgisi olan potansiyel kullanıcılar ───────────────
    # user_interests: bu kategoriyle ilgilenen (score >= 0.3) kullanıcılar
    try:
        interest_rows = await db.execute(
            text("""
                SELECT DISTINCT user_id
                FROM user_interests
                WHERE category = :cat
                  AND score >= 0.3
                  AND user_id != :uid
                LIMIT :lim
            """),
            {"cat": listing_category, "uid": owner_id, "lim": cap},
        )
        audience.update(r[0] for r in interest_rows.fetchall())
    except Exception as exc:
        logging.getLogger(__name__).warning("[AudienceEstimate] user_interests sorgusu başarısız: %s", exc)

    return list(audience)[:cap]


@router.get("/{listing_id}/audience-estimate")
async def audience_estimate(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.routers.leads import (
        _get_blast_used,
        _PER_BLAST_CAP_PRO, _PER_BLAST_CAP_STANDARD,
        _BLAST_LIMIT_PRO, _BLAST_LIMIT_STANDARD,
        COST_PER_PERSON,
    )

    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise HTTPException(404, "İlan bulunamadı")
    if listing.status != ListingStatus.ACTIVE:
        raise HTTPException(422, detail={"code": "LISTING_NOT_ACTIVE", "status": listing.status.value})

    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    used  = await _get_blast_used(current_user.id, current_user.premium_since)
    credits_remaining = max(0, limit - used)

    candidate_ids = await _build_listing_audience(
        listing_id=listing_id,
        listing_category=listing.category or "",
        owner_id=current_user.id,
        db=db,
    )

    reachable = 0
    if candidate_ids:
        token_count = await db.scalar(text("""
            SELECT COUNT(*) FROM users
            WHERE id = ANY(:ids)
              AND fcm_token IS NOT NULL AND fcm_token != ''
              AND id NOT IN (SELECT follower_id FROM follows WHERE followed_id = :me)
        """), {"ids": candidate_ids, "me": current_user.id})
        reachable = int(token_count or 0)

    actual_cap     = min(reachable, cap)
    free_used      = min(credits_remaining, actual_cap)
    paid_count     = actual_cap - free_used
    estimated_cost = paid_count * COST_PER_PERSON

    return {
        "audience_size":           reachable,
        "blast_credits_remaining": credits_remaining,
        "per_blast_cap":           cap,
        "tuci_balance":            current_user.tuci_balance,
        "estimated_cost":          estimated_cost,
    }


# ── AI Listing Description — TUCi & PRO krediler ─────────────────────────────

AI_DESC_COST      = 5   # TUCi (standart kullanıcılar ve PRO limit aşınca)
AI_DESC_LIMIT_PRO = 6   # PRO kullanıcılar ayda 6 ücretsiz sorgu


def _ai_desc_billing_start(premium_since: datetime) -> _date:
    """PRO fatura dönemi başlangıcı (premium_since günü, her ay)."""
    today = _date.today()
    day = premium_since.day
    if today.day >= day:
        return _date(today.year, today.month, min(day, _calendar.monthrange(today.year, today.month)[1]))
    if today.month == 1:
        return _date(today.year - 1, 12, min(day, 31))
    pm = today.month - 1
    return _date(today.year, pm, min(day, _calendar.monthrange(today.year, pm)[1]))


def _ai_desc_next_billing(premium_since: datetime) -> _date:
    """Bir sonraki PRO fatura tarihi."""
    p = _ai_desc_billing_start(premium_since)
    nm = p.month + 1 if p.month < 12 else 1
    ny = p.year if p.month < 12 else p.year + 1
    return _date(ny, nm, min(p.day, _calendar.monthrange(ny, nm)[1]))


def _ai_desc_redis_key(user_id: int, premium_since: datetime | None = None) -> str:
    if premium_since:
        period = _ai_desc_billing_start(premium_since)
        return f"ai_desc_credits:{user_id}:{period.isoformat()}"
    month = datetime.now().strftime("%Y-%m")
    return f"ai_desc_credits:{user_id}:{month}"


async def _get_ai_desc_used(user_id: int, premium_since: datetime | None = None) -> int:
    try:
        redis = await get_redis()
        val = await redis.get(_ai_desc_redis_key(user_id, premium_since))
        return int(val) if val else 0
    except Exception:
        return 0


async def _increment_ai_desc_atomic(user_id: int, premium_since: datetime | None = None) -> int:
    try:
        redis = await get_redis()
        key   = _ai_desc_redis_key(user_id, premium_since)
        count = await redis.incr(key)
        if count == 1:
            now = datetime.now()
            if premium_since:
                nxt    = _ai_desc_next_billing(premium_since)
                end_dt = datetime(nxt.year, nxt.month, nxt.day)
            else:
                last_day = _calendar.monthrange(now.year, now.month)[1]
                end_dt   = datetime(now.year, now.month, last_day, 23, 59, 59)
            await redis.expire(key, int((end_dt - now).total_seconds()) + 1)
        return count
    except Exception:
        return 0


# ── AI Listing Description ────────────────────────────────────────────────────

class GenerateDescriptionRequest(BaseModel):
    title: str = Field(..., min_length=2, max_length=200)
    category: str = Field(..., min_length=1, max_length=50)
    condition: Optional[str] = Field(default=None)
    price: Optional[float] = Field(default=None, ge=0)
    location: Optional[str] = Field(default=None)


@router.get("/ai-desc-credits")
async def ai_desc_credits(current_user: User = Depends(get_current_user)):
    """PRO kullanıcının bu ayki AI açıklama yazarı kredi durumunu döndürür."""
    if not current_user.is_premium:
        return {"used": 0, "limit": 0, "remaining": 0, "is_premium": False, "renewal_date": None}
    used = await _get_ai_desc_used(current_user.id, current_user.premium_since)
    remaining = max(0, AI_DESC_LIMIT_PRO - used)
    renewal_date: str | None = None
    if current_user.premium_since:
        renewal_date = _ai_desc_next_billing(current_user.premium_since).isoformat()
    return {
        "used": used,
        "limit": AI_DESC_LIMIT_PRO,
        "remaining": remaining,
        "is_premium": True,
        "renewal_date": renewal_date,
    }


from fastapi.responses import StreamingResponse
import json
from app.services.ml.llm_service import generate_listing_description_stream

@router.post("/generate-description")
@limiter.limit("10/minute")
async def generate_description(
    request: Request,
    body: GenerateDescriptionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Ollama (Qwen2.5:3b) ile ilan açıklaması üretir ve metni stream eder (SSE).
    PRO: ayda 6 ücretsiz, sonrası 5 TUCi. Standart: her seferinde 5 TUCi.
    """
    logger.info(f"[API] /generate-description called by user_id={current_user.id} | title='{body.title}'")
    # ── TUCi / PRO kredi ön kontrolü ──────────────────────────────────────────
    if current_user.is_premium:
        ai_used = await _get_ai_desc_used(current_user.id, current_user.premium_since)
        if ai_used >= AI_DESC_LIMIT_PRO and current_user.tuci_balance < AI_DESC_COST:
            logger.warning(f"[API] User {current_user.id} has insufficient TUCi (PRO limit reached).")
            raise HTTPException(
                status_code=402,
                detail="INSUFFICIENT_FUNDS_PRO",
            )
    else:
        if current_user.tuci_balance < AI_DESC_COST:
            logger.warning(f"[API] User {current_user.id} has insufficient TUCi.")
            raise HTTPException(
                status_code=402,
                detail="INSUFFICIENT_FUNDS_STD",
            )

    async def event_generator():
        logger.info(f"[API] event_generator started for user_id={current_user.id}")
        text_generated = False
        queue = asyncio.Queue()

        async def producer():
            try:
                async for chunk in generate_listing_description_stream(
                    title=body.title,
                    category=body.category,
                    condition=body.condition,
                    price=body.price,
                    location=body.location,
                ):
                    await queue.put({"type": "chunk", "data": chunk})
                await queue.put({"type": "done"})
            except Exception as e:
                await queue.put({"type": "error", "error": e})

        producer_task = asyncio.create_task(producer())

        try:
            while True:
                try:
                    # Nginx proxy_read_timeout is usually 60s. We send a ping every 15s.
                    msg = await asyncio.wait_for(queue.get(), timeout=15.0)
                except asyncio.TimeoutError:
                    yield f"data: {json.dumps({'keep_alive': True})}\n\n"
                    continue

                if msg["type"] == "done":
                    break
                elif msg["type"] == "error":
                    raise msg["error"]
                elif msg["type"] == "chunk":
                    chunk = msg["data"]
                    if not text_generated:
                        logger.info(f"[API] First chunk received from Ollama for user_id={current_user.id}")
                    text_generated = True
                    yield f"data: {json.dumps({'text': chunk}, ensure_ascii=False)}\n\n"
            
            if text_generated:
                logger.info(f"[API] Stream finished for user_id={current_user.id}. Charging TUCi...")
                # Üretim bittikten sonra TUCi kesintisi yap
                tuci_spent = 0
                if current_user.is_premium:
                    ai_used_new = await _increment_ai_desc_atomic(current_user.id, current_user.premium_since)
                    if ai_used_new > AI_DESC_LIMIT_PRO:
                        await db.execute(
                            text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                            {"cost": AI_DESC_COST, "uid": current_user.id},
                        )
                        db.add(TuciTransaction(user_id=current_user.id, amount=-AI_DESC_COST, transaction_type="spend_ai"))
                        await db.commit()
                        tuci_spent = AI_DESC_COST
                else:
                    await db.execute(
                        text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                        {"cost": AI_DESC_COST, "uid": current_user.id},
                    )
                    db.add(TuciTransaction(user_id=current_user.id, amount=-AI_DESC_COST, transaction_type="spend_ai"))
                    await db.commit()
                    tuci_spent = AI_DESC_COST
                
                # Bitiş sinyali ve harcanan TUCi
                yield f"data: {json.dumps({'done': True, 'tuci_spent': tuci_spent}, ensure_ascii=False)}\n\n"
        except Exception as e:
            logger.error(f"[LLM] Stream generator error: {e}")
            yield f"data: {json.dumps({'error': 'AI_SERVICE_ERROR'}, ensure_ascii=False)}\n\n"
        finally:
            producer_task.cancel()

    return StreamingResponse(event_generator(), media_type="text/event-stream")


# ── Send Mass Notification ────────────────────────────────────────────────────

class MassNotificationRequest(BaseModel):
    estimated_cost: int = Field(default=0, ge=0)
    recipient_count: int | None = Field(default=None, ge=1)


@router.post("/{listing_id}/send-mass-notification", status_code=202)
async def send_mass_notification(
    listing_id: int,
    body: MassNotificationRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.routers.leads import (
        _get_blast_used, _increment_blast,
        _PER_BLAST_CAP_PRO, _PER_BLAST_CAP_STANDARD,
        _BLAST_LIMIT_PRO, _BLAST_LIMIT_STANDARD,
        COST_PER_PERSON,
    )

    # Cooldown kontrolü
    last_sent = await db.scalar(
        select(MassNotificationCampaign.created_at)
        .where(
            MassNotificationCampaign.listing_id == listing_id,
            MassNotificationCampaign.user_id == current_user.id,
        )
        .order_by(MassNotificationCampaign.created_at.desc())
        .limit(1)
    )
    if last_sent:
        aware = last_sent.replace(tzinfo=timezone.utc) if last_sent.tzinfo is None else last_sent
        elapsed = int((datetime.now(timezone.utc) - aware).total_seconds())
        remaining = max(0, _BLAST_COOLDOWN_SECS - elapsed)
        if remaining > 0:
            raise HTTPException(429, detail={"code": "cooldown", "seconds_remaining": remaining})

    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id, Listing.user_id == current_user.id)
    )
    if not listing:
        raise HTTPException(404, "İlan bulunamadı")
    if listing.status != ListingStatus.ACTIVE:
        raise HTTPException(422, detail={"code": "LISTING_NOT_ACTIVE", "status": listing.status.value})

    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    used  = await _get_blast_used(current_user.id, current_user.premium_since)
    credits_remaining = max(0, limit - used)

    desired = body.recipient_count or cap
    max_paid_authorized = body.estimated_cost // COST_PER_PERSON
    actual_count = min(desired, credits_remaining + max_paid_authorized, cap)
    free_used    = min(credits_remaining, actual_count)
    paid_count   = actual_count - free_used
    tuci_cost    = paid_count * COST_PER_PERSON

    if tuci_cost > 0 and current_user.tuci_balance < tuci_cost:
        raise HTTPException(402, f"Yetersiz TUCi bakiyesi. Mevcut: {current_user.tuci_balance}, Gerekli: {tuci_cost}")

    # Hedef kitleyi oluştur: doğrudan görüntüleyenler + kategori ilgisi olanlar
    candidate_ids = await _build_listing_audience(
        listing_id=listing_id,
        listing_category=listing.category or "",
        owner_id=current_user.id,
        db=db,
        cap=min(cap * 3, 1500),
    )

    if not candidate_ids:
        return {"sent": 0, "spent": 0, "message": "Henüz yeterli kitle verisi yok."}

    token_rows = (await db.execute(text("""
        SELECT fcm_token FROM users
        WHERE id = ANY(:ids)
          AND fcm_token IS NOT NULL AND fcm_token != ''
          AND id NOT IN (SELECT follower_id FROM follows WHERE followed_id = :me)
        LIMIT :cap
    """), {"ids": candidate_ids, "me": current_user.id, "cap": actual_count})).fetchall()
    fcm_tokens = [r[0] for r in token_rows]

    if not fcm_tokens:
        return {"sent": 0, "spent": 0, "message": "Bildirim gönderilebilecek kullanıcı bulunamadı."}

    from app.services.firebase_service import send_push, InvalidFCMTokenError

    async def _send_one(token: str) -> None:
        try:
            await send_push(
                token=token,
                title="Hâlâ ilgilendin mi? 👀",
                body=f"{listing.title} — hâlâ satışta!",
                data={"type": "new_listing", "listing_id": str(listing_id)},
                extra_data={"url": f"/listing/{listing_id}"},
            )
        except InvalidFCMTokenError:
            pass
        except Exception as exc:
            logging.getLogger(__name__).warning("[MassNotif] Push başarısız: %s", exc)

    sent = 0
    for i in range(0, len(fcm_tokens), 50):
        chunk = fcm_tokens[i: i + 50]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)

    # Kampanya kaydı
    campaign = MassNotificationCampaign(
        user_id=current_user.id,
        listing_id=listing_id,
        target_count=len(fcm_tokens),
        sent_count=sent,
        spent_tuci=tuci_cost,
        spent_free_credits=free_used,
    )
    db.add(campaign)

    if tuci_cost > 0:
        await db.execute(
            text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
            {"cost": tuci_cost, "uid": current_user.id},
        )
        db.add(TuciTransaction(
            user_id=current_user.id,
            amount=-tuci_cost,
            transaction_type="spend_mass_notification",
            reference_id=listing_id,
            reference_type="listing",
        ))

    await db.commit()

    if free_used > 0:
        await _increment_blast(current_user.id, count=free_used, premium_since=current_user.premium_since)

    logging.getLogger(__name__).info(
        "[MassNotif] Gönderildi | seller=%d | listing=%d | sent=%d | free=%d | paid=%d | cost=%d TUCi",
        current_user.id, listing_id, sent, free_used, paid_count, tuci_cost,
    )

    return {"sent": sent, "spent": tuci_cost, "message": f"{sent} kişiye bildirim gönderildi."}
