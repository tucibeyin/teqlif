import asyncio
import os
import sys
from dotenv import load_dotenv

# Backend dizinini yola ekle ki 'app' modülünü bulabilsin
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)

# .env dosyasını backend dizininden yükle
load_dotenv(os.path.join(backend_dir, ".env"))

from app.database import get_db
from sqlalchemy import text

async def backfill():
    print("Geçmiş ilanların last_sold_price verileri dolduruluyor (Backfill)...")
    async for db in get_db():
        # Her ilan için geçmişte yapılmış en yüksek (veya en son) başarılı açık artırmayı bul
        # ve o açık artırmanın start_price / final_price değerlerini listing tablosuna kopyala.
        query = text("""
            WITH RankedAuctions AS (
                SELECT 
                    listing_id, 
                    start_price, 
                    final_price,
                    ROW_NUMBER() OVER(PARTITION BY listing_id ORDER BY final_price DESC) as rn
                FROM auctions
                WHERE winner_username IS NOT NULL 
                  AND final_price > 0
            )
            UPDATE listings l
            SET 
                last_start_price = ra.start_price,
                last_sold_price = ra.final_price
            FROM RankedAuctions ra
            WHERE l.id = ra.listing_id
              AND ra.rn = 1
              AND l.last_sold_price IS NULL;
        """)
        
        result = await db.execute(query)
        await db.commit()
        
        print(f"İşlem tamamlandı! Güncellenen ilan sayısı: {result.rowcount}")
        print("Artık Yapay Zeka eski ilanları referans alarak fiyat önerisi yapabilecek.")
        break

if __name__ == "__main__":
    asyncio.run(backfill())
