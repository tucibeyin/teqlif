import json
import base64
from typing import Literal
from pydantic import BaseModel
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import numpy as np

from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.utils.auth import get_current_user, get_current_user_optional
from app.models.user import User
from app.models.listing import Listing
from app.use_cases.feed.queries.feed_queries import FeedQueries
from app.services.recommendation_service import (
    get_personalized_feed as get_ch_personalized_feed,
    get_user_category_affinity,
)
from app.utils.redis_client import get_redis

router = APIRouter(prefix="/api/feed", tags=["feed"])


@router.get("")
async def get_feed(
    page: int = Query(default=0, ge=0, le=100),
    seed: str = Query(default="default", max_length=64),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User | None = Depends(get_current_user_optional),
):
    """
    Kişiselleştirilmiş ilan akışı.

    - Giriş yapmış kullanıcılar: kategori ilgisine göre sıralı feed
    - Misafirler: popüler ilanlar (son 30 gün, beğeni sayısına göre)
    - page: 0-tabanlı sayfa numarası (sayfa başına 20 ilan)
    - seed: oturum başında üretilmeli, scroll boyunca aynı kalmalı
    """
    user_id = current_user.id if current_user else None
    return await FeedQueries(uow).get_personalized_feed(user_id, page, seed)


@router.get("/personalized")
async def get_clickhouse_personalized_feed(
    limit: int = Query(default=10, ge=1, le=30),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    ClickHouse telemetri verisinden epsilon-greedy kişiselleştirilmiş feed.

    - click +5 / impression+dwell>3s +2 / skip -2 (son 7 gün)
    - Top-3 kategori belirlenir; %80 bu kategorilerden, %20 keşfet
    - Yeni kullanıcılarda (cold start) son 30 günün popüler ilanları döner
    """
    return await get_ch_personalized_feed(current_user.id, db, limit)


@router.get("/personalized/affinity")
async def get_affinity_profile(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Kullanıcının ClickHouse tabanlı kategori affinite profilini döndürür (debug/test için)."""
    affinity = await get_user_category_affinity(current_user.id, db)
    return {"user_id": current_user.id, "affinity": affinity, "cold_start": not affinity}


@router.post("/not-interested/{listing_id}", status_code=204)
async def mark_not_interested(
    listing_id: int,
    current_user: User = Depends(get_current_user),
):
    """
    Bir ilanı 'ilgilenmiyorum' olarak işaretle — Redis set'e ekler.
    Feed ve For-You sorgularında bu ilanlar filtrelenir (7 gün TTL).
    """
    redis = await get_redis()
    key = f"not_interested:{current_user.id}"
    await redis.sadd(key, listing_id)
    await redis.expire(key, 7 * 86400)


@router.get("/recent")
async def get_recent_mixed_feed(
    page: int = Query(default=0, ge=0, le=50),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User | None = Depends(get_current_user_optional),
):
    """
    Son ilanlar + ilgi enjeksiyonu (pos 5,10,15) + sponsored (page 0, pos 2,7,12).
    Misafirler: sadece son ilanlar, enjeksiyon yok.
    """
    user_id = current_user.id if current_user else None
    return await FeedQueries(uow).get_mixed_recent_feed(user_id, page)


@router.get("/for-you")
async def get_for_you_feed(
    page: int = Query(default=0, ge=0, le=4),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    """
    Embedding tabanlı kişisel 'Sana Özel' akışı.

    - preference_embedding yoksa cold start (popüler ilanlar)
    - varsa pgvector cosine distance ile en yakın ilanlar
    - Sayfa başına 20 ilan, maks 5 sayfa (100 ilan havuzu Redis'te 5 dk önbelleklenir)
    """
    return await FeedQueries(uow).get_foryou_feed(current_user.id, page)


class FeedSignalPayload(BaseModel):
    listing_id: int
    event: Literal["click", "skip"]


@router.post("/signal", status_code=204)
async def record_feed_signal(
    payload: FeedSignalPayload,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Session-içi drift: kullanıcının mevcut oturumda hangi yöne ilgi gösterdiğini yakalar.
    click → session vektörüne eklenir (EMA α=0.3)
    skip  → oturumu etkilemez (negatif sinyal çok gürültülü)
    Session vektörü 30 dakika TTL ile Redis'te tutulur.
    """
    if payload.event != "click":
        return

    emb_row = await db.scalar(
        select(Listing.embedding).where(
            Listing.id == payload.listing_id,
            Listing.embedding.isnot(None),
        )
    )
    if emb_row is None:
        return

    new_vec = np.array(emb_row, dtype=np.float32)
    norm = np.linalg.norm(new_vec)
    if norm > 0:
        new_vec /= norm

    redis = await get_redis()
    key = f"feed:session:{current_user.id}"
    existing = await redis.get(key)

    if existing:
        try:
            alpha = 0.3
            old_vec = np.frombuffer(base64.b64decode(existing), dtype=np.float32)
            blended = (1 - alpha) * old_vec + alpha * new_vec
            bn = np.linalg.norm(blended)
            if bn > 0:
                blended /= bn
            new_vec = blended
        except Exception:
            pass
    await redis.setex(key, 1800, base64.b64encode(new_vec.tobytes()).decode())


@router.get("/hesitated")
async def get_hesitated_listings(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Son 7 günde kullanıcının teklif alanına fiyat yazıp göndermediği ilanlar.
    Maksimum 10 ilan, en son tereddüt önce.
    """
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        if ch is None:
            return []

        result = await ch.query(
            """
            SELECT item_id, MAX(timestamp) AS last_hes
            FROM user_events
            WHERE event_type = 'bid_hesitation'
              AND item_type  = 'listing'
              AND user_id    = %(uid)s
              AND timestamp >= now() - INTERVAL 7 DAY
            GROUP BY item_id
            ORDER BY last_hes DESC
            LIMIT 10
            """,
            parameters={"uid": current_user.id},
        )
        listing_ids = [int(r[0]) for r in result.result_rows if r[0]]
    except Exception:
        return []

    if not listing_ids:
        return []

    from sqlalchemy import text as sql_text
    rows = await db.execute(
        sql_text("""
            SELECT l.id, l.title, l.price, l.image_urls, l.image_url
            FROM listings l
            WHERE l.id = ANY(:ids)
              AND l.status = 'active'
        """),
        {"ids": listing_ids},
    )
    listing_map = {r.id: r for r in rows.fetchall()}

    listings = []
    for lid in listing_ids:
        r = listing_map.get(lid)
        if r is None:
            continue
        imgs = r.image_urls or []
        photo = imgs[0] if imgs else r.image_url
        listings.append({
            "id": r.id,
            "title": r.title,
            "price": float(r.price) if r.price is not None else None,
            "image_url": photo,
        })
    return listings
