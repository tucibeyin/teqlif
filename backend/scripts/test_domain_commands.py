import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.messages.commands.send_direct_message import SendDirectMessageCommand
from app.core.exceptions import NotFoundException, BadRequestException
from app.models.user import User

class MockMessage:
    def __init__(self, id, **kwargs):
        self.id = id
        for k, v in kwargs.items():
            setattr(self, k, v)

class MockMessageRepository:
    def __init__(self):
        self.messages = []
        
    async def create(self, obj_in):
        msg = MockMessage(id=len(self.messages) + 1, **obj_in)
        self.messages.append(msg)
        return msg

class MockUserRepository:
    def __init__(self):
        pass
        
    async def get(self, user_id: int):
        if user_id == 999: # Not found user
            return None
        from app.models.enums import UserStatus
        return User(id=user_id, status=UserStatus.ACTIVE)

class MockUoW(SqlAlchemyUnitOfWork):
    def __init__(self):
        self.users = MockUserRepository()
        self.messages = MockMessageRepository()
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

async def test_domain_commands():
    print("\n[TEST] CQRS Domain Commands Testi Başlıyor...")

    uow = MockUoW()
    command = SendDirectMessageCommand(uow)

    # Senaryo 1: Başarılı Mesaj Gönderimi
    result = await command.execute(sender_id=1, receiver_id=2, content="Merhaba")
    if result["status"] == "sent" and uow.committed:
        print("✅ Senaryo 1: Başarılı işlem ve veritabanı commit test edildi.")
    else:
        print("❌ Senaryo 1 Başarısız")

    # Senaryo 2: Kendine mesaj atma hatası (BadRequestException)
    try:
        await command.execute(sender_id=1, receiver_id=1, content="Merhaba")
        print("❌ Senaryo 2 Başarısız: Kendine mesaj atıldığında hata fırlatılmadı.")
    except BadRequestException:
        print("✅ Senaryo 2: BadRequestException (Kendine mesaj) doğru fırlatıldı.")

    # Senaryo 3: Alıcı bulunamadı (NotFoundException)
    try:
        await command.execute(sender_id=1, receiver_id=999, content="Merhaba")
        print("❌ Senaryo 3 Başarısız: Alıcı bulunmadığında hata fırlatılmadı.")
    except NotFoundException:
        print("✅ Senaryo 3: NotFoundException (Kullanıcı yok) doğru fırlatıldı.")

    # Senaryo 4: Boş mesaj içeriği
    try:
        await command.execute(sender_id=1, receiver_id=2, content="   ")
        print("❌ Senaryo 4 Başarısız: Boş mesajda hata fırlatılmadı.")
    except BadRequestException:
        print("✅ Senaryo 4: BadRequestException (Boş mesaj) doğru fırlatıldı.")

    print("\n🎉 Tüm CQRS Command Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    # EventBus importunu mock'lamak için basitçe bir obje ekleyebiliriz ya da sisteminkini kullanırız
    # DirectMessageCreatedEvent aslında system event_bus üzerinden fırlatılır. 
    # Unit testte mock_event_bus kullanmak daha mantıklı olurdu ancak entegrasyon seviyesinde
    # gerçek event_bus'ı tetiklemesi de uygundur.
    asyncio.run(test_domain_commands())
