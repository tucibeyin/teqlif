"""
Rate Limiting — merkezi limiter ve standart hata handler'ı.

Kullanım (router'larda):
    from app.core.rate_limit import limiter
    from fastapi import Request

    @router.post("/login")
    @limiter.limit("5/minute")
    async def login(request: Request, data: UserLogin, ...):
        ...

Limiter Redis'i arka depo olarak kullanır; redis://localhost:6379 env'de
REDIS_URL ile override edilebilir.
"""

import os
from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.logger import get_logger

logger = get_logger(__name__)

_REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

def get_user_id_or_ip(request: Request) -> str:
    """
    Rate limit key: authenticated ise 'user:<id>', değilse IP adresi.
    Bu sayede VPN arkasındaki farklı kullanıcılar birbirini bloklamaz,
    bot/spam teklif saldırıları hesap bazında engellenir.
    """
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        # decode_token sync olduğu için burada direkt kullanılabilir
        from app.utils.auth import decode_token
        user_id = decode_token(auth[7:])
        if user_id:
            return f"user:{user_id}"
    return get_remote_address(request)


limiter = Limiter(
    key_func=get_user_id_or_ip,
    storage_uri=_REDIS_URL,
    strategy="fixed-window",
)





async def rate_limit_exceeded_handler(
    request: Request, exc: RateLimitExceeded
) -> JSONResponse:
    """
    slowapi RateLimitExceeded (HTTP 429) hatalarını projenin standart
    JSON formatında döner.

    Format:
        {
            "success": false,
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": "Çok fazla istek gönderildi. ..."
            }
        }
    """
    ip = request.client.host if request.client else "unknown"
    logger.warning(
        "Rate limit aşıldı: %s %s | IP: %s | Limit: %s",
        request.method,
        request.url.path,
        ip,
        str(exc.detail),
    )
    return JSONResponse(
        status_code=429,
        content={
            "success": False,
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": "Çok fazla istek gönderildi. Lütfen biraz bekleyin.",
            },
        },
        headers={"Retry-After": "60"},
    )
