#!/usr/bin/env bash
# deploy/scale/resources/node3/bootstrap_node3.sh
# node3 (Zap-Hosting GmbH, Ashburn VA) — tek seferlik kurulum. Idempotent: tekrar çalıştırmak güvenli.
# Kapsam dışı (sır içerir): WireGuard private key, .env değerleri, DB şifresi, MinIO credentials.
#
# Kurduğu servisler:
#   Uygulama: teqlif-staging, teqlif-worker-staging, teqlif-worker-critical-staging
#   AI Proxy:  teqlif-ai-proxy
#   Medya:     livekit (staging SFU — live-staging.teqlif.com)
#   Depolama:  postgresql-17, redis-server, minio
#   Web:       nginx (uploads-staging.teqlif.com)
#   Monitoring: prometheus, loki, alertmanager, node_exporter, promtail
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCALE_VERSION="V1.3"
N3_SRC="$REPO/deploy/scale/$SCALE_VERSION/node3"
SYSTEMD_SRC="$N3_SRC/systemd"
RESOURCES="$REPO/deploy/scale/resources"
NODE3="$RESOURCES/node3"

LIVEKIT_VERSION="1.13.3"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"
PROMETHEUS_VERSION="2.51.0"
LOKI_VERSION="3.6.7"
ALERTMANAGER_VERSION="0.27.0"
MINIO_VERSION="RELEASE.2025-10-15T17-29-55Z"

echo "==> REPO: $REPO"
echo "==> Scale version: $SCALE_VERSION"

# ── apt: temel paketler ──────────────────────────────────────────────────────
echo "==> apt paketleri (temel)..."
sudo apt update -q
sudo apt install -y \
  ufw wireguard unzip curl wget ca-certificates lsb-release \
  nginx redis-server \
  python3.13-venv \
  certbot python3-certbot-nginx \
  fail2ban

# ── PostgreSQL 17 (PGDG repo) ────────────────────────────────────────────────
echo "==> PostgreSQL 17 (PGDG)..."
if ! dpkg -l | grep -q postgresql-17; then
  sudo install -d /usr/share/postgresql-common/pgdg
  sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list
  sudo apt update -q
  sudo apt install -y postgresql-17 postgresql-17-pgvector
fi
sudo systemctl enable postgresql
sudo systemctl start postgresql

# ── Grup üyelikleri ──────────────────────────────────────────────────────────
echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm            tucibeyin 2>/dev/null || true

# ── Python venv (staging + AI proxy ortak) ───────────────────────────────────
# Staging requirements, AI proxy requirements'ı kapsıyor; tek venv yeterli.
# Not: sentence-transformers + ML paketleri ~1-2 GB disk kullanır (CPU-only torch).
VENV="$REPO/venv"
echo "==> Python venv @ $VENV (staging requirements)..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
# CPU-only torch önce kurulur — sentence-transformers varsayılan olarak CUDA indirir (GPU yok).
"$VENV/bin/pip" install torch --index-url https://download.pytorch.org/whl/cpu -q
"$VENV/bin/pip" install -r "$RESOURCES/node3/node3_staging_requirements.txt"

# ── MinIO ─────────────────────────────────────────────────────────────────────
echo "==> MinIO $MINIO_VERSION..."
if [[ ! -f /usr/local/bin/minio ]]; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/minio/minio/releases/download/${MINIO_VERSION}/minio.linux-amd64" \
    -O "$TMP/minio"
  sudo mv "$TMP/minio" /usr/local/bin/minio
  sudo chmod +x /usr/local/bin/minio
  rm -rf "$TMP"
fi
sudo mkdir -p /var/lib/minio
sudo chown tucibeyin:tucibeyin /var/lib/minio
# MinIO credentials: minio.service doğrudan resources/node3/.env.staging'den okur — /etc/minio.env gerekmez

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
sudo cp "$N3_SRC/promtail-config.yml" /etc/promtail-config.yml

# ── prometheus ────────────────────────────────────────────────────────────────
echo "==> prometheus $PROMETHEUS_VERSION..."
if ! /usr/local/bin/prometheus --version 2>&1 | grep -q "$PROMETHEUS_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
    -O "$TMP/prom.tar.gz"
  tar xzf "$TMP/prom.tar.gz" -C "$TMP"
  sudo mv "$TMP/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /usr/local/bin/
  sudo mv "$TMP/prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool"   /usr/local/bin/
  rm -rf "$TMP"
fi
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp "$N3_SRC/prometheus.yml"       /etc/prometheus/prometheus.yml
sudo cp "$N3_SRC/prometheus-rules.yml" /etc/prometheus/prometheus-rules.yml
sudo chown -R tucibeyin:tucibeyin /etc/prometheus /var/lib/prometheus

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
sudo mkdir -p /etc/loki /var/lib/loki
sudo chown -R tucibeyin:tucibeyin /var/lib/loki
sudo cp "$N3_SRC/loki-config.yml" /etc/loki/config.yml

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
sudo chown -R tucibeyin:tucibeyin /var/lib/alertmanager
# alertmanager.yml.template → envsubst ile .env.production'dan TELEGRAM_* inject edilir
# (alertmanager.service ExecStartPre'si bu işi yapar — deployment sırasında otomatik)

# ── LiveKit ───────────────────────────────────────────────────────────────────
echo "==> livekit-server $LIVEKIT_VERSION..."
if ! /usr/local/bin/livekit-server --version 2>&1 | grep -q "$LIVEKIT_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  wget -q \
    "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_${LIVEKIT_VERSION}_linux_amd64.tar.gz" \
    -O "$TMP/livekit.tar.gz"
  tar xzf "$TMP/livekit.tar.gz" -C "$TMP"
  sudo mv "$TMP/livekit-server" /usr/local/bin/livekit-server
  sudo chmod +x /usr/local/bin/livekit-server
  rm -rf "$TMP"
fi
# livekit kullanıcısı
if ! id livekit &>/dev/null; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin livekit
fi
sudo mkdir -p /etc/livekit/certs
sudo chown -R livekit:livekit /etc/livekit
# livekit.yaml — <LIVEKIT_API_SECRET> elle doldurulmalı (bootstrap sonrası):
if [[ ! -f /etc/livekit/livekit.yaml ]]; then
  sudo cp "$N3_SRC/livekit.yaml" /etc/livekit/livekit.yaml
  sudo chmod 640 /etc/livekit/livekit.yaml
fi

# ── nginx: uploads-staging.teqlif.com ────────────────────────────────────────
echo "==> nginx site config..."
sudo cp "$N3_SRC/nginx/uploads-staging.teqlif.com" \
  /etc/nginx/sites-available/uploads-staging.teqlif.com
if [[ ! -L /etc/nginx/sites-enabled/uploads-staging.teqlif.com ]]; then
  sudo ln -s /etc/nginx/sites-available/uploads-staging.teqlif.com \
    /etc/nginx/sites-enabled/uploads-staging.teqlif.com
fi
# Default site kaldır (varsa)
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# ── sysctl ────────────────────────────────────────────────────────────────────
echo "==> sysctl optimizasyonları..."
sudo mkdir -p /etc/sysctl.d
sudo cp "$N3_SRC/sysctl/99-teqlif.conf" /etc/sysctl.d/99-teqlif.conf
sudo sysctl -p /etc/sysctl.d/99-teqlif.conf

# ── Swap (4 GB) ───────────────────────────────────────────────────────────────
# vm.swappiness=10 yukarıdaki sysctl adımında uygulandı — swap sadece baskı altında kullanılır
echo "==> Swap (4 GB)..."
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  echo "    4 GB swap aktif."
else
  echo "    /swapfile zaten mevcut — atlanıyor."
fi

# ── journald limitleri ───────────────────────────────────────────────────────
echo "==> journald limitleri..."
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp "$N3_SRC/journald/journald.conf" /etc/systemd/journald.conf.d/99-teqlif.conf
sudo systemctl restart systemd-journald

# ── systemd servisleri ────────────────────────────────────────────────────────
echo "==> systemd servisleri..."
for svc in \
  teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging \
  teqlif-ai-proxy \
  minio livekit \
  node_exporter promtail prometheus loki alertmanager; do
  sudo cp "$SYSTEMD_SRC/${svc}.service" /etc/systemd/system/
done
sudo systemctl daemon-reload
for svc in \
  teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging \
  teqlif-ai-proxy \
  minio livekit \
  node_exporter promtail prometheus loki alertmanager; do
  sudo systemctl enable "$svc"
done

# ── WireGuard ─────────────────────────────────────────────────────────────────
echo "==> WireGuard..."
if [[ -f /etc/wireguard/node3_private.key ]]; then
  if [[ ! -f /etc/wireguard/wg0.conf ]]; then
    NODE3_PRIV=$(sudo cat /etc/wireguard/node3_private.key)
    sudo cp "$REPO/deploy/scale/$SCALE_VERSION/wireguard/node3-wg0.conf" /etc/wireguard/wg0.conf
    sudo sed -i "s|<NODE3_PRIVATE_KEY>|${NODE3_PRIV}|" /etc/wireguard/wg0.conf
    sudo chmod 600 /etc/wireguard/wg0.conf
    echo "    wg0.conf yazildi."
  else
    echo "    wg0.conf zaten mevcut, atlaniyor."
  fi
  sudo systemctl enable wg-quick@wg0 2>/dev/null || true
  sudo systemctl is-active wg-quick@wg0 &>/dev/null || sudo systemctl start wg-quick@wg0
else
  echo "  UYARI: /etc/wireguard/node3_private.key bulunamadi — WireGuard atlanıyor."
  echo "  Once anahtari olustur:"
  echo "  sudo bash -c 'wg genkey | tee /etc/wireguard/node3_private.key | wg pubkey > /etc/wireguard/node3_public.key'"
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
echo "==> UFW..."
sudo ufw allow 22/tcp     comment 'SSH'                                 2>/dev/null || true
sudo ufw allow 51820/udp  comment 'WireGuard'                          2>/dev/null || true
sudo ufw allow 80/tcp     comment 'HTTP — certbot + nginx redirect'    2>/dev/null || true
sudo ufw allow 443/tcp    comment 'HTTPS — uploads-staging.teqlif.com' 2>/dev/null || true
# WireGuard mesh erişimleri
sudo ufw allow in on wg0 to any port 8001 proto tcp comment 'staging FastAPI — gateway' 2>/dev/null || true
sudo ufw allow in on wg0 to any port 8080 proto tcp comment 'AI proxy — node1'         2>/dev/null || true
sudo ufw allow in on wg0 to any port 3100 proto tcp comment 'Loki — mesh pushları'      2>/dev/null || true
sudo ufw allow in on wg0 to any port 9100 proto tcp comment 'node_exporter — Prometheus self' 2>/dev/null || true
sudo ufw --force enable

# ── Hostname ──────────────────────────────────────────────────────────────────
if [[ "$(hostname)" != "node3" ]]; then
  echo "==> Hostname node3 olarak ayarlaniyor..."
  sudo hostnamectl set-hostname node3
  grep -q "node3" /etc/hosts || echo "127.0.1.1 node3" | sudo tee -a /etc/hosts > /dev/null
fi

# ── .env izinleri ─────────────────────────────────────────────────────────────
echo "==> .env izinleri..."
chmod 600 "$NODE3/.env.production"
chmod 600 "$NODE3/.env.staging"

echo ""
echo "Bootstrap tamamlandi."
echo ""
echo "Kalan manuel adimlar:"
echo ""
echo "  1. WireGuard key yoksa:"
echo "     sudo bash -c 'wg genkey | tee /etc/wireguard/node3_private.key | wg pubkey > /etc/wireguard/node3_public.key'"
echo "     cat /etc/wireguard/node3_public.key  # → diğer node'ların wg0.conf'una [Peer] ekle"
echo "     Sonra bu scripti tekrar calistir — wg0.conf otomatik yazilir."
echo ""
echo "  2. .env dosyalarini doldur:"
echo "     nano $NODE3/.env.production   (AI proxy + monitoring)"
echo "     nano $NODE3/.env.staging       (staging uygulama)"
echo "     # MinIO credentials: .env.staging içinde MINIO_ROOT_USER/PASSWORD satırları"
echo ""
echo "  3. .env dosyalarini /var/www/teqlif.com/backend/'a kopyala:"
echo "     cp $NODE3/.env.production /var/www/teqlif.com/backend/.env"
echo "     cp $NODE3/.env.staging    /var/www/teqlif.com/backend/.env.staging"
echo ""
echo "  4. PostgreSQL — DB ve kullanici olustur:"
echo "     sudo -u postgres createuser --no-superuser --createdb tucibeyin"
echo "     sudo -u postgres createdb -O tucibeyin teqlif_staging"
echo "     sudo -u postgres psql -c \"CREATE EXTENSION IF NOT EXISTS vector;\" teqlif_staging"
echo "     sudo -u postgres psql -c \"ALTER USER tucibeyin WITH PASSWORD '<sifre>';\" "
echo "     (DATABASE_URL'yi .env.staging'e gir, sonra devam et)"
echo ""
echo "  5. SSL sertifikası al (nginx calisiyor olmali):"
echo "     sudo nginx -t && sudo systemctl start nginx"
echo "     sudo certbot --nginx -d uploads-staging.teqlif.com"
echo "     sudo systemctl reload nginx"
echo ""
echo "  6. MinIO bucket'lari olustur (MinIO calisiyor olmali, sonra mc ile):"
echo "     mc alias set node3 http://localhost:9010 <user> <password>"
echo "     mc mb node3/teqlif-staging"
echo "     mc mb node3/teqlif-dm-staging"
echo ""
echo "  7. Tum servisleri baslat:"
echo "     bash $NODE3/node3_services.sh start"
echo ""
echo "  8. DNS: Cloudflare'de uploads-staging.teqlif.com → 5.249.165.10 (DNS only, gray cloud)"
echo ""
echo "  9. Diger node'larda node3 WireGuard peer'ini ekle — plan.md §9.5'e bak."
