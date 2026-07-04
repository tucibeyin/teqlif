"""
Geri Hedefleme ekranı verilerini doğrular (retargeting-audience).
İlk aktif ilanı otomatik seçer; argüman ile override edilebilir.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/retargeting_check.py [user_id] [listing_id]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UID        = int(sys.argv[1]) if len(sys.argv) > 1 else 3
LISTING_ID = int(sys.argv[2]) if len(sys.argv) > 2 else None


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from sqlalchemy import select, text
    from app.database import AsyncSessionLocal
    from app.database_clickhouse import get_clickhouse_client
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:

        # ── Hedef ilanı bul ───────────────────────────────────────────────
        q = select(Listing).where(
            Listing.user_id == UID,
            Listing.is_active == True,  # noqa
            Listing.is_deleted == False,  # noqa
        )
        if LISTING_ID:
            q = q.where(Listing.id == LISTING_ID)
        else:
            q = q.limit(1)

        listing = (await db.execute(q)).scalar_one_or_none()
        if not listing:
            print("Aktif ilan bulunamadı."); return

        sep(f"HEDEF İLAN #{listing.id}: {listing.title}")

        ch = await get_clickhouse_client()

        # ── 1. ClickHouse: viewer_ids ────────────────────────────────────
        sep("1. GÖRÜNTÜLEYEN KULLANICI SAYISI  (user_events — son 30 gün)")

        # Ekranın kullandığı event_type'lar
        for et in ['view', 'dwell', 'detail_dwell', 'click',
                   'listing_photo_swipe', 'listing_video_watch']:
            cnt = (await ch.query(f"""
                SELECT COUNT(DISTINCT user_id)
                FROM user_events
                WHERE item_id = {listing.id}
                  AND event_type = '{et}'
                  AND timestamp >= now() - INTERVAL 30 DAY
                  AND user_id != {UID}
                  AND user_id != 0
            """)).result_rows[0][0]
            print(f"  {et:<25}: {int(cnt)} eşsiz kullanıcı")

        # Backend'in sorguladığı eventler (view + dwell + detail_dwell + click)
        vid_result = await ch.query(f"""
            SELECT DISTINCT user_id
            FROM user_events
            WHERE item_id = {listing.id}
              AND event_type IN ('view', 'dwell', 'detail_dwell', 'click')
              AND timestamp >= now() - INTERVAL 30 DAY
              AND user_id != {UID}
              AND user_id != 0
            LIMIT 500
        """)
        viewer_ids = [int(r[0]) for r in vid_result.result_rows]
        total_viewers = len(viewer_ids)
        print(f"\n  → Backend'in saydığı total_viewers_30d: {total_viewers}")

        # listing_impressions tablosundaki kayıt sayısı (karşılaştırma için)
        imp_count = (await db.execute(text("""
            SELECT COUNT(*) FROM listing_impressions
            WHERE listing_id = :lid AND user_id != :uid
        """), {"lid": listing.id, "uid": UID})).scalar()
        print(f"  → listing_impressions (farklı kaynak): {imp_count} eşsiz kullanıcı")

        if total_viewers == 0 and imp_count > 0:
            print("  ⚠ listing_impressions'da görüntüleme var ama user_events'da 'view/dwell/click' yok")
            print("    → Retargeting için doğru event_type gönderilmiyor olabilir")

        # ── 2. PostgreSQL: already_bought ────────────────────────────────
        sep("2. SATIN ALANLAR  (auctions tablosu)")
        buyer_result = (await db.execute(text("""
            SELECT COUNT(*) FROM auctions
            WHERE listing_id = :lid AND winner_username IS NOT NULL AND status = 'completed'
        """), {"lid": listing.id})).scalar()
        already_bought = int(buyer_result or 0)
        print(f"  Satın alan sayısı (status=completed): {already_bought}")

        # ── 3. FCM token sayısı ───────────────────────────────────────────
        sep("3. ULAŞILABİLİR KİTLE  (FCM token)")
        reachable = 0
        if viewer_ids:
            token_count = (await db.execute(text("""
                SELECT COUNT(*) FROM users
                WHERE id = ANY(:ids) AND fcm_token IS NOT NULL AND fcm_token != ''
            """), {"ids": viewer_ids})).scalar()
            reachable = int(token_count or 0)
        print(f"  FCM tokenlı izleyici: {reachable}")
        print(f"\n  → Ekranda gösterilecek:")
        print(f"     total_viewers_30d  : {total_viewers}")
        print(f"     already_bought     : {already_bought}")
        print(f"     reachable_audience : {reachable}")

        # ── 4. Blast credits ──────────────────────────────────────────────
        sep("4. BLAST KREDİLERİ  (Redis)")
        try:
            import calendar
            from datetime import datetime, timezone
            now = datetime.now(timezone.utc)
            month_key = f"blast_credits:{UID}:{now.year}:{now.month}"
            from app.database_redis import get_redis
            redis = await get_redis()
            used_raw = await redis.get(month_key)
            used = int(used_raw) if used_raw else 0
            _BLAST_LIMIT_PRO = 5
            remaining = max(0, _BLAST_LIMIT_PRO - used)
            print(f"  Bu ay kullanılan: {used} / {_BLAST_LIMIT_PRO}")
            print(f"  Kalan           : {remaining}")
            print(f"  is_free         : {'Evet' if remaining > 0 else 'Hayır'}")
        except Exception as e:
            print(f"  ⚠ Redis hatası: {e}")

    print()


asyncio.run(main())
