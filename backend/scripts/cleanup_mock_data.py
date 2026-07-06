import asyncio
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import delete, select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.like import ListingLike

async def cleanup():
    print("🧹 Mock Veriler Temizleniyor...")
    
    async with AsyncSessionLocal() as session:
        # Mock kullanıcıları tespit et (@example.com olanlar)
        stmt = select(User.id).where(User.email.like("%@example.com%"))
        result = await session.execute(stmt)
        user_ids = [row[0] for row in result]
        
        if not user_ids:
            print("Silinecek mock kullanıcı bulunamadı.")
            return

        print(f"🗑️ {len(user_ids)} adet mock kullanıcıya ait bağımlı veriler siliniyor...")
        
        # SQLAlchemy'de ForeignKey kısıtlamalarına takılmamak için sırayla siliyoruz
        await session.execute(delete(ListingLike).where(ListingLike.user_id.in_(user_ids)))
        await session.execute(delete(LiveStream).where(LiveStream.seller_id.in_(user_ids)))
        await session.execute(delete(Listing).where(Listing.user_id.in_(user_ids)))
        await session.execute(delete(User).where(User.id.in_(user_ids)))
        
        await session.commit()
        print("✅ Başarılı! Tüm mock veriler (ilanlar, yayınlar, beğeniler ve kullanıcılar) veritabanından tamamen silindi.")

if __name__ == "__main__":
    asyncio.run(cleanup())
