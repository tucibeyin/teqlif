#!/usr/bin/env bash
# deploy/scale/V1.4/node4/resources/certbot_node4.sh
# V1.4 Edge 2 (Node4) için Standalone SSL Sertifika Scripti
set -euo pipefail

DOMAIN_LIVE="live2.teqlif.com"
DOMAIN_MINIO="minio2.teqlif.com"
EMAIL="tucibeyin@gmail.com"

echo "==> V1.4 Edge 2 SSL İstemi Başlıyor..."
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

# Sertifikalar alındığına göre Edge servislerini (MinIO & LiveKit) kur
echo "==> Edge servisleri otomatik kuruluyor..."
WG_IP="10.10.0.6"
ENV_FILE="/var/www/teqlif.com/backend/.env.production"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "HATA: $ENV_FILE bulunamadı! Lütfen önce .env dosyanızı oluşturun."
    exit 1
fi

source "$ENV_FILE"

if [[ -z "${MINIO_ROOT_PASSWORD:-}" || -z "${LIVEKIT_API_SECRET:-}" ]]; then
    echo "HATA: .env.production dosyasında MINIO_ROOT_PASSWORD veya LIVEKIT_API_SECRET eksik!"
    echo "Lütfen /var/www/teqlif.com/backend/.env.production dosyasına güçlü şifreler tanımlayın ve tekrar çalıştırın."
    exit 1
fi

# SSL Sertifika Yolları (Certbot tek bir sertifika oluşturup ilk domainin adıyla kaydeder)
CERT_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/privkey.pem"
MINIO_CERT_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/fullchain.pem"
MINIO_KEY_FILE="/etc/letsencrypt/live/$DOMAIN_LIVE/privkey.pem"

# 1. MinIO Kurulumu (MinIO artık hazır binary sunmadığı için Go ile derliyoruz)
echo "==> Go (Golang) kontrol ediliyor..."
if ! command -v go &> /dev/null; then
    echo "==> Go (Golang) Debian deposundan yükleniyor..."
    sudo apt-get update && sudo apt-get install -y golang
fi

# GOPATH ayarla ve derle
echo "==> MinIO kaynak koddan derleniyor (Bu işlem 1-2 dakika sürebilir)..."
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export CGO_ENABLED=0
go install github.com/minio/minio@latest

sudo mv $GOPATH/bin/minio /usr/local/bin/
sudo chmod +x /usr/local/bin/minio
echo "✅ MinIO başarıyla derlendi ve kuruldu!"

sudo mkdir -p /var/lib/minio
sudo chown -R tucibeyin:tucibeyin /var/lib/minio

MINIO_CERTS_DIR="/home/tucibeyin/.minio/certs"
sudo mkdir -p "$MINIO_CERTS_DIR"
sudo ln -sf "$MINIO_CERT_FILE" "$MINIO_CERTS_DIR/public.crt"
sudo ln -sf "$MINIO_KEY_FILE" "$MINIO_CERTS_DIR/private.key"
sudo chown -R tucibeyin:tucibeyin /home/tucibeyin/.minio

cat <<EOF | sudo tee /etc/systemd/system/minio.service
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
User=tucibeyin
Group=tucibeyin
Environment="MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin}"
Environment="MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}"
Environment="MINIO_SERVER_URL=https://$DOMAIN_MINIO:9010"
ExecStart=/usr/local/bin/minio server /var/lib/minio --address $WG_IP:9010 --console-address $WG_IP:9011 --certs-dir $MINIO_CERTS_DIR
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 2. LiveKit Kurulumu
echo "==> LiveKit kuruluyor..."
curl -sSL https://get.livekit.io | bash
echo "✅ LiveKit başarıyla kuruldu!"
sudo mkdir -p /etc/livekit

cat <<EOF | sudo tee /etc/livekit/livekit.yaml
port: 7880
prometheus_port: 7881

rtc:
  port_range_start: 50000
  port_range_end: 60000
  udp_port: 7882
  tcp_port: 7882
  use_external_ip: true
  node_ip: "51.75.74.124"

turn:
  enabled: true
  domain: "$DOMAIN_LIVE"
  cert_file: "$CERT_FILE"
  key_file: "$KEY_FILE"
  tls_port: 5349
  udp_port: 3478

keys:
  ${LIVEKIT_API_KEY:-devkey}: "${LIVEKIT_API_SECRET}"

logging:
  level: info
  json: false
EOF

cat <<EOF | sudo tee /etc/systemd/system/livekit.service
[Unit]
Description=LiveKit Server
After=network.target

[Service]
ExecStart=/usr/local/bin/livekit-server --config /etc/livekit/livekit.yaml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 3. Nginx Reverse Proxy
echo "==> Nginx yapılandırılıyor..."
sudo apt-get install -y nginx
cat <<EOF | sudo tee /etc/nginx/sites-available/edge_services
server {
    listen 443 ssl;
    server_name $DOMAIN_LIVE;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;

    location / {
        proxy_pass http://localhost:7880;
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

    ssl_certificate $MINIO_CERT_FILE;
    ssl_certificate_key $MINIO_KEY_FILE;

    location / {
        proxy_pass http://$WG_IP:9010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 1G;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/edge_services /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

# 4. Servisleri Başlat
echo "==> Servisler başlatılıyor..."
sudo systemctl daemon-reload
sudo systemctl enable --now minio livekit

echo "========================================================================="
echo " ✅ Node4 (Edge 2) Kurulumu Tamamlandı!"
echo " MinIO S3 URL:  https://$DOMAIN_MINIO"
echo " LiveKit URL:   wss://$DOMAIN_LIVE"
echo "========================================================================="
