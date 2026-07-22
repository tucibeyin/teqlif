import sys
import os
import asyncio
import random

# Backend dizinini yola ekle ki app modüllerini import edebilelim
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.services.ml.llm_service import generate_listing_description_stream

CATEGORIES = ["elektronik", "giyim", "vasıta", "emlak", "mobilya", "hobi"]
CONDITIONS = ["new", "like_new", "used", "damaged"]
LOCATIONS = ["İstanbul", "Ankara", "İzmir", "Bursa", "Antalya", None]

async def main():
    print("==================================================")
    print(" LLM İLAN AÇIKLAMASI TEST ARACI")
    print(" (Çıkmak için 'q' veya 'quit' yazın)")
    print("==================================================\n")

    while True:
        try:
            title = input("\nİlan Başlığı Girin (Örn: 'Iphone 14 Pro'): ").strip()
            if not title:
                continue
            if title.lower() in ['q', 'quit', 'exit']:
                print("Çıkış yapılıyor...")
                break

            # Rastgele değerler seç
            category = random.choice(CATEGORIES)
            condition = random.choice(CONDITIONS)
            location = random.choice(LOCATIONS)
            
            # Fiyatı %20 ihtimalle boş (None) bırak, %80 ihtimalle rastgele üret
            price = None if random.random() < 0.2 else float(random.randint(500, 50000))

            print("\n--- TEST PARAMETRELERİ ---")
            print(f"Başlık  : {title}")
            print(f"Kategori: {category}")
            print(f"Durum   : {condition}")
            print(f"Lokasyon: {location if location else 'Kargo/Elden'}")
            print(f"Fiyat   : {price if price else 'Belirtilmedi'} TL")
            print("--------------------------\n")
            
            print("LLM Üretiyor...\n\n> ", end="")
            
            # Stream'i çek
            async for chunk in generate_listing_description_stream(
                title=title,
                category=category,
                condition=condition,
                price=price,
                location=location
            ):
                print(chunk, end="", flush=True)
            
            print("\n\n" + "="*50)
            
        except KeyboardInterrupt:
            print("\nÇıkış yapılıyor...")
            break
        except Exception as e:
            print(f"\n[Hata]: {e}")

if __name__ == "__main__":
    # Windows/Mac asenkron IO hatalarını engellemek için
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
