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
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp # WireGuard
# Nginx'in 10.10.0.0/24 subnetine erişimi WireGuard üzerinden olacaktır.

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
SERVICES=(node_exporter promtail nginx)
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
  sudo systemctl restart "$svc" 2>/dev/null || true
done

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo apt-get autoremove -y -q
sudo apt-get clean -q

echo "=============================================="
echo " Gateway Bootstrap Tamamlandı!"
echo " V1.4 Nginx upstream yapılandırmalarının (Node5'e doğru)"
echo " yapılması için 'certbot_gateway.sh' çalıştırılmalıdır."
echo "=============================================="
