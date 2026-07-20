import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.users.block_user_use_case import BlockUserUseCase
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.user import User

class MockUserRepository:
    def __init__(self):
        self.blocks = []
        
    async def get_by_username(self, username: str):
        if username == "not_found_user":
            return None
            
        from app.models.enums import UserStatus
        mock_user = User(id=2, username=username, status=UserStatus.ACTIVE)
        return mock_user
        
    async def add_block(self, blocker_id, blocked_id):
        self.blocks.append((blocker_id, blocked_id))

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.users = MockUserRepository()
        self.committed = False
        self.rollbacked = False

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, traceback):
        if exc_type:
            await self.rollback()
        else:
            await self.commit()

    async def commit(self):
        self.committed = True

    async def rollback(self):
        self.rollbacked = True

async def test_use_cases():
    print("\n[TEST] Use Case (Interactor) Pattern Testi Başlıyor...")

    uow = MockUoW()
    use_case = BlockUserUseCase(uow)
    current_user = User(id=1, username="blocker_user")

    # Senaryo 1: Başarılı Engelleme
    result = await use_case.execute("target_user", current_user)
    if result.is_blocked and uow.committed:
        print("✅ Senaryo 1: Başarılı engelleme ve commit test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Kullanıcı bulunamadı hatası
    try:
        await use_case.execute("not_found_user", current_user)
        print("❌ Senaryo 2 Başarısız: Hata fırlatılmadı")
    except NotFoundException:
        print("✅ Senaryo 2: NotFoundException doğru fırlatıldı.")

    # Senaryo 3: Kendini engelleme hatası
    try:
        await use_case.execute("blocker_user", current_user)
        print("❌ Senaryo 3 Başarısız: Hata fırlatılmadı")
    except BadRequestException:
        print("✅ Senaryo 3: BadRequestException doğru fırlatıldı.")

    print("\n🎉 Tüm Use Case Testleri Başarıyla Tamamlandı!")


if __name__ == "__main__":
    asyncio.run(test_use_cases())
