"""
Ollama (Qwen2.5:3b) LLM Servisi (API üzerinden Streaming)

Akış:
  1. _generate_system_prompt() — Kombinasyonlara göre sistem komutunu (copywriting kurallarını) hazırlar.
  2. _generate_user_prompt() — Kullanıcının girdiği ilan verilerini hazırlar.
  3. generate_listing_description_stream() — Ollama API'sine istek atar ve sonucu stream eder.
"""
import json
import logging
from typing import AsyncGenerator, Optional
import httpx

logger = logging.getLogger(__name__)

OLLAMA_API_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "qwen2.5:3b"

def _generate_system_prompt(category: str, condition: Optional[str]) -> str:
    """Kategori ve duruma göre dinamik pazarlama kopyası kuralları üretir."""
    base_prompt = (
        "Sen bir yapay zeka değilsin. Sen Türkiye'de ikinci el ilan platformunda (Letgo, Sahibinden gibi) kendi şahsi ürününü satan normal bir vatandaşsın. Sadece doğrudan ilan açıklamasını yaz.\n\n"
        "KESİN KURALLAR:\n"
        "1. Metnin başına veya sonuna ASLA tırnak işareti (' veya \") koyma.\n"
        "2. ASLA 'Size yardımcı olabilirim', 'Vurgulayalım', 'Öneririm', 'Merhaba' gibi yapay zeka veya müşteri temsilcisi kelimeleri kullanma.\n"
        "3. Doğrudan 1. tekil şahıs (Ben) ağzıyla yaz (Örn: 'Satıyorum', 'Kullandım').\n"
        "4. En fazla 3-4 cümle kur. Samimi ol. 'Alıcısına hayırlı olsun', 'Pazarlık payı vardır', 'İhtiyaçtan satılık' gibi gerçekçi Türk satıcı jargonları kullan.\n"
        "5. Cümleleri çok karmaşık kurma, günlük konuşma dilini kullan.\n"
        "6. ASLA 'sepetimize eklendi', 'mağazamızda', 'hizmetler sunabilirim', 'özel hizmetler' gibi e-ticaret/kurumsal firma ağzı kullanma. Sen bireysel bir satıcısın.\n"
        "7. ASLA 'müşteri' veya 'müşteriler' kelimesini kullanma. Bunun yerine 'alıcı' veya 'yeni sahibi' de.\n"
        "8. METNİ KESİNLİKLE 1. TEKİL ŞAHIS (Ben) AĞZIYLA YAZ. 'Ürününüz' deme 'Ürünüm' veya 'Cihazım' de. 'Bıraktığını unutmayın' deme, 'Bıraktım' de.\n"
        "9. Eğer ürün durumu (Condition) ile başlık çelişiyorsa, HER ZAMAN durumu (Condition) baz al ve hasarı/arızayı dürüstçe belirt.\n"
        "10. 'Tıbbi olarak temiz', 'bana dikkat etmeyin', 'durulamaz' gibi devrik, saçma veya çeviri kokan absürt cümleler KESİNLİKLE kurma. Sadece son derece sade, normal bir Türkçe kullan.\n"
    )
    
    cat_hints = []
    cat_lower = category.lower()
    if "elektronik" in cat_lower or "telefon" in cat_lower or "bilgisayar" in cat_lower:
        cat_hints.append("Çalışmayan aksamı olmadığını veya kozmetik durumunu (çizik vs.) kısaca belirt.")
    elif "araç" in cat_lower or "vasıta" in cat_lower or "araba" in cat_lower:
        cat_hints.append("Yürüründe veya motorunda sıkıntı olup olmadığını dürüstçe belirt.")
    elif "emlak" in cat_lower or "ev" in cat_lower or "arsa" in cat_lower:
        cat_hints.append("Masrafsız olduğunu, konumunu veya krediye uygunluğunu samimi bir dille belirt.")
    elif "giyim" in cat_lower or "ayakkabı" in cat_lower:
        cat_hints.append("Bedeninin uymadığı için veya tarz değişikliğinden dolayı sattığını belirt.")
    elif "mobilya" in cat_lower or "eşya" in cat_lower:
        cat_hints.append("Kırık/çizik olmadığını veya evde yer açmak için sattığını belirt. (Çamur vb. saçma kelimeler kullanma).")
        
    cond_hints = []
    if condition == "new":
        cond_hints.append("Ürünün kutusunda, hiç açılmamış sıfır ürün olduğunu belirt.")
    elif condition == "like_new":
        cond_hints.append("Çok az kullanıldığını, adeta sıfır ayarında tertemiz olduğunu belirt.")
    elif condition == "used":
        cond_hints.append("Temiz kullanıldığını ve yeni sahibine masraf çıkarmayacağını söyle.")
    elif condition == "damaged":
        cond_hints.append("Üründe hasar/arızalar olduğunu saklama. Yedek parça veya tamirlik alanlar için uygun fiyata bıraktığını söyle.")

    hints = "Özel Tavsiyeler:\n" + "\n".join(f"- {h}" for h in cat_hints + cond_hints)
    
    return base_prompt + "\n" + hints

def _generate_user_prompt(
    title: str,
    category: str,
    condition: Optional[str],
    price: Optional[float],
    location: Optional[str],
) -> str:
    """Kullanıcının verilerini LLM'e sunar."""
    lines = [
        "Aşağıdaki bilgileri kullanarak sadece ilan metnini oluştur (Fazladan giriş/çıkış cümlesi yazma):",
        f"- Ürün: {title}",
    ]
    
    if price and price > 0:
        lines.append(f"- Fiyat: {int(price)} TL (Bu fiyatı metnin içine doğalca yedir, örn: 'Fiyatını {int(price)} TL olarak uygun tuttum', '{int(price)} TL istiyorum')")
        
    if location:
        lines.append(f"- Teslimat: Sadece {location} (Örn: 'Sadece {location} içi elden teslim yapabilirim' yaz ve metni bitir)")
    else:
        lines.append("- Teslimat: Kargo veya elden teslim yapabilirim.")
        
    return "\n".join(lines)


async def generate_listing_description_stream(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> AsyncGenerator[str, None]:
    """
    Ollama API'sine bağlanıp üretilen metni stream eder (yield chunk).
    """
    system_prompt = _generate_system_prompt(category, condition)
    user_prompt = _generate_user_prompt(title, category, condition, price, location)
    
    payload = {
        "model": MODEL_NAME,
        "system": system_prompt,
        "prompt": user_prompt,
        "stream": True,
        "options": {
            "temperature": 0.4,
            "top_p": 0.85,
            "num_predict": 100,
            "num_thread": 4
        }
    }
    
    try:
        logger.info(f"[LLM] Sending stream request to Ollama ({MODEL_NAME}). Timeout=120.0s")
        async with httpx.AsyncClient() as client:
            async with client.stream("POST", OLLAMA_API_URL, json=payload, timeout=120.0) as response:
                logger.info(f"[LLM] Ollama response status: {response.status_code}")
                if response.status_code != 200:
                    logger.error(f"[LLM] Ollama API Error: {response.status_code}")
                    yield "Yapay zeka sunucusu şu an meşgul. Lütfen daha sonra tekrar deneyin."
                    return
                
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                        if "response" in data:
                            yield data["response"]
                    except json.JSONDecodeError:
                        continue
    except Exception as exc:
        logger.error(f"[LLM] Ollama bağlantı hatası: {exc}")
        yield "Yapay zeka sistemine şu an ulaşılamıyor. (Lütfen Ollama'nın kurulu olduğundan emin olun)."
