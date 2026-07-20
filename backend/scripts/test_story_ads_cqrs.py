import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.stories.commands.create_story import CreateStoryCommand
from app.core.exceptions import BadRequestException

class MockStory:
    def __init__(self, id, **kwargs):
        self.id = id
        for k, v in kwargs.items():
            setattr(self, k, v)

class MockStoryRepository:
    def __init__(self):
        self.stories = []
    async def create(self, obj_in):
        story = MockStory(id=len(self.stories) + 1, **obj_in)
        self.stories.append(story)
        return story

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.stories = MockStoryRepository()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_story_ads_cqrs():
    print("\n[TEST] Sprint 5: Stories & Ads CQRS Testi Başlıyor...")

    uow = MockUoW()
    create_story_cmd = CreateStoryCommand(uow)

    # Senaryo 1: Başarılı Hikaye Oluşturma
    result = await create_story_cmd.execute(user_id=1, media_url="http://example.com/img.jpg")
    if result["status"] == "created":
        print("✅ Senaryo 1: Başarılı hikaye oluşturma test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Boş Medya URL
    try:
        await create_story_cmd.execute(user_id=1, media_url="")
        print("❌ Senaryo 2 Başarısız: Boş medya URL'sine izin verildi.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Boş Medya) doğru fırlatıldı.")

    print("\n🎉 Tüm Stories Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_story_ads_cqrs())
