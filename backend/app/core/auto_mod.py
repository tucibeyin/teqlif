"""
Auto-Mod çekirdeği — içerik filtreleme altyapısı.

Kullanım:
    from app.core.auto_mod import auto_mod

    if auto_mod.contains_profanity(text):
        # mesajı reddet veya gizle

Özel kelimeler `app/core/bad_words.txt` dosyasından yüklenir (her satır bir kelime).
better_profanity'nin varsayılan İngilizce listesi de aktiftir; iki liste birleştirilir.
"""

import os
from better_profanity import profanity

from app.core.logger import get_logger

logger = get_logger(__name__)

_BAD_WORDS_PATH = os.path.join(os.path.dirname(__file__), "bad_words.txt")


class AutoMod:
    """
    Canlı yayın chat ve DM mesajları için içerik denetleyici.

    Başlangıçta bir kez yüklenir; uygulama genelinde singleton olarak kullanılır.
    Özel kelimeler `bad_words.txt`'den eklenir; better_profanity'nin yerleşik
    İngilizce listesi de aktif tutulur.
    """

    def __init__(self) -> None:
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

        # load_censor_words: mevcut listeye ekler (extend=True varsayılan değil,
        # bu yüzden önce profanity.load_censor_words() ile built-in'i yükle,
        # ardından custom_words'ü ekle)
        profanity.load_censor_words()
        if custom_words:
            profanity.add_censor_words(custom_words)
            logger.info("[AUTO_MOD] %d özel kelime yüklendi", len(custom_words))

    def contains_profanity(self, text: str) -> bool:
        """
        Metinde yasaklı kelime varsa True döner.

        Args:
            text: Kontrol edilecek ham metin.

        Returns:
            True  → yasaklı kelime bulundu (mesaj reddedilmeli / gizlenmeli).
            False → temiz.
        """
        return profanity.contains_profanity(text)


# Uygulama genelinde kullanılan singleton
auto_mod = AutoMod()
