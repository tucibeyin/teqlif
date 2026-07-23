"""
Backend i18n — error code tabanlı lokalizasyon servisi.

Kullanım:
    # Uygulama başlangıcında bir kere yükle:
    I18nService.load_all()

    # Error handler'da:
    lang = I18nService.parse_accept_language(request.headers.get("Accept-Language"))
    msg  = I18nService.resolve("COOLDOWN", lang, seconds_remaining=45)
"""

from __future__ import annotations

import json
from pathlib import Path

_LOCALES_DIR = Path(__file__).parent / "locales"
_SUPPORTED: frozenset[str] = frozenset({"tr", "en", "ar", "ru"})
_DEFAULT = "tr"


class I18nService:
    _data: dict[str, dict[str, str]] = {}

    # ── Startup ──────────────────────────────────────────────────────────────

    @classmethod
    def load_all(cls) -> None:
        for lang in _SUPPORTED:
            path = _LOCALES_DIR / f"{lang}.json"
            if path.exists():
                cls._data[lang] = json.loads(path.read_text(encoding="utf-8"))

    # ── Accept-Language parsing ───────────────────────────────────────────────

    @classmethod
    def parse_accept_language(cls, header: str | None) -> str:
        if not header:
            return _DEFAULT
        for tag in header.split(","):
            lang = tag.split(";")[0].strip()[:2].lower()
            if lang in _SUPPORTED:
                return lang
        return _DEFAULT

    # ── Resolution ───────────────────────────────────────────────────────────

    @classmethod
    def resolve(cls, code: str, lang: str, **kwargs: object) -> str | None:
        """
        error code → lokalize string.
        kwargs: template placeholder değerleri (örn. seconds_remaining=45).
        None döner → caller exc.message fallback'ini kullanır.
        """
        bucket = cls._data.get(lang) or cls._data.get(_DEFAULT) or {}
        template = bucket.get(code)
        if template is None:
            return None
        if kwargs:
            # seconds_remaining → readable_time dönüşümü burada
            if "seconds_remaining" in kwargs and "readable_time" not in kwargs:
                kwargs["readable_time"] = cls.format_duration(
                    int(kwargs.pop("seconds_remaining")), lang  # type: ignore[arg-type]
                )
            try:
                return template.format(**kwargs)
            except (KeyError, ValueError):
                return template
        return template

    @classmethod
    def resolve_hint(cls, code: str, lang: str) -> str | None:
        bucket = cls._data.get(lang) or cls._data.get(_DEFAULT) or {}
        return bucket.get(f"{code}_hint")

    # ── Duration formatting ───────────────────────────────────────────────────

    @classmethod
    def format_duration(cls, total_seconds: int, lang: str) -> str:
        minutes, secs = divmod(total_seconds, 60)
        if lang == "tr":
            if minutes > 0:
                return f"{minutes} dakika {secs} saniye" if secs else f"{minutes} dakika"
            return f"{secs} saniye"
        if lang == "ar":
            if minutes > 0:
                return f"{minutes} دقيقة {secs} ثانية" if secs else f"{minutes} دقيقة"
            return f"{secs} ثانية"
        if lang == "ru":
            if minutes > 0:
                return f"{minutes} мин. {secs} сек." if secs else f"{minutes} мин."
            return f"{secs} сек."
        # en + default
        if minutes > 0:
            return f"{minutes} min {secs} sec" if secs else f"{minutes} min"
        return f"{secs} sec"
