#!/usr/bin/env bash
# deploy/scale/resources/bootstrap_node2.sh
# node2 (RackNerd Buffalo) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, .env değerleri.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SCALE_VERSION="V1.2"
SYSTEMD_SRC="$REPO/deploy/scale/$SCALE_VERSION/node2/systemd"
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

# ── Grup üyelikleri (promtail journal okuyabilsin) ────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── Python venv ───────────────────────────────────────────────────────────────
echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install -r "$RESOURCES/node2_production_requirements.txt"

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
sudo cp "$REPO/deploy/scale/$SCALE_VERSION/node2/promtail-config.yml" /etc/promtail-config.yml

# ── systemd servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri..."
for svc in teqlif-ai-proxy node_exporter promtail; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
sudo systemctl daemon-reload
for svc in teqlif-ai-proxy node_exporter promtail; do
  sudo systemctl enable "$svc"
done

# ── WireGuard wg0.conf (private key zaten üretilmişse otomatik yazar) ─────────
# Key üretimi kapsam dışı — önceden çalıştır:
#   sudo bash -c 'wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key'
echo "==> WireGuard wg0.conf..."
if [[ -f /etc/wireguard/node2_private.key ]]; then
  if [[ ! -f /etc/wireguard/wg0.conf ]]; then
    NODE2_PRIV=$(sudo cat /etc/wireguard/node2_private.key)
    printf '[Interface]\nAddress = 10.10.0.3/24\nListenPort = 51820\nPrivateKey = %s\n\n[Peer]\n# node1 — OVH Paris\nPublicKey = JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=\nAllowedIPs = 10.10.0.1/32\nEndpoint = 135.125.175.223:51820\nPersistentKeepalive = 25\n\n[Peer]\n# gateway — Netcup\nPublicKey = 7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=\nAllowedIPs = 10.10.0.2/32\nEndpoint = 94.16.105.135:51820\nPersistentKeepalive = 25\n' \
      "$NODE2_PRIV" | sudo tee /etc/wireguard/wg0.conf > /dev/null
    sudo chmod 600 /etc/wireguard/wg0.conf
    echo "    wg0.conf yazildi."
  else
    echo "    wg0.conf zaten mevcut, atlaniyor."
  fi
  sudo systemctl enable wg-quick@wg0 2>/dev/null || true
  sudo systemctl is-active wg-quick@wg0 &>/dev/null || sudo systemctl start wg-quick@wg0
else
  echo "  UYARI: /etc/wireguard/node2_private.key bulunamadi — WireGuard atlanıyor."
  echo "  Once anahtari olustur:"
  echo "  sudo bash -c 'wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key'"
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp   comment 'SSH'       2>/dev/null || true
sudo ufw allow 51820/udp comment 'WireGuard' 2>/dev/null || true
sudo ufw allow in on wg0 to any port 8080 proto tcp comment 'AI proxy via WireGuard' 2>/dev/null || true
sudo ufw allow in on wg0 to any port 9100 proto tcp comment 'node_exporter — gateway' 2>/dev/null || true
sudo ufw --force enable

# ── Hostname ──────────────────────────────────────────────────────────────────
if [[ "$(hostname)" != "node2" ]]; then
  echo "==> Hostname node2 olarak ayarlaniyor..."
  sudo hostnamectl set-hostname node2
fi

# ── .env izinleri ─────────────────────────────────────────────────────────────
echo "==> .env izinleri..."
[[ -f "$RESOURCES/.env.node2.production" ]] && chmod 600 "$RESOURCES/.env.node2.production"

echo ""
echo "Bootstrap tamamlandi."
echo ""
echo "Kalan manuel adimlar:"
echo "  1. WireGuard key yoksa: sudo bash -c 'wg genkey | tee /etc/wireguard/node2_private.key | wg pubkey > /etc/wireguard/node2_public.key'"
echo "     Sonra scripti tekrar calistir — wg0.conf otomatik yazilir."
echo "  2. .env degerlerini doldur: $RESOURCES/.env.node2.production"
echo "  3. Servisleri baslat: sudo systemctl start teqlif-ai-proxy node_exporter promtail"
