"""
Ollama (Qwen2.5:3b) LLM Servisi — Hybrid Streaming

Akış:
  1. _build_prompt()  — kısa direktif + 2 few-shot örnek (kural listesi yerine).
  2. stream + preamble detector — YZ açılış cümlelerini ilk 80 char'da yakala.
  3. stop sequences — Ollama fiyat/teslimat token'ı üretirse durur.
  4. _build_suffix() — fiyat/lokasyon deterministik şablon olarak eklenir.

Hybrid mantığı:
  LLM  → ürün gövdesi (3-4 cümle, yaratıcı)
  Python → fiyat + lokasyon (deterministik, asla kaybolmaz, asla çifte gelmez)
"""
import json
import logging
import random
import re
from typing import AsyncGenerator, Optional
import httpx

logger = logging.getLogger(__name__)

OLLAMA_API_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "qwen2.5:3b"

# ── Fiyat + lokasyon şablonları ───────────────────────────────────────────────
_PRICE_ONLY: list[str] = [
    "{price} TL'ye satıyorum, pazarlık payı var.",
    "Fiyatım {price} TL, ciddi alıcı beklerim.",
    "{price} TL istiyorum, fiyat konuşulur.",
    "{price} TL, sabit fiyat.",
]
_LOCATION_ONLY: list[str] = [
    "Sadece {city} içi elden teslim yapabilirim.",
    "{city}'den elden teslim, kargoya bakmıyorum.",
    "Elden {city}'den verebilirim.",
    "{city} içinden elden teslim tercihim.",
]
_PRICE_AND_LOCATION: list[str] = [
    "{price} TL, sadece {city} içi elden teslim.",
    "{price} TL'ye satıyorum, {city}'den elden verebilirim.",
    "Fiyatım {price} TL. {city} içi elden teslim yapabilirim.",
    "{price} TL istiyorum, {city}'den elden.",
]

# ── Kategori ipuçları ─────────────────────────────────────────────────────────
_CAT_HINTS: dict[str, str] = {
    "elektronik": "Ekran, batarya ve genel çalışma durumunu belirt.",
    "vasita":     "Motor ve karoser durumunu dürüstçe belirt.",
    "emlak":      "Konumu ve krediye uygunluğunu kısaca belirt.",
    "giyim":      "Neden sattığını (beden uymadı, tarz değişti vb.) belirt.",
    "ev":         "Kırık/çizik varsa söyle, yoksa tertemiz olduğunu belirt.",
    "spor":       "Ne sıklıkta kullandığını ve genel durumunu belirt.",
    "kitap":      "Kapak ve sayfa durumunu belirt.",
}

# ── Ürün durumu etiketleri ────────────────────────────────────────────────────
_CONDITION_LABELS: dict[str, str] = {
    "new":       "Sıfır, kutusunda hiç açılmamış",
    "like_new":  "Az kullanılmış, adeta sıfır",
    "used":      "Kullanılmış, temiz",
    "damaged":   "Hasarlı veya arızalı",
}

# ── Few-shot örnekler (kategori → 2 örnek output) ────────────────────────────
_FEW_SHOT: dict[str, list[str]] = {
    "elektronik": [
        "3 yıl kullandım, ekranında hiç çizik yok, bataryası sağlıklı. Orijinal kutusu ve şarj adaptörü mevcut. İhtiyaçtan satılık, alıcısına hayırlı olsun.",
        "Ekran kırık, kamera çalışıyor ama dokunmatik kısmen hassas değil. Fiyata yansıttım, parça olarak da değerlendirebilirsiniz.",
    ],
    "vasita": [
        "2019 model, 85.000 km'de, motoru ve şanzımanı sorunsuz. Bakımları zamanında yapıldı, servis defteri mevcut. Sahibinden, ihtiyaçtan satılık.",
        "Kaporta hasarı var, motor çalışıyor fakat klima gaz istiyor. Fiyata yansıttım, ciddi alıcı beklerim.",
    ],
    "emlak": [
        "3+1, 120 m², güney cepheli, asansörlü binada 3. kat. Mutfak ve banyosu yenilenmiş, masraf gerektirmiyor. Krediye uygun.",
        "Köy içi, 500 m² arsa, imarlı. Tapu hazır, hemen devredebilirim.",
    ],
    "giyim": [
        "1 kere giyildi, bedenim uymadığı için satıyorum. Etiketi hâlâ üzerinde, tertemiz.",
        "Tarz değişikliğinden satıyorum, yırtık veya leke yok, temiz kullanıldı.",
    ],
    "ev": [
        "3 yıl kullandım, kırık veya çizik yok, tertemiz. Taşınma nedeniyle satıyorum.",
        "Koltuğun bir yerinde küçük bir çizik var, fiyata yansıttım. Genel durumu iyi.",
    ],
    "spor": [
        "Ayda 2-3 kez kullandım, hasar yok, aksesuarları tam. İhtiyaçtan satılık.",
        "Sporu bıraktığım için satıyorum, çok az kullandım, neredeyse sıfır gibi.",
    ],
    "kitap": [
        "Bir kere okunduktan sonra rafta kaldı, sayfaları ve kapağı tertemiz.",
        "Birkaç sayfasında not var, kapakta hafif yıpranma dışında sağlam.",
    ],
    "diger": [
        "Temiz kullandım, yırtık veya kırık yok. İhtiyaç fazlası olduğu için satıyorum.",
        "Az kullanılmış, genel durumu iyi. Alıcısına hayırlı olsun.",
    ],
}

# YZ/robot açılış kalıpları — preamble'da yakalanırsa atlanır
_RE_AI_OPENER = re.compile(
    r"^(üzgünüm\b|tabii\s+ki\b|elbette\b|merhaba\b|size\s+yardım|ürününüz\b|"
    r"aşağıda\b|işte\s+ilan|evet[,\s]|anladım\b)",
    re.IGNORECASE,
)


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


def _build_prompt(
    title: str,
    category: str,
    condition: Optional[str],
) -> tuple[str, str]:
    """
    (system_prompt, user_prompt) döner.
    Strateji: kural listesi yerine kısa direktif + 2 somut örnek.
    3b model örnekleri taklit eder, kuralları analiz edemez.
    """
    cat = category.lower().strip()
    cond_label = _CONDITION_LABELS.get(condition or "", "")
    cat_hint = _CAT_HINTS.get(cat, "")
    examples = _FEW_SHOT.get(cat, _FEW_SHOT["diger"])

    system = (
        "Türkiye'de ikinci el ilan platformunda bireysel satıcısın. "
        "Sana ürün bilgisi verilecek, sen sadece kısa ilan metnini yazacaksın. "
        "Kurallar: 1. tekil şahıs kullan (Ben/Satıyorum). "
        "Fiyat ve teslimat bilgisi YAZMA. "
        "YZ gibi 'Merhaba' veya 'Tabii ki' ile başlama. "
        "Özür veya açıklama cümlesi ekleme, direkt ilan metnini yaz. "
        "3-4 cümle, sade Türkçe.\n\n"
        f"İyi örnek:\n\"{examples[0]}\"\n\n"
        f"İyi örnek:\n\"{examples[1]}\""
    )

    user_lines = [
        "Şu ürün için ilan metni yaz:",
        f"Ürün: {title}",
        f"Durum: {cond_label}" if cond_label else "",
        f"Not: {cat_hint}" if cat_hint else "",
    ]
    user = "\n".join(line for line in user_lines if line)

    return system, user


async def generate_listing_description_stream(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> AsyncGenerator[str, None]:
    """
    LLM gövdesini stream eder, ardından suffix yield eder.
    - Preamble buffer (ilk 80 char): YZ açılış cümlesi yakalanırsa atlanır.
    - Stop sequences: Ollama fiyat/lokasyon yazmaya başlayınca durur.
    - Hata: __LLM_ERROR__ sentinel yield eder.
    """
    system_prompt, user_prompt = _build_prompt(title, category, condition)

    payload = {
        "model": MODEL_NAME,
        "system": system_prompt,
        "prompt": user_prompt,
        "stream": True,
        "keep_alive": "10m",   # warm model — cold start önler
        "options": {
            "temperature": 0.5,
            "top_p": 0.85,
            "num_predict": 150,
            "num_thread": 6,
            "stop": [
                # Fiyat/lokasyon cümlesi başlamadan önce durdur
                " TL", " lira", "₺",
                "elden teslim", "Elden teslim",
                "kargo", "Kargo",
                "Fiyat", "fiyat",
                "Ücret", "ücret",
            ],
        },
    }

    try:
        logger.info("[LLM] Stream isteği (%s) | title=%r", MODEL_NAME, title[:60])

        # Preamble buffer — ilk 80 char'da YZ açılış tespiti
        _PREAMBLE_LEN = 80
        preamble_buf = ""
        preamble_done = False
        total_chars = 0

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
                    except json.JSONDecodeError:
                        continue

                    token = data.get("response", "")
                    if not token:
                        continue

                    if not preamble_done:
                        preamble_buf += token
                        if len(preamble_buf) >= _PREAMBLE_LEN:
                            preamble_done = True
                            # YZ açılış cümlesini sil
                            clean_start = _RE_AI_OPENER.sub("", preamble_buf).lstrip()
                            if clean_start != preamble_buf.lstrip():
                                logger.warning("[LLM] YZ açılış cümlesi tespit edildi ve silindi")
                            if clean_start:
                                yield clean_start
                                total_chars += len(clean_start)
                    else:
                        yield token
                        total_chars += len(token)

        # Preamble dolmadan stream bittiyse (çok kısa çıktı) — onu da yield et
        if not preamble_done and preamble_buf:
            clean_start = _RE_AI_OPENER.sub("", preamble_buf).lstrip()
            if clean_start:
                yield clean_start
                total_chars += len(clean_start)

        # Suffix — her zaman Python'dan gelir
        suffix = _build_suffix(price, location)
        if suffix:
            yield " "
            yield suffix

        logger.info("[LLM] Tamamlandı | %d char | suffix=%r", total_chars, suffix or "─")

    except Exception as exc:
        logger.error("[LLM] Ollama bağlantı hatası: %s", exc)
        yield "__LLM_ERROR__"
