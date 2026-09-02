"""
Groq model chain primary / Gemini (gemini-3.1-flash-lite) fallback LLM Servisi

Provider seçimi (sırayla, kota bitince sonraki modele geçilir):
  1..N. Groq modelleri — _GROQ_MODELS listesinde tanımlı, her biri kendi RPD kotasıyla
  N+1.  Gemini         — tüm Groq kotaları dolmuş ya da key yok (1,000 req/gün güvenli marj)

Her path aynı sentence-boundary streaming + Python-side suffix kullanır.
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
GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"

# Groq free-plan model chain (öncelik sırasına göre; RPD = requests per day)
# Kota dolan model atlanır, bir sonraki denenir.
_GROQ_MODELS: list[tuple[str, int]] = [
    ("openai/gpt-oss-120b", 1_000),
    ("openai/gpt-oss-20b",  1_000),
    ("qwen/qwen3.6-27b",    1_000),
    ("qwen/qwen3.8-27b",    1_000),
    ("groq/compound",         250),
    ("groq/compound-mini",    250),
]

GEMINI_API_URL    = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:streamGenerateContent"
_GEMINI_DAILY_LIMIT = 1_000  # günlük güvenli marj (free tier: 1500 req/gün)

# Sentences containing these words are truncated from LLM output (price/delivery guard)
# Max 4 items — Groq hard limit. "kargo" intentionally omitted: truncation risk in
# legitimate contexts ("kargo geldi" etc.); system prompt directive handles it instead.
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
    "new":       "brand new, never opened",
    "like_new":  "lightly used, like new",
    "used":      "used, good condition",
    "damaged":   "damaged or defective",
}

# ── Fiyat şablonları (lokasyon suffix'i artık mobile tarafında ekleniyor) ─────
_PRICE_ONLY: list[str] = [
    "{price} TL'ye satıyorum, pazarlık payı var.",
    "Fiyatım {price} TL, ciddi alıcı beklerim.",
    "{price} TL istiyorum, fiyat konuşulur.",
    "{price} TL, sabit fiyat.",
]

# ── Yazım çeşitlendirme direktifleri ─────────────────────────────────────────
# Her request'te rastgele seçilir → aynı (kategori, kondisyon) için farklı yapılar
_PARA_DIRECTIVES: list[str] = [
    (
        "Write EXACTLY TWO PARAGRAPHS separated by a blank line. "
        "Paragraph 1: condition and features of the item (2-3 sentences). "
        "Paragraph 2: reason for selling or a short note to the buyer (1-2 sentences)."
    ),
    (
        "Write EXACTLY THREE PARAGRAPHS separated by blank lines. "
        "Paragraph 1: physical condition of the item (2 sentences). "
        "Paragraph 2: a standout feature or advantage (1-2 sentences). "
        "Paragraph 3: reason for selling or note to buyer (1-2 sentences)."
    ),
    (
        "Write EXACTLY TWO PARAGRAPHS separated by a blank line. "
        "Paragraph 1: condition and notable features (2-3 sentences). "
        "Paragraph 2: reason for selling and pricing rationale (1-2 sentences)."
    ),
]

_FOCUS_DIRECTIVES: list[str] = [
    "Describe the physical condition with concrete details.",
    "Anticipate what a buyer would want to know and address it directly.",
    "Use an honest but persuasive tone.",
    "Be concise and clear, avoid filler words.",
]

# YZ açılış kalıpları — ilk cümlede tespit edilirse atlanır
_RE_AI_OPENER = re.compile(
    r"^(üzgünüm\b|tabii\s+ki\b|elbette\b|merhaba\b|size\s+yardım|ürününüz\b|"
    r"aşağıda\b|işte\s+ilan|evet[,\s]|anladım\b|ilan\s+metni\b)",
    re.IGNORECASE,
)

_SENTENCE_END = frozenset({".", "!", "?"})


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────
def _build_suffix(price: Optional[float]) -> str:
    """Fiyat bilgisini suffix olarak döndürür. Lokasyon mobile tarafında eklenir."""
    if price and price > 0:
        p = f"{int(price):,}".replace(",", ".")
        return random.choice(_PRICE_ONLY).format(price=p)
    return ""


_LANG_DIRECTIVE: dict[str, str] = {
    "tr": "ÇIKTI DİLİ: Türkçe. Açıklamayı Türkçe yaz.",
    "en": "OUTPUT LANGUAGE: English. Write the entire listing description in English.",
    "ar": "لغة الإخراج: العربية. اكتب وصف الإعلان بالكامل باللغة العربية.",
    "ru": "ЯЗЫК ВЫВОДА: Русский. Напиши всё описание объявления на русском языке.",
}


def _build_prompt(
    title: str,
    category: str,
    condition: Optional[str],
    subcategory: Optional[str] = None,
    extra_fields: Optional[dict[str, str]] = None,
    lang: str = "tr",
) -> tuple[str, str]:
    cat_raw = category.lower().strip()
    cat = _CAT_NORMALIZE.get(cat_raw, cat_raw)

    cond = condition or "used"
    cond_label = _CONDITION_LABELS.get(cond, "")

    ex1, ex2 = ListingTemplates.get_few_shot(cat, cond)
    combo_hint = ListingTemplates.get_combo_hint(cat, cond)

    para_directive = random.choice(_PARA_DIRECTIVES)
    focus_directive = random.choice(_FOCUS_DIRECTIVES)
    lang_directive = _LANG_DIRECTIVE.get(lang, _LANG_DIRECTIVE["tr"])

    system = (
        "You are an individual seller on a second-hand marketplace in Turkey. "
        "You will be given product information and must write only the listing description text.\n\n"
        "RULES:\n"
        "- Write in first person: 'I used', 'I'm selling', 'I bought' (adapted to output language).\n"
        f"- {para_directive}\n"
        "- Naturally mention the product name and brand/model if present.\n"
        "- Do NOT include price or delivery information.\n"
        "- No apologetic or artificial opening sentences — start directly.\n"
        f"- {focus_directive}\n"
        "- No quotation marks.\n"
        f"- {lang_directive}\n\n"
        "STYLE EXAMPLES (format reference only — follow this structure, write in the output language):\n"
        f"Opening paragraph:\n{ex1}\n\n"
        f"Closing paragraph:\n{ex2}"
    )

    user_lines: list[str] = [
        "Write a listing description for this product:",
        f"Title: {title}",
        f"Subcategory: {subcategory}" if subcategory else "",
        f"Condition: {cond_label}" if cond_label else "",
    ]

    if extra_fields:
        field_lines = [
            f"  {key}: {val}"
            for key, val in extra_fields.items()
            if val and val.strip()
        ]
        if field_lines:
            user_lines.append("Product details:")
            user_lines.extend(field_lines)

    user_lines += [
        "",
        "Topics commonly discussed for this type of product (use what's relevant):",
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
async def _tokens_groq(system: str, user: str, model: str) -> AsyncGenerator[str, None]:
    headers = {
        "Authorization": f"Bearer {settings.groq_api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": model,
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
    provider: str,
) -> AsyncGenerator[str, None]:
    """Token stream'ini cümle sınırlarında flush eder, fiyat suffix'i ekler."""
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

    suffix = _build_suffix(price)
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
    subcategory: Optional[str] = None,
    extra_fields: Optional[dict[str, str]] = None,
    lang: str = "tr",
) -> AsyncGenerator[str, None]:
    """
    Groq model chain primary → Gemini fallback.
    Sentence-boundary streaming: her cümleyi nokta/ünlem gelince flush eder.
    Lokasyon bilgisi bu fonksiyona gelmez — mobile client tarafında eklenir.
    """
    system_prompt, user_prompt = _build_prompt(title, category, condition, subcategory, extra_fields, lang)

    # ── Groq model chain ──────────────────────────────────────────────────────
    if settings.groq_api_key:
        for model_id, daily_limit in _GROQ_MODELS:
            if not await _quota_ok(model_id, daily_limit):
                continue
            try:
                logger.info("[LLM] %s | title=%r", model_id, title[:60])
                yield "__META_groq__"
                async for chunk in _sentence_stream(
                    _tokens_groq(system_prompt, user_prompt, model_id), price, model_id
                ):
                    yield chunk
                return
            except Exception as exc:
                logger.error("[LLM] %s başarısız, sonraki model deneniyor: %s", model_id, exc)
                continue

    # ── Gemini fallback ────────────────────────────────────────────────────────
    if settings.gemini_api_key and await _quota_ok("gemini", _GEMINI_DAILY_LIMIT):
        try:
            logger.info("[LLM] Gemini | title=%r", title[:60])
            yield "__META_gemini__"
            async for chunk in _sentence_stream(
                _tokens_gemini(system_prompt, user_prompt), price, "gemini"
            ):
                yield chunk
            return
        except Exception as exc:
            logger.error("[LLM] Gemini başarısız: %s", exc)

    logger.error("[LLM] Tüm providerlar başarısız | title=%r", title[:60])
    yield "__LLM_ERROR__"
