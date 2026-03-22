"""
Merkezi loglama ve Sentry servisi.

Tüm modüller log almak veya istisna göndermek için bu modülü kullanmalıdır.
Böylece Sentry DSN değişikliği, farklı bir hata izleme aracına geçiş gibi
altyapı kararları tek noktadan yönetilir.

Kullanım:
    from app.core.logger import get_logger, capture_exception

    logger = get_logger(__name__)
    logger.error("Bir şeyler ters gitti: %s", str(e), exc_info=True)
    capture_exception(e)
"""
import logging
import sentry_sdk


def get_logger(name: str = "teqlif") -> logging.Logger:
    """
    Belirtilen isimde bir logger döndürür.
    Loglama altyapısı (handler, format, dosyalar) logging_config.py'de
    uygulama başlangıcında tek seferlik kurulur; burası sadece logger alır.
    """
    return logging.getLogger(name)


def capture_exception(exc: Exception) -> None:
    """
    İstisnayı Sentry'e iletir.
    Sentry init edilmemişse (DSN tanımlı değilse) sessizce atlanır.
    """
    if sentry_sdk.is_initialized():
        sentry_sdk.capture_exception(exc)


def capture_message(message: str, level: str = "error") -> None:
    """
    Serbest metin bir mesajı Sentry'e iletir.
    Exception olmayan ama takip edilmesi gereken durumlar için.
    """
    if sentry_sdk.is_initialized():
        sentry_sdk.capture_message(message, level=level)
