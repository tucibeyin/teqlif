#!/usr/bin/env bash
# deploy/scale/V1.4/gateway/resources/bootstrap_gateway.sh
# gateway (netcup GmbH) — Nginx Reverse Proxy & SSL Termination
# Idempotent: V1.4 Generic Pathing kuralına uyar.
set -euo pipefail

# -- V1.4 Jenerik Yol (Generic Path) Kuralı --
RESOURCES_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$RESOURCES_DIR/../../../../.." && pwd)"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO Root: $REPO"
echo "==> Resources Dir: $RESOURCES_DIR"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri (Gateway profili)..."
sudo apt update -q
sudo apt install -y ufw wireguard unzip nginx certbot python3-certbot-nginx fail2ban rsync

# ── UFW (Güvenlik Duvarı) ─────────────────────────────────────────────────────
echo "==> UFW yapılandırması..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 80/tcp       # HTTP
sudo ufw allow 443/tcp      # HTTPS
sudo ufw allow 51820/udp    # WireGuard
sudo ufw --force enable

# ── WireGuard (Mesh Network) ──────────────────────────────────────────────────
echo "==> WireGuard ağı (Mesh) yapılandırılıyor..."
if [[ -f "$RESOURCES_DIR/wg0.conf" ]]; then
  sudo mkdir -p /etc/wireguard
  sudo cp "$RESOURCES_DIR/wg0.conf" /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf
  
  if grep -q "<GATEWAY_PRIVATE_KEY>" /etc/wireguard/wg0.conf; then
    echo "==> Otomatik WireGuard Anahtarı Üretiliyor..."
    sudo apt-get install -y -q wireguard-tools
    PRIV_KEY=$(wg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
    sudo sed -i "s|<GATEWAY_PRIVATE_KEY>|$PRIV_KEY|" /etc/wireguard/wg0.conf
    echo "=================================================================="
    echo " 🚨 DİKKAT: Gateway için YENİ WireGuard Public Key üretildi! 🚨"
    echo " PUBLIC KEY: \"$PUB_KEY\""
    echo " Lütfen bu anahtarı diğer sunucularda wg0.conf içindeki Gateway [Peer] kısmına kopyalayın!"
    echo "=================================================================="
  fi
  
  sudo systemctl enable --now wg-quick@wg0 || echo "Uyarı: WireGuard başlatılamadı."
else
  echo "Uyarı: wg0.conf bulunamadı, WireGuard ağı kurulamadı!"
fi

# ── Nginx Temizliği ve V1.4 Konfigürasyonu ────────────────────────────────────
echo "==> Eski Nginx ayarları temizleniyor ve V1.4 Gateway konfigürasyonu kuruluyor..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-available/default
# Ana konfigürasyonu kopyala
sudo cp "$RESOURCES_DIR/teqlif_gateway.conf" /etc/nginx/nginx.conf
# Routing (Proxy) Konfigürasyonunu kopyala
sudo cp "$RESOURCES_DIR/teqlif.com.conf" /etc/nginx/sites-available/teqlif.com.conf
sudo ln -sf /etc/nginx/sites-available/teqlif.com.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# ── node_exporter & promtail ──────────────────────────────────────────────────
echo "==> Binery kurulumları..."
if ! /usr/local/bin/node_exporter --version 2>&1 | grep -q "$NODE_EXPORTER_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | tar xz -C "$TMP"
  sudo mv "$TMP/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf "$TMP"
fi

if ! /usr/local/bin/promtail --version 2>&1 | grep -q "$PROMTAIL_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/promtail.zip" "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
  unzip -q "$TMP/promtail.zip" promtail-linux-amd64 -d "$TMP"
  sudo mv "$TMP/promtail-linux-amd64" /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail
  rm -rf "$TMP"
fi

# ── Systemd Servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri (node_exporter, promtail)..."
SERVICES=(node_exporter promtail)
for svc in "${SERVICES[@]}"; do
  if [[ -f "$REPO/deploy/scale/V1.3/gateway/systemd/${svc}.service" ]]; then
    sudo cp "$REPO/deploy/scale/V1.3/gateway/systemd/${svc}.service" "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
  sudo systemctl enable "$svc" 2>/dev/null || true
  sudo systemctl restart "$svc" 2>/dev/null || true
done
sudo systemctl enable nginx 2>/dev/null || true
sudo systemctl restart nginx 2>/dev/null || true

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo apt-get autoremove -y -q
sudo apt-get clean -q

echo "=============================================="
echo " Gateway Bootstrap Tamamlandı!"
echo " V1.4 Nginx upstream yapılandırmalarının (Node5'e doğru)"
echo " yapılması için 'certbot_gateway.sh' çalıştırılmalıdır."
echo "=============================================="
