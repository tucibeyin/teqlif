"""
Ollama (Qwen2.5:3b) LLM Servisi — Hybrid Streaming

Akış:
  1. _generate_system_prompt()  — slug-based kategori/durum kuralları.
  2. _generate_user_prompt()    — sadece ürün gövdesi (fiyat/lokasyon YOK).
  3. generate_listing_description_stream() — Ollama'yı stream eder,
     bitince _build_suffix() ile fiyat/lokasyon şablonunu yield eder.

Hybrid mantığı:
  - LLM → ürün tanıtım gövdesi  (yaratıcı, hallüsinasyon riski kabul edilebilir)
  - Şablon → fiyat + lokasyon cümlesi  (deterministik, asla kaybolmaz)
"""
import json
import logging
import random
from typing import AsyncGenerator, Optional
import httpx

logger = logging.getLogger(__name__)

OLLAMA_API_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "qwen2.5:3b"

# ── Kategori ipuçları (slug → hint) ──────────────────────────────────────────
_CAT_HINTS: dict[str, str] = {
    "elektronik": "Çalışmayan aksam olmadığını veya kozmetik durumunu (çizik, baret vb.) kısaca belirt.",
    "vasita":     "Motorunda veya karoserinde sıkıntı olup olmadığını dürüstçe belirt.",
    "emlak":      "Konumundan veya krediye uygunluğundan samimi bir dille bahset.",
    "giyim":      "Bedeninin uymadığı için ya da tarz değişikliğinden sattığını belirt.",
    "ev":         "Kırık veya çizik olmadığını ya da evde yer açmak için sattığını belirt.",
    "spor":       "Kullanım sıklığını ve genel durumunu kısaca belirt.",
    "kitap":      "Kapak veya sayfa durumunu belirt.",
}

# ── Ürün durumu etiketleri ─────────────────────────────────────────────────────
_CONDITION_LABELS: dict[str, str] = {
    "new":       "Sıfır (kutusunda, hiç açılmamış)",
    "like_new":  "Az kullanılmış (adeta sıfır)",
    "used":      "Kullanılmış",
    "damaged":   "Hasarlı / Arızalı",
}

# ── Fiyat şablonları ───────────────────────────────────────────────────────────
_PRICE_ONLY: list[str] = [
    "{price} TL'ye satıyorum, pazarlık payı var.",
    "Fiyatım {price} TL, ciddi alıcı beklerim.",
    "{price} TL istiyorum, fiyat konuşulur.",
    "{price} TL, sabit fiyat.",
]

# ── Lokasyon şablonları ────────────────────────────────────────────────────────
_LOCATION_ONLY: list[str] = [
    "Sadece {city} içi elden teslim yapabilirim.",
    "{city}'den elden teslim, kargoya bakmıyorum.",
    "Elden {city}'den verebilirim.",
    "{city} içinden elden teslim tercihim.",
]

# ── Fiyat + lokasyon birleşik şablonları ──────────────────────────────────────
_PRICE_AND_LOCATION: list[str] = [
    "{price} TL, sadece {city} içi elden teslim.",
    "{price} TL'ye satıyorum, {city}'den elden verebilirim.",
    "Fiyatım {price} TL. {city} içi elden teslim yapabilirim.",
    "{price} TL istiyorum, {city}'den elden.",
]


def _build_suffix(price: Optional[float], location: Optional[str]) -> str:
    """Fiyat ve/veya lokasyondan deterministik şablon cümlesi üretir."""
    p = f"{int(price):,}".replace(",", ".") if price and price > 0 else None
    c = location.strip() if location else None

    if p and c:
        return random.choice(_PRICE_AND_LOCATION).format(price=p, city=c)
    if p:
        return random.choice(_PRICE_ONLY).format(price=p)
    if c:
        return random.choice(_LOCATION_ONLY).format(city=c)
    return ""


def _generate_system_prompt(category: str, condition: Optional[str]) -> str:
    """Slug-based kategori ve duruma göre dinamik system prompt üretir."""
    base = (
        "Sen bir yapay zeka değilsin. Türkiye'de ikinci el ilan platformunda kendi ürününü satan "
        "sıradan bir vatandaşsın. Sadece ürün tanıtım metnini yaz.\n\n"
        "KESİN KURALLAR:\n"
        "1. Metnin başına veya sonuna ASLA tırnak işareti (' veya \") koyma.\n"
        "2. ASLA 'Merhaba', 'Size yardımcı olabilirim', 'Vurgulayalım' gibi YZ veya müşteri "
        "temsilcisi ifadeleri kullanma.\n"
        "3. 1. tekil şahıs (Ben) ağzıyla yaz: 'Satıyorum', 'Kullandım' gibi.\n"
        "4. En fazla 3 cümle. Samimi ol. 'Alıcısına hayırlı olsun', 'Pazarlık payı var', "
        "'İhtiyaçtan satılık' gibi gerçekçi satıcı jargonları kullanabilirsin.\n"
        "5. Günlük konuşma dilini kullan, cümleleri karmaşık kurma.\n"
        "6. ASLA kurumsal veya e-ticaret dili kullanma ('mağazamız', 'müşteri', 'hizmetlerimiz').\n"
        "7. 'Müşteri' yerine 'alıcı' veya 'yeni sahibi' de.\n"
        "8. KESİNLİKLE 1. tekil şahıs yaz. 'Ürününüz', 'Sizin için' gibi 2. şahıs hitapları YASAK.\n"
        "9. Başlık ile ürün durumu çelişiyorsa HER ZAMAN durumu esas al, hasarı dürüstçe belirt.\n"
        "10. Devrik, absürt veya çeviri kokan ifadeler kullanma; sade doğal Türkçe yaz.\n"
        "11. FİYAT VE TESLİMAT BİLGİSİ YAZMA. Sadece ürünü ve durumunu anlat; "
        "fiyat ve şehir bilgisi ayrıca eklenecek.\n"
    )

    hints: list[str] = []

    cat_hint = _CAT_HINTS.get(category.lower().strip())
    if cat_hint:
        hints.append(cat_hint)

    if condition == "new":
        hints.append("Ürünün kutusunda, hiç açılmamış sıfır ürün olduğunu belirt.")
    elif condition == "like_new":
        hints.append("Çok az kullanıldığını, adeta sıfır ayarında tertemiz olduğunu belirt.")
    elif condition == "used":
        hints.append("Temiz kullanıldığını ve yeni sahibine masraf çıkarmayacağını söyle.")
    elif condition == "damaged":
        hints.append("Üründe hasar/arıza olduğunu SAKLAMA; 'Hasarlıdır' veya 'Arızalıdır' diye açıkça belirt.")

    if hints:
        base += "\nÖzel Tavsiyeler:\n" + "\n".join(f"- {h}" for h in hints)

    return base


def _generate_user_prompt(
    title: str,
    category: str,
    condition: Optional[str],
) -> str:
    """Kullanıcı girdilerini XML etiketlerle LLM'e sunar (injection koruması)."""
    cond_label = _CONDITION_LABELS.get(condition or "", condition or "")
    lines = [
        "Aşağıdaki bilgileri kullanarak sadece ürün tanıtım metnini oluştur "
        "(fiyat ve teslimat bilgisi YAZMA, fazladan giriş/çıkış cümlesi de ekleme):",
        f"<urun>{title}</urun>",
        f"<kategori>{category}</kategori>",
    ]
    if cond_label:
        lines.append(f"<durum>{cond_label}</durum>")
    return "\n".join(lines)


async def generate_listing_description_stream(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> AsyncGenerator[str, None]:
    """
    LLM gövdesini stream eder, ardından fiyat/lokasyon şablonunu yield eder.
    Hata durumunda __LLM_ERROR__ sentinel'i yield eder.
    """
    system_prompt = _generate_system_prompt(category, condition)
    user_prompt = _generate_user_prompt(title, category, condition)

    payload = {
        "model": MODEL_NAME,
        "system": system_prompt,
        "prompt": user_prompt,
        "stream": True,
        "options": {
            "temperature": 0.4,
            "top_p": 0.85,
            "num_predict": 150,
            "num_thread": 4,
        },
    }

    try:
        logger.info("[LLM] Stream isteği gönderiliyor (%s) | title=%r", MODEL_NAME, title[:60])
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST", OLLAMA_API_URL, json=payload, timeout=120.0
            ) as response:
                if response.status_code != 200:
                    logger.error("[LLM] Ollama API hatası: %d", response.status_code)
                    yield "__LLM_ERROR__"
                    return

                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        data = json.loads(line)
                        token = data.get("response", "")
                        if token:
                            yield token
                    except json.JSONDecodeError:
                        continue

        # Gövde bitti — deterministik fiyat/lokasyon şablonunu ekle
        suffix = _build_suffix(price, location)
        if suffix:
            yield " "
            yield suffix

    except Exception as exc:
        logger.error("[LLM] Ollama bağlantı hatası: %s", exc)
        yield "__LLM_ERROR__"
