"""
Auto-Mod çekirdeği — Zero-Latency içerik filtreleme.

Genel kullanım:
    from app.core.auto_mod import analyze_text, normalize_text

    if analyze_text(text, language='tr'):
        # mesajı gizle / shadowban uygula

Dil sözlükleri app/core/bad_words/{lang}.json dosyalarından yüklenir.
Tüm diller aynı anda kontrol edilmek istenirse analyze_text_all() kullanılır.

Dayanıklılık: JSON dosyası yoksa ilgili dil sessizce atlanır (filtre hiç
çalışmaz değil, sadece eksik dil listeye katkı sağlamaz).
"""

from __future__ import annotations

import json
import os
import re
from functools import lru_cache

from app.core.logger import get_logger

logger = get_logger(__name__)

_BAD_WORDS_DIR = os.path.join(os.path.dirname(__file__), "bad_words")
_SUPPORTED_LANGS = ("tr", "en", "ar")

# Normalize'da temizlenecek karakter sınıfı: noktalama, boşluk ve ayırıcılar
_STRIP_RE = re.compile(r"[\s\.,\-_\*\+|\\/:;'\"!?@#$%^&()\[\]{}<>~`​­]+")


# ── Metin normalleştirme ──────────────────────────────────────────────────────

def normalize_text(text: str) -> str:
    """
    Metni küçük harfe çevirip noktalama, boşluk ve ayırıcı karakterleri kaldırır.

    Örnek:
        "S.i.k.t.i.r  git!" → "siktirgo"  (substring eşleşmesi için)
    """
    text = text.lower()
    text = _STRIP_RE.sub("", text)
    return text


# ── Sözlük yükleme (uygulama ömrü boyunca önbelleklenir) ────────────────────

@lru_cache(maxsize=8)
def _load_bad_words(language: str) -> frozenset[str]:
    """
    Verilen dil için bad_words/{lang}.json'ı yükler ve normalize eder.
    Dosya yoksa boş küme döner; bir sonraki çağrıda tekrar okunmaz.
    """
    path = os.path.join(_BAD_WORDS_DIR, f"{language}.json")
    try:
        with open(path, encoding="utf-8") as f:
            words: list[str] = json.load(f)
        normalized = frozenset(normalize_text(w) for w in words if w.strip())
        logger.info("[AUTO_MOD] %s: %d kelime yüklendi", language, len(normalized))
        return normalized
    except FileNotFoundError:
        logger.warning("[AUTO_MOD] Sözlük bulunamadı: %s", path)
        return frozenset()
    except Exception as exc:
        logger.error("[AUTO_MOD] Sözlük yüklenemedi (%s): %s", language, exc)
        return frozenset()


# ── Analiz fonksiyonları ──────────────────────────────────────────────────────

def analyze_text(text: str, language: str = "tr") -> bool:
    """
    Metni normalize edip belirtilen dil sözlüğünde substring eşleşmesi arar.

    Args:
        text:     Kontrol edilecek ham metin.
        language: Dil kodu — 'tr', 'en', 'ar'. Bilinmiyorsa 'tr' kullanılır.

    Returns:
        True  → yasaklı kelime bulundu (mesaj gizlenmeli).
        False → temiz veya sözlük boş.
    """
    normalized = normalize_text(text)
    if not normalized:
        return False
    words = _load_bad_words(language)
    return any(word in normalized for word in words)


def analyze_text_all(text: str) -> bool:
    """
    Tüm desteklenen dillerde (tr, en, ar) içerik kontrolü yapar.
    Herhangi bir dilde eşleşme bulunursa True döner.
    Çok dilli kullanıcı tabanı için tercih edilen yol.
    """
    normalized = normalize_text(text)
    if not normalized:
        return False
    return any(
        any(word in normalized for word in _load_bad_words(lang))
        for lang in _SUPPORTED_LANGS
    )


# ── Geriye dönük uyumluluk — eski kod auto_mod.contains_profanity() kullanıyor ──

class _LegacyAutoMod:
    """
    Eski ChatService entegrasyonu için shim.
    Yeni kod analyze_text() veya analyze_text_all() kullanmalı.
    """

    def contains_profanity(self, text: str) -> bool:
        return analyze_text_all(text)


auto_mod = _LegacyAutoMod()
