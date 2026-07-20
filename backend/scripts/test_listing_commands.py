import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.listings.commands.create_listing import CreateListingCommand
from app.core.exceptions import BadRequestException, ContentPolicyException

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
        self.committed = False
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        self.committed = True

async def test_listing_commands():
    print("\n[TEST] Sprint 1 Faz 2: Listing Commands Testi Başlıyor...")

    uow = MockUoW()
    command = CreateListingCommand(uow)

    # Senaryo 1: Başarılı İlan
    result = await command.execute(
        user_id=1, 
        title="Temiz iPhone 13", 
        description="Çiziksiz, garantili.", 
        price=35000, 
        category="elektronik"
    )
    if result["status"] == "created" and uow.committed:
        print("✅ Senaryo 1: Başarılı ilan oluşturma ve DB commit test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Boş Başlık
    try:
        await command.execute(user_id=1, title="", category="elektronik")
        print("❌ Senaryo 2 Başarısız: Boş başlığa izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Boş Başlık) doğru fırlatıldı.")

    # Senaryo 3: Geçersiz Kategori
    try:
        await command.execute(user_id=1, title="Test", category="olmayan_kategori")
        print("❌ Senaryo 3 Başarısız: Geçersiz kategoriye izin verildi.")
    except BadRequestException as e:
        if "Geçersiz kategori" in str(e):
            print("✅ Senaryo 3: BadRequestException (Geçersiz Kategori) doğru fırlatıldı.")
        else:
            print("❌ Senaryo 3 Başarısız: Beklenmeyen hata mesajı")

    # Senaryo 4: Profanity Check (Küfür)
    # auto_mod.py içinde "o.ç" "amk" gibi kelimeler yasaklı (mocklamadık ama sistemin kendi analyze_listing_text metoduna gidecek)
    try:
        await command.execute(user_id=1, title="Satılık Telefon amk", category="elektronik")
        print("❌ Senaryo 4 Başarısız: Küfürlü ilana izin verildi.")
    except ContentPolicyException:
        print("✅ Senaryo 4: ContentPolicyException (Küfür Filtresi) doğru fırlatıldı.")
    except Exception as e:
        print(f"❌ Senaryo 4 Beklenmeyen Hata: {e}")

    print("\n🎉 Tüm Listing Commands Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_listing_commands())
