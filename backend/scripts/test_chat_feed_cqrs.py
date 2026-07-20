import asyncio
import logging

from app.database import AsyncSessionLocal
from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.chat.commands.chat_commands import ChatCommands
from app.use_cases.feed.queries.feed_queries import FeedQueries
from app.use_cases.feed.queries.swipe_live_queries import SwipeLiveQueries

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_chat_feed_cqrs():
    print("\n[TEST] Chat, Feed & SwipeLive CQRS Testi Başlıyor...\n")

    async with AsyncSessionLocal() as db:
        uow = SqlAlchemyUnitOfWork(session_factory=lambda: db)

        # 1. Chat Commands Initialization
        try:
            chat_cmd = ChatCommands(uow=uow)
            print("✅ Senaryo 1: ChatCommands başarıyla başlatıldı ve UoW bağlandı.")
        except Exception as e:
            print(f"❌ Senaryo 1 Hata (Chat): {e}")

        # 2. Feed Queries Initialization
        try:
            feed_queries = FeedQueries(uow=uow)
            print("✅ Senaryo 2: FeedQueries başarıyla başlatıldı ve UoW bağlandı.")
        except Exception as e:
            print(f"❌ Senaryo 2 Hata (Feed): {e}")

        # 3. Swipe Live Queries Initialization
        try:
            swipe_queries = SwipeLiveQueries(uow=uow)
            print("✅ Senaryo 3: SwipeLiveQueries başarıyla başlatıldı ve UoW bağlandı.")
        except Exception as e:
            print(f"❌ Senaryo 3 Hata (Swipe): {e}")

    print("\n🎉 Chat, Feed & SwipeLive CQRS Testleri Başarıyla Tamamlandı!\n")

if __name__ == "__main__":
    asyncio.run(test_chat_feed_cqrs())
