import asyncio
from sqlalchemy import select, text
from app.database import AsyncSessionLocal
from app.models.user import User

async def main():
    async with AsyncSessionLocal() as db:
        # Find teqlif user
        res = await db.execute(select(User).where(User.email == 'teqlif@gmail.com'))
        user = res.scalar_one_or_none()
        
        if not user:
            print("User teqlif@gmail.com not found!")
            return
            
        uid = user.id
        print(f"Testing AI Metrics for {user.email} (ID: {uid})")
        print("-" * 50)

        # 1. Ortalama Detay İnceleme Süresi
        dwell_result = await db.execute(text("""
            SELECT AVG((event_metadata->>'duration_seconds')::float) AS avg_dwell
            FROM analytics_events ae
            INNER JOIN listings l ON l.id = (ae.event_metadata->>'item_id')::int
            WHERE l.user_id = :uid
              AND ae.event_type = 'detail_dwell'
              AND ae.created_at > NOW() - INTERVAL '30 days'
              AND ae.event_metadata->>'duration_seconds' IS NOT NULL
        """), {"uid": uid})
        dwell_row = dwell_result.fetchone()
        avg_dwell = round(float(dwell_row[0]), 1) if dwell_row and dwell_row[0] else None
        print(f"1. Average Detail Dwell: {avg_dwell} seconds")

        # 2. Arama Görünürlüğü (MEVCUT KUSURLU YAPI)
        vis_result_current = await db.execute(text("""
            SELECT l.category, COUNT(ae.id) AS search_count
            FROM listings l
            INNER JOIN analytics_events ae
                ON ae.event_type = 'search'
                AND ae.event_metadata->>'category' = l.category
                AND ae.created_at > NOW() - INTERVAL '30 days'
            WHERE l.user_id = :uid AND l.is_active = TRUE AND l.is_deleted = FALSE
            GROUP BY l.category
            ORDER BY search_count DESC
            LIMIT 5
        """), {"uid": uid})
        
        # 2. Arama Görünürlüğü (DÜZELTİLMİŞ YAPI)
        vis_result_fixed = await db.execute(text("""
            SELECT l.category, COUNT(DISTINCT ae.id) AS search_count
            FROM listings l
            INNER JOIN analytics_events ae
                ON ae.event_type = 'search'
                AND ae.event_metadata->>'category' = l.category
                AND ae.created_at > NOW() - INTERVAL '30 days'
            WHERE l.user_id = :uid AND l.is_active = TRUE AND l.is_deleted = FALSE
            GROUP BY l.category
            ORDER BY search_count DESC
            LIMIT 5
        """), {"uid": uid})
        
        print("\n2. Search Visibility (Category Searches):")
        print("  [CURRENT / BUGGY]")
        for row in vis_result_current.all():
            print(f"   - {row[0]}: {int(row[1])} searches")
            
        print("  [FIXED / CORRECTED]")
        for row in vis_result_fixed.all():
            print(f"   - {row[0]}: {int(row[1])} searches")

        # 3. En İyi Paylaşım Saati (MEVCUT KUSURLU YAPI)
        hour_result_current = await db.execute(text("""
            SELECT
                EXTRACT(HOUR FROM l.created_at) AS hour,
                COUNT(ae.id) AS clicks,
                COUNT(DISTINCT imp.user_id) AS impressions,
                (COUNT(ae.id)::float / NULLIF(COUNT(DISTINCT imp.user_id), 0)) AS ctr
            FROM listings l
            LEFT JOIN analytics_events ae
                ON ae.event_type = 'click'
                AND ae.event_metadata->>'item_id' = l.id::text
                AND ae.created_at > NOW() - INTERVAL '30 days'
            LEFT JOIN listing_impressions imp ON imp.listing_id = l.id
            WHERE l.user_id = :uid
              AND l.created_at > NOW() - INTERVAL '90 days'
            GROUP BY hour
            HAVING COUNT(DISTINCT imp.user_id) >= 10
            ORDER BY ctr DESC
            LIMIT 3
        """), {"uid": uid})
        
        # 3. En İyi Paylaşım Saati (DÜZELTİLMİŞ YAPI)
        hour_result_fixed = await db.execute(text("""
            SELECT
                EXTRACT(HOUR FROM l.created_at) AS hour,
                COUNT(DISTINCT ae.id) AS clicks,
                COUNT(DISTINCT imp.user_id) AS impressions,
                (COUNT(DISTINCT ae.id)::float / NULLIF(COUNT(DISTINCT imp.user_id), 0)) AS ctr
            FROM listings l
            LEFT JOIN analytics_events ae
                ON ae.event_type = 'click'
                AND ae.event_metadata->>'item_id' = l.id::text
                AND ae.created_at > NOW() - INTERVAL '30 days'
            LEFT JOIN listing_impressions imp ON imp.listing_id = l.id
            WHERE l.user_id = :uid
              AND l.created_at > NOW() - INTERVAL '90 days'
            GROUP BY hour
            HAVING COUNT(DISTINCT imp.user_id) >= 10
            ORDER BY ctr DESC
            LIMIT 3
        """), {"uid": uid})
        
        print("\n3. Best Posting Hour:")
        print("  [CURRENT / BUGGY]")
        for row in hour_result_current.all():
            print(f"   - Hour {int(row[0])}: {int(row[1])} clicks, {int(row[2])} unique impressions (CTR: {round(float(row[3] or 0)*100, 2)}%)")
            
        print("  [FIXED / CORRECTED]")
        for row in hour_result_fixed.all():
            print(f"   - Hour {int(row[0])}: {int(row[1])} clicks, {int(row[2])} unique impressions (CTR: {round(float(row[3] or 0)*100, 2)}%)")

        # 4. Geri Dönen İzleyici Oranı
        return_result = await db.execute(text("""
            WITH viewer_counts AS (
                SELECT lsv.user_id, COUNT(DISTINCT ls.id) AS stream_count
                FROM live_stream_viewers lsv
                INNER JOIN live_streams ls ON ls.id = lsv.stream_id AND ls.host_id = :uid
                WHERE lsv.user_id != :uid
                  AND lsv.joined_at >= NOW() - INTERVAL '180 days'
                GROUP BY lsv.user_id
            )
            SELECT
                COUNT(*) FILTER (WHERE stream_count >= 2)::float /
                NULLIF(COUNT(*), 0) AS return_rate,
                COUNT(*) AS total_viewers,
                COUNT(*) FILTER (WHERE stream_count >= 2) AS return_viewers
            FROM viewer_counts
        """), {"uid": uid})
        ret_row = return_result.fetchone()
        
        print("\n4. Return Viewer Rate:")
        if ret_row and ret_row[0] is not None:
            print(f"   - Return Rate: {round(float(ret_row[0]) * 100, 1)}%")
            print(f"   - Total Unique Viewers: {int(ret_row[1])}")
            print(f"   - Returning Viewers (>=2 streams): {int(ret_row[2])}")
        else:
            print("   - No streams or viewers in the last 180 days.")

if __name__ == "__main__":
    asyncio.run(main())
