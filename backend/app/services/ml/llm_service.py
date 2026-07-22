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
    "You are a Turkish marketplace listing assistant. "
    "Write a short, honest, clear Turkish product description based on the given details. "
    "Rules: 2-4 sentences, 50-100 words, Turkish only, no hashtags, no bullet points, "
    "no made-up features, no exaggeration. Output only the description text."
)

_FEW_SHOT_EXAMPLE = (
    "Başlık: iPhone 13 Pro 256GB\n"
    "Kategori: Telefon\n"
    "Durum: Az Kullanılmış\n"
    "Fiyat: 18.000 ₺\n"
    "Konum: Ankara\n\n"
    "Açıklama: "
)

_FEW_SHOT_ANSWER = (
    "iPhone 13 Pro 256GB, az kullanılmış durumda satılıktır. "
    "Ekranında veya kasasında çizik yoktur, tüm tuşlar sorunsuz çalışmaktadır. "
    "Orijinal kutusu ve şarj kablosu ile birlikte teslim edilir. "
    "Ankara içi elden teslim mümkündür, kargo seçeneği de mevcuttur."
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
                n_ctx=2048,
                n_threads=4,
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

    parts = [f"Ürün başlığı: {title.strip()}", f"Kategori: {category.strip()}"]
    if condition:
        label = _CONDITION_LABELS.get(condition, condition)
        parts.append(f"Durum: {label}")
    if price and price > 0:
        parts.append(f"Fiyat: {int(price):,} ₺".replace(",", "."))
    if location:
        parts.append(f"Konum: {location.strip()}")

    user_message = "\n".join(parts) + "\n\nAçıklama: "

    try:
        output = model.create_chat_completion(
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": _FEW_SHOT_EXAMPLE},
                {"role": "assistant", "content": _FEW_SHOT_ANSWER},
                {"role": "user", "content": user_message},
            ],
            max_tokens=200,
            temperature=0.4,
            top_p=0.85,
            repeat_penalty=1.15,
        )
        text = output["choices"][0]["message"]["content"].strip()
        return text if text else None
    except Exception as exc:
        logger.error("[LLM] Üretim hatası: %s", exc)
        return None
