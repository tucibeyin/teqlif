"""
Türkçe Hype Sözlüğü ve mesaj puanlama fonksiyonu.

Regex/sözlük tabanlı — NLP modeli yok, CPU/RAM etkisi minimumdur.
Kelimeler küçük harfe çevrilip token'lara bölündükten sonra
HYPE_DICTIONARY ile eşleştirilir; puan toplanır ve döndürülür.
"""

import re

# ── Hype Sözlüğü ──────────────────────────────────────────────────────────────
# Pozitif değerler heyecanı artırır, negatifler düşürür.
# Aralıklar: +5 çok yüksek hype | +1 hafif pozitif | -1 hafif negatif | -5 çok olumsuz

HYPE_DICTIONARY: dict[str, int] = {
    # ── Satın alma / teklif sinyalleri (en güçlü hype) ─────────────────────────
    "aldım":         5,
    "alıyorum":      5,
    "alacağım":      4,
    "alırım":        4,
    "aldı":          4,
    "satın":         3,
    "teklif":        3,
    "teklifim":      4,
    "öneriyorum":    3,
    "sipariş":       4,
    "rezerve":       4,

    # ── VIP / premium ifadeler ───────────────────────────────────────────────────
    "vip":           5,
    "premium":       4,
    "özel":          3,
    "sınırlı":       3,
    "nadir":         4,
    "koleksiyon":    3,

    # ── Yüksek duygusal hype ────────────────────────────────────────────────────
    "harika":        5,
    "mükemmel":      5,
    "süper":         5,
    "şahane":        5,
    "efsane":        5,
    "inanılmaz":     5,
    "muhteşem":      5,
    "wow":           5,
    "ateş":          4,
    "helal":         4,
    "bravo":         4,
    "tebrikler":     4,
    "heyecanlı":     4,
    "heyecan":       4,
    "coşku":         4,
    "bayıldım":      5,
    "çıldırıyorum":  5,
    "delirdim":      4,

    # ── Orta hype ───────────────────────────────────────────────────────────────
    "güzel":         3,
    "sevdim":        3,
    "beğendim":      3,
    "fırsat":        3,
    "indirim":       3,
    "kaliteli":      3,
    "tavsiye":       2,
    "değer":         2,
    "ucuz":          3,
    "uygun":         2,
    "geliyorum":     3,
    "geliyor":       3,
    "izliyorum":     2,
    "bekleyorum":    2,
    "bekliyorum":    2,
    "keşke":         2,
    "bedava":        2,
    "ücretsiz":      3,
    "evet":          2,
    "iyi":           2,
    "doğru":         2,
    "haklı":         2,
    "anlaştık":      4,

    # ── Emoji (Unicode doğrudan eşleşir) ────────────────────────────────────────
    "🔥":            4,
    "❤️":            2,
    "💯":            3,
    "💪":            3,
    "🎉":            3,
    "😍":            3,
    "🙌":            2,
    "👍":            2,
    "🥳":            4,
    "😱":            3,
    "🚀":            4,
    "💎":            4,
    "⭐":            3,
    "🌟":            4,
    "✅":            2,
    "🎁":            3,

    # ── Olumsuz ifadeler ────────────────────────────────────────────────────────
    "pahalı":        -3,
    "kötü":          -2,
    "yavaş":         -2,
    "çöp":           -4,
    "kasıyor":       -3,
    "berbat":        -4,
    "rezalet":       -4,
    "vasat":         -2,
    "olmaz":         -2,
    "hayır":         -1,
    "kandırıyor":    -4,
    "sahte":         -4,
    "kalitesiz":     -3,
    "bozuk":         -2,
    "hata":          -2,
    "dolandırıcı":   -5,
    "dolandırıyor":  -5,
    "şikayet":       -3,
    "yalan":         -3,
    "işe yaramaz":   -3,
    "saçma":         -2,
    "alakasız":      -2,
    "hayal kırıklığı": -3,
    "mağdur":        -3,
}

# Emoji'ler Unicode sembolü içerdiğinden ayrı tutulur;
# token split bunları kırabileceği için arama direkt text üzerinden yapılır.
_EMOJI_KEYS: set[str] = {k for k in HYPE_DICTIONARY if not k.isascii() or not k.isalpha()}
_WORD_DICT:  dict[str, int] = {k: v for k, v in HYPE_DICTIONARY.items() if k not in _EMOJI_KEYS}

_TOKEN_RE = re.compile(r"[^\w]+", re.UNICODE)


def calculate_message_hype(text: str) -> int:
    """
    Bir chat mesajının Hype Puanını hesaplar ve döndürür.
    Pozitif = heyecan artışı, negatif = düşüş.
    Sonuç sınırlanmaz — çağıran taraf oda skoruna ekleyip 0-100 arasına çeker.
    """
    if not text:
        return 0

    score = 0

    # Kelime bazlı eşleşme
    tokens = _TOKEN_RE.split(text.lower())
    for token in tokens:
        if token:
            score += _WORD_DICT.get(token, 0)

    # Emoji / özel karakter bazlı eşleşme (token'a bölünmeden direkt arama)
    for key in _EMOJI_KEYS:
        if key in text:
            score += HYPE_DICTIONARY[key]

    return score
