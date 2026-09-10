#!/usr/bin/env bash
# deploy/scale/resources/bootstrap_node1.sh
# node1 (OVH Paris) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, .env değerleri.
# NOT: livekit, minio, postgresql, redis ayrıca kurulmalı — bu script sadece
#      teqlif uygulama katmanını ve izleme bileşenlerini kurar.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SCALE_VERSION="V1.2"
SYSTEMD_SRC="$REPO/deploy/scale/$SCALE_VERSION/node1/systemd"
RESOURCES="$REPO/deploy/scale/resources"
VENV="$REPO/venv"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO: $REPO"
echo "==> Scale version: $SCALE_VERSION"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri..."
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip

# ── Python venv ───────────────────────────────────────────────────────────────
echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$RESOURCES/node1_production_requirements.txt"

# ── Log dizini ────────────────────────────────────────────────────────────────
echo "==> Log dizini..."
sudo mkdir -p /var/log/teqlif
sudo chown "$USER:$USER" /var/log/teqlif
if [[ ! -L "$REPO/logs" ]]; then
  ln -s /var/log/teqlif "$REPO/logs"
fi

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
sudo cp "$REPO/deploy/scale/$SCALE_VERSION/node1/promtail-config.yml" /etc/promtail-config.yml

# ── systemd servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri..."
SERVICES=(teqlif teqlif-staging teqlif-worker teqlif-worker-critical node_exporter promtail)
for svc in "${SERVICES[@]}"; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
# redis-backup timer
sudo cp "$SYSTEMD_SRC/redis-backup.service" /etc/systemd/system/
sudo cp "$SYSTEMD_SRC/redis-backup.timer"   /etc/systemd/system/
sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc"
done
sudo systemctl enable redis-backup.timer

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp   comment 'SSH'       2>/dev/null || true
sudo ufw allow 51820/udp comment 'WireGuard' 2>/dev/null || true
# API port'ları sadece gateway WireGuard IP'sinden
sudo ufw allow in on wg0 from 10.10.0.2 to any port 8000 proto tcp comment 'API prod — gateway' 2>/dev/null || true
sudo ufw allow in on wg0 from 10.10.0.2 to any port 8001 proto tcp comment 'API staging — gateway' 2>/dev/null || true
# Redis — node2 AI proxy'den
sudo ufw allow in on wg0 from 10.10.0.3 to any port 6379 proto tcp comment 'Redis — node2' 2>/dev/null || true
sudo ufw --force enable

echo ""
echo "Bootstrap tamamlandi."
echo ""
echo "Kalan manuel adimlar:"
echo "  1. WireGuard: sudo bash -c 'wg genkey | tee /etc/wireguard/node1_private.key | wg pubkey > /etc/wireguard/node1_public.key'"
echo "  2. wg0.conf yaz ve 'sudo systemctl enable --now wg-quick@wg0' calistir"
echo "  3. .env degerlerini doldur: $RESOURCES/.env.node1.production"
echo "  4. Servisleri baslat: sudo systemctl start teqlif teqlif-staging teqlif-worker teqlif-worker-critical"
echo "  5. node_exporter ve promtail: sudo systemctl start node_exporter promtail"
echo "  6. livekit, minio, postgresql, redis ayrica kurulmali"
