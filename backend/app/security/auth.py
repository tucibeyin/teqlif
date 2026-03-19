"""
Güvenli kimlik doğrulama entegrasyonu
Admin şifre hash'leme ve güvenli authentication utilities
"""

import bcrypt
import secrets
from passlib.context import CryptContext
from app.config import settings

# Admin şifre kontrol için özel context
admin_pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AdminSecurity:
    """Administrator şifre güvenliği yönetimi"""
    
    def __init__(self):
        """
        Admin şifre güvenliği setup
        
        admin_password değeri artık hash olarak .env'de olmalı:
        ADMIN_PASSWORD_HASH=$2b$12$salt_hash_value
        """
        pass
    
    @classmethod
    def hash_password(cls, password: str) -> str:
        """
        Administrator şifresini güvenli şekilde hash'ler

        Args:
            password (str): Admin şifre

        Returns:
            str: Bcrypt hash'lenmiş şifre
        """
        return admin_pwd_ctx.hash(password)
    
    def verify_admin_password(self, password: str, stored_hash: str = None) -> bool:
        """
        Admin şifresini kontrol eder
        
        Args:
            password (str): Girilen şifre
            stored_hash (str): Kayıtlı hash (fallback: settings.admin_password_hash)
            
        Returns:
            bool: Şifre doğru mu
        """
        if stored_hash is None:
            stored_hash = settings.admin_password_hash
        
        if not stored_hash:
            # settings.admin_password_hash boşsa, eski düz metin admin_password ile dene
            if settings.admin_password:
                return password == settings.admin_password
            return False
        
        if not stored_hash.startswith('$2b$'):
            # Legacy düz metin kontrolü (geçici uyumluluk)
            return False
        
        return admin_pwd_ctx.verify(password, stored_hash)
    
    @staticmethod
    def generate_temp_admin_access() -> str:
        """
        Geçici admin erişim token'i üretir (backup için)
        
        Returns:
            str: 32 karakter güvenli token
        """
        return secrets.token_urlsafe(32)

class PasswordPolicy:
    """Kullanıcı şifre güvenlik politikası"""
    
    MIN_LENGTH = 8
    MAX_LENGTH = 128
    REQUIRE_UPPERCASE = True
    REQUIRE_LOWERCASE = True
    REQUIRE_DIGITS = True
    REQUIRE_SPECIAL = True
    RESERVED_PASSWORDS = ['password123', 'admin', '123456']
    
    @classmethod
    def validate_password(cls, password: str) -> tuple[bool, str | None]:
        """
        Şifre güvenlik politikası kontrolü
        
        Args:
            password (str): Şifre
            
        Returns:
            tuple[bool, str | None]: (geçerli_mi, hata_mesajı)
        """
        if len(password) < cls.MIN_LENGTH:
            return False, f"Şifre en az {cls.MIN_LENGTH} karakter olmalı"
        
        if len(password) > cls.MAX_LENGTH:
            return False, f"Şifre en fazla {cls.MAX_LENGTH} karakter olmalı"
        
        if cls.REQUIRE_UPPERCASE and not any(c.isupper() for c in password):
            return False, "Şifre en az bir büyük harf içermeli"
        
        if cls.REQUIRE_LOWERCASE and not any(c.islower() for c in password):
            return False, "Şifre en az bir küçük harf içermeli"
        
        if cls.REQUIRE_DIGITS and not any(c.isdigit() for c in password):
            return False, "Şifre en az bir rakam içermeli"
        
        if cls.REQUIRE_SPECIAL and not any(c in '!@#$%^&*()_+-=[]{}|;:,.<>?' for c in password):
            return False, "Şifre özel karakter içermeli"
        
        if password.lower() in [p.lower() for p in cls.RESERVED_PASSWORDS]:
            return False, "Bu şifre kullanılamaz"
        
        return True, None

# Admin setup script için helper fonksiyonları
def setup_admin_security():
    """
    Administrator güvenlik setup script
    Bu script terminalden koşularak admin şifre hash'i oluşturur
    """
    import getpass
    
    print("\n🔒 Admin şifre güvenliği setup\n")
    password = getpass.getpass("Yönetici şifresi: ")
    confirm_password = getpass.getpass("Şifreyi tekrar girin: ")
    
    if password != confirm_password:
        print("❌ Şifreler eşleşmiyor!")
        return False
    
    if not password:
        print("❌ Şifre boş olamaz!")
        return False
    
    validation_result, error = PasswordPolicy.validate_password(password)
    if not validation_result:
        print(f"❌ Şifre güvenlik politikasına uymuyor: {error}")
        return False
    
    password_hash = AdminSecurity.hash_password(password)
    
    print(f"\n✅ Şifre başarıyla oluşturuldu!")
    print("\nAşağıdaki değeri .env dosyanıza ekleyin:")
    print(f"ADMIN_PASSWORD_HASH={password_hash}")
    print("\nDeprecated: eski admin şifresi kullanımdan kaldırılıyor")
    
    return password_hash

if __name__ == "__main__":
    setup_admin_security()