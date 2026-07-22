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
        "Sen Teqlif adlı e-ticaret platformunda satıcılar için profesyonel ilan metinleri yazan bir asistansın. "
        "Görevin, sana verilen bilgileri kullanarak alıcıların ilgisini çekecek, satışı hızlandıracak, "
        "samimi ve güven veren bir ürün açıklaması yazmaktır.\n\n"
        "KESİN KURALLAR:\n"
        "1. YALNIZCA TÜRKÇE yazacaksın. Çince, İngilizce veya başka hiçbir dil kullanma.\n"
        "2. Asla yalan söyleme veya üründe olmayan bir özelliği uydurma. Sadece sana verilen bilgileri kullan.\n"
        "3. Açıklama 2-3 kısa paragrafı geçmemelidir ve çok uzatılmamalıdır.\n"
        "4. Kendini asistan olarak tanıtma, metne doğrudan ilan açıklaması olarak başla.\n"
    )
    
    cat_hints = []
    cat_lower = category.lower()
    if "giyim" in cat_lower or "ayakkabı" in cat_lower:
        cat_hints.append("Ürünün kumaş yapısından, kalıbından, rahatlığından ve tarzından bahset.")
    elif "elektronik" in cat_lower or "telefon" in cat_lower or "bilgisayar" in cat_lower:
        cat_hints.append("Cihazın çalışmayan hiçbir aksamı olmadığını, teknik performansını ve günlük kullanımdaki avantajlarını öne çıkar.")
    elif "araç" in cat_lower or "vasıta" in cat_lower or "araba" in cat_lower:
        cat_hints.append("Aracın motor durumuna, kazasızlığına veya şeffaf bir şekilde varsa hasarına odaklan, bakım geçmişine vurgu yap.")
    else:
        cat_hints.append("Ürünün kalitesini, ne kadar işlevsel olduğunu ve neden satın alınması gerektiğini vurgula.")
        
    cond_hints = []
    if condition == "new":
        cond_hints.append("Ürünün KUTUSUNDA, HİÇ KULLANILMAMIŞ ve SIFIR olduğunu coşkulu bir dille belirt.")
    elif condition == "like_new":
        cond_hints.append("Ürünün çok az kullanıldığını, adeta sıfır ayarında olduğunu, kılcal çizik bile olmadığını vurgula.")
    elif condition == "used":
        cond_hints.append("Ürünün ikinci el olduğunu ancak temiz kullanıldığını, yeni alıcısına masraf çıkarmayacağını samimi bir dille belirt.")
    elif condition == "damaged":
        cond_hints.append("Ürünün hasarlı/arızalı olduğunu dürüstçe belirt. Tamir edilip kullanılabileceğini veya yedek parça olarak çok uygun fiyata fırsat olduğunu açıkla.")

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
        "Aşağıdaki bilgileri kullanarak profesyonel bir ilan metni yaz:",
        f"- İlan Başlığı: {title}",
        f"- Kategori: {category}",
    ]
    if condition:
        cond_tr = {"new": "Sıfır", "like_new": "Yeni Gibi", "used": "İkinci El", "damaged": "Hasarlı"}
        lines.append(f"- Durum: {cond_tr.get(condition, condition)}")
    
    if price and price > 0:
        lines.append(f"- Fiyat: {int(price)} TL (Fiyatın ürünün durumuna göre çok mantıklı olduğunu vurgula)")
    
    if location:
        lines.append(f"- Teslimat: Sadece {location} içi elden teslim (Kargo yok, elden görerek alma güvenini vurgula)")
    else:
        lines.append("- Teslimat: Kargo veya elden teslim seçenekleri mevcut.")
        
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
