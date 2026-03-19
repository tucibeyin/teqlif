# Input validation and sanitization
import re
import bleach
from typing import Optional

ALLOWED_TAGS = ['p', 'br', 'strong', 'em', 'u']


class SecureTextField:
    @staticmethod
    def sanitize_html(dirty: str) -> str:
        if not dirty:
            return ""
        return bleach.clean(dirty, tags=ALLOWED_TAGS, strip=True)

    @staticmethod
    def strip_scripts(html: str) -> str:
        if not html:
            return ""
        html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
        html = re.sub(r'javascript:', '', html, flags=re.IGNORECASE)
        html = re.sub(r'on\w+\s*=', '', html, flags=re.IGNORECASE)
        return html

    @staticmethod
    def escape_html(text: str) -> str:
        if not text:
            return ""
        return (text.replace("&", "&").replace('"', """).replace("'", "&#x27;").replace(">", ">").replace("<", "<"))


class SecureInputValidator:
    USER_RE = r'^[a-zA-Z0-9_]{3,50}$'
    CAT_RE = r'^[a-z0-9-]+$'
    PHONE_RE = r'^\+?[0-9]{10,15}$'
    URL_RE = r'^https?://[^\s/$.?#].[^\s]*$'

    @classmethod
    def validate_username(cls, u: str) -> tuple:
        if not u:
            return False, "Required"
        if len(u) < 3 or len(u) > 50:
            return False, "3-50 chars"
        if not re.match(cls.USER_RE, u):
            return False, "Invalid format"
        return True, None

    @classmethod
    def validate_category(cls, c: str) -> tuple:
        if not c:
            return True, None
        if not re.match(cls.CAT_RE, c):
            return False, "Invalid"
        return True, None

    @classmethod
    def validate_price(cls, p: float) -> tuple:
        if p < 0 or p > 10000000:
            return False, "Invalid price"
        return True, None

    @classmethod
    def validate_phone(cls, p: str) -> tuple:
        if not p:
            return True, None
        if not re.match(cls.PHONE_RE, p):
            return False, "Invalid phone"
        return True, None

    @classmethod
    def validate_url(cls, u: str) -> tuple:
        if not u:
            return True, None
        if not re.match(cls.URL_RE, u):
            return False, "Invalid URL"
        return True, None


class FileUploadSecurity:
    IMG_TYPES = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'}
    DOC_TYPES = {'application/pdf'}
    MAX_IMG = 10 * 1024 * 1024
    MAX_DOC = 50 * 1024 * 1024

    @classmethod
    def validate_type(cls, ct: str, cat: str = 'image') -> tuple:
        allowed = cls.IMG_TYPES if cat == 'image' else cls.DOC_TYPES
        if ct not in allowed:
            return False, f"Not allowed: {ct}"
        return True, None

    @classmethod
    def validate_size(cls, size: int, cat: str = 'image') -> tuple:
        max_sz = cls.MAX_IMG if cat == 'image' else cls.MAX_DOC
        if size > max_sz:
            return False, f"Too large. Max: {max_sz // (1024*1024)}MB"
        return True, None

    @classmethod
    def safe_filename(cls, name: str) -> bool:
        if '..' in name or '/' in name or '\\' in name:
            return False
        if name.startswith('.'):
            return False
        if re.search(r'[^\w\s.-]', name):
            return False
        return True


class SQLInjectionProtection:
    SQL_KW = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'DROP', 'CREATE', 'ALTER', 'EXEC', 'UNION']

    @classmethod
    def has_sql(cls, val: str) -> bool:
        if not val:
            return False
        return any(kw in val.upper() for kw in cls.SQL_KW)

    @classmethod
    def sanitize_like(cls, val: str) -> str:
        if not val:
            return ""
        return val.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')


__all__ = ['SecureTextField', 'SecureInputValidator', 'FileUploadSecurity', 'SQLInjectionProtection']
