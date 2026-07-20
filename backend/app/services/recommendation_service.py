"""
Recommendation Service — ClickHouse telemetri verisinden Thompson Sampling kişiselleştirilmiş feed.

Akış:
  1. get_user_category_affinity():
       ClickHouse feed_analytics → listing bazlı affinity skoru
       → PostgreSQL'den category bilgisi → kategori skorlarını topla → top-N
  2. get_personalized_feed():
       Affinity boşsa → cold start (popüler ilanlar)
       Affinity varsa → Thompson Sampling ile kategori seçimi
         Her kategori için Beta(α, β) örneklenir; en yüksek örnekten kategori seçilir.
         Explore kategoriler Beta(1, 5) ile az ama sıfır olmayan olasılıkta seçilir.

Puanlama (son 7 gün):
  click              → +5
  impression + dwell_time_ms > 3000ms → +2
  skip               → -2
"""
from __future__ import annotations

import json
import logging
import random
from typing import Optional

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import ListingStatus
from app.database_clickhouse import get_clickhouse_client
from app.models.listing import Listing
from app.models.user import User
from app.services.listing_service import _row_dict
from app.services.like_service import LikeService
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

_AFFINITY_CACHE_TTL = 900   # 15 dakika
_AFFINITY_DAYS = 7


async def get_user_category_affinity(
    user_id: int,
    db: AsyncSession,
    top_n: int = 3,
) -> dict[str, float]:
    """
    ClickHouse feed_analytics üzerinden kategori affinite profili döndürür.

    Döndürür: {category: normalized_score, ...} — en yüksek top_n kategori.
    ClickHouse erişilemezse boş dict döner (graceful degradation).
    """
    redis = await get_redis()
    cache_key = f"ch_affinity:{user_id}"
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    # ── 1. ClickHouse: listing bazlı davranış skorları ───────────────────────
    try:
        ch = await get_clickhouse_client()
        if ch is None:
            return {}
    except Exception as exc:
        logger.warning("[RecSvc] ClickHouse bağlanamadı: %s", exc)
        return {}

    uid_str = str(user_id)
    # Position bias düzeltmesi: üst slotlarda görünen ilanlar daha kolay tıklanır.
    # log2(slot_index + 2) ile tıklamaları normalize ediyoruz — alt slottaki tıklama daha değerli.
    ch_query = f"""
        SELECT
            listing_id,
            SUM(
                CASE
                    WHEN event_type = 'click'
                        THEN 5 * log2(toFloat64(slot_index) + 2.0)
                    WHEN event_type = 'impression' AND dwell_time_ms > 3000
                        THEN 2
                    WHEN event_type = 'skip'
                        THEN -2
                    ELSE 0
                END
            ) AS score
        FROM feed_analytics
        WHERE user_id = '{uid_str}'
          AND timestamp >= now() - INTERVAL {_AFFINITY_DAYS} DAY
        GROUP BY listing_id
        HAVING score > 0
        ORDER BY score DESC
        LIMIT 100
    """

    try:
        result = await ch.query(ch_query)
        rows = result.result_rows  # [(listing_id_str, score), ...]
    except Exception as exc:
        logger.warning("[RecSvc] ClickHouse affinity sorgusu başarısız: %s", exc)
        return {}

    if not rows:
        return {}

    # ── 2. PostgreSQL: listing_id → category eşleştirmesi ────────────────────
    score_by_listing: dict[int, float] = {}
    for lid_str, score in rows:
        try:
            lid = int(lid_str)
            score_by_listing[lid] = float(score)
        except (ValueError, TypeError):
            continue

    if not score_by_listing:
        return {}

    cat_result = await db.execute(
        select(Listing.id, Listing.category).where(
            Listing.id.in_(list(score_by_listing.keys()))
        )
    )

    # ── 3. Kategori bazlı skor toplamı ───────────────────────────────────────
    category_scores: dict[str, float] = {}
    for lid, category in cat_result.all():
        if not category:
            continue
        category_scores[category] = category_scores.get(category, 0.0) + score_by_listing.get(lid, 0.0)

    if not category_scores:
        return {}

    # Normalize → en yüksek skor = 1.0; top_n kategori seç
    max_score = max(category_scores.values())
    affinity = {
        cat: round(score / max_score, 4)
        for cat, score in sorted(category_scores.items(), key=lambda x: x[1], reverse=True)[:top_n]
    }

    await redis.setex(cache_key, _AFFINITY_CACHE_TTL, json.dumps(affinity))
    return affinity


def _thompson_sample_categories(
    affinity: dict[str, float],
    all_categories: list[str],
    n_exploit: int,
    n_explore: int,
) -> tuple[list[str], list[str]]:
    """
    Thompson Sampling ile exploit ve explore kategorilerini seçer.

    Her kategori için Beta dağılımı:
      - Affinity'de varsa: Beta(α = score × 20 + 1, β = (1 - score) × 20 + 1)
      - Affinity'de yoksa:  Beta(1, 5) — düşük ama sıfır olmayan keşif olasılığı

    En yüksek n_exploit örneği → exploit kategorileri
    Kalan yüksekler veya keşif havuzu → explore kategorileri
    """
    try:
        from scipy.stats import beta as beta_dist  # type: ignore
    except ImportError:
        top_cats = list(affinity.keys())[:n_exploit]
        other_cats = [c for c in all_categories if c not in set(top_cats)]
        return top_cats, other_cats[:n_explore]

    scores: dict[str, float] = {}
    for cat in all_categories:
        if cat in affinity:
            a = affinity[cat] * 20.0 + 1.0
            b = (1.0 - affinity[cat]) * 20.0 + 1.0
        else:
            a, b = 1.0, 5.0
        scores[cat] = beta_dist.rvs(a, b)

    ranked = sorted(all_categories, key=lambda c: scores[c], reverse=True)
    exploit_cats = [c for c in ranked if c in affinity][:n_exploit]
    explore_cats = [c for c in ranked if c not in set(exploit_cats)][:n_explore]
    return exploit_cats, explore_cats


async def get_personalized_feed(
    user_id: int,
    db: AsyncSession,
    limit: int = 10,
) -> list[dict]:
    """
    Thompson Sampling tabanlı kişiselleştirilmiş ilan akışı.

    - Affinity boşsa (yeni kullanıcı — cold start): son 30 günün popüler ilanları.
    - Affinity varsa:
        Thompson Sampling ile hem exploit hem explore kategorileri seçilir.
        Exploit → affinity yüksek kategorilerden; explore → diğerlerinden.
      Liste karıştırılarak döndürülür.
    """
    affinity = await get_user_category_affinity(user_id, db)

    if not affinity:
        return await _cold_start_feed(user_id, db, limit)

    # Mevcut tüm aktif kategorileri PostgreSQL'den çek (keşif havuzu için)
    cat_result = await db.execute(
        text("""
            SELECT DISTINCT category FROM listings
            WHERE status = 'active' AND category IS NOT NULL
            LIMIT 50
        """)
    )
    all_categories = [row[0] for row in cat_result.fetchall()]
    if not all_categories:
        all_categories = list(affinity.keys())

    n_exploit = round(limit * 0.80)
    n_explore = limit - n_exploit

    exploit_cats, explore_cats = _thompson_sample_categories(
        affinity, all_categories, n_exploit, n_explore
    )

    exploit_ids = await _ids_from_categories(
        user_id, db, categories=exploit_cats or list(affinity.keys()), limit=n_exploit * 4
    )
    explore_ids = await _ids_from_categories(
        user_id, db,
        categories=explore_cats if explore_cats else None,
        exclude_categories=list(affinity.keys()) if not explore_cats else None,
        limit=n_explore * 4,
    )

    random.shuffle(exploit_ids)
    random.shuffle(explore_ids)

    selected = exploit_ids[:n_exploit] + explore_ids[:n_explore]
    random.shuffle(selected)

    return await _hydrate(user_id, selected, db)


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────

async def _ids_from_categories(
    user_id: int,
    db: AsyncSession,
    *,
    categories: Optional[list[str]] = None,
    exclude_categories: Optional[list[str]] = None,
    limit: int = 40,
) -> list[int]:
    """Belirtilen kategorilerden (veya hariç) rastgele aktif ilan ID'leri döndürür."""
    clauses = [
        "l.status = 'active'",
        "l.status != 'deleted'",
        "l.user_id != :uid",
    ]
    params: dict = {"uid": user_id, "lim": limit}

    if categories:
        clauses.append("l.category = ANY(:cats)")
        params["cats"] = categories
    if exclude_categories:
        clauses.append("l.category != ALL(:excats)")
        params["excats"] = exclude_categories

    where = " AND ".join(clauses)
    result = await db.execute(
        text(f"SELECT l.id FROM listings l WHERE {where} ORDER BY RANDOM() LIMIT :lim"),
        params,
    )
    return [row.id for row in result]


async def _cold_start_feed(user_id: int, db: AsyncSession, limit: int) -> list[dict]:
    """Cold start: son 30 günün en beğenilen ilanları."""
    result = await db.execute(
        text("""
            SELECT l.id
            FROM listings l
            LEFT JOIN listing_likes ll ON ll.listing_id = l.id
            WHERE l.status = 'active'
              AND l.status != 'deleted'
              AND l.user_id != :uid
              AND l.created_at > NOW() - INTERVAL '30 days'
            GROUP BY l.id
            ORDER BY COUNT(ll.id) DESC, l.created_at DESC
            LIMIT :lim
        """),
        {"lim": limit, "uid": user_id},
    )
    ids = [row.id for row in result]
    return await _hydrate(user_id, ids, db)


async def _hydrate(user_id: int, listing_ids: list[int], db: AsyncSession) -> list[dict]:
    """ID listesini tam ilan dict'lerine çevirir (like sayısı + kullanıcı bilgisi)."""
    if not listing_ids:
        return []

    rows_result = await db.execute(
        select(Listing, User)
        .join(User, User.id == Listing.user_id)
        .where(
            Listing.id.in_(listing_ids),
            Listing.status == ListingStatus.ACTIVE,    # noqa: E712
            Listing.status != ListingStatus.DELETED,  # noqa: E712
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

    return result
