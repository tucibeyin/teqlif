"""
Feed ALS ve Tavsiye Motoru Manuel Tetikleme ile Önbellek Yönetim Scripti (trigger_feed_ml.py)

Bu script, ARQ Worker'ın gece 03:45'te çalışmasını beklemeden ClickHouse'taki mevcut
etkileşim verileri (feed_analytics, user_events) üzerinden ALS işbirlikçi filtreleme modelini
eğitir ve Redis üzerindeki 'Sana Özel' (feed:foryou:*) önbelleklerini temizler.

Kullanım:
  cd /Users/tucibeyin/Desktop/teqlif/backend (veya VPS backend klasörü)
  python3 scripts/trigger_feed_ml.py
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


async def main():
    print("🚀 [TriggerFeedML] Teqlif Tavsiye Motoru Manuel Eğitim ve Önbellek Yönetimi Başlatılıyor...")
    
    from app.services.ml.feed_als_ml import train_feed_als
    from app.database import AsyncSessionLocal
    from app.utils.redis_client import get_redis

    # 1. ALS Modelini Eğit (PostgreSQL oturumu ile subcategory centroid'leri de hesaplanır)
    print("\n▶ 1. ALS modeli eğitiliyor (ClickHouse -> Redis faktör yazımı)...")
    try:
        async with AsyncSessionLocal() as db:
            await train_feed_als(db_session=db)
        print("✅ ALS eğitimi ve vektör atamaları tamamlandı.")
    except Exception as exc:
        print(f"❌ ALS eğitimi sırasında hata oluştu: {exc}")

    # 2. Redis üzerindeki Feed Önbelleklerini (Cache) Temizle
    print("\n▶ 2. Redis Feed önbellekleri temizleniyor (Invalidation)...")
    try:
        redis = await get_redis()
        
        # Temizlenecek desenler
        patterns = [
            "feed:foryou:*",
            "feed:recent:*",
            "feed:mixed_recent:*",
            "feed:swipe:*",
            "trending:*",
        ]
        
        total_deleted = 0
        for pat in patterns:
            keys = await redis.keys(pat)
            if keys:
                deleted = await redis.delete(*keys)
                total_deleted += deleted
                print(f"   🧹 {pat} -> {deleted} anahtar silindi.")
            else:
                print(f"   ▫️ {pat} -> Temizlenecek anahtar bulunamadı.")
                
        print(f"✅ Önbellek temizliği tamamlandı. Toplam {total_deleted} önbellek anahtarı sıfırlandı.")
    except Exception as exc:
        print(f"❌ Redis önbellek temizliği başarısız: {exc}")

    print("\n🎉 Tüm işlemler tamamlandı. Keşfet (Sizin İçin Seçilen İlanlar) akışı güncellenmiş model ve kurallarla hizmete hazır!")


if __name__ == "__main__":
    asyncio.run(main())
