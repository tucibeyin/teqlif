import asyncio
import httpx
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.main import app
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
        
        # 1. Pro Insights (Funnel, KPIs, Hot Leads vb.)
        print("1. [GET] /api/analytics/pro-insights")
        r_insights = await client.get("/api/analytics/pro-insights", headers=headers)
        if r_insights.status_code == 200:
            data = r_insights.json()
            funnel = data.get("funnel", {})
            kpis = data.get("kpis", {})
            hot_leads = data.get("hot_leads", [])
            print("  ✅ Başarılı!")
            print(f"  - Funnel Görüntülenme (Views): {funnel.get('views')} | Tereddüt (Hesitations): {funnel.get('hesitations')}")
            print(f"  - KPIs: Aktif İlanlar: {kpis.get('active_listings')} | Toplam Satış: {kpis.get('total_sales')}")
            print(f"  - Hot Leads (Sıcak Talep) Sayısı: {len(hot_leads)}")
        else:
            print(f"  ❌ Hata: {r_insights.status_code} - {r_insights.text}")
            
        # 2. AI Metrics (Yeni ClickHouse Entegrasyonu)
        print("\n2. [GET] /api/analytics/pro/metrics")
        r_metrics = await client.get("/api/analytics/pro/metrics", headers=headers)
        if r_metrics.status_code == 200:
            metrics = r_metrics.json()
            print("  ✅ Başarılı!")
            print(f"  - En İyi Paylaşım Saati (Best Posting Hour): {metrics.get('best_posting_hour')}")
            print(f"  - Ortalama Detay İnceleme Süresi (Dwell): {metrics.get('avg_detail_dwell_seconds')} saniye")
            print(f"  - Geri Dönen İzleyici Oranı (Sadakat): %{metrics.get('return_viewer_rate_pct')}")
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
        print(f"\n3. REKLAM KAMPANYASI RAPORLARI ({len(campaigns)} Adet)")
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
            else:
                print(f"    ❌ Hata: {r_ad.status_code} - {r_ad.text}")

if __name__ == "__main__":
    asyncio.run(main())
