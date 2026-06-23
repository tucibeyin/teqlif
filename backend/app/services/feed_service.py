"""
Feed Service — Kişiselleştirilmiş ilan akışı.

Algoritma:
  1. Kullanıcının category affinity skorları user_interests tablosundan okunur
     (ARQ worker tarafından her 15 dakikada güncellenir)
  2. ~400 aday ilan oluşturulur: affinity pool + social pool + exploration pool
  3. Her aday formülle skorlanır (pure SQL)
  4. Top-N ilan döndürülür, listing_impressions'a yazılır
  5. Sonuç Redis'te 5 dk önbelleklenir

Cold start: user_interests boşsa global popüler ilanlar gösterilir.
"""
from __future__ import annotations

import json
import math
import random
import logging
from typing import Optional

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.utils.redis_client import get_redis
from app.services.listing_service import _row_dict
from app.services.like_service import LikeService
from app.models.listing import Listing
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from sqlalchemy import select

logger = logging.getLogger(__name__)

PAGE_SIZE = 20
FEED_CACHE_TTL = 300   # 5 dakika
INTEREST_CACHE_TTL = 900  # 15 dakika

# Sponsored ilan pozisyonları (0-indexed) — 3., 8., 13. slot
AD_SLOTS = [2, 7, 12]


# ── Kategori ağırlık hesabı ───────────────────────────────────────────────────

async def get_user_interests(user_id: int, db: AsyncSession) -> dict[str, float]:
    """Kullanıcının category → score sözlüğünü döndürür. Redis'ten okur, yoksa DB'den."""
    redis = await get_redis()
    cache_key = f"interests:{user_id}"
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    rows = await db.execute(
        text("SELECT category, score FROM user_interests WHERE user_id = :uid ORDER BY score DESC"),
        {"uid": user_id},
    )
    interests = {row.category: row.score for row in rows}
    if interests:
        await redis.setex(cache_key, INTEREST_CACHE_TTL, json.dumps(interests))
    return interests


# ── Ana feed sorgusu ──────────────────────────────────────────────────────────

async def get_personalized_feed(
    user_id: Optional[int],
    page: int,
    seed: str,
    db: AsyncSession,
) -> list[dict]:
    """
    Kişiselleştirilmiş feed döndürür.

    - user_id None ise (misafir): popüler ilanlar
    - page: 0-tabanlı sayfa numarası
    - seed: oturum başına üretilen rastgele string (tutarlı sıralama için)
    """
    if user_id:
        cache_key = f"feed:{user_id}:{seed}:{page}"
        redis = await get_redis()
        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

    offset = page * PAGE_SIZE

    if user_id:
        interests = await get_user_interests(user_id, db)
        listing_ids = await _score_and_rank(user_id, interests, offset, PAGE_SIZE, seed, db)
    else:
        listing_ids = await _popular_feed(offset, PAGE_SIZE, db)

    if not listing_ids:
        return []

    # İlanları + kullanıcı bilgilerini çek
    rows_result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(Listing.id.in_(listing_ids), Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
    )
    rows = {listing.id: (listing, user) for listing, user in rows_result.all()}

    counts, liked_set = await LikeService.batch_listing_likes(db, listing_ids, user_id)

    # Sıralamayı koru (scoring'den gelen sıra)
    result = []
    for lid in listing_ids:
        if lid not in rows:
            continue
        listing, user = rows[lid]
        result.append(_row_dict(listing, user, counts.get(lid, 0), lid in liked_set))

    # Görüldü olarak işaretle (arka planda, hata olursa sessizce geç)
    if user_id and result:
        try:
            await _mark_impressions(user_id, [r["id"] for r in result], db)
        except Exception as exc:
            logger.warning("[Feed] Impression yazılamadı: %s", exc)

    # Önbelleğe al
    if user_id and result:
        redis = await get_redis()
        await redis.setex(cache_key, FEED_CACHE_TTL, json.dumps(result))

    return result


async def _score_and_rank(
    user_id: int,
    interests: dict[str, float],
    offset: int,
    limit: int,
    seed: str,
    db: AsyncSession,
) -> list[int]:
    """
    Aday ilanları puanlar ve sıralı ID listesi döndürür.

    feed_score =
      category_affinity × 0.40
      + listing_quality  × 0.25   (log-normalize beğeni sayısı)
      + freshness        × 0.20   (e^(-age_days/7), 7 günde yarıya düşer)
      + social_signal    × 0.10   (takip edilen satıcı ise +1)
      + exploration      × 0.05   (ilgi dışı kategori ise +0.3)
      + random_jitter    × 0.02   (seed tabanlı küçük çeşitlilik)
      - seen_penalty     × 0.30   (daha önce görüldüyse)
    """
    if not interests:
        return await _popular_feed(offset, limit, db)

    # Top-5 kategori ve skorları
    top_cats = sorted(interests.items(), key=lambda x: x[1], reverse=True)[:5]
    top_cat_names = [c for c, _ in top_cats]

    # Affinity skoru için CASE ifadesi oluştur
    cat_cases = " ".join(
        f"WHEN l.category = '{cat}' THEN {score:.4f}"
        for cat, score in top_cats
    )
    cat_affinity_expr = f"CASE {cat_cases} ELSE 0.0 END"

    # Exploration bonusu — top-5 dışındaki kategoriler
    exploration_expr = f"CASE WHEN l.category NOT IN ({','.join(repr(c) for c in top_cat_names)}) THEN 0.3 ELSE 0.0 END"

    sql = text(f"""
        WITH candidates AS (
            -- Affinity pool: ilgi kategorilerinden yeni ilanlar
            (
                SELECT l.id
                FROM listings l
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  AND l.user_id != :uid
                  AND l.category IN :top_cats
                ORDER BY l.created_at DESC
                LIMIT 250
            )
            UNION
            -- Social pool: takip edilenlerin son ilanları
            (
                SELECT l.id
                FROM listings l
                INNER JOIN follows f ON f.followed_id = l.user_id AND f.follower_id = :uid
                WHERE l.is_active = TRUE AND l.is_deleted = FALSE
                ORDER BY l.created_at DESC
                LIMIT 50
            )
            UNION
            -- Exploration pool: kaliteli ama farklı kategorilerden ilanlar
            (
                SELECT l.id
                FROM listings l
                LEFT JOIN listing_likes ll ON ll.listing_id = l.id
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  AND l.user_id != :uid
                  AND l.category NOT IN :top_cats
                GROUP BY l.id
                HAVING COUNT(ll.id) >= 1
                ORDER BY l.created_at DESC
                LIMIT 100
            )
        ),
        scored AS (
            SELECT
                l.id,
                (
                    ({cat_affinity_expr}) * 0.40
                    + (LOG(1.0 + COALESCE(lk.like_count, 0)) / 5.0) * 0.25
                    + EXP(-EXTRACT(EPOCH FROM (NOW() - l.created_at)) / 604800.0) * 0.20
                    + COALESCE(soc.is_followed, 0.0) * 0.10
                    + ({exploration_expr}) * 0.05
                    + (ABS(HASHTEXT(l.id::text || :seed)::float / 2147483647.0)) * 0.02
                    - COALESCE(imp.seen, 0.0) * 0.30
                ) AS feed_score
            FROM candidates c
            INNER JOIN listings l ON l.id = c.id
            LEFT JOIN (
                SELECT listing_id, COUNT(*) AS like_count
                FROM listing_likes
                GROUP BY listing_id
            ) lk ON lk.listing_id = l.id
            LEFT JOIN (
                SELECT l2.id, 1.0 AS is_followed
                FROM listings l2
                INNER JOIN follows f ON f.followed_id = l2.user_id AND f.follower_id = :uid
            ) soc ON soc.id = l.id
            LEFT JOIN (
                SELECT listing_id, 1.0 AS seen
                FROM listing_impressions
                WHERE user_id = :uid
            ) imp ON imp.listing_id = l.id
        )
        SELECT id
        FROM scored
        ORDER BY feed_score DESC
        LIMIT :lim OFFSET :off
    """)

    result = await db.execute(sql, {
        "uid": user_id,
        "top_cats": tuple(top_cat_names),
        "seed": seed,
        "lim": limit,
        "off": offset,
    })
    return [row.id for row in result]


async def _popular_feed(offset: int, limit: int, db: AsyncSession) -> list[int]:
    """Cold start ve misafir kullanıcılar için son 30 günün en popüler ilanları."""
    result = await db.execute(
        text("""
            SELECT l.id
            FROM listings l
            LEFT JOIN listing_likes ll ON ll.listing_id = l.id
            WHERE l.is_active = TRUE
              AND l.is_deleted = FALSE
              AND l.created_at > NOW() - INTERVAL '30 days'
            GROUP BY l.id
            ORDER BY COUNT(ll.id) DESC, l.created_at DESC
            LIMIT :lim OFFSET :off
        """),
        {"lim": limit, "off": offset},
    )
    return [row.id for row in result]


async def _mark_impressions(user_id: int, listing_ids: list[int], db: AsyncSession) -> None:
    """Gösterilen ilanları listing_impressions tablosuna yazar (upsert)."""
    if not listing_ids:
        return
    await db.execute(
        text("""
            INSERT INTO listing_impressions (user_id, listing_id)
            VALUES (:uid, unnest(:ids::int[]))
            ON CONFLICT (user_id, listing_id) DO UPDATE SET seen_at = NOW()
        """),
        {"uid": user_id, "ids": listing_ids},
    )
    await db.commit()


# ── For-You Feed (pgvector cosine distance) ──────────────────────────────────

FORYOU_CACHE_TTL = 300    # 5 dakika
FORYOU_POOL_SIZE = 100    # Önceden hesaplanan ID havuzu


async def get_foryou_feed(user_id: int, page: int, db: AsyncSession) -> list[dict]:
    """
    Embedding tabanlı 'Sana Özel' akışı.

    - user.preference_embedding yoksa → cold start (popüler ilanlar)
    - varsa → pgvector cosine distance ile en yakın ilanlar
    - user.max_budget varsa price <= max_budget * 1.2 filtresi uygulanır
    - Tüm ID havuzu Redis'te 5 dk önbelleklenir; sayfalama Redis'ten yapılır
    """
    cache_key = f"feed:foryou:{user_id}"
    redis = await get_redis()

    cached = await redis.get(cache_key)
    if cached:
        all_ids = json.loads(cached)
    else:
        all_ids = await _compute_foryou_ids(user_id, db, limit=FORYOU_POOL_SIZE)
        if all_ids:
            await redis.setex(cache_key, FORYOU_CACHE_TTL, json.dumps(all_ids))

    start = page * PAGE_SIZE
    listing_ids = all_ids[start: start + PAGE_SIZE]

    if not listing_ids:
        return []

    rows_result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.id.in_(listing_ids),
            Listing.is_active == True,  # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
        )
    )
    rows = {listing.id: (listing, user) for listing, user in rows_result.all()}
    counts, liked_set = await LikeService.batch_listing_likes(db, listing_ids, user_id)

    result = []
    for lid in listing_ids:
        if lid not in rows:
            continue
        listing, user = rows[lid]
        result.append(_row_dict(listing, user, counts.get(lid, 0), lid in liked_set))

    # Sponsored ilan enjeksiyonu — sadece ilk sayfa
    if page == 0:
        try:
            ad_items = await _get_sponsored_listings(db)
            result = _inject_ads(result, ad_items)
        except Exception as exc:
            logger.warning("[Feed] Sponsored enjeksiyonu atlandı: %s", exc)

    return result


async def _compute_foryou_ids(user_id: int, db: AsyncSession, limit: int) -> list[int]:
    """
    Kullanıcının preference_embedding'ine en yakın ilan ID'lerini döndürür.
    - Embedding yoksa popüler ilanlar döner (cold start).
    - user.max_budget varsa: price <= max_budget * 1.2 filtresi uygulanır.
      (Bütçenin %20 üstüne kadar tolerans — kullanıcıyı tamamen kesmez.)
    """
    user = await db.scalar(select(User).where(User.id == user_id))

    if user is None or user.preference_embedding is None:
        return await _popular_feed(0, limit, db)

    vec_str = "[" + ",".join(f"{x:.8f}" for x in user.preference_embedding) + "]"

    # Bütçe filtresi — max_budget NULL ise WHERE koşulu eklenmez
    budget_clause = ""
    params: dict = {"uid": user_id, "vec": vec_str, "lim": limit}
    if user.max_budget is not None:
        budget_clause = "AND (price IS NULL OR price <= :price_ceiling)"
        params["price_ceiling"] = user.max_budget * 1.2

    result = await db.execute(
        text(f"""
            SELECT id
            FROM listings
            WHERE is_active = TRUE
              AND is_deleted = FALSE
              AND embedding IS NOT NULL
              AND user_id != :uid
              {budget_clause}
            ORDER BY embedding <=> :vec::vector
            LIMIT :lim
        """),
        params,
    )
    ids = [r.id for r in result]
    return ids if ids else await _popular_feed(0, limit, db)


# ── Sponsored İlan Enjeksiyonu ────────────────────────────────────────────────

async def _get_sponsored_listings(db: AsyncSession) -> list[dict]:
    """
    Redis'teki aktif kampanyalardan rastgele en fazla AD_SLOTS adet
    sponsored ilan çeker. Bütçesi kalmayan kampanyaların key'leri
    zaten Redis'te olmadığından otomatik olarak filtre dışı kalır.
    """
    redis = await get_redis()

    campaign_ids: list[int] = []
    async for key in redis.scan_iter("ad_campaign_budget:*", count=100):
        try:
            campaign_ids.append(int(key.split(":")[-1]))
        except (ValueError, IndexError):
            continue
        if len(campaign_ids) >= 50:  # tarama limiti
            break

    if not campaign_ids:
        return []

    selected = random.sample(campaign_ids, min(len(AD_SLOTS), len(campaign_ids)))

    result = await db.execute(
        select(AdCampaign, Listing, User)
        .join(Listing, Listing.id == AdCampaign.listing_id)
        .join(User, User.id == Listing.user_id)
        .where(
            AdCampaign.id.in_(selected),
            AdCampaign.status == "active",
            Listing.is_active == True,   # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
        )
    )
    return [
        _row_dict(listing, user, 0, False, is_sponsored=True, campaign_id=campaign.id)
        for campaign, listing, user in result.all()
    ]


def _inject_ads(organic: list[dict], ads: list[dict]) -> list[dict]:
    """
    Sponsored item'ları organik feed'e AD_SLOTS pozisyonlarına enjekte eder.
    Her insert önceki insertlerin yarattığı kaymayı hesaba katar.
    Organik eleman sayısı değişmez — toplam eleman sayısı ad sayısı kadar artar.
    """
    if not ads:
        return organic
    result = list(organic)
    for i, ad in enumerate(ads):
        if i >= len(AD_SLOTS):
            break
        # i adet önceki insert, hedef pozisyonu i kadar sağa kaydırdı
        pos = min(AD_SLOTS[i] + i, len(result))
        result.insert(pos, ad)
    return result


# ── Cache invalidation ────────────────────────────────────────────────────────

async def invalidate_user_feed_cache(user_id: int) -> None:
    """Kullanıcı beğeni/favori/mesaj attığında feed cache'ini temizler."""
    try:
        redis = await get_redis()
        keys = await redis.keys(f"feed:{user_id}:*")
        if keys:
            await redis.delete(*keys)
        await redis.delete(f"interests:{user_id}")
    except Exception as exc:
        logger.warning("[Feed] Cache invalidation başarısız: %s", exc)
