#!/usr/bin/env bash
# deploy/scale/V1.4/node1/resources/bootstrap_node1.sh
# node1 (Edge 1 - Saf Medya & Storage) — OVH DE (6 Core, 11.4GB RAM)
# NOT: Node1 daha önce monolith DB/Backend (V1.3) barındırıyordu. V1.4 itibariyle tamamen Edge roldedir.
# Idempotent: tekrar çalıştırmak güvenli. V1.4 Generic Pathing kuralına uyar.
set -euo pipefail

# -- V1.4 Jenerik Yol (Generic Path) Kuralı --
RESOURCES_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$RESOURCES_DIR/../../../../.." && pwd)"
VENV="$REPO/venv"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO Root: $REPO"
# ── Repo Sahipliği Düzeltmesi ────────────────────────────────────────────────
# sudo ile çalıştırıldığında repo dosyaları root'a geçebilir; tümünü düzelt.
REPO_OWNER=$(stat -c '%U' "$(dirname "$REPO")" 2>/dev/null || echo "tucibeyin")
if [[ "$(stat -c '%U' "$REPO" 2>/dev/null)" == "root" ]]; then
  echo "==> Repo dizin sahipliği $REPO_OWNER'a düzeltiliyor..."
  sudo chown -R "$REPO_OWNER:$REPO_OWNER" "$REPO"
fi

echo "==> Resources Dir: $RESOURCES_DIR"

# ── apt ───────────────────────────────────────────────────────────────────────
echo "==> apt paketleri (Edge profili)..."
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip rsync fail2ban redis-server certbot

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── WireGuard (Mesh Network) ──────────────────────────────────────────────────
echo "==> WireGuard ağı (Mesh) yapılandırılıyor..."
if [[ -f "$RESOURCES_DIR/wg0.conf" ]]; then
  sudo mkdir -p /etc/wireguard
  sudo cp "$RESOURCES_DIR/wg0.conf" /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf
  
  if grep -q "<NODE1_PRIVATE_KEY>" /etc/wireguard/wg0.conf; then
    echo "==> Otomatik WireGuard Anahtarı Üretiliyor..."
    sudo apt-get install -y -q wireguard-tools
    PRIV_KEY=$(wg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
    sudo sed -i "s|<NODE1_PRIVATE_KEY>|$PRIV_KEY|" /etc/wireguard/wg0.conf
    echo "=================================================================="
    echo " 🚨 DİKKAT: Node1 için YENİ WireGuard Public Key üretildi! 🚨"
    echo " PUBLIC KEY: \"$PUB_KEY\""
    echo " Lütfen bu anahtarı diğer sunucularda (Node2, Node3, Node4, Node5, Gateway)"
    echo " wg0.conf içindeki Node1 [Peer] kısmına kopyalamayı unutmayın!"
    echo "=================================================================="
  fi
  
  sudo systemctl enable --now wg-quick@wg0 || echo "Uyarı: WireGuard başlatılamadı."
else
  echo "Uyarı: wg0.conf bulunamadı, WireGuard ağı kurulamadı!"
fi

# ── UFW (Güvenlik Duvarı) Edge Profili ────────────────────────────────────────
echo "==> UFW (Güvenlik Duvarı) Edge kuralları uygulanıyor..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 80/tcp       # HTTP (Certbot/Livekit)
sudo ufw allow 443/tcp      # HTTPS (Livekit/MinIO SSL)
sudo ufw allow 9010/tcp     # MinIO Standalone Web/API
sudo ufw allow 7880/tcp     # LiveKit TCP
sudo ufw allow 50000:60000/udp # LiveKit WebRTC UDP
sudo ufw allow 51820/udp    # WireGuard
sudo ufw --force enable

# ── Swap Alanı (8GB - Edge Media/Storage Buffer) ──────────────────────────────
echo "==> Swap yapılandırması kontrol ediliyor..."
if ! sudo swapon --show 2>/dev/null | grep -q "/swapfile"; then
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
"$VENV/bin/pip" install -r "$RESOURCES_DIR/node1_production_requirements.txt"

# ── Log ve Konum Dizinleri ────────────────────────────────────────────────────
echo "==> Log, Promtail ve MinIO dizinleri..."
sudo mkdir -p /var/log/teqlif /var/lib/promtail /var/lib/minio
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /var/log/teqlif /var/lib/promtail /var/lib/minio
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

sudo cp "$RESOURCES_DIR/promtail-config.yml" /etc/promtail-config.yml 2>/dev/null || true

# ── Systemd Servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri (V1.4 dinamik env referansları ile)..."
SERVICES=(node_exporter promtail)

for svc in "${SERVICES[@]}"; do
  if [[ -f "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" ]]; then
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$REPO/backend/.env.production|g" \
      "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
done

# Install the edge-metrics-agent
sudo cp "$RESOURCES_DIR/edge-metrics-agent.service" /etc/systemd/system/
SERVICES+=("edge-metrics-agent")

sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
done

# ── Otomatik .env ve Servis Başlatma ──────────────────────────────────────────
echo "==> .env.production şablonu kopyalanıyor ve Ajan başlatılıyor..."
mkdir -p "$REPO/backend"
if [[ ! -f "$REPO/backend/.env.production" ]]; then
  cp "$RESOURCES_DIR/.env.production.template" "$REPO/backend/.env.production"
fi
sudo systemctl restart edge-metrics-agent || true

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo apt-get autoremove -y -q
sudo apt-get clean -q
"$VENV/bin/pip" cache purge 2>/dev/null || true

echo "=============================================="
echo " Node1 (Edge 1) Bootstrap Tamamlandı!"
echo " Clean State (Sıfır Kurulum) kuralı gereği önbellekler temizlendi."
echo " Lütfen LiveKit ve MinIO kurulumlarınızı gerçekleştirin."
echo "=============================================="

echo " "
echo "==> Servis Durumları (Son Kontrol):"
bash "$RESOURCES_DIR/node1_services.sh" status || true
echo " "
