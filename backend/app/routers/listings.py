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

from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
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
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listings(user_id, category, location, current_user_id)


@router.get("/my")
async def get_my_listings(
    active: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_my_listings(current_user, active)


@router.get("/video-feed")
async def get_video_feed(
    limit: int = 8,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_video_feed(limit)


@router.get("/swipe-feed")
async def get_swipe_feed(
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_swipe_feed(limit)


@router.get("/{listing_id}")
async def get_listing(
    listing_id: int,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    return await ListingService(db).get_listing(listing_id, current_user_id)


@router.post("")
async def create_listing(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await ListingService(db).create_listing(payload, current_user)
    pool = get_pool()
    if pool:
        await pool.enqueue_job("generate_listing_embedding_task", result["id"])
    return result


@router.get("/{listing_id}/reactivation-cost")
async def reactivation_cost(
    listing_id: int,
    current_user: User = Depends(get_current_user),
):
    """Pasif ilanı aktife almak için gereken maliyet bilgisini döner."""
    if current_user.is_premium:
        used      = await _get_reactivation_used(current_user.id, current_user.premium_since)
        remaining = max(0, _REACTIVATION_FREE_MONTHLY - used)
        renewal_date: str | None = None
        if current_user.premium_since:
            renewal_date = _reactivation_next_billing(current_user.premium_since).isoformat()
    else:
        remaining    = 0
        renewal_date = None

    is_free    = remaining > 0
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
    return await ListingService(db).delete_listing(listing_id, current_user)


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
        text("SELECT embedding, category FROM listings WHERE id = :id AND is_active = TRUE AND is_deleted = FALSE"),
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
              AND l.is_active = TRUE
              AND l.is_deleted = FALSE
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
