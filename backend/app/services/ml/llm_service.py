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
        "Sen kendi ürününü satmaya çalışan bir satıcısın. Kendi ürünün için bir ilan açıklaması yazıyorsun. "
        "Görevin, sana verilen bilgileri kullanarak alıcıların ilgisini çekecek, "
        "samimi ve güven veren bir ürün açıklaması yazmaktır.\n\n"
        "KESİN KURALLAR:\n"
        "1. YALNIZCA TÜRKÇE yazacaksın. Çince, İngilizce veya başka hiçbir dil kullanma.\n"
        "2. Asla yalan söyleme veya üründe olmayan bir özelliği uydurma. Sadece sana verilen bilgileri kullan.\n"
        "3. Açıklama 2 kısa paragrafı geçmemelidir.\n"
        "4. ASİSTAN GİBİ KONUŞMA ('şunu vurgulayabiliriz', 'kargo ücretlerini paylaşacağız', 'sizin için' vb). DOĞRUDAN SATICI GİBİ KONUŞ ('Cihazım çok temizdir', 'Elden teslim edeceğim', 'Sorunsuzdur').\n"
        "5. Sana verilen talimat cümlelerini metnin içine kopyalama. O talimatların GEREĞİNİ YAP, kendisini yazma.\n"
    )
    
    cat_hints = []
    cat_lower = category.lower()
    if "giyim" in cat_lower or "ayakkabı" in cat_lower:
        cat_hints.append("Kumaş yapısından, kalıbından, rahatlığından ve tarzından kısaca bahset.")
    elif "elektronik" in cat_lower or "telefon" in cat_lower or "bilgisayar" in cat_lower:
        cat_hints.append("Çalışmayan hiçbir aksamı olmadığını ve teknik performansını birinci tekil şahıs ('cihazımın') olarak öne çıkar.")
    elif "araç" in cat_lower or "vasıta" in cat_lower or "araba" in cat_lower:
        cat_hints.append("Aracın motor durumuna, kazasızlığına veya varsa hasarına dürüstçe odaklan.")
    else:
        cat_hints.append("Ürünün kalitesini ve neden satın alınması gerektiğini satıcı gözünden vurgula.")
        
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
        "Aşağıdaki bilgileri kullanarak kendi ürünün için bir ilan metni oluştur:",
        f"- Ürün Başlığı: {title}",
        f"- Kategori: {category}",
    ]
    if condition:
        cond_tr = {"new": "Sıfır", "like_new": "Yeni Gibi", "used": "İkinci El", "damaged": "Hasarlı"}
        lines.append(f"- Durum: {cond_tr.get(condition, condition)}")
    
    if price and price > 0:
        lines.append(f"- Fiyat: {int(price)} TL (Bu fiyatın ne kadar uygun olduğunu doğal bir şekilde belirt)")
    
    if location:
        lines.append(f"- Teslimat Şekli: Sadece {location} içi elden teslim (Alıcının ürünü görerek gönül rahatlığıyla alabileceğini belirt)")
    else:
        lines.append("- Teslimat Şekli: Kargo veya elden teslim seçenekleri mevcut.")
        
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
            "top_p": 0.85
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
