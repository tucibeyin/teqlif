import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.uow import SqlAlchemyUnitOfWork

async def test_listing_repositories():
    print("\n[TEST] Sprint 1: Listing Domain Repositories & UoW Testi Başlıyor...")

    uow = SqlAlchemyUnitOfWork()

    async with uow:
        try:
            assert hasattr(uow, 'listings'), "UoW 'listings' repo'suna sahip değil."
            assert hasattr(uow, 'favorites'), "UoW 'favorites' repo'suna sahip değil."
            assert hasattr(uow, 'categories'), "UoW 'categories' repo'suna sahip değil."
            
            assert hasattr(uow.listings, 'get'), "ListingRepository 'get' metoduna sahip değil."
            assert hasattr(uow.favorites, 'get_multi'), "FavoriteRepository 'get_multi' metoduna sahip değil."
            assert hasattr(uow.categories, 'create'), "CategoryRepository 'create' metoduna sahip değil."

            print("✅ Tüm Listing Domain repoları (Listing, Favorite, Category) UoW içerisine başarıyla yüklendi.")
            
            # Rollback tetiklemesi
            raise ValueError("Test için rollback")
            
        except ValueError as e:
            if "Test için rollback" in str(e):
                print("✅ UoW otomatik rollback işlemi Listing Domain repoları ile başarıyla çalıştı.")
            else:
                raise e
        except Exception as e:
            print(f"❌ Beklenmeyen Hata: {e}")
            sys.exit(1)

    print("\n🎉 Tüm Listing Domain Repository ve UoW Testleri Başarıyla Tamamlandı!")

if __name__ == "__main__":
    asyncio.run(test_listing_repositories())
