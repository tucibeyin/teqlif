# Teqlif VPS Kurulum Rehberi

**Referans VPS:** `135.125.175.223`  
**İşletim Sistemi:** Debian 13 (trixie)  
**Hazırlanma / Son Güncelleme:** 2026-09-02

> Bu rehber, mevcut çalışan bir VPS'ten yeni bir VPS'e geçişi kapsar.
> Eski VPS'e erişim varsayılır — config, binary ve veri oradan alınır.

---

## Stack

| Bileşen | Versiyon | Port |
|---------|----------|------|
| Python | 3.13 (Debian 13 native) | — |
| FastAPI + Uvicorn | — | 8000 |
| PostgreSQL | 17 + pgvector (Debian 13 native) | 5432 |
| Redis | 8.x | 6379 |
| ClickHouse | 26.x | 8123 / 9000 |
| MinIO | latest | 9010 (API), 9011 (console) |
| LiveKit | 1.13.3 | 7880, 7881, 7882 |
| Nginx | — | 80, 443 |
| Loki | 3.6.7 | 3100 |
| Promtail | 3.0.0 | 9080 |
| Prometheus | 2.51.0 | 9090 |
| Grafana | 13.x | 3000 |
| node_exporter | 1.8.2 | 9100 |
| prometheus-postgres-exporter | 0.17.x | 9187 |

---

## Faz 1 — Sistem Kurulumu

### 1.1 SSH

```bash
ssh tucibeyin@YENİ_VPS_IP
```

> Root ile değil, sudo yetkili kullanıcıyla giriş yap.

### 1.2 Sistem Güncelleme ve Paketler

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  build-essential curl wget git unzip \
  software-properties-common gnupg2 \
  htop jq \
  libpq-dev libssl-dev libffi-dev \
  libjpeg-dev zlib1g-dev \
  python3-venv python3-dev
```

> **Not:** Debian 13 trixie'de Python 3.13 zaten kuruludur — PPA gerekmez.

### 1.3 Dizin Yapısı

```bash
sudo mkdir -p /var/www/teqlif.com/uploads
sudo mkdir -p /var/www/teqlif.com/backend/logs
sudo mkdir -p /var/www/teqlif.com/backend/certificates
sudo mkdir -p /var/backups/redis

sudo chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

> İleride `www-data`'ya devredilecek; önce git işlemleri için tucibeyin sahibi olmalı.

### 1.4 Güvenlik Duvarı (UFW)

```bash
sudo ufw allow 22/tcp
sudo ufw allow 'Nginx Full'
sudo ufw allow 3000/tcp comment 'Grafana'

# LiveKit
sudo ufw allow 50000:60000/udp comment 'LiveKit WebRTC medya'
sudo ufw allow 7882/tcp comment 'LiveKit TCP fallback'

# TURN / STUN
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp

# Ek WebRTC
sudo ufw allow 30000:40000/udp

# Cloudflare IPv4
for ip in 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 104.16.0.0/13 104.24.0.0/14 108.162.192.0/18 131.0.72.0/22 141.101.64.0/18 162.158.0.0/15 172.64.0.0/13 173.245.48.0/20 188.114.96.0/20 190.93.240.0/20 197.234.240.0/22 198.41.128.0/17; do
  sudo ufw allow from $ip to any port 80,443 proto tcp
done

# Cloudflare IPv6
for ip in 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32; do
  sudo ufw allow from $ip to any port 80,443 proto tcp
done

sudo ufw --force enable
sudo ufw status verbose
```

### 1.5 Fail2ban

```bash
# Kontrol et — zaten kuruluysa dokunma
sudo systemctl status fail2ban
# Aktif değilse:
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

---

## Faz 2 — Servis Kurulumları

### 2.1 PostgreSQL 17

```bash
# Debian 13'te native olarak gelir — PGDG repo gerekmez
sudo apt install -y postgresql postgresql-17-pgvector
sudo systemctl enable --now postgresql
```

#### Veritabanı ve Kullanıcı Oluştur

```bash
sudo -u postgres psql <<EOF
CREATE USER teqlif WITH PASSWORD 'SIFRE_YAZ';
CREATE DATABASE teqlif OWNER teqlif;
\c teqlif
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOF
```

### 2.2 Redis

Config'i eski VPS'ten kopyala:

```bash
# Eski VPS'te:
scp /etc/redis/redis.conf tucibeyin@YENİ_VPS_IP:/tmp/redis.conf

# Yeni VPS'te:
sudo cp /tmp/redis.conf /etc/redis/redis.conf
sudo systemctl enable --now redis-server
redis-cli ping   # PONG
```

### 2.3 ClickHouse

> ⚠️ Debian 13'te APT repo GPG URL'leri 404 verebilir. Resmi install scripti kullan:

```bash
curl https://clickhouse.com/install.sh | sudo bash
```

Systemd unit'i eski VPS'ten kopyala (install script farklı bir unit dosyası oluşturabilir):

```bash
# Eski VPS'te:
sudo cat /etc/systemd/system/clickhouse-server.service > /tmp/clickhouse.service
scp /tmp/clickhouse.service tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo cp /tmp/clickhouse.service /etc/systemd/system/clickhouse-server.service
sudo systemctl daemon-reload
sudo systemctl enable --now clickhouse-server
clickhouse-client --query "SELECT version()"
```

> Tablolar uygulama ilk açılışında otomatik oluşturulur (`init_clickhouse()`).

### 2.4 MinIO

```bash
# Binary
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio \
  -O /tmp/minio
sudo mv /tmp/minio /usr/local/bin/minio
sudo chmod +x /usr/local/bin/minio

# Veri dizini
sudo mkdir -p /var/minio/data
sudo useradd -r -s /sbin/nologin minio-user 2>/dev/null || true
sudo chown minio-user:minio-user /var/minio/data
```

EnvironmentFile (`.env`'deki MINIO_ACCESS_KEY ve MINIO_SECRET_KEY değerleri):

```bash
sudo tee /etc/minio.env > /dev/null <<EOF
MINIO_ROOT_USER=ACCESS_KEY_YAZ
MINIO_ROOT_PASSWORD=SECRET_KEY_YAZ
MINIO_VOLUMES="/var/minio/data"
EOF
sudo chmod 600 /etc/minio.env
```

Systemd unit'i eski VPS'ten kopyala:

```bash
# Eski VPS'te:
sudo cat /etc/systemd/system/minio.service > /tmp/minio.service
scp /tmp/minio.service tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo cp /tmp/minio.service /etc/systemd/system/minio.service
sudo systemctl daemon-reload
sudo systemctl enable --now minio
```

#### Bucket Oluştur

```bash
wget -q https://dl.min.io/client/mc/release/linux-amd64/mc \
  -O /tmp/mc
sudo mv /tmp/mc /usr/local/bin/mc
sudo chmod +x /usr/local/bin/mc

mc alias set local http://localhost:9010 ACCESS_KEY_YAZ SECRET_KEY_YAZ
mc mb local/teqlif
```

### 2.5 Nginx

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

Config'i eski VPS'ten kopyala:

```bash
# Eski VPS'te:
sudo scp /etc/nginx/sites-available/teqlif.com tucibeyin@YENİ_VPS_IP:/tmp/
sudo scp /etc/nginx/nginx.conf tucibeyin@YENİ_VPS_IP:/tmp/nginx.conf

# Yeni VPS'te:
sudo cp /tmp/teqlif.com /etc/nginx/sites-available/teqlif.com
sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf
sudo ln -sf /etc/nginx/sites-available/teqlif.com /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
```

> ⚠️ **`/uploads/` location'ı kopyaladıktan sonra mutlaka kontrol et.**  
> Nginx config `alias /var/www/teqlif.com/uploads/` (yerel dizin) olarak geliyorsa  
> MinIO'ya proxy'e çevir:
>
> ```nginx
> location /uploads/ {
>     proxy_pass http://127.0.0.1:9010/teqlif/;
>     proxy_set_header Host $http_host;
>     proxy_buffering off;
>     expires 30d;
>     add_header Cache-Control "public, no-transform";
> }
> ```
>
> Ve MinIO bucket'ı public-read yap:
> ```bash
> mc anonymous set download local/teqlif
> ```

---

## Faz 3 — Uygulama Kurulumu

### 3.1 Git ve SSH Anahtarı

```bash
# Yeni VPS'te SSH anahtarı oluştur
ssh-keygen -t ed25519 -C "teqlif-vps"
cat ~/.ssh/id_ed25519.pub
# Public key'i GitHub → Settings → SSH Keys'e ekle
```

#### Repo'yu Klonla

```bash
git clone git@github.com:tucibeyin/teqlif.git /var/www/teqlif.com
git config --global --add safe.directory /var/www/teqlif.com
```

### 3.2 Virtual Environment

```bash
cd /var/www/teqlif.com
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip wheel
pip install -r backend/requirements.txt
```

> `sentence-transformers`, `faiss-cpu`, `nudenet` gibi ML paketleri büyük — 5-10 dakika sürebilir.

### 3.3 .env Dosyası

```bash
sudo tee /var/www/teqlif.com/backend/.env > /dev/null <<EOF
DATABASE_URL=postgresql+asyncpg://teqlif:SIFRE@127.0.0.1:5432/teqlif
REDIS_URL=redis://localhost:6379
SECRET_KEY=UZUN_RASTGELE_STRING
UPLOAD_DIR=/var/www/teqlif.com/uploads
SITE_URL=https://www.teqlif.com

FIREBASE_SERVICE_ACCOUNT=/var/www/teqlif.com/backend/firebase-service-account.json

APNS_KEY_PATH=/var/www/teqlif.com/backend/certificates/AuthKey_XXXXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
APNS_CERT_PATH=/var/www/teqlif.com/backend/certificates/voip_cert.pem
APNS_USE_SANDBOX=False

LIVEKIT_URL=wss://live.teqlif.com
LIVEKIT_API_KEY=API_KEY
LIVEKIT_API_SECRET=API_SECRET

MINIO_ENDPOINT=localhost:9010
MINIO_ACCESS_KEY=ACCESS_KEY
MINIO_SECRET_KEY=SECRET_KEY
MINIO_BUCKET=teqlif
MINIO_SECURE=false

CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123

ADMIN_PASSWORD_HASH=ESKİ_VPS_HASH_KOPYALA

BREVO_API_KEY=
SENTRY_BACKEND_DSN=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
GROQ_API_KEY=
GEMINI_API_KEY=
GOOGLE_CLIENT_ID=
EOF

sudo chmod 600 /var/www/teqlif.com/backend/.env
sudo chown www-data:www-data /var/www/teqlif.com/backend/.env
```

> `ADMIN_PASSWORD_HASH` eski VPS'teki `.env`'den kopyala.

### 3.4 Sertifika Dosyaları

Eski VPS'ten kopyala:

```bash
# Eski VPS'te:
scp /var/www/teqlif.com/backend/certificates/AuthKey_*.p8 tucibeyin@YENİ_VPS_IP:/tmp/
scp /var/www/teqlif.com/backend/certificates/voip_cert.pem tucibeyin@YENİ_VPS_IP:/tmp/
scp /var/www/teqlif.com/backend/firebase-service-account.json tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo mv /tmp/AuthKey_*.p8 /var/www/teqlif.com/backend/certificates/
sudo mv /tmp/voip_cert.pem /var/www/teqlif.com/backend/certificates/
sudo mv /tmp/firebase-service-account.json /var/www/teqlif.com/backend/
sudo chmod 600 /var/www/teqlif.com/backend/certificates/*
sudo chmod 600 /var/www/teqlif.com/backend/firebase-service-account.json
```

> **Not:** `firebase-service-account.json` `backend/` altına gider — `backend/certificates/` değil.

### 3.5 DB Şeması

> ⚠️ `alembic upgrade head` kullanma — migration ordering hatası var. Eski VPS'ten schema dump al.

```bash
# Eski VPS'te:
sudo -u postgres pg_dump --schema-only teqlif > /tmp/teqlif_schema.sql
scp /tmp/teqlif_schema.sql tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo -u postgres psql teqlif < /tmp/teqlif_schema.sql
cd /var/www/teqlif.com/backend
source /var/www/teqlif.com/venv/bin/activate
alembic stamp head
```

### 3.6 Production Verisini Taşı

#### PostgreSQL Verisi

```bash
# Eski VPS'te — data dump al:
sudo -u postgres pg_dump \
  --data-only \
  --exclude-table=alembic_version \
  -Fc teqlif \
  -f /tmp/teqlif_data.dump
scp /tmp/teqlif_data.dump tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te — tabloları temizle ve restore et:
sudo -u postgres psql -d teqlif -c "
DO \$\$ DECLARE r RECORD;
BEGIN
  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename != 'alembic_version') LOOP
    EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
  END LOOP;
END \$\$;
"

sudo -u postgres pg_restore \
  --data-only \
  --disable-triggers \
  -d teqlif \
  /tmp/teqlif_data.dump
```

#### MinIO Verisi

```bash
# Yeni VPS'te — hedef dizini oluştur:
mkdir -p /tmp/minio-teqlif

# Eski VPS'te — bucket dosyalarını kopyala:
sudo scp -r /var/minio/data/teqlif/ tucibeyin@YENİ_VPS_IP:/tmp/minio-teqlif/

# Yeni VPS'te — MinIO veri dizinine taşı:
sudo cp -r /tmp/minio-teqlif/* /var/minio/data/teqlif/
sudo chown -R minio-user:minio-user /var/minio/data/
sudo systemctl restart minio
```

### 3.7 Systemd Servisleri

Eski VPS'ten kopyala:

```bash
# Eski VPS'te:
for svc in teqlif teqlif-worker teqlif-worker-critical redis-backup; do
  sudo cat /etc/systemd/system/${svc}.service > /tmp/${svc}.service
done
sudo cat /etc/systemd/system/redis-backup.timer > /tmp/redis-backup.timer
scp /tmp/teqlif*.service /tmp/redis-backup* tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
for svc in teqlif teqlif-worker teqlif-worker-critical redis-backup; do
  sudo cp /tmp/${svc}.service /etc/systemd/system/
done
sudo cp /tmp/redis-backup.timer /etc/systemd/system/
```

#### Worker PartOf Override

```bash
for svc in teqlif-worker teqlif-worker-critical; do
  sudo mkdir -p /etc/systemd/system/${svc}.service.d/
  sudo tee /etc/systemd/system/${svc}.service.d/partof.conf > /dev/null <<EOF
[Unit]
PartOf=teqlif.service
EOF
done
```

#### www-data Sahibi ve Enable

```bash
sudo chown -R www-data:www-data /var/www/teqlif.com
sudo usermod -aG www-data tucibeyin   # ssh yeniden bağlan

sudo systemctl daemon-reload
sudo systemctl enable --now teqlif teqlif-worker teqlif-worker-critical
sudo systemctl enable --now redis-backup.timer
```

---

## Faz 4 — LiveKit

### 4.1 Binary

> ⚠️ GitHub release URL'leri değişebilir. Binary'yi doğrudan eski VPS'ten kopyala.

```bash
# Eski VPS'te:
scp /usr/local/bin/livekit-server tucibeyin@YENİ_VPS_IP:/tmp/livekit-server

# Yeni VPS'te:
sudo mv /tmp/livekit-server /usr/local/bin/livekit-server
sudo chmod +x /usr/local/bin/livekit-server
```

### 4.2 Config

```bash
# Eski VPS'te:
sudo scp /etc/livekit/livekit.yaml tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo mkdir -p /etc/livekit
sudo cp /tmp/livekit.yaml /etc/livekit/livekit.yaml

# node_ip'yi yeni VPS'e güncelle:
sudo sed -i 's/node_ip: .*/node_ip: "YENİ_VPS_IP"/' /etc/livekit/livekit.yaml
```

TURN sertifikaları:

```bash
# Eski VPS'te:
sudo scp -r /etc/livekit/certs/ tucibeyin@YENİ_VPS_IP:/tmp/livekit-certs/

# Yeni VPS'te:
sudo mkdir -p /etc/livekit/certs
sudo cp /tmp/livekit-certs/* /etc/livekit/certs/
```

### 4.3 Systemd

```bash
# Eski VPS'te:
sudo cat /etc/systemd/system/livekit.service > /tmp/livekit.service
scp /tmp/livekit.service tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo useradd -r -s /sbin/nologin livekit 2>/dev/null || true
sudo cp /tmp/livekit.service /etc/systemd/system/livekit.service
sudo systemctl daemon-reload
sudo systemctl enable --now livekit
```

---

## Faz 5 — Nginx + SSL

### 5.1 SSL Sertifikaları (DNS cutover öncesi)

Eski VPS'teki mevcut sertifikaları taşı:

```bash
# Eski VPS'te:
sudo tar czf /tmp/letsencrypt.tar.gz /etc/letsencrypt/
scp /tmp/letsencrypt.tar.gz tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo tar xzf /tmp/letsencrypt.tar.gz -C /
```

### 5.2 Nginx Doğrulama

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 5.3 DNS Cutover Sonrası — Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx

# Mevcut sertifikalar taşındıysa sadece yenileme ayarla:
sudo systemctl status certbot.timer

# Sertifikalar yoksa yeni al (DNS A kayıtları yeni VPS'e yönlenmiş olmalı):
sudo certbot --nginx \
  -d teqlif.com \
  -d www.teqlif.com \
  -d admin.teqlif.com \
  -d live.teqlif.com \
  --non-interactive --agree-tos \
  -m admin@teqlif.com
```

---

## Faz 6 — Monitoring

### 6.1 Loki

```bash
# Eski VPS'ten binary ve config kopyala:
scp /usr/local/bin/loki tucibeyin@YENİ_VPS_IP:/tmp/
sudo cat /etc/loki/config.yml > /tmp/loki.config.yml
scp /tmp/loki.config.yml tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo mv /tmp/loki /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
sudo mkdir -p /etc/loki /var/lib/loki
sudo cp /tmp/loki.config.yml /etc/loki/config.yml
```

Systemd unit:

```bash
sudo tee /etc/systemd/system/loki.service > /dev/null <<'EOF'
[Unit]
Description=Loki service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/loki -config.file /etc/loki/config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now loki
```

### 6.2 Promtail

```bash
# Eski VPS'ten binary kopyala:
scp /usr/local/bin/promtail tucibeyin@YENİ_VPS_IP:/tmp/
sudo mv /tmp/promtail /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail

# GeoIP veritabanı (nginx-access geoip pipeline için gerekli):
sudo mkdir -p /usr/share/GeoIP
scp /usr/share/GeoIP/GeoLite2-City.mmdb tucibeyin@YENİ_VPS_IP:/tmp/
sudo mv /tmp/GeoLite2-City.mmdb /usr/share/GeoIP/

# Config — eski VPS'ten kopyala:
sudo scp /etc/promtail-config.yml tucibeyin@YENİ_VPS_IP:/tmp/
sudo cp /tmp/promtail-config.yml /etc/promtail-config.yml
```

Systemd unit:

```bash
sudo tee /etc/systemd/system/promtail.service > /dev/null <<'EOF'
[Unit]
Description=Promtail log shipper
After=network.target

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail-config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now promtail
```

> Config'de `worker.log` da dahil olmalı — promtail-config.yml içinde `teqlif-worker-log` job'ı mevcut olduğunu kontrol et.

### 6.3 Prometheus

```bash
# Eski VPS'ten binary ve config kopyala:
scp /usr/local/bin/prometheus tucibeyin@YENİ_VPS_IP:/tmp/
sudo cat /etc/prometheus/prometheus.yml > /tmp/prometheus.yml
scp /tmp/prometheus.yml tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo useradd -r -s /sbin/nologin prometheus 2>/dev/null || true
sudo mv /tmp/prometheus /usr/local/bin/prometheus
sudo chmod +x /usr/local/bin/prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
sudo cp /tmp/prometheus.yml /etc/prometheus/prometheus.yml
```

Systemd unit:

```bash
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

### 6.4 Grafana

```bash
sudo apt install -y apt-transport-https
wget -q -O - https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
```

#### Dashboard'ları Taşı (grafana.db kopyala)

```bash
# Eski VPS'te:
sudo systemctl stop grafana-server
sudo scp /var/lib/grafana/grafana.db tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo systemctl stop grafana-server
sudo cp /tmp/grafana.db /var/lib/grafana/grafana.db
sudo chown grafana:grafana /var/lib/grafana/grafana.db
sudo systemctl start grafana-server

# Eski VPS'te tekrar başlat:
sudo systemctl start grafana-server
```

#### ClickHouse Plugin

```bash
sudo GF_PATHS_HOME=/usr/share/grafana \
  /usr/share/grafana/bin/grafana cli \
  --homepath /usr/share/grafana \
  plugins install grafana-clickhouse-datasource
sudo systemctl restart grafana-server
```

### 6.5 node_exporter

```bash
# Eski VPS'ten binary kopyala:
scp /usr/local/bin/node_exporter tucibeyin@YENİ_VPS_IP:/tmp/

# Yeni VPS'te:
sudo mv /tmp/node_exporter /usr/local/bin/node_exporter
sudo chmod +x /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### 6.6 prometheus-postgres-exporter

```bash
sudo apt install -y prometheus-postgres-exporter

# PostgreSQL kullanıcısı oluştur (Unix socket ile bağlanır):
sudo -u postgres psql -c "CREATE USER prometheus;"
sudo -u postgres psql -c "GRANT pg_monitor TO prometheus;"

# EnvironmentFile'ı yapılandır:
sudo tee /etc/default/prometheus-postgres-exporter > /dev/null <<'EOF'
DATA_SOURCE_NAME='user=prometheus host=/run/postgresql dbname=postgres'
ARGS=""
EOF

# Override dosyası varsa kaldır (User=prometheus ile çalışmalı):
sudo rm -f /etc/systemd/system/prometheus-postgres-exporter.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus-postgres-exporter

# Doğrula:
curl -s "http://localhost:9090/api/v1/query?query=pg_up" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('pg_up =', d['data']['result'][0]['value'][1])"
```

> **Not:** v0.17'de `DATA_SOURCE_NAME` env var hala desteklenir ama servis `prometheus` OS kullanıcısıyla çalışmalıdır — EnvironmentFile bu kullanıcıya ait (`prometheus:prometheus`). Override ile `User=postgres` gibi farklı bir kullanıcı ayarlanırsa dosya okunamaz ve "empty dsn" hatası çıkar.

---

## Faz 7 — DNS Geçişi (Squarespace)

### 7.1 TTL'i Düşür (24 Saat Önce)

DNS panelinde tüm kayıtların TTL'ini **60 saniye**'ye düşür.

### 7.2 A Kayıtlarını Güncelle

| Host | Tip | Yeni Değer |
|------|-----|------------|
| `teqlif.com` | A | `YENİ_VPS_IP` |
| `www.teqlif.com` | A | `YENİ_VPS_IP` |
| `admin.teqlif.com` | A | `YENİ_VPS_IP` |
| `live.teqlif.com` | A | `YENİ_VPS_IP` |

### 7.3 Yayılmayı Doğrula

```bash
watch -n 10 "dig teqlif.com +short"
# YENİ_VPS_IP çıkana kadar bekle

curl -I https://teqlif.com/api/health
```

---

## Faz 8 — Dış Servis Kontrolleri

| Servis | Yapılacak |
|--------|-----------|
| Firebase | JSON kopyalandı — ek işlem yok |
| APNs | `.p8` kopyalandı, `APNS_USE_SANDBOX=False` — kontrol et |
| Brevo | SPF kaydında eski IP varsa güncelle |
| LiveKit | `node_ip` config'de yeni IP'ye güncellendi |
| Sentry | Otomatik çalışır |

#### Brevo SPF

```bash
dig TXT teqlif.com | grep spf
# Eski IP (örn. 51.81.34.27) varsa DNS panelinden güncelle
```

---

## Günlük Kullanım

```bash
# Kod güncelle
cd /var/www/teqlif.com
git pull
sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical

# Log izle
journalctl -u teqlif -f

# Çeviri güncelle
cd /var/www/teqlif.com/backend
source /var/www/teqlif.com/venv/bin/activate
python3 scripts/sync_translations.py

# Migration çalıştır
alembic upgrade head
```

---

## Kontrol Listesi

```
### Sistem
[x] apt upgrade tamamlandı
[x] Python 3.13 (Debian 13 native — PPA gerekmez)
[x] Dizin yapısı oluşturuldu
[x] UFW aktif (SSH, Nginx Full, LiveKit, TURN, Grafana, Cloudflare IP'leri)
[x] Fail2ban aktif (3 jail: nginx-botscan, nginx-req-limit, sshd)

### Servisler
[x] PostgreSQL 17 + pgvector
[x] DB ve kullanıcı oluşturuldu (vector + pg_trgm extension)
[x] Redis — config eski VPS'ten kopyalandı
[x] ClickHouse — resmi install script kullanıldı
[x] MinIO — /var/minio/data, port 9010, /etc/minio.env
[x] Nginx — config eski VPS'ten kopyalandı

### Uygulama
[x] Git SSH anahtarı kuruldu, repo klonlandı
[x] venv + pip install (ML paketler dahil)
[x] .env oluşturuldu (ADMIN_PASSWORD_HASH dahil)
[x] Sertifika dosyaları kopyalandı (p8, voip_cert, firebase JSON)
[x] DB şeması pg_dump --schema-only ile uygulandı
[x] alembic stamp head çalıştırıldı
[x] PostgreSQL verisi taşındı (pg_dump --data-only — 8 kullanıcı, 12020 çeviri, 970 ilçe)
[x] MinIO verisi taşındı (80 obje — /var/minio/data/teqlif/)
[x] Systemd unit'ler kuruldu (teqlif, workers, redis-backup.timer)
[x] PartOf override'lar uygulandı (teqlif-worker, teqlif-worker-critical)
[x] www-data sahipliği ayarlandı

### LiveKit
[x] Binary eski VPS'ten kopyalandı (v1.13.3)
[x] /etc/livekit/livekit.yaml — node_ip 135.125.175.223 olarak güncellendi
[x] TURN sertifikaları kopyalandı
[x] livekit sistem kullanıcısı oluşturuldu
[x] Systemd unit kuruldu, aktif

### Nginx + SSL
[x] Config eski VPS'ten kopyalandı
[x] SSL sertifikaları taşındı (/etc/letsencrypt/)
[x] nginx -t başarılı

### Monitoring
[x] Loki 3.6.7 — binary + config eski VPS'ten kopyalandı, retention_period=720h
[x] Promtail 3.0.0 — binary + config + GeoIP DB kopyalandı (worker.log dahil)
[x] Prometheus 2.51.0 — binary + config + prometheus kullanıcısı
[x] Grafana 13.x — grafana.db kopyalandı, ClickHouse plugin kuruldu
[x] node_exporter 1.8.2 — binary eski VPS'ten kopyalandı
[x] prometheus-postgres-exporter 0.17.1 — apt kurulum, Unix socket (prometheus kullanıcısı)

### DNS Cutover (Squarespace) — BEKLIYOR
[ ] TTL'ler 60 saniyeye düşürüldü (cutover'dan 24 saat önce)
[ ] A kayıtları 135.125.175.223'e güncellendi:
      teqlif.com / www.teqlif.com / admin.teqlif.com / live.teqlif.com
[ ] dig teqlif.com +short → 135.125.175.223
[ ] curl https://teqlif.com/api/health → 200
[ ] Certbot kuruldu, certbot.timer aktif

### Dış Servisler — BEKLIYOR
[ ] Brevo SPF kaydında eski IP varsa güncelle
[ ] Firebase bağlantısı log'larda görünüyor (app başladığında)
[ ] APNs SANDBOX=False doğrulandı
```

---

## Sorun Giderme

### `git pull` — Permission Denied (.git/objects)

**Belirti:** `error: insufficient permission for adding an object to repository database .git/objects`

**Neden:** Önceki bir `sudo git pull` ya da root işlemi `.git/objects` altında root'a ait dosya bırakmış.

**Doğru düzeltme — sadece .git dizinini düzelt, tüm repo'yu değil:**

```bash
sudo chown -R www-data:www-data /var/www/teqlif.com/.git
git pull   # tucibeyin www-data grubunda olduğu için çalışır
```

> ⚠️ `sudo chown -R tucibeyin:tucibeyin /var/www/teqlif.com` YAPMA.  
> Tüm repo'yu `tucibeyin`'e bağlarsa `www-data` `.env`, `firebase-service-account.json`,  
> `certificates/`, `logs/` gibi dosyalara erişemez — servis çöker.

**Yanlış düzeltme sonrası kurtarma** (tüm repo `tucibeyin`'e bağlandıysa):

```bash
# Tüm repo'yu tekrar www-data'ya devret
sudo chown -R www-data:www-data /var/www/teqlif.com

# Hassas dosyalar: sadece www-data okuyabilmeli
sudo chmod 600 /var/www/teqlif.com/backend/.env
sudo chmod 600 /var/www/teqlif.com/backend/firebase-service-account.json
sudo chmod 600 /var/www/teqlif.com/backend/certificates/*

# Servisin yazma ihtiyacı olan dizinler
sudo chown -R www-data:www-data /var/www/teqlif.com/backend/logs
sudo chown -R www-data:www-data /var/www/teqlif.com/uploads

sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical
```

### Sahiplik Modeli Özeti

| Yol | Sahip | İzin | Neden |
|-----|-------|------|-------|
| `/var/www/teqlif.com` (genel) | `www-data:www-data` | 755/644 | Servis `www-data` olarak çalışır |
| `backend/.env` | `www-data:www-data` | 600 | Secret — sadece www-data |
| `backend/firebase-service-account.json` | `www-data:www-data` | 600 | Secret — sadece www-data |
| `backend/certificates/*` | `www-data:www-data` | 600 | Secret — sadece www-data |
| `backend/logs/` | `www-data:www-data` | 755 | Servis buraya yazar |
| `uploads/` | `www-data:www-data` | 755 | Servis buraya yazar |

`tucibeyin` kullanıcısı `www-data` grubundadır (`usermod -aG www-data tucibeyin`) — bu sayede `git pull` ve dosya düzenlemeleri çalışır.
