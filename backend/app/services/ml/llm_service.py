"""
Phi-3.5-mini-instruct LLM Servisi (CPU inference via llama-cpp-python)

Singleton model yüklemesi — ilk çağrıda disk'ten yüklenir (~5-10 sn),
sonraki çağrılar anlık döner.

Model: microsoft/Phi-3.5-mini-instruct (Q4_K_M GGUF ~2.3 GB)
Çıkarım: llama-cpp-python (CPU, 4 thread)
Beklenen süre: 100-200 token için ~10-20 sn

Depolama: .model_cache/phi35-mini-instruct-q4_k_m.gguf
İndirme komutu (VPS'te bir kez):
    pip install llama-cpp-python
    huggingface-cli download bartowski/Phi-3.5-mini-instruct-GGUF \
        Phi-3.5-mini-instruct-Q4_K_M.gguf \
        --local-dir /var/www/teqlif.com/backend/.model_cache
    mv /var/www/teqlif.com/backend/.model_cache/Phi-3.5-mini-instruct-Q4_K_M.gguf \
       /var/www/teqlif.com/backend/.model_cache/phi35-mini-instruct-q4_k_m.gguf
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_MODEL_DIR = Path(__file__).resolve().parents[3] / ".model_cache"
_MODEL_PATH = _MODEL_DIR / "phi35-mini-instruct-q4_k_m.gguf"

_model = None
_model_lock = threading.Lock()

_SYSTEM_PROMPT = (
    "Sen Türkçe ikinci el ilan sitesi için açıklama yazan bir asistansın. "
    "Yalnızca verilen bilgileri kullan. Hiçbir şey uydurma."
)

_CONDITION_LABELS = {
    "new": "Sıfır",
    "like_new": "Az Kullanılmış",
    "used": "İkinci El",
    "damaged": "Hasarlı / Onarım Gerekiyor",
}


def _load_model():
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        if not _MODEL_PATH.exists():
            logger.warning(
                "[LLM] Model dosyası bulunamadı: %s — llm_service devre dışı", _MODEL_PATH
            )
            return None
        try:
            from llama_cpp import Llama
            logger.info("[LLM] Phi-3.5-mini yükleniyor: %s", _MODEL_PATH)
            _model = Llama(
                model_path=str(_MODEL_PATH),
                n_ctx=1024,
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
    """Model dosyası var mı ve yüklenebilir mi?"""
    return _MODEL_PATH.exists()


def generate_listing_description(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> Optional[str]:
    """
    İlan bilgilerinden Türkçe açıklama üretir.

    Dönüş: üretilen metin (str) veya None (model yoksa / hata varsa)
    """
    model = _load_model()
    if model is None:
        return None

    condition_label = _CONDITION_LABELS.get(condition or "", condition or "")

    # Phi-3.5-mini chat template — raw completion with pre-filled sentence start
    # Pre-filling forces the model to complete a sentence instead of generating from scratch
    title_stripped = title.strip()
    prompt = (
        f"<|system|>\n{_SYSTEM_PROMPT}<|end|>\n"
        f"<|user|>\n"
        f"Başlık: {title_stripped}\n"
        f"Kategori: {category.strip()}\n"
    )
    if condition_label:
        prompt += f"Durum: {condition_label}\n"
    if price and price > 0:
        prompt += f"Fiyat: {int(price):,} ₺\n".replace(",", ".")
    if location:
        prompt += f"Konum: {location.strip()}\n"
    prompt += f"<|end|>\n<|assistant|>\n{title_stripped},"

    try:
        output = model.create_completion(
            prompt=prompt,
            max_tokens=110,
            temperature=0.7,
            top_p=0.9,
            repeat_penalty=1.1,
            stop=["<|end|>", "<|user|>", "\n\n", "Başlık:"],
        )
        completion = output["choices"][0]["text"].strip()
        text = f"{title_stripped},{completion}"
        # Trim to last complete sentence
        for sep in (".", "!", "?"):
            idx = text.rfind(sep)
            if idx != -1 and idx > len(text) // 2:
                text = text[: idx + 1]
                break
        return text if len(text) > 20 else None
    except Exception as exc:
        logger.error("[LLM] Üretim hatası: %s", exc)
        return None
