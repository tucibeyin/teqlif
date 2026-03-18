#!/usr/bin/env python3
"""
Administrator şifre güvenlik setup script

Kullanım:
    python setup_admin_security.py
    
Bu script yeni admin şifrenizi güvenli şekilde hash'ler ve 
.env dosyanız için gerekli değerleri üretir.
"""

import os
import sys
import getpass
import asyncio
from pathlib import Path

# Project root'e git
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.config import settings
from app.security.auth import AdminSecurity, PasswordPolicy

async def setup_admin_password():
    """Interactive admin şifre setup"""
    print("🔐 Teqlif Admin Güvenlik Setup")
    print("=" * 50)
    
    while True:
        try:
            password = getpass.getpass("\nYönetici şifresi: ")
            if not password:
                print("❌ Şifre boş olamaz!")
                continue
                
            confirm_password = getpass.getpass("Şifreyi tekrar girin: ")
            
            if password != confirm_password:
                print("❌ Şifreler eşleşmiyor! Tekrar deneyin.")
                continue
            
            # Şifre güvenlik kontrolü
            validation_result, error = PasswordPolicy.validate_password(password)
            if not validation_result:
                print(f"❌ Şifre güvenlik politikasına uymuyor: {error}")
                continue
                
            # Şifre hash'leme
            password_hash = AdminSecurity.hash_password(password)
            
            print("\n✅ Şifre başarıyla oluşturuldu!")
            print("\n📝 Aşağıdaki değeri .env dosyanıza ekleyin:")
            print(f"ADMIN_PASSWORD_HASH={password_hash}")
            
            # .env dosyasını güncelleme önerisi
            env_file = Path(".env")
            if env_file.exists():
                old_admin_password = os.getenv("ADMIN_PASSWORD")
                print(f"\n⚠️  Eski ADMIN_PASSWORD değişkenini kaldırın!")
                print("dığer backup yöntemi isterseniz:")
                print(f"# Eski admin şifresi: {old_admin_password[:3]}...")
                
                # Yeni .env satırları
                new_env_lines = [
                    f"# Güncellenen admin şifre ayarları",
                    f"ADMIN_PASSWORD_HASH={password_hash}",
                    f"# eski: ADMIN_PASSWORD=your_old_password"
                ]
                
                # .env güncelleme istemi
                print(f"\n📝 Değişiklik önerisi:")
                for line in new_env_lines:
                    print(line)
                    
                response = input("\n.env dosyasını otomatik güncelleyeyim mi? (Y/n): ")
                if response.lower() != 'n':
                    update_env_file(password_hash)
                    print("✅ .env dosyası güncellendi!")
                else:
                    print("""
Manuel güncelleme için:
1. .env dosyasını açın
2. ADMIN_PASSWORD=... satırını kaldırın
3. ADMIN_PASSWORD_HASH=... şeklinde ekleyin
                    """)
            
            return password_hash
            
        except KeyboardInterrupt:
            print("\n❌ Setup iptal edildi.")
            return None
        except Exception as e:
            print(f"❌ Hata: {e}")
            return None

def update_env_file(password_hash: str):
    """.env dosyasını günceller"""
    env_path = Path(".env")
    
    if not env_path.exists():
        print("⚠️ .env dosyası bulunamadı, oluşturuluyor...")
    
    try:
        # Mevcut .env içeriğini oku
        if env_path.exists():
            with open(env_path, 'r') as f:
                lines = f.readlines()
        else:
            lines = []
        
        # Yeni içeriği hazırla
        new_lines = []
        admin_password_found = False
        
        for line in lines:
            line = line.strip()
            if line.startswith("ADMIN_PASSWORD") and not line.startswith("ADMIN_PASSWORD_"):
                # Eski şifreyi yorum satırı haline getir
                new_lines.append(f"# Eski: {line}")
                admin_password_found = True
            elif line.startswith("ADMIN_PASSWORD_HASH"):
                # Zaten varsa atla
                continue
            elif line.strip():  # Boş satırlar koru
                new_lines.append(line)
        
        # Yeni admin hash'i ekle
        new_lines.append(f"ADMIN_PASSWORD_HASH={password_hash}")
        new_lines.append(f"# Admin şifre güvenlik güncelleme: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        
        with open(env_path, 'w') as f:
            f.write('\n'.join(new_lines))
            f.write('\n')
            
    except Exception as e:
        print(f"❌ .env güncelleme hatası: {e}")

def main():
    """Main setup function"""
    # Admin security kurulumu
    password_hash = asyncio.run(setup_admin_password())
    
    if password_hash:
        print("\n" + "=" * 50)
        print("🚀 Setup tamamlandı!")
        print("Üretim ortamına geçiş için:")
        print("1. .env dosyanızı kontrol edin")
        print("2. Uygulamayı yeniden başlatın")
        print("3. Eski admin şifresini kontrol edin")
        print("=" * 50)
        
        # Test recommendation
        print("\nTest için:")
        print("python test_admin_security.py")
    else:
        print("❌ Setup başarısız!")
        sys.exit(1)

if __name__ == "__main__":
    main()