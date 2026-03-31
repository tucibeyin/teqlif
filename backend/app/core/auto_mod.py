"""
Auto-Mod çekirdeği — içerik filtreleme altyapısı.

Kullanım:
    from app.core.auto_mod import auto_mod

    if auto_mod.contains_profanity(text):
        # mesajı reddet veya gizle

Özel kelimeler `app/core/bad_words.txt` dosyasından yüklenir (her satır bir kelime).
better_profanity'nin varsayılan İngilizce listesi de aktiftir; iki liste birleştirilir.

Dayanıklılık: better_profanity kurulu değilse AutoMod yine de çalışır,
contains_profanity() her zaman False döner (filtreleme devre dışı, mesajlar akar).
"""

import os
from app.core.logger import get_logger

logger = get_logger(__name__)

_BAD_WORDS_PATH = os.path.join(os.path.dirname(__file__), "bad_words.txt")

# better_profanity opsiyonel — kurulu değilse filtreleme sessizce devre dışı kalır
try:
    from better_profanity import profanity as _profanity
    _PROFANITY_AVAILABLE = True
except ImportError:
    _profanity = None  # type: ignore[assignment]
    _PROFANITY_AVAILABLE = False
    logger.warning(
        "[AUTO_MOD] better_profanity kurulu değil — küfür filtresi devre dışı. "
        "`pip install better-profanity==0.7.0` ile kurabilirsiniz."
    )


class AutoMod:
    """
    Canlı yayın chat ve DM mesajları için içerik denetleyici.

    Başlangıçta bir kez yüklenir; uygulama genelinde singleton olarak kullanılır.
    Özel kelimeler `bad_words.txt`'den eklenir; better_profanity'nin yerleşik
    İngilizce listesi de aktif tutulur.
    """

    def __init__(self) -> None:
        if _PROFANITY_AVAILABLE:
            self._load_custom_words()

    def _load_custom_words(self) -> None:
        """bad_words.txt'i okuyup better_profanity'ye ekler."""
        custom_words: list[str] = []
        try:
            with open(_BAD_WORDS_PATH, encoding="utf-8") as f:
                for line in f:
                    word = line.strip()
                    if word and not word.startswith("#"):
                        custom_words.append(word)
        except FileNotFoundError:
            logger.warning("[AUTO_MOD] bad_words.txt bulunamadı: %s", _BAD_WORDS_PATH)
        except Exception as exc:
            logger.error("[AUTO_MOD] bad_words.txt okunamadı: %s", exc)

        _profanity.load_censor_words()
        if custom_words:
            _profanity.add_censor_words(custom_words)
            logger.info("[AUTO_MOD] %d özel kelime yüklendi", len(custom_words))

    def contains_profanity(self, text: str) -> bool:
        """
        Metinde yasaklı kelime varsa True döner.
        better_profanity kurulu değilse her zaman False döner.

        Args:
            text: Kontrol edilecek ham metin.

        Returns:
            True  → yasaklı kelime bulundu (mesaj gizlenmeli).
            False → temiz veya filtre devre dışı.
        """
        if not _PROFANITY_AVAILABLE:
            return False
        return _profanity.contains_profanity(text)


# Uygulama genelinde kullanılan singleton
auto_mod = AutoMod()
