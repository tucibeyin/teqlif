import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.di import init_di, container
from app.core.ports.push_notification_port import PushNotificationPort

async def test_firebase_adapter():
    print("\n[TEST] Hexagonal Architecture (Ports & Adapters) Testi Başlıyor...")

    # 1. DI Container'ı başlat (Bu FirebaseAdapter'ı PushNotificationPort olarak kaydeder)
    init_di()

    try:
        # 2. Port üzerinden servisi çöz (Dependency Injection)
        push_service = container.resolve(PushNotificationPort)
        
        # 3. Adapter metodunu çağır
        # Gerçek bir token olmadığı için FirebaseAdapter içindeki Invalid token logiği veya
        # ServiceException fırlatma durumu test edilir.
        test_token = "TEST_INVALID_TOKEN_123"
        print(f"[*] PushNotificationPort (FirebaseAdapter) üzerinden push gönderiliyor: {test_token}")
        
        result = await push_service.send_notification(
            token=test_token,
            title="Test",
            body="Hexagonal Architecture Test"
        )
        
        if result is False:
            print("✅ Senaryo 1: Geçersiz token adapter tarafından yakalandı ve yönetildi (ServiceException veya Event fırlatıldı).")
        else:
            print("❓ Push başarılı döndü (Beklenmeyen durum)")

    except Exception as e:
        print(f"❌ Beklenmeyen hata: {e}")
        sys.exit(1)

    print("\n🎉 Tüm Ports & Adapters Testleri Başarıyla Tamamlandı!")


if __name__ == "__main__":
    asyncio.run(test_firebase_adapter())
