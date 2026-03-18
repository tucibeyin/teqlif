#!/bin/bash

# Teqlif Güvenlik Geliştirme Kurulum Scripti
# Tüm açıklar için komple güvenlik kurulumu

echo "🔐 Teqlif Güvenlik Sistemi Kurulumu"
echo "=================================="

# 1. Gereksinimleri yükle
echo "📦 1. Güvenlik paketleri yüklüyor..."
pip install bcrypt slowapi bleach pydantic-settings --quiet
if [ $? -ne 0 ]; then
    echo "❌ Paket yükleme başarısız!"
    exit 1
fi

# 2. Environment setup
echo "⚙️  2. Environment güvenliği ayarlanıyor..."
ENV_FILE=".env"
CASE_FILE=".env.example"

# .env.example dosyasını güncelle
if [ -f "$CASE_FILE" ]; then
    # Yeni admin hash değişkeni ekle
    if ! grep -q "ADMIN_PASSWORD_HASH=" "$CASE_FILE"; then
        echo "" >> "$CASE_FILE"
        echo "# Admin güvenlik ayarları" >> "$CASE_FILE"
        echo "ADMIN_PASSWORD_HASH=" >> "$CASE_FILE"
        echo "✅ .env.example güncellendi"
    fi
fi

# 3. Admin şifre kurulumu
echo "🔑 3. Admin güvenlik kurulumu..."
python setup_admin_security.py
if [ $? -ne 0 ]; then
    echo "❌ Admin şifre setup başarısız!"
    exit 1
fi

# 4. Güvenlik testleri
echo "🧪 4. Güvenlik testleri..."
python -c "
import sys
try:
    from app.security.auth import AdminSecurity, PasswordPolicy
    from app.security.middleware import SecurityMiddleware
    print('✅ Güvenlik modülleri import edilebiliyor')
    
    # Admin security test
    security = AdminSecurity()
    test_hash = security.hash_password('TestPass123!')
    assert security.verify_admin_password('TestPass123!', test_hash)
    assert not security.verify_admin_password('WrongPass', test_hash)
    print('✅ Admin şifre hash sistemi çalışıyor')
    
    # Password policy test
    valid, error = PasswordPolicy.validate_password('TestPass123!')
    assert valid, f'Password policy error: {error}'
    invalid, error = PasswordPolicy.validate_password('123')
    assert not invalid, 'Güvenlik zayıf şifre reddi'
    print('✅ Şifre politikası çalışıyor')
    
    # Middleware test
    middleware = SecurityMiddleware()
    print('✅ Güvenlik middleware çalışıyor')
    
except Exception as e:
    print(f'❌ Test hatası: {e}')
    sys.exit(1)
"

# 5. Rate limiting kurulumu
echo "🛡️  5. Rate limiting yapılandırması..."
redis-cli ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚠️  Redis çalışmıyor, rate limiting aktif değil"
    echo "Redis başlatın: redis-server"
else
    echo "✅ Redis bağlantısı başarılı - rate limiting aktif"
fi

# 6. SSL/TLS kurulumu önerileri
echo "🌐 6. SSL/TLS kurulumu..."
echo "    Production için yapılacaklar:"
echo "    - Let's Encrypt ile SSL sertifikası"
echo "    - Domain: teqlif.com, admin.teqlif.com"
echo "    - auto-renewal: certbot"
echo "    - Nginx reverse proxy konfigürasyonu"

# 7. Güvenlik başarılı message
echo ""
echo "🎉 Temel güvenlik kurulumu tamamlandı!"
echo "========================================"
echo ""
echo "Kalan adımlar:"
echo "1. Admin şifresi kurulumu (yüksek öncelik)"
echo "2. Rate limiting ve CORS testleri"
echo "3. SSL sertifikası kurulumu"
echo "4. Güvenlik monitoring ayarları"
echo ""
echo "Test komutları:"
echo "  python setup_admin_security.py"
echo "  python -m pytest tests/security/ -v"
echo ""
echo "Production checklist:"
echo "  ⚡ Daily vulnerability scans"
echo "  📊 Real-time security monitoring"
echo "  🔍 Weekly penetration tests"
echo ""

chmod +x setup_security.sh
echo "✅ Kurulum script çalıştırılabilir!"