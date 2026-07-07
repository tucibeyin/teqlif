"""
app/utils/i18n.py
─────────────────
Merkezi çeviri (ARB) yardımcısı.

_get_t(lang) fonksiyonu ilgili dile ait app_<lang>.arb dosyasını
okur ve bir dict olarak döner.  Dosyanın mtime'ı her çağrıda
kontrol edilir; değişmişse cache otomatik yenilenir — sunucu
restart gerektirmez.
"""

import json
import os

_ARB_CACHE: dict = {}   # lang -> dict
_ARB_MTIME: dict = {}   # lang -> float (son değiştirilme zamanı)

def _arb_path(lang: str) -> str:
    """mobile/lib/l10n/app_<lang>.arb dosyasının mutlak yolunu döner."""
    base_dir = os.path.dirname(                 # backend/
                   os.path.dirname(             # app/
                       os.path.dirname(         # utils/
                           os.path.abspath(__file__))))
    # backend/ → proje kökü → mobile/lib/l10n/
    project_root = os.path.dirname(base_dir)
    return os.path.join(project_root, "mobile", "lib", "l10n", f"app_{lang}.arb")


def _get_t(lang: str) -> dict:
    """
    Belirtilen dil için çeviri sözlüğünü döner.

    * ARB dosyası değişmişse cache otomatik yenilenir.
    * Dosya bulunamazsa Türkçe'ye (tr) düşer; o da yoksa {} döner.
    """
    try:
        path = _arb_path(lang)
        mtime = os.path.getmtime(path)
        if lang not in _ARB_CACHE or _ARB_MTIME.get(lang) != mtime:
            with open(path, "r", encoding="utf-8") as f:
                _ARB_CACHE[lang] = json.load(f)
            _ARB_MTIME[lang] = mtime
        return _ARB_CACHE[lang]
    except Exception:
        if lang != "tr":
            return _get_t("tr")
        return {}


_SUPPORTED = {"tr", "en", "ar", "ru"}

def get_locale(user=None, request=None, default: str = "tr") -> str:
    """
    Öncelik: Accept-Language header > user.locale (DB) > default.

    Request header önce gelir çünkü kullanıcının o andaki uygulama
    dilini yansıtır; DB değeri senkronizasyon gecikmesinden etkilenebilir.
    """
    if request is not None:
        al = request.headers.get("accept-language", "")
        for part in al.replace(",", ";").split(";"):
            lang = part.strip()[:2].lower()
            if lang in _SUPPORTED:
                return lang
    if user:
        loc = getattr(user, "locale", None)
        if loc and loc in _SUPPORTED:
            return loc
    return default
