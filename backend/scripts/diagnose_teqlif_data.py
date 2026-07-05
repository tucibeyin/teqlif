import asyncio
from sqlalchemy import select, text
from app.database import AsyncSessionLocal
from app.models.user import User

async def main():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.email == 'teqlif@gmail.com'))
        user = res.scalar_one_or_none()
        if not user:
            print("teqlif@gmail.com not found!")
            return
            
        uid = user.id
        print(f"--- TEQLIF KULLANICISI (ID: {uid}) VERI ANALIZI ---\n")

        # 1. ILANLARI AL
        l_res = await db.execute(text("SELECT id, title, category FROM listings WHERE user_id = :uid AND is_active = TRUE AND is_deleted = FALSE"), {"uid": uid})
        active_listings = l_res.fetchall()
        print(f"Aktif Ilan Sayisi: {len(active_listings)}")
        listing_ids = [str(l[0]) for l in active_listings]
        categories = list(set([l[2] for l in active_listings]))
        
        for l in active_listings:
            print(f"  - ID: {l[0]} | Title: '{l[1]}' | Cat: {l[2]}")
        
        if not listing_ids:
            print("\nAktif ilan bulunamadı.")
            return

        ids_str = ",".join(listing_ids)

        # 2. CLICKHOUSE ANALİZİ (Pro Insights ve Reklam Performansı için asıl kullanılan yer)
        print("\n--- 1. PRO ARAÇLAR (ClickHouse user_events Tablosu) ---")
        try:
            from app.database_clickhouse import get_clickhouse_client
            ch = await get_clickhouse_client()
            
            # Funnel Analizi
            ch_r = await ch.query(f"""
                SELECT
                    countIf(event_type = 'view') AS views,
                    countIf(event_type = 'dwell') AS dwells,
                    countDistinctIf(user_id, event_type = 'bid_hesitation') AS hesitations,
                    countIf(event_type = 'search') AS searches,
                    countIf(event_type = 'click') AS clicks
                FROM user_events
                WHERE item_type = 'listing'
                  AND item_id IN ({ids_str})
                  AND timestamp >= now() - INTERVAL 90 DAY
            """)
            if ch_r.result_rows:
                r = ch_r.result_rows[0]
                print(f"Son 90 Gün ClickHouse İlan Etkileşimleri:")
                print(f"  Views: {r[0]}, Dwells: {r[1]}, Hesitations: {r[2]}")
                print(f"  Searches: {r[3]}, Clicks: {r[4]}")
                
            # Kategori aramaları
            cats_str = ",".join([f"'{c}'" for c in categories])
            ch_cat = await ch.query(f"""
                SELECT category, count(*) as count
                FROM user_events 
                WHERE event_type = 'search' 
                  AND category IN ({cats_str})
                  AND timestamp >= now() - INTERVAL 30 DAY
                GROUP BY category
            """)
            print("\nSon 30 Gün Kategori Aramaları (ClickHouse):")
            for row in ch_cat.result_rows:
                print(f"  - {row[0]}: {row[1]} arama")

        except Exception as e:
            print(f"ClickHouse bağlantı hatası: {e}")

        # 3. REKLAM KAMPANYALARI (PostgreSQL + ClickHouse)
        print("\n--- 2. REKLAM PERFORMANSI ---")
        ad_res = await db.execute(text("SELECT id, listing_id, status FROM ad_campaigns WHERE seller_id = :uid"), {"uid": uid})
        ads = ad_res.fetchall()
        print(f"Toplam Reklam Kampanyası: {len(ads)}")
        
        ad_ids = [str(a[0]) for a in ads]
        for a in ads:
            print(f"  - Ad ID: {a[0]} | Listing ID: {a[1]} | Status: {a[2]}")
            
        if ad_ids:
            try:
                ad_ids_str = ",".join(ad_ids)
                ch_ad_r = await ch.query(f"""
                    SELECT 
                        item_id,
                        countIf(event_type = 'ad_impression') AS impr,
                        countIf(event_type = 'ad_click') AS clks
                    FROM user_events
                    WHERE item_type = 'ad_campaign'
                      AND item_id IN ({ad_ids_str})
                    GROUP BY item_id
                """)
                print("Reklam ClickHouse (user_events) Metrikleri:")
                for r in ch_ad_r.result_rows:
                    ctr = round(r[2] / r[1] * 100, 2) if r[1] > 0 else 0.0
                    print(f"  - Ad ID: {r[0]} | Impressions: {r[1]} | Clicks: {r[2]} | CTR: %{ctr}")
            except Exception as e:
                print(f"Ad ClickHouse query hatası: {e}")

        # 4. POSTGRESQL ESKI ANALITIK TABLOSU (AI Metrikleri'nin şu an kullandığı)
        print("\n--- 3. AI METRİKLERİ SORUNU (PostgreSQL analytics_events) ---")
        ae_res = await db.execute(text(f"""
            SELECT event_type, COUNT(*) 
            FROM analytics_events 
            WHERE (event_metadata->>'item_id')::int IN ({ids_str})
            GROUP BY event_type
        """))
        pg_events = ae_res.fetchall()
        print("İlanlarınız için PostgreSQL 'analytics_events' tablosundaki veriler:")
        if not pg_events:
            print("  [BOMBOŞ] - Hiç veri yok!")
        else:
            for e in pg_events:
                print(f"  - {e[0]}: {e[1]}")

        print("\n=== SONUÇ & ASIL PROBLEM ===")
        print("Teqlif sisteminde analiz verileri (Pro Insights, Funnel, Reklam) yeni ve hızlı olan")
        print("'ClickHouse' (user_events) veritabanına taşınmış/kaydedilmektedir. Sizin de bahsettiğiniz")
        print("gibi orada bolca veri (gösterim, arama, tıklama) bulunmaktadır.")
        print("\nAncak AI Metrikleri endpoint'i (/pro/metrics) eski (legacy) PostgreSQL")
        print("'analytics_events' ve 'listing_impressions' tablolarını kullanmaya devam etmektedir.")
        print("Yeni veriler ClickHouse'a aktığı için, PostgreSQL tabloları boş (veya güncel değil) kalmakta,")
        print("bu nedenle AI Metrikleri tüm istatistikleri 0 veya None olarak göstermektedir.")
        print("Çözüm: AI Metrikleri sorgularının ClickHouse altyapısına geçirilmesidir!")

if __name__ == "__main__":
    asyncio.run(main())
