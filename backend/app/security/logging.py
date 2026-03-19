# Security Logging and Monitoring
# Phase 5: Security Monitoring
import logging
import json
import time
from datetime import datetime
from typing import Optional, Any
from fastapi import Request
from app.utils.redis_client import get_redis

# Security event types
SECURITY_EVENTS = {
    'LOGIN_SUCCESS': 'user.login.success',
    'LOGIN_FAILED': 'user.login.failed',
    'LOGOUT': 'user.logout',
    'PASSWORD_CHANGE': 'user.password.change',
    'PASSWORD_RESET': 'user.password.reset',
    'REGISTER': 'user.register',
    'ADMIN_ACCESS': 'admin.access',
    'ADMIN_ACTION': 'admin.action',
    'RATE_LIMIT': 'security.rate_limit',
    'SUSPICIOUS_ACTIVITY': 'security.suspicious',
    'TOKEN_BLACKLIST': 'security.token.blacklist',
    'IP_BLOCKED': 'security.ip.blocked',
    'UPLOAD_BLOCKED': 'security.upload.blocked',
    'INJECTION_ATTEMPT': 'security.injection',
}


class SecurityLogger:
    """Centralized security event logging"""
    
    def __init__(self):
        self.logger = logging.getLogger('security')
        self.logger.setLevel(logging.INFO)
    
    def _log(self, event_type: str, user_id: Optional[int], ip: str, details: dict):
        """Internal logging method"""
        log_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'event': event_type,
            'user_id': user_id,
            'ip': ip,
            'details': details
        }
        self.logger.info(json.dumps(log_entry))
    
    def login_success(self, user_id: int, ip: str, request: Request):
        self._log(SECURITY_EVENTS['LOGIN_SUCCESS'], user_id, ip, {
            'method': request.method,
            'path': request.url.path,
            'user_agent': request.headers.get('user-agent', '')[:100]
        })
    
    def login_failed(self, user_id: Optional[int], ip: str, reason: str):
        self._log(SECURITY_EVENTS['LOGIN_FAILED'], user_id, ip, {'reason': reason})
    
    def rate_limit_exceeded(self, ip: str, endpoint: str):
        self._log(SECURITY_EVENTS['RATE_LIMIT'], None, ip, {'endpoint': endpoint})
    
    def suspicious_activity(self, user_id: Optional[int], ip: str, activity: str):
        self._log(SECURITY_EVENTS['SUSPICIOUS_ACTIVITY'], user_id, ip, {'activity': activity})
    
    def injection_attempt(self, ip: str, payload: str):
        self._log(SECURITY_EVENTS['INJECTION_ATTEMPT'], None, ip, {'payload': payload[:200]})
    
    def admin_action(self, user_id: int, action: str, details: dict):
        self._log(SECURITY_EVENTS['ADMIN_ACTION'], user_id, 'admin', {'action': action, **details})


class SecurityMonitor:
    """Real-time security monitoring"""
    
    @staticmethod
    async def record_failed_login(ip: str, username: str):
        """Record failed login attempt"""
        redis = await get_redis()
        key = f"failed_login:{ip}:{username}"
        await redis.incr(key)
        await redis.expire(key, 3600)  # 1 hour
    
    @staticmethod
    async def get_failed_login_count(ip: str, username: str) -> int:
        """Get failed login count"""
        redis = await get_redis()
        count = await redis.get(f"failed_login:{ip}:{username}")
        return int(count or 0)
    
    @staticmethod
    async def record_suspicious_ip(ip: str, reason: str):
        """Mark IP as suspicious"""
        redis = await get_redis()
        key = f"suspicious_ip:{ip}"
        await redis.incr(key)
        await redis.expire(key, 86400)  # 24 hours
    
    @staticmethod
    async def is_ip_suspicious(ip: str) -> bool:
        """Check if IP is marked suspicious"""
        redis = await get_redis()
        count = await redis.get(f"suspicious_ip:{ip}")
        return int(count or 0) > 3
    
    @staticmethod
    async def get_security_stats() -> dict:
        """Get security statistics"""
        redis = await get_redis()
        
        # This would need more sophisticated queries in production
        return {
            'recorded_at': datetime.utcnow().isoformat(),
            'monitoring': True
        }


class RequestSanitizer:
    """Sanitize request data for logging"""
    
    @staticmethod
    def get_client_ip(request: Request) -> str:
        """Get real client IP"""
        forwarded = request.headers.get('x-forwarded-for')
        if forwarded:
            return forwarded.split(',')[0].strip()
        return request.client.host if request.client else 'unknown'
    
    @staticmethod
    def sanitize_request_data(data: dict) -> dict:
        """Remove sensitive data from request"""
        sensitive_keys = ['password', 'token', 'secret', 'key', 'fcm_token']
        return {k: v for k, v in data.items() if k.lower() not in sensitive_keys}


# Global instance
security_logger = SecurityLogger()


__all__ = ['SecurityLogger', 'SecurityMonitor', 'RequestSanitizer', 'SECURITY_EVENTS']
