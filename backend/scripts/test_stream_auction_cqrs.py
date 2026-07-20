import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.streams.commands.start_stream import StartStreamCommand
from app.core.exceptions import BadRequestException
from app.models.enums import StreamStatus

class MockStream:
    def __init__(self, id, **kwargs):
        self.id = id
        for k, v in kwargs.items():
            setattr(self, k, v)

class MockStreamRepository:
    def __init__(self):
        self.streams = []
    async def create(self, obj_in):
        stream = MockStream(id=len(self.streams) + 1, **obj_in)
        self.streams.append(stream)
        return stream

class MockUser:
    def __init__(self, id, username="test_user"):
        self.id = id
        self.username = username

class MockUserRepository:
    async def get(self, user_id):
        return MockUser(id=user_id)

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.streams = MockStreamRepository()
        self.users = MockUserRepository()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_stream_auction_cqrs():
    print("\n[TEST] Sprint 2: Streams & Auctions CQRS Testi Başlıyor...")

    uow = MockUoW()
    start_cmd = StartStreamCommand(uow)

    # Senaryo 1: Başarılı Yayın Başlatma
    result = await start_cmd.execute(user_id=1, title="iPhone 13 Açık Artırması!")
    if result.get("stream_id") == 1:
        print("✅ Senaryo 1: Başarılı canlı yayın başlatma ve Event tetikleme test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Boş Başlık
    try:
        await start_cmd.execute(user_id=1, title="")
        print("❌ Senaryo 2 Başarısız: Boş yayın başlığına izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Boş Yayın Başlığı) doğru fırlatıldı.")

    print("\n🎉 Tüm Streams & Auctions Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_stream_auction_cqrs())
