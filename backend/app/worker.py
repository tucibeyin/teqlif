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
    ]

    cron_jobs = [
        # Her saat başında süresi dolan hikayeleri temizle
        cron(cleanup_expired_stories_task, minute=0),
        # Her gün 01:00 — eski stream kalplerini temizle
        cron(cleanup_old_stream_likes_task, hour=1, minute=0),
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
    ]

    redis_settings = RedisSettings.from_dsn(settings.redis_url)

    max_jobs = 20
    job_timeout = 300     # 5 dakika — bulk delete sorguları için artırıldı
    keep_result = 3600    # 1 saat — hata ayıklama için sonuçlar saklı tutulur
    max_tries = 3         # başarısız task'lar 3 kez yeniden denenir
