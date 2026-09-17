#!/usr/bin/env bash
# deploy/scale/V1.4/node3/resources/bootstrap_node3.sh
# node3 (Monitor, Staging & AI Proxy 2)
# Idempotent: tekrar çalıştırmak güvenli. V1.4 Generic Pathing kuralına uyar.
set -euo pipefail

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

echo "==> apt paketleri (Staging DB dâhil)..."
# gnupg ve wget önce kurulmalı (Grafana keyring için gerekli)
sudo apt update -q
sudo apt install -y gnupg wget
# Grafana OSS apt kaynağı ekle (idempotent - içerik kontrolü)
if ! grep -q "apt.grafana.com" /etc/apt/sources.list.d/grafana.list 2>/dev/null; then
  sudo rm -f /etc/apt/sources.list.d/grafana.list /etc/apt/keyrings/grafana.gpg
  sudo mkdir -p /etc/apt/keyrings
  wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
fi
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip rsync fail2ban build-essential ffmpeg redis-server grafana postgresql postgresql-contrib

echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── WireGuard (Mesh Network) ──────────────────────────────────────────────────
echo "==> WireGuard ağı (Mesh) yapılandırılıyor..."
if [[ -f "$RESOURCES_DIR/wg0.conf" ]]; then
  sudo mkdir -p /etc/wireguard
  if [[ ! -f "/etc/wireguard/wg0.conf" ]]; then
    sudo cp "$RESOURCES_DIR/wg0.conf" /etc/wireguard/wg0.conf
    sudo chmod 600 /etc/wireguard/wg0.conf
  else
    echo "==> Mevcut wg0.conf bulundu, üzerine yazılmıyor (Private Key korundu)."
  fi
  
  if grep -q "<NODE3_PRIVATE_KEY>" /etc/wireguard/wg0.conf; then
    echo "==> Otomatik WireGuard Anahtarı Üretiliyor..."
    sudo apt-get install -y -q wireguard-tools
    PRIV_KEY=$(wg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
    sudo sed -i "s|<NODE3_PRIVATE_KEY>|$PRIV_KEY|" /etc/wireguard/wg0.conf
    echo "=================================================================="
    echo " 🚨 DİKKAT: Node3 için YENİ WireGuard Public Key üretildi! 🚨"
    echo " PUBLIC KEY: \"$PUB_KEY\""
    echo " Lütfen bu anahtarı diğer sunucularda wg0.conf içindeki Node3 [Peer] kısmına kopyalayın!"
    echo "=================================================================="
  fi
  
  sudo systemctl enable --now wg-quick@wg0 || echo "Uyarı: WireGuard başlatılamadı."
else
  echo "Uyarı: wg0.conf bulunamadı, WireGuard ağı kurulamadı!"
fi

echo "==> UFW (Güvenlik Duvarı) Worker kuralları uygulanıyor..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 51820/udp    # WireGuard (Mesh)
sudo ufw allow in on wg0 to any 2>/dev/null || echo "Uyarı: wg0 henüz aktif olmayabilir."
sudo ufw --force enable

echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install torch --index-url https://download.pytorch.org/whl/cpu -q
"$VENV/bin/pip" install -r "$RESOURCES_DIR/node3_production_requirements.txt"

echo "==> Log dizinleri..."
sudo mkdir -p /var/log/teqlif /var/lib/promtail
sudo chown "$USER:$USER" /var/log/teqlif /var/lib/promtail
if [[ ! -L "$REPO/logs" ]]; then
  ln -s /var/log/teqlif "$REPO/logs"
fi

echo "==> node_exporter & promtail..."
if ! /usr/local/bin/node_exporter --version 2>&1 | grep -q "$NODE_EXPORTER_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | tar xz -C "$TMP"
  sudo mv "$TMP/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf "$TMP"
fi

if ! /usr/local/bin/promtail --version 2>&1 | grep -q "$PROMTAIL_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/promtail.zip" "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
  unzip -q "$TMP/promtail.zip" -d "$TMP"
  sudo mv "$TMP/promtail-linux-amd64" /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail
  rm -rf "$TMP"
fi

echo "==> Yapılandırma Dosyaları (Prometheus, Loki, Alertmanager, LiveKit)..."
sudo mkdir -p /etc/prometheus /etc/loki /etc/livekit /var/lib/alertmanager /var/lib/loki
sudo cp "$RESOURCES_DIR/prometheus.yml" /etc/prometheus/prometheus.yml || true
sudo cp "$RESOURCES_DIR/prometheus-rules.yml" /etc/prometheus/prometheus-rules.yml || true
sudo cp "$RESOURCES_DIR/loki-config.yml" /etc/loki/config.yml || true
sudo cp "$RESOURCES_DIR/promtail-config.yml" /etc/promtail-config.yml || true
sudo cp "$RESOURCES_DIR/livekit.yaml" /etc/livekit/livekit.yaml || true
sudo chown -R "$USER:$USER" /etc/prometheus /etc/loki /var/lib/alertmanager /var/lib/loki
sudo chown -R livekit:livekit /etc/livekit 2>/dev/null || true

# ── LiveKit Kurulumu ──────────────────────────────────────────────────────────
echo "==> LiveKit (Staging) kuruluyor..."
if ! command -v livekit-server &> /dev/null; then
    curl -sSL https://get.livekit.io | bash
fi

# ── MinIO Kurulumu ────────────────────────────────────────────────────────────
echo "==> MinIO (Staging) kaynak koddan derleniyor..."
if ! command -v minio &> /dev/null; then
    echo "==> Go (Golang) Debian deposundan yükleniyor..."
    sudo apt-get update -q && sudo apt-get install -y golang
    
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin
    export CGO_ENABLED=0
    go install github.com/minio/minio@latest
    
    sudo mv $GOPATH/bin/minio /usr/local/bin/
    sudo chmod +x /usr/local/bin/minio
    
    # Derleme sonrası temizlik (Cleanup)
    echo "==> MinIO derleme artıkları temizleniyor..."
    sudo rm -rf $HOME/go
    sudo apt-get remove --purge -y golang
    sudo apt-get autoremove -y -q
fi
sudo mkdir -p /var/lib/minio
sudo chown -R tucibeyin:tucibeyin /var/lib/minio

# ── PostgreSQL (Staging) Yapılandırması ───────────────────────────────────────
echo "==> PostgreSQL izole staging veritabanı kuruluyor..."
sudo systemctl start postgresql 2>/dev/null || true
if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw teqlif_staging; then
    echo "==> teqlif_staging veritabanı zaten var."
else
    echo "==> teqlif_staging veritabanı oluşturuluyor..."
    sudo -u postgres psql -c "CREATE USER teqlif_staging WITH PASSWORD 'password';" || true
    sudo -u postgres psql -c "CREATE DATABASE teqlif_staging OWNER teqlif_staging;" || true
fi

echo "==> systemd servisleri (V1.4)..."
SERVICES=(
  alertmanager grafana-server livekit loki minio node_exporter prometheus promtail redis-server
  teqlif-ai-proxy teqlif-staging teqlif-worker-critical-staging teqlif-worker-staging
)

for svc in "${SERVICES[@]}"; do
  if [[ -f "$REPO/deploy/scale/V1.4/node3/systemd/${svc}.service" ]]; then
    # Staging servisleri için .env.staging, AI proxy için .env.production kullan
    if [[ "$svc" == *"staging"* ]]; then
      ENV_FILE="$REPO/backend/.env.staging"
    else
      ENV_FILE="$REPO/backend/.env.production"
    fi
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$ENV_FILE|g" \
      "$REPO/deploy/scale/V1.4/node3/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
done

sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
done

# ── Otomatik .env Şablonu ─────────────────────────────────────────────────────
echo "==> .env şablonları kopyalanıyor..."
mkdir -p "$REPO/backend"
if [[ ! -f "$REPO/backend/.env.production" ]]; then
  cp "$RESOURCES_DIR/.env.production.template" "$REPO/backend/.env.production"
fi
if [[ ! -f "$REPO/backend/.env.staging" ]]; then
  cp "$RESOURCES_DIR/.env.staging.template" "$REPO/backend/.env.staging"
  # Rastgele güçlü bir şifre üret ve SECRET_KEY alanına yaz
  YENI_SECRET=$(openssl rand -hex 32)
  sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$YENI_SECRET/g" "$REPO/backend/.env.staging"
  echo "==> .env.staging otomatik yapılandırıldı (SECRET_KEY atandı)."
fi

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo apt-get autoremove -y -q
sudo apt-get clean -q
"$VENV/bin/pip" cache purge 2>/dev/null || true

echo "=============================================="
echo " Node3 (Monitor & Staging) Bootstrap Tamamlandı!"
echo " Lütfen .env.staging ve monitor/ konfigürasyonlarını gözden geçirin."
echo "=============================================="

echo " "
echo "==> Servis Durumları (Son Kontrol):"
bash "$RESOURCES_DIR/node3_services.sh" status || true
echo " "
