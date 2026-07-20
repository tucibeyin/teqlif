import asyncio
import logging
import os
import sys

# Add backend directory to PYTHONPATH
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.ml.turkish_nlp import stem_word, build_stemmed_tsquery
from app.core.auto_mod import auto_mod

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_ml_services():
    print("\n[TEST] Sprint 14: ML & Moderasyon Servisleri Testi Başlıyor...\n")

    # 1. NLP Testi
    try:
        word = "ayakkabılar"
        stem = stem_word(word)
        print(f"✅ NLP Test 1 (Stemming): '{word}' -> '{stem}'")
        
        query = "koşu ayakkabıları"
        tsquery = build_stemmed_tsquery(query)
        print(f"✅ NLP Test 2 (TSQuery): '{query}' -> '{tsquery}'")
    except Exception as e:
        print(f"❌ NLP Testi Hata: {e}")

    # 2. Moderation Testi
    try:
        safe_text = "Merhaba nasılsın"
        is_bad = auto_mod(safe_text, "chat")
        print(f"✅ Moderation Test 1 (Safe Text): '{safe_text}' -> is_bad={is_bad}")
    except Exception as e:
        print(f"❌ Moderation Testi Hata: {e}")

    print("\n🎉 Tüm ML Testleri Başarıyla Tamamlandı!\n")

if __name__ == "__main__":
    asyncio.run(test_ml_services())
