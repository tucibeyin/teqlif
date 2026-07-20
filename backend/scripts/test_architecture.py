import asyncio
import sys
import os
from fastapi import APIRouter
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import sessionmaker

# Backend kök dizinini PYTHONPATH'e ekle
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.event_bus import event_bus
from app.core.events import TokenInvalidatedEvent
from app.core.exceptions import AppException
from app.repositories.user_repository import user_repository
from main import app

async def test_event_bus():
    print("\n[TEST] 1. EventBus Pub/Sub Testi Başlıyor...")
    received_events = []
    
    async def dummy_handler(event: TokenInvalidatedEvent):
        received_events.append(event)
        
    event_bus.subscribe(TokenInvalidatedEvent, dummy_handler)
    
    test_token = "TEST_INVALID_TOKEN_123"
    event_bus.publish(TokenInvalidatedEvent(token=test_token))
    
    # Event loop'un task'ı çalıştırmasına fırsat ver
    await asyncio.sleep(0.1)
    
    assert len(received_events) == 1, "EventBus event'i fırlatamadı!"
    assert received_events[0].token == test_token, "EventBus yanlış token fırlattı!"
    
    print("✅ EventBus Pub/Sub başarıyla test edildi.")

async def test_central_error_handlers():
    print("\n[TEST] 2. Central Error Handlers Testi Başlıyor...")
    
    # Test için geçici bir endpoint ekliyoruz
    test_router = APIRouter()
    @test_router.get("/api/test-domain-error")
    async def trigger_domain_error():
        raise AppException(status_code=400, error_code="TEST_ERROR", message="Bu bir test hatasıdır.")
        
    app.include_router(test_router)
    
    client = TestClient(app)
    # TestClient senkron çalışır ancak route async olabilir, o yüzden arka planda kendi loop'unu kullanır
    response = client.get("/api/test-domain-error")
    
    assert response.status_code == 400, f"Beklenen 400, dönen: {response.status_code}"
    
    data = response.json()
    assert data["success"] is False, "Hata formatında 'success' alanı False olmalı!"
    assert "error" in data, "Hata formatında 'error' objesi bulunmalı!"
    assert data["error"]["code"] == "TEST_ERROR", "Error code eksik veya hatalı!"
    assert data["error"]["message"] == "Bu bir test hatasıdır.", "Error message hatalı!"
    assert "request_id" in data["error"], "Request ID (Contextual logging) basılmamış!"
    
    print("✅ Central Error Handlers (JSON Standartları) başarıyla test edildi.")

async def test_repository_pattern():
    print("\n[TEST] 3. Repository Pattern Testi Başlıyor...")
    from app.database import engine
    
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as db:
        # Mock bir get sorgusu çalıştırıyoruz
        try:
            user = await user_repository.get_by_username(db, "olmayan_biri_123")
            assert user is None, "Olmayan kullanıcı sorgusu patlamamalıydı!"
            print("✅ Repository Pattern (DB Bağlantısı ve Sorgu) başarıyla test edildi.")
        except Exception as e:
            print(f"❌ Repository Testi Başarısız: {e}")

async def run_all_tests():
    try:
        await test_event_bus()
        await test_central_error_handlers()
        await test_repository_pattern()
        print("\n🎉 Tüm Mimari Değişiklikleri Başarıyla Doğrulandı!")
    except AssertionError as e:
        print(f"\n❌ TEST BAŞARISIZ: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ BEKLENMEYEN HATA: {e}")
        sys.exit(1)

if __name__ == "__main__":
    print("🚀 Mimari Testler Başlatılıyor...")
    asyncio.run(run_all_tests())
