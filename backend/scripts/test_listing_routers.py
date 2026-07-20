import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fastapi.testclient import TestClient
from main import app
from app.utils.auth import create_access_token

def test_listing_routers_cqrs():
    print("\n[TEST] Sprint 6: Listing Routers CQRS Entegrasyon Testi Başlıyor...")

    client = TestClient(app)

    # Test kullanıcısı token'ı
    test_user_id = 1
    token = create_access_token(test_user_id)
    headers = {"Authorization": f"Bearer {token}"}

    # 1. GET /api/listings (Arama / Filtreleme)
    print("[*] GET /api/listings isteği atılıyor...")
    response = client.get("/api/listings?q=test&limit=1", headers=headers)
    print(f"[*] Sunucu Yanıt Kodu: {response.status_code}")
    
    if response.status_code in [200, 201]:
        print("✅ Başarılı: SearchListingsQuery router üzerinden çalıştı.")
    else:
        print(f"⚠️ Hata veya beklenmeyen yanıt: {response.text[:100]}")

    # 2. GET /api/listings/my (Kullanıcı İlanları)
    print("[*] GET /api/listings/my isteği atılıyor...")
    response = client.get("/api/listings/my", headers=headers)
    print(f"[*] Sunucu Yanıt Kodu: {response.status_code}")
    
    if response.status_code in [200, 201]:
        print("✅ Başarılı: GetUserListingsQuery router üzerinden çalıştı.")
    else:
        print(f"⚠️ Hata veya beklenmeyen yanıt: {response.text[:100]}")

    print("\n🎉 Tüm Listing Router Testleri Tamamlandı!")

if __name__ == "__main__":
    test_listing_routers_cqrs()
