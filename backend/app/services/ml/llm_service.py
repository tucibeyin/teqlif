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
        "Sen ikinci el ilan platformunda kendi ürününü satan bir kullanıcısın. Aşağıda verilen bilgilere dayanarak KISA, DOĞRUDAN ve SAMİMİ bir ilan metni yaz.\n\n"
        "KURALLAR:\n"
        "1. Maksimum 3-4 cümle yaz. Uzun destanlar yazma.\n"
        "2. Doğrudan satıcı ağzıyla yaz (Örn: 'Cihazım çok temizdir', 'Satıyorum').\n"
        "3. 'Size yardımcı olabilirim', 'Vurgulayalım', 'Öneririm' gibi robotik/asistan cümleleri KESİNLİKLE kurma.\n"
        "4. Uydurma bilgi ekleme.\n\n"
        "ÖRNEK ÇIKTI:\n"
        "'Telefonum hasarlıdır ancak kullanıma engel bir durumu yoktur. Parça niyetine veya tamir ettirip kullanmak isteyenler alabilir. Sadece Ankara içi elden teslim edebilirim. Alıcısına şimdiden hayırlı olsun.'\n"
    )
    
    cat_hints = []
    cat_lower = category.lower()
    if "elektronik" in cat_lower or "telefon" in cat_lower or "bilgisayar" in cat_lower:
        cat_hints.append("Donanım veya kozmetik durumundan kısaca bahset.")
    elif "araç" in cat_lower or "vasıta" in cat_lower or "araba" in cat_lower:
        cat_hints.append("Motor veya kaporta durumundan dürüstçe bahset.")
        
    cond_hints = []
    if condition == "new":
        cond_hints.append("Ürünün kutusunda, hiç kullanılmamış ve sıfır olduğunu coşkulu bir dille belirt.")
    elif condition == "like_new":
        cond_hints.append("Çok az kullanıldığını, adeta sıfır ayarında olduğunu, kılcal çizik bile olmadığını belirt.")
    elif condition == "used":
        cond_hints.append("İkinci el olduğunu ancak temiz kullanıldığını, yeni sahibine masraf çıkarmayacağını samimi bir dille belirt.")
    elif condition == "damaged":
        cond_hints.append("Hasarlı/arızalı olduğunu dürüstçe belirt. Tamir edilip kullanılabileceğini veya yedek parça olarak uygun fiyata fırsat olduğunu açıkla.")

    hints = "Özel Tavsiyeler:\n" + "\n".join(f"- {h}" for h in cat_hints + cond_hints)
    
    return base_prompt + "\n\n" + hints

def _generate_user_prompt(
    title: str,
    category: str,
    condition: Optional[str],
    price: Optional[float],
    location: Optional[str],
) -> str:
    """Kullanıcının verilerini LLM'e sunar."""
    lines = [
        "Aşağıdaki gerçek bilgileri kullanarak kendi ürünün için bir ilan metni oluştur:",
        f"- Ürün Başlığı: {title}",
        f"- Kategori: {category}",
    ]
    if condition:
        cond_tr = {"new": "Sıfır", "like_new": "Yeni Gibi", "used": "İkinci El", "damaged": "Hasarlı"}
        lines.append(f"- Durum: {cond_tr.get(condition, condition)}")
        
    if price and price > 0:
        lines.append(f"- Fiyat: {int(price)} TL (Bunu cümleye 'Fiyatı {int(price)} TL olarak uygun tuttum', '{int(price)} TL'ye bırakıyorum' gibi farklı ve doğal satıcı ağzıyla yedir)")
        
    if location:
        lines.append(f"- Teslimat Şekli: Sadece {location} içi elden teslim (Bunu 'Sadece {location} içinden gelip alabilirsiniz', 'Kargo yok, {location} elden teslim' gibi her defasında farklı ama net bir cümleyle belirt)")
    else:
        lines.append("- Teslimat Şekli: Kargo veya elden teslim seçenekleri mevcut. (Bunu cümleye doğal bir şekilde yedir)")
        
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
            "num_predict": 100
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
