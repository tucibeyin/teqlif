#!/usr/bin/env bash
# deploy/scale/resources/gateway/certbot.sh
# gateway üzerinde Let's Encrypt SSL sertifikası al (certbot --nginx)
# Ön koşul: nginx kurulu ve çalışıyor, DNS kayıtları gateway'e işaret ediyor olmalı.
set -euo pipefail

if ! command -v certbot &>/dev/null; then
  echo "==> certbot kuruluyor..."
  sudo apt install -y certbot python3-certbot-nginx
fi

echo "==> SSL sertifikası alınıyor..."
sudo certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email tucibeyin@gmail.com \
  -d teqlif.com \
  -d www.teqlif.com \
  -d staging.teqlif.com

echo "==> nginx yeniden yükleniyor..."
sudo systemctl reload nginx

echo "Sertifika alındı. Otomatik yenileme için:"
echo "  sudo systemctl status certbot.timer"
