import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.listings.commands.create_listing import CreateListingCommand
from app.use_cases.listings.projectors.listing_projector import register_listing_projectors, READ_MODEL_LISTINGS_FEED

class MockListing:
    def __init__(self, id, **kwargs):
        self.id = id

class MockListingRepository:
    def __init__(self):
        self.listings = []
    async def create(self, obj_in):
        listing = MockListing(id=len(self.listings) + 1, **obj_in)
        self.listings.append(listing)
        return listing

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.listings = MockListingRepository()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_listing_projectors():
    print("\n[TEST] Sprint 1 Faz 3: Listing Projector ve Read Model Testi Başlıyor...")

    # 1. Sistemin başlangıcında EventBus'a Listing Projector'ları kaydet
    register_listing_projectors()

    uow = MockUoW()
    command = CreateListingCommand(uow)

    # Öncesinde feed boş olmalı
    print(f"[*] Command çalışmadan önceki Feed Read Model boyutu: {len(READ_MODEL_LISTINGS_FEED)}")

    # 2. Command çalışır, DB'ye yazar (Mock) ve arka planda EventBus'a ListingCreatedEvent gönderir
    print("[*] Yeni bir ilan oluşturuluyor (Write Model Update)...")
    await command.execute(
        user_id=1, 
        title="Temiz iPhone 13", 
        description="Açıklama", 
        price=35000, 
        category="elektronik"
    )

    # EventBus arka planda çalıştığı için çok kısa bir an bekleyelim (RabbitMQ vs. taklidi)
    await asyncio.sleep(0.1)

    # 3. Read Model'i kontrol edelim
    feed_count = len(READ_MODEL_LISTINGS_FEED)
    if feed_count == 1 and READ_MODEL_LISTINGS_FEED[0]["title"] == "Temiz iPhone 13":
        print("✅ Faz 3 Başarılı: CreateListingCommand -> EventBus -> ListingProjector -> Feed ReadModel senkronizasyonu mükemmel çalıştı!")
        print("✅ Feed ekranı artık ilanları doğrudan Redis'ten (veya ClickHouse'tan) O(1) hızında okuyabilecek.")
    else:
        print(f"❌ Faz 3 Başarısız: Read model senkronize olamadı. Count: {feed_count}")
        sys.exit(1)

    print("\n🎉 Tüm Faz 3 Listing Projector Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_listing_projectors())
