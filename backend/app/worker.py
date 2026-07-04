"""
ARQ Worker — arka plan görev tanımları.

Başlatmak için sunucuda ayrı bir process olarak çalıştır:
    arq app.worker.WorkerSettings

Her task:
- Hata durumunda logger.error + Sentry ile raporlar (error-logger standardı)
- raise ile hatayı yeniden fırlatır → ARQ görevi "failed" işaretler ve retries devreye girer
"""

from __future__ import annotations

import json

from arq import cron
from arq.connections import RedisSettings

from app.config import settings
from app.core.logger import get_logger, capture_exception
from app.tasks.analytics_tasks import process_churn_and_airdrop, cleanup_hype_highlights_task
from app.tasks.listing_tasks import deactivate_expired_listings_task, delete_expired_inactive_listings_task

logger = get_logger(__name__)


# ── Task: E-posta Gönderimi ──────────────────────────────────────────────────

async def send_verification_email_task(
    ctx: dict,
    email: str,
    full_name: str,
    code: str,
    has_phone: bool = False,
) -> None:
    """
    Doğrulama kodunu e-posta ile iletir.
    Brevo API çağrısı bu task içinde yapılır; API endpoint'i bloklamaz.
    """
    try:
        from app.utils.email import send_verification_code
        await send_verification_code(email, full_name, code, has_phone=has_phone)
        logger.info("[Worker] Doğrulama e-postası gönderildi: %s", email)
    except Exception as exc:
        logger.error(
            "[Worker] Doğrulama e-postası gönderilemedi [%s]: %s",
            email,
            str(exc),
            exc_info=True,
        )
        capture_exception(exc)
        raise  # ARQ görevi "failed" olarak işaretlenir


async def send_welcome_email_task(
    ctx: dict,
    email: str,
    full_name: str,
    has_phone: bool = False,
    lang: str = "tr",
) -> None:
    try:
        from app.utils.email import send_welcome_email
        await send_welcome_email(email, full_name, has_phone=has_phone, lang=lang)
        logger.info("[Worker] Hoşgeldin e-postası gönderildi: %s", email)
    except Exception as exc:
        logger.error("[Worker] Hoşgeldin e-postası gönderilemedi [%s]: %s", email, str(exc), exc_info=True)
        capture_exception(exc)


# ── Task: FCM Push Bildirimi ─────────────────────────────────────────────────

async def send_push_notification_task(
    ctx: dict,
    fcm_token: str,
    title: str,
    body: str | None = None,
    badge: int | None = None,
    notif_type: str | None = None,
    extra_data: dict[str, str] | None = None,
    image_url: str | None = None,
) -> None:
    """
    FCM üzerinden push bildirimi gönderir.
    Firebase SDK çağrısı bu task içinde yapılır; API endpoint'i bloklamaz.
    """
    if not fcm_token:
        logger.warning("[Worker] send_push_notification_task: fcm_token boş, atlanıyor")
        return
    try:
        from app.services.firebase_service import send_push, InvalidFCMTokenError
        await send_push(fcm_token, title, body, badge=badge, notif_type=notif_type, extra_data=extra_data, image_url=image_url)
        logger.info("[Worker] Push bildirimi gönderildi | token=%s…", fcm_token[:12])
    except InvalidFCMTokenError:
        # Token geçersiz/silinmiş — DB'den temizle, retry yapma
        logger.warning("[Worker] Geçersiz FCM token temizleniyor | token=%s…", fcm_token[:12])
        try:
            from app.database import AsyncSessionLocal
            from app.models.user import User
            from sqlalchemy import update as sa_update
            async with AsyncSessionLocal() as db:
                await db.execute(
                    sa_update(User).where(User.fcm_token == fcm_token).values(fcm_token=None)
                )
                await db.commit()
            logger.info("[Worker] FCM token temizlendi | token=%s…", fcm_token[:12])
        except Exception as db_exc:
            logger.error("[Worker] FCM token temizlenemedi | %s", db_exc)
        # raise edilmez — ARQ retry yapmasın, kalıcı hata
    except Exception as exc:
        logger.error(
            "[Worker] Push bildirimi gönderilemedi | token=%s… | %s",
            fcm_token[:12],
            str(exc),
            exc_info=True,
        )
        capture_exception(exc)
        raise  # ARQ görevi "failed" olarak işaretlenir (geçici hatalar için retry)


# ── Task: Süresi Dolan Hikaye Temizliği ──────────────────────────────────────

async def cleanup_expired_stories_task(ctx: dict) -> None:
    """
    Her saat başında çalışır; expires_at geçmiş hikayeleri diskten ve DB'den siler.
    story_views kayıtları CASCADE ile otomatik silinir.
    """
    try:
        from app.database import AsyncSessionLocal
        from app.services.story_service import StoryService
        async with AsyncSessionLocal() as db:
            deleted = await StoryService.cleanup_expired_stories(db)
            logger.info("[Worker] Story cleanup tamamlandı | silinen=%d", deleted)
    except Exception as exc:
        logger.error(
            "[Worker] Story cleanup başarısız | %s", str(exc), exc_info=True
        )
        capture_exception(exc)
        raise


# ── Task: Eski Bildirimleri Temizle ──────────────────────────────────────────

async def cleanup_old_notifications_task(ctx: dict) -> None:
    """
    Her gün 03:00'da çalışır; 30 günden eski bildirimleri siler.

    Kullanıcı başına birikim: ~30 bildirim/gün × 1000 kullanıcı = 900K satır/ay.
    30 günlük retention yeterli; daha eskisi operasyonel değer taşımaz.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '30 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Bildirim cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Bildirim cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Eski Analitik Eventleri Temizle ────────────────────────────────────

async def cleanup_old_analytics_task(ctx: dict) -> None:
    """
    Her Pazartesi 04:00'da çalışır; 90 günden eski analytics_events kayıtlarını siler.

    Bu tablo en hızlı büyüyen tablodur; retention olmadan GB'larca büyür.
    90 günlük veri çoğu analiz ihtiyacı için fazlasıyla yeterli.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM analytics_events WHERE created_at < NOW() - INTERVAL '90 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Analytics cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Analytics cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Eski Stream Kalplerini Temizle ─────────────────────────────────────

async def cleanup_old_stream_likes_task(ctx: dict) -> None:
    """
    Her gün 01:00'da çalışır; 7 günden eski stream_likes kayıtlarını siler.

    stream_likes unique constraint içermez — kalp animasyonu için her tıkta 1 satır.
    Canlı yayın genellikle birkaç saat sürer; 7 gün sonra bu kayıtların
    hiçbir operasyonel ya da analitik değeri kalmaz.

    Not: stream bitişinde inline temizlik de yapılır (stream_service.py).
    Bu job, o temizliği atlayan edge case'leri yakalar.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM stream_likes WHERE created_at < NOW() - INTERVAL '7 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Stream likes cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Stream likes cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Gizlenmiş Mesajları Temizle ────────────────────────────────────────

async def cleanup_hidden_messages_task(ctx: dict) -> None:
    """
    Her gün 02:30'da çalışır; is_hidden=True olan ve 60 günden eski
    direkt mesajları hard-delete eder.

    is_hidden flag'i moderasyon/shadowban için kullanılır; gizlenen mesajlar
    görüntülenmez ama tabloda kalır. 60 gün sonra itiraz penceresi kapanmış
    sayılır ve kayıtlar silinebilir.
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("""
                    DELETE FROM direct_messages
                    WHERE is_hidden = TRUE
                      AND created_at < NOW() - INTERVAL '60 days'
                """)
            )
            await db.commit()
            logger.info(
                "[Worker] Gizli mesaj cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Gizli mesaj cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Redis Interaction Kuyruğunu DB'ye Yaz ──────────────────────────────

async def flush_interactions_to_db(ctx: dict) -> None:
    """
    Her 5 dakikada çalışır; Redis'teki interaction_queue kuyruğunu
    toplu okur ve user_interactions tablosuna bulk-insert yapar.

    Atomic kuyruk tüketimi için LRANGE + DEL yerine pipeline kullanılır.
    """
    import json
    from datetime import datetime, timezone
    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis

    QUEUE_KEY = "interaction_queue"
    BATCH_LIMIT = 2000

    try:
        redis = await get_redis()

        # Kuyruğu atomik olarak al ve sıfırla
        async with redis.pipeline(transaction=True) as pipe:
            await pipe.lrange(QUEUE_KEY, 0, BATCH_LIMIT - 1)
            await pipe.ltrim(QUEUE_KEY, BATCH_LIMIT, -1)
            results = await pipe.execute()

        raw_items: list[str] = results[0]
        if not raw_items:
            return

        now = datetime.now(timezone.utc)
        rows = []
        for item in raw_items:
            try:
                data = json.loads(item)
                rows.append({
                    "user_id": data.get("user_id"),
                    "item_id": int(data["item_id"]),
                    "item_type": str(data["item_type"])[:20],
                    "interaction_type": str(data["interaction_type"])[:30],
                    "duration_seconds": float(data["duration_seconds"]) if data.get("duration_seconds") is not None else None,
                    "price_point": float(data["price_point"]) if data.get("price_point") is not None else None,
                    "created_at": now,
                })
            except Exception:
                continue

        if not rows:
            return

        # ── PostgreSQL insert ──────────────────────────────────────────────────
        from sqlalchemy import insert as sa_insert
        from app.models.analytics import UserInteraction
        async with AsyncSessionLocal() as db:
            await db.execute(sa_insert(UserInteraction), rows)
            await db.commit()

        # ── ClickHouse bulk insert ─────────────────────────────────────────────
        try:
            from app.database_clickhouse import get_clickhouse_client
            ch = await get_clickhouse_client()
            ch_data = [
                [
                    r["user_id"],                    # Nullable(UInt32)
                    r["item_id"],                    # UInt32
                    r["item_type"],                  # LowCardinality(String)
                    r["interaction_type"],           # event_type
                    r["price_point"],                 # Nullable(Float64) — ClickHouse'a ilet
                    r["duration_seconds"],           # Nullable(Float64)
                    r["created_at"],                 # DateTime
                ]
                for r in rows
            ]
            await ch.insert(
                "user_events",
                ch_data,
                column_names=[
                    "user_id", "item_id", "item_type",
                    "event_type", "price_point",
                    "duration_seconds", "timestamp",
                ],
            )
            logger.info(
                "[Worker] ClickHouse user_events insert tamamlandı | kayıt=%d", len(ch_data)
            )
        except Exception as ch_exc:
            # ClickHouse hatası PostgreSQL akışını engellememeli
            logger.warning(
                "[Worker] ClickHouse insert başarısız (PostgreSQL etkilenmedi) | %s", ch_exc
            )

        logger.info(
            "[Worker] flush_interactions_to_db tamamlandı | kayıt=%d", len(rows)
        )

        # Listing etkileşimi olan her kullanıcı için preference_embedding'i güncelle
        # _job_id ile deduplication — aynı kullanıcı için çakışan job'lar atlanır
        listing_user_ids = {
            r["user_id"]
            for r in rows
            if r["user_id"] is not None and r["item_type"] == "listing"
        }
        if listing_user_ids:
            from app.core.task_queue import get_pool
            pool = get_pool()
            if pool:
                for uid in listing_user_ids:
                    await pool.enqueue_job(
                        "update_user_preference_embedding",
                        uid,
                        _job_id=f"pref_emb:{uid}",
                    )

    except Exception as exc:
        logger.error(
            "[Worker] flush_interactions_to_db başarısız | %s", str(exc), exc_info=True
        )
        capture_exception(exc)
        raise


# ── Task: SwipeLive → user_interests köprüsü ─────────────────────────────────

async def sync_swipelive_interests_task(ctx: dict) -> None:
    """
    Her 20 dakikada bir çalışır.
    Son 22 dakikadaki swipe_live_events (ClickHouse) → analytics_events (PostgreSQL).

    listing_category önceliği; yoksa stream_category kullanılır.
    Yazılan event_type='swipelive_dwell', compute_user_interests_task bu sinyali işler.
    ClickHouse erişilemezse sessizce geçer — kritik değil.
    """
    from datetime import datetime, timezone
    from app.database import AsyncSessionLocal
    from app.models.analytics import AnalyticsEvent

    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        if ch is None:
            return

        result = await ch.query("""
            SELECT
                user_id,
                if(listing_category != '', listing_category, stream_category) AS category,
                countIf(event_type = 'dwell')                                 AS dwells,
                avgIf(dwell_ms, event_type = 'dwell')                         AS avg_dwell_ms,
                countIf(event_type = 'stream_heart')                          AS hearts,
                countIf(event_type IN ('stream_gift', 'stream_bid'))          AS strong_eng,
                countIf(event_type = 'listing_tap')                           AS listing_taps
            FROM swipe_live_events
            WHERE timestamp >= now() - INTERVAL 22 MINUTE
              AND user_id > 0
              AND (listing_category != '' OR stream_category != '')
            GROUP BY user_id, category
            HAVING dwells + hearts + strong_eng + listing_taps > 0
        """)

        rows = result.result_rows
        if not rows:
            return

        now = datetime.now(timezone.utc)
        events = []
        for row in rows:
            uid, category, dwells, avg_dwell_ms, hearts, strong_eng, listing_taps = row
            try:
                uid = int(uid)
                if not category:
                    continue
                events.append(AnalyticsEvent(
                    user_id=uid,
                    event_type="swipelive_dwell",
                    event_metadata={
                        "category": str(category),
                        "dwells": int(dwells or 0),
                        "avg_dwell_ms": float(avg_dwell_ms or 0),
                        "hearts": int(hearts or 0),
                        "strong_eng": int(strong_eng or 0),
                        "listing_taps": int(listing_taps or 0),
                    },
                    created_at=now,
                ))
            except (ValueError, TypeError):
                continue

        if not events:
            return

        async with AsyncSessionLocal() as db:
            db.add_all(events)
            await db.commit()

        logger.info("[Worker] sync_swipelive_interests_task: %d kayıt yazıldı", len(events))

    except Exception as exc:
        logger.error("[Worker] sync_swipelive_interests_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


# ── Task: Kullanıcı İlgi Skorlarını Güncelle ─────────────────────────────────

async def compute_user_interests_task(ctx: dict) -> None:
    """
    Her 15 dakikada çalışır; son 30 günün analytics_events + like/favorite/message
    sinyallerinden kullanıcı başına kategori ilgi skorlarını hesaplar ve
    user_interests tablosunu günceller. Redis interests:{uid} cache'ini invalidate eder.

    Ağırlıklar:
      mesaj gönderdi   × 10
      favoriledi       × 5
      beğendi          × 3
      foto kaydırdı    × 2
      uzun izledi      × 2  (dwell_seconds >= 10)
      video %80 izledi × 3
      video %30 izledi × 1
      kısa baktı       × 1  (dwell_seconds < 10)
      atladı           × -1

    Zaman ağırlığı:
      son 7 gün   → 1.0×
      7-14 gün    → 0.7×
      14-30 gün   → 0.4×

    Skor normalize edilir → [0, 1]
    """
    try:
        from sqlalchemy import text
        from app.database import AsyncSessionLocal
        from app.utils.redis_client import get_redis

        async with AsyncSessionLocal() as db:
            # Tüm aktif kullanıcılar için skor hesapla
            # Sadece son 30 günde sinyal veren kullanıcıları işle
            result = await db.execute(text("""
                WITH time_weight AS (
                    SELECT
                        user_id,
                        event_metadata->>'category' AS category,
                        event_type,
                        (event_metadata->>'dwell_seconds')::float AS dwell_sec,
                        (event_metadata->>'watch_pct')::float AS watch_pct,
                        (event_metadata->>'swipe_count')::int AS swipe_count,
                        CASE
                            WHEN created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                            WHEN created_at > NOW() - INTERVAL '14 days' THEN 0.7
                            ELSE 0.4
                        END AS time_w
                    FROM analytics_events
                    WHERE user_id IS NOT NULL
                      AND created_at > NOW() - INTERVAL '30 days'
                      AND event_type IN (
                          'listing_view', 'listing_skip',
                          'listing_photo_swipe', 'listing_video_watch'
                      )
                      AND event_metadata->>'category' IS NOT NULL
                ),
                analytics_scores AS (
                    SELECT
                        user_id,
                        category,
                        SUM(time_w * CASE
                            WHEN event_type = 'listing_skip'  THEN -1.0
                            WHEN event_type = 'listing_photo_swipe' THEN 2.0 * COALESCE(swipe_count, 1)
                            WHEN event_type = 'listing_video_watch' AND watch_pct >= 80 THEN 3.0
                            WHEN event_type = 'listing_video_watch' AND watch_pct >= 30 THEN 1.0
                            WHEN event_type = 'listing_view' AND dwell_sec >= 10 THEN 2.0
                            WHEN event_type = 'listing_view' THEN 1.0
                            ELSE 0.0
                        END) AS raw_score
                    FROM time_weight
                    GROUP BY user_id, category
                ),
                like_scores AS (
                    SELECT
                        ll.user_id,
                        l.category,
                        SUM(
                            CASE
                                WHEN ll.created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                                WHEN ll.created_at > NOW() - INTERVAL '14 days' THEN 0.7
                                ELSE 0.4
                            END * 3.0
                        ) AS raw_score
                    FROM listing_likes ll
                    INNER JOIN listings l ON l.id = ll.listing_id
                    WHERE ll.created_at > NOW() - INTERVAL '30 days'
                      AND l.category IS NOT NULL
                    GROUP BY ll.user_id, l.category
                ),
                fav_scores AS (
                    SELECT
                        f.user_id,
                        l.category,
                        SUM(
                            CASE
                                WHEN f.created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                                WHEN f.created_at > NOW() - INTERVAL '14 days' THEN 0.7
                                ELSE 0.4
                            END * 5.0
                        ) AS raw_score
                    FROM favorites f
                    INNER JOIN listings l ON l.id = f.listing_id
                    WHERE f.created_at > NOW() - INTERVAL '30 days'
                      AND l.category IS NOT NULL
                    GROUP BY f.user_id, l.category
                ),
                msg_scores AS (
                    SELECT
                        dm.sender_id AS user_id,
                        l.category,
                        SUM(
                            CASE
                                WHEN dm.created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                                WHEN dm.created_at > NOW() - INTERVAL '14 days' THEN 0.7
                                ELSE 0.4
                            END * 10.0
                        ) AS raw_score
                    FROM direct_messages dm
                    INNER JOIN listings l ON l.id = dm.listing_id
                    WHERE dm.created_at > NOW() - INTERVAL '30 days'
                      AND l.category IS NOT NULL
                    GROUP BY dm.sender_id, l.category
                ),
                -- Arama sinyali: kullanıcının kategori bazlı arama geçmişi
                search_scores AS (
                    SELECT
                        ae.user_id,
                        ae.event_metadata->>'category' AS category,
                        SUM(
                            CASE
                                WHEN ae.created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                                WHEN ae.created_at > NOW() - INTERVAL '14 days' THEN 0.7
                                ELSE 0.4
                            END * CASE
                                WHEN (ae.event_metadata->>'result_count')::int > 0 THEN 2.0
                                ELSE 1.0
                            END
                        ) AS raw_score
                    FROM analytics_events ae
                    WHERE ae.user_id IS NOT NULL
                      AND ae.created_at > NOW() - INTERVAL '30 days'
                      AND ae.event_type = 'search'
                      AND ae.event_metadata->>'category' IS NOT NULL
                      AND ae.event_metadata->>'category' != ''
                    GROUP BY ae.user_id, ae.event_metadata->>'category'
                ),
                -- SwipeLive sinyali: canlı yayın izlerken gösterilen kategori tercihleri
                swipelive_scores AS (
                    SELECT
                        ae.user_id,
                        ae.event_metadata->>'category' AS category,
                        SUM(
                            CASE
                                WHEN ae.created_at > NOW() - INTERVAL '7 days'  THEN 1.0
                                WHEN ae.created_at > NOW() - INTERVAL '14 days' THEN 0.7
                                ELSE 0.4
                            END * (
                                COALESCE((ae.event_metadata->>'strong_eng')::float, 0) * 4.0
                                + COALESCE((ae.event_metadata->>'hearts')::float, 0) * 2.0
                                + COALESCE((ae.event_metadata->>'listing_taps')::float, 0) * 3.0
                                + LEAST(COALESCE((ae.event_metadata->>'avg_dwell_ms')::float, 0) / 5000.0, 2.0)
                                + COALESCE((ae.event_metadata->>'dwells')::float, 0) * 0.5
                                + 1.0
                            )
                        ) AS raw_score
                    FROM analytics_events ae
                    WHERE ae.user_id IS NOT NULL
                      AND ae.created_at > NOW() - INTERVAL '30 days'
                      AND ae.event_type = 'swipelive_dwell'
                      AND ae.event_metadata->>'category' IS NOT NULL
                    GROUP BY ae.user_id, ae.event_metadata->>'category'
                ),
                combined AS (
                    SELECT user_id, category, raw_score FROM analytics_scores WHERE raw_score > 0
                    UNION ALL
                    SELECT user_id, category, raw_score FROM like_scores
                    UNION ALL
                    SELECT user_id, category, raw_score FROM fav_scores
                    UNION ALL
                    SELECT user_id, category, raw_score FROM msg_scores
                    UNION ALL
                    SELECT user_id, category, raw_score FROM search_scores WHERE raw_score > 0
                    UNION ALL
                    SELECT user_id, category, raw_score FROM swipelive_scores WHERE raw_score > 0
                ),
                summed AS (
                    SELECT user_id, category, SUM(raw_score) AS total_score
                    FROM combined
                    GROUP BY user_id, category
                ),
                normalized AS (
                    SELECT
                        user_id,
                        category,
                        total_score,
                        total_score / NULLIF(MAX(total_score) OVER (PARTITION BY user_id), 0) AS score
                    FROM summed
                )
                SELECT user_id, category, GREATEST(score, 0) AS score,
                       total_score AS raw
                FROM normalized
                WHERE score IS NOT NULL
            """))

            rows = result.all()
            if not rows:
                logger.info("[Worker] compute_user_interests: sinyal yok, atlanıyor")
                return

            # Toplu upsert
            upsert_sql = text("""
                INSERT INTO user_interests (user_id, category, score, raw_signals, updated_at)
                VALUES (:uid, :cat, :score, :raw, NOW())
                ON CONFLICT (user_id, category)
                DO UPDATE SET score = EXCLUDED.score,
                              raw_signals = EXCLUDED.raw_signals,
                              updated_at = NOW()
            """)

            updated_users = set()
            for row in rows:
                await db.execute(upsert_sql, {
                    "uid": row.user_id,
                    "cat": row.category,
                    "score": float(row.score),
                    "raw": json.dumps({"raw_total": float(row.raw)}),
                })
                updated_users.add(row.user_id)

            await db.commit()

            # Redis cache invalidation
            redis = await get_redis()
            for uid in updated_users:
                await redis.delete(f"interests:{uid}")
                # Feed cache'lerini de temizle (pattern delete)
                feed_keys = await redis.keys(f"feed:{uid}:*")
                if feed_keys:
                    await redis.delete(*feed_keys)

            logger.info(
                "[Worker] compute_user_interests tamamlandı | kullanıcı=%d | kayıt=%d",
                len(updated_users), len(rows)
            )

    except Exception as exc:
        logger.error(
            "[Worker] compute_user_interests başarısız | %s", str(exc), exc_info=True
        )
        capture_exception(exc)
        raise


# ── Task: Kullanıcı Tercih Embedding'i Güncelle ──────────────────────────────

async def update_user_preference_embedding(ctx: dict, user_id: int) -> None:
    """
    Belirtilen kullanıcının preference_embedding'ini günceller.

    Sinyal kaynakları (birleşik ağırlıklı ortalama):
      1. PostgreSQL UserInteraction — explicit etkileşimler (tıklama, teklif, satın alma)
         - auction_won × 20, offer × 5, click × 2, diğer × 1
         - duration_seconds ağırlığı (maks 60s kırpılır)
      2. ClickHouse feed_analytics — implicit sinyal (son 7 gün)
         - click → × 3.0
         - impression + dwell > 8000ms → × 1.5
         - impression + dwell > 3000ms → × 0.8
         ClickHouse erişilemezse sadece PostgreSQL sinyali kullanılır.
    """
    try:
        import numpy as np
        from sqlalchemy import select
        from sqlalchemy import update as sa_update
        from app.database import AsyncSessionLocal
        from app.models.analytics import UserInteraction
        from app.models.listing import Listing
        from app.models.user import User

        async with AsyncSessionLocal() as db:
            # ── 1. PostgreSQL explicit sinyaller ─────────────────────────────
            interactions = list(await db.scalars(
                select(UserInteraction)
                .where(
                    UserInteraction.user_id == user_id,
                    UserInteraction.item_type == "listing",
                )
                .order_by(
                    UserInteraction.duration_seconds.desc().nullslast(),
                    UserInteraction.created_at.desc(),
                )
                .limit(50)
            ))

            # ── 2. ClickHouse implicit sinyaller (son 7 gün) ─────────────────
            ch_signals: dict[int, float] = {}
            try:
                from app.database_clickhouse import get_clickhouse_client
                ch = await get_clickhouse_client()
                if ch is not None:
                    uid_str = str(user_id)
                    ch_result = await ch.query(f"""
                        SELECT
                            listing_id,
                            SUM(
                                CASE
                                    WHEN event_type = 'click' THEN 3.0
                                    WHEN event_type = 'impression' AND dwell_time_ms > 8000 THEN 1.5
                                    WHEN event_type = 'impression' AND dwell_time_ms > 3000 THEN 0.8
                                    ELSE 0
                                END
                            ) AS signal
                        FROM feed_analytics
                        WHERE user_id = '{uid_str}'
                          AND timestamp >= now() - INTERVAL 7 DAY
                        GROUP BY listing_id
                        HAVING signal > 0
                        LIMIT 100
                    """)
                    for lid_str, signal in ch_result.result_rows:
                        try:
                            ch_signals[int(lid_str)] = float(signal)
                        except (ValueError, TypeError):
                            continue
            except Exception as ch_exc:
                logger.debug("[Worker] ClickHouse sinyal alınamadı, atlanıyor: %s", ch_exc)

            # ── 3. Tüm listing ID'lerini topla ───────────────────────────────
            pg_item_ids = [i.item_id for i in interactions]
            ch_item_ids = list(ch_signals.keys())
            all_item_ids = list(set(pg_item_ids) | set(ch_item_ids))

            if not all_item_ids:
                return

            emb_rows = await db.execute(
                select(Listing.id, Listing.embedding)
                .where(Listing.id.in_(all_item_ids), Listing.embedding.isnot(None))
            )
            emb_map = {r.id: r.embedding for r in emb_rows}

            if not emb_map:
                return

            vecs: list = []
            ws: list = []

            # PostgreSQL sinyalleri
            for inter in interactions:
                emb = emb_map.get(inter.item_id)
                if emb is None:
                    continue
                w = min(float(inter.duration_seconds or 1.0), 60.0)
                if inter.interaction_type == "auction_won":
                    w *= 20.0
                elif inter.interaction_type == "offer":
                    w *= 5.0
                elif inter.interaction_type == "click":
                    w *= 2.0
                vecs.append(np.array(emb, dtype=np.float32))
                ws.append(max(w, 0.1))

            # ClickHouse sinyalleri (PostgreSQL'de olmayan listing'ler)
            pg_ids_set = set(pg_item_ids)
            for lid, signal in ch_signals.items():
                if lid in pg_ids_set:
                    continue  # PostgreSQL'de zaten var, çift sayma
                emb = emb_map.get(lid)
                if emb is None:
                    continue
                vecs.append(np.array(emb, dtype=np.float32))
                ws.append(max(signal, 0.1))

            if not vecs:
                return

            ws_arr = np.array(ws, dtype=np.float32)
            ws_arr /= ws_arr.sum()
            mean_vec = np.average(vecs, axis=0, weights=ws_arr)
            norm = np.linalg.norm(mean_vec)
            if norm > 0:
                mean_vec = mean_vec / norm

            await db.execute(
                sa_update(User)
                .where(User.id == user_id)
                .values(preference_embedding=mean_vec.tolist())
            )
            await db.commit()

        logger.info(
            "[Worker] preference_embedding güncellendi | user_id=%d pg_signals=%d ch_signals=%d",
            user_id, len(interactions), len(ch_signals),
        )

        # For-you feed cache'ini temizle
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        await redis.delete(f"feed:foryou:{user_id}")

    except Exception as exc:
        logger.error(
            "[Worker] update_user_preference_embedding başarısız | user_id=%d | %s",
            user_id, str(exc), exc_info=True,
        )
        capture_exception(exc)
        raise


# ── Task: İlan Embedding Üretimi ─────────────────────────────────────────────

async def generate_listing_embedding_task(ctx: dict, listing_id: int) -> None:
    """
    Yeni/güncellenen ilan için sentence-transformer ile 384 boyutlu embedding üretir
    ve listings.embedding kolonuna yazar.

    Tetiklenir: ilan oluşturulduğunda veya başlık/açıklama/kategori değiştiğinde.
    Model ilk çağrıda yüklenir, sonraki çağrılarda önbellekten kullanılır.
    """
    try:
        from sqlalchemy import select, update as sa_update
        from app.database import AsyncSessionLocal
        from app.models.listing import Listing
        from app.services.ml_service import generate_embedding

        async with AsyncSessionLocal() as db:
            listing = await db.scalar(
                select(Listing).where(Listing.id == listing_id)
            )
            if not listing:
                logger.warning(
                    "[Worker] generate_listing_embedding: listing bulunamadı | id=%d", listing_id
                )
                return

            parts = [listing.title or ""]
            if listing.description:
                parts.append(listing.description)
            if listing.category:
                parts.append(listing.category)
            text = " ".join(parts).strip()

            embedding = generate_embedding(text)

            await db.execute(
                sa_update(Listing)
                .where(Listing.id == listing_id)
                .values(embedding=embedding)
            )
            await db.commit()

        logger.info(
            "[Worker] İlan embedding güncellendi | listing_id=%d | dim=%d",
            listing_id, len(embedding)
        )

    except Exception as exc:
        logger.error(
            "[Worker] generate_listing_embedding başarısız | listing_id=%d | %s",
            listing_id, str(exc), exc_info=True
        )
        capture_exception(exc)
        raise


# ── Task: Embedding Backfill ─────────────────────────────────────────────────

async def backfill_listing_embeddings_task(ctx: dict) -> None:
    """
    Her saat çalışır; embedding'i NULL olan aktif ilanlar için
    sentence-transformer embedding üretir ve kaydeder.
    Batch 20 ilan — uzun süren işlerin cron'u bloke etmemesi için küçük tutuldu.
    """
    try:
        from sqlalchemy import select, update as sa_update
        from app.database import AsyncSessionLocal
        from app.models.listing import Listing
        from app.services.ml_service import generate_embedding

        async with AsyncSessionLocal() as db:
            rows = (await db.scalars(
                select(Listing)
                .where(Listing.embedding.is_(None), Listing.is_deleted.is_(False))
                .order_by(Listing.id)
                .limit(20)
            )).all()

            if not rows:
                return

            count = 0
            for listing in rows:
                parts = [listing.title or ""]
                if listing.description:
                    parts.append(listing.description)
                if listing.category:
                    parts.append(listing.category)
                text = " ".join(parts).strip()
                if not text:
                    continue
                try:
                    emb = generate_embedding(text)
                    await db.execute(
                        sa_update(Listing).where(Listing.id == listing.id).values(embedding=emb)
                    )
                    count += 1
                except Exception as e:
                    logger.warning("[Worker] backfill_listing_embeddings: id=%d hata: %s", listing.id, e)

            await db.commit()
            if count:
                logger.info("[Worker] backfill_listing_embeddings: %d ilan embedding üretildi", count)

    except Exception as exc:
        logger.error("[Worker] backfill_listing_embeddings başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)


# ── Task: Eski İmpressionları Temizle ────────────────────────────────────────

async def cleanup_old_impressions_task(ctx: dict) -> None:
    """Her gün 05:00'da çalışır; 30 günden eski listing_impressions kayıtlarını siler."""
    try:
        from sqlalchemy import text
        from app.database import AsyncSessionLocal
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("DELETE FROM listing_impressions WHERE seen_at < NOW() - INTERVAL '30 days'")
            )
            await db.commit()
            logger.info(
                "[Worker] Impression cleanup tamamlandı | silinen=%d", result.rowcount
            )
    except Exception as exc:
        logger.error("[Worker] Impression cleanup başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)
        raise


async def cleanup_stale_streams_task(ctx: dict) -> None:
    """Her 2 dk: LiveKit'te odası kapanmış ama DB'de is_live=True olan hayalet yayınları kapat."""
    try:
        import aiohttp
        from datetime import datetime, timezone, timedelta
        from sqlalchemy import select
        from app.database import AsyncSessionLocal
        from app.models.stream import LiveStream
        from app.config import settings
        from livekit.api.room_service import RoomService, ListRoomsRequest

        cutoff = datetime.now(timezone.utc) - timedelta(minutes=3)

        async with AsyncSessionLocal() as db:
            streams = (await db.execute(
                select(LiveStream).where(
                    LiveStream.is_live == True,  # noqa: E712
                    LiveStream.started_at <= cutoff,
                )
            )).scalars().all()

            if not streams:
                return

            try:
                async with aiohttp.ClientSession() as session:
                    svc = RoomService(
                        session,
                        settings.livekit_api_base,
                        settings.livekit_api_key,
                        settings.livekit_api_secret,
                    )
                    res = await svc.list_rooms(ListRoomsRequest())
                    active_rooms = {r.name for r in res.rooms}
            except Exception as lk_exc:
                logger.warning("[Worker] Stale stream cleanup: LiveKit API erişilemedi | %s", lk_exc)
                return

            from app.routers.webhooks import _close_stream
            for stream in streams:
                if stream.room_name not in active_rooms:
                    elapsed = int(
                        (datetime.now(timezone.utc) - stream.started_at.replace(tzinfo=timezone.utc)).total_seconds() // 60
                        if stream.started_at.tzinfo is None
                        else (datetime.now(timezone.utc) - stream.started_at).total_seconds() // 60
                    )
                    logger.warning(
                        "[Worker] Hayalet yayın kapatılıyor | stream_id=%s room=%s elapsed=%d dk",
                        stream.id, stream.room_name, elapsed,
                    )
                    await _close_stream(db, stream.room_name)

    except Exception as exc:
        logger.error("[Worker] cleanup_stale_streams başarısız | %s", str(exc), exc_info=True)
        capture_exception(exc)


async def send_smart_auction_alerts(ctx: dict, stream_id: int) -> None:
    """
    Yeni yayın başladığında ilgili kitlenin FCM tokenlarına akıllı bildirim gönderir.

    Algoritma:
      1. Stream + aktif auction + listing (embedding, start_price) çek
      2. listing.embedding varsa →
            preference_embedding <=> listing_vec < 0.4 (cosine distance)
            AND (max_budget IS NULL OR max_budget * 1.2 >= start_price)
      3. Embedding yoksa → user_interests kategori eşleşmesi (fallback)
      4. Max 200 kullanıcı, 10'luk batch'ler hâlinde, host hariç
      5. pref_key="stream_started" kontrolü push_notification içinde yapılır
    """
    import asyncio as _asyncio
    from sqlalchemy import text as sa_text
    from app.database import AsyncSessionLocal
    from app.models.stream import LiveStream
    from app.models.auction import Auction
    from app.models.listing import Listing
    from app.routers.notifications import push_notification

    COSINE_THRESHOLD = 0.40
    MAX_USERS = 200
    BATCH_SIZE = 10

    try:
        async with AsyncSessionLocal() as db:
            # ── 1. Yayını getir ───────────────────────────────────────────────
            from sqlalchemy import select
            stream = await db.scalar(select(LiveStream).where(LiveStream.id == stream_id))
            if stream is None:
                logger.warning("[SmartAlert] stream_id=%s bulunamadı, atlanıyor.", stream_id)
                return

            host_id = stream.host_id
            stream_title = stream.title
            stream_category = stream.category
            thumbnail = stream.thumbnail_url

            # ── 2. Aktif auction + listing çek (opsiyonel) ───────────────────
            auction = await db.scalar(
                select(Auction).where(
                    Auction.stream_id == stream_id,
                    Auction.status == "active",
                ).order_by(Auction.id.desc())
            )

            listing_embedding: list | None = None
            start_price: float | None = None
            listing_title: str | None = None

            if auction:
                start_price = auction.start_price
                if auction.listing_id:
                    listing = await db.scalar(
                        select(Listing).where(Listing.id == auction.listing_id)
                    )
                    if listing:
                        listing_embedding = listing.embedding
                        listing_title = listing.title

            # ── 3. Kullanıcıları çek ─────────────────────────────────────────
            budget_clause = (
                "AND (u.max_budget IS NULL OR u.max_budget * 1.2 >= :start_price)"
                if start_price is not None else ""
            )
            params: dict = {"host_id": host_id, "lim": MAX_USERS}

            if listing_embedding is not None:
                # pgvector cosine distance — embedding'e yakın kullanıcılar
                vec_str = "[" + ",".join(f"{x:.8f}" for x in listing_embedding) + "]"
                params["vec"] = vec_str
                params["threshold"] = COSINE_THRESHOLD
                if start_price is not None:
                    params["start_price"] = start_price
                rows = await db.execute(sa_text(f"""
                    SELECT u.id, u.fcm_token, u.notification_prefs, u.username
                    FROM users u
                    WHERE u.is_active = TRUE
                      AND u.fcm_token IS NOT NULL
                      AND u.preference_embedding IS NOT NULL
                      AND u.id != :host_id
                      AND u.preference_embedding <=> CAST(:vec AS vector) < :threshold
                      {budget_clause}
                    ORDER BY u.preference_embedding <=> CAST(:vec AS vector) ASC
                    LIMIT :lim
                """), params)
            else:
                # Fallback: kategori ilgisine göre kullanıcılar
                if start_price is not None:
                    params["start_price"] = start_price
                params["category"] = stream_category
                rows = await db.execute(sa_text(f"""
                    SELECT u.id, u.fcm_token, u.notification_prefs, u.username
                    FROM users u
                    INNER JOIN user_interests ui
                        ON ui.user_id = u.id AND ui.category = :category
                    WHERE u.is_active = TRUE
                      AND u.fcm_token IS NOT NULL
                      AND u.id != :host_id
                      {budget_clause}
                    ORDER BY ui.score DESC
                    LIMIT :lim
                """), params)

            users = rows.fetchall()

        if not users:
            logger.info("[SmartAlert] stream_id=%s için uygun kullanıcı bulunamadı.", stream_id)
            return

        logger.info("[SmartAlert] stream_id=%s → %d kullanıcıya bildirim gönderiliyor.",
                    stream_id, len(users))

        # ── 4. Kişiselleştirilmiş bildirim metni ─────────────────────────────
        display_title = listing_title or stream_title
        price_str = f" ({int(start_price):,} ₺'den başlayan fiyatlarla)".replace(",", ".") if start_price else ""
        notif_body = f"{display_title}{price_str}"

        # ── 5. Batch FCM gönderimi ────────────────────────────────────────────
        async def _notify(user_row) -> None:
            try:
                await push_notification(
                    user_id=user_row.id,
                    notif={
                        "type": "smart_auction_alert",
                        "title": "Tam sana göre bir yayın başladı! 🎯",
                        "body": notif_body,
                        "related_id": stream_id,
                        "stream_id": stream_id,       # FCM data: deep link için
                        "sender_image_url": thumbnail or "",
                    },
                    pref_key="smart_alert",
                )
            except Exception as e:
                logger.warning("[SmartAlert] user_id=%s bildirim hatası: %s", user_row.id, e)

        for i in range(0, len(users), BATCH_SIZE):
            batch = users[i: i + BATCH_SIZE]
            await _asyncio.gather(*[_notify(u) for u in batch])

        logger.info("[SmartAlert] stream_id=%s bildirim tamamlandı | gönderilen=%d",
                    stream_id, len(users))

    except Exception as exc:
        logger.error("[Worker] send_smart_auction_alerts başarısız | stream_id=%s | %s",
                     stream_id, str(exc), exc_info=True)
        capture_exception(exc)
        raise


async def compute_seller_badges_task(ctx: dict) -> None:
    """
    Her gün 01:30'da çalışır.
    Son 30 gündeki auction_won / (auction_won + auction_ended) oranından
    satıcı rozetlerini hesaplar ve Redis'e yazar (25 saat TTL).

    Rozetler:
      trusted_seller  → conv_rate >= 0.65 VE en az 3 tamamlanan açık artırma
      active_seller   → en az 5 tamamlanan açık artırma (conv_rate sınırı yok)
    """
    try:
        from app.database_clickhouse import get_clickhouse_client
        from app.utils.redis_client import get_redis

        ch = await get_clickhouse_client()
        result = await ch.query("""
            SELECT
                user_id,
                countIf(event_type = 'auction_won')                           AS won,
                countIf(event_type IN ('auction_won', 'auction_ended'))        AS total
            FROM user_events
            WHERE timestamp >= now() - INTERVAL 30 DAY
              AND event_type IN ('auction_won', 'auction_ended')
              AND user_id IS NOT NULL
            GROUP BY user_id
            HAVING total >= 3
        """)

        redis = await get_redis()
        pipe = redis.pipeline()
        badge_count = 0
        for row in result.result_rows:
            uid, won, total = row
            conv = won / total if total > 0 else 0.0
            if conv >= 0.65:
                badge = "trusted_seller"
            elif total >= 5:
                badge = "active_seller"
            else:
                continue
            pipe.setex(f"seller:badge:{uid}", 90_000, badge)  # 25 saat
            badge_count += 1
        await pipe.execute()
        logger.info("[Worker] compute_seller_badges_task tamamlandı | rozet=%d", badge_count)
    except Exception as exc:
        logger.error("[Worker] compute_seller_badges_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def compute_trending_categories_task(ctx: dict) -> None:
    """
    Her 6 saatte çalışır.
    Son 7 gündeki auction_won sayısını önceki 7 günle karşılaştırır.
    %30'dan fazla artış gösteren kategorileri 'trending:categories' Redis setine yazar.
    """
    try:
        from app.database_clickhouse import get_clickhouse_client
        from app.utils.redis_client import get_redis

        ch = await get_clickhouse_client()
        # user_events'te item_type='listing' olan auction_won event'lerini kategoriye göre say
        # listing kategorisini bilmediğimiz için feed_analytics'teki stream_category alanını kullanıyoruz
        # Alternatif: PostgreSQL'den son 7/14 günün auction kazanma sayısını kategori bazlı çekelim
        from app.database import AsyncSessionLocal
        from sqlalchemy import text as sql_text

        async with AsyncSessionLocal() as db:
            rows = await db.execute(sql_text("""
                WITH
                    recent AS (
                        SELECT l.category, COUNT(*) AS cnt
                        FROM auctions a
                        INNER JOIN listings l ON l.id = a.listing_id
                        WHERE a.ended_at >= NOW() - INTERVAL '7 days'
                          AND a.winner_id IS NOT NULL
                          AND l.category IS NOT NULL
                        GROUP BY l.category
                    ),
                    prev AS (
                        SELECT l.category, COUNT(*) AS cnt
                        FROM auctions a
                        INNER JOIN listings l ON l.id = a.listing_id
                        WHERE a.ended_at >= NOW() - INTERVAL '14 days'
                          AND a.ended_at <  NOW() - INTERVAL '7 days'
                          AND a.winner_id IS NOT NULL
                          AND l.category IS NOT NULL
                        GROUP BY l.category
                    )
                SELECT r.category
                FROM recent r
                LEFT JOIN prev p ON p.category = r.category
                WHERE r.cnt >= 2
                  AND (p.cnt IS NULL OR r.cnt > p.cnt * 1.3)
            """))
            trending = [row[0] for row in rows.fetchall()]

        redis = await get_redis()
        key = "trending:categories"
        pipe = redis.pipeline()
        pipe.delete(key)
        if trending:
            pipe.sadd(key, *trending)
        pipe.expire(key, 21_600)  # 6 saat
        await pipe.execute()
        logger.info("[Worker] compute_trending_categories_task | trend=%s", trending)
    except Exception as exc:
        logger.error("[Worker] compute_trending_categories_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def send_budget_match_notifications_task(ctx: dict, listing_id: int) -> None:
    """
    Yeni ilan oluşturulduğunda bütçesi + tercihleri uyumlu kullanıcılara bildirim gönderir.
    listing_service.create_listing() tarafından 3 dakika gecikmeli enqueue edilir
    (embedding worker'ının çalışması için yeterli süre tanınır).
    """
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import select, text as sql_text
        from app.models.listing import Listing

        async with AsyncSessionLocal() as db:
            res = await db.execute(select(Listing).where(Listing.id == listing_id))
            listing = res.scalar_one_or_none()
            if not listing or not listing.is_active or listing.is_deleted:
                return

            min_price = listing.price * 0.7

            if listing.embedding is not None:
                emb_str = "[" + ",".join(str(x) for x in listing.embedding) + "]"
                rows = await db.execute(
                    sql_text(f"""
                        SELECT id FROM users
                        WHERE max_budget >= :min_price
                          AND id != :owner_id
                          AND is_active = TRUE
                          AND preference_embedding IS NOT NULL
                          AND preference_embedding <=> '{emb_str}'::vector < 0.45
                        ORDER BY preference_embedding <=> '{emb_str}'::vector
                        LIMIT 100
                    """),
                    {"min_price": min_price, "owner_id": listing.user_id},
                )
            else:
                rows = await db.execute(
                    sql_text("""
                        SELECT id FROM users
                        WHERE max_budget >= :min_price AND id != :owner_id AND is_active = TRUE
                        ORDER BY max_budget DESC LIMIT 60
                    """),
                    {"min_price": min_price, "owner_id": listing.user_id},
                )

            recipient_ids = [r[0] for r in rows.fetchall()]
            title_val = listing.title
            price_val = listing.price

        if not recipient_ids:
            return

        from app.routers.notifications import push_notification
        import asyncio as _asyncio

        title = "Bütçene uygun yeni ilan! 💡"
        body = f"{title_val} — {price_val:.0f} ₺"

        async def _notify(uid: int) -> None:
            try:
                await push_notification(
                    user_id=uid,
                    notif={"type": "budget_match", "title": title, "body": body, "related_id": listing_id},
                    pref_key="budget_match",
                )
            except Exception:
                pass

        for i in range(0, len(recipient_ids), 20):
            await _asyncio.gather(*[_notify(uid) for uid in recipient_ids[i:i + 20]])

        logger.info("[BudgetMatch] listing_id=%s → %d kullanıcıya bildirim", listing_id, len(recipient_ids))
    except Exception as exc:
        logger.error("[BudgetMatch] Başarısız | listing_id=%s | %s", listing_id, exc, exc_info=True)
        capture_exception(exc)
        raise


async def calculate_user_budgets_task(ctx: dict) -> None:
    """
    Her gece 02:00'da çalışır.
    ClickHouse'daki son 7 günün etkileşim verisinden her kullanıcı için
    p90 price_point değerini hesaplar ve PostgreSQL User.max_budget'ı günceller.
    """
    try:
        from app.services.analytics_processor import calculate_user_budgets
        updated = await calculate_user_budgets()
        logger.info("[Worker] calculate_user_budgets_task tamamlandı | güncellenen=%d", updated)
    except Exception as exc:
        logger.error("[Worker] calculate_user_budgets_task başarısız | %s", str(exc), exc_info=True)
        # ClickHouse erişilemezse sessizce geçilebilir (kritik değil)


async def sync_ad_campaigns_task(ctx: dict) -> None:
    """
    Her 10 dakikada çalışır.
    PostgreSQL'deki aktif reklam kampanyalarını Redis'e yükler.
    Yeni eklenen kampanyaları Redis'e tanıtır ve PostgreSQL-Redis
    bütçe sapmasını düzeltir.
    """
    try:
        from app.services.ad_service import load_active_campaigns_to_redis
        count = await load_active_campaigns_to_redis()
        logger.info("[Worker] sync_ad_campaigns_task tamamlandı | kampanya=%d", count)
    except Exception as exc:
        logger.error("[Worker] sync_ad_campaigns_task başarısız | %s", str(exc), exc_info=True)


async def train_swipe_live_als_task(ctx: dict) -> None:
    """
    Her gece 03:15'te çalışır.
    30 günlük swipe_live_events verisinden ALS collaborative filtering modeli eğitir.
    Kullanıcı ve stream vektörlerini Redis'e yazar (25 saat TTL).
    """
    try:
        from app.services.swipe_live_ml import train_swipe_live_als
        await train_swipe_live_als()
        logger.info("[Worker] train_swipe_live_als_task tamamlandı")
    except Exception as exc:
        logger.error("[Worker] train_swipe_live_als_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


async def train_feed_als_task(ctx: dict) -> None:
    """
    Her gece 03:45'te çalışır.
    30 günlük feed_analytics verisinden ilan feed'i ALS collaborative filtering modeli eğitir.
    Kullanıcı ve ilan vektörlerini Redis'e yazar (25 saat TTL).
    SwipeLive ALS'den 30 dk sonra çalışır — yük çakışmasını önler.
    """
    try:
        from app.services.feed_als_ml import train_feed_als
        await train_feed_als()
        logger.info("[Worker] train_feed_als_task tamamlandı")
    except Exception as exc:
        logger.error("[Worker] train_feed_als_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)
        raise


# ── Task: Bildirim Zaman Optimizasyonu ────────────────────────────────────────

async def optimize_notification_timing_task(ctx: dict) -> None:
    """
    Her gece 04:00'da çalışır.
    Son 14 günün feed_analytics verisiyle kullanıcı başına günün hangi saatlerinde
    en çok etkileşim yaptığını hesaplar ve Redis'e yazar (25 saat TTL).

    Pazarlama bildirimleri bu veriyi kullanarak doğru saate denk getirilir.
    Açık artırma / gerçek zamanlı bildirimler bu filtreden geçmez.

    Redis key: notif:peak_hours:{uid}  → JSON "[8,20,21]"
    """
    try:
        import json
        from app.database_clickhouse import get_clickhouse_client
        from app.utils.redis_client import get_redis

        ch = await get_clickhouse_client()
        if ch is None:
            logger.warning("[NotifTiming] ClickHouse yok, atlanıyor")
            return

        result = await ch.query("""
            SELECT
                user_id,
                toHour(timestamp)     AS hour_of_day,
                count()               AS event_cnt
            FROM feed_analytics
            WHERE timestamp >= now() - INTERVAL 14 DAY
              AND user_id != ''
              AND event_type IN ('click', 'impression')
            GROUP BY user_id, hour_of_day
            HAVING event_cnt >= 2
            ORDER BY user_id, event_cnt DESC
        """)

        rows = result.result_rows
        if not rows:
            logger.info("[NotifTiming] Yeterli veri yok, atlanıyor")
            return

        from collections import defaultdict
        user_hours: dict[int, list[tuple[int, int]]] = defaultdict(list)
        for uid_s, hour, cnt in rows:
            try:
                uid = int(uid_s)
                user_hours[uid].append((int(hour), int(cnt)))
            except (ValueError, TypeError):
                continue

        redis = await get_redis()
        pipe = redis.pipeline()
        _TTL = 90_000  # 25 saat
        written = 0
        for uid, hour_counts in user_hours.items():
            sorted_hours = sorted(hour_counts, key=lambda x: x[1], reverse=True)
            peak = [h for h, _ in sorted_hours[:3]]
            pipe.setex(f"notif:peak_hours:{uid}", _TTL, json.dumps(peak))
            written += 1

        await pipe.execute()
        logger.info("[NotifTiming] Tamamlandı | kullanıcı=%d", written)

    except Exception as exc:
        logger.error("[NotifTiming] optimize_notification_timing_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


# ── Task: LightFM Hybrid Model ────────────────────────────────────────────────

async def train_lightfm_task(ctx: dict) -> None:
    """
    Her gece 04:15'te çalışır.
    LightFM hybrid collaborative + content filtering modelini eğitir.
    Kullanıcı ve ilan vektörlerini Redis'e yazar (25 saat TTL).
    """
    try:
        from app.services.feed_lightfm_ml import train_lightfm
        await train_lightfm()
        logger.info("[Worker] train_lightfm_task tamamlandı")
    except ImportError:
        logger.warning("[Worker] lightfm kurulu değil, atlanıyor")
    except Exception as exc:
        logger.error("[Worker] train_lightfm_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


# ── Task: CLIP Visual Embedding Backfill ─────────────────────────────────────

async def clip_visual_backfill_task(ctx: dict) -> None:
    """
    Her gece 04:30'da çalışır.
    visual_embedding'i NULL olan ilanlar için CLIP ViT-B/32 ile görsel embedding üretir.
    Rate limit: işlem başına 2 saniye bekleme — VPS CPU koruması.
    Batch: 30 ilan/çalıştırma.
    """
    try:
        from app.services.clip_service import backfill_clip_embeddings
        count = await backfill_clip_embeddings(batch_size=30)
        logger.info("[Worker] clip_visual_backfill_task tamamlandı | işlenen=%d", count)
    except ImportError:
        logger.warning("[Worker] CLIP bağımlılıkları eksik, atlanıyor")
    except Exception as exc:
        logger.error("[Worker] clip_visual_backfill_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def compute_listing_phash_task(ctx: dict, listing_id: int, image_url: str) -> None:
    """İlan primary görselinden pHash hesapla, DB'ye yaz, kopya varsa logla."""
    try:
        from app.services.image_mod_service import store_listing_phash
        await store_listing_phash(listing_id, image_url)
    except Exception as exc:
        logger.error("[Worker] compute_listing_phash_task başarısız | listing_id=%s | %s", listing_id, exc, exc_info=True)
        capture_exception(exc)


async def backfill_phash_task(ctx: dict) -> None:
    """image_phash NULL olan ilanlar için toplu pHash hesaplama (50 ilan/çalıştırma)."""
    try:
        from app.services.image_mod_service import backfill_phash
        count = await backfill_phash(batch_size=50)
        logger.info("[Worker] backfill_phash_task tamamlandı | işlenen=%d", count)
    except Exception as exc:
        logger.error("[Worker] backfill_phash_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def nsfw_check_task(ctx: dict, listing_id: int) -> None:
    """Tek ilanın tüm görsellerini NSFW için kontrol et."""
    try:
        from app.services.nsfw_service import check_listing_nsfw
        await check_listing_nsfw(listing_id)
    except Exception as exc:
        logger.error("[Worker] nsfw_check_task başarısız | listing_id=%s | %s", listing_id, exc, exc_info=True)
        capture_exception(exc)


async def nsfw_backfill_task(ctx: dict) -> None:
    """nsfw_checked_at NULL olan ilanlar için toplu NSFW kontrolü (20 ilan/çalıştırma)."""
    try:
        from app.services.nsfw_service import nsfw_backfill
        count = await nsfw_backfill(batch_size=20)
        logger.info("[Worker] nsfw_backfill_task tamamlandı | işlenen=%d", count)
    except Exception as exc:
        logger.error("[Worker] nsfw_backfill_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def rebuild_faiss_index_task(ctx: dict) -> None:
    """Tüm aktif listing embedding'lerinden FAISS IVFFlat index yeniden kur."""
    try:
        from app.services.faiss_service import rebuild_index
        await rebuild_index()
    except Exception as exc:
        logger.error("[Worker] rebuild_faiss_index_task başarısız | %s", exc, exc_info=True)
        capture_exception(exc)


async def invalidate_swipe_live_configs_task(ctx: dict) -> None:
    """
    Her 15 dakikada bir: ClickHouse'daki yeni SwipeLive etkileşim verisini
    kullanıcı config cache'lerine yansıtmak için ilgili Redis anahtarlarını temizler.
    Bir sonraki /swipe-live-config isteğinde konfigürasyon yeniden hesaplanır.
    Tüm keyler değil — sadece son 15 dakikada event gönderen kullanıcılarınki.
    """
    try:
        from app.database_clickhouse import get_clickhouse_client
        from app.utils.redis_client import get_redis

        ch = await get_clickhouse_client()
        result = await ch.query(
            """
            SELECT DISTINCT user_id
            FROM swipe_live_events
            WHERE timestamp >= now() - INTERVAL 15 MINUTE
              AND user_id > 0
            """
        )
        if not result.result_rows:
            return

        redis = await get_redis()
        keys = [f"swivelive_cfg:{row[0]}" for row in result.result_rows]
        if keys:
            await redis.delete(*keys)
            logger.info("[Worker] invalidate_swipe_live_configs: %d kullanıcı cache sıfırlandı", len(keys))
    except Exception as exc:
        logger.warning("[Worker] invalidate_swipe_live_configs başarısız | %s", exc)


# ── Worker Ayarları ──────────────────────────────────────────────────────────

class WorkerSettings:
    """
    `arq app.worker.WorkerSettings` komutuyla başlatılır.

    Redis bağlantısı projenin REDIS_URL config'inden alınır.
    max_jobs: Aynı anda çalışabilecek maksimum task sayısı.
    job_timeout: Tek bir task'ın zaman aşımı (saniye).
    keep_result: Tamamlanan task sonuçlarının Redis'te tutulma süresi.
    """

    functions = [
        send_verification_email_task,
        send_welcome_email_task,
        send_push_notification_task,
        cleanup_expired_stories_task,
        cleanup_old_notifications_task,
        cleanup_old_analytics_task,
        cleanup_old_stream_likes_task,
        cleanup_hidden_messages_task,
        compute_user_interests_task,
        cleanup_old_impressions_task,
        generate_listing_embedding_task,
        flush_interactions_to_db,
        update_user_preference_embedding,
        calculate_user_budgets_task,
        send_smart_auction_alerts,
        sync_ad_campaigns_task,
        process_churn_and_airdrop,
        cleanup_hype_highlights_task,
        deactivate_expired_listings_task,
        delete_expired_inactive_listings_task,
        compute_seller_badges_task,
        compute_trending_categories_task,
        send_budget_match_notifications_task,
        invalidate_swipe_live_configs_task,
        train_swipe_live_als_task,
        train_feed_als_task,
        sync_swipelive_interests_task,
        backfill_listing_embeddings_task,
        optimize_notification_timing_task,
        train_lightfm_task,
        clip_visual_backfill_task,
        compute_listing_phash_task,
        backfill_phash_task,
        nsfw_check_task,
        nsfw_backfill_task,
        rebuild_faiss_index_task,
        cleanup_stale_streams_task,
    ]

    cron_jobs = [
        # Her saat başında süresi dolan hikayeleri temizle
        cron(cleanup_expired_stories_task, minute=0),
        # Her gün 01:00 — eski stream kalplerini temizle
        cron(cleanup_old_stream_likes_task, hour=1, minute=0),
        # Her gün 02:00 — ClickHouse'dan kullanıcı bütçe tavanlarını hesapla
        cron(calculate_user_budgets_task, hour=2, minute=0),
        # Her gün 02:30 — gizlenmiş mesajları temizle
        cron(cleanup_hidden_messages_task, hour=2, minute=30),
        # Her gün 03:00 — eski bildirimleri temizle
        cron(cleanup_old_notifications_task, hour=3, minute=0),
        # Her Pazartesi 04:00 — eski analitik verilerini temizle
        cron(cleanup_old_analytics_task, weekday=0, hour=4, minute=0),
        # Her 15 dakikada kullanıcı ilgi skorlarını güncelle
        cron(compute_user_interests_task, minute={0, 15, 30, 45}),
        # Her 15 dakikada SwipeLive config cache'lerini sıfırla (yeni event gelenlerin)
        cron(invalidate_swipe_live_configs_task, minute={5, 20, 35, 50}),
        # Her gün 05:00 — eski listing impressionlarını temizle
        cron(cleanup_old_impressions_task, hour=5, minute=0),
        # Her 5 dakikada Redis interaction kuyruğunu DB'ye yaz
        cron(flush_interactions_to_db, minute={0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55}),
        # Her 10 dakikada PostgreSQL → Redis kampanya bütçe senkronizasyonu
        cron(sync_ad_campaigns_task, minute={0, 10, 20, 30, 40, 50}),
        # Her gün 03:30 — churn tespiti ve airdrop
        cron(process_churn_and_airdrop, hour=3, minute=30),
        # Her saat başında — süresi dolmuş highlight dosya + DB temizliği
        cron(cleanup_hype_highlights_task, minute=0),
        # Her gün 04:00 — 30 günlük ilanları pasife al
        cron(deactivate_expired_listings_task, hour=4, minute=0),
        # Her gün 04:30 — 60+ gün pasif kalan ilanları sil
        cron(delete_expired_inactive_listings_task, hour=4, minute=30),
        # Her gün 01:30 — satıcı rozetlerini hesapla (Redis cache)
        cron(compute_seller_badges_task, hour=1, minute=30),
        # Her 6 saatte — trend kategorileri hesapla (Redis cache)
        cron(compute_trending_categories_task, hour={0, 6, 12, 18}, minute=0),
        # Her gece 03:15 — SwipeLive ALS collaborative filtering modeli eğit
        cron(train_swipe_live_als_task, hour=3, minute=15),
        # Her gece 03:45 — İlan feed ALS collaborative filtering modeli eğit
        cron(train_feed_als_task, hour=3, minute=45),
        # Her gece 04:00 — kullanıcı bazlı bildirim saat optimizasyonu
        cron(optimize_notification_timing_task, hour=4, minute=0),
        # Her gece 04:15 — LightFM hybrid model eğitimi
        cron(train_lightfm_task, hour=4, minute=15),
        # Her gece 04:30 — CLIP görsel embedding backfill (30 ilan/çalıştırma)
        cron(clip_visual_backfill_task, hour=4, minute=30),
        # Her gece 05:15 — NSFW backfill (20 ilan/çalıştırma)
        cron(nsfw_backfill_task, hour=5, minute=15),
        # Her gece 05:30 — pHash backfill (50 ilan/çalıştırma)
        cron(backfill_phash_task, hour=5, minute=30),
        # Günde 2x 00:30 + 12:30 — FAISS index yeniden kur
        cron(rebuild_faiss_index_task, hour={0, 12}, minute=30),
        # Her 20 dakikada SwipeLive olaylarını kullanıcı ilgi sinyaline dönüştür
        cron(sync_swipelive_interests_task, minute={0, 20, 40}),
        # Her saat başı — embedding'i olmayan ilanlar için backfill (20'şer batch)
        cron(backfill_listing_embeddings_task, minute=30),
        # Her 2 dakikada — LiveKit'te odası kapanmış hayalet yayınları kapat
        cron(cleanup_stale_streams_task, minute=set(range(0, 60, 2))),
    ]

    redis_settings = RedisSettings.from_dsn(settings.redis_url)

    max_jobs = 20
    job_timeout = 300     # 5 dakika — bulk delete sorguları için artırıldı
    keep_result = 3600    # 1 saat — hata ayıklama için sonuçlar saklı tutulur
    max_tries = 3         # başarısız task'lar 3 kez yeniden denenir
