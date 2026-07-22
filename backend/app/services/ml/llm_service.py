"""
Qwen2.5-1.5B-Instruct LLM Servisi (CPU inference via llama-cpp-python)

Akış:
  1. _generate_template()  — anlık, her zaman doğru Türkçe şablon
  2. _enrich_with_llm()   — şablonu LLM'e paraphrase ettirir (model varsa)
  3. generate_listing_description() — LLM başarılıysa zenginleştirilmiş,
                                      başarısızsa şablon döner

Model: Qwen/Qwen2.5-1.5B-Instruct (Q4_K_M GGUF ~1 GB)
Çıkarım: llama-cpp-python (CPU, 5 thread)
Beklenen süre: ~8-12 sn

Depolama: .model_cache/qwen2.5-1.5b-instruct-q4_k_m.gguf
İndirme:
    huggingface-cli download Qwen/Qwen2.5-1.5B-Instruct-GGUF \\
        qwen2.5-1.5b-instruct-q4_k_m.gguf \\
        --local-dir /var/www/teqlif.com/backend/.model_cache
"""
from __future__ import annotations

import hashlib
import logging
import threading
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "qwen2.5-1.5b-instruct-q4_k_m.gguf"

_model = None
_model_lock = threading.Lock()

_CONDITION_VERBS = {
    "new": "sıfır olup kutusunda satışa sunulmuştur",
    "like_new": "az kullanılmış olarak satışa çıkarılmıştır",
    "used": "ikinci el olarak satışa sunulmuştur",
    "damaged": "hasarlı/onarım gerektiren durumda satışa çıkarılmıştır",
}

_CONDITION_ADJECTIVES = {
    "new": "sıfır ürün arayanlar",
    "like_new": "az kullanılmış ürün arayanlar",
    "used": "uygun fiyatlı ikinci el arayanlar",
    "damaged": "kendin onar veya parça arayanlar",
}

_DELIVERY_PHRASES = [
    "{location}'da elden teslim yapılmaktadır.",
    "{location} içinde elden teslim tercih edilmektedir.",
    "{location}'dan elden teslim sağlanmaktadır.",
]


def _load_model():
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        if not _MODEL_PATH.exists():
            logger.warning("[LLM] Model dosyası bulunamadı: %s", _MODEL_PATH)
            return None
        try:
            from llama_cpp import Llama
            logger.info("[LLM] Phi-3.5-mini yükleniyor: %s", _MODEL_PATH)
            _model = Llama(
                model_path=str(_MODEL_PATH),
                n_ctx=512,
                n_threads=5,
                n_gpu_layers=0,
                verbose=False,
            )
            logger.info("[LLM] Model yüklendi.")
        except Exception as exc:
            logger.error("[LLM] Model yüklenemedi: %s", exc)
            return None
    return _model


def is_available() -> bool:
    """Açıklama üretme her zaman aktif — LLM yoksa şablon devreye girer."""
    return True


def _generate_template(
    title: str,
    category: str,
    condition: Optional[str],
    price: Optional[float],
    location: Optional[str],
) -> str:
    """Anlık, deterministik, hallucination-free şablon."""
    cond = condition or "used"
    verb = _CONDITION_VERBS.get(cond, "satışa sunulmuştur")
    adj = _CONDITION_ADJECTIVES.get(cond, "ilgilenenler")

    s1 = f"{title}, {verb}."

    if price and price > 0:
        price_str = f"{int(price):,}".replace(",", ".")
        s2 = f"{price_str} ₺ fiyatıyla {category} kategorisinde {adj} için değerlendirilebilir."
    else:
        s2 = f"{category.capitalize()} kategorisinde {adj} için değerlendirilebilir."

    if location:
        idx = int(hashlib.md5(title.encode()).hexdigest(), 16) % len(_DELIVERY_PHRASES)
        s3 = _DELIVERY_PHRASES[idx].format(location=location)
    else:
        s3 = "Kargo veya elden teslim seçenekleri hakkında iletişime geçilebilir."

    return f"{s1} {s2} {s3}"


def _enrich_with_llm(template: str, title: str) -> Optional[str]:
    """
    Şablonu LLM'e paraphrase ettirir.

    Model görevi: yeni bilgi üretme → sadece mevcut cümleleri akıcılaştır.
    Pre-fill ile başlangıç sabitlenir — model başlığı uyduramaaz.
    """
    model = _load_model()
    if model is None:
        return None

    # Qwen2.5 chat template + pre-fill
    prompt = (
        "<|im_start|>system\n"
        "Türkçe ilan açıklamasını daha akıcı ve doğal bir dille yeniden yaz. "
        "Hiçbir bilgi EKLEME veya ÇIKARMA — yalnızca ifadeyi güzelleştir.<|im_end|>\n"
        "<|im_start|>user\n"
        f"Orijinal: {template}\n"
        "Yeniden yaz:<|im_end|>\n"
        "<|im_start|>assistant\n"
        f"{title},"
    )

    try:
        output = model.create_completion(
            prompt=prompt,
            max_tokens=120,
            temperature=0.7,
            top_p=0.9,
            repeat_penalty=1.1,
            stop=["<|im_end|>", "<|im_start|>", "\n\n", "Orijinal:"],
        )
        completion = output["choices"][0]["text"].strip()
        enriched = f"{title},{completion}"

        # Son tam cümleye kırp
        for sep in (".", "!", "?"):
            idx = enriched.rfind(sep)
            if idx != -1 and idx > len(enriched) // 3:
                enriched = enriched[: idx + 1]
                break

        # Kalite filtresi: şablonun %60'ından kısa → bozuk üretim
        if len(enriched) < len(template) * 0.6:
            logger.debug("[LLM] Çıktı çok kısa, şablona fallback | len=%d", len(enriched))
            return None

        logger.info("[LLM] Zenginleştirme başarılı | %d → %d karakter", len(template), len(enriched))
        return enriched

    except Exception as exc:
        logger.error("[LLM] Zenginleştirme hatası: %s", exc)
        return None


def generate_listing_description(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> str:
    """
    İlan bilgilerinden Türkçe açıklama üretir.

    Önce şablon üretir (anlık, güvenli), ardından LLM ile zenginleştirmeyi dener.
    LLM başarısız veya yoksa şablon döner.
    """
    title = title.strip()
    category = category.strip()
    if location:
        location = location.strip()

    template = _generate_template(title, category, condition, price, location)

    if not _MODEL_PATH.exists():
        return template

    enriched = _enrich_with_llm(template, title)
    return enriched if enriched else template
