#!/usr/bin/env bash
# deploy/scale/V1.4/node5/resources/bootstrap_node5.sh
# node5 (Core / Orchestrator) — ZAP-Hosting (4 Core EPYC, 7.8GB RAM)
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

# ── apt & Veritabanı Kurulumları ──────────────────────────────────────────────
echo "==> apt paketleri ve ana servisler (PostgreSQL, Redis)..."
export DEBIAN_FRONTEND=noninteractive
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip rsync fail2ban postgresql postgresql-contrib redis-server apt-transport-https ca-certificates curl gnupg

echo "==> ClickHouse kurulumu..."
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | sudo gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt update -q
sudo apt install -y clickhouse-server clickhouse-client

echo "==> Servisler aktifleştiriliyor..."
sudo systemctl enable --now postgresql
sudo systemctl enable --now redis-server
sudo systemctl enable --now clickhouse-server

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── UFW (Güvenlik Duvarı) Core Profili ────────────────────────────────────────
echo "==> UFW (Güvenlik Duvarı) Core kuralları uygulanıyor..."
echo "NOT: Core Node dışarıya DB portlarını AÇMAZ. Sadece WireGuard ve SSH."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 51820/udp    # WireGuard (Mesh)
# 10.10.0.0/24 subnetine (Wireguard arayüzüne) sınırsız izin
sudo ufw allow in on wg0 to any 2>/dev/null || echo "Uyarı: wg0 henüz aktif olmayabilir."
sudo ufw --force enable

# ── Swap Alanı (Deli Gömleği / OOM Koruması) ────────────────────────────────────
echo "==> Swap yapılandırması kontrol ediliyor..."
if ! sudo swapon --show 2>/dev/null | grep -q "/swapfile"; then
  echo "==> 8GB Swap dosyası oluşturuluyor..."
  sudo fallocate -l 8G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  
  # Swap optimizasyonu (DB ağırlıklı node için swappiness düşük tutulur)
  sudo sysctl vm.swappiness=10
  sudo mkdir -p /etc/sysctl.d
  echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-teqlif.conf || true
else
  echo "==> Swap zaten aktif."
fi

# ── Python venv ───────────────────────────────────────────────────────────────
echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install torch --index-url https://download.pytorch.org/whl/cpu -q
"$VENV/bin/pip" install -r "$RESOURCES_DIR/node5_production_requirements.txt"

# ── Log ve Konum Dizinleri ────────────────────────────────────────────────────
echo "==> Log ve Promtail dizinleri..."
sudo mkdir -p /var/log/teqlif /var/lib/promtail
sudo chown "$USER:$USER" /var/log/teqlif /var/lib/promtail
if [[ ! -L "$REPO/logs" ]]; then
  ln -s /var/log/teqlif "$REPO/logs"
fi

# ── Backup dizinleri ─────────────────────────────────────────────────────────
echo "==> Backup dizinleri (PostgreSQL & Redis)..."
sudo mkdir -p /var/backups/teqlif/pg /var/backups/teqlif/redis
sudo chown -R "$USER:$USER" /var/backups/teqlif

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

# Not: promtail-config.yml şablonunuz varsa kopyalayın
# sudo cp "$RESOURCES_DIR/promtail-config.yml" /etc/promtail-config.yml 2>/dev/null || true

# ── Systemd Servisleri (Dinamik Path Injector) ────────────────────────────────
echo "==> systemd servisleri (V1.4 dinamik env referansları ile)..."
SERVICES=(teqlif teqlif-worker node_exporter promtail)

# V1.3 systemd dosyalarını al, içlerindeki eski EnvironmentFile path'ini dinamik olarak V1.4'e çevir ve kur
for svc in "${SERVICES[@]}"; do
  # Eğer V1.4 içinde özel systemd klasörü açılırsa ordan okur, yoksa eski repodan okuyup sed ile V1.4'e çevirir.
  if [[ -f "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" ]]; then
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$REPO/backend/.env.production|g" \
      "$REPO/deploy/scale/V1.3/node1/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
done

sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
done

# ── Veritabanı ve Çevresel Değişken (Env) Hazırlığı ───────────────────────────
echo "==> PostgreSQL Veritabanı teqlif yaratılıyor..."
sudo -u postgres psql -c "CREATE USER teqlif WITH PASSWORD 'teqlif_db_pass';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE teqlif OWNER teqlif;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE teqlif TO teqlif;" 2>/dev/null || true

echo "==> .env.production dosyası oluşturuluyor..."
if [[ ! -f "$REPO/backend/.env.production" ]]; then
  cp "$RESOURCES_DIR/.env.production.template" "$REPO/backend/.env.production"
  sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"postgresql+asyncpg://teqlif:teqlif_db_pass@localhost/teqlif\"|" "$REPO/backend/.env.production"
  sed -i "s|^REDIS_URL=.*|REDIS_URL=\"redis://localhost:6379\"|" "$REPO/backend/.env.production"
  SECRET=$(openssl rand -hex 32)
  sed -i "s|^SECRET_KEY=.*|SECRET_KEY=\"$SECRET\"|" "$REPO/backend/.env.production"
  echo ".env.production otomatik ayarlandı."
fi

echo "==> Alembic Migration çalıştırılıyor..."
cd "$REPO/backend" || true
export ENV=production
"$VENV/bin/alembic" upgrade head || echo "Uyarı: Alembic migration başarısız oldu."
cd "$REPO" || true

# ── Backend Servislerini Başlat ───────────────────────────────────────────────
echo "==> Servisler başlatılıyor..."
for svc in "${SERVICES[@]}"; do
  sudo systemctl restart "$svc" 2>/dev/null || true
done

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo apt-get autoremove -y -q
sudo apt-get clean -q
"$VENV/bin/pip" cache purge 2>/dev/null || true

echo "=============================================="
echo " Node5 (Core) Bootstrap Tamamlandı!"
echo " Clean State (Sıfır Kurulum) kuralı gereği önbellekler temizlendi."
echo " V1.4 Tuning scriptlerini (apply_pg_tuning.sh ve apply_ch_tuning.sh) çalıştırabilirsiniz."
echo "=============================================="
