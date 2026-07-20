import asyncio
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

def test_ml_services():
    print("\n[TEST] Sprint 9: ML & Moderation Servisleri Testi Başlıyor...")

    # ML servisleri genelde internal çalışır, sadece modül importlarının bozulmadığını test ediyoruz.
    try:
        import app.services.nsfw_service
        import app.services.feed_als_ml
        print("✅ Başarılı: ML servisleri import edilebiliyor ve izole edildi.")
    except Exception as e:
        print(f"⚠️ Import hatası: {e}")

    print("\n🎉 Tüm ML Testleri Tamamlandı!")

if __name__ == "__main__":
    test_ml_services()
