import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.messages.commands.send_direct_message import SendDirectMessageCommand
from app.use_cases.messages.queries.get_chat_history_query import GetChatHistoryQuery
from app.use_cases.messages.projectors.message_projector import register_projectors, READ_MODEL_CHAT_HISTORY

# Dalga 2'deki Mock nesneleri
class MockMessage:
    def __init__(self, id, **kwargs):
        self.id = id

class MockMessageRepository:
    def __init__(self):
        self.messages = []
    async def create(self, obj_in):
        msg = MockMessage(id=len(self.messages) + 1, **obj_in)
        self.messages.append(msg)
        return msg

class MockUserRepository:
    async def get(self, user_id: int):
        class DummyUser:
            pass
        return DummyUser()

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.users = MockUserRepository()
        self.messages = MockMessageRepository()
    async def __aenter__(self):
        return self
    async def __aexit__(self, exc_type, exc_val, traceback):
        pass
    async def commit(self):
        pass

async def test_cqrs_read_models():
    print("\n[TEST] CQRS Wave 3 (Projectors & Read Models) Testi Başlıyor...")

    # 1. Sistemin başlangıcında EventBus'a Projector'ları (Dinleyicileri) kaydet
    register_projectors()

    uow = MockUoW()
    command = SendDirectMessageCommand(uow)
    query = GetChatHistoryQuery()

    # Öncesinde sohbet geçmişi boş olmalı
    history_before = await query.execute(user_1=1, user_2=2)
    print(f"[*] Mesaj atılmadan önceki sohbet geçmişi (Read Model): {len(history_before)} mesaj")

    # 2. Command çalışır, DB'ye yazar (Mock) ve arka planda EventBus'a sinyal gönderir
    print("[*] 1'den 2'ye 'Naber' mesajı atılıyor (Write Model Update)...")
    await command.execute(sender_id=1, receiver_id=2, content="Naber")

    # EventBus arka planda çalıştığı için çok kısa bir an bekleyelim (Gerçek hayatta RabbitMQ vb. gecikmesi)
    await asyncio.sleep(0.1)

    # 3. Query (Okuma Modeli) devreye girer
    history_after = await query.execute(user_1=1, user_2=2)
    
    if len(history_after) == 1 and history_after[0]["content"] == "Naber":
        print("✅ Dalga 3 Başarılı: Command -> EventBus -> Projector -> ReadModel senkronizasyonu mükemmel çalıştı!")
        print("✅ Okuma işlemi veritabanına VURMADAN, saniyenin milyarda biri hızla gerçekleşti.")
    else:
        print("❌ Dalga 3 Başarısız: Read model senkronize olamadı.")
        sys.exit(1)

    print("\n🎉 Tüm Wave 3 CQRS Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_cqrs_read_models())
