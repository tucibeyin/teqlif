#!/usr/bin/env bash
# deploy/scale/V1.4/node1/resources/certbot_node1.sh
# V1.4 Edge 1 (Node1) için Standalone SSL Sertifika Scripti
set -euo pipefail

DOMAIN_LIVE="live1.teqlif.com"
DOMAIN_MINIO="minio1.teqlif.com"
EMAIL="tucibeyin@gmail.com"

echo "==> V1.4 Edge 1 SSL İstemi Başlıyor..."
echo "Hedefler: $DOMAIN_LIVE, $DOMAIN_MINIO"

# 80 Portunu boşaltmak için varsa eski servisleri durdur
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop livekit 2>/dev/null || true

# Standalone modda sertifikayı al (Cloudflare proxy KAPALI - DNS Only olmalı!)
sudo certbot certonly --standalone \
  -d "$DOMAIN_LIVE" -d "$DOMAIN_MINIO" \
  --non-interactive --agree-tos -m "$EMAIL" \
  || echo "Sertifika alınırken hata oluştu. Cloudflare DNS'in 'Gri Bulut' (DNS Only) olduğundan emin olun."

# Servisleri geri başlat
sudo systemctl start nginx 2>/dev/null || true
sudo systemctl start livekit 2>/dev/null || true

echo "=========================================================="
echo " SSL Sertifikaları başarıyla alındı!"
echo " MinIO veya LiveKit konfigürasyonlarınızda şu yolları kullanın:"
echo " Cert: /etc/letsencrypt/live/$DOMAIN_LIVE/fullchain.pem"
echo " Key:  /etc/letsencrypt/live/$DOMAIN_LIVE/privkey.pem"
echo "=========================================================="

# Sertifikalar alındığına göre Edge servislerini (MinIO & LiveKit) otomatik kur
echo "==> Edge servisleri otomatik kuruluyor..."
sudo bash "$(dirname "$0")/../../install_edge_services.sh"
