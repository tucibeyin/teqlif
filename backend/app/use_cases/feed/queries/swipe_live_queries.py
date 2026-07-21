"""
SwipeLive Kişiselleştirme Servisi

Kullanıcıya özel SwipeLive konfigürasyonu üretir:
  1. Yayınları çok sinyalli skorla sıralar
  2. Yayınlar arası gösterilecek ilan sayısını (0-3) CTR'dan hesaplar
  3. Listing-stream kategori korelasyonundan tercih edilen ilan kategorileri döndürür

Algoritma ağırlıkları:
  category_affinity   × 0.35  (UserInterest tablosundan)
  stream_quality      × 0.20  (izleyici + like)
  ch_engagement       × 0.20  (swipe_live_events dwell/skip oranı)
  als_score           × 0.15  (collaborative filtering — benzer kullanıcılar ne izledi)
  recency             × 0.10  (yeni yayın önce)
  + diversity penalty         (aynı kategori tekrar → ceza)

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
from app.use_cases.feed.queries.feed_queries import FeedQueries
from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.streams.queries.misc_queries import GetActiveStreamsQuery
from app.core.uow import SqlAlchemyUnitOfWork
from app.services.ml.swipe_live_ml import get_als_scores
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)



CONFIG_CACHE_TTL = 120   # 2 dakika (daha sık güncelleme → seans içi davranış yansır)
AFFINITY_CACHE_TTL = 900  # 15 dakika (worker tarafından yazılır)

# ----------------------------  PUBLIC API  -----------------------------------


from app.core.uow import AbstractUnitOfWork

class SwipeLiveQueries:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def get_swipe_live_config(self, user_id: int,) -> dict:
        """Kullanıcıya özel SwipeLive konfigürasyonunu döndürür (Redis önbellekli)."""
        redis = await get_redis()
        cache_key = f"swivelive_cfg:{user_id}"
        cached = await redis.get(cache_key)
        if cached:
            return json.loads(cached)

        config = await self._build_config(user_id)
        await redis.setex(cache_key, CONFIG_CACHE_TTL, json.dumps(config))
        return config


    async def invalidate_config_cache(self, user_id: int) -> None:
        redis = await get_redis()
        await redis.delete(f"swivelive_cfg:{user_id}")


    # ----------------------------  INTERNAL  ------------------------------------


    async def _build_config(self, user_id: int,) -> dict:
        # 1. Aktif yayınlar
        from app.use_cases.streams.queries.misc_queries import GetActiveStreamsQuery
        streams = await GetActiveStreamsQuery(self.uow).execute(user_id)

        # 2. Kategori ilgi skorları
        interests: dict[str, float] = await FeedQueries(self.uow).get_user_interests(user_id)

        # 3. ClickHouse sinyalleri — paralel çek
        import asyncio
        ch_engagement, listing_engagement, listing_stream_corr = await asyncio.gather(
            self._fetch_ch_stream_engagement(user_id),
            self._fetch_ch_listing_engagement(user_id),
            self._fetch_listing_stream_correlation(user_id, interests),
        )

        # 4. ALS collaborative filtering skorları
        stream_ids = [s.id for s in streams]
        als_scores: dict[int, float] = {}
        try:
            als_scores = await get_als_scores(user_id, stream_ids)
        except Exception as exc:
            logger.debug("[SwipeLive] ALS skor alınamadı: %s", exc)

        # 4b. Chat hızı (son 90s mesaj sayısı) — momentum sinyali
        # + viewer count delta (son 5 dk izleyici büyümesi) — momentum sinyali
        chat_rates: dict[int, float] = {}
        viewer_deltas: dict[int, float] = {}
        try:
            from app.utils.redis_client import get_redis
            _redis = await get_redis()
            tick_keys = [f"stream:chat_tick:{sid}" for sid in stream_ids]
            snap_keys = [f"stream:viewers_snap:{sid}" for sid in stream_ids]
            if tick_keys:
                raw_ticks = await _redis.mget(*tick_keys)
                raw_snaps = await _redis.mget(*snap_keys)
                max_tick = max((int(v or 0) for v in raw_ticks), default=1)
                snap_pipe = _redis.pipeline()
                for sid, raw_tick, raw_snap, stream in zip(stream_ids, raw_ticks, raw_snaps, streams):
                    tick = int(raw_tick or 0)
                    chat_rates[sid] = tick / max(max_tick, 1)
                    # Viewer momentum: delta = current - snapshot (5 dakika önce)
                    current_viewers = getattr(stream, "viewer_count", 0) or 0
                    old_viewers = int(raw_snap or current_viewers)
                    delta = max(0, current_viewers - old_viewers)
                    max_v = max(current_viewers, 1)
                    viewer_deltas[sid] = min(delta / max_v, 1.0)
                    # Snapshot'ı güncelle (6 dakika TTL)
                    snap_pipe.setex(f"stream:viewers_snap:{sid}", 360, current_viewers)
                await snap_pipe.execute()
        except Exception as exc:
            logger.debug("[SwipeLive] Chat hızı / viewer delta alınamadı: %s", exc)

        # 5. Yayınları skorla ve sırala
        seen_categories: dict[str, int] = {}
        scored = []
        for stream in streams:
            score = self._score_stream(
                stream, interests, ch_engagement,
                als_scores, seen_categories,
                chat_rate=chat_rates.get(stream.id, 0.0),
                viewer_delta=viewer_deltas.get(stream.id, 0.0),
            )
            scored.append((score, stream))
            seen_categories[stream.category] = seen_categories.get(stream.category, 0) + 1

        scored.sort(key=lambda x: -x[0])
        ranked_streams = [s for _, s in scored]

        # 6. listings_per_group CTR'dan hesapla
        lpg = self._compute_listings_per_group(listing_engagement)

        # 7. Tercih edilen ilan kategorileri
        #    a) Listing-stream korelasyonu (SwipeLive içi davranış)
        #    b) Fallback: genel kategori ilgisi
        if listing_stream_corr:
            preferred_cats = listing_stream_corr
        else:
            preferred_cats = [
                cat for cat, _ in sorted(interests.items(), key=lambda x: -x[1])[:3]
            ]

        # Serialization
        stream_dicts = [self._stream_to_dict(s) for s in ranked_streams]

        return {
            "streams": stream_dicts,
            "listings_per_group": lpg,
            "preferred_listing_categories": preferred_cats,
        }


    def _score_stream(self, 
        stream,
        interests: dict[str, float],
        ch_engagement: dict[int, dict],
        als_scores: dict[int, float],
        seen_categories: dict[str, int],
        chat_rate: float = 0.0,
        viewer_delta: float = 0.0,
    ) -> float:
        # 1. Category affinity
        affinity = min(interests.get(stream.category, 0.05), 1.0)

        # 2. Stream quality (viewer + like)
        viewer_score = math.log1p(getattr(stream, "viewer_count", 0)) / 10.0
        like_score = math.log1p(getattr(stream, "likes_count", 0)) / 8.0
        quality = min((viewer_score + like_score) / 2.0, 1.0)

        # 3. ClickHouse geçmiş etkileşimi
        eng = ch_engagement.get(stream.id, {})
        ch_score = eng.get("engagement_score", 0.0)

        # 4. ALS collaborative filtering
        als = min(als_scores.get(stream.id, 0.0), 1.0)

        # 5. Yenilik
        now = datetime.now(timezone.utc)
        started = stream.started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        age_hours = (now - started).total_seconds() / 3600.0
        recency = max(0.0, 1.0 - age_hours / 2.0)

        # 6. Momentum: chat hızı + viewer büyümesi delta
        chat_momentum = min(chat_rate, 1.0)
        view_momentum = min(viewer_delta, 1.0)
        momentum = chat_momentum * 0.60 + view_momentum * 0.40

        # 7. Çeşitlilik cezası — kategorinin kaçıncı tekrarı
        repeat_count = seen_categories.get(stream.category, 0)
        diversity_penalty = repeat_count * 0.08

        return (
            affinity  * 0.30
            + quality * 0.18
            + ch_score * 0.18
            + als      * 0.14
            + recency  * 0.10
            + momentum * 0.10
            - diversity_penalty
        )


    def _compute_listings_per_group(self, listing_engagement: dict) -> int:
        """CTR'a göre yayınlar arası ilan sayısı (0-3).

        Eşikler daraltıldı: çoğunluk artık 2 bandında takılmıyor.
        Soğuk başlanguç 1'e indirildi — yeterli veri gelince yukarı veya aşağı adapt eder.
        """
        clicks = listing_engagement.get("clicks", 0)
        impressions = listing_engagement.get("impressions", 0)
        if impressions < 3:
            return 1  # soğuk başlanguç: nötr başlangıç noktası
        ctr = clicks / impressions
        # CTR eşikleri: daha dar bantlar, daha hassas adaptasyon
        if ctr >= 0.12:   # Aktif tıklayıcı → çok ilan göster
            return 3
        if ctr >= 0.05:   # Orta ilgi → biraz ilan göster
            return 2
        if ctr >= 0.02:   # Düşük ilgi → az ilan göster
            return 1
        return 0           # İlan tıklamayan kullanıcı → ilan gösterme


    # ----------------------------  CLICKHOUSE QUERIES  --------------------------


    async def _fetch_ch_stream_engagement(self, user_id: int) -> dict[int, dict]:
        """Son 30 günde kullanıcının her yayınla etkileşimini döndürür."""
        try:
            ch = await get_clickhouse_client()
            result = await ch.query(
                """
                SELECT
                    stream_id,
                    countIf(event_type = 'dwell')                        AS dwells,
                    countIf(event_type = 'skip')                         AS skips,
                    avgIf(dwell_ms, event_type = 'dwell')                AS avg_dwell,
                    countIf(event_type = 'stream_heart')                 AS hearts,
                    countIf(event_type IN ('stream_gift', 'stream_bid')) AS strong_eng
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
                sid, dwells, skips, avg_dwell, hearts, strong = row
                total = (dwells or 0) + (skips or 0)
                if total == 0:
                    score = 0.0
                else:
                    dwell_ratio = (dwells or 0) / total
                    quality = min((avg_dwell or 0) / 15000.0, 1.0)
                    # Güçlü etkileşim (hediye, teklif, kalp) bonusu
                    engagement_bonus = min((hearts or 0) * 0.05 + (strong or 0) * 0.15, 0.3)
                    score = dwell_ratio * quality + engagement_bonus
                out[int(sid)] = {"engagement_score": round(min(score, 1.0), 4)}
            return out
        except Exception as exc:
            logger.debug("[SwipeLive] _fetch_ch_stream_engagement başarısız: %s", exc)
            return {}


    async def _fetch_ch_listing_engagement(self, user_id: int) -> dict:
        """Son 30 günde listing tıklama/impression verisini döndürür."""
        try:
            ch = await get_clickhouse_client()
            r1 = await ch.query(
                """
                SELECT
                    countIf(event_type = 'listing_tap')                              AS clicks,
                    countIf(event_type IN ('listing_impression', 'listing_skip'))    AS impressions
                FROM swipe_live_events
                WHERE user_id = {uid:UInt32}
                  AND timestamp >= now() - INTERVAL 30 DAY
                  AND listing_id > 0
                """,
                parameters={"uid": user_id},
            )
            row1 = r1.result_rows[0] if r1.result_rows else (0, 0)

            r2 = await ch.query(
                """
                SELECT
                    countIf(event_type = 'click')      AS clicks,
                    countIf(event_type = 'impression') AS impressions
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


    async def _fetch_listing_stream_correlation(self, 
        user_id: int,
        interests: dict[str, float],
    ) -> list[str]:
        """
        Kullanıcının izlediği stream kategorileri sonrasında hangi listing
        kategorilerine tıkladığını hesaplar → preferred_listing_categories listesi.

        Mantık:
          1. Kullanıcının swipe_live_events'teki listing_tap eventlerini çek
          2. stream_category → listing_category tıklama sayısı
          3. Kullanıcının top-3 stream kategori ilgisiyle ağırlıklandır
          4. En yüksek skora sahip top-3 listing kategorisi döndür

        Yeterli veri yoksa boş liste → _build_config fallback'e düşer.
        """
        try:
            ch = await get_clickhouse_client()
            result = await ch.query(
                """
                SELECT
                    stream_category,
                    listing_category,
                    count() AS taps
                FROM swipe_live_events
                WHERE user_id = {uid:UInt32}
                  AND event_type = 'listing_tap'
                  AND stream_category != ''
                  AND listing_category != ''
                  AND timestamp >= now() - INTERVAL 60 DAY
                GROUP BY stream_category, listing_category
                HAVING taps >= 1
                ORDER BY taps DESC
                LIMIT 50
                """,
                parameters={"uid": user_id},
            )

            if not result.result_rows:
                # Kullanıcı verisi yoksa global korelasyona bak
                return await self._fetch_global_listing_stream_correlation(interests)

            # stream_category affinity'si ile ağırlıklandırılmış listing skoru
            listing_scores: dict[str, float] = {}
            for stream_cat, listing_cat, taps in result.result_rows:
                stream_weight = interests.get(stream_cat, 0.1)
                listing_scores[listing_cat] = listing_scores.get(listing_cat, 0.0) + taps * stream_weight

            if not listing_scores:
                return []

            top = sorted(listing_scores.items(), key=lambda x: -x[1])[:3]
            return [cat for cat, _ in top]

        except Exception as exc:
            logger.debug("[SwipeLive] _fetch_listing_stream_correlation başarısız: %s", exc)
            return []


    async def _fetch_global_listing_stream_correlation(self, 
        interests: dict[str, float],
    ) -> list[str]:
        """
        Kullanıcıya özel veri yokken global korelasyon tablosuna bak.
        Tüm kullanıcıların davranışından en iyi listing kategorisi.
        """
        try:
            ch = await get_clickhouse_client()
            # Kullanıcının top-2 stream kategorisini al
            top_stream_cats = [
                cat for cat, _ in sorted(interests.items(), key=lambda x: -x[1])[:2]
            ]
            if not top_stream_cats:
                return []

            result = await ch.query(
                """
                SELECT
                    listing_category,
                    count() AS taps
                FROM swipe_live_events
                WHERE event_type = 'listing_tap'
                  AND stream_category IN {cats:Array(String)}
                  AND listing_category != ''
                  AND timestamp >= now() - INTERVAL 30 DAY
                GROUP BY listing_category
                ORDER BY taps DESC
                LIMIT 3
                """,
                parameters={"cats": top_stream_cats},
            )
            return [row[0] for row in result.result_rows]
        except Exception:
            return []


    # ----------------------------  HELPERS  -------------------------------------


    def _stream_to_dict(self, s) -> dict:
        return {
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
        }
