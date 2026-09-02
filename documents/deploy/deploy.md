# Teqlif VPS Taşıma Rehberi

**Eski VPS:** `51.81.34.27`  
**Yeni VPS:** `135.125.175.223`  
**Hazırlanma tarihi:** 2026-09-02

---

## Stack Özeti

| Bileşen | Versiyon / Not |
|---------|----------------|
| Python | 3.13 |
| FastAPI + Uvicorn | 4 worker, uvloop |
| PostgreSQL | 16 |
| Redis | local, AOF+RDB |
| ClickHouse | local, port 8123 |
| MinIO | local, port 9000 — kullanıcı uploadları |
| LiveKit | self-hosted, Nginx → /rtc |
| Nginx | reverse proxy + SSL |
| ARQ workers | 2 adet: `teqlif-worker` + `teqlif-worker-critical` |
| Monitoring | Promtail → Loki → Grafana |
| Prometheus | `/metrics` endpoint |
| Systemd | 4 birim: teqlif, teqlif-worker, teqlif-worker-critical, redis-backup |

---

## Taşıma Sırası

```
Faz 0 → Eski VPS: yedek al
Faz 1 → Yeni VPS: sistem kurulumu
Faz 2 → Yeni VPS: servis kurulumları
Faz 3 → Yeni VPS: uygulama kurulumu
Faz 4 → Veri taşıma (PostgreSQL + MinIO)
Faz 5 → Nginx + SSL
Faz 6 → LiveKit
Faz 7 → Monitoring
Faz 8 → DNS geçişi (kesinti penceresi)
Faz 9 → Dış servis IP güncellemeleri
Faz 10 → Doğrulama + eski VPS kapatma
```

---

## Faz 0 — Eski VPS: Yedek Al

Yeni VPS hazır olmadan önce eski VPS'te bu adımları tamamla.

### 0.1 PostgreSQL Dump

```bash
# Eski VPS'te
sudo -u postgres pg_dump teqlif | gzip > /tmp/teqlif_pg_$(date +%F).sql.gz
ls -lh /tmp/teqlif_pg_*.sql.gz
```

### 0.2 Redis Dump

```bash
redis-cli BGSAVE
sleep 3
cp /var/lib/redis/dump.rdb /tmp/teqlif_redis_$(date +%F).rdb
```

### 0.3 .env Dosyasını Kaydet

```bash
cp /var/www/teqlif.com/backend/.env /tmp/teqlif_env_backup
```

### 0.4 Sertifika Dosyalarını Kaydet

```bash
ls /var/www/teqlif.com/backend/certificates/
# APNs .p8 dosyası ve Firebase service account JSON burada olmalı
```

### 0.5 LiveKit Config

```bash
# LiveKit binary ve config nerede çalışıyor?
which livekit-server || find /usr /opt /var -name "livekit*" 2>/dev/null | head -5
cat /etc/livekit/config.yaml 2>/dev/null || \
cat /opt/livekit/config.yaml 2>/dev/null || \
systemctl cat livekit 2>/dev/null | grep -i "config\|exec"
```

### 0.6 Nginx Config

```bash
cat /etc/nginx/sites-available/teqlif
# Bu dosyanın içeriğini sakla
```

### 0.7 MinIO Bucket İçeriği (Kritik)

MinIO verisi yeni VPS'e taşınacak. Şimdilik boyutu not al:

```bash
du -sh /var/lib/minio 2>/dev/null || \
du -sh /home/minio 2>/dev/null || \
mc du local/teqlif 2>/dev/null
```

---

## Faz 1 — Yeni VPS: Sistem Kurulumu

```bash
# Yeni VPS'e SSH ile bağlan
ssh root@135.125.175.223
```

### 1.1 Sistem Güncelleme

```bash
apt update && apt upgrade -y
apt install -y \
  build-essential curl wget git unzip \
  software-properties-common gnupg2 \
  ufw fail2ban htop jq \
  libpq-dev libssl-dev libffi-dev \
  libjpeg-dev zlib1g-dev
```

### 1.2 Python 3.13

```bash
add-apt-repository ppa:deadsnakes/ppa -y
apt update
apt install -y python3.13 python3.13-venv python3.13-dev python3-pip
python3.13 --version   # 3.13.x çıkmalı
```

### 1.3 www-data Kullanıcısı ve Dizin Yapısı

```bash
# www-data zaten mevcut olmalı (nginx ile gelir)
id www-data

mkdir -p /var/www/teqlif.com/backend
mkdir -p /var/www/teqlif.com/uploads
mkdir -p /var/www/teqlif.com/backend/logs
mkdir -p /var/www/teqlif.com/backend/certificates
mkdir -p /var/backups/redis

chown -R www-data:www-data /var/www/teqlif.com
chmod -R 755 /var/www/teqlif.com
```

### 1.4 UFW Güvenlik Duvarı

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP (Let's Encrypt + redirect)
ufw allow 443/tcp     # HTTPS
ufw allow 443/udp     # QUIC (LiveKit WebRTC)
ufw allow 7881/tcp    # LiveKit TCP fallback
ufw allow 50000:60000/udp  # LiveKit ICE UDP range (eski VPS'teki aralığı kontrol et)
ufw --force enable
ufw status
```

### 1.5 Fail2ban

```bash
systemctl enable --now fail2ban
# SSH brute-force koruması aktif
```

---

## Faz 2 — Yeni VPS: Servis Kurulumları

### 2.1 PostgreSQL 16

```bash
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
  https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

apt update
apt install -y postgresql-16 postgresql-16-pgvector

systemctl enable --now postgresql
```

#### PostgreSQL Kullanıcı ve Veritabanı Oluştur

```bash
sudo -u postgres psql <<EOF
CREATE USER teqlif WITH PASSWORD 'GUCLU_SIFRE_YAZ';
CREATE DATABASE teqlif OWNER teqlif;
\c teqlif
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOF
```

> **Not:** Şifreyi eski VPS'teki `.env` → `DATABASE_URL`'den al.

### 2.2 Redis

```bash
apt install -y redis-server

# /etc/redis/redis.conf — eski VPS ayarlarını uygula
cat > /etc/redis/redis.conf <<'EOF'
bind 127.0.0.1
port 6379
maxmemory 4gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
EOF

systemctl enable --now redis-server
redis-cli ping   # PONG çıkmalı
```

### 2.3 ClickHouse

```bash
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | \
  gpg --dearmor > /usr/share/keyrings/clickhouse.gpg

echo "deb [signed-by=/usr/share/keyrings/clickhouse.gpg] \
  https://packages.clickhouse.com/deb stable main" \
  > /etc/apt/sources.list.d/clickhouse.list

apt update
apt install -y clickhouse-server clickhouse-client

systemctl enable --now clickhouse-server
clickhouse-client --query "SELECT version()"   # versiyon çıkmalı
```

> **Not:** ClickHouse verisi sıfırdan başlıyor — tablolar uygulama startup'ında otomatik oluşturulur (`init_clickhouse()`).

### 2.4 MinIO

```bash
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio \
  -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

wget -q https://dl.min.io/client/mc/release/linux-amd64/mc \
  -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Veri dizini
mkdir -p /var/lib/minio
useradd -r -s /sbin/nologin minio-user 2>/dev/null || true
chown minio-user:minio-user /var/lib/minio

# Systemd unit
cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
User=minio-user
Group=minio-user
WorkingDirectory=/var/lib/minio
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server /var/lib/minio --console-address ":9001"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# MinIO credentials — eski VPS'ten al: MINIO_ACCESS_KEY / MINIO_SECRET_KEY
cat > /etc/default/minio <<EOF
MINIO_ROOT_USER=ESKİ_ACCESS_KEY
MINIO_ROOT_PASSWORD=ESKİ_SECRET_KEY
MINIO_VOLUMES="/var/lib/minio"
EOF

chmod 600 /etc/default/minio
systemctl daemon-reload
systemctl enable --now minio
```

### 2.5 Nginx

```bash
apt install -y nginx
systemctl enable nginx
```

### 2.6 Certbot

```bash
apt install -y certbot python3-certbot-nginx
```

---

## Faz 3 — Uygulama Kurulumu

### 3.1 Kodu Çek

```bash
cd /var/www/teqlif.com
git clone https://github.com/tucibeyin/teqlif.git .
# veya belirli bir dizine:
# git clone https://github.com/tucibeyin/teqlif.git /tmp/teqlif_repo
# cp -r /tmp/teqlif_repo/backend /var/www/teqlif.com/backend
```

### 3.2 Python Virtual Environment

```bash
cd /var/www/teqlif.com
python3.13 -m venv venv
source venv/bin/activate

pip install --upgrade pip wheel
pip install -r backend/requirements.txt
```

> **Not:** `sentence-transformers`, `faiss-cpu`, `nudenet` gibi ML paketleri büyük ve yavaş yüklenir. Sabırlı ol.

### 3.3 .env Dosyası

Eski VPS'ten kopyala:

```bash
# Lokal makineden (ya da eski VPS'ten direkt):
scp root@51.81.34.27:/var/www/teqlif.com/backend/.env \
    /tmp/teqlif_env

scp /tmp/teqlif_env root@135.125.175.223:/var/www/teqlif.com/backend/.env
```

Yeni VPS'te dosya izinlerini ayarla:

```bash
chmod 600 /var/www/teqlif.com/backend/.env
chown www-data:www-data /var/www/teqlif.com/backend/.env
```

#### .env İçinde Güncellenmesi Gereken Satırlar

Eski VPS'ten gelen `.env`'de aşağıdaki satırları kontrol et ve gerekirse güncelle:

```bash
nano /var/www/teqlif.com/backend/.env
```

| Değişken | Kontrol Notu |
|----------|-------------|
| `DATABASE_URL` | `localhost` kalır — değişmez |
| `REDIS_URL` | `localhost` kalır — değişmez |
| `UPLOAD_DIR` | `/var/www/teqlif.com/uploads` kalır — değişmez |
| `SITE_URL` | `https://www.teqlif.com` kalır — değişmez |
| `LIVEKIT_URL` | `wss://teqlif.com/rtc` kalır — değişmez |
| `APNS_KEY_PATH` | `/var/www/teqlif.com/backend/certificates/AuthKey_...p8` — sertifika kopyalanınca geçerli olur |
| `FIREBASE_SERVICE_ACCOUNT` | sertifika kopyalanınca geçerli olur |

### 3.4 Sertifika Dosyalarını Kopyala

```bash
# Eski VPS'ten
scp -r root@51.81.34.27:/var/www/teqlif.com/backend/certificates/ \
    /var/www/teqlif.com/backend/

chown -R www-data:www-data /var/www/teqlif.com/backend/certificates/
chmod 600 /var/www/teqlif.com/backend/certificates/*
```

### 3.5 Alembic Migration

```bash
cd /var/www/teqlif.com/backend
source /var/www/teqlif.com/venv/bin/activate

alembic upgrade head
```

### 3.6 Systemd Servisleri

```bash
cd /var/www/teqlif.com   # repo kökü

# Teqlif ana servis
cp deploy/systemd/teqlif.service /etc/systemd/system/
cp deploy/systemd/teqlif-worker.service /etc/systemd/system/
cp deploy/systemd/teqlif-worker-critical.service /etc/systemd/system/

# Redis backup
cp deploy/systemd/redis-backup.service /etc/systemd/system/
cp deploy/systemd/redis-backup.timer /etc/systemd/system/

# Redis backup script
bash deploy/scripts/redis-backup.sh --install

systemctl daemon-reload

# Servisleri etkinleştir (henüz başlatma — DNS geçişinden sonra)
systemctl enable teqlif
systemctl enable teqlif-worker
systemctl enable teqlif-worker-critical
```

---

## Faz 4 — Veri Taşıma

### 4.1 PostgreSQL: Eski → Yeni

```bash
# Eski VPS'te dump al (zaten aldıysan 0.1'i atla)
sudo -u postgres pg_dump teqlif | gzip > /tmp/teqlif_pg_latest.sql.gz

# Dump'ı yeni VPS'e kopyala
scp root@51.81.34.27:/tmp/teqlif_pg_latest.sql.gz /tmp/

# Yeni VPS'te restore et
gunzip -c /tmp/teqlif_pg_latest.sql.gz | sudo -u postgres psql teqlif

# Doğrulama
sudo -u postgres psql -d teqlif -c "\dt" | head -20
sudo -u postgres psql -d teqlif -c "SELECT COUNT(*) FROM users;"
```

### 4.2 MinIO: Eski → Yeni

MinIO verisini `mc mirror` ile taşı. **Eski VPS çalışırken yap**, büyük dosyalar varsa birkaç saat sürebilir.

```bash
# Yeni VPS'te — mc (MinIO Client) yapılandır
mc alias set old-vps http://51.81.34.27:9000 ESKİ_ACCESS_KEY ESKİ_SECRET_KEY
mc alias set new-vps http://127.0.0.1:9000 YENİ_ACCESS_KEY YENİ_SECRET_KEY

# Bucket oluştur
mc mb new-vps/teqlif

# Mirror (kopyala)
mc mirror old-vps/teqlif new-vps/teqlif --overwrite --preserve

# Doğrulama
mc du old-vps/teqlif
mc du new-vps/teqlif
# İki taraf eşit boyut göstermeli
```

> **Not:** DNS geçişinden hemen önce bir kez daha `mc mirror` çalıştırarak son değişiklikleri yakala.

### 4.3 Redis Taşıma (Opsiyonel)

Redis çoğunlukla ephemeral veri tutar (oturum cache, request counter). Taşımak istersen:

```bash
# Eski VPS'te
redis-cli BGSAVE
sleep 5
scp root@51.81.34.27:/var/lib/redis/dump.rdb /tmp/

# Yeni VPS'te (Redis durdur → dosyayı koy → başlat)
systemctl stop redis-server
cp /tmp/dump.rdb /var/lib/redis/dump.rdb
chown redis:redis /var/lib/redis/dump.rdb
systemctl start redis-server
redis-cli DBSIZE  # key sayısı çıkmalı
```

---

## Faz 5 — Nginx + SSL

### 5.1 Geçici HTTP Config (SSL almadan önce)

```bash
cat > /etc/nginx/sites-available/teqlif <<'EOF'
server {
    listen 80;
    server_name teqlif.com www.teqlif.com admin.teqlif.com;

    # Let's Encrypt doğrulama
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF

ln -sf /etc/nginx/sites-available/teqlif /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

### 5.2 SSL Sertifikası Al

```bash
certbot --nginx \
  -d teqlif.com \
  -d www.teqlif.com \
  -d admin.teqlif.com \
  --non-interactive \
  --agree-tos \
  -m admin@teqlif.com
```

### 5.3 Tam Nginx Config

```bash
cat > /etc/nginx/sites-available/teqlif <<'NGINXEOF'
# Rate limiting tanımları
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=60r/s;
limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=5r/m;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

# HTTP → HTTPS
server {
    listen 80;
    server_name teqlif.com www.teqlif.com admin.teqlif.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}

# Ana site
server {
    listen 443 ssl;
    http2 on;
    server_name teqlif.com www.teqlif.com;

    ssl_certificate     /etc/letsencrypt/live/teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/teqlif.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    client_max_body_size 50M;

    # Uploads (MinIO proxy veya statik)
    location /uploads/ {
        alias /var/www/teqlif.com/uploads/;
        expires 7d;
        add_header Cache-Control "public";
    }

    # API
    location /api/ {
        limit_req zone=api_limit burst=200 delay=100;

        proxy_set_header X-Real-IP        $remote_addr;
        proxy_set_header X-Forwarded-For  $remote_addr;
        proxy_set_header Host             $host;
        proxy_set_header Upgrade          $http_upgrade;
        proxy_set_header Connection       "upgrade";

        proxy_pass http://127.0.0.1:8000;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    # Auth — daha sıkı rate limit
    location /api/auth {
        limit_req zone=auth_limit burst=5 nodelay;
        limit_conn conn_limit 3;

        proxy_set_header X-Real-IP        $remote_addr;
        proxy_set_header X-Forwarded-For  $remote_addr;
        proxy_set_header Host             $host;

        proxy_pass http://127.0.0.1:8000;
    }

    # WebSocket (mesajlaşma, canlı yayın)
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # LiveKit
    location /rtc/ {
        proxy_pass http://127.0.0.1:7880/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_read_timeout 3600s;
    }
}
NGINXEOF

nginx -t && systemctl reload nginx
```

> **Not:** Eski VPS'teki `/etc/nginx/sites-available/teqlif` içeriğini kontrol et — özel location blokları varsa buraya ekle.

---

## Faz 6 — LiveKit Kurulumu

### 6.1 Eski VPS'ten LiveKit Config'i Al

```bash
# Eski VPS'te
find / -name "livekit*" 2>/dev/null | grep -v proc
systemctl status livekit 2>/dev/null || systemctl status livekit-server 2>/dev/null
```

### 6.2 Yeni VPS'e LiveKit Kur

```bash
# Güncel sürümü kontrol et: https://github.com/livekit/livekit/releases
LIVEKIT_VERSION="1.8.2"  # eski VPS'tekiyle eşleştir

wget -q "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_linux_amd64.tar.gz" \
  -O /tmp/livekit.tar.gz
tar xzf /tmp/livekit.tar.gz -C /usr/local/bin livekit-server
chmod +x /usr/local/bin/livekit-server
livekit-server --version
```

### 6.3 LiveKit Config Dosyası

Eski VPS'teki config'i kopyala ve `node_ip`'i güncelle:

```bash
# Eski VPS'ten al
scp root@51.81.34.27:/etc/livekit/config.yaml /tmp/livekit_config.yaml

# Yeni VPS'e kopyala
mkdir -p /etc/livekit
cp /tmp/livekit_config.yaml /etc/livekit/config.yaml

# node_ip satırını yeni IP ile güncelle
sed -i 's/51\.81\.34\.27/135.125.175.223/g' /etc/livekit/config.yaml
nano /etc/livekit/config.yaml  # gözden geçir
```

Örnek config yapısı (eski config yoksa oluştur):

```yaml
# /etc/livekit/config.yaml
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: true
  node_ip: "135.125.175.223"
keys:
  # .env'deki LIVEKIT_API_KEY / LIVEKIT_API_SECRET ile eşleşmeli
  api_key_buraya: api_secret_buraya
logging:
  level: info
```

### 6.4 LiveKit Systemd

```bash
cat > /etc/systemd/system/livekit.service <<EOF
[Unit]
Description=LiveKit Server
After=network.target

[Service]
ExecStart=/usr/local/bin/livekit-server --config /etc/livekit/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable livekit
```

---

## Faz 7 — Monitoring Kurulumu

### 7.1 Loki

```bash
LOKI_VERSION="3.3.2"
wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip" \
  -O /tmp/loki.zip
unzip -q /tmp/loki.zip -d /usr/local/bin
chmod +x /usr/local/bin/loki-linux-amd64
ln -sf /usr/local/bin/loki-linux-amd64 /usr/local/bin/loki

mkdir -p /etc/loki /var/lib/loki

cat > /etc/loki/config.yaml <<'EOF'
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
storage_config:
  tsdb_shipper:
    active_index_directory: /var/lib/loki/index
    cache_location: /var/lib/loki/index_cache
  filesystem:
    directory: /var/lib/loki/chunks
limits_config:
  reject_old_samples: false
EOF

cat > /etc/systemd/system/loki.service <<EOF
[Unit]
Description=Loki Log Aggregation
After=network.target

[Service]
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now loki
```

### 7.2 Promtail

```bash
PROMTAIL_VERSION="3.3.2"
wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip" \
  -O /tmp/promtail.zip
unzip -q /tmp/promtail.zip -d /usr/local/bin
chmod +x /usr/local/bin/promtail-linux-amd64
ln -sf /usr/local/bin/promtail-linux-amd64 /usr/local/bin/promtail

mkdir -p /etc/promtail

# Repo'daki config'i kopyala
cp /var/www/teqlif.com/deploy/promtail-config.yml /etc/promtail/config.yml

cat > /etc/systemd/system/promtail.service <<EOF
[Unit]
Description=Promtail Log Shipper
After=network.target loki.service

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now promtail
```

### 7.3 Grafana

```bash
wget -q https://dl.grafana.com/oss/release/grafana_11.4.0_amd64.deb \
  -O /tmp/grafana.deb
dpkg -i /tmp/grafana.deb

systemctl enable --now grafana-server
# Grafana: http://135.125.175.223:3000 (admin / admin)
# → Loki datasource ekle: http://localhost:3100
```

> **Güvenlik:** Grafana portunu (3000) UFW'da dışarıya kapatmalısın. Erişim için SSH tüneli kullan:
> ```bash
> ssh -L 3000:localhost:3000 root@135.125.175.223
> # Sonra tarayıcıda: http://localhost:3000
> ```

---

## Faz 8 — DNS Geçişi (Kesinti Penceresi)

Bu faz gerçek trafiği yönlendirir. **Servislerin yeni VPS'te çalıştığından emin olduktan sonra** yap.

### 8.1 Servisleri Başlat (Yeni VPS)

```bash
# Önce test et
cd /var/www/teqlif.com/backend
source /var/www/teqlif.com/venv/bin/activate
python -c "from app.config import settings; print('Config OK')"

# Servisleri başlat
systemctl start teqlif
systemctl start teqlif-worker
systemctl start teqlif-worker-critical
systemctl start livekit

# Durum kontrolü
systemctl status teqlif --no-pager
systemctl status teqlif-worker --no-pager
journalctl -u teqlif -n 50 --no-pager
```

### 8.2 DNS TTL'i Düşür (geçişten 24 saat önce)

DNS yönetim panelinde (Cloudflare veya domain registrar):
- `teqlif.com` A kaydı TTL → **60 saniye**
- `www.teqlif.com` A kaydı TTL → **60 saniye**
- `admin.teqlif.com` A kaydı TTL → **60 saniye**

### 8.3 DNS A Kayıtlarını Güncelle

DNS panelinde tüm A kayıtlarını güncelle:

| Host | Tip | Eski Değer | Yeni Değer |
|------|-----|------------|------------|
| `teqlif.com` | A | `51.81.34.27` | `135.125.175.223` |
| `www.teqlif.com` | A | `51.81.34.27` | `135.125.175.223` |
| `admin.teqlif.com` | A | `51.81.34.27` | `135.125.175.223` |

### 8.4 Yayılmayı İzle

```bash
# DNS yayılmasını kontrol et
watch -n 10 "dig teqlif.com +short"
# 135.125.175.223 çıkana kadar bekle

# SSL sertifika geçerlilik kontrolü
curl -I https://teqlif.com/api/health
```

### 8.5 DNS'ten Hemen Sonra — Son MinIO Sync

```bash
# Yeni VPS'te — DNS geçişinden hemen sonra kalan dosyaları yakala
mc mirror old-vps/teqlif new-vps/teqlif --overwrite --newer-than 1h
```

---

## Faz 9 — Dış Servis IP Güncellemeleri

### 9.1 Firebase Console

Firebase FCM giden bağlantılarda IP kısıtlaması **uygulamaz**. Ancak Service Account üzerinde IP kısıtı varsa:

1. [Firebase Console](https://console.firebase.google.com) → Proje ayarları → Servis hesapları
2. Google Cloud Console → IAM → Service Accounts → `firebase-adminsdk-...@...` → Keys sekmesi
3. IP kısıtı yoksa işlem gerekmez.

### 9.2 Google Cloud Console (OAuth)

Google OAuth, sunucu IP'si ile ilgilenmez (sadece redirect URI doğrular). Değişiklik gerekmez.

### 9.3 Apple APNs

Apple APNs, sunucu IP kısıtlaması uygulamaz. `.p8` dosyası kopyalandıysa çalışır.

### 9.4 Brevo (E-posta)

Brevo outbound API çağrısıdır, IP kısıtlaması yoktur. Ancak e-posta **deliverability** için:
- Yeni VPS IP'si için SPF kaydına eklenmiş mi kontrol et
- Brevo panelinde → Senders → Domain Authentication → SPF/DKIM kayıtları

Mevcut DNS SPF kaydı:
```
v=spf1 include:spf.brevo.com ... ip4:51.81.34.27 ...
```

Varsa `ip4:51.81.34.27` → `ip4:135.125.175.223` olarak güncelle.

### 9.5 Sentry

Sentry cloud tabanlıdır, IP kısıtlaması yoktur. Otomatik çalışır.

### 9.6 Cloudflare (Captcha / Turnstile)

Turnstile domain tabanlı doğrulama yapar, IP kısıtlaması yoktur. Domain adı aynı kaldığı için değişiklik gerekmez.

### 9.7 LiveKit (Self-hosted)

LiveKit config `node_ip`'i Faz 6'da güncellendi. Ek adım yok.

---

## Faz 10 — Doğrulama

### Servis Sağlık Kontrolleri

```bash
# Yeni VPS'te
systemctl status teqlif teqlif-worker teqlif-worker-critical livekit minio --no-pager
journalctl -u teqlif --since "5 min ago" --no-pager

# API sağlık
curl -s https://teqlif.com/api/health | python3 -m json.tool

# DB bağlantısı
sudo -u postgres psql -d teqlif -c "SELECT COUNT(*) FROM users;"

# Redis
redis-cli PING && redis-cli DBSIZE

# ClickHouse
clickhouse-client --query "SHOW TABLES"

# MinIO
mc ls new-vps/teqlif | tail -5
```

### Test Scripti

```bash
cd /var/www/teqlif.com/backend
python3 scripts/test_privacy_block.py
# API endpoint'lerini gerçek kullanıcılarla test eder
```

### Eski VPS'i Kapat

Her şey doğrulandıktan sonra (en az 48 saat bekle):

```bash
# Eski VPS'te servisleri durdur
systemctl stop teqlif teqlif-worker teqlif-worker-critical livekit
# Sonra VPS'i sil / kapat
```

---

## Sertifika Otomatik Yenileme

Certbot yenileme zaten cron'a eklenir. Kontrol et:

```bash
systemctl status certbot.timer
# veya
crontab -l | grep certbot
```

Yoksa ekle:

```bash
echo "0 3 * * * root certbot renew --quiet && systemctl reload nginx" \
  > /etc/cron.d/certbot-renew
```

---

## Hızlı Komut Referansı

```bash
# Teqlif güncelle (normal deploy)
cd /var/www/teqlif.com && git pull && sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical

# Log izle
journalctl -u teqlif -f

# Servis durumu
systemctl status teqlif teqlif-worker teqlif-worker-critical livekit minio --no-pager

# Çeviri güncelle
cd /var/www/teqlif.com/backend && source ../venv/bin/activate && python3 scripts/sync_translations.py

# Alembic migration
cd /var/www/teqlif.com/backend && source ../venv/bin/activate && alembic upgrade head
```

---

## Kontrol Listesi

```
### Hazırlık
[ ] PostgreSQL dump alındı
[ ] Redis dump alındı
[ ] .env yedeklendi
[ ] Sertifika dosyaları yedeklendi
[ ] LiveKit config kopyalandı
[ ] Nginx config kopyalandı
[ ] MinIO boyutu not edildi

### Yeni VPS Kurulum
[ ] Sistem paketleri kuruldu
[ ] Python 3.13 kuruldu
[ ] PostgreSQL 16 + pgvector kuruldu
[ ] Redis kuruldu ve yapılandırıldı
[ ] ClickHouse kuruldu
[ ] MinIO kuruldu
[ ] Nginx kuruldu
[ ] Certbot kuruldu

### Uygulama
[ ] Git repo klonlandı
[ ] venv oluşturuldu, pip install tamamlandı
[ ] .env kopyalandı ve izinler ayarlandı
[ ] Sertifika dosyaları kopyalandı
[ ] Alembic upgrade head çalıştı
[ ] Systemd unit'ler kuruldu ve etkinleştirildi

### Veri
[ ] PostgreSQL restore edildi
[ ] MinIO mirror tamamlandı ve boyutlar eşleşti
[ ] Redis restore edildi (opsiyonel)

### Nginx + SSL
[ ] SSL sertifikası alındı
[ ] Nginx config uygulandı
[ ] nginx -t başarılı

### LiveKit
[ ] Binary kuruldu
[ ] Config kopyalandı, node_ip güncellendi
[ ] Systemd unit kuruldu

### Monitoring
[ ] Loki kuruldu ve çalışıyor
[ ] Promtail kuruldu ve çalışıyor
[ ] Grafana kuruldu ve çalışıyor

### DNS Geçişi
[ ] TTL 60 saniyeye düşürüldü (24 saat önce)
[ ] Tüm A kayıtları 135.125.175.223 olarak güncellendi
[ ] DNS yayılması doğrulandı
[ ] SSL çalışıyor
[ ] Son MinIO sync yapıldı

### Dış Servisler
[ ] Firebase Console kontrol edildi (IP kısıtı varsa güncellendi)
[ ] SPF kaydı güncellendi (Brevo için)
[ ] LiveKit node_ip güncellendi

### Doğrulama
[ ] Tüm servisler çalışıyor
[ ] API sağlık kontrolü geçti
[ ] Test scripti çalıştı
[ ] 48 saat beklendi
[ ] Eski VPS kapatıldı
```
