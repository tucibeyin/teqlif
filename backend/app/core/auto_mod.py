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

# ── better-profanity — Türkçe kelime listesiyle genişletilmiş İngilizce filtre ──

_bp_profanity = None
try:
    from better_profanity import profanity as _bpp
    _tr_path = os.path.join(os.path.dirname(__file__), "bad_words", "tr.json")
    if os.path.exists(_tr_path):
        with open(_tr_path, encoding="utf-8") as _f_bp:
            _bpp.add_censor_words(json.load(_f_bp))
    _bp_profanity = _bpp
except Exception:
    pass

_BAD_WORDS_DIR = os.path.join(os.path.dirname(__file__), "bad_words")
_SUPPORTED_LANGS = ("tr", "en", "ar")

# Normalize'da temizlenecek karakter sınıfı: noktalama ve ayırıcılar (BOŞLUKLAR HARİÇ)
_PUNCT_RE = re.compile(r"[\.,\-_\*\+|\\/:;'\"!?@#$%^&()\[\]{}<>~`​­]+")


# ── Metin normalleştirme ──────────────────────────────────────────────────────

def normalize_text(text: str) -> str:
    """
    Metni küçük harfe çevirip SADECE noktalama işaretlerini kaldırır.
    Boşluklar kelime ayrımı için yerinde kalır.
    """
    text = text.lower()
    text = _PUNCT_RE.sub("", text)
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
        # Sözlükteki kelimeleri boşluksuz yalın hale getiriyoruz
        normalized = frozenset(w.lower().replace(" ", "").strip() for w in words if w.strip())
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
    Metni normalize edip tam kelime (token) eşleşmesi veya bitişik eşleşme arar.
    False-positive önlemek için 'tam kelime' kullanılır.
    """
    normalized = normalize_text(text)
    if not normalized:
        return False
    
    tokens = set(normalized.split())
    stripped_all = normalized.replace(" ", "")
    bad_words = _load_bad_words(language)
    
    # 1. Normal boşluklu kelimelerden herhangi biri küfür mü?
    if not tokens.isdisjoint(bad_words):
        return True
    
    # 2. Kullanıcı kelimeyi aralara boşluk koyarak (s i k) mi yazmış?
    if stripped_all in bad_words:
        return True
        
    return False


def analyze_text_all(text: str) -> bool:
    """
    Tüm desteklenen dillerde içerik kontrolü yapar.
    Herhangi bir dilde eşleşme bulunursa True döner.
    """
    normalized = normalize_text(text)
    if not normalized:
        return False
        
    tokens = set(normalized.split())
    stripped_all = normalized.replace(" ", "")
    
    for lang in _SUPPORTED_LANGS:
        bad_words = _load_bad_words(lang)
        if not tokens.isdisjoint(bad_words):
            return True
        if stripped_all in bad_words:
            return True
            
    return False


# ── Geriye dönük uyumluluk — eski kod auto_mod.contains_profanity() kullanıyor ──

def analyze_listing_text(title: str, description: str = "") -> bool:
    """
    İlan başlığı + açıklamasını uygunsuz içerik için kontrol et.
    Hem JSON sözlüğü hem better-profanity kullanılır.
    """
    combined = f"{title} {description or ''}".strip()
    if not combined:
        return False
    if analyze_text_all(combined):
        return True
    if _bp_profanity is not None:
        try:
            return _bp_profanity.contains_profanity(combined)
        except Exception:
            pass
    return False


class _LegacyAutoMod:
    """
    Eski ChatService entegrasyonu için shim.
    Yeni kod analyze_text() veya analyze_text_all() kullanmalı.
    """

    def contains_profanity(self, text: str) -> bool:
        return analyze_text_all(text)


auto_mod = _LegacyAutoMod()
