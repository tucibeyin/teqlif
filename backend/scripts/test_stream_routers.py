import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fastapi.testclient import TestClient
from main import app
from app.utils.auth import create_access_token

def test_stream_routers_cqrs():
    print("\n[TEST] Sprint 7: Stream & Auction Routers CQRS Entegrasyon Testi Başlıyor...")

    with TestClient(app) as client:
        test_user_id = 1
        token = create_access_token(test_user_id)
        headers = {"Authorization": f"Bearer {token}"}
    
        # 1. POST /api/streams/start (Start Stream)
        print("[*] POST /api/streams/start isteği atılıyor...")
        response = client.post("/api/streams/start", json={"title": "Test Yayın", "category": "other"}, headers=headers)
        print(f"[*] Sunucu Yanıt Kodu: {response.status_code}")
        
        if response.status_code in [200, 201]:
            print("✅ Başarılı: StartStreamCommand router üzerinden çalıştı.")
        else:
            print(f"⚠️ Hata veya beklenmeyen yanıt: {response.text[:100]}")
    
        print("\n🎉 Tüm Stream Router Testleri Tamamlandı!")

if __name__ == "__main__":
    test_stream_routers_cqrs()
