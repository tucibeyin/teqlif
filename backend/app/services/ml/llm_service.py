"""
Groq (llama-3.3-70b) primary / Ollama (Qwen2.5:3b) fallback LLM Servisi

Provider seçimi:
  1. Groq   — API key var ve günlük kota dolmamışsa (14,000 req/gün)
  2. Ollama — Groq key yok, kota dolmuş veya hata

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
OLLAMA_API_URL    = "http://localhost:11434/api/generate"
OLLAMA_MODEL      = "qwen2.5:3b"
GROQ_API_URL      = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL        = "llama-3.3-70b-versatile"
_GROQ_DAILY_LIMIT = 14_000  # free tier: 14,400/gün, güvenli marjla

_STOP_WORDS = [
    "TL", " TL", "₺", "lira", " lira",
    "elden", "kargo", "Kargo",
    "Fiyat", "fiyat", "Ücret", "ücret",
]
# Groq max 4 stop word kabul eder
_GROQ_STOP_WORDS = ["TL", "₺", "elden", "kargo"]

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
_FEW_SHOT: dict[tuple[str, str], tuple[str, str]] = {
    ("elektronik", "new"): (
        "Hiç açmadım, kutusunda duruyor, tüm aksesuarları tam. Hediye almıştım ama ihtiyacım olmadı, alıcısına hayırlı olsun.",
        "3 yıl kullandım, ekranında hiç çizik yok, bataryası sağlıklı. Orijinal kutusu mevcut, ihtiyaçtan satılık.",
    ),
    ("elektronik", "like_new"): (
        "Çok az kullandım, ekranında hiç çizik yok, bataryası gayet sağlıklı. Kutusunu ve şarj adaptörünü sakladım. İhtiyaçtan satılık.",
        "Ekrana temperli cam yapıştırdım, kılıfla taşıdım, sıfır gibi duruyor. Almak isteyenler ulaşabilir.",
    ),
    ("elektronik", "used"): (
        "2 yıl kullandım, ekranda küçük çizikler var ama çalışması tam. Bataryası hâlâ iyi, masraf çıkarmaz.",
        "Eski telefon, genel olarak temiz kullandım. Ekranda hafif kullanım izleri var, fiyata yansıttım.",
    ),
    ("elektronik", "damaged"): (
        "Ekran kırık, kamera çalışıyor ama dokunmatik kısmen hassas değil. Hasarı olduğu gibi söyledim, parça olarak da değerlendirilebilir.",
        "Bataryası şişmiş, açılıyor ama uzun süre dayanmıyor. Fiyatı düşük tuttum, onarcak birine gider.",
    ),
    ("vasita", "new"): (
        "0 km, hiç binmedim, depolama amaçlı aldım. Tüm belgeleri ve garantisi mevcut.",
        "Sıfır kilometre, fabrika ayarlarında, anahtar teslim satıyorum.",
    ),
    ("vasita", "like_new"): (
        "2021 model, 15.000 km'de, motoru ve şanzımanı sorunsuz, kazasız. Bakımları zamanında yapıldı.",
        "Az kullanılmış, temiz bir araç. Kaporta hasarı yok, muayenesi yeni.",
    ),
    ("vasita", "used"): (
        "2018 model, 95.000 km'de, motor ve şanzıman sağlam. Bakım geçmişi bende mevcut, ihtiyaçtan satılık.",
        "Kullanılmış ama temiz araç. Küçük kaporta çizikleri var, fiyata yansıttım.",
    ),
    ("vasita", "damaged"): (
        "Kaporta hasarı var, motor çalışıyor fakat klima gaz istiyor. Her şeyi olduğu gibi söyledim, ciddi alıcı beklerim.",
        "Motor çalışıyor ama şanzımanda sorun var. Hasarını söyledim, fiyata yansıttım.",
    ),
    ("emlak", "new"): (
        "Sıfır daire, hiç oturulmadı, tapu hazır. İnşaat firmasından alındı, masrafsız teslim.",
        "Yeni bina, 2024 yapımı, asansörlü. Mutfak ve banyosu sıfır, hemen taşınılabilir.",
    ),
    ("emlak", "like_new"): (
        "3 yıllık bina, 2+1, 80 m². Temiz kullandık, hiç tadilat yapmadan taşınabilirsiniz. Krediye uygun.",
        "Az kullanılmış, iç mekanı temiz, masraf gerektirmiyor. Tapu bende mevcut.",
    ),
    ("emlak", "used"): (
        "Eski bina ama sağlam yapı, 3+1, 110 m². Mutfak yenilendi, banyo eski ama çalışıyor. Fiyata yansıttım.",
        "Satılık daire, tadilat istiyor ama fiyatı uygun. Tapu temiz, kredi kullanılabilir.",
    ),
    ("emlak", "damaged"): (
        "Depremden etkilenmiş, hasar tespit raporu var. Arsası değerli, üstü yıkılarak yeniden yapılabilir.",
        "Su basmış, zemin ve duvarlar rutubetli. Tadilat gerekiyor, fiyatı buna göre düşük tuttum.",
    ),
    ("giyim", "new"): (
        "Hiç giymeden satıyorum, etiketi üzerinde. Hediye almıştım ama bedenim uymadı.",
        "Sıfır, kutusunda duruyor. Beğendim ama bir daha giymeyeceğimi fark ettim.",
    ),
    ("giyim", "like_new"): (
        "1-2 kere giydim, marka ürün, tertemiz. Bedenim değişti, bu yüzden satıyorum.",
        "Çok az kullandım, yırtık veya leke yok. Tarz değişikliğinden satıyorum.",
    ),
    ("giyim", "used"): (
        "Temiz kullandım, yırtık yok ama hafif solma var. Fiyata yansıttım.",
        "Birkaç sezon giydim, genel olarak temiz. Küçük kullanım izleri var, fiyata göre ayarladım.",
    ),
    ("giyim", "damaged"): (
        "Küçük yırtık var, dikişle onarılabilir. Hasarını söyledim, fiyatı düşük tutuyorum.",
        "Leke var, temizleyemedim. Dürüstçe söyledim, fiyatı buna göre düşük.",
    ),
    ("ev", "new"): (
        "Sıfır, hiç kullanmadım. Taşınırken aldım ama o odaya sığmadı, kutusunda duruyor.",
        "Açılmamış paketinde, hasarsız, tüm parçaları tam.",
    ),
    ("ev", "like_new"): (
        "Çok az kullandım, çizik veya hasar yok, sıfır gibi. Taşınma nedeniyle satıyorum.",
        "1-2 kere kullandım, tertemiz, yeni gibi. Fazla olduğu için satıyorum.",
    ),
    ("ev", "used"): (
        "2 yıl kullandım, çalışması tam, küçük çizikler var. Taşınma nedeniyle satıyorum.",
        "Kullanılmış ama sağlam, masraf çıkarmaz. Fiyata yansıttım.",
    ),
    ("ev", "damaged"): (
        "Bir köşesi kırık ama işlevselliği etkilemiyor. Hasarını söyledim, fiyatı uygun.",
        "Çalışıyor ama yüzeyde hasar var. Fiyatı düşük tuttum.",
    ),
    ("spor", "new"): (
        "Hiç kullanmadım, kutusunda duruyor. Spor yapmaya başlayamamıştım, ihtiyaç fazlası.",
        "Sıfır, tüm aksesuarları tam. Hediye almıştım, aynısı var, satıyorum.",
    ),
    ("spor", "like_new"): (
        "Çok az kullandım, hasar yok, aksesuarları tam. Sporu bıraktığım için satıyorum.",
        "Ayda birkaç kez kullandım, neredeyse sıfır gibi. İhtiyaçtan satılık.",
    ),
    ("spor", "used"): (
        "Düzenli kullandım, işlevsel ama kullanım izleri var. Masraf çıkarmaz.",
        "Temiz kullandım, eskimiş ama sağlam çalışıyor.",
    ),
    ("spor", "damaged"): (
        "Bir parçası kırık ama tamir edilebilir. Hasarını söyledim, fiyatı buna göre düşük.",
        "Çalışıyor ama hasar var. Kendisi onaracak birine gider.",
    ),
    ("kitap", "new"): (
        "Hiç okunmadı, yeni gibi. Almıştım ama okuyamadım.",
        "Sıfır kitap, kapağı ve sayfaları tertemiz.",
    ),
    ("kitap", "like_new"): (
        "Bir kere okundu, kapağı ve sayfaları tertemiz. Rafta yer kaplıyor.",
        "Az okunmuş, not yok, çizik yok. İyi okumalar.",
    ),
    ("kitap", "used"): (
        "Okunmuş, birkaç sayfada altı çizili notlar var. Kapağı sağlam.",
        "Eski kitap, sayfaları sararmış ama okunabilir durumda.",
    ),
    ("kitap", "damaged"): (
        "Kapağı yırtılmış ama sayfalar tam. Fiyatı düşük tutuyorum.",
        "Su görmüş, sayfalar dalgalı ama okunuyor. Hasarını söyledim.",
    ),
    ("diger", "new"): (
        "Sıfır, hiç kullanmadım. İhtiyaç fazlası, alıcısına hayırlı olsun.",
        "Kullanılmamış, tüm parçaları tam, tertemiz.",
    ),
    ("diger", "like_new"): (
        "Az kullandım, hasarsız ve temiz. İhtiyacım kalmadığı için satıyorum.",
        "Neredeyse sıfır gibi, iyi durumda. Alıcısına hayırlı olsun.",
    ),
    ("diger", "used"): (
        "Temiz kullandım, iyi durumda, masraf çıkarmaz. İhtiyaçtan satılık.",
        "Kullanılmış ama sağlam. Alıcısına hayırlı olsun.",
    ),
    ("diger", "damaged"): (
        "Hasarlı, olduğu gibi söyledim. Fiyatı buna göre düşük tuttum.",
        "Arızalı, onarcak birine gider. Dürüstçe belirtiyorum.",
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
        "Sana ürün bilgisi verilecek, sen sadece kısa ilan metnini yazacaksın.\n"
        "- Birinci tekil şahısla yaz: 'kullandım', 'satıyorum', 'aldım' gibi.\n"
        "- Fiyat ve teslimat bilgisi YAZMA.\n"
        "- Özür veya açıklama cümlesi ekleme, direkt metni yaz.\n"
        "- 3-4 cümle, sade Türkçe.\n\n"
        f"Örnek:\n\"{ex1}\"\n\n"
        f"Örnek:\n\"{ex2}\""
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
async def _groq_quota_ok() -> bool:
    """True dönerse Groq'u kullan; Redis hatasında da True (Groq'u dene)."""
    try:
        redis = await get_redis()
        key = f"groq:calls:{date.today().isoformat()}"
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, 86_400)
        if count > _GROQ_DAILY_LIMIT:
            logger.warning("[LLM] Groq günlük kota doldu (%d req), Ollama'ya geçiliyor", count)
            return False
        return True
    except Exception as exc:
        logger.error("[LLM] Redis kota kontrolü başarısız: %s — Groq deneniyor", exc)
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
        "max_tokens": 150,
        "stop": _GROQ_STOP_WORDS,
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


async def _tokens_ollama(system: str, user: str) -> AsyncGenerator[str, None]:
    payload = {
        "model": OLLAMA_MODEL,
        "system": system,
        "prompt": user,
        "stream": True,
        "keep_alive": "10m",
        "options": {
            "temperature": 0.5,
            "top_p": 0.85,
            "num_predict": 150,
            "num_thread": 4,
            "stop": _STOP_WORDS,
        },
    }
    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST", OLLAMA_API_URL, json=payload, timeout=120.0
        ) as resp:
            if resp.status_code != 200:
                raise RuntimeError(f"Ollama HTTP {resp.status_code}")
            async for line in resp.aiter_lines():
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    token = data.get("response", "")
                    if token:
                        yield token
                except json.JSONDecodeError:
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
        yield " "
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
    Groq primary → Ollama fallback.
    Sentence-boundary streaming: her cümleyi nokta/ünlem gelince flush eder.
    """
    system_prompt, user_prompt = _build_prompt(title, category, condition)

    # ── Groq path ─────────────────────────────────────────────────────────────
    if settings.groq_api_key and await _groq_quota_ok():
        try:
            logger.info("[LLM] Groq | title=%r", title[:60])
            async for chunk in _sentence_stream(
                _tokens_groq(system_prompt, user_prompt), price, location, "groq"
            ):
                yield chunk
            return
        except Exception as exc:
            logger.error("[LLM] Groq başarısız, Ollama'ya fallback: %s", exc)

    # ── Ollama fallback ────────────────────────────────────────────────────────
    try:
        logger.info("[LLM] Ollama | title=%r", title[:60])
        async for chunk in _sentence_stream(
            _tokens_ollama(system_prompt, user_prompt), price, location, "ollama"
        ):
            yield chunk
    except Exception as exc:
        logger.error("[LLM] Ollama hatası: %s", exc)
        yield "__LLM_ERROR__"
