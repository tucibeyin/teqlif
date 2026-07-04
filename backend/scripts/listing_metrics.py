"""
İlan metriklerini tüm kaynaklardan karşılaştırır.

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/listing_metrics.py <listing_id>
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LISTING_ID = int(sys.argv[1]) if len(sys.argv) > 1 else 2


async def main():
    from sqlalchemy import select, func, text
    from app.database import AsyncSessionLocal
    from app.database_clickhouse import get_clickhouse_client
    from app.models.listing import Listing
    from app.models.user import User
    from app.models.listing_impression import ListingImpression

    async with AsyncSessionLocal() as db:
        # ── 1. İlan temel bilgisi ─────────────────────────────────────────
        row = (await db.execute(
            select(Listing, User).join(User, User.id == Listing.user_id).where(Listing.id == LISTING_ID)
        )).first()
        if not row:
            print(f"İlan {LISTING_ID} bulunamadı."); return
        listing, user = row

        print(f"\n{'━'*65}")
        print(f"  İLAN #{listing.id}: {listing.title}")
        print(f"  Sahip: @{user.username}  |  Kategori: {listing.category}")
        print(f"{'━'*65}")

        # ── 2. PostgreSQL: listing_impressions ────────────────────────────
        # "X kişi gördü" kaynağı — hem organik hem sponsored gösterimler
        pg_unique = (await db.execute(
            select(func.count(func.distinct(ListingImpression.user_id)))
            .where(ListingImpression.listing_id == LISTING_ID)
        )).scalar() or 0

        pg_total = (await db.execute(
            select(func.count())
            .where(ListingImpression.listing_id == LISTING_ID)
        )).scalar() or 0

        pg_rows = (await db.execute(
            select(ListingImpression.user_id, ListingImpression.seen_at)
            .where(ListingImpression.listing_id == LISTING_ID)
            .order_by(ListingImpression.seen_at)
        )).all()

        print(f"\n[PostgreSQL — listing_impressions]")
        print(f"  Unique kişi (X kişi gördü)  : {pg_unique}")
        print(f"  Toplam kayıt                : {pg_total}")
        if pg_rows:
            print(f"  Kayıtlar:")
            for uid, seen_at in pg_rows:
                print(f"    user_id={uid}  seen_at={seen_at}")

        # ── 3. ClickHouse: feed_analytics (swipe/organic) ─────────────────
        # İlan Analizleri (+66 gösterim, %10.6 CTR) kaynağı
        ch = await get_clickhouse_client()

        feed_result = await ch.query(f"""
            SELECT
                event_type,
                count() AS cnt
            FROM feed_analytics
            WHERE listing_id = '{LISTING_ID}'
            GROUP BY event_type
            ORDER BY cnt DESC
        """)
        feed_rows = feed_result.result_rows

        print(f"\n[ClickHouse — feed_analytics (organik swipe feed)]")
        if feed_rows:
            for r in feed_rows:
                print(f"  event_type={r[0]:<20}  count={r[1]}")
        else:
            print("  (kayıt yok)")

        # ── 4. ClickHouse: user_events (reklam) ───────────────────────────
        # Reklam Performansı (164 gösterim, 4 tıklama) kaynağı
        # Kampanya ID'sini bul
        from app.models.ad_campaign import AdCampaign
        campaigns = (await db.execute(
            select(AdCampaign).where(AdCampaign.listing_id == LISTING_ID)
        )).scalars().all()

        print(f"\n[PostgreSQL — ad_campaigns]")
        if campaigns:
            for c in campaigns:
                print(f"  campaign_id={c.id}  status={c.status}  budget={c.budget}  spent={c.spent}")
        else:
            print("  (reklam kampanyası yok)")

        if campaigns:
            campaign_ids = [str(c.id) for c in campaigns]
            ids_str = ", ".join(campaign_ids)

            ad_result = await ch.query(f"""
                SELECT
                    event_type,
                    count() AS cnt
                FROM user_events
                WHERE campaign_id IN ({ids_str})
                  AND event_type IN ('ad_impression', 'ad_click')
                GROUP BY event_type
                ORDER BY event_type
            """)
            ad_rows = ad_result.result_rows

            print(f"\n[ClickHouse — user_events (reklam ad_impression/ad_click)]")
            if ad_rows:
                for r in ad_rows:
                    print(f"  event_type={r[0]:<20}  count={r[1]}")
            else:
                print("  (kayıt yok)")

        # ── 5. Özet ──────────────────────────────────────────────────────
        print(f"\n{'━'*65}")
        print(f"  ÖZET")
        print(f"{'━'*65}")
        print(f"  'X kişi gördü'     → PG listing_impressions unique user = {pg_unique}")

        feed_imp = next((r[1] for r in feed_rows if r[0] == 'impression'), 0) if feed_rows else 0
        feed_clk = next((r[1] for r in feed_rows if r[0] == 'click'), 0) if feed_rows else 0
        print(f"  İlan Analizleri    → CH feed_analytics impression={feed_imp}  click={feed_clk}")

        if campaigns and ad_rows:
            ad_imp = next((r[1] for r in ad_rows if r[0] == 'ad_impression'), 0)
            ad_clk = next((r[1] for r in ad_rows if r[0] == 'ad_click'), 0)
            print(f"  Reklam Performansı → CH user_events  ad_impression={ad_imp}  ad_click={ad_clk}")

        print()


asyncio.run(main())
