#!/usr/bin/env bash
# deploy/scale/resources/gateway/bootstrap_gateway.sh
# gateway (netcup GmbH, Nürnberg) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, alertmanager.env, nginx SSL sertifikaları.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCALE_VERSION="V1.2"
GW_SRC="$REPO/deploy/scale/$SCALE_VERSION/gateway"
SYSTEMD_SRC="$GW_SRC/systemd"
GATEWAY="$REPO/deploy/scale/resources/gateway"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"
PROMETHEUS_VERSION="2.51.0"
LOKI_VERSION="3.6.7"
ALERTMANAGER_VERSION="0.27.0"

echo "==> REPO: $REPO"
echo "==> Scale version: $SCALE_VERSION"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri..."
sudo apt update -q
sudo apt install -y ufw wireguard unzip nginx

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── Dizin izinleri ───────────────────────────────────────────────────────────
sudo mkdir -p /etc/prometheus /var/lib/prometheus /var/lib/alertmanager
sudo chown tucibeyin:tucibeyin /var/lib/prometheus /var/lib/alertmanager

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> node_exporter $NODE_EXPORTER_VERSION..."
if ! /usr/local/bin/node_exporter --version 2>&1 | grep -q "$NODE_EXPORTER_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" \
    -O "$TMP/ne.tar.gz"
  tar xzf "$TMP/ne.tar.gz" -C "$TMP"
  sudo mv "$TMP/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf "$TMP"
fi

# ── promtail ──────────────────────────────────────────────────────────────────
echo "==> promtail $PROMTAIL_VERSION..."
if ! /usr/local/bin/promtail --version 2>&1 | grep -q "$PROMTAIL_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip" \
    -O "$TMP/promtail.zip"
  unzip -q "$TMP/promtail.zip" -d "$TMP"
  sudo mv "$TMP/promtail-linux-amd64" /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail
  rm -rf "$TMP"
fi
sudo cp "$GW_SRC/promtail-config.yml" /etc/promtail-config.yml

# ── prometheus ────────────────────────────────────────────────────────────────
echo "==> prometheus $PROMETHEUS_VERSION..."
if ! /usr/local/bin/prometheus --version 2>&1 | grep -q "$PROMETHEUS_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
    -O "$TMP/prom.tar.gz"
  tar xzf "$TMP/prom.tar.gz" -C "$TMP"
  sudo mv "$TMP/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus"  /usr/local/bin/
  sudo mv "$TMP/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool"    /usr/local/bin/
  rm -rf "$TMP"
fi
sudo cp "$GW_SRC/prometheus.yml"       /etc/prometheus/prometheus.yml
sudo cp "$GW_SRC/prometheus-rules.yml" /etc/prometheus/prometheus-rules.yml
sudo chown -R tucibeyin:tucibeyin /etc/prometheus

# ── loki ──────────────────────────────────────────────────────────────────────
echo "==> loki $LOKI_VERSION..."
if ! /usr/local/bin/loki --version 2>&1 | grep -q "$LOKI_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" \
    -O "$TMP/loki.zip"
  unzip -q "$TMP/loki.zip" -d "$TMP"
  sudo mv "$TMP/loki-linux-amd64" /usr/local/bin/loki
  sudo chmod +x /usr/local/bin/loki
  rm -rf "$TMP"
fi
sudo mkdir -p /etc/loki
sudo cp "$GW_SRC/loki-config.yml" /etc/loki/config.yml

# ── alertmanager ──────────────────────────────────────────────────────────────
echo "==> alertmanager $ALERTMANAGER_VERSION..."
if ! /usr/local/bin/alertmanager --version 2>&1 | grep -q "$ALERTMANAGER_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz" \
    -O "$TMP/am.tar.gz"
  tar xzf "$TMP/am.tar.gz" -C "$TMP"
  sudo mv "$TMP/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /usr/local/bin/
  rm -rf "$TMP"
fi
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
if [[ ! -f /etc/alertmanager/alertmanager.yml ]]; then
  sudo cp "$GW_SRC/alertmanager.yml.template" /etc/alertmanager/alertmanager.yml
  echo "  UYARI: /etc/alertmanager/alertmanager.yml sıfırdan kopyalandı — gerçek değerleri doldur."
fi

# ── nginx.conf optimizasyonu ─────────────────────────────────────────────────
echo "==> nginx.conf optimizasyonu..."
sudo cp "$GW_SRC/nginx/nginx.conf" /etc/nginx/nginx.conf

# ── nginx site config (teqlif.conf + /cf-health) ─────────────────────────────
echo "==> nginx site config..."
sudo cp "$GW_SRC/nginx/teqlif.conf" /etc/nginx/sites-available/teqlif.conf
if [[ ! -L /etc/nginx/sites-enabled/teqlif.conf ]]; then
  sudo ln -s /etc/nginx/sites-available/teqlif.conf /etc/nginx/sites-enabled/teqlif.conf
fi
if [[ -f "$GW_SRC/nginx/nginx-http-zones.conf" ]]; then
  sudo cp "$GW_SRC/nginx/nginx-http-zones.conf" /etc/nginx/conf.d/nginx-http-zones.conf
fi
sudo nginx -t && sudo systemctl reload nginx 2>/dev/null || true

# ── Kernel sysctl ────────────────────────────────────────────────────────────
echo "==> sysctl optimizasyonları..."
sudo mkdir -p /etc/sysctl.d
sudo cp "$GW_SRC/sysctl/99-teqlif.conf" /etc/sysctl.d/99-teqlif.conf
sudo sysctl -p /etc/sysctl.d/99-teqlif.conf

# ── journald limitleri ───────────────────────────────────────────────────────
echo "==> journald limitleri..."
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp "$GW_SRC/journald/journald.conf" /etc/systemd/journald.conf.d/99-teqlif.conf
sudo systemctl restart systemd-journald

# ── systemd servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri..."
for svc in node_exporter promtail prometheus loki alertmanager; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
sudo systemctl daemon-reload
for svc in node_exporter promtail prometheus loki alertmanager; do
  sudo systemctl enable "$svc"
done

# ── WireGuard: node2 peer (V1.2) ─────────────────────────────────────────────
NODE2_PUBKEY="t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k="
NODE2_ENDPOINT="198.12.123.33:51820"
echo "==> WireGuard: node2 peer..."
if sudo wg show wg0 2>/dev/null | grep -q "$NODE2_PUBKEY"; then
  echo "    node2 peer zaten mevcut, atlaniyor."
elif sudo systemctl is-active wg-quick@wg0 &>/dev/null; then
  sudo wg set wg0 peer "$NODE2_PUBKEY" \
    allowed-ips 10.10.0.3/32 \
    endpoint "$NODE2_ENDPOINT" \
    persistent-keepalive 25
  printf '\n[Peer]\n# node2 — VPSHostingService.co Buffalo\nPublicKey = %s\nAllowedIPs = 10.10.0.3/32\nEndpoint = %s\nPersistentKeepalive = 25\n' \
    "$NODE2_PUBKEY" "$NODE2_ENDPOINT" | sudo tee -a /etc/wireguard/wg0.conf > /dev/null
  echo "    node2 peer eklendi ve wg0.conf'a yazildi."
else
  echo "  UYARI: wg0 servisi aktif degil — node2 peer atlaniyor."
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp    comment 'SSH'      2>/dev/null || true
sudo ufw allow 80/tcp    comment 'HTTP'     2>/dev/null || true
sudo ufw allow 443/tcp   comment 'HTTPS'    2>/dev/null || true
sudo ufw allow 51820/udp comment 'WireGuard' 2>/dev/null || true
sudo ufw allow in on wg0 to any port 3100 proto tcp comment 'Loki — mesh' 2>/dev/null || true
sudo ufw --force enable

echo ""
echo "Bootstrap tamamlandi."
echo ""
# ── .env izinleri ─────────────────────────────────────────────────────────────
echo "==> .env izinleri..."
chmod 600 "$GATEWAY/.env.gateway.production"

echo "Kalan manuel adimlar:"
echo "  1. WireGuard: wg0.conf yaz, 'sudo systemctl enable --now wg-quick@wg0' calistir"
echo "  2. .env degerlerini doldur: $GATEWAY/.env.gateway.production"
echo "     (TELEGRAM_BOT_TOKEN ve TELEGRAM_CHAT_ID)"
echo "  3. alertmanager.yml kopyala:"
echo "     sudo cp deploy/scale/V1.2/gateway/alertmanager.yml.template /etc/alertmanager/alertmanager.yml"
echo "  4. nginx SSL sertifikasi al:"
echo "     bash $GATEWAY/certbot_gateway.sh"
echo "  5. Grafana ayri kurulmali (apt repo veya binary)"
echo "  6. Tum servisleri baslat:"
echo "     bash $GATEWAY/gateway_services.sh start"
