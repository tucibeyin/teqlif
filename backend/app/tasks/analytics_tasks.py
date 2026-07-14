"""
Churn Tespiti & Airdrop Görevi

Her gün 03:30'da ARQ worker tarafından çalıştırılır.

Mantık:
  1. ClickHouse feed_analytics'ten riskli kullanıcı ID'lerini çek (iki kriter, OR):
       a) Son 5 gündür hiç impression veya click üretmemiş (ama 5-30 gün önce aktifti)
       b) Son 3 günün toplam dwell_time'ı 3-6 gün öncesine göre %70'ten fazla düşmüş
  2. PostgreSQL tuci_transactions'tan son 30 günde 'churn_airdrop' almış olanları filtrele
  3. Kalan hak kazananların bakiyesine +10 TUCi ekle, transaction logu yaz
  4. FCM push bildirimi gönder
"""

from __future__ import annotations

import asyncio
import os
import pathlib
import time
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

_AIRDROP_AMOUNT = 10
_AIRDROP_TYPE = "churn_airdrop"
_COOLDOWN_DAYS = 30        # Aynı kullanıcıya tekrar airdrop göndermeden önce bekleme süresi
_INACTIVE_DAYS = 5         # Bu kadar gün sessizlik → risk sinyali
_LOOKBACK_DAYS = 30        # Daha önce aktif miydi? kontrolü için pencere
_DWELL_WINDOW_DAYS = 3     # Dwell drop karşılaştırma penceresi
_BATCH_SIZE = 20           # Aynı anda kaç kullanıcıya push
_SELLER_GAP_DAYS = 14      # Bu kadar gün ilan açmamış satıcı → risk sinyali
_SELLER_LOOKBACK_DAYS = 60 # Satıcı geçmişi kontrol penceresi


# ── ClickHouse sorguları ────────────────────────────────────────────────────────

# Kriter 1: Son N gündür impression/click üretmemiş, ama öncesinde aktifti
_Q_INACTIVE = """
WITH
    active_recent AS (
        SELECT DISTINCT user_id
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL {inactive_days} DAY
          AND event_type IN ('impression', 'click')
          AND match(user_id, '^[1-9][0-9]*$')
    ),
    active_before AS (
        SELECT DISTINCT user_id
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL {lookback_days} DAY
          AND timestamp  < now() - INTERVAL {inactive_days} DAY
          AND event_type IN ('impression', 'click')
          AND match(user_id, '^[1-9][0-9]*$')
    )
SELECT toUInt32(b.user_id) AS uid
FROM active_before b
WHERE b.user_id NOT IN (SELECT user_id FROM active_recent)
""".format(inactive_days=_INACTIVE_DAYS, lookback_days=_LOOKBACK_DAYS)

# Kriter 2: Dwell time'ı %70'ten fazla düşmüş kullanıcılar
_Q_DWELL_DROP = """
WITH
    recent AS (
        SELECT user_id, sum(dwell_time_ms) AS dwell
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL {window} DAY
          AND match(user_id, '^[1-9][0-9]*$')
        GROUP BY user_id
    ),
    prev AS (
        SELECT user_id, sum(dwell_time_ms) AS dwell
        FROM feed_analytics
        WHERE timestamp >= now() - INTERVAL {window2} DAY
          AND timestamp  < now() - INTERVAL {window} DAY
          AND match(user_id, '^[1-9][0-9]*$')
        GROUP BY user_id
    )
SELECT toUInt32(r.user_id) AS uid
FROM recent r
INNER JOIN prev p ON r.user_id = p.user_id
WHERE p.dwell > 0
  AND r.dwell < p.dwell * 0.30
""".format(window=_DWELL_WINDOW_DAYS, window2=_DWELL_WINDOW_DAYS * 2)


# Kriter 3: Daha önce ilan açmış ama son N gündür açmayan satıcılar
_Q_SELLER_INACTIVE = """
WITH
    active_sellers AS (
        SELECT DISTINCT user_id
        FROM user_events
        WHERE event_type = 'listing_created'
          AND timestamp >= now() - INTERVAL {gap} DAY
          AND user_id IS NOT NULL
    ),
    was_active AS (
        SELECT DISTINCT user_id
        FROM user_events
        WHERE event_type = 'listing_created'
          AND timestamp >= now() - INTERVAL {lookback} DAY
          AND timestamp  < now() - INTERVAL {gap} DAY
          AND user_id IS NOT NULL
    )
SELECT toUInt32(w.user_id) AS uid
FROM was_active w
WHERE w.user_id NOT IN (SELECT user_id FROM active_sellers)
""".format(gap=_SELLER_GAP_DAYS, lookback=_SELLER_LOOKBACK_DAYS)


async def _fetch_risky_user_ids() -> tuple[set[int], set[int]]:
    """
    ClickHouse'dan riskli kullanıcı ID'lerini çek.
    Döner: (alıcı_churn_ids, satıcı_churn_ids)
    Hata durumunda boş kümeler döner.
    """
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()

        result1, result2, result3 = await asyncio.gather(
            ch.query(_Q_INACTIVE),
            ch.query(_Q_DWELL_DROP),
            ch.query(_Q_SELLER_INACTIVE),
            return_exceptions=True,
        )

        buyer_risky: set[int] = set()
        seller_risky: set[int] = set()

        if isinstance(result1, Exception):
            logger.warning("[ChurnAirdrop] Kriter-1 sorgusu başarısız: %s", result1)
        else:
            buyer_risky.update(int(row[0]) for row in result1.result_rows if row[0])

        if isinstance(result2, Exception):
            logger.warning("[ChurnAirdrop] Kriter-2 sorgusu başarısız: %s", result2)
        else:
            buyer_risky.update(int(row[0]) for row in result2.result_rows if row[0])

        if isinstance(result3, Exception):
            logger.warning("[ChurnAirdrop] Kriter-3 (satıcı) sorgusu başarısız: %s", result3)
        else:
            seller_risky.update(int(row[0]) for row in result3.result_rows if row[0])
            # Satıcı churn aynı zamanda alıcı churn olabilir — çakışan ID'leri satıcı olarak tut
            buyer_risky -= seller_risky

        # ML tahminini heuristik sonuçlarına ekle
        try:
            from app.services import churn_ml_service
            ml_user_ids, ml_features = await churn_ml_service.fetch_candidate_features()
            if ml_features:
                probs = churn_ml_service.predict_churn_risk(ml_features)
                _ML_THRESHOLD = 0.65
                ml_risky = {
                    uid for uid, p in zip(ml_user_ids, probs) if p >= _ML_THRESHOLD
                }
                added = ml_risky - buyer_risky - seller_risky
                buyer_risky |= added
                logger.info(
                    "[ChurnAirdrop] ML tahmin: toplam=%d yeni=%d (threshold=%.2f)",
                    len(ml_risky), len(added), _ML_THRESHOLD,
                )
        except Exception as ml_exc:
            logger.warning("[ChurnAirdrop] ML tahmin atlandı: %s", ml_exc)

        logger.info(
            "[ChurnAirdrop] ClickHouse riskli kullanıcı: alıcı=%d satıcı=%d",
            len(buyer_risky), len(seller_risky),
        )
        return buyer_risky, seller_risky

    except Exception as exc:
        logger.error("[ChurnAirdrop] ClickHouse erişilemedi: %s", exc, exc_info=True)
        return set(), set()


async def _filter_already_received(user_ids: set[int]) -> set[int]:
    """
    Son 30 günde 'churn_airdrop' almış kullanıcıları çıkar.
    Dönen küme: airdrop almaya hak kazanan kullanıcı ID'leri.
    """
    if not user_ids:
        return set()
    from app.database import AsyncSessionLocal
    from sqlalchemy import text

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            text("""
                SELECT DISTINCT user_id
                FROM tuci_transactions
                WHERE user_id = ANY(:uids)
                  AND transaction_type = :ttype
                  AND created_at >= NOW() - INTERVAL '30 days'
            """),
            {
                "uids": list(user_ids),
                "ttype": _AIRDROP_TYPE,
            },
        )
        already_received = {row[0] for row in result.fetchall()}

    eligible = user_ids - already_received
    logger.info(
        "[ChurnAirdrop] Hak kazanan: %d (toplam riskli=%d, daha önce almış=%d)",
        len(eligible), len(user_ids), len(already_received),
    )
    return eligible


async def _apply_airdrops(user_ids: set[int]) -> list[dict]:
    """
    Hak kazanan kullanıcılara TUCi yükle ve transaction logu yaz.
    Döner: [{"user_id": int, "fcm_token": str|None}, ...]
    """
    if not user_ids:
        return []

    from app.database import AsyncSessionLocal
    from sqlalchemy import text

    uid_list = list(user_ids)

    async with AsyncSessionLocal() as db:
        # Bakiyeleri toplu güncelle
        await db.execute(
            text("""
                UPDATE users
                SET tuci_balance = tuci_balance + :amount
                WHERE id = ANY(:uids) AND is_active = TRUE
            """),
            {"amount": _AIRDROP_AMOUNT, "uids": uid_list},
        )

        # Transaction loglarını toplu ekle
        await db.execute(
            text("""
                INSERT INTO tuci_transactions (user_id, amount, transaction_type, created_at)
                SELECT u, :amount, :ttype, NOW()
                FROM unnest(CAST(:uids AS BIGINT[])) AS u
            """),
            {"amount": _AIRDROP_AMOUNT, "ttype": _AIRDROP_TYPE, "uids": uid_list},
        )

        # Push için FCM tokenları çek (tek sorguda)
        rows = await db.execute(
            text("""
                SELECT id, fcm_token
                FROM users
                WHERE id = ANY(:uids) AND is_active = TRUE
            """),
            {"uids": uid_list},
        )
        recipients = [{"user_id": row[0], "fcm_token": row[1]} for row in rows.fetchall()]

        await db.commit()

    logger.info("[ChurnAirdrop] %d kullanıcıya %d TUCi yüklendi.", len(recipients), _AIRDROP_AMOUNT)
    return recipients


async def _send_airdrop_notifications(recipients: list[dict], is_seller: bool = False) -> None:
    """Her alıcıya push bildirimi gönder (batch'ler hâlinde)."""
    from app.routers.notifications import push_notification

    _i18n = {
        "title_key": "notifChurnAirdropSeller" if is_seller else "notifChurnAirdropBuyer",
        "body_key": "notifChurnBodySeller" if is_seller else "notifChurnBodyBuyer",
        "body_params": {"amount": _AIRDROP_AMOUNT},
    }

    async def _notify(r: dict) -> None:
        try:
            await push_notification(
                user_id=r["user_id"],
                notif={
                    "type": "churn_airdrop",
                    "i18n": _i18n,
                },
                pref_key=None,  # Cüzdan kredisi — tercih filtresi atlanır
            )
        except Exception as exc:
            logger.warning(
                "[ChurnAirdrop] Push gönderilemedi | user_id=%s | %s",
                r["user_id"], exc,
            )

    for i in range(0, len(recipients), _BATCH_SIZE):
        batch = recipients[i : i + _BATCH_SIZE]
        await asyncio.gather(*[_notify(r) for r in batch])

    logger.info("[ChurnAirdrop] %d push bildirimi gönderildi (satıcı=%s).", len(recipients), is_seller)


# ── Ana görev ──────────────────────────────────────────────────────────────────

async def process_churn_and_airdrop(ctx: dict) -> None:
    """
    ARQ cron görevi — her gün 03:30'da çalışır.
    ClickHouse analizinden riskli alıcıları ve inaktif satıcıları tespit eder,
    son 30 günde airdrop almamışlara 10 TUCi yükler ve role özel bildirim gönderir.
    """
    logger.info("[ChurnAirdrop] Görev başlatıldı.")
    try:
        buyer_ids, seller_ids = await _fetch_risky_user_ids()
        all_risky = buyer_ids | seller_ids

        if not all_risky:
            logger.info("[ChurnAirdrop] Riskli kullanıcı bulunamadı, görev tamamlandı.")
            return

        eligible_ids = await _filter_already_received(all_risky)
        if not eligible_ids:
            logger.info("[ChurnAirdrop] Tüm riskli kullanıcılar zaten airdrop aldı, atlanıyor.")
            return

        eligible_buyers = eligible_ids & buyer_ids
        eligible_sellers = eligible_ids & seller_ids

        buyer_recipients = await _apply_airdrops(eligible_buyers)
        seller_recipients = await _apply_airdrops(eligible_sellers)

        await _send_airdrop_notifications(buyer_recipients, is_seller=False)
        await _send_airdrop_notifications(seller_recipients, is_seller=True)

        logger.info(
            "[ChurnAirdrop] Görev tamamlandı | alıcı_airdrop=%d | satıcı_airdrop=%d",
            len(buyer_recipients), len(seller_recipients),
        )
    except Exception as exc:
        logger.error("[ChurnAirdrop] Görev başarısız: %s", exc, exc_info=True)
        capture_exception(exc)
        raise


# ── Highlight GC ───────────────────────────────────────────────────────────────

_HIGHLIGHTS_DIR = pathlib.Path(__file__).resolve().parents[2] / "static" / "highlights"
_HIGHLIGHT_MAX_AGE_SECS = 7_200   # 2 saat

async def cleanup_hype_highlights_task(ctx: dict) -> None:
    """
    ARQ cron görevi — her saat çalışır.

    1. backend/static/highlights/ içindeki 2 saatten eski .mp4 dosyalarını siler.
    2. DB'de expires_at süresi dolmuş highlight listing kayıtlarını temizler.

    Güvenlik ağı: yayıncı internetten düşerse stream_service.end() çağrılmaz;
    bu görev garanti temizliği sağlar.
    """
    logger.info("[HighlightGC] Görev başlatıldı.")
    deleted_files = 0
    deleted_rows = 0

    # 1. Disk temizliği
    try:
        if _HIGHLIGHTS_DIR.exists():
            now = time.time()
            for f in _HIGHLIGHTS_DIR.glob("*.mp4"):
                try:
                    age = now - f.stat().st_mtime
                    if age > _HIGHLIGHT_MAX_AGE_SECS:
                        os.remove(f)
                        deleted_files += 1
                        logger.info("[HighlightGC] Dosya silindi | %s (yaş=%.0fs)", f.name, age)
                except Exception as exc:
                    logger.warning("[HighlightGC] Dosya silinemedi | %s | %s", f, exc)
    except Exception as exc:
        logger.error("[HighlightGC] Disk tarama hatası | %s", exc, exc_info=True)

    # 2. DB temizliği
    try:
        from app.database import AsyncSessionLocal
        from sqlalchemy import text

        async with AsyncSessionLocal() as db:
            result = await db.execute(
                text("""
                    DELETE FROM listings
                    WHERE is_highlight = TRUE
                      AND expires_at IS NOT NULL
                      AND expires_at < NOW()
                """)
            )
            deleted_rows = result.rowcount
            await db.commit()
    except Exception as exc:
        logger.error("[HighlightGC] DB temizliği hatası | %s", exc, exc_info=True)

    logger.info(
        "[HighlightGC] Tamamlandı | silinen_dosya=%d silinen_kayıt=%d",
        deleted_files, deleted_rows,
    )
