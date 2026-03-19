# Data Encryption and GDPR Compliance
# Phase 4: Data Security
import os
import base64
import hashlib
from datetime import datetime, timedelta
from typing import Optional
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from app.config import settings


class FieldEncryption:
    """Encrypt sensitive database fields"""
    
    _fernet: Optional[Fernet] = None
    
    @classmethod
    def get_fernet(cls) -> Fernet:
        if cls._fernet is None:
            # Generate key from secret
            key = settings.secret_key.encode()
            kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=b'teqlif_salt', iterations=100000)
            key = base64.urlsafe_b64encode(kdf.derive(key))
            cls._fernet = Fernet(key)
        return cls._fernet
    
    @classmethod
    def encrypt(cls, data: str) -> str:
        if not data:
            return ""
        f = cls.get_fernet()
        return f.encrypt(data.encode()).decode()
    
    @classmethod
    def decrypt(cls, encrypted_data: str) -> str:
        if not encrypted_data:
            return ""
        try:
            f = cls.get_fernet()
            return f.decrypt(encrypted_data.encode()).decode()
        except Exception:
            return ""


class GDPRCompliance:
    """GDPR compliance helpers"""
    
    # Data retention periods
    MESSAGE_RETENTION_DAYS = 730  # 2 years
    FILE_RETENTION_DAYS = 90  # 90 days
    LOG_RETENTION_DAYS = 365  # 1 year
    SESSION_RETENTION_DAYS = 30
    
    @staticmethod
    def should_delete_message(created_at: datetime) -> bool:
        """Check if message should be deleted based on retention policy"""
        retention_date = datetime.utcnow() - timedelta(days=GDPRCompliance.MESSAGE_RETENTION_DAYS)
        return created_at < retention_date
    
    @staticmethod
    def should_delete_file(created_at: datetime) -> bool:
        """Check if file should be deleted based on retention policy"""
        retention_date = datetime.utcnow() - timedelta(days=GDPRCompliance.FILE_RETENTION_DAYS)
        return created_at < retention_date
    
    @staticmethod
    def get_data_export_template() -> dict:
        """Template for user data export"""
        return {
            "export_date": datetime.utcnow().isoformat(),
            "user_data": {
                "profile": {},
                "listings": [],
                "messages": [],
                "auctions": [],
                "notifications": []
            },
            "privacy_settings": {},
            "consent_history": []
        }
    
    @staticmethod
    def anonymize_data(data: dict) -> dict:
        """Anonymize user data for analytics"""
        anonymized = data.copy()
        if "email" in anonymized:
            email = anonymized["email"]
            if email and "@" in email:
                local, domain = email.split("@", 1)
                anonymized["email"] = f"{local[:2]}***@{domain}"
        if "phone" in anonymized and anonymized["phone"]:
            anonymized["phone"] = "***" + anonymized["phone"][-4:]
        if "full_name" in anonymized:
            anonymized["full_name"] = "***"
        return anonymized


class SecureStorage:
    """Secure file storage helpers"""
    
    @staticmethod
    def generate_secure_filename(original_filename: str) -> str:
        """Generate secure random filename"""
        import uuid
        ext = os.path.splitext(original_filename)[1].lower()
        return f"{uuid.uuid4().hex}{ext}"
    
    @staticmethod
    def get_file_hash(file_path: str) -> str:
        """Calculate file hash for integrity check"""
        sha256 = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256.update(chunk)
        return sha256.hexdigest()
    
    @staticmethod
    def is_safe_path(base_path: str, user_path: str) -> bool:
        """Prevent path traversal attacks"""
        # Resolve paths
        base = os.path.abspath(base_path)
        full = os.path.abspath(os.path.join(base_path, user_path))
        return full.startswith(base)


__all__ = ['FieldEncryption', 'GDPRCompliance', 'SecureStorage']
