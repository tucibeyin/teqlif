#!/usr/bin/env bash
# deploy/scale/resources/node1/bootstrap_node1.sh
# node1 (OVHcloud SAS, Frankfurt) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, .env değerleri.
# NOT: livekit, minio, postgresql, redis ayrıca kurulmalı.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCALE_VERSION="V1.2"
N1_SRC="$REPO/deploy/scale/$SCALE_VERSION/node1"
SYSTEMD_SRC="$N1_SRC/systemd"
RESOURCES="$REPO/deploy/scale/resources"
NODE1="$RESOURCES/node1"
VENV="$REPO/venv"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO: $REPO"
echo "==> Scale version: $SCALE_VERSION"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri..."
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip nginx

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── Python venv ───────────────────────────────────────────────────────────────
echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$NODE1/node1_production_requirements.txt"

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
sudo cp "$N1_SRC/promtail-config.yml" /etc/promtail-config.yml

# ── nginx fallback (Cloudflare failover için port 443) ───────────────────────
echo "==> nginx fallback (CF failover, port 443)..."
if [[ ! -f /etc/ssl/certs/teqlif-fallback.crt ]]; then
  sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/ssl/private/teqlif-fallback.key \
    -out /etc/ssl/certs/teqlif-fallback.crt \
    -subj "/CN=teqlif.com"
  echo "    Self-signed cert olusturuldu (10 yil gecerli)."
fi
sudo cp "$N1_SRC/nginx/teqlif-fallback.conf" /etc/nginx/sites-available/teqlif-fallback.conf
if [[ ! -L /etc/nginx/sites-enabled/teqlif-fallback.conf ]]; then
  sudo ln -s /etc/nginx/sites-available/teqlif-fallback.conf /etc/nginx/sites-enabled/
fi
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx

# ── Kernel sysctl ────────────────────────────────────────────────────────────
echo "==> sysctl optimizasyonları..."
sudo mkdir -p /etc/sysctl.d
sudo cp "$N1_SRC/sysctl/99-teqlif.conf" /etc/sysctl.d/99-teqlif.conf
sudo sysctl -p /etc/sysctl.d/99-teqlif.conf

# ── journald limitleri ───────────────────────────────────────────────────────
echo "==> journald limitleri..."
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp "$N1_SRC/journald/journald.conf" /etc/systemd/journald.conf.d/99-teqlif.conf
sudo systemctl restart systemd-journald

# ── systemd servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri..."
SERVICES=(teqlif teqlif-staging teqlif-worker teqlif-worker-critical node_exporter promtail)
for svc in "${SERVICES[@]}"; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
sudo cp "$SYSTEMD_SRC/redis-backup.service" /etc/systemd/system/
sudo cp "$SYSTEMD_SRC/redis-backup.timer"   /etc/systemd/system/
sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc"
done
sudo systemctl enable redis-backup.timer

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
  echo "  wg-quick@wg0 baslatildiktan sonra scripti tekrar calistir."
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp    comment 'SSH'        2>/dev/null || true
sudo ufw allow 443/tcp   comment 'HTTPS — CF failover fallback' 2>/dev/null || true
sudo ufw allow 51820/udp comment 'WireGuard'  2>/dev/null || true
CF_IPS=(
  103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
  104.16.0.0/13   104.24.0.0/14   108.162.192.0/18
  131.0.72.0/22   141.101.64.0/18 162.158.0.0/15
  172.64.0.0/13   173.245.48.0/20 188.114.96.0/20
  190.93.240.0/20 197.234.240.0/22 198.41.128.0/17
)
for cidr in "${CF_IPS[@]}"; do
  sudo ufw allow from "$cidr" to any port 80,443 proto tcp comment "CF — $cidr" 2>/dev/null || true
done
sudo ufw allow in on wg0 from 10.10.0.2 to any port 8000 proto tcp comment 'API prod — gateway' 2>/dev/null || true
sudo ufw allow in on wg0 from 10.10.0.2 to any port 8001 proto tcp comment 'API staging — gateway' 2>/dev/null || true
sudo ufw allow in on wg0 from 10.10.0.3 to any port 6379 proto tcp comment 'Redis — node2' 2>/dev/null || true
sudo ufw --force enable

# ── .env izinleri ─────────────────────────────────────────────────────────────
echo "==> .env izinleri..."
chmod 600 "$NODE1/.env.node1.production"
chmod 600 "$NODE1/.env.node1.staging"

echo ""
echo "Bootstrap tamamlandi."
echo ""
echo "Kalan manuel adimlar:"
echo "  1. WireGuard: sudo bash -c 'wg genkey | tee /etc/wireguard/node1_private.key | wg pubkey > /etc/wireguard/node1_public.key'"
echo "  2. wg0.conf yaz ve 'sudo systemctl enable --now wg-quick@wg0' calistir"
echo "  3. .env degerlerini doldur: $NODE1/.env.node1.production"
echo "  4. PostgreSQL tuning uygula:"
echo "     bash $NODE1/apply_pg_tuning.sh"
echo "  5. Tum servisleri baslat:"
echo "     bash $NODE1/node1_services.sh start"
echo "  6. livekit, minio, postgresql, redis ayrica kurulmali"
