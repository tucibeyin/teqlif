"""
Merkezi loglama, Sentry servisi ve güvenli görev oluşturma.

Tüm modüller log almak veya istisna göndermek için bu modülü kullanmalıdır.
Böylece Sentry DSN değişikliği, farklı bir hata izleme aracına geçiş gibi
altyapı kararları tek noktadan yönetilir.

Kullanım:
    from app.core.logger import get_logger, capture_exception

    logger = get_logger(__name__)
    logger.error("Bir şeyler ters gitti: %s", str(e), exc_info=True)
    capture_exception(e)
"""
import asyncio
import logging
from typing import Coroutine, Any

import sentry_sdk

_log = logging.getLogger("teqlif.tasks")


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


def fire_and_forget(coro: Coroutine[Any, Any, Any], *, tag: str = "") -> asyncio.Task:
    """
    asyncio.create_task() replacement that logs and captures unhandled exceptions.

    Plain create_task() silently drops exceptions — they surface only as an
    unraisable RuntimeWarning that never reaches Sentry.  Use this wrapper
    everywhere a background coroutine must not block the caller but must also
    not lose failures silently.

    Usage:
        fire_and_forget(push_notification(...), tag="auction.outbid_push")
    """
    task = asyncio.create_task(coro)

    def _on_done(t: asyncio.Task) -> None:
        if t.cancelled():
            return
        exc = t.exception()
        if exc is not None:
            label = f"[{tag}] " if tag else ""
            _log.error("%sfire_and_forget task raised: %s", label, exc, exc_info=exc)
            capture_exception(exc)

    task.add_done_callback(_on_done)
    return task
