"""
İlan Analizleri ekranı verilerini doğrular (video-roi, gallery-stats, video-performance).

VPS:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/listing_analytics_check.py [user_id] [days]
"""
import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

UID  = int(sys.argv[1]) if len(sys.argv) > 1 else 3
DAYS = int(sys.argv[2]) if len(sys.argv) > 2 else 30


def sep(title):
    print(f"\n{'━'*65}")
    print(f"  {title}")
    print(f"{'━'*65}")


async def main():
    from sqlalchemy import select
    from app.database import AsyncSessionLocal
    from app.database_clickhouse import get_clickhouse_client
    from app.models.listing import Listing

    async with AsyncSessionLocal() as db:
        listings = (await db.execute(
            select(Listing.id, Listing.title, Listing.video_url, Listing.image_urls)
            .where(Listing.user_id == UID, Listing.is_deleted == False)  # noqa
        )).fetchall()

        if not listings:
            print("İlan bulunamadı."); return

        listing_map = {str(r.id): {"title": r.title, "has_video": bool(r.video_url)} for r in listings}
        listing_ids_str = ", ".join(f"'{r.id}'" for r in listings)
        listing_ids_int = ", ".join(str(r.id) for r in listings)

        ch = await get_clickhouse_client()

        # ── 1. Video ROI — feed_analytics content_type bazında ────────────
        sep(f"1. VİDEO ROI  (video-roi, son {DAYS} gün)")
        seg_rows = (await ch.query(f"""
            SELECT
                content_type,
                countIf(event_type='impression')                                      AS impressions,
                countIf(event_type='click')                                           AS clicks,
                if(impressions>0, round(toFloat64(clicks)/impressions*100, 2), 0)     AS ctr,
                round(avgIf(dwell_time_ms, event_type IN ('impression','skip')), 0)   AS avg_dwell_ms
            FROM feed_analytics
            WHERE timestamp >= now() - INTERVAL {DAYS} DAY
              AND listing_id IN ({listing_ids_str})
            GROUP BY content_type
        """)).result_rows

        print(f"  {'content_type':<12}  {'impression':>11}  {'click':>6}  {'CTR%':>6}  {'dwell_ms':>9}")
        print(f"  {'─'*50}")
        for row in seg_rows:
            ct, imp, clk, ctr, dwell = row
            print(f"  {ct:<12}  {imp:>11}  {clk:>6}  {float(ctr):>6.2f}  {int(dwell):>9}")
        if not seg_rows:
            print("  (kayıt yok)")

        # ── İlan bazında video-roi ─────────────────────────────────────────
        print(f"\n  İlan bazında:")
        per_rows = (await ch.query(f"""
            SELECT
                listing_id,
                content_type,
                countIf(event_type='impression')                                      AS impressions,
                countIf(event_type='click')                                           AS clicks,
                if(impressions>0, round(toFloat64(clicks)/impressions*100, 2), 0)     AS ctr
            FROM feed_analytics
            WHERE timestamp >= now() - INTERVAL {DAYS} DAY
              AND listing_id IN ({listing_ids_str})
            GROUP BY listing_id, content_type
            ORDER BY impressions DESC
            LIMIT 20
        """)).result_rows

        print(f"  {'ID':<6}  {'type':<8}  {'imp':>6}  {'clk':>5}  {'CTR%':>6}  Başlık")
        print(f"  {'─'*55}")
        for row in per_rows:
            lid, ct, imp, clk, ctr = row
            title = listing_map.get(str(lid), {}).get("title", "?")[:25]
            has_v = "🎬" if listing_map.get(str(lid), {}).get("has_video") else "📷"
            print(f"  {lid:<6}  {ct:<8}  {imp:>6}  {clk:>5}  {float(ctr):>6.2f}  {has_v} {title}")
        if not per_rows:
            print("  (kayıt yok)")

        # ── 2. Gallery Stats — user_events listing_photo_swipe ────────────
        sep(f"2. GALERİ İSTATİSTİKLERİ  (gallery-stats, son {DAYS} gün)")
        import json as _json
        photo_count_map: dict[int, int] = {}
        for r in listings:
            try:
                urls = _json.loads(r.image_urls) if r.image_urls else []
                photo_count_map[r.id] = max(1, len(urls))
            except Exception:
                photo_count_map[r.id] = 1

        gal_rows = (await ch.query(f"""
            SELECT
                item_id,
                COUNT(*)                        AS views,
                round(avg(duration_seconds), 1) AS avg_depth,
                max(duration_seconds)           AS max_depth
            FROM user_events
            WHERE item_type='listing'
              AND event_type='listing_photo_swipe'
              AND item_id IN ({listing_ids_int})
              AND timestamp >= now() - INTERVAL {DAYS} DAY
            GROUP BY item_id
            ORDER BY avg_depth DESC
            LIMIT 20
        """)).result_rows

        print(f"  {'ID':<6}  {'views':>6}  {'avg_depth':>10}  {'max_depth':>10}  {'toplam_fotoğraf':>15}  {'derinlik%':>10}  Başlık")
        print(f"  {'─'*75}")
        for row in gal_rows:
            lid, views, avg_d, max_d = row
            total_p = photo_count_map.get(int(lid), 1)
            depth_pct = round(min(100.0, float(avg_d or 0) / total_p * 100), 1) if total_p > 0 else 0
            title = next((r.title for r in listings if r.id == int(lid)), "?")[:20]
            print(f"  {lid:<6}  {int(views):>6}  {float(avg_d or 0):>10.1f}  {int(max_d or 0):>10}  {total_p:>15}  {depth_pct:>10.1f}%  {title}")
        if not gal_rows:
            print("  (listing_photo_swipe kaydı yok)")

        # ── 3. Video Performance — tamamlanma oranı ───────────────────────
        sep(f"3. VİDEO PERFORMANSI  (video-performance, son {DAYS} gün)")
        video_listings = [r for r in listings if r.video_url]
        print(f"  Video içeren ilan sayısı: {len(video_listings)}")

        if video_listings:
            vid_ids = ", ".join(str(r.id) for r in video_listings)
            vid_rows = (await ch.query(f"""
                SELECT
                    item_id,
                    COUNT(*)                            AS plays,
                    round(avg(duration_seconds), 1)     AS avg_watch_sec,
                    max(duration_seconds)               AS max_watch_sec
                FROM user_events
                WHERE item_type='listing'
                  AND event_type='video_watch'
                  AND item_id IN ({vid_ids})
                  AND timestamp >= now() - INTERVAL {DAYS} DAY
                GROUP BY item_id
                ORDER BY plays DESC
            """)).result_rows

            print(f"  {'ID':<6}  {'plays':>6}  {'avg_watch_s':>12}  {'max_watch_s':>12}  Başlık")
            print(f"  {'─'*55}")
            for row in vid_rows:
                lid, plays, avg_w, max_w = row
                title = next((r.title for r in video_listings if r.id == int(lid)), "?")[:25]
                print(f"  {lid:<6}  {int(plays):>6}  {float(avg_w or 0):>12.1f}  {int(max_w or 0):>12}  {title}")
            if not vid_rows:
                print("  (video_watch kaydı yok)")
        else:
            print("  (video içeren ilan yok)")

    print()


asyncio.run(main())
