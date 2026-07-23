import logging
import traceback
import uuid
from fastapi import Request, FastAPI, HTTPException
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from app.core.exceptions import AppException
from app.core.i18n import I18nService
from app.core.idempotency import _IdempotencyReplay
from app.core.logger import capture_exception

logger = logging.getLogger(__name__)

def setup_exception_handlers(app: FastAPI):
    """
    Tüm global hata yakalayıcılarını FastAPI uygulamasına kaydeder.
    """
    
    @app.exception_handler(_IdempotencyReplay)
    async def idempotency_replay_handler(request: Request, exc: _IdempotencyReplay):
        return exc.response
        
    @app.exception_handler(AppException)
    async def app_exception_handler(request: Request, exc: AppException):
        user = getattr(request.state, "user", None)
        user_id = getattr(user, "id", "guest") if user else "guest"
        req_id = getattr(request.state, "request_id", str(uuid.uuid4()))

        log_level = logging.ERROR if exc.status_code >= 500 else logging.WARNING
        logger.log(
            log_level,
            "[DomainError] %s | code=%s user=%s path=%s req_id=%s",
            exc.message, exc.error_code, user_id, request.url.path, req_id,
        )

        headers = {}
        retry_after = getattr(exc, "retry_after", None)
        if retry_after:
            headers["Retry-After"] = str(retry_after)

        # ── i18n ─────────────────────────────────────────────────────────────
        lang = I18nService.parse_accept_language(
            request.headers.get("Accept-Language")
        )
        seconds_remaining = getattr(exc, "seconds_remaining", None)
        resolve_kwargs: dict = {}
        if seconds_remaining is not None:
            resolve_kwargs["seconds_remaining"] = seconds_remaining

        localized = I18nService.resolve(exc.error_code, lang, **resolve_kwargs)
        message = localized if localized is not None else exc.message

        localized_hint = I18nService.resolve_hint(exc.error_code, lang)
        raw_hint = getattr(exc, "hint", None)
        hint = localized_hint if localized_hint is not None else raw_hint
        # ─────────────────────────────────────────────────────────────────────

        extra: dict = {}
        if getattr(exc, "email", None):
            extra["email"] = exc.email
        if hint:
            extra["hint"] = hint
        if seconds_remaining is not None:
            extra["seconds_remaining"] = seconds_remaining

        return JSONResponse(
            status_code=exc.status_code,
            content={
                "success": False,
                "error": {
                    "code": exc.error_code,
                    "message": message,
                    "request_id": req_id,
                    **extra,
                },
            },
            headers=headers or None,
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException):
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "success": False,
                "error": {
                    "code": f"HTTP_{exc.status_code}",
                    "message": exc.detail if isinstance(exc.detail, str) else str(exc.detail),
                },
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        req_id = getattr(request.state, "request_id", str(uuid.uuid4()))
        
        try:
            errors = exc.errors()
        except Exception:
            errors = str(exc)
            
        def _safe(obj):
            if isinstance(obj, dict):
                return {k: _safe(v) for k, v in obj.items()}
            if isinstance(obj, list):
                return [_safe(i) for i in obj]
            if isinstance(obj, (str, int, float, bool, type(None))):
                return obj
            return str(obj)
            
        safe_errors = _safe(errors)
        logger.warning(
            "[ValidationError] path=%s req_id=%s errors=%s", 
            request.url.path, req_id, safe_errors
        )
        lang = I18nService.parse_accept_language(
            request.headers.get("Accept-Language")
        )
        val_msg = I18nService.resolve("VALIDATION_ERROR", lang) or "Geçersiz istek verisi"
        return JSONResponse(
            status_code=422,
            content={
                "success": False,
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": val_msg,
                    "details": safe_errors,
                    "request_id": req_id,
                },
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        if isinstance(exc, HTTPException):
            return await http_exception_handler(request, exc)
            
        user = getattr(request.state, "user", None)
        user_id = getattr(user, "id", "guest") if user else "guest"
        req_id = getattr(request.state, "request_id", str(uuid.uuid4()))
        
        logger.error(
            "[UnhandledError] %s | user=%s path=%s req_id=%s\n%s", 
            str(exc), user_id, request.url.path, req_id, traceback.format_exc()
        )
        capture_exception(exc)

        lang = I18nService.parse_accept_language(
            request.headers.get("Accept-Language")
        )
        srv_msg = (
            I18nService.resolve("INTERNAL_SERVER_ERROR", lang)
            or "Sunucuda beklenmeyen bir hata oluştu."
        )
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "error": {
                    "code": "INTERNAL_SERVER_ERROR",
                    "message": srv_msg,
                    "request_id": req_id,
                },
            },
        )
