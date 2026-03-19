# Redis and Database Security Configuration
# Phase 5: Infrastructure Security
import redis
from typing import Optional
from app.config import settings


class RedisSecurity:
    """Secure Redis connection management"""
    
    @staticmethod
    def get_secure_redis_url() -> str:
        """Get Redis URL with password if configured"""
        url = settings.redis_url
        
        # If Redis has password, use it
        if hasattr(settings, 'redis_password') and settings.redis_password:
            # Format: redis://:password@host:port/db
            if '://' in url:
                parts = url.split('://')
                return f"redis://:{settings.redis_password}@{parts[1]}"
            return f"redis://:{settings.redis_password}@localhost:6379"
        
        return url
    
    @staticmethod
    async def test_connection() -> tuple[bool, str]:
        """Test Redis connection securely"""
        try:
            r = redis.from_url(RedisSecurity.get_secure_redis_url())
            r.ping()
            return True, "Redis connection OK"
        except redis.ConnectionError as e:
            return False, f"Redis connection failed: {e}"
    
    @staticmethod
    async def get_memory_info() -> dict:
        """Get Redis memory usage info"""
        r = redis.from_url(RedisSecurity.get_secure_redis_url())
        info = r.info('memory')
        return {
            'used_memory': info.get('used_memory_human'),
            'used_memory_peak': info.get('used_memory_peak_human'),
            'connected_clients': info.get('connected_clients'),
        }


class DatabaseSecurity:
    """Database security helpers"""
    
    # Sensitive fields that should be encrypted
    ENCRYPTED_FIELDS = [
        'email', 'phone', 'fcm_token', 
        'notification_prefs', 'hashed_password'
    ]
    
    # Fields to exclude from logs
    EXCLUDED_FIELDS = [
        'password', 'hashed_password', 'fcm_token', 
        'token', 'secret', 'api_key'
    ]
    
    @staticmethod
    def should_log_field(field_name: str) -> bool:
        """Check if field should be logged"""
        return field_name.lower() not in DatabaseSecurity.EXCLUDED_FIELDS
    
    @staticmethod
    def sanitize_for_log(data: dict) -> dict:
        """Remove sensitive data before logging"""
        return {
            k: v for k, v in data.items() 
            if DatabaseSecurity.should_log_field(k)
        }


class ConnectionPoolSecurity:
    """Database connection pool security"""
    
    @staticmethod
    def get_safe_pool_config() -> dict:
        """Get secure connection pool settings"""
        return {
            'pool_size': 10,
            'max_overflow': 20,
            'pool_timeout': 30,
            'pool_recycle': 3600,
            'pool_pre_ping': True,  # Test connections before use
            'echo': False,  # Don't log SQL in production
        }


__all__ = ['RedisSecurity', 'DatabaseSecurity', 'ConnectionPoolSecurity']
