#!/usr/bin/env bash
# deploy/scale/V1.4/node3/resources/certbot_node3.sh
# V1.4 Staging (Node3) için SSL Sertifika + Nginx Kurulum Scripti
set -euo pipefail

DOMAIN_LIVE="live-staging.teqlif.com"
DOMAIN_MINIO="minio-staging.teqlif.com"
EMAIL="tucibeyin@gmail.com"

echo "==> V1.4 Staging SSL İstemi Başlıyor..."
echo "Hedefler: $DOMAIN_LIVE, $DOMAIN_MINIO"

# 80 portunu boşalt
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop livekit 2>/dev/null || true

# Certbot kurulu değilse kur
if ! command -v certbot &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y certbot
fi

# Standalone modda sertifika al (CF DNS Only olmalı!)
sudo certbot certonly --standalone \
  -d "$DOMAIN_LIVE" -d "$DOMAIN_MINIO" \
  --non-interactive --agree-tos -m "$EMAIL" \
  || { echo "HATA: Sertifika alınamadı. live-staging ve minio-staging DNS kayıtlarının CF 'DNS Only' olduğundan emin ol."; exit 1; }

echo "=========================================================="
echo " SSL Sertifikaları alındı!"
echo " Cert: /etc/letsencrypt/live/$DOMAIN_LIVE/fullchain.pem"
echo " Key:  /etc/letsencrypt/live/$DOMAIN_LIVE/privkey.pem"
echo "=========================================================="

CERT_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/privkey.pem"

# Nginx kurulu değilse kur
if ! command -v nginx &>/dev/null; then
    sudo apt-get install -y nginx
fi

# Nginx SSL proxy konfigürasyonu
cat <<EOF | sudo tee /etc/nginx/sites-available/staging_edge
server {
    listen 443 ssl;
    server_name $DOMAIN_LIVE;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:7880;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN_MINIO;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:9010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 1G;
    }
}

server {
    listen 80;
    server_name $DOMAIN_LIVE $DOMAIN_MINIO;
    return 301 https://\$host\$request_uri;
}
EOF

sudo ln -sf /etc/nginx/sites-available/staging_edge /etc/nginx/sites-enabled/staging_edge
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl start livekit 2>/dev/null || true

echo "=========================================================="
echo " ✅ Node3 Staging SSL Kurulumu Tamamlandı!"
echo " LiveKit: wss://$DOMAIN_LIVE"
echo " MinIO:   https://$DOMAIN_MINIO"
echo "=========================================================="
