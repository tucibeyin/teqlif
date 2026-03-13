#!/bin/bash
# VPS'te tek seferlik ilk kurulum scripti
# Kullanım: sudo bash setup.sh

set -e

REPO_DIR="/var/www/teqlif.com"
DOMAIN="teqlif.com"

echo "=== Teqlif VPS Kurulumu ==="

# Sistem paketleri
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv postgresql postgresql-contrib redis-server nginx certbot python3-certbot-nginx git curl

# Proje dizini
mkdir -p $REPO_DIR
mkdir -p $REPO_DIR/uploads

# Repo buraya klonlanmış olmalı (ya da zaten var)
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "HATA: $REPO_DIR bir git reposu değil."
    echo "Önce: git clone https://github.com/tucibeyin/teqlif.git $REPO_DIR"
    exit 1
fi

# Python virtual env
python3 -m venv $REPO_DIR/venv
$REPO_DIR/venv/bin/pip install --upgrade pip
$REPO_DIR/venv/bin/pip install -r $REPO_DIR/backend/requirements.txt

# .env dosyası
if [ ! -f "$REPO_DIR/backend/.env" ]; then
    cp $REPO_DIR/backend/.env.example $REPO_DIR/backend/.env
    echo ""
    echo ">>> $REPO_DIR/backend/.env dosyasını düzenle! (SECRET_KEY, DB şifresi vb.)"
fi

# PostgreSQL veritabanı
echo "PostgreSQL kurulumu..."
sudo -u postgres psql -c "CREATE USER teqlif WITH PASSWORD 'DEGISTIR' CREATEDB;" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE teqlif OWNER teqlif;" 2>/dev/null || true

# Dosya izinleri
chown -R www-data:www-data $REPO_DIR

# Systemd service
cp $REPO_DIR/deploy/systemd/teqlif.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable teqlif

# Nginx
cp $REPO_DIR/deploy/nginx/teqlif.com.conf /etc/nginx/sites-available/teqlif.com
ln -sf /etc/nginx/sites-available/teqlif.com /etc/nginx/sites-enabled/teqlif.com
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# SSL (Let's Encrypt)
echo ""
echo "=== SSL Sertifikası (Let's Encrypt) ==="
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || \
    echo "UYARI: SSL sertifikası alınamadı, DNS ayarlarını kontrol et."

# Servisi başlat
systemctl start teqlif

echo ""
echo "=== Kurulum tamamlandı ==="
echo "Servis durumu: systemctl status teqlif"
echo "Loglar: journalctl -u teqlif -f"
