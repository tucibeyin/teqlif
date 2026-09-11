# Teqlif Scale V1.3 — Task

> **Baseline:** V1.2 aktif  
> **Hedef:** V1.3 — node3 (Ashburn VA, 5.249.165.10, 10.10.0.4) 4 rolde eklenir  
> **Sıra bağımlılığı:** Faz 0 → Faz 1 → Faz 2 → Faz 3 → Faz 4 → Faz 5 → Faz 6 → Faz 7 → Faz 8  
> **Kullanıcı yok:** Sistemde aktif kullanıcı olmadığı için downtime toleransı yüksek.

## Çalışma Kuralı

Her adım için sıra:
1. **Onayla** — kullanıcı onaylar
2. **Uygula** — implement edilir
3. **Push** — `git push` (lokal değişiklik varsa)
4. **Test** — VPS'te doğrulanır
5. **Test onayı** — kullanıcı test çıktısını iletir ve onaylar
6. **task.md güncelle** — adım `[x]` işaretlenir
7. **Sonraki adım** — bir sonraki adıma geçilir

---

## Faz 0 — Repo Hazırlığı (Lokal → git push)

Tüm lokal dosya değişiklikleri **bu oturumda tamamlandı**. Doğrula ve push et.

### 0.1 Backend Kod Değişiklikleri

- [x] `backend/app/config.py` — `node2_internal_token` → `ai_proxy_internal_token`; `node3_ai_proxy_url: str = ""` eklendi
- [x] `backend/app/ai_proxy_main.py` — `settings.node2_internal_token` → `settings.ai_proxy_internal_token`
- [x] `backend/app/services/ml/ai_proxy_client.py` — `generate_via_node2` → `generate_via_proxy`; node3 secondary + 30s timeout
- [x] `backend/app/routers/listings.py` — import ve çağrı adı güncellendi (`generate_via_proxy`)
- [x] `backend/app/logging_config.py` — `LOG_NODE` env var; `{LOG_NODE}-app/error/worker.log`; worker double-write fix

### 0.2 Resource Dosya Güncellemeleri

- [x] `deploy/scale/resources/gateway/gateway_services.sh` — `prometheus loki alertmanager` SERVICES'ten çıkarıldı
- [x] `deploy/scale/resources/gateway/bootstrap_gateway.sh` — `SCALE_VERSION="V1.3"`; monitoring install blokları kaldırıldı; Loki UFW kuralı → node3 node_exporter kuralına değiştirildi
- [x] `deploy/scale/resources/node1/node1_services.sh` — `teqlif-staging` kaldırıldı
- [x] `deploy/scale/resources/node1/.env.production` — `NODE3_AI_PROXY_URL`, `AI_PROXY_INTERNAL_TOKEN`, `LOG_NODE=node1` eklendi
- [x] `deploy/scale/resources/node2/.env.production` — `AI_PROXY_INTERNAL_TOKEN` eklendi
- [x] `deploy/scale/resources/node3/` — bootstrap, services, env şablonları hazır

### 0.3 Yeni Dosyalar

- [x] `deploy/scripts/pg-backup.sh` — pg_dump + gzip + 3 gün local retention
- [x] `deploy/scripts/offsite-rsync.sh` — node3'e rsync; Redis 14 gün remote retention
- [x] `deploy/scale/V1.3/node1/systemd/teqlif-backup.service` — pg + rsync one-shot
- [x] `deploy/scale/V1.3/node1/systemd/teqlif-backup.timer` — 03:00 UTC

### 0.4 Config Dosyaları

- [x] `deploy/scale/V1.3/node1/promtail-config.yml` — push URL `10.10.0.4:3100`; dosya job'ları kaldırıldı
- [x] `deploy/scale/V1.3/node1/journald/journald.conf` — `2d / 200M`
- [x] `deploy/scale/V1.3/node2/promtail-config.yml` — push URL `10.10.0.4:3100`; `teqlif-ai-proxy` job'u kaldırıldı
- [x] `deploy/scale/V1.3/node2/journald/journald.conf` — `2d / 100M`
- [x] `deploy/scale/V1.3/gateway/promtail-config.yml` — push URL `10.10.0.4:3100`
- [x] `deploy/scale/V1.3/gateway/journald/journald.conf` — `2d / 100M`
- [x] `deploy/scale/V1.3/gateway/systemd/node_exporter.service` — `--web.listen-address=10.10.0.2:9100`
- [x] `deploy/scale/V1.3/gateway/nginx/teqlif.conf` — staging upstream `10.10.0.4:8001`
- [x] `deploy/scale/V1.3/node3/` — tüm config + systemd dosyaları hazır

### 0.5 WireGuard Şablonları

- [x] `deploy/scale/V1.3/wireguard/node1-wg0.conf` — node3 `[Peer]` bloğu eklendi (`<NODE3_PUBLIC_KEY>` placeholder)
- [x] `deploy/scale/V1.3/wireguard/node2-wg0.conf` — node3 `[Peer]` bloğu eklendi
- [x] `deploy/scale/V1.3/wireguard/gateway-wg0.conf` — node3 `[Peer]` bloğu eklendi
- [x] `deploy/scale/V1.3/wireguard/node3-wg0.conf` — hazır (diğer 3 node'un public key'lerini içeriyor; private key placeholder)

### 0.6 Mobile

- [x] `mobile/dart_defines/staging.json` — `UPLOADS_HOST=https://uploads-staging.teqlif.com`
- [x] `mobile/dart_defines/release.json` — `UPLOADS_HOST=https://uploads.teqlif.com`

### 0.7 Repo Temizliği

- [x] `deploy/scale/resources/node1/.env.node1.staging` — **silindi** (staging node3'e taşındı)
- [x] `deploy/scale/resources/node1/node1_staging_requirements.txt` — **silindi** (staging venv artık node3'te)
- [x] `deploy/scale/V1.3/gateway/prometheus.yml` — **silindi** (monitoring node3'e taşındı)
- [x] `deploy/scale/V1.3/gateway/prometheus-rules.yml` — **silindi**
- [x] `deploy/scale/V1.3/gateway/loki-config.yml` — **silindi**
- [x] `deploy/scale/V1.3/gateway/alertmanager.yml.template` — **silindi**
- [x] `deploy/scale/V1.3/gateway/systemd/prometheus.service` — **silindi**
- [x] `deploy/scale/V1.3/gateway/systemd/loki.service` — **silindi**
- [x] `deploy/scale/V1.3/gateway/systemd/alertmanager.service` — **silindi**

### 0.8 Git Push

- [x] **[Lokal]** Değişiklikleri doğrula: `git diff --stat`
- [x] **[Lokal]** Commit ve push: `8324261d` → `a54ff83d..8324261d main → main`

---

## Faz 1 — WireGuard: node3 Mesh'e Katılır

> **Ön koşul:** node3'e SSH erişimi var (5.249.165.10).  
> **Bağımlılık:** Faz 2 ve sonrası bu mesh'e bağlıdır.

### 1.1 node3 — WireGuard Kurulumu ve Key Üretimi

- [x] **[node3]** WireGuard kur ve key üret:
  ```bash
  sudo apt install -y wireguard
  sudo bash -c 'wg genkey | tee /etc/wireguard/node3_private.key | wg pubkey > /etc/wireguard/node3_public.key'
  sudo chmod 600 /etc/wireguard/node3_private.key
  sudo cat /etc/wireguard/node3_public.key   # ← bu değeri not al (NODE3_PUBLIC_KEY)
  ```

- [x] **[node3]** `/etc/wireguard/wg0.conf` oluştur — `deploy/scale/V1.3/wireguard/node3-wg0.conf`'u baz al:
  ```bash
  # Repo'dan kopyala (git pull öncesi değil — elle yaz):
  sudo nano /etc/wireguard/wg0.conf
  # <NODE3_PRIVATE_KEY> → sudo cat /etc/wireguard/node3_private.key çıktısıyla değiştir
  # Diğer 3 node'un public key'leri dosyada zaten var (placeholder değil, gerçek değerler):
  #   node1: JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=
  #   node2: t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k=
  #   gateway: 7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=
  ```

- [x] **[node3]** WireGuard başlat:
  ```bash
  sudo systemctl enable --now wg-quick@wg0
  sudo wg show
  ```

### 1.2 Diğer Node'lar — node3 [Peer] Ekle

**node3 public key'ini önceki adımda not aldın. Aşağıdaki komutlarda `<NODE3_PUBLIC_KEY>` yerine yaz.**

- [x] **[node1]** node3 peer ekle:
  ```bash
  NODE3_PUBKEY="<NODE3_PUBLIC_KEY>"
  # Runtime ekle:
  sudo wg set wg0 peer "$NODE3_PUBKEY" \
    allowed-ips 10.10.0.4/32 \
    endpoint 5.249.165.10:51820 \
    persistent-keepalive 25
  # Kalıcı yap — /etc/wireguard/wg0.conf sonuna ekle:
  printf '\n[Peer]  # node3 — Zap-Hosting Ashburn VA\nPublicKey = %s\nAllowedIPs = 10.10.0.4/32\nEndpoint = 5.249.165.10:51820\nPersistentKeepalive = 25\n' "$NODE3_PUBKEY" | sudo tee -a /etc/wireguard/wg0.conf
  ```

- [x] **[node2]** node3 peer ekle:
  ```bash
  NODE3_PUBKEY="<NODE3_PUBLIC_KEY>"
  sudo wg set wg0 peer "$NODE3_PUBKEY" \
    allowed-ips 10.10.0.4/32 \
    endpoint 5.249.165.10:51820 \
    persistent-keepalive 25
  printf '\n[Peer]  # node3 — Zap-Hosting Ashburn VA\nPublicKey = %s\nAllowedIPs = 10.10.0.4/32\nEndpoint = 5.249.165.10:51820\nPersistentKeepalive = 25\n' "$NODE3_PUBKEY" | sudo tee -a /etc/wireguard/wg0.conf
  ```

- [x] **[gateway]** node3 peer ekle:
  ```bash
  NODE3_PUBKEY="<NODE3_PUBLIC_KEY>"
  sudo wg set wg0 peer "$NODE3_PUBKEY" \
    allowed-ips 10.10.0.4/32 \
    endpoint 5.249.165.10:51820 \
    persistent-keepalive 25
  printf '\n[Peer]  # node3 — Zap-Hosting Ashburn VA\nPublicKey = %s\nAllowedIPs = 10.10.0.4/32\nEndpoint = 5.249.165.10:51820\nPersistentKeepalive = 25\n' "$NODE3_PUBKEY" | sudo tee -a /etc/wireguard/wg0.conf
  ```

### 1.3 Doğrulama

- [x] **[node1]** Ping testi:
  ```bash
  ping -c 3 10.10.0.4   # node3'e
  ping -c 3 10.10.0.3   # node2 — mevcut, bozulmamalı
  ```
- [x] **[node2]** Ping testi:
  ```bash
  ping -c 3 10.10.0.4
  ```
- [x] **[gateway]** Ping testi:
  ```bash
  ping -c 3 10.10.0.4
  ```
- [x] **[node3]** Tüm node'lara ulaşıyor mu:
  ```bash
  ping -c 2 10.10.0.1   # node1
  ping -c 2 10.10.0.2   # gateway
  ping -c 2 10.10.0.3   # node2
  ```

---

## Faz 2 — node3 Bootstrap ve Servisler

> **Ön koşul:** WireGuard mesh aktif (Faz 1 ✓).

### 2.1 Git Clone ve Bootstrap

- [x] **[node3]** Repo kopyala ve bootstrap çalıştır:
  ```bash
  git clone <REPO_URL> /var/www/teqlif.com
  cd /var/www/teqlif.com
  bash deploy/scale/resources/node3/bootstrap_node3.sh
  ```
  > Bootstrap: apt paketleri, Python venv (ML dahil), MinIO binary, Prometheus/Loki/Alertmanager/node_exporter/promtail binary'leri, swap (4 GB), sysctl, journald, systemd servisleri (enable), dizin izinleri.

### 2.2 Ortam Değişkenleri

- [x] **[node3]** Production env doldur:
  ```bash
  nano /var/www/teqlif.com/deploy/scale/resources/node3/.env.production
  # Doldurulacaklar: GROQ_API_KEY, GEMINI_API_KEY, AI_PROXY_INTERNAL_TOKEN (node1/node2 ile aynı değer)
  # REDIS_URL zaten wg IP'sini gösteriyor: redis://10.10.0.1:6379
  ```

- [x] **[node3]** Staging env doldur:
  ```bash
  nano /var/www/teqlif.com/deploy/scale/resources/node3/.env.staging
  # Doldurulacaklar: SECRET_KEY, DATABASE_URL (postgresql://...@localhost:5432/teqlif_staging),
  # REDIS_URL=redis://localhost:6379/0, MINIO_ACCESS_KEY, MINIO_SECRET_KEY,
  # GROQ_API_KEY, GEMINI_API_KEY, LOG_NODE=staging, LIVEKIT_API_KEY, LIVEKIT_API_SECRET,
  # APPLE_TEAM_ID, APNS_KEY_ID, APNS_KEY_PATH, NODE2_AI_PROXY_URL, NODE3_AI_PROXY_URL,
  # AI_PROXY_INTERNAL_TOKEN (aynı değer)
  ```


- [x] **[node3]** Env izinlerini ayarla (servisler doğrudan resources'tan okur):
  ```bash
  chmod 600 /var/www/teqlif.com/deploy/scale/resources/node3/.env.production
  chmod 600 /var/www/teqlif.com/deploy/scale/resources/node3/.env.staging
  ```

### 2.3 PostgreSQL — Staging DB Hazırlığı

- [x] **[node3]** DB ve kullanıcı oluştur:
  ```bash
  sudo -u postgres psql <<'SQL'
  CREATE DATABASE teqlif_staging;
  CREATE USER teqlif WITH PASSWORD '<DB_SIFRESI>';
  GRANT ALL PRIVILEGES ON DATABASE teqlif_staging TO teqlif;
  ALTER DATABASE teqlif_staging OWNER TO teqlif;
  SQL
  ```
  > `DATABASE_URL` env'de aynı şifreyi kullan.

### 2.4 MinIO — Staging Bucket'ları

- [x] **[node3]** MinIO başlat ve bucket'ları oluştur:
  ```bash
  sudo systemctl start minio
  sudo systemctl status minio   # active?
  # MinIO CLI kur (ilk kez):
  sudo wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
  sudo chmod +x /usr/local/bin/mc
  # Alias ekle:
  mc alias set node3 http://localhost:9010 <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD>
  # Bucket'ları oluştur:
  mc mb node3/teqlif-staging
  mc mb node3/teqlif-dm-staging
  ```

### 2.5 Alertmanager Yapılandırması

- [x] **[node3]** alertmanager.yml render et:
  ```bash
  # .env.production içindeki TELEGRAM_BOT_TOKEN ve TELEGRAM_CHAT_ID'yi export et:
  set -o allexport; source /var/www/teqlif.com/deploy/scale/resources/node3/.env.production; set +o allexport
  sudo mkdir -p /etc/alertmanager
  envsubst < /var/www/teqlif.com/deploy/scale/V1.3/node3/alertmanager.yml.template \
    | sudo tee /etc/alertmanager/alertmanager.yml
  sudo chmod 640 /etc/alertmanager/alertmanager.yml
  ```

### 2.6 Backup Hedef Dizini

- [x] **[node3]** Backup dizini oluştur:
  ```bash
  sudo mkdir -p /var/backups/teqlif/pg /var/backups/teqlif/redis
  sudo chown -R tucibeyin:tucibeyin /var/backups/teqlif
  ```

### 2.7 UFW Kuralları

- [x] **[node3]** UFW kural seti:
  ```bash
  sudo ufw allow 22/tcp comment 'SSH'
  sudo ufw allow 80/tcp comment 'HTTP — uploads-staging'
  sudo ufw allow 443/tcp comment 'HTTPS — uploads-staging'
  sudo ufw allow 51820/udp comment 'WireGuard'
  sudo ufw allow in on wg0 from 10.10.0.2 to any port 8001 proto tcp comment 'staging FastAPI — gateway'
  sudo ufw allow in on wg0 to any port 8080 proto tcp comment 'AI proxy — WG mesh'
  sudo ufw allow in on wg0 to any port 3100 proto tcp comment 'Loki — WG mesh push'
  sudo ufw allow in on wg0 to any port 9100 proto tcp comment 'node_exporter — Prometheus self'
  sudo ufw --force enable
  sudo ufw status numbered
  ```

### 2.8 Servisleri Başlat

- [x] **[node3]** Tüm servisleri başlat:
  ```bash
  bash /var/www/teqlif.com/deploy/scale/resources/node3/node3_services.sh start
  ```

### 2.9 LiveKit Staging — node3

- [x] **[Lokal]** node3 LiveKit config + systemd + bootstrap güncelleme dosyaları oluştur ve push et.

- [x] **[node3]** git pull, sonra bootstrap LiveKit adımını çalıştır:
  ```bash
  git pull
  bash deploy/scale/resources/node3/bootstrap_node3.sh  # sadece LiveKit binary adımı yeniden çalışır
  ```

- [x] **[node3]** livekit.yaml yerleştir ve secret doldur:
  ```bash
  sudo mkdir -p /etc/livekit/certs
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node3/livekit.yaml /etc/livekit/livekit.yaml
  # <LIVEKIT_API_SECRET> yerine secret yaz:
  LKSECRET=$(openssl rand -hex 32)
  sudo sed -i "s|<LIVEKIT_API_SECRET>|$LKSECRET|" /etc/livekit/livekit.yaml
  echo "LIVEKIT_API_KEY=teqlif_livekit_staging"
  echo "LIVEKIT_API_SECRET=$LKSECRET"
  # Bu iki değeri .env.staging dosyasına ekle
  ```

- [x] **[node3]** TLS sertifikası al (TURN için):
  ```bash
  sudo certbot certonly --standalone -d live-staging.teqlif.com \
    --non-interactive --agree-tos -m tucibeyin@gmail.com
  sudo cp /etc/letsencrypt/live/live-staging.teqlif.com/fullchain.pem /etc/livekit/certs/
  sudo cp /etc/letsencrypt/live/live-staging.teqlif.com/privkey.pem   /etc/livekit/certs/
  sudo chmod 640 /etc/livekit/certs/*.pem
  ```
  > DNS: `live-staging.teqlif.com` A → `5.249.165.10` (CF proxy kapalı) tanımlı olmalı.

- [x] **[node3]** LiveKit servisi başlat:
  ```bash
  sudo systemctl enable --now livekit
  sudo systemctl status livekit
  ```

- [x] **[node3]** UFW — LiveKit portları:
  ```bash
  sudo ufw allow 7880/tcp comment 'LiveKit API/WebSocket staging'
  sudo ufw allow 7882/tcp comment 'LiveKit RTC/TCP staging'
  sudo ufw allow 7882/udp comment 'LiveKit RTC/UDP staging'
  sudo ufw allow 3478/udp comment 'LiveKit TURN/UDP staging'
  sudo ufw allow 5349/tcp comment 'LiveKit TURN/TLS staging'
  sudo ufw allow 50000:60000/udp comment 'LiveKit media port range staging'
  sudo ufw reload
  ```

### 2.10 Nginx — uploads-staging.teqlif.com

- [x] **[node3]** nginx config aktive et:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node3/nginx/uploads-staging.teqlif.com \
    /etc/nginx/sites-available/uploads-staging.teqlif.com
  sudo ln -sf /etc/nginx/sites-available/uploads-staging.teqlif.com \
    /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
  ```

- [x] **[node3]** SSL sertifikası al:
  ```bash
  sudo certbot --nginx -d uploads-staging.teqlif.com --non-interactive --agree-tos -m tucibeyin@gmail.com
  ```
  > DNS: `uploads-staging.teqlif.com` A → `5.249.165.10` (CF proxy kapalı) zaten tanımlı olmalı.

### 2.10 Servis Sağlık Kontrolleri

- [x] **[node3]** Servis durumları:
  ```bash
  systemctl status prometheus loki alertmanager node_exporter promtail \
    teqlif-ai-proxy minio
  # Hepsi active (running) veya active (waiting) olmalı
  ```

- [x] **[node3]** Prometheus hedefleri kontrol:
  ```bash
  curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'
  # Beklenen: node3 kendi hedefleri UP
  ```

- [x] **[node3]** Loki sağlık:
  ```bash
  curl -s http://localhost:3100/ready
  # Beklenen: "ready"
  ```

- [x] **[node3]** AI proxy sağlık:
  ```bash
  curl -s http://10.10.0.4:8080/health
  # Beklenen: 200 OK {"status":"ok"} (veya similar)
  ```

---

## Faz 3 — node1 → node3 Backup SSH Erişimi

> **Ön koşul:** WireGuard mesh aktif (Faz 1 ✓).

- [x] **[node1]** Backup için ED25519 key üret (root olarak):
  ```bash
  sudo ssh-keygen -t ed25519 -f /root/.ssh/id_backup -N "" -C "node1-backup"
  sudo cat /root/.ssh/id_backup.pub
  ```

- [x] **[node3]** node1'in public key'ini authorized_keys'e ekle:
  ```bash
  # Önceki adımın çıktısını buraya yapıştır:
  echo "<NODE1_BACKUP_PUBLIC_KEY>" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  ```

- [x] **[node1]** SSH bağlantısını test et:
  ```bash
  sudo ssh -i /root/.ssh/id_backup -o StrictHostKeyChecking=no tucibeyin@10.10.0.4 "echo OK"
  # Beklenen: OK (şifre istemeden)
  ```

---

## Faz 4 — node1 Değişiklikleri

> **Ön koşul:** Faz 1 (WG), Faz 2 (node3 çalışıyor), Faz 3 (backup SSH) tamamlandı.

### 4.1 UFW — node3 İçin Portlar Aç

- [x] **[node1]** Yeni UFW kuralları:
  ```bash
  sudo ufw allow in on wg0 from 10.10.0.4 to any port 9100 proto tcp comment 'node_exporter — node3 Prometheus'
  sudo ufw allow in on wg0 from 10.10.0.4 to any port 9187 proto tcp comment 'postgres_exporter — node3 Prometheus'
  sudo ufw allow in on wg0 from 10.10.0.4 to any port 7881 proto tcp comment 'LiveKit metrics — node3 Prometheus'
  sudo ufw allow in on wg0 from 10.10.0.4 to any port 6379 proto tcp comment 'Redis — node3 AI proxy'
  sudo ufw status numbered
  ```

### 4.2 Code Deploy (Backend + Proxy Token Rename)

- [x] **[node1]** Kodu güncelle ve yeniden başlat:
  ```bash
  cd /var/www/teqlif.com && git pull
  python3 backend/scripts/sync_translations.py
  sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical
  sudo systemctl status teqlif
  ```

- [x] **[node1]** Servis dosyalarını güncelle ve env'i resources'a taşı:
  ```bash
  cd /var/www/teqlif.com

  # Servis dosyalarını güncelle (V1.3: EnvironmentFile artık resources/node1/.env.production)
  sudo cp deploy/scale/V1.3/node1/systemd/teqlif.service /etc/systemd/system/
  sudo cp deploy/scale/V1.3/node1/systemd/teqlif-worker.service /etc/systemd/system/
  sudo cp deploy/scale/V1.3/node1/systemd/teqlif-worker-critical.service /etc/systemd/system/
  sudo cp deploy/scale/V1.3/node1/systemd/minio.service /etc/systemd/system/
  sudo systemctl daemon-reload

  # Mevcut backend/.env değerlerini resources'a taşı (tek seferlik):
  # AI_PROXY_INTERNAL_TOKEN ve NODE3_AI_PROXY_URL zaten resources'ta var (Faz 4.2'de eklenmişti)
  # Eksik diğer tüm değerleri kontrol et:
  diff <(grep -v '^#\|^$' deploy/scale/resources/node1/.env.production | cut -d= -f1 | sort) \
       <(grep -v '^#\|^$' backend/.env | cut -d= -f1 | sort)
  # Farkı görünce backend/.env'deki değerleri resources/.env.production'a ekle:
  nano deploy/scale/resources/node1/.env.production

  sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical
  ```

### 4.3 Backup Servisleri Kur

- [x] **[node1]** Scriptleri kur:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scripts/pg-backup.sh /usr/local/sbin/pg-backup.sh
  sudo cp /var/www/teqlif.com/deploy/scripts/offsite-rsync.sh /usr/local/sbin/offsite-rsync.sh
  sudo chmod +x /usr/local/sbin/pg-backup.sh /usr/local/sbin/offsite-rsync.sh
  ```

- [x] **[node1]** Systemd servis ve timer kur:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node1/systemd/teqlif-backup.service /etc/systemd/system/
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node1/systemd/teqlif-backup.timer /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now teqlif-backup.timer
  sudo systemctl list-timers teqlif-backup.timer
  ```

- [x] **[node1]** Manuel kuru koşu — backup çalışıyor mu doğrula:
  ```bash
  sudo systemctl start teqlif-backup.service
  sudo journalctl -u teqlif-backup.service -n 20
  # node3'te:
  ls -lh /var/backups/teqlif/pg/
  ```

### 4.4 journald Güncelle

- [x] **[node1]** journald retention kısalt:
  ```bash
  sudo mkdir -p /etc/systemd/journald.conf.d
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node1/journald/journald.conf \
    /etc/systemd/journald.conf.d/99-teqlif.conf
  sudo systemctl restart systemd-journald
  ```

### 4.5 Promtail — Push URL'i node3'e Çevir

- [x] **[node1]** promtail config güncelle:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node1/promtail-config.yml /etc/promtail-config.yml
  sudo systemctl restart promtail
  sudo systemctl status promtail
  ```
  > Loki'de node1 logları gelmeye başlamalı: `curl -s "http://10.10.0.4:3100/loki/api/v1/query?query={node=\"node1\"}" | python3 -m json.tool`

---

## Faz 5 — gateway Değişiklikleri

> **Ön koşul:** node3 monitoring stack çalışıyor (Faz 2 ✓).  
> **Dikkat:** Önce node3'ün Prometheus scrape'ini doğrula, SONRA gateway monitoring'i durdur.

### 5.1 git pull

- [x] **[gateway]** Kodu güncelle:
  ```bash
  cd /var/www/teqlif.com && git pull
  ```

### 5.2 UFW — Loki Kuralını Kaldır, node_exporter Ekle

- [x] **[gateway]** UFW değiştir:
  ```bash
  # Loki kuralını bul ve sil:
  sudo ufw status numbered
  sudo ufw delete allow in on wg0 to any port 3100 2>/dev/null || \
    sudo ufw delete $(sudo ufw status numbered | grep "3100" | grep -o "^\[ *[0-9]*\]" | tr -d '[ ]') 2>/dev/null || true

  # node3 Prometheus için node_exporter porta izin ver:
  sudo ufw allow in on wg0 from 10.10.0.4 to any port 9100 proto tcp comment 'node_exporter — node3 Prometheus'
  sudo ufw reload
  sudo ufw status
  ```

### 5.3 node_exporter — Listen Address Değiştir

- [x] **[gateway]** node_exporter.service güncelle:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/gateway/systemd/node_exporter.service \
    /etc/systemd/system/node_exporter.service
  sudo systemctl daemon-reload
  sudo systemctl restart node_exporter
  sudo systemctl status node_exporter
  # Doğrula — WG IP'de dinliyor mu:
  ss -tlnp | grep 9100
  # Beklenen: 10.10.0.2:9100
  ```

### 5.4 Promtail — Push URL'i node3'e Çevir

- [x] **[gateway]** promtail config güncelle:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/gateway/promtail-config.yml /etc/promtail-config.yml
  sudo systemctl restart promtail
  sudo systemctl status promtail
  ```

### 5.5 journald Güncelle

- [x] **[gateway]** journald retention kısalt:
  ```bash
  sudo mkdir -p /etc/systemd/journald.conf.d
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/gateway/journald/journald.conf \
    /etc/systemd/journald.conf.d/99-teqlif.conf
  sudo systemctl restart systemd-journald
  ```

### 5.6 Nginx — Staging Upstream node3

- [x] **[gateway]** nginx config güncelle ve reload:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/gateway/nginx/teqlif.conf \
    /etc/nginx/sites-available/teqlif.conf
  sudo nginx -t && sudo systemctl reload nginx
  ```
  > staging.teqlif.com artık `10.10.0.4:8001`'e proxy yapıyor.

### 5.7 Monitoring Stack'i Durdur ve Kaldır

> **Önce doğrula:** node3 Prometheus'ta gateway node_exporter target'ı UP mu?
> ```bash
> curl -s "http://10.10.0.4:9090/api/v1/query?query=up{job=\"node-gateway\"}" | python3 -m json.tool
> ```

- [x] **[gateway]** Prometheus, Loki, Alertmanager durdur ve disable et:
  ```bash
  sudo systemctl stop prometheus loki alertmanager
  sudo systemctl disable prometheus loki alertmanager
  sudo systemctl status prometheus loki alertmanager   # inactive (dead) olmalı
  ```

- [ ] **[gateway]** Gereksiz binary'leri kaldır (opsiyonel — disk boşaltır):
  ```bash
  sudo rm -f /usr/local/bin/prometheus /usr/local/bin/promtool
  sudo rm -f /usr/local/bin/loki
  sudo rm -f /usr/local/bin/alertmanager
  # TSDB ve log verisi saklanabilir ya da temizlenebilir:
  # sudo rm -rf /var/lib/prometheus /var/lib/loki /var/lib/alertmanager
  ```

---

## Faz 6 — node2 Değişiklikleri

### 6.1 Code Deploy ve Token Rename

- [x] **[node2]** Kodu güncelle:
  ```bash
  cd /var/www/teqlif.com
  # ÖNEMLİ: git pull öncesi — mevcut değerleri yeni isimli dosyaya kopyala
  # (V1.3 refactor: .env.node2.production → .env.production)
  cp deploy/scale/resources/node2/.env.node2.production \
     deploy/scale/resources/node2/.env.production 2>/dev/null || true
  git pull
  # Servis dosyasını güncelle (.env.production'ı okuyacak şekilde):
  sudo cp deploy/scale/V1.3/node2/systemd/teqlif-ai-proxy.service /etc/systemd/system/
  sudo cp deploy/scale/V1.3/node2/systemd/cf-failover.service /etc/systemd/system/
  sudo systemctl daemon-reload
  # AI_PROXY_INTERNAL_TOKEN değerini kontrol et/doldur:
  nano deploy/scale/resources/node2/.env.production
  sudo systemctl restart teqlif-ai-proxy
  sudo systemctl status teqlif-ai-proxy
  ```

### 6.2 Promtail — Push URL'i node3'e Çevir

- [x] **[node2]** promtail config güncelle:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node2/promtail-config.yml /etc/promtail-config.yml
  sudo systemctl restart promtail
  sudo systemctl status promtail
  ```

### 6.3 journald Güncelle

- [x] **[node2]** journald retention kısalt:
  ```bash
  sudo mkdir -p /etc/systemd/journald.conf.d
  sudo cp /var/www/teqlif.com/deploy/scale/V1.3/node2/journald/journald.conf \
    /etc/systemd/journald.conf.d/99-teqlif.conf
  sudo systemctl restart systemd-journald
  ```

---

## Faz 7 — node1 Staging Temizliği

> **Ön koşul:** node3 staging stack çalışıyor ve doğrulandı (Faz 2 ✓).  
> Staging.teqlif.com `10.10.0.4:8001`'e ulaşabiliyor mu test et önce.

### 7.1 Staging Servisini Durdur

- [x] **[node1]** teqlif-staging durdur ve kaldır:
  ```bash
  sudo systemctl stop teqlif-staging
  sudo systemctl disable teqlif-staging
  sudo rm -f /etc/systemd/system/teqlif-staging.service
  sudo systemctl daemon-reload
  sudo systemctl reset-failed
  ```

### 7.2 PostgreSQL Staging DB Sil

- [x] **[node1]** teqlif_staging veritabanını sil:
  ```bash
  sudo -u postgres dropdb teqlif_staging
  sudo -u postgres psql -c "\l"   # teqlif_staging artık listede yok
  ```

### 7.3 Redis Staging Verisi Temizle

- [x] **[node1]** Redis db=1'i temizle:
  ```bash
  redis-cli -n 1 FLUSHDB
  redis-cli -n 1 DBSIZE   # Beklenen: 0
  ```

### 7.4 MinIO Staging Bucket'larını Sil

- [x] **[node1]** Opsiyonel: Önce medyayı arşivle:
  ```bash
  # İçerik varsa arşivle:
  mc mirror node1/teqlif-staging /tmp/staging-media-backup/
  ```

- [x] **[node1]** Bucket'ları sil:
  ```bash
  mc rb --force node1/teqlif-staging
  mc rb --force node1/teqlif-dm-staging
  mc ls node1   # Sadece prod bucket'lar kalmalı: teqlif, teqlif-dm
  ```

### 7.5 UFW — 8001 Kuralını Kaldır

- [x] **[node1]** 8001 UFW kuralını sil:
  ```bash
  sudo ufw status numbered
  # 8001 gateway'e açık satırı bul ve sil:
  sudo ufw delete allow in on wg0 from 10.10.0.2 to any port 8001 2>/dev/null || \
    sudo ufw delete $(sudo ufw status numbered | grep "8001" | grep -o "^\[ *[0-9]*\]" | tr -d '[ ]') 2>/dev/null || true
  sudo ufw reload
  ```

---

## Faz 8 — Final Doğrulama

### 8.1 Prometheus — Tüm Hedefler

- [x] **[node3]** Tüm scrape target'lar UP:
  ```bash
  curl -s "http://localhost:9090/api/v1/targets" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); [print(t['labels']['job'], t['health']) for t in d['data']['activeTargets']]"
  # Beklenen: node-gateway up, node-node1 up, node-node2 up, node-node3 up, livekit up, postgres up
  ```

### 8.2 Loki — Tüm Node'lardan Log Geliyor

- [x] **[node3]** Log stream kontrol:
  ```bash
  curl -sG "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool
  # Beklenen: node label değerlerinde node1, node2, gateway, node3
  ```

### 8.3 AI Proxy Fallback Zinciri

- [x] **[node1]** Fallback testi — node2 önce dene, node3'e düşmeli:
  ```bash
  # node2 proxy'ye doğrudan erişim testi (Prometheus token varsa):
  # Gerçek test için generate-description endpoint'ini çağır:
  curl -s -X POST https://www.teqlif.com/api/listings/generate-description \
    -H "Authorization: Bearer <TEST_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"title":"Test","category_slug":"electronics","lang":"tr","extra_fields":{}}' \
    | python3 -m json.tool
  # Beklenen: description + provider
  ```

### 8.4 Staging İzolasyon Testi

- [x] **[gateway]** staging.teqlif.com erişimi:
  ```bash
  curl -sk https://staging.teqlif.com/api/health
  # Beklenen: 200 {"status":"ok"} — node3'ten geliyor
  ```

- [x] **[node3]** Staging worker çalışıyor:
  ```bash
  systemctl status teqlif-worker-staging teqlif-worker-critical-staging
  ```

### 8.5 Backup Doğrulama

- [x] **[node1]** Backup dosyaları oluştu mu (kuru koşu yaptıysan):
  ```bash
  ls -lh /var/backups/pg/
  ls -lh /var/backups/redis/
  ```

- [x] **[node3]** Off-site backup ulaştı mı:
  ```bash
  ls -lh /var/backups/teqlif/pg/
  ls -lh /var/backups/teqlif/redis/
  ```

### 8.6 Alert Sistemi Testi

- [x] **[node3]** Test alert gönder:
  ```bash
  curl -s -X POST http://localhost:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d '[{"labels":{"alertname":"TestAlert","severity":"warning","node":"node3"},"annotations":{"summary":"V1.3 test alerti"}}]'
  # Telegram'dan bildirim gelmeli
  ```

### 8.7 Genel Servis Durumu

- [x] **[node1]** Prod servisleri:
  ```bash
  systemctl status teqlif teqlif-worker teqlif-worker-critical
  # teqlif-staging artık burada çalışmıyor — yoksa sorun
  systemctl status teqlif-staging 2>&1 | grep -E "inactive|not-found"
  ```

- [x] **[node3]** Tüm servisler:
  ```bash
  bash /var/www/teqlif.com/deploy/scale/resources/node3/node3_services.sh status
  ```

- [x] **[node2]** AI proxy:
  ```bash
  systemctl status teqlif-ai-proxy
  ```

---

## Bekleyen Görevler

- [ ] **node3 Swap doğrulaması** — `swapon --show` ile 4 GB swap aktif mi kontrol et. Bootstrap MinIO hatasında `set -euo pipefail` ile durmuş olabileceğinden swap kurulmamış olabilir. Kurulum: `sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab`
- [ ] **Bootstrap env izinleri** — `bootstrap_node*.sh` sonunda `chmod 600` otomatik uygulansın; şu an elle yapılıyor. Her node'un bootstrap'ına `chmod 600 "$NODE_DIR"/.env.*` satırı eklenecek.
- [ ] **Staging Sentry DSN** — `deploy/scale/resources/node3/.env.staging` içinde `SENTRY_BACKEND_DSN=` boş. Staging için Sentry projesi oluşturulunca DSN buraya girilmeli ve `sudo systemctl restart teqlif-staging` çalıştırılmalı.
- [ ] **Staging Admin Panel** — production `admin.html` → `staging.admin.html` olarak ayrılmalı; aynı fonksiyonalite ama staging URL'lerine (staging.teqlif.com) bakmalı. Şimdilik ADMIN_EMAIL/ADMIN_PASSWORD_HASH aynı değer kullanıyor.
- [ ] **Staging Telegram kanalı** — node3 `.env.production` (alertmanager) ve `.env.staging` (app) için ayrı Telegram kanalı/bot oluşturulacak. Şimdilik bu iki dosyada `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID` boş — alertmanager ve uygulama Telegram bildirimleri staging'de çalışmıyor.
- [ ] **Staging DB şema kurulumu (migration zinciri)** — `alembic upgrade head` migration zinciriyle staging DB fresh olarak oluşturulamıyor; `listings` tablosunu ALTER eden bir migration, tablo oluşturulmadan önce çalışıyor. Geçici çözüm (V1.3 setup'ta uygulandı): node1'den `pg_dump --schema-only -h 127.0.0.1 -U teqlif teqlif | psql -h 127.0.0.1 -U teqlif_staging teqlif_staging` ile şema kopyalandı, ardından `alembic stamp head` ile revision işaretlendi. Kalıcı çözüm: ya migration zinciri düzeltilmeli ya da `pg_dump` yaklaşımı bootstrap'e dokümante edilmeli. `teqlif-staging` servisi node3'te aktif çalışıyor.

---

## Notlar

### node3 Panel — 90 Günde Bir Giriş

node3'ün Zap-Hosting hesabına ilk giriş 2026-09-11. Sonraki: **~2026-12-10**.  
Giriş yapılmassa ballooning devreye girebilir (RAM 1.8 GiB'a düşer).

### Env Dosyası Düzenleme Notu

Repo'da tüm `.env` şablonları boş değerli. Production `.env` dosyaları VPS'te `/var/www/teqlif.com/.env` olarak el ile doldurulur. Her node farklı `.env` içeriğine sahip olduğundan, bir node güncellenirken yanlış değer girilmediğini `grep KEY /var/www/teqlif.com/.env` ile doğrula.

### AI_PROXY_INTERNAL_TOKEN Üretimi (İlk Kez)

```bash
openssl rand -hex 32
```
Üretilen değer node1, node2, node3'te **aynı olmalı**. WireGuard arkasında olduğu için dışarıya açık değil.

### Rollback

Herhangi bir fazda sorun çıkarsa:
- Faz 1 (WG): `sudo wg set wg0 peer <NODE3_PUBKEY>` ile peer kaldırılabilir
- Faz 4 (node1 deploy): `git revert` + redeploy
- Faz 5 (gateway monitoring): gateway'de `sudo systemctl start prometheus loki alertmanager` ile geri alınır (binary'ler silinmediyse)
- Faz 7 (staging temizliği): Geri alınamaz — bu faz için özellikle dikkatli ol
