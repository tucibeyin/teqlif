"""
Projeye özel Custom Exception sınıfları.

FastAPI'nin HTTPException'ını genişleterek tüm hataların
standart bir JSON formatında (`{"success": false, "error": {...}}`)
dönmesini sağlar. Global exception handler'lar main.py'de bu
sınıfları yakalar.

Kullanım:
    from app.core.exceptions import NotFoundException, DatabaseException

    # 404
    raise NotFoundException("İlan bulunamadı")

    # 500 (DB hatası yakalandıktan sonra)
    raise DatabaseException()

    # Özel mesajlı 403
    raise ForbiddenException("Bu ilanı düzenleme yetkiniz yok")
"""
from fastapi import HTTPException


class AppException(HTTPException):
    """
    Projeye özel temel istisna sınıfı.
    Global handler bu sınıfı yakalayıp standart hata formatını döner.
    Doğrudan kullanmak yerine alt sınıfları tercih edin.
    """

    def __init__(self, status_code: int, message: str, code: str | None = None):
        super().__init__(status_code=status_code, detail=message)
        self.message = message
        self.error_code = code or f"ERR_{status_code}"


class NotFoundException(AppException):
    """404 — İstenen kayıt bulunamadı."""

    def __init__(self, message: str = "Kayıt bulunamadı"):
        super().__init__(status_code=404, message=message, code="NOT_FOUND")


class ForbiddenException(AppException):
    """403 — Yetki hatası."""

    def __init__(self, message: str = "Bu işlem için yetkiniz yok", code: str = "FORBIDDEN"):
        super().__init__(status_code=403, message=message, code=code)


class EmailNotVerifiedException(AppException):
    """403 — E-posta adresi henüz doğrulanmamış."""

    def __init__(self, message: str = "E-posta adresinizi doğrulamanız gerekiyor", email: str | None = None):
        super().__init__(status_code=403, message=message, code="EMAIL_NOT_VERIFIED")
        self.email = email


class UnauthorizedException(AppException):
    """401 — Kimlik doğrulama hatası (yanlış şifre, geçersiz token vb.)."""

    def __init__(self, message: str = "Kimlik doğrulama başarısız"):
        super().__init__(status_code=401, message=message, code="UNAUTHORIZED")


class BadRequestException(AppException):
    """400 — Geçersiz istek / iş kuralı ihlali."""

    def __init__(self, message: str = "Geçersiz istek"):
        super().__init__(status_code=400, message=message, code="BAD_REQUEST")


class ContentPolicyException(AppException):
    """400 — İçerik politikası ihlali (profanity, NSFW vb.)."""

    def __init__(self, message: str = "İçerik topluluk kurallarına aykırı"):
        super().__init__(status_code=400, message=message, code="CONTENT_POLICY_VIOLATION")


class ConflictException(AppException):
    """409 — Çakışma (zaten mevcut kayıt vb.)."""

    def __init__(self, message: str = "Kayıt zaten mevcut"):
        super().__init__(status_code=409, message=message, code="CONFLICT")


class DatabaseException(AppException):
    """
    500 — Veritabanı seviyesinde beklenmeyen hata.
    Bu sınıfı raise etmeden önce:
      - db.rollback() çağrısı yapın
      - logger.error(..., exc_info=True) ile orijinal hatayı loglandırın
      - capture_exception(orijinal_hata) ile Sentry'e gönderin
    """

    def __init__(self, message: str = "Veritabanı hatası oluştu"):
        super().__init__(status_code=500, message=message, code="DB_ERROR")


class ServiceException(AppException):
    """
    500 — Dış servis (LiveKit, Firebase, Brevo vb.) hatası.
    DatabaseException ile aynı kurallar geçerli.
    """

    def __init__(self, message: str = "Servis hatası oluştu"):
        super().__init__(status_code=500, message=message, code="SERVICE_ERROR")


class TooManyRequestsException(AppException):
    """
    429 — Hız sınırı aşıldı (kullanıcı bazlı aksiyon rate limit).
    retry_after: İstemcinin kaç saniye beklemesi gerektiği.
    """

    def __init__(self, message: str = "Çok fazla istek gönderildi. Lütfen bekleyin.", retry_after: int = 60):
        super().__init__(status_code=429, message=message, code="RATE_LIMIT_EXCEEDED")
        self.retry_after = retry_after


class CooldownException(AppException):
    """429 — Belirli bir aksiyon için bekleme süresi dolmadı (blast, mesaj vb.)."""

    def __init__(self, seconds_remaining: int):
        minutes, secs = divmod(seconds_remaining, 60)
        if minutes > 0:
            readable = f"{minutes} dakika {secs} saniye" if secs else f"{minutes} dakika"
        else:
            readable = f"{secs} saniye"
        super().__init__(
            status_code=429,
            message=f"Tekrar göndermek için {readable} beklemeniz gerekiyor.",
            code="COOLDOWN",
        )
        self.seconds_remaining = seconds_remaining
        self.retry_after = seconds_remaining


class ListingNotActiveException(AppException):
    """409 — İlan aktif değil, işlem yapılamaz."""

    def __init__(self, message: str = "İlan şu an aktif değil."):
        super().__init__(status_code=409, message=message, code="LISTING_NOT_ACTIVE")


class InsufficientFundsException(AppException):
    """402 — Yetersiz TUCi bakiyesi."""

    def __init__(self, message: str = "Bu işlem için yeterli TUCi bakiyeniz yok."):
        super().__init__(status_code=402, message=message, code="INSUFFICIENT_FUNDS")
        self.hint = "TUCi Cüzdan sayfasından bakiye yükleyebilirsiniz."
