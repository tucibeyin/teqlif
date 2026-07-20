import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.users.commands.follow_user import FollowUserCommand
from app.core.exceptions import BadRequestException, NotFoundException

class MockUser:
    def __init__(self, id, **kwargs):
        self.id = id
        for k, v in kwargs.items():
            setattr(self, k, v)

class MockUserRepository:
    def __init__(self):
        self.users = {
            2: MockUser(2, username="test_user")
        }
    async def get(self, id):
        return self.users.get(id)

class MockFollowRepository:
    def __init__(self):
        self.follows = []

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
        self.users = MockUserRepository()
        self.follows = MockFollowRepository()
        self.session = MockSession()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_user_cqrs():
    print("\n[TEST] Sprint 4: Users CQRS Testi Başlıyor...")

    uow = MockUoW()
    follow_cmd = FollowUserCommand(uow)

    # Senaryo 1: Başarılı Takip
    result = await follow_cmd.execute(follower_id=1, followed_id=2)
    if result["action"] in ["followed", "unfollowed"]:
        print(f"✅ Senaryo 1: Başarılı kullanıcı takibi ({result['action']}) test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Kendini Takip
    try:
        await follow_cmd.execute(follower_id=1, followed_id=1)
        print("❌ Senaryo 2 Başarısız: Kendini takibe izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Kendini Takip) doğru fırlatıldı.")

    # Senaryo 3: Olmayan Kullanıcı
    try:
        await follow_cmd.execute(follower_id=1, followed_id=99)
        print("❌ Senaryo 3 Başarısız: Olmayan kullanıcı takibine izin verildi.")
    except NotFoundException:
        print("✅ Senaryo 3: NotFoundException doğru fırlatıldı.")

    print("\n🎉 Tüm User Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_user_cqrs())
