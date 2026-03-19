# JWT Token Security Enhancements
# Phase 3: Authentication Improvements
import secrets
import time
from datetime import datetime, timedelta
from typing import Optional
from jose import jwt, JWTError
from app.config import settings
from app.utils.redis_client import get_redis

# Token configurations
ACCESS_TOKEN_EXPIRE_MINUTES = 15  # Reduced from 30
REFRESH_TOKEN_EXPIRE_DAYS = 7
TOKEN_TYPE = "bearer"


class TokenManager:
    """Enhanced token management with blacklisting"""
    
    @staticmethod
    def create_access_token(user_id: int, additional_claims: dict = None) -> str:
        """Create access token with short expiry"""
        now = datetime.utcnow()
        expire = now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        
        payload = {
            "sub": str(user_id),
            "exp": expire,
            "iat": now,
            "type": "access",
            "jti": secrets.token_urlsafe(16)  # Unique token ID
        }
        
        if additional_claims:
            payload.update(additional_claims)
        
        return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)
    
    @staticmethod
    def create_refresh_token(user_id: int) -> str:
        """Create refresh token with longer expiry"""
        now = datetime.utcnow()
        expire = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
        
        payload = {
            "sub": str(user_id),
            "exp": expire,
            "iat": now,
            "type": "refresh",
            "jti": secrets.token_urlsafe(16)
        }
        
        return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)
    
    @staticmethod
    def decode_token(token: str) -> Optional[dict]:
        """Decode and validate token"""
        try:
            payload = jwt.decode(
                token, 
                settings.secret_key, 
                algorithms=[settings.algorithm]
            )
            return payload
        except JWTError:
            return None
    
    @staticmethod
    async def is_token_blacklisted(jti: str) -> bool:
        """Check if token is blacklisted"""
        redis = await get_redis()
        result = await redis.exists(f"blacklist:{jti}")
        return bool(result)
    
    @staticmethod
    async def blacklist_token(jti: str, expires_in: int):
        """Add token to blacklist"""
        redis = await get_redis()
        await redis.setex(f"blacklist:{jti}", expires_in, "1")
    
    @staticmethod
    async def validate_token(token: str, token_type: str = "access") -> Optional[dict]:
        """Full token validation including blacklist check"""
        payload = TokenManager.decode_token(token)
        if not payload:
            return None
        
        # Check token type
        if payload.get("type") != token_type:
            return None
        
        # Check blacklist
        jti = payload.get("jti")
        if jti and await TokenManager.is_token_blacklisted(jti):
            return None
        
        return payload


class SessionManager:
    """User session management"""
    
    @staticmethod
    async def create_session(user_id: int, device_info: dict = None) -> str:
        """Create new session"""
        session_id = secrets.token_urlsafe(32)
        redis = await get_redis()
        
        session_data = {
            "user_id": user_id,
            "created_at": int(time.time()),
            "device_info": device_info or {}
        }
        
        # Store session for 30 days
        await redis.hset(f"session:{session_id}", mapping=session_data)
        await redis.expire(f"session:{session_id}", 30 * 24 * 60 * 60)
        
        return session_id
    
    @staticmethod
    async def get_session(session_id: str) -> Optional[dict]:
        """Get session data"""
        redis = await get_redis()
        data = await redis.hgetall(f"session:{session_id}")
        return data if data else None
    
    @staticmethod
    async def delete_session(session_id: str):
        """Delete session"""
        redis = await get_redis()
        await redis.delete(f"session:{session_id}")
    
    @staticmethod
    async def get_user_sessions(user_id: int) -> list:
        """Get all active sessions for user"""
        redis = await get_redis()
        # This would require maintaining a user->sessions mapping
        # Simplified version
        return []
    
    @staticmethod
    async def limit_concurrent_sessions(user_id: int, max_sessions: int = 3) -> bool:
        """Check and limit concurrent sessions"""
        redis = await get_redis()
        user_sessions_key = f"user_sessions:{user_id}"
        
        current_count = await redis.scard(user_sessions_key)
        if current_count >= max_sessions:
            return False
        
        return True


class PasswordResetManager:
    """Secure password reset flow"""
    
    RESET_TOKEN_EXPIRE_MINUTES = 15
    MAX_RESET_ATTEMPTS = 3
    RESET_COOLDOWN_MINUTES = 15
    
    @staticmethod
    def create_reset_token(user_id: int) -> str:
        """Create password reset token"""
        now = datetime.utcnow()
        expire = now + timedelta(minutes=PasswordResetManager.RESET_TOKEN_EXPIRE_MINUTES)
        
        payload = {
            "sub": str(user_id),
            "exp": expire,
            "iat": now,
            "type": "password_reset",
            "jti": secrets.token_urlsafe(16)
        }
        
        return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)
    
    @staticmethod
    async def check_reset_attempts(user_id: int) -> tuple:
        """Check if user has too many reset attempts"""
        redis = await get_redis()
        key = f"reset_attempts:{user_id}"
        
        attempts = await redis.get(key)
        if attempts and int(attempts) >= PasswordResetManager.MAX_RESET_ATTEMPTS:
            ttl = await redis.ttl(key)
            return False, f"Too many attempts. Try again in {ttl // 60} minutes"
        
        return True, None
    
    @staticmethod
    async def record_reset_attempt(user_id: int):
        """Record failed reset attempt"""
        redis = await get_redis()
        key = f"reset_attempts:{user_id}"
        
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, PasswordResetManager.RESET_COOLDOWN_MINUTES * 60)
    
    @staticmethod
    async def clear_reset_attempts(user_id: int):
        """Clear reset attempts after successful reset"""
        redis = await get_redis()
        await redis.delete(f"reset_attempts:{user_id}")


__all__ = ['TokenManager', 'SessionManager', 'PasswordResetManager']
