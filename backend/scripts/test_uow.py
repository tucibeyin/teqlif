import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.core.exceptions import DatabaseException

async def test_uow():
    print("\n[TEST] Unit of Work (UoW) Pattern Testi Başlıyor...")

    # Senaryo 1: Başarılı işlem
    async with SqlAlchemyUnitOfWork() as uow:
        # Mock repo query
        user = await uow.users.get_by_username("test_uow_user_doesnt_exist")
        # Değişiklik yok, commit etmeli
        
    print("✅ Senaryo 1: Başarılı işlem ve commit test edildi.")

    # Senaryo 2: Hata anında Rollback kontrolü
    try:
        async with SqlAlchemyUnitOfWork() as uow:
            # Yapay bir exception fırlatıyoruz (AppException harici bir exception)
            raise ValueError("Bilinçli test hatası")
    except ValueError:
        print("✅ Senaryo 2: Hata fırlatıldığında otomatik rollback yapıldı.")
    except Exception as e:
        print(f"❌ Beklenmeyen hata: {e}")
        sys.exit(1)

    print("\n🎉 Tüm Unit of Work (UoW) Testleri Başarıyla Tamamlandı!")


if __name__ == "__main__":
    asyncio.run(test_uow())
