#!/bin/bash
# git pull sonrası her deploy için çalıştır
# Kullanım: bash deploy.sh

set -e

REPO_DIR="/var/www/teqlif"

echo "=== Teqlif Deploy ==="

# Bağımlılıkları güncelle
echo "Bağımlılıklar güncelleniyor..."
$REPO_DIR/venv/bin/pip install -q -r $REPO_DIR/backend/requirements.txt

# Nginx config güncelle (değişmişse)
cp $REPO_DIR/deploy/nginx/teqlif.com.conf /etc/nginx/sites-available/teqlif.com
nginx -t && systemctl reload nginx

# Servisi yeniden başlat
echo "Servis yeniden başlatılıyor..."
systemctl restart teqlif

echo "=== Deploy tamamlandı ==="
systemctl status teqlif --no-pager
