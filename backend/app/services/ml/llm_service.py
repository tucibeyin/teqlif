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
from app.services.ml.llm_templates import ListingTemplates

logger = logging.getLogger(__name__)

# ── Sağlayıcı ayarları ────────────────────────────────────────────────────────
GROQ_API_URL      = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL        = "llama-3.3-70b-versatile"
_GROQ_DAILY_LIMIT = 14_000

GEMINI_API_URL    = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:streamGenerateContent"
_GEMINI_DAILY_LIMIT = 1_000  # günlük güvenli marj (free tier: 1500 req/gün)

# "kargo" çıkarıldı — sistem direktifi zaten kapsamakta; meşru bağlamda truncation riski taşır
_STOP_WORDS = ["TL", "₺", "elden"]

# ── Kategori normalizasyonu ───────────────────────────────────────────────────
_CAT_NORMALIZE: dict[str, str] = {
    "telefon": "electronics", "cep telefonu": "electronics",
    "bilgisayar": "electronics", "laptop": "electronics", "tablet": "electronics",
    "tv": "electronics", "televizyon": "electronics", "konsol": "electronics",
    "araba": "vehicles", "otomobil": "vehicles",
    "motor": "vehicles", "motosiklet": "vehicles",
    "daire": "real_estate", "konut": "real_estate", "işyeri": "real_estate",
    "kıyafet": "fashion", "elbise": "fashion", "ayakkabı": "fashion", "çanta": "fashion",
    "mobilya": "home", "beyaz eşya": "home", "mutfak eşyası": "home",
    "roman": "books", "ders kitabı": "books", "dergi": "books",
    "bisiklet": "sports", "fitness": "sports",
}

# ── Ürün durumu etiketleri ────────────────────────────────────────────────────
_CONDITION_LABELS: dict[str, str] = {
    "new":       "Sıfır, kutusunda hiç açılmamış",
    "like_new":  "Az kullanılmış, adeta sıfır",
    "used":      "Kullanılmış, temiz",
    "damaged":   "Hasarlı veya arızalı",
}

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

# ── Yazım çeşitlendirme direktifleri ─────────────────────────────────────────
# Her request'te rastgele seçilir → aynı (kategori, kondisyon) için farklı yapılar
_PARA_DIRECTIVES: list[str] = [
    (
        "TAM OLARAK İKİ PARAGRAF yaz, aralarına boş satır bırak. "
        "1. paragraf: ürünün durumu ve özellikleri (2-3 cümle). "
        "2. paragraf: satış nedeni veya alıcıya kısa not (1-2 cümle)."
    ),
    (
        "TAM OLARAK ÜÇ PARAGRAF yaz, aralarına boş satır bırak. "
        "1. paragraf: ürünün fiziksel durumu (2 cümle). "
        "2. paragraf: öne çıkan bir özellik veya avantaj (1-2 cümle). "
        "3. paragraf: satış nedeni veya alıcıya not (1-2 cümle)."
    ),
    (
        "TAM OLARAK İKİ PARAGRAF yaz, aralarına boş satır bırak. "
        "1. paragraf: ürünün durumu ve dikkat çeken özellikleri (2-3 cümle). "
        "2. paragraf: satış nedeni ve fiyat mantığı (1-2 cümle)."
    ),
]

_FOCUS_DIRECTIVES: list[str] = [
    "Ürünün fiziksel durumunu somut detaylarla anlat.",
    "Alıcının aklındaki soruları önceden yanıtlayacak şekilde yaz.",
    "Dürüst ama ikna edici bir dil kullan.",
    "Kısa ve net yaz, gereksiz kelime kullanma.",
]

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
    # Alt kategorileri canonical forma çevir
    cat_raw = category.lower().strip()
    cat = _CAT_NORMALIZE.get(cat_raw, cat_raw)

    cond = condition or "used"
    cond_label = _CONDITION_LABELS.get(cond, "")

    ex1, ex2 = ListingTemplates.get_few_shot(cat, cond)
    combo_hint = ListingTemplates.get_combo_hint(cat, cond)

    # Her request'te farklı yapı ve odak → çeşitli çıktılar
    para_directive = random.choice(_PARA_DIRECTIVES)
    focus_directive = random.choice(_FOCUS_DIRECTIVES)

    system = (
        "Türkiye'de ikinci el ilan platformunda bireysel satıcısın. "
        "Sana ürün bilgisi verilecek, sen sadece ilan metnini yazacaksın.\n\n"
        "YAZIM KURALLARI:\n"
        "- Birinci tekil şahısla yaz: 'kullandım', 'satıyorum', 'aldım' gibi.\n"
        f"- {para_directive}\n"
        "- Başlıktaki ürün adını ve varsa marka veya modeli metninde doğal olarak kullan.\n"
        "- Fiyat ve teslimat bilgisi YAZMA.\n"
        "- Özür veya yapay açılış cümlesi ekleme, direkt yaz.\n"
        f"- {focus_directive}\n"
        "- Sade Türkçe, tırnak işareti kullanma.\n\n"
        "YAZI TARZI ÖRNEĞİ:\n"
        f"1. paragraf:\n{ex1}\n\n"
        f"Son paragraf:\n{ex2}"
    )

    user_lines = [
        "Şu ürün için ilan metni yaz:",
        f"Ürün: {title}",
        f"Durum: {cond_label}" if cond_label else "",
        "",
        "Bu tür ürünlerde genellikle şunlar konuşulur (ürününe uyanları kullan):",
        combo_hint,
    ]
    user = "\n".join(line for line in user_lines if line is not None)
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
        "temperature": 0.6,
        "max_tokens": 350,
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
            "temperature": 0.6,
            "maxOutputTokens": 350,
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
