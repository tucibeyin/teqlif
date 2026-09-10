#!/usr/bin/env bash
# deploy/scale/resources/certbot_gateway.sh
# gateway'de çalıştır — Let's Encrypt SSL sertifikası al ve nginx'e uygula.
# Ön koşul: DNS A kayıtları gateway'e işaret etmeli, nginx çalışıyor olmalı.
# Idempotent: sertifika zaten varsa yenilemez (certbot kendi halleder).
set -euo pipefail

DOMAINS=(-d teqlif.com -d www.teqlif.com -d staging.teqlif.com)
EMAIL="tucibeyin@gmail.com"

echo "==> certbot kuruluyor..."
sudo apt install -y certbot python3-certbot-nginx

echo "==> SSL sertifikası alınıyor..."
sudo certbot --nginx "${DOMAINS[@]}" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --redirect \
  --non-interactive

echo "==> nginx test + reload..."
sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "SSL sertifikası alındı."
echo "Otomatik yenileme: sudo systemctl status certbot.timer"
echo "Manuel yenileme:   sudo certbot renew --dry-run"
