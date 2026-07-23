"""
Projeye özel Custom Exception sınıfları.

FastAPI'nin HTTPException'ını genişleterek tüm hataların
standart bir JSON formatında (`{"success": false, "error": {...}}`)
dönmesini sağlar. Global exception handler'lar main.py'de bu
sınıfları yakalar.

Kullanım:
    from app.core.exceptions import NotFoundException, DatabaseException

    # 404
    raise NotFoundException()

    # 500 (DB hatası yakalandıktan sonra)
    raise DatabaseException()

    # Özel mesajlı 403 (migration tamamlanana kadar desteklenir)
    raise ForbiddenException("Bu ilanı düzenleme yetkiniz yok")
"""
from fastapi import HTTPException


class AppException(HTTPException):
    """
    Projeye özel temel istisna sınıfı.
    Global handler bu sınıfı yakalayıp standart hata formatını döner.
    Doğrudan kullanmak yerine alt sınıfları tercih edin.
    """

    def __init__(self, status_code: int, message: str | None = None, code: str | None = None):
        super().__init__(status_code=status_code, detail=message or "")
        self.message = message
        self.error_code = code or f"ERR_{status_code}"


class NotFoundException(AppException):
    """404 — İstenen kayıt bulunamadı."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=404, message=message, code="NOT_FOUND")


class ForbiddenException(AppException):
    """403 — Yetki hatası."""

    def __init__(self, message: str | None = None, code: str = "FORBIDDEN"):
        super().__init__(status_code=403, message=message, code=code)


class EmailNotVerifiedException(AppException):
    """403 — E-posta adresi henüz doğrulanmamış."""

    def __init__(self, message: str | None = None, email: str | None = None):
        super().__init__(status_code=403, message=message, code="EMAIL_NOT_VERIFIED")
        self.email = email


class UnauthorizedException(AppException):
    """401 — Kimlik doğrulama hatası (yanlış şifre, geçersiz token vb.)."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=401, message=message, code="UNAUTHORIZED")


class BadRequestException(AppException):
    """400 — Geçersiz istek / iş kuralı ihlali."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=400, message=message, code="BAD_REQUEST")


class ContentPolicyException(AppException):
    """400 — İçerik politikası ihlali (profanity, NSFW vb.)."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=400, message=message, code="CONTENT_POLICY_VIOLATION")


class ConflictException(AppException):
    """409 — Çakışma (zaten mevcut kayıt vb.)."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=409, message=message, code="CONFLICT")


class DatabaseException(AppException):
    """
    500 — Veritabanı seviyesinde beklenmeyen hata.
    Bu sınıfı raise etmeden önce:
      - db.rollback() çağrısı yapın
      - logger.error(..., exc_info=True) ile orijinal hatayı loglandırın
      - capture_exception(orijinal_hata) ile Sentry'e gönderin
    """

    def __init__(self, message: str | None = None):
        super().__init__(status_code=500, message=message, code="DB_ERROR")


class ServiceException(AppException):
    """
    500 — Dış servis (LiveKit, Firebase, Brevo vb.) hatası.
    DatabaseException ile aynı kurallar geçerli.
    """

    def __init__(self, message: str | None = None):
        super().__init__(status_code=500, message=message, code="SERVICE_ERROR")


class TooManyRequestsException(AppException):
    """
    429 — Hız sınırı aşıldı (kullanıcı bazlı aksiyon rate limit).
    retry_after: İstemcinin kaç saniye beklemesi gerektiği.
    """

    def __init__(self, message: str | None = None, retry_after: int = 60):
        super().__init__(status_code=429, message=message, code="RATE_LIMIT_EXCEEDED")
        self.retry_after = retry_after


class CooldownException(AppException):
    """429 — Belirli bir aksiyon için bekleme süresi dolmadı (blast, mesaj vb.).
    I18nService seconds_remaining'i okuyarak dile özel süre mesajı üretir.
    """

    def __init__(self, seconds_remaining: int):
        super().__init__(status_code=429, message=None, code="COOLDOWN")
        self.seconds_remaining = seconds_remaining
        self.retry_after = seconds_remaining


class ListingNotActiveException(AppException):
    """409 — İlan aktif değil, işlem yapılamaz."""

    def __init__(self, message: str | None = None):
        super().__init__(status_code=409, message=message, code="LISTING_NOT_ACTIVE")


class InsufficientFundsException(AppException):
    """402 — Yetersiz TUCi bakiyesi.
    Hint metni I18nService üzerinden INSUFFICIENT_FUNDS_hint kodu ile gelir.
    """

    def __init__(self, message: str | None = None):
        super().__init__(status_code=402, message=message, code="INSUFFICIENT_FUNDS")
