#!/usr/bin/env bash
# deploy/scale/V1.4/node4/resources/bootstrap_node4.sh
# node4 (Edge 2 - Saf Medya & Storage) — OVH DE (6 Core, 11.4GB RAM)
# Idempotent: tekrar çalıştırmak güvenli. V1.4 Generic Pathing kuralına uyar.
set -euo pipefail

# -- V1.4 Jenerik Yol (Generic Path) Kuralı --
RESOURCES_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$RESOURCES_DIR/../../../../.." && pwd)"
VENV="$REPO/venv"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO Root: $REPO"
echo "==> Resources Dir: $RESOURCES_DIR"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri (Edge profili)..."
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip rsync fail2ban redis-server

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── Swap Alanı (8GB - Edge Media/Storage Buffer) ──────────────────────────────
echo "==> Swap yapılandırması kontrol ediliyor..."
if ! swapon --show | grep -q "/swapfile"; then
  echo "==> 8GB Swap dosyası oluşturuluyor..."
  sudo fallocate -l 8G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  
  # Swap optimizasyonu
  sudo sysctl vm.swappiness=10
  sudo mkdir -p /etc/sysctl.d
  echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-teqlif.conf || true
else
  echo "==> Swap zaten aktif."
fi

# ── Python venv (Sadece Edge Metrics Agent için) ──────────────────────────────
echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
# Sadece minör gereksinimler (psutil, redis vb.)
"$VENV/bin/pip" install -r "$RESOURCES_DIR/node4_production_requirements.txt"

# ── Log ve Konum Dizinleri ────────────────────────────────────────────────────
echo "==> Log, Promtail ve MinIO dizinleri..."
sudo mkdir -p /var/log/teqlif /var/lib/promtail /var/lib/minio
sudo chown "$USER:$USER" /var/log/teqlif /var/lib/promtail /var/lib/minio
if [[ ! -L "$REPO/logs" ]]; then
  ln -s /var/log/teqlif "$REPO/logs"
fi

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
echo "==> systemd servisleri (V1.4 dinamik env referansları ile)..."
SERVICES=(node_exporter promtail)

for svc in "${SERVICES[@]}"; do
  if [[ -f "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" ]]; then
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$RESOURCES_DIR/.env.production|g" \
      "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
done

sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
done

echo "=============================================="
echo " Node4 (Edge 2) Bootstrap Tamamlandı!"
echo " Lütfen LiveKit ve MinIO Standalone kurulumlarınızı"
echo " V1.4 mimarisine uygun olarak gerçekleştirin."
echo " Ayrıca 'edge-metrics-agent' servisini kurmayı unutmayın."
echo "=============================================="
