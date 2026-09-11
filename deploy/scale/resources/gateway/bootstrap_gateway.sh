#!/usr/bin/env bash
# deploy/scale/resources/gateway/bootstrap_gateway.sh
# gateway (netcup GmbH, Nürnberg) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, nginx SSL sertifikaları.
# Scale V1.3: prometheus/loki/alertmanager node3'e taşındı — gateway yalnızca nginx + node_exporter + promtail çalıştırır.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCALE_VERSION="V1.3"
GW_SRC="$REPO/deploy/scale/$SCALE_VERSION/gateway"
SYSTEMD_SRC="$GW_SRC/systemd"
GATEWAY="$REPO/deploy/scale/resources/gateway"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

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
sudo mkdir -p /var/lib/promtail
sudo chown tucibeyin:tucibeyin /var/lib/promtail

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
for svc in node_exporter promtail; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
sudo systemctl daemon-reload
for svc in node_exporter promtail; do
  sudo systemctl enable "$svc"
done

# ── WireGuard: node2 peer ─────────────────────────────────────────────────────
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
  printf '\n[Peer]\n# node2 — RackNerd Buffalo\nPublicKey = %s\nAllowedIPs = 10.10.0.3/32\nEndpoint = %s\nPersistentKeepalive = 25\n' \
    "$NODE2_PUBKEY" "$NODE2_ENDPOINT" | sudo tee -a /etc/wireguard/wg0.conf > /dev/null
  echo "    node2 peer eklendi."
else
  echo "  UYARI: wg0 servisi aktif degil — node2 peer atlaniyor."
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp    comment 'SSH'      2>/dev/null || true
sudo ufw allow 80/tcp    comment 'HTTP'     2>/dev/null || true
sudo ufw allow 443/tcp   comment 'HTTPS'    2>/dev/null || true
sudo ufw allow 51820/udp comment 'WireGuard' 2>/dev/null || true
# Scale V1.3: node3 Prometheus node_exporter'ı scrape eder — WG IP'de dinle
sudo ufw allow in on wg0 from 10.10.0.4 to any port 9100 proto tcp comment 'node_exporter — node3 Prometheus' 2>/dev/null || true
sudo ufw --force enable

echo ""
echo "Bootstrap tamamlandi."
echo ""
# ── .env izinleri ─────────────────────────────────────────────────────────────
echo "==> .env izinleri..."
chmod 600 "$GATEWAY/.env.gateway.production"

echo "Kalan manuel adimlar:"
echo "  1. WireGuard: wg0.conf yaz, 'sudo systemctl enable --now wg-quick@wg0' calistir"
echo "     node3 [Peer] blogu da wg0.conf'a ekle (task.md Faz 1)"
echo "  2. .env degerlerini doldur: $GATEWAY/.env.gateway.production"
echo "  3. nginx SSL sertifikasi al:"
echo "     bash $GATEWAY/certbot_gateway.sh"
echo "  4. Tum servisleri baslat:"
echo "     bash $GATEWAY/gateway_services.sh start"
