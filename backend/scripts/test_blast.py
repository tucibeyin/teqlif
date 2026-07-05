import asyncio
import httpx
import sys
import getpass

# Ayarlar
BASE_URL = "http://127.0.0.1:8000"
EMAIL = "teqlif@gmail.com"
LISTING_TITLE = "Teqlif Deneme 2"

async def test_mass_notification():
    password = getpass.getpass(prompt=f"Lütfen {EMAIL} için şifrenizi girin: ")

    async with httpx.AsyncClient(base_url=BASE_URL) as client:
        print("\n1. Sisteme Giriş Yapılıyor...")
        login_resp = await client.post("/api/auth/login", json={"email": EMAIL, "password": password})
        if login_resp.status_code != 200:
            print("❌ Giriş Başarısız! Şifrenizi kontrol edin:", login_resp.text)
            return
        
        token = login_resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}
        print("✅ Giriş Başarılı, Token Alındı.\n")

        print("2. 'Teqlif Deneme 2' İlanı Bulunuyor...")
        listings_resp = await client.get("/api/listings/my", headers=headers)
        if listings_resp.status_code != 200:
            print("❌ İlanlar çekilemedi:", listings_resp.text)
            return
            
        listings = listings_resp.json()
        
        target_listing = next((l for l in listings if l["title"] == LISTING_TITLE), None)
        if not target_listing:
            print(f"❌ '{LISTING_TITLE}' adlı ilan bulunamadı.")
            return
        
        listing_id = target_listing["id"]
        print(f"✅ İlan Bulundu! ID: {listing_id}\n")

        print("3. Kitle Tahmini Alınıyor (/audience-estimate)...")
        est_resp = await client.get(f"/api/listings/{listing_id}/audience-estimate", headers=headers)
        if est_resp.status_code == 200:
            est_data = est_resp.json()
            print(f"📊 Son 30 Gündeki Aktif Kitleniz: {est_data.get('total_viewers_30d', 0)} kişi")
            print(f"🎯 Ulaşılabilir (Reachable): {est_data.get('reachable_audience', 0)} kişi\n")
        else:
            print("⚠️ Kitle tahmini alınamadı:", est_resp.text)

        print("4. Raporun Önceki Durumu Kontrol Ediliyor...")
        report_before = await client.get("/api/leads/mass-notification-report", headers=headers)
        if report_before.status_code == 200:
            print("📉 Mevcut Toplam Tıklama Sayısı:", report_before.json().get("total_clicks", 0), "\n")

        print("5. Toplu Kitle Bildirimi Gönderiliyor (Blast)...")
        blast_payload = {
            "title": LISTING_TITLE,
            "listing_id": listing_id,
            "category": target_listing.get("category"),
            "recipient_count": 1000, # Max limit
            "estimated_cost": 0      # Pydantic schema zorunlu kıldığı için
        }
        blast_resp = await client.post("/api/leads/send-blast", json=blast_payload, headers=headers)
        if blast_resp.status_code != 202:
            print("❌ Bildirim Gönderimi Başarısız:", blast_resp.text)
            return
        
        blast_data = blast_resp.json()
        campaign_id = blast_data.get("campaign_id")
        sent = blast_data.get("sent", 0)
        spent = blast_data.get("spent", 0)
        
        print(f"✅ Bildirim Başarıyla İşlendi!")
        print(f"📌 Kampanya ID: {campaign_id}")
        print(f"📲 Kesin Gönderilen Cihaz: {sent}")
        print(f"💰 Kesilen TUCi: {spent}\n")

        if not campaign_id:
            print("⚠️ Backend güncellenmemiş, campaign_id dönmüyor. Tıklama testi atlanacak.")
            return

        print("6. Tıklama Simüle Ediliyor (Push Notification Click)...")
        print("   (Mobil uygulamada bildirime tıklandığında bu tetiklenir)")
        click_resp = await client.post(f"/api/leads/campaign/{campaign_id}/click", headers=headers)
        if click_resp.status_code == 204:
            print("✅ Tıklama Başarıyla Veritabanına Yazıldı!\n")
        else:
            print("❌ Tıklama Kaydı Başarısız:", click_resp.text)

        print("7. Dönüşüm Hunisi Sonuçları Kontrol Ediliyor (/mass-notification-report)...")
        report_after = await client.get("/api/leads/mass-notification-report", headers=headers)
        if report_after.status_code == 200:
            r_data = report_after.json()
            print("🎉 GÜNCEL RAPOR SONUCU:")
            print(f"   Hedeflenen Kitle: {r_data.get('total_target')}")
            print(f"   İletilen Cihaz: {r_data.get('total_sent')}")
            print(f"   Toplam Tıklama (Açma): {r_data.get('total_clicks')}")
            if r_data.get('total_clicks', 0) > 0 and r_data.get('total_sent', 0) > 0:
                ctr = (r_data['total_clicks'] / r_data['total_sent']) * 100
                print(f"   Açılma Oranı (CTR): %{ctr:.2f}")
        else:
            print("❌ Rapor alınamadı:", report_after.text)

if __name__ == "__main__":
    asyncio.run(test_mass_notification())
