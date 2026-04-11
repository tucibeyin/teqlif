"""
Güvenlik middleware'leri ve rate limiting
"""

import time
from fastapi import Request
from slowapi.errors import RateLimitExceeded

from app.utils.redis_client import get_redis
# Kanonik limiter ve standart 429 handler — app/core/rate_limit.py'de tanımlı
from app.core.rate_limit import limiter, rate_limit_exceeded_handler as _rate_limit_exceeded_handler  # noqa: F401

class SecurityMiddleware:
    """Güvenlik middleware collection"""
    
    def __init__(self):
        self.shared_limiter = limiter
        
    # Rate limiting decorators
    def auth_rate_limit(self):
        """Authentication endpoint için rate limiting"""
        return self.shared_limiter.limit("3 per minute")
    
    def auction_rate_limit(self):
        """Açık artırma endpoint'leri için rate limiting"""
        return self.shared_limiter.limit("1 per second")
    
    def general_rate_limit(self):
        """Genel API endpoint'leri için rate limiting"""
        return self.shared_limiter.limit("50 per minute")
    
    def upload_rate_limit(self):
        """File upload endpoint'leri için rate limiting"""
        return self.shared_limiter.limit("5 per hour")

# Security headers middleware
async def security_headers(request: Request, call_next):
    """
    Tüm response'lara güvenlik header'ları ekler
    """
    response = await call_next(request)
    
    # Security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self' https://accounts.google.com https://www.google.com https://browser.sentry-cdn.com https://cdn.jsdelivr.net https://challenges.cloudflare.com https://www.gstatic.com https://pagead2.googlesyndication.com https://partner.googleadservices.com https://tpc.googlesyndication.com; "
        "style-src 'self' 'unsafe-inline' https://accounts.google.com https://cdn.jsdelivr.net; "
        "img-src 'self' data: https:; "
        "media-src 'self' blob:; "
        "font-src 'self' https://fonts.gstatic.com https://cdn.jsdelivr.net; "
        "frame-src 'self' https://accounts.google.com https://www.google.com https://challenges.cloudflare.com https://*.firebaseapp.com https://googleads.g.doubleclick.net https://tpc.googlesyndication.com; "
        "connect-src 'self' ws: wss: https://accounts.google.com https://www.google.com https://*.sentry.io https://cdn.jsdelivr.net https://browser.sentry-cdn.com https://challenges.cloudflare.com https://*.googleapis.com https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.gstatic.com https://pagead2.googlesyndication.com https://googleads.g.doubleclick.net;"
    )
    response.headers["Permissions-Policy"] = "camera=(self), microphone=(self), geolocation=()"
    
    return response

# Custom security rate limiter functions
def block_suspicious_ip(ip_address: str, ttl_minutes: int = 30):
    """
    şpheli IP'leri temporary olarak engeller
    
    Args:
        ip_address (str): Engellenecek IP adresi
        ttl_minutes (int): Engelleme süresi (varsayılan 30 dk)
    """
    import asyncio
    asyncio.create_task(_block_ip_async(ip_address, ttl_minutes))

async def _block_ip_async(ip_address: str, ttl_minutes: int):
    """Async IP blocking için helper"""
    redis = await get_redis()
    await redis.setex(f"blocked:{ip_address}", ttl_minutes * 60, "1")

async def is_ip_blocked(ip_address: str) -> bool:
    """
    IP adresinin engellendiğini kontrol eder
    
    Args:
        ip_address (str): kontrol edilecek IP
        
    Returns:
        bool: engelli ise True
    """
    redis = await get_redis()
    is_blocked = await redis.exists(f"blocked:{ip_address}")
    return bool(is_blocked)

class SuspiciousActivityDetector:
    """Şüpheli aktivite tespit sistemi"""
    
    def __init__(self):
        self.thresholds = {
            "failed_logins": 5,  # Saatlik limit
            "auction_bids": 10,  # Dakikada
            "upload_attempts": 20  # Saatlik
        }
    
    async def check_failed_login(self, ip_address: str, username: str):
        """Başarısız login denemelerini izler"""
        redis = await get_redis()
        
        key = f"failed_login:{ip_address}:{username}"
        failed_count = await redis.incr(key)
        await redis.expire(key, 3600)  # 1 saat
        
        if failed_count >= self.thresholds["failed_logins"]:
            await block_suspicious_ip(ip_address, 60)
            
    async def check_auction_abuse(self, ip_address: str, user_id: int):
        """Açık artırma abuse tespiti"""
        redis = await get_redis()
        
        key = f"auction_throttle:{ip_address}:{user_id}"
        current_count = await redis.incr(key)
        await redis.expire(key, 60)  # 1 dakika
        
        if current_count > self.thresholds["auction_bids"]:
            await block_suspicious_ip(ip_address, 15)

# Security configuration
class SecurityConfig:
    """Güvenlik ayarları yapılandırması"""
    
    # Rate limiting thresholds
    RATE_LIMITS = {
        "login_attempts": {"limit": 3, "per": "minute"},
        "auction_bids": {"limit": 10, "per": "minute"},
        "file_uploads": {"limit": 5, "per": "hour"},
        "api_general": {"limit": 50, "per": "hour"},
        "admin_access": {"limit": 20, "per": "hour"}
    }
    
    # Suspend thresholds
    SUSPEND_THRESHOLDS = {
        "failed_logins": 5,
        "malicious_requests": 10,
        "rate_limit_violations": 3
    }
    
    # Security headers
    ENABLED = {
        "hsts": True,
        "csp": True,
        "xss_protection": True,
        "frame_protection": True
    }

# Security utilities
class SecurityLogger:
    """Güvenlik olayları için logging"""
    
    import logging
    logger = logging.getLogger("security")
    
    @classmethod
    def log_security_event(cls, event_type: str, **kwargs):
        """
        Bir güvenlik olayını loglar
        
        Args:
            event_type (str): olay tipi (login_fail, rate_limit, etc)
            **kwargs: additional context bilgileri
        """
        import logging
        logger = logging.getLogger("security")
        log_data = {
            "event_type": event_type,
            "timestamp": time.time(),
            **kwargs
        }
        logger.info(f"SECURITY_EVENT: {log_data}")
        
        # Real-time alerts for critical events
        if event_type in ["ip_blocked", "multiple_failed_logins", "admin_access_violation"]:
            # Here you would send to alerting system
            pass