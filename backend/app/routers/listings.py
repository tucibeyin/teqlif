"""
İlan router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db, captcha) alır
  2. ListingService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, DB sorguları ve bildirimler tamamen
app.services.listing_service.ListingService'e taşınmıştır.
"""
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi_cache.decorator import cache

from app.models.enums import ListingStatus
from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.use_cases.listings.commands.create_listing import CreateListingCommand
from app.use_cases.listings.commands.update_listing import UpdateListingCommand
from app.use_cases.listings.commands.delete_listing import DeleteListingCommand
from app.use_cases.listings.queries.search_listings_query import SearchListingsQuery
from app.core.uow import SqlAlchemyUnitOfWork
from app.services.listing_service import (
    ListingService,
    _get_reactivation_used,
    _reactivation_next_billing,
    _REACTIVATION_FREE_MONTHLY,
    _REACTIVATION_COST_TUCI,
)
from app.services.like_service import LikeService
from app.schemas.listing import ListingOfferCreate
from app.core.task_queue import get_pool
from app.core.rate_limit import limiter
from app.core.read_cache import cache_get, cache_set, invalidate_cache

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
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    # CQRS cache-aside: kişiselleştirilmemiş (anonim) sorgular cache'lenir
    # Giriş yapmış kullanıcıya özel sorgular (user_id filtresi) cache atlanır
    use_cache = current_user_id is None and user_id is None
    params = {"category": category, "location": location, "q": q, "limit": limit, "offset": offset}
    if use_cache:
        cached = await cache_get("listings:search", params)
        if cached is not None:
            return cached
            
    query_uc = SearchListingsQuery()
    result = await query_uc.execute(db, user_id, category, location, q, current_user_id, limit, offset)
    
    if use_cache:
        await cache_set("listings:search", params, result, ttl=30)
    return result


from app.use_cases.listings.queries.get_user_listings_query import GetUserListingsQuery

@router.get("/my")
@router.get("/my-listings")
async def get_my_listings(
    active: Optional[bool] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query_uc = GetUserListingsQuery()
    return await query_uc.execute(db, current_user.id, active, q, category, limit, offset, start_date, end_date)


def _listing_key_builder(func, namespace="", *, request=None, response=None, args=None, kwargs=None):
    listing_id = (kwargs or {}).get("listing_id") or (args[0] if args else "?")
    uid = (kwargs or {}).get("current_user_id") or "anon"
    return f"listing:detail:{listing_id}:{uid}"


@router.get("/video-feed")
@cache(expire=60)
async def get_video_feed(
    limit: int = 8,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_video_feed(limit)


@router.get("/swipe-feed")
@cache(expire=60)
async def get_swipe_feed(
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_swipe_feed(limit)


@router.get("/{listing_id}")
@cache(expire=60, key_builder=_listing_key_builder)
async def get_listing(
    listing_id: int,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing(listing_id, current_user_id)


@router.post("")
@limiter.limit("20/minute")
async def create_listing(
    request: Request,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.core.uow import SqlAlchemyUnitOfWork
    from app.use_cases.listings.commands.create_listing import CreateListingCommand

    # UoW başlat ve Command'a ver
    uow = SqlAlchemyUnitOfWork()
    command = CreateListingCommand(uow)
    
    # Payload verilerini açarak gönder
    result = await command.execute(
        user_id=current_user.id,
        title=payload.get("title", ""),
        description=payload.get("description"),
        price=payload.get("price"),
        category=payload.get("category", "diger"),
        location=payload.get("location"),
        image_url=payload.get("image_url"),
        image_urls=payload.get("image_urls")
    )

    # Eski yan etkiler (Gelecekte EventBus ile Projector'lara taşınacak, şimdilik kırılmasın diye burada)
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
    db: AsyncSession = Depends(get_db), # db depends still here but we use uow
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = UpdateListingCommand(uow)
    
    result = await cmd.execute(
        listing_id=listing_id, 
        user_id=current_user.id,
        title=payload.get("title"),
        description=payload.get("description"),
        price=payload.get("price")
    )
    
    await invalidate_cache("listings:search")
    return result


@router.get("/{listing_id}/reactivation-cost")
async def reactivation_cost(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Pasif ilanı aktife almak için gereken maliyet bilgisini döner."""
    from sqlalchemy import select
    from app.models.listing import Listing
    from datetime import datetime, timezone, timedelta
    from fastapi import HTTPException

    listing = await db.scalar(select(Listing).where(Listing.id == listing_id))
    if not listing:
        raise HTTPException(status_code=404, detail="İlan bulunamadı")

    created_at = listing.created_at
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)

    within_window = created_at > (datetime.now(timezone.utc) - timedelta(days=30))

    if current_user.is_premium:
        used      = await _get_reactivation_used(current_user.id, current_user.premium_since)
        remaining = max(0, _REACTIVATION_FREE_MONTHLY - used)
        renewal_date: str | None = None
        if current_user.premium_since:
            renewal_date = _reactivation_next_billing(current_user.premium_since).isoformat()
    else:
        remaining    = 0
        renewal_date = None

    is_free    = within_window or (remaining > 0)
    cost       = 0 if is_free else _REACTIVATION_COST_TUCI
    can_afford = is_free or current_user.tuci_balance >= _REACTIVATION_COST_TUCI

    return {
        "is_premium":    current_user.is_premium,
        "free_remaining": remaining,
        "free_limit":    _REACTIVATION_FREE_MONTHLY,
        "cost":          cost,
        "balance":       current_user.tuci_balance,
        "can_afford":    can_afford,
        "renewal_date":  renewal_date,
        "within_window": within_window,
    }


@router.patch("/{listing_id}/toggle")
async def toggle_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).toggle_listing(listing_id, current_user)


@router.delete("/{listing_id}")
async def delete_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = DeleteListingCommand(uow)
    return await cmd.execute(listing_id=listing_id, user_id=current_user.id)


@router.post("/{listing_id}/offers")
async def create_offer(
    listing_id: int,
    payload: ListingOfferCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).create_offer(listing_id, current_user, payload.amount)


@router.post("/{listing_id}/view", status_code=204)
async def record_listing_view(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """İlan detay sayfası açıldığında çağrılır. 'X kişi gördü' sayacı için unique reach yazar."""
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
    db: AsyncSession = Depends(get_db),
):
    """İlanı beğen / beğeniyi kaldır (toggle). Güncel `likes_count` ve `is_liked` döner."""
    return await LikeService(db).toggle_listing_like(listing_id, current_user.id)


@router.get("/{listing_id}/offers")
async def get_listing_offers(
    listing_id: int,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing_offers(listing_id)


@router.get("/{listing_id}/similar")
async def get_similar_listings(
    listing_id: int,
    limit: int = Query(default=10, ge=1, le=20),
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    """
    pgvector cosine distance ile semantik olarak benzer ilanları döndürür.
    İlan embedding'i yoksa boş liste döner.
    """
    row = await db.execute(
        text("SELECT embedding, category FROM listings WHERE id = :id AND status = 'active'"),
        {"id": listing_id},
    )
    target = row.first()
    if target is None or target.embedding is None:
        return []

    block_clause = ""
    params: dict = {"lid": listing_id, "lim": limit,
                    "vec": target.embedding if isinstance(target.embedding, str)
                    else "[" + ",".join(f"{x:.8f}" for x in target.embedding) + "]"}
    if current_user_id:
        block_clause = """
            AND l.user_id NOT IN (
                SELECT blocked_id FROM user_blocks WHERE blocker_id = :uid
                UNION
                SELECT blocker_id FROM user_blocks WHERE blocked_id = :uid
            )
        """
        params["uid"] = current_user_id

    result = await db.execute(
        text(f"""
            SELECT
                l.id, l.title, l.price, l.category, l.location,
                l.image_url, l.image_urls, l.created_at,
                u.id AS user_id, u.username, u.full_name, u.profile_image_url,
                (1.0 - (l.embedding <=> CAST(:vec AS vector))) AS similarity
            FROM listings l
            JOIN users u ON u.id = l.user_id
            WHERE l.id != :lid
              AND l.status = 'active'
              AND l.status != 'deleted'
              AND l.embedding IS NOT NULL
              AND (l.embedding <=> CAST(:vec AS vector)) < 0.7
              {block_clause}
            ORDER BY l.embedding <=> CAST(:vec AS vector)
            LIMIT :lim
        """),
        params,
    )
    import json
    rows = result.fetchall()
    return [
        {
            "id": r.id,
            "title": r.title,
            "price": r.price,
            "category": r.category,
            "location": r.location,
            "image_url": r.image_url,
            "image_urls": json.loads(r.image_urls) if r.image_urls else [],
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "similarity": round(float(r.similarity), 4),
            "user": {
                "id": r.user_id,
                "username": r.username,
                "full_name": r.full_name,
                "profile_image_url": r.profile_image_url,
            },
        }
        for r in rows
    ]


# ── Toplu Kitle Bildirimi (Mass Audience Notification) ───────────────────────

@router.get("/{listing_id}/audience-estimate")
async def estimate_audience_for_listing(
    listing_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Belirtilen ilanın kategorisindeki diğer ilanlarla etkileşime giren,
    ancak bu ilanı henüz görmemiş / etkileşime girmemiş kullanıcı sayısını hesaplar.
    Ayrıca kullanıcının TUCi bakiyesi ve Blast kredi limitlerini döner.
    """
    from sqlalchemy import select
    from app.models.listing import Listing
    from app.routers.leads import _PER_BLAST_CAP_PRO, _PER_BLAST_CAP_STANDARD, _BLAST_LIMIT_PRO, _BLAST_LIMIT_STANDARD, _get_blast_used
    from app.database import engine
    from sqlalchemy import text as sql_text

    listing = await db.scalar(select(Listing).where(Listing.id == listing_id))
    if not listing:
        raise HTTPException(status_code=404, detail="İlan bulunamadı.")
        
    if listing.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Bu işlem için yetkiniz yok.")

    category = listing.category or ""
    
    listing_q = select(Listing.id).where(
        Listing.status != ListingStatus.DELETED,
        Listing.status == ListingStatus.ACTIVE,
    )
    if category:
        listing_q = listing_q.where(Listing.category == category)
    listing_q = listing_q.limit(500)

    result = await db.execute(listing_q)
    listing_ids = [row[0] for row in result.fetchall()]

    if not listing_ids:
        return {"audience_size": 0, "estimated_cost": 0, "blast_credits_remaining": 0, "per_blast_cap": 10, "tuci_balance": current_user.tuci_balance}

    ids_str = ", ".join(str(i) for i in listing_ids)
    target_user_ids = []
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        ch_result = await ch.query(f"""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_type = 'listing'
              AND item_id IN ({ids_str})
              AND event_type IN ('view', 'dwell', 'bid_hesitation')
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id IS NOT NULL
              AND user_id != {current_user.id}
            LIMIT 10000
        """)
        target_user_ids = [int(r[0]) for r in ch_result.result_rows if r[0]]
    except Exception as exc:
        pass

    reachable = 0
    if target_user_ids:
        token_count = await db.scalar(sql_text("""
            SELECT COUNT(*) FROM users
            WHERE id = ANY(:ids)
              AND fcm_token IS NOT NULL AND fcm_token != ''
              AND id NOT IN (
                  SELECT follower_id FROM follows WHERE followed_id = :me
              )
        """), {"ids": target_user_ids, "me": current_user.id})
        reachable = int(token_count or 0)

    cap   = _PER_BLAST_CAP_PRO if current_user.is_premium else _PER_BLAST_CAP_STANDARD
    limit = _BLAST_LIMIT_PRO if current_user.is_premium else _BLAST_LIMIT_STANDARD
    used  = await _get_blast_used(current_user.id, current_user.premium_since)
    credits_remaining = max(0, limit - used)

    return {
        "audience_size": reachable,
        "estimated_cost": 0,
        "blast_credits_remaining": credits_remaining,
        "per_blast_cap": cap,
        "tuci_balance": current_user.tuci_balance
    }

from pydantic import BaseModel, Field
class MassNotificationRequest(BaseModel):
    estimated_cost: int | None = Field(default=None, ge=0)
    recipient_count: int | None = Field(default=None, ge=1)

@router.get("/{listing_id}/notification-cooldown")
async def notification_cooldown(
    listing_id: int,
    current_user: User = Depends(get_current_user),
):
    """İlan başına 24 saatlik bildirim cooldown süresi (saniye). 0 ise gönderim yapılabilir."""
    from app.utils.redis_client import get_redis
    redis = await get_redis()
    ttl = await redis.ttl(f"blast_cooldown:{current_user.id}:{listing_id}")
    return {"seconds_remaining": max(0, ttl)}


@router.post("/{listing_id}/send-mass-notification", status_code=202)
async def send_mass_notification_for_listing(
    listing_id: int,
    body: MassNotificationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    İlan için Toplu Kitle Bildirimi gönderir.
    Ücretsiz krediler ve/veya TUCi bakiyesi kullanılır.
    Her ilan için 24 saatlik cooldown uygulanır.
    """
    from app.routers.leads import BlastRequest, send_blast
    from app.models.listing import Listing
    from sqlalchemy import select
    from app.utils.redis_client import get_redis

    listing = await db.scalar(select(Listing).where(Listing.id == listing_id))
    if not listing:
        raise HTTPException(status_code=404, detail="İlan bulunamadı.")

    if listing.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Bu işlem için yetkiniz yok.")

    redis = await get_redis()
    cooldown_key = f"blast_cooldown:{current_user.id}:{listing_id}"
    ttl = await redis.ttl(cooldown_key)
    if ttl > 0:
        raise HTTPException(
            status_code=429,
            detail={"code": "cooldown", "seconds_remaining": ttl},
        )

    blast_req = BlastRequest(
        title=listing.title,
        category=listing.category or "",
        listing_id=listing.id,
        estimated_cost=body.estimated_cost,
        recipient_count=body.recipient_count,
    )

    result = await send_blast(body=blast_req, db=db, current_user=current_user)
    await redis.setex(cooldown_key, 86400, 1)
    return result
