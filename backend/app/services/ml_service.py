"""
ML Service — yerel embedding üretimi.

all-MiniLM-L6-v2 modeli ilk çağrıda bir kez yüklenir (Singleton).
Sonraki çağrılar önbellekten kullanır; model her request'te baştan yüklenmez.

Model: sentence-transformers/all-MiniLM-L6-v2
  - Çıktı: 384 boyutlu float32 vektörü
  - Boyut: ~90 MB
  - Hız: CPU'da ~10-50ms / cümle
  - Lisans: Apache 2.0, tamamen açık kaynak
"""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING

from app.core.logger import get_logger

if TYPE_CHECKING:
    from sentence_transformers import SentenceTransformer

logger = get_logger(__name__)

MODEL_NAME = "all-MiniLM-L6-v2"

_model: "SentenceTransformer | None" = None
_model_lock = threading.Lock()


def _get_model() -> "SentenceTransformer":
    """Thread-safe singleton model yükleyici."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from sentence_transformers import SentenceTransformer
                logger.info("[ML] %s yükleniyor…", MODEL_NAME)
                _model = SentenceTransformer(MODEL_NAME)
                logger.info("[ML] Model yüklendi.")
    return _model


def generate_embedding(text: str) -> list[float]:
    """
    Verilen metni 384 boyutlu vektöre çevirir.
    Boş/kısa metin için yine de geçerli bir vektör döner.
    """
    text = (text or "").strip()
    model = _get_model()
    vector = model.encode(text, normalize_embeddings=True)
    return vector.tolist()
