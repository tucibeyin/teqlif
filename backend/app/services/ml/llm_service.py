"""
Groq (llama-3.3-70b) primary / Gemini (gemini-3.1-flash-lite) fallback LLM Servisi

Provider seçimi:
  1. Groq   — API key var ve günlük kota dolmamışsa (14,000 req/gün)
  2. Gemini — Groq key yok, kota dolmuş veya hata (1,000 req/gün güvenli marj)

Her iki path da aynı sentence-boundary streaming + Python-side suffix kullanır.
"""
import json
import logging
import random
import re
from datetime import date
from typing import AsyncGenerator, Optional
import httpx

from app.config import settings
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

# ── Sağlayıcı ayarları ────────────────────────────────────────────────────────
GROQ_API_URL      = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL        = "llama-3.3-70b-versatile"
_GROQ_DAILY_LIMIT = 14_000

GEMINI_API_URL    = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:streamGenerateContent"
_GEMINI_DAILY_LIMIT = 1_000  # günlük güvenli marj (free tier: 1500 req/gün)

# Groq max 4 stop word kabul eder; Gemini 5'e kadar
_STOP_WORDS = ["TL", "₺", "elden", "kargo"]

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
    "elektronik": "Ekran ve batarya durumunu belirt.",
    "vasita":     "Motor ve karoser durumunu dürüstçe belirt.",
    "emlak":      "Konumu ve krediye uygunluğunu kısaca belirt.",
    "giyim":      "Neden sattığını belirt.",
    "ev":         "Kırık çizik varsa söyle.",
    "spor":       "Kullanım sıklığını ve genel durumunu belirt.",
    "kitap":      "Kapak ve sayfa durumunu belirt.",
}

# ── Ürün durumu etiketleri ────────────────────────────────────────────────────
_CONDITION_LABELS: dict[str, str] = {
    "new":       "Sıfır, kutusunda hiç açılmamış",
    "like_new":  "Az kullanılmış, adeta sıfır",
    "used":      "Kullanılmış, temiz",
    "damaged":   "Hasarlı veya arızalı",
}

# ── Condition-aware few-shot örnekler ─────────────────────────────────────────
# ex1 → ürün durumu/özellikleri paragrafı örneği
# ex2 → satış nedeni/alıcıya not paragrafı örneği
_FEW_SHOT: dict[tuple[str, str], tuple[str, str]] = {
    ("elektronik", "new"): (
        "Hiç açmadım, kutusunda duruyor, tüm aksesuarları tam. Ekranında çizik yok, fabrika ayarlarında.",
        "Hediye almıştım ama ihtiyacım olmadı. Alıcısına hayırlı olsun.",
    ),
    ("elektronik", "like_new"): (
        "Çok az kullandım, ekranında hiç çizik yok, bataryası gayet sağlıklı. Kutusunu ve şarj adaptörünü sakladım.",
        "İhtiyaçtan satıyorum. Almak isteyenler ulaşabilir.",
    ),
    ("elektronik", "used"): (
        "2 yıl kullandım, ekranda küçük çizikler var ama çalışması tam. Bataryası hâlâ iyi, masraf çıkarmaz.",
        "Yeni telefon aldığım için satıyorum. Fiyata yansıttım.",
    ),
    ("elektronik", "damaged"): (
        "Ekran kırık, kamera çalışıyor ama dokunmatik kısmen hassas değil. Hasarı olduğu gibi söylüyorum.",
        "Parça olarak da değerlendirilebilir. Ciddi alıcı beklerim.",
    ),
    ("vasita", "new"): (
        "0 km, hiç binmedim, fabrika ayarlarında. Tüm belgeleri ve garantisi mevcut.",
        "Depolama amaçlı almıştım, ihtiyacım kalmadı. Anahtar teslim satıyorum.",
    ),
    ("vasita", "like_new"): (
        "2021 model, 15.000 km'de, motoru ve şanzımanı sorunsuz, kazasız. Bakımları zamanında yapıldı.",
        "İhtiyaçtan satıyorum. Kaporta hasarı yok, muayenesi yeni.",
    ),
    ("vasita", "used"): (
        "2018 model, 95.000 km'de, motor ve şanzıman sağlam. Bakım geçmişi bende mevcut.",
        "İhtiyaçtan satılık. Küçük kaporta çizikleri var, fiyata yansıttım.",
    ),
    ("vasita", "damaged"): (
        "Kaporta hasarı var, motor çalışıyor fakat klima gaz istiyor. Her şeyi olduğu gibi söylüyorum.",
        "Ciddi alıcı beklerim. Fiyatı hasara göre düşük tuttum.",
    ),
    ("emlak", "new"): (
        "Sıfır daire, hiç oturulmadı, tapu hazır. İnşaat firmasından alındı, masrafsız teslim.",
        "Yeni bina, 2024 yapımı, asansörlü. Hemen taşınılabilir.",
    ),
    ("emlak", "like_new"): (
        "3 yıllık bina, 2+1, 80 m². Temiz kullandık, hiç tadilat yapmadan taşınabilirsiniz.",
        "Şehir dışına taşındığımız için satıyoruz. Krediye uygun, tapu bende mevcut.",
    ),
    ("emlak", "used"): (
        "Eski bina ama sağlam yapı, 3+1, 110 m². Mutfak yenilendi, banyo eski ama çalışıyor.",
        "İhtiyaçtan satılık. Fiyatı tadilat ihtiyacına göre düşük tuttum.",
    ),
    ("emlak", "damaged"): (
        "Depremden etkilenmiş, hasar tespit raporu var. Arsası değerli.",
        "Üstü yıkılarak yeniden yapılabilir. Fiyatı buna göre ayarladım.",
    ),
    ("giyim", "new"): (
        "Hiç giymeden satıyorum, etiketi üzerinde. Marka ürün, tertemiz.",
        "Hediye almıştım ama bedenim uymadı. Alıcısına hayırlı olsun.",
    ),
    ("giyim", "like_new"): (
        "1-2 kere giydim, yırtık veya leke yok, sıfır gibi duruyor.",
        "Bedenim değişti, bu yüzden satıyorum. Tarz değişikliğinden de olabilir.",
    ),
    ("giyim", "used"): (
        "Temiz kullandım, yırtık yok ama hafif solma var.",
        "Birkaç sezon giydim, ihtiyaçtan satıyorum. Fiyata yansıttım.",
    ),
    ("giyim", "damaged"): (
        "Küçük yırtık var, dikişle onarılabilir. Leke yoktur.",
        "Hasarını söyledim, fiyatı düşük tutuyorum. Alıcısına hayırlı olsun.",
    ),
    ("ev", "new"): (
        "Sıfır, hiç kullanmadım, açılmamış paketinde. Tüm parçaları tam.",
        "Taşınırken aldım ama o odaya sığmadı. İhtiyaç fazlası.",
    ),
    ("ev", "like_new"): (
        "Çok az kullandım, çizik veya hasar yok, sıfır gibi duruyor.",
        "Taşınma nedeniyle satıyorum. Almak isteyene hayırlı olsun.",
    ),
    ("ev", "used"): (
        "2 yıl kullandım, çalışması tam, küçük çizikler var.",
        "Taşınma nedeniyle satıyorum. Masraf çıkarmaz.",
    ),
    ("ev", "damaged"): (
        "Çalışıyor ama yüzeyde hasar var. Bir köşesi kırık, işlevselliği etkilemiyor.",
        "Hasarını söyledim, fiyatı buna göre düşük tuttum.",
    ),
    ("spor", "new"): (
        "Hiç kullanmadım, kutusunda duruyor. Tüm aksesuarları tam.",
        "Spor yapmaya başlayamamıştım, ihtiyaç fazlası. Alıcısına hayırlı olsun.",
    ),
    ("spor", "like_new"): (
        "Çok az kullandım, hasar yok, aksesuarları tam.",
        "Sporu bıraktığım için satıyorum. İhtiyacı olana hayırlı olsun.",
    ),
    ("spor", "used"): (
        "Düzenli kullandım, işlevsel ama kullanım izleri var.",
        "Yeni ekipman aldığım için satıyorum. Masraf çıkarmaz.",
    ),
    ("spor", "damaged"): (
        "Çalışıyor ama hasar var. Bir parçası kırık, tamir edilebilir.",
        "Kendisi onaracak birine gider. Fiyatı buna göre düşük.",
    ),
    ("kitap", "new"): (
        "Hiç okunmadı, kapağı ve sayfaları tertemiz, yeni gibi.",
        "Almıştım ama okuyamadım. Alıcısına iyi okumalar.",
    ),
    ("kitap", "like_new"): (
        "Bir kere okundu, kapağı ve sayfaları tertemiz, not yok.",
        "Rafta yer kaplıyor, satıyorum. İyi okumalar.",
    ),
    ("kitap", "used"): (
        "Okunmuş, birkaç sayfada altı çizili notlar var. Kapağı sağlam.",
        "Kitaplığımı düzenliyorum, ihtiyaçtan satıyorum.",
    ),
    ("kitap", "damaged"): (
        "Kapağı yırtılmış ama sayfalar tam, okunabilir durumda.",
        "Hasarını söyledim, fiyatı düşük tutuyorum.",
    ),
    ("diger", "new"): (
        "Sıfır, hiç kullanmadım, tüm parçaları tam.",
        "İhtiyaç fazlası, alıcısına hayırlı olsun.",
    ),
    ("diger", "like_new"): (
        "Az kullandım, hasarsız ve temiz, sıfır gibi duruyor.",
        "İhtiyacım kalmadığı için satıyorum.",
    ),
    ("diger", "used"): (
        "Temiz kullandım, iyi durumda, masraf çıkarmaz.",
        "İhtiyaçtan satılık. Alıcısına hayırlı olsun.",
    ),
    ("diger", "damaged"): (
        "Hasarlı, olduğu gibi söylüyorum.",
        "Fiyatı buna göre düşük tuttum. Onarcak birine gider.",
    ),
}

# YZ açılış kalıpları — ilk cümlede tespit edilirse atlanır
_RE_AI_OPENER = re.compile(
    r"^(üzgünüm\b|tabii\s+ki\b|elbette\b|merhaba\b|size\s+yardım|ürününüz\b|"
    r"aşağıda\b|işte\s+ilan|evet[,\s]|anladım\b|ilan\s+metni\b)",
    re.IGNORECASE,
)

_SENTENCE_END = frozenset({".", "!", "?"})


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────
def _build_suffix(price: Optional[float], location: Optional[str]) -> str:
    p = f"{int(price):,}".replace(",", ".") if price and price > 0 else None
    c = location.strip() if location else None
    if p and c:
        return random.choice(_PRICE_AND_LOCATION).format(price=p, city=c)
    if p:
        return random.choice(_PRICE_ONLY).format(price=p)
    if c:
        return random.choice(_LOCATION_ONLY).format(city=c)
    return ""


def _build_prompt(title: str, category: str, condition: Optional[str]) -> tuple[str, str]:
    cat = category.lower().strip()
    cond = condition or "used"
    cond_label = _CONDITION_LABELS.get(cond, "")
    cat_hint = _CAT_HINTS.get(cat, "")

    key = (cat, cond)
    ex1, ex2 = (
        _FEW_SHOT.get(key)
        or _FEW_SHOT.get(("diger", cond))
        or _FEW_SHOT[("diger", "used")]
    )

    system = (
        "Türkiye'de ikinci el ilan platformunda bireysel satıcısın. "
        "Sana ürün bilgisi verilecek, sen sadece ilan metnini yazacaksın.\n"
        "- Birinci tekil şahısla yaz: 'kullandım', 'satıyorum', 'aldım' gibi.\n"
        "- TAM OLARAK İKİ PARAGRAF yaz, aralarına boş satır bırak.\n"
        "  1. paragraf: ürünün durumu ve özellikleri (2-3 cümle).\n"
        "  2. paragraf: neden sattığın veya alıcıya kısa not (1-2 cümle).\n"
        "- Fiyat ve teslimat bilgisi YAZMA.\n"
        "- Özür veya açıklama cümlesi ekleme, direkt metni yaz.\n"
        "- Sade Türkçe, tırnak işareti kullanma.\n\n"
        f"Örnek 1. paragraf:\n{ex1}\n\n"
        f"Örnek 2. paragraf:\n{ex2}"
    )
    user_lines = [
        "Şu ürün için ilan metni yaz:",
        f"Ürün: {title}",
        f"Durum: {cond_label}" if cond_label else "",
        f"Not: {cat_hint}" if cat_hint else "",
    ]
    user = "\n".join(line for line in user_lines if line)
    return system, user


# ── Kota kontrolü ────────────────────────────────────────────────────────────
async def _quota_ok(provider: str, daily_limit: int) -> bool:
    try:
        redis = await get_redis()
        key = f"{provider}:calls:{date.today().isoformat()}"
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, 86_400)
        if count > daily_limit:
            logger.warning("[LLM] %s günlük kota doldu (%d req)", provider, count)
            return False
        return True
    except Exception as exc:
        logger.error("[LLM] Redis kota kontrolü başarısız (%s): %s — deneniyor", provider, exc)
        return True


# ── Raw token async generatorlar ─────────────────────────────────────────────
async def _tokens_groq(system: str, user: str) -> AsyncGenerator[str, None]:
    headers = {
        "Authorization": f"Bearer {settings.groq_api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": GROQ_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.5,
        "max_tokens": 250,
        "stop": _STOP_WORDS,
        "stream": True,
    }
    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST", GROQ_API_URL, headers=headers, json=payload, timeout=60.0
        ) as resp:
            if resp.status_code != 200:
                body = await resp.aread()
                raise RuntimeError(f"Groq HTTP {resp.status_code}: {body[:200]}")
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                raw = line[6:].strip()
                if raw == "[DONE]":
                    break
                try:
                    delta = json.loads(raw)["choices"][0]["delta"].get("content", "")
                    if delta:
                        yield delta
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue


async def _tokens_gemini(system: str, user: str) -> AsyncGenerator[str, None]:
    payload = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {
            "temperature": 0.5,
            "maxOutputTokens": 250,
            "stopSequences": _STOP_WORDS,
        },
    }
    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST",
            GEMINI_API_URL,
            params={"key": settings.gemini_api_key, "alt": "sse"},
            json=payload,
            timeout=60.0,
        ) as resp:
            if resp.status_code != 200:
                body = await resp.aread()
                raise RuntimeError(f"Gemini HTTP {resp.status_code}: {body[:200]}")
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                raw = line[6:].strip()
                try:
                    data = json.loads(raw)
                    text = (
                        data.get("candidates", [{}])[0]
                            .get("content", {})
                            .get("parts", [{}])[0]
                            .get("text", "")
                    )
                    if text:
                        yield text
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue


# ── Sentence-boundary wrapper ─────────────────────────────────────────────────
async def _sentence_stream(
    token_gen: AsyncGenerator[str, None],
    price: Optional[float],
    location: Optional[str],
    provider: str,
) -> AsyncGenerator[str, None]:
    """Token stream'ini cümle sınırlarında flush eder, suffix ekler."""
    sentence_buf = ""
    is_first = True
    total_chars = 0

    async for token in token_gen:
        sentence_buf += token
        if any(c in token for c in _SENTENCE_END):
            if is_first:
                is_first = False
                clean = _RE_AI_OPENER.sub("", sentence_buf).lstrip()
                if clean != sentence_buf.lstrip():
                    logger.warning("[LLM] YZ açılış cümlesi silindi")
                sentence_buf = clean
            if sentence_buf.strip():
                yield sentence_buf
                total_chars += len(sentence_buf)
            sentence_buf = ""

    if sentence_buf.strip():
        logger.info("[LLM] Dangling fragment yutuldu: %r", sentence_buf[:60])

    suffix = _build_suffix(price, location)
    if suffix:
        yield "\n\n"
        yield suffix

    logger.info("[LLM] Tamamlandı | %s | %d char | suffix=%r", provider, total_chars, suffix or "─")


# ── Public API ────────────────────────────────────────────────────────────────
async def generate_listing_description_stream(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> AsyncGenerator[str, None]:
    """
    Groq primary → Gemini fallback.
    Sentence-boundary streaming: her cümleyi nokta/ünlem gelince flush eder.
    """
    system_prompt, user_prompt = _build_prompt(title, category, condition)

    # ── Groq path ─────────────────────────────────────────────────────────────
    if settings.groq_api_key and await _quota_ok("groq", _GROQ_DAILY_LIMIT):
        try:
            logger.info("[LLM] Groq | title=%r", title[:60])
            async for chunk in _sentence_stream(
                _tokens_groq(system_prompt, user_prompt), price, location, "groq"
            ):
                yield chunk
            return
        except Exception as exc:
            logger.error("[LLM] Groq başarısız, Gemini'ye fallback: %s", exc)

    # ── Gemini fallback ────────────────────────────────────────────────────────
    if settings.gemini_api_key and await _quota_ok("gemini", _GEMINI_DAILY_LIMIT):
        try:
            logger.info("[LLM] Gemini | title=%r", title[:60])
            async for chunk in _sentence_stream(
                _tokens_gemini(system_prompt, user_prompt), price, location, "gemini"
            ):
                yield chunk
            return
        except Exception as exc:
            logger.error("[LLM] Gemini başarısız: %s", exc)

    logger.error("[LLM] Tüm providerlar başarısız | title=%r", title[:60])
    yield "__LLM_ERROR__"
