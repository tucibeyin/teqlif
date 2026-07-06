import asyncio
import sys
import os

# Add backend directory to sys.path to resolve 'app' module
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import AsyncSessionLocal
from app.models.listing import Listing
from app.services.ner_service import extract_ner

async def backfill_listings():
    print("Listing verilerinde brand, model_name ve condition alanları taranıyor...")
    
    async with AsyncSessionLocal() as session:
        # brand VEYA model_name boş olan kayıtları getir
        # (Eskiden girilmiş olup NER'dan geçmemiş olanlar)
        stmt = select(Listing).where(
            (Listing.brand == None) | (Listing.model_name == None)
        )
        result = await session.execute(stmt)
        listings = result.scalars().all()
        
        if not listings:
            print("Güncellenecek eksik ilan bulunamadı.")
            return

        print(f"Toplam {len(listings)} adet eksik kayıt bulundu. İşlem başlatılıyor...")
        
        updated_count = 0
        for listing in listings:
            # NER Servisi ile analiz et
            extracted = extract_ner(
                title=listing.title or "",
                description=listing.description or "",
                category=listing.category or ""
            )
            
            needs_update = False
            
            if extracted.get("brand") and not listing.brand:
                listing.brand = extracted["brand"]
                needs_update = True
                
            if extracted.get("model_name") and not listing.model_name:
                listing.model_name = extracted["model_name"]
                needs_update = True
                
            if extracted.get("condition") and not listing.condition:
                listing.condition = extracted["condition"]
                needs_update = True
                
            if needs_update:
                updated_count += 1

        print(f"{updated_count} adet ilana başarıyla NER etiketlemesi yapıldı. Veritabanına kaydediliyor...")
        await session.commit()
        print("İşlem başarıyla tamamlandı.")

if __name__ == "__main__":
    asyncio.run(backfill_listings())
