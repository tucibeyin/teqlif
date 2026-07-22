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
    "Sen Türkçe ilan açıklaması yazan bir asistansın. "
    "KURAL: Yalnızca kullanıcının verdiği bilgileri kullan. "
    "Hiçbir özellik, teknik bilgi veya garanti UYDURMA. "
    "3 cümle yaz: (1) ürün adı ve durumu, (2) fiyat ve genel değerlendirme, (3) teslim bilgisi. "
    "Yalnızca Türkçe. Madde işareti yok. Hashtag yok."
)

# Tek örnek — kısa context için
_EXAMPLES = [
    {
        "user": (
            "Ürün: Nike Air Max 90\nKategori: Ayakkabı\nDurum: İkinci El\n"
            "Fiyat: 800 ₺\nKonum: Bursa\nAçıklama:"
        ),
        "assistant": (
            "Nike Air Max 90 spor ayakkabı ikinci el satışa çıkarılmıştır. "
            "800 ₺ fiyatıyla uygun bir seçenek arayanlar için değerlendirilebilir. "
            "Bursa içinde elden teslim yapılır."
        ),
    },
]

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

    parts = [f"Ürün: {title.strip()}", f"Kategori: {category.strip()}"]
    if condition:
        label = _CONDITION_LABELS.get(condition, condition)
        parts.append(f"Durum: {label}")
    if price and price > 0:
        parts.append(f"Fiyat: {int(price):,} ₺".replace(",", "."))
    if location:
        parts.append(f"Konum: {location.strip()}")

    user_message = "\n".join(parts) + "\nAçıklama:"

    messages = [{"role": "system", "content": _SYSTEM_PROMPT}]
    for ex in _EXAMPLES:
        messages.append({"role": "user", "content": ex["user"]})
        messages.append({"role": "assistant", "content": ex["assistant"]})
    messages.append({"role": "user", "content": user_message})

    try:
        output = model.create_chat_completion(
            messages=messages,
            max_tokens=120,
            temperature=0.2,
            top_p=0.9,
            repeat_penalty=1.15,
            stop=["\n\n", "Ürün:", "Kategori:", "4."],
        )
        text = output["choices"][0]["message"]["content"].strip()
        return text if text else None
    except Exception as exc:
        logger.error("[LLM] Üretim hatası: %s", exc)
        return None
