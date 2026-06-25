"""
ARQ Worker — arka plan görev tanımları.

Başlatmak için sunucuda ayrı bir process olarak çalıştır:
    arq app.worker.WorkerSettings

Her task:
- Hata durumunda logger.error + Sentry ile raporlar (error-logger standardı)
- raise ile hatayı yeniden fırlatır → ARQ görevi "failed" işaretler ve retries devreye girer
"""

from __future__ import annotations

from arq import cron
from arq.connections import RedisSettings

from app.config import settings
from app.core.logger import get_logger, capture_exception
from app.tasks.analytics_tasks import process_churn_and_airdrop, cleanup_hype_highlights_task

logger = get_logger(__name__)


# ── Task: E-posta Gönderimi ──────────────────────────────────────────────────

async def send_verification_email_task(
    ctx: dict,
    email: str,
    full_name: str,
    code: str,
) -> None:
    """
    Doğrulama kodunu e-posta ile iletir.
    Brevo API çağrısı bu task içinde yapılır; API endpoint'i bloklamaz.
    """
    try:
        from app.utils.email import send_verification_code
        await send_verification_code(email, full_name, code)
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
                combined AS (
                    SELECT user_id, category, raw_score FROM analytics_scores WHERE raw_score > 0
                    UNION ALL
                    SELECT user_id, category, raw_score FROM like_scores
                    UNION ALL
                    SELECT user_id, category, raw_score FROM fav_scores
                    UNION ALL
                    SELECT user_id, category, raw_score FROM msg_scores
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
                    "raw": {"raw_total": float(row.raw)},
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
    Belirtilen kullanıcının son 50 ilan etkileşiminden ağırlıklı ortalama vektör
    hesaplar ve User.preference_embedding kolonuna yazar.

    Ağırlık:
      - duration_seconds (maks 60s'e kırpılır) → uzun izleme = güçlü sinyal
      - interaction_type: 'offer' × 5, 'click' × 2, diğer × 1
      - Hiç embeddingsi olmayan ilanlar atlanır
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

            if not interactions:
                return

            item_ids = [i.item_id for i in interactions]
            emb_rows = await db.execute(
                select(Listing.id, Listing.embedding)
                .where(Listing.id.in_(item_ids), Listing.embedding.isnot(None))
            )
            emb_map = {r.id: r.embedding for r in emb_rows}

            if not emb_map:
                return

            vecs, ws = [], []
            for inter in interactions:
                emb = emb_map.get(inter.item_id)
                if emb is None:
                    continue
                w = min(float(inter.duration_seconds or 1.0), 60.0)
                if inter.interaction_type == "offer":
                    w *= 5.0
                elif inter.interaction_type == "click":
                    w *= 2.0
                vecs.append(np.array(emb, dtype=np.float32))
                ws.append(max(w, 0.1))

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

        logger.info("[Worker] preference_embedding güncellendi | user_id=%d", user_id)

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
                      AND u.preference_embedding <=> :vec::vector < :threshold
                      {budget_clause}
                    ORDER BY u.preference_embedding <=> :vec::vector ASC
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
    ]

    redis_settings = RedisSettings.from_dsn(settings.redis_url)

    max_jobs = 20
    job_timeout = 300     # 5 dakika — bulk delete sorguları için artırıldı
    keep_result = 3600    # 1 saat — hata ayıklama için sonuçlar saklı tutulur
    max_tries = 3         # başarısız task'lar 3 kez yeniden denenir
