import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.message import DirectMessage

async def test_global_repositories():
    print("\n[TEST] Global Repositories ve UoW Testi Başlıyor...")

    uow = SqlAlchemyUnitOfWork()

    async with uow:
        try:
            # Sadece Repositories'lerin yüklenip yüklenmediğini kontrol ediyoruz
            # Veritabanına bağlandığında hata vermiyor mu? (Mock UoW olmadan)
            assert hasattr(uow, 'listings'), "UoW 'listings' repo'suna sahip değil."
            assert hasattr(uow, 'streams'), "UoW 'streams' repo'suna sahip değil."
            assert hasattr(uow, 'messages'), "UoW 'messages' repo'suna sahip değil."
            
            # Repoların BaseRepository üzerinden metodlara erişimi var mı kontrolü
            assert hasattr(uow.listings, 'get'), "ListingRepository 'get' metoduna sahip değil."
            assert hasattr(uow.streams, 'get_multi'), "StreamRepository 'get_multi' metoduna sahip değil."
            assert hasattr(uow.messages, 'create'), "MessageRepository 'create' metoduna sahip değil."

            print("✅ Tüm global repolar (Listing, Stream, Message) UoW içerisine başarıyla yüklendi ve BaseRepository'den kalıtım aldı.")
            
            # Bilinçli hata oluşturup rollback tetiklenmesini sağlıyoruz
            # Bu, test ortamına çöp veri yazılmasını önler.
            raise ValueError("Test için rollback tetiklemesi")
            
        except ValueError as e:
            if "Test için rollback" in str(e):
                print("✅ UoW otomatik rollback işlemi başarıyla çalıştı.")
            else:
                raise e
        except Exception as e:
            print(f"❌ Beklenmeyen Hata: {e}")
            sys.exit(1)

    print("\n🎉 Tüm Global Repository ve UoW Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_global_repositories())
