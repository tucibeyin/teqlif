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
    """Açıklama üretme özelliği her zaman aktif (şablon tabanlı)."""
    return True


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


def generate_listing_description(
    title: str,
    category: str,
    condition: Optional[str] = None,
    price: Optional[float] = None,
    location: Optional[str] = None,
) -> Optional[str]:
    """İlan bilgilerinden şablon tabanlı Türkçe açıklama üretir."""
    import hashlib

    title = title.strip()
    category = category.strip()
    cond = condition or "used"

    # Sentence 1: title + condition verb
    verb = _CONDITION_VERBS.get(cond, "satışa sunulmuştur")
    s1 = f"{title}, {verb}."

    # Sentence 2: price + audience or generic
    adj = _CONDITION_ADJECTIVES.get(cond, "ilgilenenler")
    if price and price > 0:
        price_str = f"{int(price):,}".replace(",", ".")
        s2 = f"{price_str} ₺ fiyatıyla {category} kategorisinde {adj} için değerlendirilebilir."
    else:
        s2 = f"{category.capitalize()} kategorisinde {adj} için değerlendirilebilir."

    # Sentence 3: location or generic delivery
    if location:
        loc = location.strip()
        # Deterministic rotation based on title hash so same listing always gets same phrase
        idx = int(hashlib.md5(title.encode()).hexdigest(), 16) % len(_DELIVERY_PHRASES)
        s3 = _DELIVERY_PHRASES[idx].format(location=loc)
    else:
        s3 = "Kargo veya elden teslim seçenekleri hakkında iletişime geçilebilir."

    return f"{s1} {s2} {s3}"
