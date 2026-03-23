"""
Captcha Doğrulama Dependency — Cloudflare Turnstile / reCAPTCHA Hazırlığı

Kritik endpoint'ler için X-Captcha-Token header'ı doğrular.

Konfigürasyon (.env veya settings):
    CAPTCHA_ENABLED=false     → Mock mod: token varlığını kontrol eder, API çağrısı yapmaz
    CAPTCHA_ENABLED=true      → Gerçek Turnstile/reCAPTCHA API doğrulaması
    CAPTCHA_PROVIDER=turnstile  → "turnstile" (varsayılan) veya "recaptcha"
    CAPTCHA_SECRET_KEY=...    → Cloudflare Site Secret veya Google reCAPTCHA Secret

Kullanım (router endpoint'lerinde):
    from app.security.captcha import verify_captcha_token
    from fastapi import Depends

    @router.post("/create")
    async def create_something(
        _captcha: None = Depends(verify_captcha_token),
        current_user: User = Depends(get_current_user),
        ...
    ):
        ...

Frontend (Flutter/iOS/Android):
    Cloudflare Turnstile widget'ı token üretir → HTTP header'a ekle:
        X-Captcha-Token: <turnstile_token>
"""

import httpx
from fastapi import Header
from app.core.exceptions import ForbiddenException
from app.core.logger import get_logger

logger = get_logger(__name__)

# Doğrulama endpoint'leri
_TURNSTILE_VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
_RECAPTCHA_VERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"


def _get_captcha_config() -> tuple[bool, str, str | None]:
    """
    Captcha ayarlarını app.config.settings'ten okur.
    settings'te tanımlı değilse güvenli varsayılanları döner.

    Returns:
        (enabled: bool, provider: str, secret_key: str | None)
    """
    try:
        from app.config import settings
        enabled = getattr(settings, "captcha_enabled", False)
        provider = getattr(settings, "captcha_provider", "turnstile")
        secret = getattr(settings, "captcha_secret_key", None)
        return bool(enabled), str(provider), secret
    except Exception:
        return False, "turnstile", None


async def verify_captcha_token(
    x_captcha_token: str | None = Header(default=None, alias="X-Captcha-Token"),
) -> None:
    """
    FastAPI Dependency — X-Captcha-Token header'ını doğrular.

    CAPTCHA_ENABLED=False (varsayılan/geliştirme):
        Token varsa kabul eder, yoksa ForbiddenException fırlatır.
        Dış API çağrısı yapılmaz — geliştirme ortamında sürtünme yaratmaz.

    CAPTCHA_ENABLED=True (production):
        Cloudflare Turnstile veya reCAPTCHA API'sine POST atar.
        API success=false dönerse ForbiddenException fırlatır.
        Dış servis hatasında fail-open: loglanır ve geçilir.

    Raises:
        ForbiddenException(403) — Token eksik veya doğrulama başarısız
    """
    captcha_enabled, provider, secret_key = _get_captcha_config()

    # Token yoksa her zaman reddet (mock mod dahil)
    if not x_captcha_token:
        logger.warning(
            "[CAPTCHA] Token eksik | captcha_enabled=%s", captcha_enabled,
        )
        raise ForbiddenException("Captcha token eksik. Lütfen captcha'yı tamamlayın.")

    # Mock mod — token varlığı yeterli, API çağrısı yok
    if not captcha_enabled:
        logger.debug("[CAPTCHA] Mock mod aktif — token mevcut, doğrulama atlandı")
        return

    # Production: Gerçek API doğrulaması
    if not secret_key:
        # Secret key yapılandırılmamış: logla ama geç (misconfiguration alarm)
        logger.error(
            "[CAPTCHA] CAPTCHA_SECRET_KEY tanımlı değil — doğrulama atlanıyor! "
            "Production'da bu log görünüyorsa .env'i kontrol edin."
        )
        return

    verify_url = _TURNSTILE_VERIFY_URL if provider == "turnstile" else _RECAPTCHA_VERIFY_URL

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                verify_url,
                data={"secret": secret_key, "response": x_captcha_token},
            )
            result = resp.json()

        if not result.get("success"):
            error_codes = result.get("error-codes", [])
            logger.warning(
                "[CAPTCHA] Doğrulama başarısız | provider=%s | error_codes=%s",
                provider, error_codes,
            )
            raise ForbiddenException("Captcha doğrulaması başarısız. Lütfen tekrar deneyin.")

        logger.info("[CAPTCHA] Doğrulama başarılı | provider=%s", provider)

    except ForbiddenException:
        raise
    except Exception as exc:
        # Dış servis hatası → fail-open: captcha servisi çöktüğünde işlemler durmamalı
        logger.error(
            "[CAPTCHA] Doğrulama servisi hatası — fail-open | provider=%s | %s",
            provider, exc, exc_info=True,
        )
