import logging
from typing import Optional

from fastapi import APIRouter, Depends, Request, Query as FastApiQuery
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import text

from app.database import get_db
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
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
from app.core.uow import SqlAlchemyUnitOfWork
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
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user),
):
    # SearchListingsQuery / GetMyListingsQuery yönlendirmesi
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    
    if user_id and current_user and user_id == current_user.id:
        # Kendi ilanlarım (Aktif/Pasif vs görebilir)
        # /api/listings?user_id=me istekleri için
        active_str = request.query_params.get("active")
        is_active = (active_str.lower() == "true") if active_str else None
        
        query_handler = GetMyListingsQuery(uow)
        return await query_handler.execute(
            current_user=current_user,
            active=is_active,
            q=q,
            category=category,
            limit=limit,
            offset=offset,
            start_date=start_date,
            end_date=end_date
        )
    else:
        # Genel arama
        query_handler = SearchListingsQuery(uow)
        return await query_handler.execute(
            user_id=user_id,
            category=category,
            location=location,
            q=q,
            limit=limit,
            offset=offset
        )


def _listing_key_builder(func, namespace="", *, request=None, response=None, args=None, kwargs=None):
    listing_id = (kwargs or {}).get("listing_id") or (args[0] if args else "?")
    uid = (kwargs or {}).get("current_user_id") or "anon"
    return f"listing:detail:{listing_id}:{uid}"


@router.get("/video-feed")
async def get_video_feed(
    limit: int = 8,
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    query = GetVideoFeedQuery(uow)
    return await query.execute(limit=limit)


@router.get("/swipe-feed")
async def get_swipe_feed(
    limit: int = 10,
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    query = GetSwipeFeedQuery(uow)
    return await query.execute(limit=limit)


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
    db: AsyncSession = Depends(get_db),
):
    """Giriş yapmış kullanıcının kendi ilanlarını döner."""
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    is_active = (active.lower() == "true") if active else None
    query_handler = GetMyListingsQuery(uow)
    return await query_handler.execute(
        current_user=current_user,
        active=is_active,
        q=q,
        category=category,
        limit=limit,
        offset=offset,
        start_date=start_date,
        end_date=end_date,
    )


@router.get("/{listing_id}")

async def get_listing(
    request: Request,
    listing_id: int,
    current_user_id: Optional[int] = Depends(_optional_user_id),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    query = GetListingQuery(uow)
    ip_address = request.client.host if request.client else None
    return await query.execute(listing_id, current_user_id, ip_address=ip_address)


@router.post("")
@limiter.limit("20/minute")
async def create_listing(
    request: Request,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    command = CreateListingCommand(uow)
    
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
    db: AsyncSession = Depends(get_db),
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
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    query = GetReactivationCostQuery(uow)
    return await query.execute(listing_id, current_user)


@router.patch("/{listing_id}/toggle")
async def toggle_listing(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = ToggleListingCommand(uow)
    return await cmd.execute(listing_id, current_user)


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
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = CreateListingOfferCommand(uow)
    return await cmd.execute(listing_id, current_user, payload.amount)


@router.post("/{listing_id}/view", status_code=204)
async def record_listing_view(
    listing_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
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
    from app.use_cases.listings.commands.like_listing import LikeListingCommand
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    cmd = LikeListingCommand(uow)
    return await cmd.execute(listing_id, current_user.id)


@router.get("/{listing_id}/offers")
async def get_listing_offers(
    listing_id: int,
    db: AsyncSession = Depends(get_db),
):
    uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)
    query = GetListingOffersQuery(uow)
    return await query.execute(listing_id)
