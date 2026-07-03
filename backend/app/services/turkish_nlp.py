"""
Türkçe NLP yardımcıları — Snowball stemmer tabanlı

snowballstemmer (pure Python, Java gerektirmez) ile Türkçe kelime kökleri.
FTS sorgularında hem kök hem orijinal kelime kullanılarak geniş eşleşme sağlanır.

Örnek:
  "koşu ayakkabıları" → stems: ["koşu", "ayakkabı"]
  FTS query: "koşu:* & koşu:* & ayakkabı:* & ayakkabıları:*"
  (tekrarlar dedupe edilir)
"""
from __future__ import annotations

import re

_stemmer = None


def _get_stemmer():
    global _stemmer
    if _stemmer is not None:
        return _stemmer
    try:
        import snowballstemmer  # type: ignore
        _stemmer = snowballstemmer.stemmer("turkish")
        return _stemmer
    except Exception:
        return None


def stem_word(word: str) -> str:
    """Türkçe kelimeyi köklerine indir. Başarısızsa veya kök çok kısaysa orijinali döner."""
    stemmer = _get_stemmer()
    if stemmer is None:
        return word
    try:
        stemmed = stemmer.stemWord(word.lower())
        # Çok kısa kök (≤2 karakter) arama gürültüsü yaratır — orijinali kullan
        return stemmed if stemmed and len(stemmed) > 2 else word
    except Exception:
        return word


def build_stemmed_tsquery(q: str) -> str:
    """
    FTS prefix query üretir: her kelime için kök + orijinal form (tekrarsız).
    to_tsquery için özel karakterler temizlenir.

    Döner: "token1:* & token2:* & ..." formatında string.
    """
    safe = re.sub(r"[&|!():<>@*\\]", " ", q)
    words = [w for w in safe.split() if len(w) >= 2]
    if not words:
        return ""

    seen: set[str] = set()
    parts: list[str] = []
    for w in words:
        stem = stem_word(w)
        for token in [stem, w]:
            t = token.lower()
            if t and len(t) >= 2 and t not in seen:
                parts.append(f"{t}:*")
                seen.add(t)

    return " & ".join(parts)
