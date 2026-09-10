"""
Scale V1.2 — Özerk registry, non-streaming, dual-provider (Groq + Gemini).

Her node kendi registry'sini tutar:
  - Startup'ta Groq model listesi çekilir, Gemini 1-token probe ile test edilir
  - 24 saatte bir yenilenir (fire_and_forget loop)
  - 429 → retry-after süresince model in-memory olarak atlanır
  - Tüm modeller tükenirse AIServiceBusyException fırlatılır

generate_listing_description() → (description: str, provider: str)
"""
import asyncio
import json
import logging
import random
import re
import time
from dataclasses import dataclass
from typing import Optional

import httpx

from app.config import settings
from app.core.exceptions import AIServiceBusyException
from app.core.logger import fire_and_forget
from app.services.ml.llm_templates import ListingTemplates

logger = logging.getLogger(__name__)

# ── Provider endpoints ────────────────────────────────────────────────────────
GROQ_API_URL    = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODELS_URL = "https://api.groq.com/openai/v1/models"
GEMINI_URL      = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-2.0-flash-lite:generateContent"
)

_REGISTRY_REFRESH_INTERVAL = 86_400  # 24 saat

# ── Stop words (Groq hard limit: max 4) ──────────────────────────────────────
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

# ── Fiyat şablonları ──────────────────────────────────────────────────────────
_PRICE_ONLY: list[str] = [
    "{price} TL'ye satıyorum, pazarlık payı var.",
    "Fiyatım {price} TL, ciddi alıcı beklerim.",
    "{price} TL istiyorum, fiyat konuşulur.",
    "{price} TL, sabit fiyat.",
]

# ── Yazım çeşitlendirme direktifleri ─────────────────────────────────────────
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

_LANG_DIRECTIVE: dict[str, str] = {
    "tr": "ÇIKTI DİLİ: Türkçe. Açıklamayı Türkçe yaz.",
    "en": "OUTPUT LANGUAGE: English. Write the entire listing description in English.",
    "ar": "لغة الإخراج: العربية. اكتب وصف الإعلان بالكامل باللغة العربية.",
    "ru": "ЯЗЫК ВЫВОДА: Русский. Напиши всё описание объявления на русском языке.",
}

# YZ açılış kalıpları — ilk cümlede tespit edilirse temizlenir
_RE_AI_OPENER = re.compile(
    r"^(üzgünüm\b|tabii\s+ki\b|elbette\b|merhaba\b|size\s+yardım|ürününüz\b|"
    r"aşağıda\b|işte\s+ilan|evet[,\s]|anladım\b|ilan\s+metni\b)",
    re.IGNORECASE,
)

_SENTENCE_END = frozenset({".", "!", "?"})


# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────
def _build_suffix(price: Optional[float]) -> str:
    if price and price > 0:
        p = f"{int(price):,}".replace(",", ".")
        return random.choice(_PRICE_ONLY).format(price=p)
    return ""


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


def _postprocess(raw: str, price: Optional[float]) -> str:
    """YZ açılış cümlesi temizleme + fiyat suffix ekleme."""
    lines = raw.strip().split("\n")
    if lines:
        cleaned = _RE_AI_OPENER.sub("", lines[0]).lstrip()
        if cleaned != lines[0].lstrip():
            logger.warning("[LLM] YZ açılış cümlesi silindi")
        lines[0] = cleaned
    text = "\n".join(lines).strip()
    suffix = _build_suffix(price)
    if suffix:
        text = text + "\n\n" + suffix
    return text


# ── Rate limit hatası ─────────────────────────────────────────────────────────
class _RateLimitError(Exception):
    def __init__(self, retry_after: float = 60.0):
        self.retry_after = retry_after


# ── In-memory exhaustion tracking ────────────────────────────────────────────
_exhausted: dict[str, float] = {}  # model_id → reset_timestamp


def _is_exhausted(model_id: str) -> bool:
    return time.monotonic() < _exhausted.get(model_id, 0.0)


def _mark_exhausted(model_id: str, retry_after: float) -> None:
    _exhausted[model_id] = time.monotonic() + retry_after
    logger.warning("[LLM] %s exhausted %.0fs süreyle atlanıyor", model_id, retry_after)


# ── Registry ──────────────────────────────────────────────────────────────────
@dataclass
class _ModelEntry:
    model_id: str
    provider: str   # "groq" | "gemini"
    score: float    # yüksek = öncelikli


_registry: list[_ModelEntry] = []


def _score_groq_model(model_info: dict) -> float:
    mid = model_info.get("id", "")
    ctx = model_info.get("context_window", 0)
    score = ctx / 1_000.0
    if any(x in mid for x in ("70b", "72b", "90b")):
        score += 50
    elif any(x in mid for x in ("27b", "32b")):
        score += 30
    elif any(x in mid for x in ("8b", "9b")):
        score += 10
    return score


async def _fetch_groq_models() -> list[_ModelEntry]:
    if not settings.groq_api_key:
        return []
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                GROQ_MODELS_URL,
                headers={"Authorization": f"Bearer {settings.groq_api_key}"},
            )
        if resp.status_code != 200:
            logger.warning("[LLM] Groq models API HTTP %d", resp.status_code)
            return []
        entries = [
            _ModelEntry(
                model_id=m["id"],
                provider="groq",
                score=_score_groq_model(m),
            )
            for m in resp.json().get("data", [])
            if m.get("id") and m.get("object") == "model"
        ]
        entries.sort(key=lambda e: e.score, reverse=True)
        logger.info("[LLM] Groq registry: %d model", len(entries))
        return entries
    except Exception as exc:
        logger.error("[LLM] Groq model listesi alınamadı: %s", exc)
        return []


async def _probe_gemini() -> Optional[_ModelEntry]:
    if not settings.gemini_api_key:
        return None
    payload = {
        "contents": [{"role": "user", "parts": [{"text": "hi"}]}],
        "generationConfig": {"maxOutputTokens": 1},
    }
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                GEMINI_URL,
                params={"key": settings.gemini_api_key},
                json=payload,
            )
        if resp.status_code == 200:
            logger.info("[LLM] Gemini probe OK — available")
            return _ModelEntry(model_id="gemini-2.0-flash-lite", provider="gemini", score=5.0)
        elif resp.status_code == 429:
            logger.warning("[LLM] Gemini probe 429 — kota doldu")
            return None
        else:
            # 403 = IP kısıtlaması (EU node), 400 = geçersiz key
            logger.warning("[LLM] Gemini probe HTTP %d — atlanıyor", resp.status_code)
            return None
    except Exception as exc:
        logger.error("[LLM] Gemini probe hatası: %s", exc)
        return None


async def _refresh_registry() -> None:
    global _registry
    groq_entries = await _fetch_groq_models()
    gemini_entry = await _probe_gemini()
    new_registry = groq_entries[:]
    if gemini_entry:
        new_registry.append(gemini_entry)
    _registry = new_registry
    logger.info("[LLM] Registry yenilendi: %d model", len(_registry))


async def _loop() -> None:
    while True:
        await asyncio.sleep(_REGISTRY_REFRESH_INTERVAL)
        try:
            await _refresh_registry()
        except Exception as exc:
            logger.warning("[LLM] Registry refresh başarısız: %s", exc)


async def start_registry_loop() -> None:
    """main.py lifespan'dan await edilir: registry'yi başlatır ve 24h refresh loop'u ateşler."""
    try:
        await _refresh_registry()
    except Exception as exc:
        logger.error("[LLM] Başlangıç registry yüklenemedi: %s — boş registry ile devam", exc)
    fire_and_forget(_loop(), tag="llm_service.registry_loop")


# ── Non-streaming provider çağrıları ─────────────────────────────────────────
async def _get_text_groq(system: str, user: str, model: str) -> str:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.6,
        "max_tokens": 350,
        "stop": _STOP_WORDS,
        "stream": False,
    }
    async with httpx.AsyncClient(timeout=45.0) as client:
        resp = await client.post(
            GROQ_API_URL,
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
    if resp.status_code == 429:
        retry_after = float(resp.headers.get("retry-after", "60"))
        raise _RateLimitError(retry_after)
    if resp.status_code != 200:
        raise RuntimeError(f"Groq HTTP {resp.status_code}: {resp.text[:200]}")
    return resp.json()["choices"][0]["message"]["content"]


async def _get_text_gemini(system: str, user: str) -> str:
    payload = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {
            "temperature": 0.6,
            "maxOutputTokens": 350,
            "stopSequences": _STOP_WORDS,
        },
    }
    async with httpx.AsyncClient(timeout=45.0) as client:
        resp = await client.post(
            GEMINI_URL,
            params={"key": settings.gemini_api_key},
            json=payload,
        )
    if resp.status_code == 429:
        retry_after = float(resp.headers.get("retry-after", "60"))
        raise _RateLimitError(retry_after)
    if resp.status_code != 200:
        raise RuntimeError(f"Gemini HTTP {resp.status_code}: {resp.text[:200]}")
    data = resp.json()
    return (
        data.get("candidates", [{}])[0]
            .get("content", {})
            .get("parts", [{}])[0]
            .get("text", "")
    )


# ── Public API ────────────────────────────────────────────────────────────────
async def generate_listing_description(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    subcategory: Optional[str] = None,
    extra_fields: Optional[dict[str, str]] = None,
    lang: str = "tr",
) -> tuple[str, str]:
    """
    Tüm registry modellerini sırayla dener; (description, provider) döner.
    Tüm modeller exhausted/başarısız ise AIServiceBusyException fırlatır.
    """
    system_prompt, user_prompt = _build_prompt(
        title, category, condition, subcategory, extra_fields, lang
    )

    for entry in _registry:
        if _is_exhausted(entry.model_id):
            continue
        try:
            logger.info("[LLM] Deneniyor: %s | title=%r", entry.model_id, title[:60])
            if entry.provider == "groq":
                raw = await _get_text_groq(system_prompt, user_prompt, entry.model_id)
            else:
                raw = await _get_text_gemini(system_prompt, user_prompt)
            text = _postprocess(raw, price)
            logger.info("[LLM] Tamamlandı | %s | %d char", entry.model_id, len(text))
            return text, entry.provider
        except _RateLimitError as exc:
            _mark_exhausted(entry.model_id, exc.retry_after)
            continue
        except Exception as exc:
            logger.error("[LLM] %s başarısız: %s", entry.model_id, exc)
            continue

    logger.error("[LLM] Tüm providerlar başarısız | title=%r", title[:60])
    raise AIServiceBusyException()
