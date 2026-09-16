#!/usr/bin/env bash
# deploy/scale/V1.4/gateway/resources/certbot_gateway.sh
# V1.4 Nginx SSL Sertifika ve Upstream (Trafik Yönlendirme) Scripti
set -euo pipefail

DOMAIN="teqlif.com"
API_DOMAIN="api.teqlif.com"
EMAIL="tucibeyin@gmail.com"

# 1. SSL Sertifikalarının Alınması
echo "==> $DOMAIN ve $API_DOMAIN için SSL sertifikaları alınıyor..."
sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" -d "$API_DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || echo "SSL alınamadı veya zaten mevcut."

# 2. V1.4 Upstream Yönlendirmesi (En Önemli Adım!)
# V1.3'te api.teqlif.com -> 10.10.0.1 (Node1) adresine gidiyordu.
# V1.4'te ise api.teqlif.com -> 10.10.0.5 (Node5 - Core) adresine gidecektir.
echo "==> Nginx Upstream yapılandırması V1.4'e göre güncelleniyor (Hedef: Node5 - 10.10.0.5)..."

# Nginx config dosyasındaki upstream adreslerini V1.4 Core IP'si ile değiştirme:
NGINX_CONF="/etc/nginx/sites-available/teqlif.com.conf"
if [[ -f "$NGINX_CONF" ]]; then
  # Eski Node1 (10.10.0.1) referanslarını Node5 (10.10.0.5) ile değiştir (sadece backend/api proxy pass'ları)
  sudo sed -i 's/proxy_pass http:\/\/10.10.0.1:8000/proxy_pass http:\/\/10.10.0.5:8000/g' "$NGINX_CONF"
  echo "=> Nginx sites-available/teqlif.com.conf başarıyla Node5 (10.10.0.5) olarak güncellendi."
else
  echo "=> UYARI: $NGINX_CONF bulunamadı. SSL aldıktan sonra upstream bloklarını manuel 10.10.0.5'e yönlendiriniz."
fi

sudo nginx -t
sudo systemctl reload nginx

echo "=============================================="
echo " V1.4 Gateway Trafik Yönlendirmesi Tamamlandı."
echo " Artık tüm API istekleri Node5 (Core) sunucusuna akacaktır."
echo "=============================================="
