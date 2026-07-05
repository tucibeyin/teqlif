import asyncio
import httpx
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from main import app
from app.utils.auth import create_access_token

async def main():
    async with AsyncSessionLocal() as db:
        res = await db.execute(select(User).where(User.email == 'teqlif@gmail.com'))
        user = res.scalar_one_or_none()
        if not user:
            print("teqlif@gmail.com not found!")
            return
            
        uid = user.id
        token = create_access_token(uid)
        
        # Get user's ad campaigns directly from db
        ad_res = await db.execute(select(AdCampaign).where(AdCampaign.seller_id == uid))
        campaigns = ad_res.scalars().all()
        
    print(f"--- TEQLIF KULLANICISI (ID: {uid}) SISTEM TUTARLILIK TESTI ---\n")
    headers = {"Authorization": f"Bearer {token}"}
    
    # httpx.ASGITransport'ı kullanarak FastAPI uygulamasını ağa çıkmadan (in-memory) test ediyoruz.
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        
        # 1. Pro Insights (Tüm Pro Araçlar Modülleri)
        print("1. [GET] /api/analytics/pro-insights")
        r_insights = await client.get("/api/analytics/pro-insights", headers=headers)
        if r_insights.status_code == 200:
            data = r_insights.json()
            funnel = data.get("funnel", {})
            kpis = data.get("kpis", {})
            hot_leads = data.get("hot_leads", [])
            price_intel = data.get("price_intel", [])
            stream_stats = data.get("stream_stats", {})
            peak_hours = data.get("peak_hours", [])
            tips = data.get("tips", [])
            
            print("  ✅ Başarılı!")
            print(f"\n  --- A. Satıcı KPI'ları (KPIs) ---")
            print(f"    * Toplam İlan: {kpis.get('total_listings')} (Aktif: {kpis.get('active_listings')})")
            print(f"    * 30 Günlük Gelir: ₺{kpis.get('revenue_30d')} (Büyüme: %{kpis.get('revenue_growth_pct') or 0})")
            print(f"    * 30 Günlük Satış: {kpis.get('sales_30d')} | Teklifler: {kpis.get('bids_30d')}")
            
            print(f"\n  --- B. Dönüşüm Hunisi (Funnel) ---")
            print(f"    * Views: {funnel.get('views')} | Hesitations: {funnel.get('hesitations')}")
            print(f"    * Bids: {funnel.get('bids')} | Sales: {funnel.get('sales')}")
            print(f"    * Dönüşüm (View->Bid): %{funnel.get('view_to_bid_pct')} | (Bid->Sale): %{funnel.get('bid_to_sale_pct')}")
            
            print(f"\n  --- C. Akıllı Öneriler (Tips) ---")
            if tips:
                for t in tips:
                    print(f"    * {t.get('type')}: {t.get('message')}")
            else:
                print("    * Öneri yok.")
                
            print(f"\n  --- D. Sıcak Talepler (Hot Leads) ---")
            if hot_leads:
                for hl in hot_leads:
                    print(f"    * İlan ID {hl.get('listing_id')} ({hl.get('title')}): {hl.get('views_30d')} View, {hl.get('hesitations_30d')} Hes, Puan: {hl.get('heat_score')}")
            else:
                print("    * Veri yok.")

            print(f"\n  --- E. Fiyat Zekası (Price Intel) ---")
            if price_intel:
                for p in price_intel:
                    print(f"    * İlan ID {p.get('listing_id')} ({p.get('title')}): Kendi Fiyatı ₺{p.get('my_price')} | Pazar Ort. ₺{p.get('market_avg')} | Sinyal: {p.get('signal')}")
            else:
                print("    * Veri yok.")
                
            print(f"\n  --- F. Canlı Yayın Performansı (Stream Stats) ---")
            print(f"    * Yayın Sayısı: {stream_stats.get('total_streams')} | Toplam İzleyici: {stream_stats.get('total_viewers')}")
            print(f"    * Satılan Ürün: {stream_stats.get('items_sold')} | Kazanılan Hediye: {stream_stats.get('total_gifts_received')}")
            
            print(f"\n  --- G. Yoğun Saatler (Peak Hours) ---")
            if peak_hours:
                for ph in peak_hours:
                    print(f"    * Saat {ph.get('label')}: {ph.get('count')} Etkileşim")
            else:
                print("    * Veri yok.")
        else:
            print(f"  ❌ Hata: {r_insights.status_code} - {r_insights.text}")
            
        # 2. AI Metrics (Yeni ClickHouse Entegrasyonu)
        print("\n=======================================================")
        print("2. [GET] /api/analytics/pro/metrics (AI Metrikleri)")
        r_metrics = await client.get("/api/analytics/pro/metrics", headers=headers)
        if r_metrics.status_code == 200:
            metrics = r_metrics.json()
            print("  ✅ Başarılı!")
            print(f"  - En İyi Paylaşım Saati: {metrics.get('best_posting_hour')}")
            print(f"  - Ortalama Detay İnceleme Süresi (Dwell): {metrics.get('avg_detail_dwell_seconds')} saniye")
            print(f"  - Geri Dönen İzleyici Oranı: %{metrics.get('return_viewer_rate_pct')}")
            search_vis = metrics.get('search_visibility', [])
            print("  - Arama Görünürlüğü (Kategori Bazlı):")
            if search_vis:
                for sv in search_vis:
                    print(f"    * Kategori '{sv.get('category')}': {sv.get('search_count')} arama")
            else:
                print("    * Veri bulunamadı.")
        else:
            print(f"  ❌ Hata: {r_metrics.status_code} - {r_metrics.text}")
            
        # 3. Reklam Raporları
        print("\n=======================================================")
        print(f"3. REKLAM KAMPANYASI RAPORLARI ({len(campaigns)} Adet)")
        if not campaigns:
            print("  - Aktif/Kayıtlı kampanya bulunamadı.")
        for cmp in campaigns:
            print(f"\n  [GET] /api/ads/campaigns/{cmp.id}/report")
            r_ad = await client.get(f"/api/ads/campaigns/{cmp.id}/report", headers=headers)
            if r_ad.status_code == 200:
                ad_data = r_ad.json()
                print("    ✅ Başarılı!")
                print(f"    - Gösterim (Impressions): {ad_data.get('impressions')}")
                print(f"    - Tıklama (Clicks): {ad_data.get('clicks')}")
                print(f"    - Tıklama Oranı (CTR): %{ad_data.get('ctr')}")
                print(f"    - Kategori Ort. CTR: %{ad_data.get('category_avg_ctr')}")
                
                perf_score = ad_data.get('performance_score', {})
                print(f"    - Performans Skoru: {perf_score.get('score')}/100 ({perf_score.get('label')})")
                print(f"    - Maliyet (Harcanan Kredi): {ad_data.get('spent_credits')}")
            else:
                print(f"    ❌ Hata: {r_ad.status_code} - {r_ad.text}")

if __name__ == "__main__":
    asyncio.run(main())
