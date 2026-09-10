"""
Scale V1.2 — Özerk registry, non-streaming, dual-provider (Groq + Gemini).

Her node kendi registry'sini tutar:
  - Startup'ta Groq model listesi çekilir, Gemini 1-token probe ile test edilir
  - 24 saatte bir yenilenir (fire_and_forget loop)
  - 429 → retry-after süresince model Redis'te exhausted olarak işaretlenir
  - llm:last_success → bir sonraki istekte önce son başarılı model denenir
  - node1 ve node2 aynı Redis'i (WireGuard üzerinden) paylaşır → cross-node kota paylaşımı
  - Redis yoksa graceful degradation: stateless fallback

generate_listing_description() → (description: str, provider: str)
"""
import asyncio
import json
import logging
import random
import re
from dataclasses import dataclass
from typing import Optional

import httpx

from app.config import settings
from app.core.exceptions import AIServiceBusyException
from app.core.logger import fire_and_forget
from app.services.ml.llm_templates import ListingTemplates
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

# ── Provider endpoints ────────────────────────────────────────────────────────
GROQ_API_URL     = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODELS_URL  = "https://api.groq.com/openai/v1/models"
GEMINI_BASE_URL  = "https://generativelanguage.googleapis.com/v1beta"

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


# ── Redis shared state ────────────────────────────────────────────────────────
# node1 ve node2 aynı Groq API key'ini paylaşır; cross-node exhaustion+last_success
# node1 Redis'e yerel bağlanır; node2 WireGuard üzerinden bağlanır (redis://10.10.0.1:6379)
# Redis erişilemezse her fonksiyon sessizce fallback değer döner — servis çalışmaya devam eder

async def _redis_is_exhausted(model_id: str) -> bool:
    try:
        r = await get_redis()
        return await r.exists(f"llm:exhausted:{model_id}") > 0
    except Exception:
        return False   # Redis yoksa model atlanmaz, denenir


async def _redis_mark_exhausted(model_id: str, retry_after: float = 60.0) -> None:
    try:
        r = await get_redis()
        await r.setex(f"llm:exhausted:{model_id}", max(1, int(retry_after)), "1")
    except Exception as exc:
        logger.debug("[LLM] Redis exhausted mark hatası: %s", exc)


async def _redis_get_last_success() -> tuple[str, str] | None:
    try:
        r = await get_redis()
        val = await r.get("llm:last_success")
        if val:
            data = json.loads(val)
            return data["model_id"], data["provider"]
    except Exception:
        pass
    return None


async def _redis_set_last_success(model_id: str, provider: str) -> None:
    try:
        r = await get_redis()
        await r.setex(
            "llm:last_success",
            3600,
            json.dumps({"model_id": model_id, "provider": provider}),
        )
    except Exception as exc:
        logger.debug("[LLM] Redis last_success set hatası: %s", exc)


def _parse_retry_after(headers: dict) -> float:
    try:
        return float(headers.get("retry-after", 60))
    except Exception:
        return 60.0


# ── Registry ──────────────────────────────────────────────────────────────────
@dataclass
class _ModelEntry:
    model_id: str
    provider: str   # "groq" | "gemini"
    score: float    # yüksek = öncelikli


_registry: list[_ModelEntry] = []


def _score_groq(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    if "gpt" in name:         score += 1000
    elif "qwen" in name:      score += 800
    elif "compound" in name:  score += 400 if "mini" not in name else 200
    m = re.search(r'(\d+)b', name)
    if m:                     score += int(m.group(1))
    return score


def _score_gemini(model_id: str) -> float:
    name = model_id.lower()
    score = 0.0
    if "gemma" in name:           score += 100      # TPM kısıtlı — en sona
    elif "flash-lite" in name:    score += 500
    elif "flash" in name:         score += 400
    m = re.search(r'(\d+)[.\-](\d+)', name)
    if m:                         score += float(f"{m.group(1)}.{m.group(2)}") * 50
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
            _ModelEntry(model_id=m["id"], provider="groq", score=_score_groq(m["id"]))
            for m in resp.json().get("data", [])
            if m.get("id") and m.get("object") == "model"
        ]
        entries.sort(key=lambda e: e.score, reverse=True)
        logger.info("[LLM] Groq registry: %d model", len(entries))
        return entries
    except Exception as exc:
        logger.error("[LLM] Groq model listesi alınamadı: %s", exc)
        return []


async def _probe_gemini_model(model_id: str, sem: asyncio.Semaphore) -> bool:
    """
    True  → registry'e al (200 veya 429 = erişilebilir, kota dolmuş olabilir)
    False → çıkar (403 = IP kısıtlama, 404 = model yok, hata)
    """
    async with sem:
        payload = {
            "contents": [{"role": "user", "parts": [{"text": "hi"}]}],
            "generationConfig": {"maxOutputTokens": 1},
        }
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(
                    f"{GEMINI_BASE_URL}/models/{model_id}:generateContent",
                    params={"key": settings.gemini_api_key},
                    json=payload,
                )
            if resp.status_code in (200, 429):
                logger.debug("[LLM] Gemini probe %s → HTTP %d", model_id, resp.status_code)
                return True
            logger.debug("[LLM] Gemini probe %s → HTTP %d (çıkarılıyor)", model_id, resp.status_code)
            return False
        except Exception as exc:
            logger.debug("[LLM] Gemini probe %s hata: %s", model_id, exc)
            return False


async def _fetch_gemini_models() -> list[_ModelEntry]:
    if not settings.gemini_api_key:
        return []
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{GEMINI_BASE_URL}/models",
                params={"key": settings.gemini_api_key},
            )
        if resp.status_code != 200:
            logger.warning("[LLM] Gemini model listesi HTTP %d", resp.status_code)
            return []

        candidates: list[str] = []
        for m in resp.json().get("models", []):
            if "generateContent" not in m.get("supportedGenerationMethods", []):
                continue
            model_id = m.get("name", "").removeprefix("models/")
            if not model_id:
                continue
            # Embedding, vision-only, ses ve özel modelleri çıkar
            lower = model_id.lower()
            if any(x in lower for x in ("embedding", "aqa", "vision", "tts", "imagen")):
                continue
            candidates.append(model_id)

        if not candidates:
            logger.info("[LLM] Gemini: hiç aday model yok (IP kısıtlaması?)")
            return []

        # Paralel probe — max 4 eşzamanlı (startup maliyetini sınırlar)
        sem = asyncio.Semaphore(4)
        results = await asyncio.gather(*[_probe_gemini_model(m, sem) for m in candidates])

        entries = [
            _ModelEntry(model_id=m, provider="gemini", score=_score_gemini(m))
            for m, ok in zip(candidates, results) if ok
        ]
        entries.sort(key=lambda e: e.score, reverse=True)
        logger.info(
            "[LLM] Gemini registry: %d model (%d adaydan) — ilk: %s",
            len(entries), len(candidates),
            entries[0].model_id if entries else "—",
        )
        return entries
    except Exception as exc:
        logger.error("[LLM] Gemini model listesi alınamadı: %s", exc)
        return []


async def _refresh_registry() -> None:
    global _registry
    groq_entries = await _fetch_groq_models()
    gemini_entries = await _fetch_gemini_models()
    # Groq önce (primary), Gemini arkada (fallback — puan sıralı)
    _registry = groq_entries + gemini_entries
    logger.info("[LLM] Registry yenilendi: %d Groq + %d Gemini", len(groq_entries), len(gemini_entries))


async def _loop() -> None:
    while True:
        await asyncio.sleep(_REGISTRY_REFRESH_INTERVAL)
        try:
            await _refresh_registry()
        except Exception as exc:
            logger.warning("[LLM] Registry refresh başarısız: %s", exc)


async def start_registry_loop() -> None:
    """main.py / ai_proxy_main.py lifespan'dan await edilir."""
    try:
        await _refresh_registry()
    except Exception as exc:
        logger.error("[LLM] Başlangıç registry yüklenemedi: %s — boş registry ile devam", exc)
    fire_and_forget(_loop(), tag="llm_service.registry_loop")


# ── Non-streaming provider çağrıları ─────────────────────────────────────────
async def _get_text_groq(system: str, user: str, model_id: str) -> str:
    async with httpx.AsyncClient(timeout=45.0) as client:
        resp = await client.post(
            GROQ_API_URL,
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model_id,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                "temperature": 0.6,
                "max_tokens": 350,
                "stop": _STOP_WORDS,
                "stream": False,
            },
        )
    if resp.status_code != 200:
        raise RuntimeError(f"Groq {model_id} HTTP {resp.status_code}: {resp.text[:200]}")
    return resp.json()["choices"][0]["message"]["content"]


async def _get_text_gemini(system: str, user: str, model_id: str) -> str:
    async with httpx.AsyncClient(timeout=45.0) as client:
        resp = await client.post(
            f"{GEMINI_BASE_URL}/models/{model_id}:generateContent",
            params={"key": settings.gemini_api_key},
            json={
                "system_instruction": {"parts": [{"text": system}]},
                "contents": [{"role": "user", "parts": [{"text": user}]}],
                "generationConfig": {
                    "temperature": 0.6,
                    "maxOutputTokens": 350,
                    "stopSequences": _STOP_WORDS,
                },
            },
        )
    if resp.status_code != 200:
        raise RuntimeError(f"Gemini {model_id} HTTP {resp.status_code}: {resp.text[:200]}")
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
    Redis shared state ile model seçimi:
      1. llm:last_success varsa → önce o model denenir (sıcak yol, latency düşer)
      2. Exhausted değilse registry başından iterasyon
      3. 429 → llm:exhausted:{model_id} SET (TTL=retry-after) — node1+node2 paylaşır
      4. Başarıda → llm:last_success güncellenir (TTL=3600s)
    Redis yoksa: sessizce stateless davranır, servis kesintisiz çalışır.
    """
    system_prompt, user_prompt = _build_prompt(
        title, category, condition, subcategory, extra_fields, lang
    )

    async def _try_entry(entry: _ModelEntry) -> tuple[str, str] | None:
        if await _redis_is_exhausted(entry.model_id):
            return None
        try:
            logger.info("[LLM] Deneniyor: %s | title=%r", entry.model_id, title[:60])
            if entry.provider == "groq":
                raw = await _get_text_groq(system_prompt, user_prompt, entry.model_id)
            else:
                raw = await _get_text_gemini(system_prompt, user_prompt, entry.model_id)
            text = _postprocess(raw, price)
            logger.info("[LLM] Tamamlandı | %s | %d char", entry.model_id, len(text))
            await _redis_set_last_success(entry.model_id, entry.provider)
            return text, entry.provider
        except Exception as exc:
            retry_after = 60.0
            try:
                retry_after = _parse_retry_after(exc.response.headers)  # type: ignore[union-attr]
            except Exception:
                pass
            if getattr(getattr(exc, "response", None), "status_code", None) == 429:
                await _redis_mark_exhausted(entry.model_id, retry_after)
            logger.warning("[LLM] %s başarısız: %s", entry.model_id, exc)
            return None

    # 1. last_success — son başarılı modeli önce dene (aynı model çalışıyorsa hızlı yol)
    last = await _redis_get_last_success()
    if last:
        last_id, _ = last
        entry = next((e for e in _registry if e.model_id == last_id), None)
        if entry:
            result = await _try_entry(entry)
            if result:
                return result

    # 2. Registry başından tam iterasyon
    for entry in _registry:
        result = await _try_entry(entry)
        if result:
            return result

    logger.error("[LLM] Tüm providerlar başarısız | title=%r", title[:60])
    raise AIServiceBusyException()
