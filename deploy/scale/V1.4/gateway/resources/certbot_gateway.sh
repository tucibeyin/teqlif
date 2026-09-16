#!/usr/bin/env bash
# deploy/scale/V1.4/gateway/resources/certbot_gateway.sh
# V1.4 Nginx SSL Sertifika ve Upstream (Trafik Yönlendirme) Scripti
set -euo pipefail

DOMAIN="teqlif.com"
API_DOMAIN="api.teqlif.com"
STAGING_DOMAIN="staging.teqlif.com"
EMAIL="tucibeyin@gmail.com"

# 1. SSL Sertifikalarının Alınması
echo "==> $DOMAIN, $API_DOMAIN ve $STAGING_DOMAIN için SSL sertifikaları alınıyor..."
sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" -d "$API_DOMAIN" -d "$STAGING_DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || echo "SSL alınamadı veya zaten mevcut."

echo "==> Nginx test ediliyor ve yeniden başlatılıyor..."
sudo nginx -t
sudo systemctl reload nginx

echo "=============================================="
echo " V1.4 Gateway Trafik Yönlendirmesi Tamamlandı."
echo " API istekleri -> Node5 (10.10.0.5:8000)"
echo " Staging istekleri -> Node3 (10.10.0.3:8000)"
echo " Canlı Medya (Bypass) -> Node1 & Node4"
echo "=============================================="
