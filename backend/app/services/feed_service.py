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
import base64
from datetime import datetime
from typing import Optional

import numpy as np
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.utils.redis_client import get_redis
from app.services.listing_service import _row_dict, _fetch_seller_meta
from app.services.like_service import LikeService
from app.services.feed_als_ml import get_als_scores
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
        # "İlgilenmiyorum" listesini Redis'ten çek
        redis = await get_redis()
        excluded_raw = await redis.smembers(f"not_interested:{user_id}")
        excluded_ids = [int(x) for x in excluded_raw] if excluded_raw else []
        # Kullanıcı embedding ve max_budget'ı al (pgvector scoring + bütçe filtresi için)
        _user = await db.scalar(select(User).where(User.id == user_id))
        user_embedding = _user.preference_embedding if _user else None
        max_budget = _user.max_budget if _user else None
        listing_ids = await _score_and_rank(
            user_id, interests, offset, PAGE_SIZE, seed, db,
            excluded_ids=excluded_ids,
            user_embedding=user_embedding,
            max_budget=max_budget,
        )
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

    # Eğer kullanıcının kendi ilanı denk geldiyse impression_count çek
    impression_map: dict[int, int] = {}
    if user_id and listing_ids:
        from sqlalchemy import func
        from app.models.listing_impression import ListingImpression
        my_listing_ids = [lid for lid in listing_ids if lid in rows and rows[lid][1].id == user_id]
        if my_listing_ids:
            imp_result = await db.execute(
                select(ListingImpression.listing_id, func.count())
                .select_from(ListingImpression)
                .where(ListingImpression.listing_id.in_(my_listing_ids))
                .group_by(ListingImpression.listing_id)
            )
            for lid, imp_count in imp_result.all():
                impression_map[lid] = imp_count

    # Sıralamayı koru (scoring'den gelen sıra)
    all_uids = list({rows[lid][1].id for lid in listing_ids if lid in rows})
    badge_map, trending_cats = await _fetch_seller_meta(all_uids)

    result = []
    for lid in listing_ids:
        if lid not in rows:
            continue
        listing, user = rows[lid]
        result.append(_row_dict(
            listing, user, counts.get(lid, 0), lid in liked_set,
            seller_badge=badge_map.get(user.id),
            is_trending=listing.category in trending_cats,
            impression_count=impression_map.get(lid, 0) if user.id == user_id else None
        ))

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
    excluded_ids: list[int] | None = None,
    user_embedding: list[float] | None = None,
    max_budget: float | None = None,
) -> list[int]:
    """
    Aday ilanları puanlar ve sıralı ID listesi döndürür.

    Embedding varsa:
      pgvector_similarity × 0.20  (cosine similarity, 0–1)
      category_affinity   × 0.30
      listing_quality     × 0.20  (log-normalize beğeni)
      freshness           × 0.22/0.15  (saat dilimine göre)
      social_signal       × 0.12/0.08
      exploration         × 0.04
      random_jitter       × 0.02
      host_quality        × 0.04
      seller_conv         × 0.06
      seen_penalty        × -0.25

    Embedding yoksa: pgvector terimi = 0, ağırlıklar orijinal değerlere döner.
    max_budget varsa: price <= max_budget × 1.2 filtresi tüm candidate pool'lara uygulanır.
    """
    if not interests:
        return await _popular_feed(offset, limit, db, exclude_user_id=user_id)

    # ── Saat dilimi bağlam sinyali ────────────────────────────────────────────
    hour = datetime.now().hour
    if user_embedding:
        freshness_w = 0.22 if 6 <= hour <= 10 else 0.15
        social_w    = 0.12 if 19 <= hour <= 23 else 0.08
        cat_w, quality_w, explore_w, host_w, conv_w, seen_w = 0.30, 0.20, 0.04, 0.04, 0.06, 0.25
    else:
        freshness_w = 0.28 if 6 <= hour <= 10 else 0.20
        social_w    = 0.14 if 19 <= hour <= 23 else 0.10
        cat_w, quality_w, explore_w, host_w, conv_w, seen_w = 0.40, 0.25, 0.05, 0.05, 0.08, 0.30

    # Top-5 kategori ve skorları
    top_cats = sorted(interests.items(), key=lambda x: x[1], reverse=True)[:5]
    top_cat_names = [c for c, _ in top_cats]

    # Affinity skoru için CASE ifadesi
    cat_cases = " ".join(
        f"WHEN l.category = '{cat}' THEN {score:.4f}"
        for cat, score in top_cats
    )
    cat_affinity_expr = f"CASE {cat_cases} ELSE 0.0 END"

    # Exploration bonusu — top-5 dışı
    exploration_expr = f"CASE WHEN l.category NOT IN ({','.join(repr(c) for c in top_cat_names)}) THEN 0.3 ELSE 0.0 END"

    # Filtreler
    ni_filter = f"AND l.id NOT IN ({','.join(str(i) for i in excluded_ids)})" if excluded_ids else ""

    budget_clause = ""
    params: dict = {
        "uid": user_id,
        "top_cats": tuple(top_cat_names),
        "seed": seed,
        "lim": limit,
        "off": offset,
    }
    if max_budget is not None:
        budget_clause = "AND (l.price IS NULL OR l.price <= :price_ceiling)"
        params["price_ceiling"] = max_budget * 1.2

    # pgvector desteği — embedding varsa pool + scoring terimi eklenir
    pgvec_pool_sql = ""
    pgvec_score_term = "0.0"
    if user_embedding:
        vec_str = "[" + ",".join(f"{x:.8f}" for x in user_embedding) + "]"
        params["vec"] = vec_str
        pgvec_pool_sql = f"""
            UNION
            -- pgvector pool: semantik benzerlik (embedding tabanlı)
            (
                SELECT l.id
                FROM listings l
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  AND l.embedding IS NOT NULL
                  AND l.user_id != :uid
                  {ni_filter}
                  {budget_clause}
                ORDER BY l.embedding <=> CAST(:vec AS vector)
                LIMIT 80
            )
        """
        pgvec_score_term = (
            "CASE WHEN l.embedding IS NOT NULL "
            "THEN (1.0 - (l.embedding <=> CAST(:vec AS vector))) * 0.20 ELSE 0.0 END"
        )

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
                  {ni_filter}
                  {budget_clause}
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
                  AND l.user_id != :uid
                  {ni_filter}
                  {budget_clause}
                ORDER BY l.created_at DESC
                LIMIT 50
            )
            UNION
            -- Exploration pool: farklı kategorilerden kaliteli ilanlar
            (
                SELECT l.id
                FROM listings l
                LEFT JOIN listing_likes ll ON ll.listing_id = l.id
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  AND l.user_id != :uid
                  AND l.category NOT IN :top_cats
                  {ni_filter}
                  {budget_clause}
                GROUP BY l.id
                HAVING COUNT(ll.id) >= 1
                ORDER BY l.created_at DESC
                LIMIT 100
            )
            {pgvec_pool_sql}
        ),
        -- Host kalitesi: son 30 gündeki ortalama yayın süresi (2 saat = tam puan)
        host_quality AS (
            SELECT host_id,
                   LEAST(
                       AVG(EXTRACT(EPOCH FROM (ended_at - started_at))),
                       7200
                   ) / 7200.0 AS quality
            FROM live_streams
            WHERE ended_at IS NOT NULL
              AND started_at IS NOT NULL
              AND started_at > NOW() - INTERVAL '30 days'
            GROUP BY host_id
        ),
        -- Satıcı conversion oranı: son 30 gündeki kazanılan / toplam açık artırma
        seller_conv AS (
            SELECT li.user_id AS seller_id,
                   COUNT(CASE WHEN a.winner_id IS NOT NULL THEN 1 END)::float /
                   NULLIF(COUNT(*), 0) AS conv_rate
            FROM auctions a
            INNER JOIN listings li ON li.id = a.listing_id
            WHERE a.ended_at > NOW() - INTERVAL '30 days'
            GROUP BY li.user_id
        ),
        scored AS (
            SELECT
                l.id,
                l.category,
                (
                    ({cat_affinity_expr}) * {cat_w}
                    + {pgvec_score_term}
                    + LEAST(LOG(1.0 + COALESCE(lk.like_count, 0)) / 5.0, 1.0) * {quality_w}
                    + EXP(-EXTRACT(EPOCH FROM (NOW() - l.created_at)) / 604800.0) * {freshness_w}
                    + COALESCE(soc.is_followed, 0.0) * {social_w}
                    + ({exploration_expr}) * {explore_w}
                    + (ABS(HASHTEXT(l.id::text || :seed)::float / 2147483647.0)) * 0.02
                    - COALESCE(imp.seen_decay, 0.0) * {seen_w}
                    + COALESCE(hq.quality, 0.0) * {host_w}
                    + COALESCE(sc.conv_rate, 0.0) * {conv_w}
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
                SELECT listing_id,
                       GREATEST(0.0, 1.0 - EXTRACT(EPOCH FROM (NOW() - seen_at)) / (30.0 * 86400)) AS seen_decay
                FROM listing_impressions
                WHERE user_id = :uid
                  AND seen_at > NOW() - INTERVAL '30 days'
            ) imp ON imp.listing_id = l.id
            LEFT JOIN host_quality hq ON hq.host_id = l.user_id
            LEFT JOIN seller_conv sc ON sc.seller_id = l.user_id
        ),
        -- Çeşitlilik kısıtı: bir kategoriden maksimum 3 ilan
        diversified AS (
            SELECT id, feed_score,
                   ROW_NUMBER() OVER (PARTITION BY category ORDER BY feed_score DESC) AS cat_rank
            FROM scored
        )
        SELECT id
        FROM diversified
        WHERE cat_rank <= 3
        ORDER BY feed_score DESC
        LIMIT :lim OFFSET :off
    """)

    result = await db.execute(sql, params)
    return [row.id for row in result]


async def _popular_feed(offset: int, limit: int, db: AsyncSession, exclude_user_id: int | None = None) -> list[int]:
    """Cold start ve misafir kullanıcılar için en popüler ilanlar.

    Önce son 180 günde dener; sonuç boşsa tüm zamanlara genişler.
    """
    uid_filter = "AND l.user_id != :uid" if exclude_user_id else ""
    params: dict = {"lim": limit, "off": offset}
    if exclude_user_id:
        params["uid"] = exclude_user_id

    for interval in ("180 days", None):
        date_filter = f"AND l.created_at > NOW() - INTERVAL '{interval}'" if interval else ""
        result = await db.execute(
            text(f"""
                SELECT l.id
                FROM listings l
                LEFT JOIN listing_likes ll ON ll.listing_id = l.id
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  {date_filter}
                  {uid_filter}
                GROUP BY l.id
                ORDER BY COUNT(ll.id) DESC, l.created_at DESC
                LIMIT :lim OFFSET :off
            """),
            params,
        )
        ids = [row.id for row in result]
        if ids:
            return ids
    return []


async def _mark_impressions(user_id: int, listing_ids: list[int], db: AsyncSession) -> None:
    """Gösterilen ilanları listing_impressions tablosuna yazar (upsert)."""
    if not listing_ids:
        return
    await db.execute(
        text("""
            INSERT INTO listing_impressions (user_id, listing_id)
            VALUES (:uid, :lid)
            ON CONFLICT (user_id, listing_id) DO UPDATE SET seen_at = NOW()
        """),
        [{"uid": user_id, "lid": lid} for lid in listing_ids],
    )
    await db.commit()


# ── For-You Feed (pgvector cosine distance) ──────────────────────────────────

FORYOU_CACHE_TTL = 3600   # 1 saat — badge tutarlılığı için mobile cache'den uzun
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

    # Kendi ilanıysa impression_count al
    impression_map: dict[int, int] = {}
    if user_id and listing_ids:
        from sqlalchemy import func
        from app.models.listing_impression import ListingImpression
        my_listing_ids = [lid for lid in listing_ids if lid in rows and rows[lid][1].id == user_id]
        if my_listing_ids:
            imp_result = await db.execute(
                select(ListingImpression.listing_id, func.count())
                .select_from(ListingImpression)
                .where(ListingImpression.listing_id.in_(my_listing_ids))
                .group_by(ListingImpression.listing_id)
            )
            for lid, imp_count in imp_result.all():
                impression_map[lid] = imp_count

    foryou_uids = list({rows[lid][1].id for lid in listing_ids if lid in rows})
    badge_map_fy, trending_cats_fy = await _fetch_seller_meta(foryou_uids)

    result = []
    for lid in listing_ids:
        if lid not in rows:
            continue
        listing, user = rows[lid]
        result.append(_row_dict(
            listing, user, counts.get(lid, 0), lid in liked_set,
            seller_badge=badge_map_fy.get(user.id),
            is_trending=listing.category in trending_cats_fy,
            impression_count=impression_map.get(lid, 0) if user.id == user_id else None
        ))

    # Organik ilanları listing_impressions'a yaz (sponsored hariç)
    organic_ids = [r["id"] for r in result]
    if organic_ids:
        try:
            await _mark_impressions(user_id, organic_ids, db)
        except Exception as exc:
            logger.warning("[ForYou] Impression yazılamadı: %s", exc)

    # Sponsored ilan enjeksiyonu — sadece ilk sayfa
    if page == 0:
        try:
            ad_items = await _get_sponsored_listings(db, user_id=user_id, exclude_user_id=user_id)
            result = _inject_ads(result, ad_items)
        except Exception as exc:
            logger.warning("[Feed] Sponsored enjeksiyonu atlandı: %s", exc)

    return result


async def _compute_foryou_ids(user_id: int, db: AsyncSession, limit: int) -> list[int]:
    """
    Kullanıcının preference_embedding'ine en yakın ilan ID'lerini döndürür.

    Strateji:
      - pgvector pool (semantic, limit*2 aday) + sosyal pool (takip edilen satıcılar, 30 aday)
      - SQL re-ranking: pgvec_sim × 0.45 + freshness × 0.15 + social × 0.12 + quality × 0.10 − seen × 0.20
      - Python ALS blending: sql_score × 0.80 + als_score × 0.20 (ALS vektörü varsa)
      - 'not_interested' Redis seti hariç tutulur.
      - max_budget varsa price <= max_budget × 1.2 filtresi uygulanır.
      - Son 3 günde görülen ilanlar yumuşak cezalandırılır (hard filter değil).
      - Embedding yoksa cold start (popüler ilanlar).
    """
    redis = await get_redis()
    user = await db.scalar(select(User).where(User.id == user_id))

    if user is None or user.preference_embedding is None:
        return await _popular_feed(0, limit, db, exclude_user_id=user_id)

    # Session-içi drift: mevcut oturum vektörüyle preference_embedding'i harmanlayın
    pref_vec = np.array(user.preference_embedding, dtype=np.float32)
    try:
        session_b64 = await redis.get(f"feed:session:{user_id}")
    except Exception:
        # decode_responses=True olan client raw binary key'i UTF-8 olarak decode edemez
        session_b64 = None
        await redis.delete(f"feed:session:{user_id}")
    sess_vec = np.array([], dtype=np.float32)
    if session_b64:
        try:
            sess_vec = np.frombuffer(base64.b64decode(session_b64), dtype=np.float32)
        except Exception:
            sess_vec = np.array([], dtype=np.float32)
    if session_b64 and sess_vec.shape == pref_vec.shape:
        blended = pref_vec * 0.70 + sess_vec * 0.30
        bn = np.linalg.norm(blended)
        if bn > 0:
            blended /= bn
        pref_vec = blended

    vec_str = "[" + ",".join(f"{x:.8f}" for x in pref_vec.tolist()) + "]"

    # not_interested filtresi (Redis)
    excluded_raw = await redis.smembers(f"not_interested:{user_id}")
    excluded_ids = [int(x) for x in excluded_raw] if excluded_raw else []
    ni_filter = f"AND l.id NOT IN ({','.join(str(i) for i in excluded_ids)})" if excluded_ids else ""

    # Bütçe filtresi (max_budget × 1.2 tolerans)
    budget_clause = ""
    params: dict = {
        "uid": user_id,
        "vec": vec_str,
        "lim": limit,
        "pgvec_lim": limit * 2,
    }
    if user.max_budget is not None:
        budget_clause = "AND (l.price IS NULL OR l.price <= :price_ceiling)"
        params["price_ceiling"] = user.max_budget * 1.2

    # SQL: candidate pool + temel skorlama — diversity için limit*3 aday çek
    diverse_lim = limit * 3
    params["diverse_lim"] = diverse_lim

    result = await db.execute(
        text(f"""
            WITH pgvec_pool AS (
                SELECT l.id,
                       (1.0 - (l.embedding <=> CAST(:vec AS vector))) AS sim_score
                FROM listings l
                WHERE l.is_active = TRUE
                  AND l.is_deleted = FALSE
                  AND l.embedding IS NOT NULL
                  AND l.user_id != :uid
                  {ni_filter}
                  {budget_clause}
                ORDER BY l.embedding <=> CAST(:vec AS vector)
                LIMIT :pgvec_lim
            ),
            social_pool AS (
                SELECT l.id, 0.0 AS sim_score
                FROM listings l
                INNER JOIN follows f ON f.followed_id = l.user_id AND f.follower_id = :uid
                WHERE l.is_active = TRUE AND l.is_deleted = FALSE
                  AND l.user_id != :uid
                  {ni_filter}
                  {budget_clause}
                ORDER BY l.created_at DESC
                LIMIT 30
            ),
            all_candidates AS (
                SELECT id, MAX(sim_score) AS sim_score
                FROM (
                    SELECT id, sim_score FROM pgvec_pool
                    UNION ALL
                    SELECT id, sim_score FROM social_pool
                ) combined
                GROUP BY id
            ),
            scored AS (
                SELECT
                    c.id,
                    l.category,
                    c.sim_score * 0.45
                    + EXP(-EXTRACT(EPOCH FROM (NOW() - l.created_at)) / 1209600.0) * 0.15
                    + COALESCE(soc.social_bonus, 0.0) * 0.12
                    + LEAST(LOG(1.0 + COALESCE(lk.like_count, 0)) / 5.0, 1.0) * 0.10
                    - COALESCE(imp.seen_decay, 0.0) * 0.20
                    AS sql_score
                FROM all_candidates c
                INNER JOIN listings l ON l.id = c.id
                LEFT JOIN (
                    SELECT listing_id, COUNT(*) AS like_count
                    FROM listing_likes GROUP BY listing_id
                ) lk ON lk.listing_id = c.id
                LEFT JOIN (
                    SELECT DISTINCT l2.id, 1.0 AS social_bonus
                    FROM listings l2
                    INNER JOIN follows f ON f.followed_id = l2.user_id AND f.follower_id = :uid
                ) soc ON soc.id = c.id
                LEFT JOIN (
                    SELECT listing_id,
                           GREATEST(0.0, 1.0 - EXTRACT(EPOCH FROM (NOW() - seen_at)) / (30.0 * 86400)) AS seen_decay
                    FROM listing_impressions
                    WHERE user_id = :uid
                      AND seen_at > NOW() - INTERVAL '30 days'
                ) imp ON imp.listing_id = c.id
            )
            SELECT id, category, sql_score FROM scored
            ORDER BY sql_score DESC
            LIMIT :diverse_lim
        """),
        params,
    )
    rows = result.all()

    if not rows:
        return await _popular_feed(0, limit, db, exclude_user_id=user_id)

    cat_map: dict[int, str] = {r.id: (r.category or "") for r in rows}
    candidate_ids = list(dict.fromkeys(r.id for r in rows))
    sql_scores: dict[int, float] = {r.id: float(r.sql_score) for r in rows}

    # ALS blending — her iki skoru [0,1] normalize et, sonra ağırlıklı topla
    try:
        als_scores = await get_als_scores(user_id, candidate_ids)
    except Exception as exc:
        logger.warning("[ForYou] ALS skorları alınamadı, atlanıyor: %s", exc)
        als_scores = {}

    if als_scores:
        sql_vals = list(sql_scores.values())
        sql_min, sql_max = min(sql_vals), max(sql_vals)
        sql_range = sql_max - sql_min or 1.0
        norm_sql = {k: (v - sql_min) / sql_range for k, v in sql_scores.items()}

        als_vals = list(als_scores.values())
        als_min, als_max = min(als_vals), max(als_vals)
        als_range = als_max - als_min or 1.0
        norm_als = {k: (v - als_min) / als_range for k, v in als_scores.items()}

        final_scores = {
            lid: norm_sql.get(lid, 0.0) * 0.80 + norm_als.get(lid, 0.0) * 0.20
            for lid in candidate_ids
        }
    else:
        final_scores = sql_scores

    # Greedy kategori çeşitliliği: her kategoriden max 4 ilan
    MAX_PER_CAT = 4
    sorted_ids = sorted(candidate_ids, key=lambda lid: final_scores[lid], reverse=True)
    cat_counts: dict[str, int] = {}
    diverse_ids: list[int] = []
    overflow_ids: list[int] = []
    for lid in sorted_ids:
        cat = cat_map.get(lid, "")
        if cat_counts.get(cat, 0) < MAX_PER_CAT:
            diverse_ids.append(lid)
            cat_counts[cat] = cat_counts.get(cat, 0) + 1
        else:
            overflow_ids.append(lid)
        if len(diverse_ids) >= limit:
            break
    # Yeterli çeşitli ilan bulunamazsa skoru yüksek overflow'dan tamamla
    if len(diverse_ids) < limit:
        diverse_ids.extend(overflow_ids[: limit - len(diverse_ids)])

    return diverse_ids[:limit]


# ── Sponsored İlan Enjeksiyonu ────────────────────────────────────────────────

_AD_FREQ_CAP = 3        # bir kullanıcı aynı reklamı 24 saatte max 3 kez görür
_AD_FREQ_TTL = 86400    # saniye (24 saat)
_CAT_MATCH_BOOST = 2.5  # kullanıcı ilgi kategorisiyle örtüşen reklama skor çarpanı


async def _get_user_top_categories(user_id: int, db: AsyncSession, n: int = 5) -> list[str]:
    """Kullanıcının son 30 gündeki izlenim geçmişinden en çok ilgi duyduğu kategorileri döndürür.
    Sonuç 1 saat Redis'te önbelleklenir."""
    redis = await get_redis()
    cache_key = f"user_top_cats:{user_id}"
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    result = await db.execute(
        text("""
            SELECT l.category, COUNT(*) AS cnt
            FROM listing_impressions li
            JOIN listings l ON l.id = li.listing_id
            WHERE li.user_id = :uid
              AND li.seen_at > NOW() - INTERVAL '30 days'
              AND l.is_deleted = FALSE
            GROUP BY l.category
            ORDER BY cnt DESC
            LIMIT :n
        """),
        {"uid": user_id, "n": n},
    )
    cats = [row.category for row in result]
    if cats:
        await redis.set(cache_key, json.dumps(cats), ex=3600)
    return cats


async def _get_sponsored_listings(
    db: AsyncSession,
    user_id: int | None = None,
    exclude_user_id: int | None = None,
) -> list[dict]:
    """
    Kullanıcıya özel, frekans-kısıtlı ve kategori-hedefli sponsored ilan seçimi.

    1. Redis'teki aktif kampanyaları tarar.
    2. Aynı kullanıcıya aynı reklamı 24 saatte _AD_FREQ_CAP kereden fazla göstermez.
    3. Kullanıcının son 30 günlük kategori geçmişiyle örtüşen reklamlara _CAT_MATCH_BOOST çarpanı uygular.
    4. 80% exploit (en yüksek skor) + 20% keşif (rastgele) ile slot'ları doldurur.
    """
    redis = await get_redis()

    campaign_ids: list[int] = []
    async for key in redis.scan_iter("ad_campaign_budget:*", count=100):
        try:
            campaign_ids.append(int(key.split(":")[-1]))
        except (ValueError, IndexError):
            continue
        if len(campaign_ids) >= 50:
            break

    if not campaign_ids:
        return []

    # Kampanya meta verilerini çek
    rows = await db.execute(
        select(AdCampaign, Listing, User)
        .join(Listing, Listing.id == AdCampaign.listing_id)
        .join(User, User.id == Listing.user_id)
        .where(
            AdCampaign.id.in_(campaign_ids),
            AdCampaign.status == "active",
            Listing.is_active == True,   # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
            *([Listing.user_id != exclude_user_id] if exclude_user_id else []),
        )
    )
    candidates = rows.all()
    if not candidates:
        return []

    # ── Frekans kısıtı (frequency cap) ──────────────────────────────────────
    if user_id:
        freq_keys = [f"ad_freq:{user_id}:{c.id}" for c, _, _ in candidates]
        counts = await redis.mget(*freq_keys)
        candidates = [
            row for row, cnt in zip(candidates, counts)
            if cnt is None or int(cnt) < _AD_FREQ_CAP
        ]
        if not candidates:
            return []

    # ── Kullanıcı ilgi kategorileri ──────────────────────────────────────────
    user_cats: set[str] = set()
    if user_id:
        try:
            user_cats = set(await _get_user_top_categories(user_id, db))
        except Exception:
            pass

    # ── Skor hesaplama: cpc_bid × kategori eşleşme çarpanı ──────────────────
    def _ad_score(campaign: AdCampaign, listing: Listing) -> float:
        score = float(campaign.cpc_bid)
        if user_cats and listing.category in user_cats:
            score *= _CAT_MATCH_BOOST
        return score

    scored = sorted(candidates, key=lambda t: _ad_score(t[0], t[1]), reverse=True)

    # ── 80% exploit + 20% keşif ──────────────────────────────────────────────
    n_slots = len(AD_SLOTS)
    n_exploit = max(1, int(n_slots * 0.8))
    top = scored[:n_exploit]
    rest = scored[n_exploit:]
    n_explore = n_slots - len(top)
    if rest and n_explore > 0:
        explore = random.sample(rest, min(n_explore, len(rest)))
        selected_rows = top + explore
    else:
        selected_rows = top

    sponsor_uids = [user.id for _, _, user in selected_rows[:n_slots]]
    badge_map_sp, trending_cats_sp = await _fetch_seller_meta(sponsor_uids)

    return [
        _row_dict(
            listing, user, 0, False,
            is_sponsored=True,
            campaign_id=campaign.id,
            seller_badge=badge_map_sp.get(user.id),
            is_trending=listing.category in trending_cats_sp,
        )
        for campaign, listing, user in selected_rows[:n_slots]
    ]


def _inject_ads(organic: list[dict], ads: list[dict]) -> list[dict]:
    """
    Sponsored item'ları organik feed'e AD_SLOTS pozisyonlarına enjekte eder.
    Aynı ilan organik listede zaten varsa önce oradan çıkarılır; böylece ilan
    tek görünür ama is_sponsored=True / campaign_id bilgisiyle (sponsored versiyonu).
    """
    if not ads:
        return organic
    ad_ids = {ad["id"] for ad in ads}
    result = [item for item in organic if item["id"] not in ad_ids]
    for i, ad in enumerate(ads):
        if i >= len(AD_SLOTS):
            break
        pos = min(AD_SLOTS[i] + i, len(result))
        result.insert(pos, ad)
    return result


# ── Son İlanlar — Karışık Feed ────────────────────────────────────────────────

_RECENT_PAGE_SIZE = 20
_INTEREST_SLOTS   = [5, 10, 15]   # ilgi enjeksiyonu pozisyonları (0-indexed, insert)


async def get_mixed_recent_feed(
    user_id: Optional[int],
    page: int,
    db: AsyncSession,
) -> list[dict]:
    """
    'Son İlanlar' karışık feed.

    Base: en son eklenen ilanlar (created_at DESC), sayfalama.
    Enjeksiyonlar:
      - pos 5, 10, 15 → kullanıcı ilgi kategorilerinden birer ilan
      - pos 2, 7, 12  → sponsored (yalnızca page 0, mevcut _inject_ads mantığıyla)
    """
    offset = page * _RECENT_PAGE_SIZE
    params: dict = {"lim": _RECENT_PAGE_SIZE, "off": offset}

    base_result = await db.execute(
        text(f"""
            SELECT l.id
            FROM listings l
            WHERE l.is_active = TRUE
              AND l.is_deleted = FALSE
            ORDER BY l.created_at DESC
            LIMIT :lim OFFSET :off
        """),
        params,
    )
    base_ids = [r.id for r in base_result]
    if not base_ids:
        return []

    rows_result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.id.in_(base_ids),
            Listing.is_active == True,    # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
        )
    )
    rows = {listing.id: (listing, user) for listing, user in rows_result.all()}
    counts, liked_set = await LikeService.batch_listing_likes(db, base_ids, user_id)

    recent_uids = list({rows[lid][1].id for lid in base_ids if lid in rows})
    badge_map_r, trending_cats_r = await _fetch_seller_meta(recent_uids)

    result = [
        _row_dict(listing, user, counts.get(lid, 0), lid in liked_set,
                  seller_badge=badge_map_r.get(user.id),
                  is_trending=listing.category in trending_cats_r)
        for lid in base_ids
        if lid in rows
        for listing, user in [rows[lid]]
    ]

    # ── İlgi enjeksiyonu (tüm sayfalar) ──────────────────────────────────────
    if user_id:
        interests = await get_user_interests(user_id, db)
        if interests:
            top_cats = list(interests.keys())[:3]
            interest_items = await _fetch_interest_items(
                user_id, top_cats, base_ids, len(_INTEREST_SLOTS), db
            )
            result = _inject_at_slots(result, interest_items, _INTEREST_SLOTS)

    # Organik + interest ilan izlenimlerini kaydet (sponsored hariç)
    if user_id:
        organic_ids = [r["id"] for r in result]
        if organic_ids:
            try:
                await _mark_impressions(user_id, organic_ids, db)
            except Exception as exc:
                logger.warning("[MixedRecent] Impression yazılamadı: %s", exc)

    # ── Sponsored enjeksiyonu (yalnızca page 0) ───────────────────────────────
    if page == 0:
        try:
            ad_items = await _get_sponsored_listings(db, user_id=user_id, exclude_user_id=user_id)
            result = _inject_ads(result, ad_items)
        except Exception as exc:
            logger.warning("[MixedRecent] Sponsored enjeksiyonu atlandı: %s", exc)

    return result


async def _fetch_interest_items(
    user_id: int,
    categories: list[str],
    exclude_ids: list[int],
    count: int,
    db: AsyncSession,
) -> list[dict]:
    """Kullanıcının ilgi kategorilerinden, base listesinde olmayan ilanlar."""
    excl = f"AND l.id NOT IN ({','.join(str(i) for i in exclude_ids)})" if exclude_ids else ""
    res = await db.execute(
        text(f"""
            SELECT l.id FROM listings l
            WHERE l.is_active = TRUE
              AND l.is_deleted = FALSE
              AND l.category = ANY(:cats)
              {excl}
            ORDER BY RANDOM()
            LIMIT :lim
        """),
        {"cats": categories, "lim": count},
    )
    ids = [r.id for r in res]
    if not ids:
        return []

    rows_result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.id.in_(ids),
            Listing.is_active == True,    # noqa: E712
            Listing.is_deleted == False,  # noqa: E712
        )
    )
    rows = {listing.id: (listing, user) for listing, user in rows_result.all()}
    counts, liked_set = await LikeService.batch_listing_likes(db, ids, user_id)

    interest_uids = list({rows[lid][1].id for lid in ids if lid in rows})
    badge_map_i, trending_cats_i = await _fetch_seller_meta(interest_uids)

    return [
        _row_dict(listing, user, counts.get(lid, 0), lid in liked_set,
                  seller_badge=badge_map_i.get(user.id),
                  is_trending=listing.category in trending_cats_i)
        for lid in ids
        if lid in rows
        for listing, user in [rows[lid]]
    ]


def _inject_at_slots(organic: list[dict], items: list[dict], slots: list[int]) -> list[dict]:
    """items'ı slots pozisyonlarına enjekte eder; önceki insertlerin kaydırmasını hesaba katar."""
    if not items:
        return organic
    result = list(organic)
    for i, item in enumerate(items):
        if i >= len(slots):
            break
        pos = min(slots[i] + i, len(result))
        result.insert(pos, item)
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
