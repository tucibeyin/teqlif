"""
SwipeLive Kişiselleştirme Servisi

Kullanıcıya özel SwipeLive konfigürasyonu üretir:
  1. Yayınları kullanıcı ilgi skorlarına + ClickHouse geçmiş davranışına göre sıralar
  2. Yayınlar arası gösterilecek ilan sayısını (0-3) geçmiş etkileşim verisinden hesaplar
  3. Tercih edilen ilan kategorilerini döndürür (listing pool filtrelemesi için)

Algoritma ağırlıkları:
  category_affinity  × 0.40  (UserInterest tablosundan)
  stream_quality     × 0.25  (izleyici sayısı + like sayısı)
  ch_engagement      × 0.20  (swipe_live_events: dwell/skip oranı)
  recency            × 0.15  (yayın ne kadar süredir aktif — yeni yayın önce)

Sonuç Redis'te 5 dakika önbelleklenir.
"""
from __future__ import annotations

import json
import logging
import math
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.database_clickhouse import get_clickhouse_client
from app.services.feed_service import get_user_interests
from app.services.stream_service import StreamService
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

CONFIG_CACHE_TTL = 300   # 5 dakika
AFFINITY_CACHE_TTL = 900  # 15 dakika (worker tarafından yazılır)

# ----------------------------  PUBLIC API  -----------------------------------


async def get_swipe_live_config(user_id: int, db: AsyncSession) -> dict:
    """
    Kullanıcıya özel SwipeLive konfigürasyonunu döndürür.
    Sonuç Redis'te önbelleklenir.
    """
    redis = await get_redis()
    cache_key = f"swivelive_cfg:{user_id}"
    cached = await redis.get(cache_key)
    if cached:
        return json.loads(cached)

    config = await _build_config(user_id, db)
    await redis.setex(cache_key, CONFIG_CACHE_TTL, json.dumps(config))
    return config


async def invalidate_config_cache(user_id: int) -> None:
    """Worker veya event handler config cache'ini sıfırladığında çağrılır."""
    redis = await get_redis()
    await redis.delete(f"swivelive_cfg:{user_id}")


# ----------------------------  INTERNAL  ------------------------------------


async def _build_config(user_id: int, db: AsyncSession) -> dict:
    # 1. Aktif yayınları çek
    streams = await StreamService(db).get_active_streams(user_id)

    # 2. Kategori ilgi skorları (feed_service ile aynı kaynak)
    interests: dict[str, float] = await get_user_interests(user_id, db)

    # 3. ClickHouse'dan geçmiş SwipeLive etkileşimi
    ch_engagement = await _fetch_ch_stream_engagement(user_id)
    listing_engagement = await _fetch_ch_listing_engagement(user_id)

    # 4. Yayınları skorla ve sırala
    scored = []
    prev_category: str | None = None
    for stream in streams:
        score = _score_stream(stream, interests, ch_engagement, prev_category)
        scored.append((score, stream))

    scored.sort(key=lambda x: -x[0])
    ranked_streams = [s for _, s in scored]
    if ranked_streams:
        prev_category = ranked_streams[0].category

    # 5. listings_per_group hesapla
    lpg = _compute_listings_per_group(listing_engagement)

    # 6. Kullanıcının tercih ettiği ilan kategorileri (ilgi skoruna göre top-3)
    preferred_cats = [
        cat for cat, _ in sorted(interests.items(), key=lambda x: -x[1])[:3]
    ]

    # Serialization için stream'leri dict'e çevir
    stream_dicts = []
    for s in ranked_streams:
        stream_dicts.append({
            "id": s.id,
            "room_name": s.room_name,
            "title": s.title,
            "category": s.category,
            "viewer_count": getattr(s, "viewer_count", 0),
            "started_at": s.started_at.isoformat(),
            "thumbnail_url": s.thumbnail_url,
            "likes_count": getattr(s, "likes_count", 0),
            "host": {
                "id": s.host.id,
                "username": s.host.username,
                "full_name": s.host.full_name,
                "profile_image_url": getattr(s.host, "profile_image_url", None),
            },
        })

    return {
        "streams": stream_dicts,
        "listings_per_group": lpg,
        "preferred_listing_categories": preferred_cats,
    }


def _score_stream(
    stream,
    interests: dict[str, float],
    ch_engagement: dict[int, dict],
    prev_category: str | None,
) -> float:
    # 1. Category affinity
    affinity = interests.get(stream.category, 0.05)
    affinity = min(affinity, 1.0)

    # 2. Stream quality (log-normalized viewer count + like count)
    viewer_score = math.log1p(getattr(stream, "viewer_count", 0)) / 10.0
    like_score = math.log1p(getattr(stream, "likes_count", 0)) / 8.0
    quality = min((viewer_score + like_score) / 2.0, 1.0)

    # 3. ClickHouse geçmiş etkileşimi
    eng = ch_engagement.get(stream.id, {})
    ch_score = eng.get("engagement_score", 0.0)

    # 4. Yenilik (son 2 saatte başlamış yayınlara bonus)
    now = datetime.now(timezone.utc)
    started = stream.started_at
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    age_hours = (now - started).total_seconds() / 3600.0
    recency = max(0.0, 1.0 - age_hours / 2.0)

    # 5. Çeşitlilik bonusu — önceki yayınla aynı kategoriyse ceza
    diversity = 0.0 if stream.category == prev_category else 0.1

    return (
        affinity  * 0.40
        + quality * 0.25
        + ch_score * 0.20
        + recency  * 0.15
        + diversity
    )


def _compute_listings_per_group(listing_engagement: dict) -> int:
    """
    Kullanıcının SwipeLive'daki listing tıklama oranına göre
    yayınlar arası gösterilecek ilan sayısını hesaplar (0-3).

    Yüksek CTR → kullanıcı ilanlara ilgili → daha fazla göster
    Düşük CTR  → ilanlara ilgisiz → az göster (yayına odaklan)
    Veri yoksa → 2 (varsayılan)
    """
    clicks = listing_engagement.get("clicks", 0)
    impressions = listing_engagement.get("impressions", 0)

    if impressions < 5:
        return 2  # soğuk başlangıç

    ctr = clicks / impressions
    if ctr >= 0.15:
        return 3
    if ctr >= 0.08:
        return 2
    if ctr >= 0.03:
        return 1
    return 0


# ----------------------------  CLICKHOUSE QUERIES  --------------------------


async def _fetch_ch_stream_engagement(user_id: int) -> dict[int, dict]:
    """
    Son 30 günde kullanıcının her yayınla etkileşimini döndürür.
    stream_id → { engagement_score: float }
    """
    try:
        ch = await get_clickhouse_client()
        result = await ch.query(
            """
            SELECT
                stream_id,
                countIf(event_type = 'dwell')   AS dwells,
                countIf(event_type = 'skip')    AS skips,
                avgIf(dwell_ms, event_type = 'dwell') AS avg_dwell
            FROM swipe_live_events
            WHERE user_id = {uid:UInt32}
              AND timestamp >= now() - INTERVAL 30 DAY
              AND stream_id > 0
            GROUP BY stream_id
            """,
            parameters={"uid": user_id},
        )
        out: dict[int, dict] = {}
        for row in result.result_rows:
            sid, dwells, skips, avg_dwell = row
            # Basit engagement score: dwell kalitesi - skip cezası
            total = dwells + skips
            if total == 0:
                score = 0.0
            else:
                dwell_ratio = dwells / total
                quality = min(avg_dwell / 15000.0, 1.0)  # 15s üzeri tam puan
                score = dwell_ratio * quality
            out[int(sid)] = {"engagement_score": round(score, 4)}
        return out
    except Exception as exc:
        logger.debug("[SwipeLive] _fetch_ch_stream_engagement başarısız: %s", exc)
        return {}


async def _fetch_ch_listing_engagement(user_id: int) -> dict:
    """
    Son 30 günde kullanıcının SwipeLive içi listing tıklama/impression verisini döndürür.
    Hem feed_analytics (genel feed) hem swipe_live_events (SwipeLive içi) birleştirilir.
    """
    try:
        ch = await get_clickhouse_client()

        # swipe_live_events'ten (listing eventleri)
        r1 = await ch.query(
            """
            SELECT
                countIf(event_type = 'listing_tap')        AS clicks,
                countIf(event_type = 'listing_impression') AS impressions
            FROM swipe_live_events
            WHERE user_id = {uid:UInt32}
              AND timestamp >= now() - INTERVAL 30 DAY
              AND listing_id > 0
            """,
            parameters={"uid": user_id},
        )
        row1 = r1.result_rows[0] if r1.result_rows else (0, 0)

        # feed_analytics'ten (genel listing feed)
        r2 = await ch.query(
            """
            SELECT
                countIf(event_type = 'click')       AS clicks,
                countIf(event_type = 'impression')  AS impressions
            FROM feed_analytics
            WHERE user_id = {uid:String}
              AND timestamp >= now() - INTERVAL 30 DAY
              AND content_type IN ('listing', 'listing_video')
            """,
            parameters={"uid": str(user_id)},
        )
        row2 = r2.result_rows[0] if r2.result_rows else (0, 0)

        return {
            "clicks":      (row1[0] or 0) + (row2[0] or 0),
            "impressions": (row1[1] or 0) + (row2[1] or 0),
        }
    except Exception as exc:
        logger.debug("[SwipeLive] _fetch_ch_listing_engagement başarısız: %s", exc)
        return {}
