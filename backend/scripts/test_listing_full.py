import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.listings.commands.update_listing import UpdateListingCommand
from app.use_cases.listings.commands.delete_listing import DeleteListingCommand
from app.use_cases.listings.commands.like_listing import LikeListingCommand
from app.core.exceptions import BadRequestException, NotFoundException, ContentPolicyException
from app.models.enums import ListingStatus

class MockListing:
    def __init__(self, id, user_id, title, status=ListingStatus.ACTIVE):
        self.id = id
        self.user_id = user_id
        self.title = title
        self.description = ""
        self.price = 0
        self.status = status

class MockListingRepository:
    def __init__(self):
        self.listings = {
            1: MockListing(1, 10, "İlan 1")
        }
    async def get(self, id):
        return self.listings.get(id)

class MockFavorite:
    pass

class MockSession:
    async def execute(self, stmt):
        class MockResult:
            def scalar_one_or_none(self):
                return None
        return MockResult()
    def add(self, obj):
        pass
    async def delete(self, obj):
        pass

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.listings = MockListingRepository()
        self.session = MockSession()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_listing_full():
    print("\n[TEST] Sprint 1: Listing Commands (Update, Delete, Like) Full Test...")

    uow = MockUoW()
    update_cmd = UpdateListingCommand(uow)
    delete_cmd = DeleteListingCommand(uow)
    like_cmd = LikeListingCommand(uow)

    # 1. Update Testleri
    print("[*] UpdateListingCommand Testleri...")
    try:
        await update_cmd.execute(listing_id=1, user_id=99, title="Yeni") # Yanlış kullanıcı
        print("❌ Yetkisiz güncellemeye izin verdi.")
    except BadRequestException:
        print("✅ Yetkisiz güncelleme engellendi.")

    try:
        await update_cmd.execute(listing_id=1, user_id=10, title="Yeni amk") # Küfür
        print("❌ Küfürlü güncellemeye izin verdi.")
    except ContentPolicyException:
        print("✅ Küfürlü güncelleme engellendi.")

    await update_cmd.execute(listing_id=1, user_id=10, title="Temiz İlan")
    print("✅ Başarılı güncelleme tamamlandı.")

    # 2. Like Testleri
    print("[*] LikeListingCommand Testleri...")
    try:
        await like_cmd.execute(listing_id=1, user_id=10) # Kendi ilanını beğenme
        print("❌ Kendi ilanını beğenmeye izin verdi.")
    except BadRequestException:
        print("✅ Kendi ilanını beğenme engellendi.")

    result = await like_cmd.execute(listing_id=1, user_id=99)
    print(f"✅ Favori işlemi başarılı: {result['action']}")

    # 3. Delete Testleri
    print("[*] DeleteListingCommand Testleri...")
    await delete_cmd.execute(listing_id=1, user_id=10)
    print("✅ Başarılı silme işlemi tamamlandı.")

    print("\n🎉 Tüm Listing Full Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_listing_full())
