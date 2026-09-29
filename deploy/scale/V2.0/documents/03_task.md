# V2.0 Görev Takip Listesi

**Kaynak:** [02_plan.md](02_plan.md)  
**Son Güncelleme:** 2026-09-29  
**Durum Açıklaması:** `[ ]` = Bekliyor · `[x]` = Tamamlandı · `[-]` = İptal / Geçerli Değil

---

## §0.0 — Secrets Üretimi (Lokalde — Tek Seferlik)

- [ ] `~/teqlif-secrets.env` oluştur → `chmod 600` → asla repoya ekleme
- [ ] `teqlif_db_password` üret → `openssl rand -hex 32`
- [ ] `replicator_password` üret
- [ ] `core_redis_pass` üret
- [ ] `orch_redis_pass` üret
- [ ] `guardian_redis_pass` üret
- [ ] `teqlif_ch_password` üret
- [ ] `secret_key` üret (prod JWT)
- [ ] `staging_secret_key` üret (staging JWT — prod'dan farklı)
- [ ] `staging_pg_pass` üret
- [ ] `staging_redis_pass` üret
- [ ] `minio_staging_root_user` + `minio_staging_root_password` üret
- [ ] `livekit_staging_api_key` + `livekit_staging_api_secret` üret
- [ ] `minio_root_user` + `minio_root_password` üret
- [ ] `ai_proxy_internal_token` üret
- [ ] External servis credential'larını panellerden al: LiveKit, Brevo, Firebase, APNS, Google, Sentry, Telegram, CF Turnstile → dosyaya ekle

---

## Faz 0 — Kod Hazırlığı (Lokalde)

### 0.1 — `edge_orchestrator.py` Kaldırma

- [ ] `backend/app/services/edge_orchestrator.py` sil
- [ ] Import eden tüm router/servis dosyalarında referansları temizle (~10 dosya)
- [ ] `config.py`'den kaldır: `edge_livekit_urls` (harici), `edge_minio_urls` (harici), `minio_storage_quota_percent`, `edge_metrics_interval_sec`

### 0.2 — Guardian Altyapısı — Redis + Local Agent

#### 0.2.1 — Redis Altyapısı

- [ ] `config.py`: `orch_redis_url: str`, `guardian_redis_url: str` ekle
- [ ] `redis_client.py`: `get_orch_redis()`, `get_guardian_redis()` fonksiyonları ekle
- [ ] `backend/app/services/orch_client.py` oluştur — 4 kademeli fallback:
  - Kademe 1: Orch-redis `orch:routing:*` key'leri
  - Kademe 2: `/var/lib/teqlif/guardian_state.json` taze (≤90s)
  - Kademe 3: Stale guardian_state.json (son bilinen topoloji)
  - Kademe 4: `config.py` hardcoded defaults (node1/node4/node7/node8)
- [ ] `get_stream_node()`, `get_storage_nodes()`, `get_ai_proxy_url()` — 4 kademeli zinciri kullanır
- [ ] Fallback seviyesi Prometheus metric olarak yayınla: `orch_client_fallback_level{level="redis|json_fresh|json_stale|config"}`

#### 0.2.2 — Guardian Agent — `backend/scripts/guardian_agent.py`

- [ ] `edge_metrics_agent.py`'ı sil
- [ ] `guardian_agent.py` oluştur — iki bağımsız goroutine:
  - **A) Local Agent (her 3s):**
    - `node.conf` okuma (YAML) → node_id, env, guardian_priority, components, network, hardware
    - psutil metrik toplama: cpu_percent, load_1m/5m/15m, ram_used_percent, swap_used_gb, disk_*, net_out_mbps, net_in_mbps, tcp_connections
    - Component health check: `type: http` → httpx GET timeout=2s; `type: cmd` → subprocess(shell=True, env=os.environ) timeout=3s
    - Rol özel telemetri: stream (livekit_active_rooms, stream_score), storage (minio_health, minio_io), gateway (nginx_active_connections, nginx_rps), core (pg_replication_lag_sec)
    - Orch-redis'e yaz: `HSET edge:metrics:{node_id}` EXPIRE 6, `HSET edge:health:{node_id}` EXPIRE 6, `HSET edge:telemetry:{node_id}` EXPIRE 10
    - `guardian_state.json` okuma → lokal routing önbelleği
    - Local healer: health=="failed" + restart count > threshold → `systemctl reset-failed + start`, `guardian:events`'e yaz
  - **B) Heartbeat + Election (her 5s UDP 9901):**
    - UDP broadcast → tüm WG peer'larına heartbeat gönder
    - Peer tablosunu tut
    - Adım 1: `SET guardian:leader EX 15 NX` → başarılı ise lider, başarısız ise takip et; `EXPIRE guardian:leader 15` (TTL yenile)
    - Redis kopma backoff: `redis_unavailable_since` takibi; 20s geçmeden Adım 2'ye geçme
    - Adım 2 (Redis 20s+ kapalı): UDP priority karşılaştırma; lider → sadece Telegram CRITICAL alert, coordinator_loop başlatma (V2.0 sınırı)
- [ ] `ALLOWED_COMMANDS`: systemctl çağrıları → `subprocess(["sudo","systemctl",...])` (direkt çağrı Permission Denied)
- [ ] HTTP server background thread → Prometheus `/metrics` endpoint `:9200`
- [ ] `guardian_state.json` atomic write: temp file → rename

### 0.3 — Storage Service + LiveKit Reconnect Fix

#### 0.3.1 — LiveKit Reconnect

- [ ] `routers/streams.py`: reconnect endpoint `stream.livekit_url` → `orch_client.get_stream_node()` ile değiştir (DB fallback olarak tut)
- [ ] `routers/calls.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `worker.py`: `allocate_node()` çağrıları → `orch_client.get_stream_node()`
- [ ] `tasks/video_tasks.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `routers/webhooks.py`: stream node referansları → `orch_client`

#### 0.3.2 — Storage Service — Dual-Write + URL Şeması

- [ ] `_build_public_url()`: node_id kaldır → `settings.media_host/{bucket}/{key}` döndür
- [ ] `upload_bytes()`: `asyncio.gather` ile tüm storage node'larına paralel PUT; min 1 başarılı → yükleme başarılı
- [ ] `upload_file_dm()`: aynı dual-write mantığı
- [ ] `delete_object()`: `storage_node_id` DB kolonunu okur, sadece o node'dan sil
- [ ] Alembic migration: `storage_node_id` kolonu
- [ ] `scripts/cleanup_orphaned_storage.py` ARQ job: MinIO objelerini DB ile karşılaştır, 24h grace period zorunlu, yetim dosyaları her iki node'dan sil

#### 0.3.3 — Upload Mimarisi — Presigned PUT (Gateway Bypass)

- [ ] `POST /api/upload/presign` endpoint: JWT doğrula → kota kontrol → `pending_uploads` kaydı → MinIO presigned PUT URL üret → URL'i `UPLOADS_HOST`'a rewrite et → `{upload_id, put_url, key, expires_in: 900}` döndür
- [ ] `PUT uploads.teqlif.com/{key}`: MinIO imzayı doğrular → S3'e yazar (gateway yok)
- [ ] `POST /api/upload/complete` endpoint: pending_uploads durumu `completed`'a güncelle → ARQ `process_media_upload` tetikle → `{url: media.teqlif.com/...}` döndür
- [ ] `worker.py`: `process_media_upload` ARQ task ekle (FFmpeg + Pillow + WS notify)
- [ ] Alembic migration: `pending_uploads` tablosu (`upload_id UUID PK`, `user_id FK`, `key TEXT`, `context TEXT`, `status TEXT`, `expires_at TIMESTAMP`)
- [ ] Mobile: 403 Expired URL transparent retry: PUT 403 → sessiz `/presign` yeniden → PUT tekrar (tek retry)
- [ ] `routers/streams.py`: stream thumbnail upload → presign/complete
- [ ] Tüm `UploadFile` endpoint'leri kaldır (V2.0 yeşil alan — legacy upload yok)

### 0.4 — Config Temizliği

- [ ] `config.py`: `site_url` hardcoded default kaldır
- [ ] `config.py`: `use_pgbouncer: bool = True` ekle
- [ ] `config.py`: `media_host`, `uploads_host` ekle (default yok — .env'de zorunlu)
- [ ] `config.py`: `minio_endpoint: str = "http://10.10.0.8:9000"` ekle
- [ ] `config.py`: `minio_endpoint_dm: str = "http://10.10.0.8:9000"` ekle
- [ ] `config.py`: `ai_proxy_url: str` ekle — default `http://10.10.0.3:8001`
- [ ] `config.py`: `edge_livekit_urls` default → `["http://10.10.0.1:7880", "http://10.10.0.6:7880"]` (4. kademe fallback)
- [ ] `config.py`: `edge_minio_urls` default → `["http://10.10.0.8:9000", "http://10.10.0.12:9000"]` (4. kademe fallback)
- [ ] `config.py`: `upload_presign_ttl: int = 900` ekle
- [ ] `config.py`: `clickhouse_db` default `"default"` → `"teqlif_prod_analytics"`

### 0.5 — Node Template Dosyaları

- [ ] Tüm 11 node için `resources/.env.{production,staging}.template` dosyalarını `<placeholder>` değerleriyle repoya commit et
  - gateway1, gateway2, node1, node2, node4, node5, node6, node7, node8, node9 → `.env.production.template`
  - node3 → `.env.staging.template`

### 0.6 — Guardian Koordinatör — `backend/app/guardian/`

- [ ] `backend/app/guardian/` modülü oluştur
- [ ] `topology.py`: guardian topology, components, roles, env set'lerini orch-redis'e yaz
- [ ] `service_state.py`: HEALTHY / DEGRADED / DOWN state makinesi; `alive_nodes` listesi; `degraded_since` takibi
- [ ] `job_state.py`: Job state machine — PENDING → RUNNING → INTERRUPTED / SUCCESS / FAILED / DEAD; checkpoint + resume
- [ ] `playbook.py`: Playbook sistemi — failover_storage, failover_ai, failover_gateway, failover_core, stream_rebalance, service_heal, storage_rebalance
- [ ] `routing.py`: `is_routing_eligible()` — 4 şart: traffic_eligible=true + env eşleşme + systemd active + health OK
- [ ] `coordinator.py`: Lider seçilince coordinator_loop başlat; topology değişikliğinde playbook tetikle; Prometheus /metrics endpoint
- [ ] `election.py`: Redis NX lider seçimi + UDP fallback (V2.0: basit priority karşılaştırma); Redis backoff 20s guard; election.mode=="udp" guard (coordinator_loop başlatma)
- [ ] `guardian_state.json`: `/var/lib/teqlif/guardian_state.json` — routing kararları, node sağlıkları, son güncelleme zamanı; atomic write (temp → rename)

### 0.7 — Ops Komutları

- [ ] `scripts/teqlif-restart.sh`: WG IP → rol tespiti → uygun servisleri yeniden başlat (node8=10.10.0.12=storage dahil)
- [ ] `scripts/teqlif-refresh.sh`: git pull + sync (veri servislerine dokunmaz)
- [ ] `deploy/scale/V2.0/node.conf.example`: tüm roller için örnek şablon

### 0.8 — Güvenlik Düzeltmesi

- [ ] FastAPI `--forwarded-allow-ips 10.10.0.2,10.10.0.9` (gateway1 + gateway2 WG IP'leri)

### 0.9 — Doğrulama (Lokalde)

- [ ] `python -c "from app.config import settings; print(settings.model_fields.keys())"` → hata yok
- [ ] `grep -r "edge_orchestrator" backend/app/` → 0 sonuç
- [ ] `grep -r "minio_storage_quota" backend/app/` → 0 sonuç
- [ ] `dart analyze mobile/` → 0 hata

### 0.10 — Cloudflare Güvenlik Yapılandırması (Free Tier — Dashboard)

- [ ] SSL/TLS Mode → **Full (Strict)**
- [ ] HSTS → Enable (max-age 6 months, includeSubDomains)
- [ ] Minimum TLS Version → TLS 1.2
- [ ] Security Level → **Low** (Medium/High Flutter dart:io'yu bloklar)
- [ ] Bot Fight Mode → **Devre Dışı** (non-browser UA challenge → native app trafiği bloklanır)
- [ ] Browser Integrity Check → **Devre Dışı** (native app Referer taşımaz)
- [ ] IP Access Rules: Tor → Block; bilinen scanner ASN'leri → Block
- [ ] WAF Custom Rules 5 kural: Path Traversal+SQLi (Block), kötü UA (Block), auth endpoint tehdit skoru (Managed Challenge), upload flood (JS Challenge), header anomalisi (Managed Challenge)
- [ ] Cache Rules: `media.teqlif.com/*` → Cache Everything + 1 month; `uploads.teqlif.com/*` → Bypass; `api.teqlif.com/api/*` → Bypass; `*.min.js` → Cache Everything + 1 year

### 0.11 — Mobil Kod Değişiklikleri

- [ ] `image_cache_manager.dart`: `stalePeriod` → `Duration(days: 14)`
- [ ] `video_cache_manager.dart`: `getTemporaryDirectory()` → `getApplicationSupportDirectory()`
- [ ] Logout akışı: `CacheService.clearData()` + `VideoCacheManager.instance.updateCache({}, {})` ekle
- [ ] `app_config.dart`: `mediaBaseUrl` türetme kaldır; `uploadsHost`, `mediaHost`, `shareBaseUrl`, `captchaBaseUrl` → `String.fromEnvironment(...)` ile oku
- [ ] `captcha_service.dart`: hardcoded `'https://www.teqlif.com'` → `appConfig.captchaBaseUrl`
- [ ] 14 hardcoded share URL noktasını → `appConfig.shareBaseUrl` ile değiştir
- [ ] `dart_defines/staging.json` + `release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` ekle
- [ ] Backend: `MessageOut.cache_key: Optional[str]` ekle; `_presign_if_dm()` hem `url` hem `cache_key` döndürsün
- [ ] Mobile: `CachedNetworkImage(imageUrl: signedUrl, cacheKey: msg.mediaCacheKey)` — `cacheKey` zorunlu (eksik = her 15dk yeniden indirme)
- [ ] `frontend/.well-known/assetlinks.json` oluştur (Android App Links)
- [ ] `frontend/.well-known/apple-app-site-association` oluştur (iOS Universal Links, Content-Type: application/json)

---

## Faz 1 — OS Temeli (Tüm Node'lar)

### 1.1 — Temel Paketler (Her Node)

- [ ] `apt-get update && upgrade -y`
- [ ] Paketler: curl, git, ufw, fail2ban, wireguard, chrony, htop, iotop, nethogs, unattended-upgrades, rsync, logrotate, jq, python3, python3-pip, python3-venv, python3-dev, build-essential, auditd

### 1.2 — Kullanıcı ve SSH (Her Node)

- [ ] `adduser tucibeyin` + `usermod -aG sudo`
- [ ] SSH public key → `/home/tucibeyin/.ssh/authorized_keys`
- [ ] `sshd_config`: PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3
- [ ] `systemctl restart ssh`

### 1.3 — Dizin Yapısı (Her Node)

- [ ] `/var/www/teqlif.com`, `/etc/teqlif` (chmod 700), `/var/log/teqlif/{api,worker,orchestrator}` oluştur
- [ ] `chown tucibeyin:tucibeyin` tüm dizinlere

### 1.4 — /etc/teqlif/node.conf (Her Node)

- [ ] Her node için YAML `node.conf` oluştur: `node_id`, `env`, `guardian_priority`, `network` (wg_ip, speed_mbps), `hardware` (cpu_cores, ram_gb), `components[]` (name, env, role, traffic_eligible, traffic_type, health_check)
- [ ] `chmod 644 /etc/teqlif/node.conf`

### 1.5 — fail2ban (Her Node)

- [ ] fail2ban kur + `sshd` jail aktif et
- [ ] `maxretry = 5`, `bantime = 3600`

### 1.6 — NTP + Timezone (Her Node)

- [ ] chrony yapılandır → `systemctl enable --now chrony`
- [ ] `timedatectl set-timezone UTC`

### 1.7 — Otomatik Güvenlik Güncellemeleri (Her Node)

- [ ] `unattended-upgrades` aktif et
- [ ] Yalnızca güvenlik güncellemeleri → `50unattended-upgrades` yapılandır

### 1.8 — LimitNOFILE — Sistem Geneli (Her Node)

- [ ] `/etc/security/limits.conf`: `* soft nofile 65536` + `* hard nofile 65536`
- [ ] `/etc/sysctl.d/99-teqlif.conf`: `fs.file-max = 2097152`

### 1.9 — Swap Dosyası (Core + Storage Node'ları)

- [ ] node5, node6: 8 GB swapfile oluştur → `mkswap` → `swapon` → `/etc/fstab`'a ekle
- [ ] node7, node8: 2 GB swapfile

### 1.10 — Log Rotation (Her Node)

- [ ] `/etc/logrotate.d/teqlif` → `/var/log/teqlif/*.log` weekly, rotate 4, compress, missingok

### 1.11 — Audit Logging — auditd (Her Node)

- [ ] `resources/security/audit.rules` → `/etc/audit/rules.d/teqlif.rules`
- [ ] `systemctl enable --now auditd`

### 1.12 — Transparent Hugepages Kapatma (Her Node)

- [ ] `resources/systemd/thp-disable.service` → `/etc/systemd/system/`
- [ ] `systemctl enable --now thp-disable`

### 1.13 — Doğrulama (Her Node)

- [ ] `ssh -o PasswordAuthentication=no tucibeyin@<ip>` → root girişi reddedilmeli
- [ ] `chronyc tracking | grep "System time"` → senkron
- [ ] `free -h | grep Swap` → swap aktif (core/storage node'ları)

---

## Faz 2 — WireGuard Mesh (Tüm Node'lar)

### 2.1 — Anahtar Üretimi (Her Node'da VPS'te)

- [ ] `wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/pubkey`
- [ ] `chmod 600 /etc/wireguard/privatekey`
- [ ] Pubkey'i `~/teqlif-secrets.env`'e not et (tüm 11 node)

### 2.2 — wg0.conf Yapısı (Her Node)

- [ ] Her node için `wg0.conf` oluştur: `[Interface]` Address + ListenPort + MTU=1420 + PrivateKey
- [ ] Tüm peer'ları `[Peer]` blokları olarak ekle
- [ ] Non-core node'larda node5 peer'ına VIP'leri ekle: `10.10.0.10/32, 10.10.0.11/32`
- [ ] `chmod 600 /etc/wireguard/wg0.conf`

### 2.3 — Başlatma (Her Node)

- [ ] `wg-quick up wg0`
- [ ] `systemctl enable wg-quick@wg0`

### 2.4 — Mesh Doğrulama

- [ ] Her node'dan tüm diğer WG IP'lere ping: `ping -c1 10.10.0.x`
- [ ] `wg show wg0` → her peer'da Latest handshake < 5 dakika

### 2.5 — Failover Sudoers — Non-Core Node'lar

- [ ] `/etc/sudoers.d/wg-failover` → `tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *` + `wg-quick save wg0`

### 2.6 — Guardian Sudoers — Tüm Node'lar

- [ ] `/etc/sudoers.d/guardian-systemctl` → `teqlif*` start/stop/restart/reload/reset-failed NOPASSWD
- [ ] Per-node ek servisler: pgbouncer, redis-core/orch/guardian, livekit, minio, nginx, prometheus, clickhouse-server, redis-staging, minio-staging, livekit-staging (ilgili node'lara)

---

## Faz 3 — Rol Bazlı OS Tuning (Tüm Node'lar)

### 3.1 — Gateway (gateway1, gateway2)

- [ ] `/etc/sysctl.d/99-teqlif.conf`: `net.core.somaxconn=65535`, `net.ipv4.tcp_max_syn_backlog=65535`, `net.ipv4.tcp_tw_reuse=1`, `net.core.netdev_max_backlog=5000`
- [ ] UFW: varsayılan deny; 22/tcp; 51820/udp; WG subnet (wg0); UDP 9901 (guardian); 80/tcp + 443/tcp yalnızca Cloudflare IP aralıklarından (17 CIDR)

### 3.2 — Core (node5, node6)

- [ ] `/etc/sysctl.d/99-teqlif.conf`: `vm.swappiness=10`, `vm.dirty_ratio=15`, `vm.dirty_background_ratio=5`, `net.core.somaxconn=65535`, `net.ipv4.tcp_tw_reuse=1`, `kernel.shmmax` (RAM'in %75'i)
- [ ] UFW: WG-only (22/tcp + 51820/udp + wg0 subnet + UDP 9901)

### 3.3 — Stream (node1, node4)

- [ ] `/etc/sysctl.d/99-teqlif.conf`: `net.core.rmem_max=8388608`, `net.core.wmem_max=8388608`, `net.ipv4.udp_mem`, `net.core.netdev_max_backlog=5000`
- [ ] UFW: 22/tcp, 51820/udp, wg0, UDP 9901; LiveKit: 7880/tcp, 7881/tcp, 7882/udp, 3478/udp, 5349/tcp, 50000:60000/udp

### 3.4 — Storage (node7, node8)

- [ ] `/etc/sysctl.d/99-teqlif.conf`: `vm.dirty_ratio=40`, `vm.dirty_background_ratio=10`, `net.core.rmem_max=4194304`, `net.core.wmem_max=4194304`
- [ ] UFW: 22/tcp, 51820/udp, wg0, UDP 9901; 80/tcp + 443/tcp (tümü — DNS Only, CF yok); MinIO 9000/tcp ufw deny
- [ ] HDD udev: mq-deadline scheduler + 2048 KB readahead + nr_requests=128 (sd[a-z] rotational==1)
- [ ] iptables hashlimit: 80/443 → 60/min burst 80 DROP + netfilter-persistent save

### 3.5 — AI Proxy (node2) + Monitor (node9)

- [ ] node2 UFW: WG-only (22/tcp + 51820/udp + wg0 + UDP 9901)
- [ ] node9 UFW: WG-only; `ufw allow in on wg0 proto udp to any port 9901`; Grafana 3000/tcp → WG-only
- [ ] node9 sysctl: `vm.overcommit_memory=1` (Prometheus + Loki mmap)

### 3.6 — Sysctl Uygulama (Her Node)

- [ ] `sysctl -p /etc/sysctl.d/99-teqlif.conf` → hata yok
- [ ] `ufw status verbose` → doğru kurallar

---

## Faz 4 — Veri Katmanı HA (node5 Primary + node6 Standby)

### 4.1 — PostgreSQL 17 — node5 Primary

- [ ] PGDG repo ekle → `postgresql-17` kur
- [ ] `postgresql.conf`: `max_connections=200`, `shared_buffers=2GB`, `work_mem=20MB`, `maintenance_work_mem=512MB`, `wal_level=replica`, `max_wal_senders=5`, `max_replication_slots=3`, `synchronous_commit=off`, `random_page_cost=1.1`, `effective_io_concurrency=200`, `max_slot_wal_keep_size=5GB`
- [ ] `pg_hba.conf`: replication kuralı → `host replication replicator 10.10.0.7/32 scram-sha-256`; wal_backup_node9 → `host replication replicator 10.10.0.13/32 scram-sha-256`; PgBouncer loopback → `host teqlif teqlif 127.0.0.1/32 scram-sha-256`
- [ ] `teqlif` DB + `teqlif` user oluştur; `replicator` user oluştur
- [ ] Replication slot: `SELECT pg_create_physical_replication_slot('node6_slot')` + `SELECT pg_create_physical_replication_slot('wal_backup_node9')`
- [ ] postgres-exporter servis kur + enable

### 4.2 — PgBouncer — node5 ve node6

- [ ] `pgbouncer.ini`: `host=127.0.0.1`, `pool_mode=transaction`, `max_client_conn=2000`, `default_pool_size=25`
- [ ] `pgbouncer.service.d/restart.conf` → `Restart=always`
- [ ] `systemctl enable pgbouncer`

### 4.3 — Core Redis — node5 (port 6379)

- [ ] `redis-core.conf`: port 6379, requirepass, `maxmemory-policy volatile-lru`, `appendonly no`, `save 3600 1`, RuntimeDirectory=redis-core
- [ ] `redis-core.service` → `/etc/systemd/system/`; `systemctl disable --now redis-server`
- [ ] `systemctl enable redis-core`

### 4.4 — Orch Redis — node5 (port 6380)

- [ ] `redis-orch.conf`: port 6380, requirepass, `appendonly no`, dir=/var/lib/redis-orch
- [ ] `redis-orch.service` → `/etc/systemd/system/`
- [ ] `systemctl enable redis-orch`

### 4.4.1 — Guardian Redis — node5 (port 6382)

- [ ] `redis-guardian.conf`: port 6382, requirepass, `appendonly yes` (job checkpoint kalıcı), dir=/var/lib/redis-guardian, `save 3600 1`
- [ ] `redis-guardian.service` → `/etc/systemd/system/`
- [ ] `systemctl enable redis-guardian`

### 4.5 — Keepalived — node5 (MASTER)

- [ ] `keepalived.conf`: `state MASTER`, priority 100, `virtual_ipaddress 10.10.0.10/24 dev wg0` + `10.10.0.11/24 dev wg0`, `nopreempt`
- [ ] `vrrp_script chk_redis`: `redis-cli -a $pass --no-auth-warning ping` → OK/FAILED
- [ ] `notify_master /etc/keepalived/scripts/wg_vip_node5.sh`
- [ ] `notify_backup /etc/keepalived/scripts/wg_vip_failover.sh`
- [ ] `wg_vip_node5.sh`: VIP'leri `wg set` ile tüm non-core node'ların routing tablosuna yaz (parallel SSH + wait)
- [ ] `wg_vip_failover.sh`: MASTER bloğu (split-brain guard, PG promote pg_is_in_recovery check, PgBouncer enable, WG routing güncelle SSH loop parallel); BACKUP bloğu (PgBouncer disable, REPLICAOF node5 IP)
- [ ] SSH public key → tüm peer node'ların `authorized_keys`'ine ekle (node1/2/3/4/7/8/9 + gateway1/2)
- [ ] `systemctl enable keepalived`

### 4.6 — PostgreSQL Streaming Replication — node6

- [ ] node5 hazırken: `pg_basebackup -h 10.10.0.5 -U replicator -D /var/lib/postgresql/17/main -P -R --slot=node6_slot`
- [ ] `postgresql.conf` override: `random_page_cost=4.0`, `effective_io_concurrency=8` (node6 yavaş disk)
- [ ] `standby.signal` mevcut → `systemctl start postgresql` (node6)
- [ ] `select * from pg_stat_replication` → node6 bağlı + replay_lag ~0

### 4.7 — Redis Replication — node6

- [ ] redis-core/orch/guardian conf: `REPLICAOF 10.10.0.11 6379/6380` (VIP üzerinden); redis-guardian: `REPLICAOF 10.10.0.5 6382` (direkt IP — VIP yok)
- [ ] `systemctl enable redis-core redis-orch redis-guardian` (node6)

### 4.9 — Faz 4 Doğrulama

- [ ] `psql -h 127.0.0.1 -U teqlif -d teqlif` → bağlantı OK
- [ ] `select * from pg_stat_replication` → node6 streaming, lag ~0
- [ ] `redis-cli -h 10.10.0.11 -p 6379 -a <pass> info replication` → role:master, connected_slaves:1
- [ ] `systemctl is-active keepalived` → active (node5 + node6)
- [ ] VIP doğrula: `ip addr show wg0` → node5'te 10.10.0.10 + 10.10.0.11 görünmeli
- [ ] PgBouncer: `psql -h 127.0.0.1 -p 6432 -U teqlif` → bağlantı OK

---

## Faz 5 — Core App (node5 Primary + node6 Standby)

### 5.1 — Repo ve Python Ortamı — node5

- [ ] `git clone` → `/var/www/teqlif.com`
- [ ] `python3 -m venv /var/www/teqlif.com/.venv`
- [ ] `.venv/bin/pip install -r backend/requirements.txt`

### 5.1.1 — Alembic — DB Şema Kurulumu

- [ ] `cd backend && .venv/bin/python -m alembic upgrade head`
- [ ] Migration başarılı → tüm tablolar mevcut

### 5.2 — .env.production — node5

- [ ] Template'den `/etc/teqlif/.env.production` oluştur
- [ ] Tüm `<placeholder>`'ları gerçek değerlerle doldur
- [ ] `chmod 600 /etc/teqlif/.env.production`

### 5.3 — Systemd Servisleri — node5

- [ ] `teqlif.service` → enable (MemoryMax=1500M, --workers 4, --forwarded-allow-ips)
- [ ] `teqlif-worker.service` → enable (MemoryMax=1000M)
- [ ] `teqlif-worker-critical.service` → enable (MemoryMax=800M)
- [ ] `teqlif-guardian.service` → enable (MemoryMax=300M)
- [ ] `systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian`

### 5.3.1 — teqlif-ai-proxy — node5 (Son Çare Fallback)

- [ ] `teqlif-ai-proxy.service` → enable ama **başlatma** (orchestrator tetikler, MemoryMax=600M)

### 5.4 — Ops Komutları Kurulumu

- [ ] `teqlif-restart.sh` → `/usr/local/sbin/teqlif-restart` (executable)
- [ ] `teqlif-refresh.sh` → `/usr/local/sbin/teqlif-refresh`

### 5.5 — node6 Standby App Kurulumu

- [ ] `git clone` → `/var/www/teqlif.com` (node6)
- [ ] `.venv` + pip install
- [ ] `/etc/teqlif/.env.production` (node6 — aynı template, aynı değerler)
- [ ] Tüm teqlif servisler **enable ama başlatma** (failover'da Keepalived tetikler)
- [ ] teqlif-guardian → enable + start (node6'da da heartbeat çalışmalı)

### 5.6 — Failover Testi

- [ ] node5 Keepalived durdur → node6 MASTER olmalı (~30s)
- [ ] `ip addr show wg0` (node6) → VIP'ler görünmeli
- [ ] API çağrısı → gateway → node6'ya ulaşıyor
- [ ] node5 geri getir → failback (nopreempt — otomatik değil, manüel)

### 5.6.1 — Failback Prosedürü

- [ ] node6: `systemctl stop teqlif teqlif-worker teqlif-worker-critical`
- [ ] Replication sync doğrula: `pg_stat_replication` lag ~0
- [ ] node5 Keepalived → MASTER alır → VIP node5'e geçer
- [ ] node5 servisleri start

### 5.7 — Faz 5 Doğrulama

- [ ] `curl http://127.0.0.1:8000/v1/ping` → 200 (node5)
- [ ] ARQ worker çalışıyor: `redis-cli -h 10.10.0.11 -p 6379 -a <pass> llen arq:queue:default`
- [ ] Guardian: `redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"` → node5 mevcut

---

## Faz 6 — Storage (node7 + node8)

*Faz 5 bittikten sonra Faz 7 ve Faz 8 ile paralel yürütülebilir.*

### 6.1 — HDD Formatı ve Mount (Her İki Node)

- [ ] HDD diskini formatla: `mkfs.ext4 /dev/sdX`
- [ ] `/etc/fstab`'a ekle → `/data` mount noktası
- [ ] `mount -a` → `df -h /data` doğrula

### 6.2 — MinIO Kurulumu (node7 + node8)

- [ ] MinIO binary'yi GitHub releases'den indir → `/usr/local/bin/minio`; `mc` client → `/usr/local/bin/mc`
- [ ] MinIO data dir: `/data/minio` (HDD) oluştur → `chown tucibeyin`
- [ ] `/etc/teqlif/.env.production` → `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`

### 6.3 — node7 — MinIO Servisi

- [ ] `minio.service` → `/etc/systemd/system/`; `MINIO_SERVER_URL=https://uploads.teqlif.com` (presigned imza için zorunlu)
- [ ] `systemctl enable --now minio`
- [ ] mc alias kur: `mc alias set minio7 http://127.0.0.1:9000 ...`
- [ ] Bucket oluştur: `mc mb minio7/teqlif` + `mc mb minio7/teqlif-dm`
- [ ] Versioning aktif: `mc version enable minio7/teqlif` + `mc version enable minio7/teqlif-dm`
- [ ] ILM: 90 gün versiyonları sakla → `mc ilm add --expire-delete-marker --expire-days 90`

### 6.4 — node7 — nginx (S3 Proxy)

- [ ] nginx kur + `/var/cache/nginx/storage` (1 GB SSD cache)
- [ ] İki server block:
  - `media.teqlif.com` (CF Proxied): set_real_ip_from CF IP ranges; GET/HEAD only; `proxy_cache storage_cache` 7 gün; `Cache-Control: public max-age=31536000 immutable`; rate limit 100r/s burst=200
  - `uploads.teqlif.com` (DNS Only): `limit_conn 10`; 10r/s burst=20; `proxy_cache off`; `Cache-Control: no-store`
- [ ] upstream: `upstream minio_media` + `upstream minio_uploads` → `proxy_next_upstream` ile fallback
- [ ] CF Origin cert: `/etc/ssl/teqlif/cf-origin.crt` + `.key`
- [ ] `nginx.service.d/restart.conf` → `Restart=always`
- [ ] `systemctl enable --now nginx`

### 6.5 — node8 — MinIO Servisi

- [ ] node7 ile aynı kurulum → `minio.service`, mc alias, bucket (versioning kur)
- [ ] **NOT:** Bucket içeriği boş başlar — Site Replication node7'yi kaynak alır

### 6.6 — node8 — nginx (S3 Proxy + 404 Fallback)

- [ ] node7 ile aynı nginx config (upstream node8 MinIO IP'si)

### 6.7 — Guardian — node7 + node8

- [ ] `teqlif-guardian.service` → enable + start (her iki node)
- [ ] `edge:metrics:node7` + `edge:metrics:node8` → orch-redis'te mevcut

### 6.8 — Cloudflare DNS — Storage

- [ ] `media.teqlif.com` → node7 IP + node8 IP (iki A record, CF Proxied)
- [ ] `uploads.teqlif.com` → node7 IP + node8 IP (DNS Only — CF bypass)

### 6.9 — MinIO Site Replication

- [ ] Her iki MinIO hazır → `mc admin replicate add minio7 minio8`
- [ ] `mc admin replicate info minio7` → replication aktif
- [ ] `teqlif-storage-cleanup.service` + `teqlif-storage-cleanup.timer` (aylık, node5'te) → enable

### 6.10 — Faz 6 Doğrulama

- [ ] `mc ls minio7/teqlif` → erişim OK
- [ ] `curl -s https://media.teqlif.com/health` → nginx cevap veriyor
- [ ] Dual-write test: bir dosya yükle → her iki node'da `mc ls` ile kontrol
- [ ] `mc version info minio7/teqlif` → Versioning: enabled

---

## Faz 7 — Gateway (gateway1 + gateway2)

*Faz 5 bittikten sonra paralel yürütülebilir.*

### 7.1 — nginx Kurulumu

- [ ] nginx kur + yapılandır
- [ ] `api.teqlif.com` server block: proxy → `10.10.0.10:8000` (VIP); WebSocket upgrade; `client_max_body_size 5m`
- [ ] `staging.teqlif.com` server block: proxy → `10.10.0.4:8000` (node3 WG IP)
- [ ] `www.teqlif.com` server block: static assets + well-known (App Links)
- [ ] WebSocket map: upgrade header doğru; `'' ''` (boş string — not close)
- [ ] `proxy_cache_path` bypass (API dinamik içerik)
- [ ] upstream keepalive 32 (TCP bağlantı yeniden kullanımı)
- [ ] `nginx.service.d/restart.conf` → `Restart=always`
- [ ] `systemctl enable --now nginx`

### 7.2 — Cloudflare Origin Certificate

- [ ] CF Dashboard → SSL/TLS → Origin Certificates → yeni sertifika → `cf-origin.crt` + `cf-origin.key`
- [ ] `/etc/ssl/teqlif/` → `chmod 600 cf-origin.key`

### 7.3 — Guardian Metrics + Promtail

- [ ] `teqlif-guardian.service` → enable + start (her iki gateway)
- [ ] Promtail kur → log stream node9 Loki'ye
- [ ] nginx `stub_status` aktif: `location /nginx_status`

### 7.4 — Cloudflare DNS — Gateway

- [ ] `api.teqlif.com` → gateway1 IP + gateway2 IP (CF Proxied, iki A record)
- [ ] `teqlif.com` + `www.teqlif.com` → gateway1 + gateway2 (CF Proxied)

### 7.5 — Guardian — gateway1 + gateway2

- [ ] `edge:metrics:gateway1/2` → orch-redis'te mevcut

### 7.6 — Faz 7 Doğrulama

- [ ] `curl -I https://api.teqlif.com/v1/ping` → 200, CF header'ları mevcut
- [ ] WebSocket test: WS bağlantısı gateway üzerinden kuruluyor
- [ ] Gateway log'unda Content-Length > 100KB POST yok (presigned upload gateway'den geçmiyor)

---

## Faz 8 — Stream + AI Proxy

*Faz 5 bittikten sonra paralel yürütülebilir.*

### 8.1 — LiveKit SFU — node1 ve node4

- [ ] LiveKit binary GitHub releases'den indir → `/usr/local/bin/livekit-server`
- [ ] `/etc/livekit/livekit.yaml`: TURN `relay_range_start: 50000` + `relay_range_end: 60000` (UFW ile eşleşmeli)
- [ ] `livekit.service` → enable + start
- [ ] Promtail kur, guardian enable + start

### 8.2 — AI Proxy — node2

- [ ] `git clone` + venv + pip install (backend)
- [ ] `/etc/teqlif/.env.production` → `GROQ_API_KEY`, `GEMINI_API_KEY`, `AI_PROXY_INTERNAL_TOKEN`
- [ ] `teqlif-ai-proxy.service` → enable + start (node2 = Primary, her zaman çalışır)

### 8.3 — Guardian — node2

- [ ] `teqlif-guardian.service` → enable + start
- [ ] `edge:metrics:node2` → orch-redis'te mevcut

### 8.4 — Faz 8 Doğrulama

- [ ] LiveKit: `curl -s http://10.10.0.1:7880/` → 200
- [ ] AI proxy: `curl -s http://10.10.0.3:8001/health` → 200
- [ ] `redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url` → `http://10.10.0.3:8001` veya nil (node2 aktif)
- [ ] Cloudflare DNS: `live1.teqlif.com` → node1 IP (DNS Only); `live2.teqlif.com` → node4 IP (DNS Only)

### 8.5 — AI Proxy Fallback — node3 (İlk Yedek)

- [ ] node3: `teqlif-ai-proxy.service` enable + start (Warm Standby — her zaman çalışır, `--host 0.0.0.0` — lokal staging ve prod mesh `10.10.0.4:8001` erişimini birlikte karşılar)
- [ ] Orchestrator node2 down → `ai_proxy:active_url` → `http://10.10.0.4:8001` (node3) otomatik güncellemeli

---

## Faz 9 — Guardian Koordinatör

**Önkoşul:** Faz 5 + 6 + 7 + 8 tamamlandı.

### 9.1 — Guardian Agent (Metrik) Doğrulaması

- [ ] `redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"` → 10 anahtar (gateway1, gateway2, node1..node8)
- [ ] `type edge:metrics:node7` → hash
- [ ] `hgetall edge:metrics:node7` → 20+ alan mevcut

### 9.2 — Guardian Aktif + AI Proxy Routing

- [ ] Tüm node'larda `systemctl is-active teqlif-guardian` → active
- [ ] `redis-cli ... get ai_proxy:active_url` → nil (node2 aktif) veya node2 URL'si
- [ ] node2/node3/node5 `edge:metrics` TTL'leri → 1-6 arası

### 9.3 — Dual-Write Routing Doğrulama

- [ ] `redis-cli ... get orch:best:storage_nodes` → `["node7","node8"]`
- [ ] Test yükleme → her iki storage node'da `mc ls` ile doğrula

### 9.4 — Failover Simülasyonu — Storage

- [ ] node8 MinIO durdur → 10s bekle → `orch:best:storage_nodes` → `["node7"]`
- [ ] Telegram #ops bildirimi geldi mi?
- [ ] node8 geri getir → `orch:best:storage_nodes` → `["node7","node8"]`

### 9.5 — Failover Simülasyonu — AI Proxy

- [ ] node2 teqlif-ai-proxy + guardian durdur → 10s → `ai_proxy:active_url` → node3
- [ ] API AI çağrısı → node3 üzerinden → 200
- [ ] node2 geri getir → `ai_proxy:active_url` → node2 (otomatik failback)

---

## Faz 10 — Monitoring + Backup + ClickHouse (node9)

### 10.0 — node9 Ön Kurulum

- [ ] OS temeli (Faz 1) + WireGuard (Faz 2) + OS tuning (§3.5) → node9'a uygula
- [ ] `/data` mount doğrula: `df -h /data` → 3.5 TB HDD RAID-1
- [ ] Backup dizin yapısı: `/data/teqlif_backups/{postgres/{wal,basebackup,dump},redis,minio}`, `/data/clickhouse-backups`, `chown tucibeyin`
- [ ] Symlink: `ln -sfn /data/teqlif_backups /opt/teqlif/backups`
- [ ] `node.conf`: guardian_priority=5
- [ ] ClickHouse kur: packages.clickhouse.com repo → `clickhouse-server` + `clickhouse-client`
- [ ] ClickHouse `config.d/teqlif.xml`: `max_server_memory_usage=24GB` (node9 OOM önlemi)
- [ ] ClickHouse DB + kullanıcı oluştur; pg_hba.conf'a node9 WAL replica girişi ekle (node5'te)

### 10.1 — Guardian — node9

- [ ] `teqlif-guardian.service` → enable + start
- [ ] `edge:metrics:node9` → orch-redis mevcut; guardian_priority=5 (lider seçilmez)

### 10.2 — Prometheus

- [ ] Prometheus binary GitHub releases'den indir → `/usr/local/bin/prometheus`
- [ ] `prometheus.yml`: 11 node scrape (her node 10.10.0.x:9200); scrape_interval=15s; retention=30d
- [ ] Alertmanager rules: NodeDown, ServiceFailed, GatewayDown, StorageNodeDown, HighCPU, MonitorDiskHigh, WALLag
- [ ] `prometheus.service` → `--web.listen-address=10.10.0.13:9090` → enable + start

### 10.3 — Grafana

- [ ] Grafana apt repo → kur
- [ ] `grafana.ini`: `http_addr=10.10.0.13` (WG-only — internete kapalı)
- [ ] Data source: Prometheus `http://10.10.0.13:9090` + Loki `http://10.10.0.13:3100`
- [ ] `systemctl enable --now grafana-server`
- [ ] Admin şifresini değiştir

### 10.4 — Loki + Promtail (node9)

- [ ] Loki Grafana apt repo'dan kur
- [ ] `loki.yaml`: listen_address=`10.10.0.13:3100`; retention=7d
- [ ] node9 Promtail kur → lokal logları node9 Loki'ye gönder
- [ ] `systemctl enable --now loki`

### 10.5 — Alertmanager → Telegram

- [ ] Alertmanager binary indir → `/usr/local/bin/alertmanager`
- [ ] `alertmanager.yml`: Telegram webhook, `#ops` kanalı, inhibit_rules (NodeDown → warning suppress)
- [ ] `alertmanager.service` → `--web.listen-address=10.10.0.13:9093` → enable + start

### 10.6 — Yedekleme

- [ ] **10.6.1 Kurulum:** backup scriptleri → `/usr/local/bin/`; tüm systemd service + timer dosyaları → enable
- [ ] **10.6.2 pg_receivewal:** `teqlif-pg-receivewal.service` → `pg_receivewal -h 10.10.0.10 -U replicator --slot=wal_backup_node9 --compress=9 -D /data/teqlif_backups/postgres/wal/` → start
- [ ] **10.6.3 pg_basebackup:** haftalık timer → `pg_basebackup -h 10.10.0.10 -U replicator -D /data/teqlif_backups/postgres/basebackup/...`; atomic temp→rename
- [ ] **10.6.4 pg_dump:** günlük timer → `pg_dump -h 10.10.0.10 -U teqlif teqlif | gzip`; eski dumplar temizle
- [ ] **10.6.6 Redis RDB:** haftalık timer → `redis-cli --rdb /tmp/...`; atomic temp→rename
- [ ] **10.6.7 ClickHouse yedek:** günlük timer → `clickhouse-backup create`; 2 günden eski localler sil
- [ ] **10.6.8 MinIO soğuk arşiv:** günlük timer (02:00 UTC) → `minio_backup.sh`; node7 primary (node8 fallback); `teqlif` + `teqlif-dm` bucket'ları → `/data/backups/minio/` lokal arşive `mc mirror --overwrite --remove`
- [ ] **10.6.9 Off-site rclone:** günlük timer → `rclone sync /data/teqlif_backups b2backup:teqlif-backups`; B2 retention 7d
- [ ] **10.6.11 WG private key kurtarma:** tüm 11 node private key'ini şifreli biçimde password manager'a kaydet

### 10.7 — Faz 10 Doğrulama

- [ ] `systemctl is-active prometheus loki alertmanager grafana-server` → tümü active
- [ ] `curl -s http://10.10.0.13:9090/api/v1/targets | python3 -m json.tool` → 11 target UP
- [ ] `systemctl is-active teqlif-pg-receivewal` → active; `/data/.../wal/` dosyaları birikiyor
- [ ] `ls /data/teqlif_backups/postgres/dump/` → ilk dump mevcut
- [ ] `rclone lsd b2backup:` → bucket görünüyor
- [ ] Grafana: http://10.10.0.13:3000 → her iki data source bağlı

---

## Faz 11 — Staging (node3)

### 11.1 — PostgreSQL — node3 Lokal

- [ ] PGDG repo → `postgresql-17` kur (node3)
- [ ] `teqlif_staging` DB + `teqlif` user (staging şifresi)
- [ ] `pg_hba.conf`: lokal bağlantı izin

### 11.2 — Redis — node3 Lokal

- [ ] `redis-staging.conf` → `cp resources/redis/redis-staging.conf /etc/redis/`; `sed` ile `<staging_redis_pass>` doldur
- [ ] `redis-staging.service` → enable + start

### 11.3 — MinIO — node3 Lokal (staging)

- [ ] MinIO binary indir + mc client
- [ ] `/data/minio-staging` data dir
- [ ] `minio-staging.service` → enable + start; `MINIO_SERVER_URL=https://staging.teqlif.com`
- [ ] mc alias: staging bucket'ları oluştur; versioning aktif
- [ ] UFW: `deny 9000/tcp` (MinIO doğrudan internet'e kapalı)

### 11.4 — LiveKit — node3 Lokal (staging)

- [ ] LiveKit binary indir
- [ ] `/etc/livekit/livekit-staging.yaml`: staging API key/secret; TURN relay_range eşleşmeli UFW ile
- [ ] `livekit-staging.service` → enable + start

### 11.5 — Staging App

- [ ] `git clone` + venv + pip install (node3)
- [ ] `/etc/teqlif/.env.staging` → template'den doldur (lokal PG, lokal Redis, lokal MinIO)
- [ ] Firebase: `firebase-service-account.json` → `/etc/teqlif/` (güvenli kanaldan kopyala — repoya GİRMEZ)
- [ ] APNS: `AuthKey_*.p8` → `/etc/teqlif/` (güvenli kanaldan kopyala — repoya GİRMEZ)
- [ ] `teqlif-staging.service` → enable + start
- [ ] `teqlif-worker-staging.service` + `teqlif-worker-critical-staging.service` → enable + start
- [ ] `teqlif-ai-proxy.service` (staging + prod fallback, `--host 0.0.0.0`) → enable + start
- [ ] `teqlif-guardian.service.d/staging-env.conf` drop-in → `.env.staging` kullan
- [ ] `teqlif-guardian.service` → enable + start
- [ ] Alembic: `cd backend && .venv/bin/python -m alembic upgrade head`

### 11.6 — nginx (staging.teqlif.com — node3)

- [ ] `cp resources/nginx/sites-available/staging /etc/nginx/sites-available/`
- [ ] `ln -s` → sites-enabled
- [ ] CF Origin cert kopyala
- [ ] `nginx -t && systemctl reload nginx`

### 11.7 — Faz 11 Doğrulama

- [ ] `systemctl is-active teqlif-staging teqlif-worker-staging teqlif-ai-proxy redis-staging minio-staging livekit-staging` → tümü active
- [ ] `curl -s http://127.0.0.1:8000/v1/ping` → 200
- [ ] `curl -s http://127.0.0.1:8001/health` → 200 (AI proxy)
- [ ] `ls /etc/teqlif/firebase-service-account.json` → dosya mevcut
- [ ] Guardian: `edge:metrics:node3` → orch-redis'te mevcut

### 11.8 — Entegrasyon Testleri

- [ ] Staging ortamında uçtan uca kullanıcı akışı test et (auth, upload, stream, AI çağrısı)
- [ ] Cloudflare DNS: `staging.teqlif.com` → gateway1 + gateway2 → node3

---

## Faz 12 — Prodüksiyon + Mobile

### 12.1 — Son Kontrol Listesi

- [ ] CF DNS: `api.teqlif.com` → gateway1 + gateway2 (iki A record, Proxied)
- [ ] CF DNS: `uploads.teqlif.com` + `media.teqlif.com` → node7 + node8 (iki A record)
- [ ] node5: teqlif + teqlif-worker + teqlif-worker-critical + teqlif-guardian → active
- [ ] `orch:best:storage_nodes = ["node7","node8"]` doğrula
- [ ] node6: keepalived active; teqlif/worker disabled; teqlif-guardian active
- [ ] node7 + node8: minio + nginx + teqlif-guardian → active
- [ ] Prometheus: 11 target UP
- [ ] Loki: 11 node'dan log akışı
- [ ] Alertmanager: test alert gönder → Telegram'da görün
- [ ] Presigned upload doğrula: `PUT` direkt node7/node8'e gidiyor, gateway log'unda media byte'ı yok
- [ ] Tüm `UploadFile` endpoint'leri kaldırıldı → gateway log'unda Content-Length > 100KB POST yok
- [ ] `nginx -T | grep client_max_body_size` → 5m (gateway)
- [ ] Dual-write: medya yükle → her iki storage node'da mc ls ile doğrula
- [ ] MinIO versioning: `mc version info minio7/teqlif` → enabled
- [ ] `systemctl is-active teqlif-pg-receivewal` → active; WAL birikiyor
- [ ] İlk pg_dump başarılı: dosya mevcut
- [ ] `rclone lsd b2backup:` → bucket görünüyor
- [ ] WireGuard private key'ler password manager'a kaydedildi (tüm 11 node)

### 12.2 — Mobile Güncellemesi

- [ ] `dart_defines/release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` güncelle
- [ ] `dart_defines/staging.json`: aynı anahtarlar staging değerleriyle
- [ ] `frontend/.well-known/assetlinks.json` — Android App Links
- [ ] `frontend/.well-known/apple-app-site-association` — iOS Universal Links
- [ ] Android: Play Store internal track
- [ ] iOS: App Store TestFlight

---

## Faz 13 — node9 Doğrulama + Tam Entegrasyon

### 13.1 — WireGuard Mesh Bütünlüğü

- [ ] node9'dan tüm 10 node'a ping → tümü OK
- [ ] Diğer node'lardan node9'a ping → OK
- [ ] `wg show wg0` her node'da → Latest handshake < 5 dakika

### 13.2 — ClickHouse — Prod Veri Akışı Doğrulaması

- [ ] `SELECT count(), max(created_at) FROM teqlif.analytics_events LIMIT 1` → satır sayısı > 0
- [ ] Circuit breaker: ClickHouse kapat → uygulama çalışmaya devam eder; aç → yazma devam eder

### 13.3 — Prometheus — Tüm Node'lar Scrape Ediliyor

- [ ] `curl http://10.10.0.13:9090/api/v1/targets` → 11 target UP
- [ ] Her node'dan Prometheus metrikleri görünüyor

### 13.4 — Loki — Tüm Node'lardan Log Akışı

- [ ] `curl "http://10.10.0.13:3100/loki/api/v1/labels"` → node label'ları görünüyor
- [ ] Grafana Loki explorer'da 11 node log'ları mevcut

### 13.5 — Backup Sistemleri — İlk Tam Doğrulama

- [ ] `pg_receivewal`: WAL lag < 10 MB; .gz.partial dosyaları birikiyor
- [ ] `pg_dump`: ilk dump mevcut, < 24 saatlik
- [ ] `clickhouse-backup`: `/data/clickhouse-backups/ch_backup_*` mevcut
- [ ] Redis backup: `/opt/teqlif/backups/redis/` mevcut
- [ ] Off-site rclone: `rclone lsd b2backup:` → bucket görünüyor

### 13.6 — Alertmanager — Telegram Testi

- [ ] Test alert POST → Telegram #ops kanalında bildirim geldi

### 13.7 — Grafana — Dashboard Doğrulaması

- [ ] Prometheus + Loki data source bağlı
- [ ] node9 metrikleri dashboard'da görünüyor
- [ ] Admin şifresi varsayılandan değiştirildi

### 13.8 — Guardian — node9 Entegrasyon Durumu

- [ ] `edge:metrics:node9` güncel → guardian_priority=5 → lider seçilmedi (node5/6 öncelikli)
- [ ] `redis-cli -h 10.10.0.11 -p 6382 -a <pass> hget guardian:topology:node9 guardian_priority` → 5

### 13.9 — Son Kontrol Listesi

- [ ] WireGuard: node9 ↔ tüm 10 node çift yönlü handshake OK
- [ ] ClickHouse: analytics_events satır sayısı artıyor
- [ ] Prometheus: 11 target UP (node9 dahil)
- [ ] Loki: 11 node log akışı
- [ ] pg_receivewal: WAL lag < 10 MB
- [ ] pg_dump: ilk dump dosyası mevcut, < 24 saatlik
- [ ] ClickHouse backup dosyaları mevcut
- [ ] Redis backup dosyaları mevcut
- [ ] Alertmanager Telegram testi geçti
- [ ] Grafana: her iki data source bağlı, dashboard çalışıyor
- [ ] Guardian: node9 lider seçilmedi, edge:metrics güncel
- [ ] Circuit breaker: ClickHouse kapatılınca app canlı kalıyor
- [ ] Off-site rclone bağlantısı doğrulandı

---

## İlerleme Özeti

| Faz | Konu | Durum |
|-----|------|-------|
| §0.0 | Secrets Üretimi | [ ] |
| Faz 0 | Kod Hazırlığı (Lokalde) | [ ] |
| Faz 1 | OS Temeli — Tüm Node'lar | [ ] |
| Faz 2 | WireGuard Mesh | [ ] |
| Faz 3 | Rol Bazlı OS Tuning | [ ] |
| Faz 4 | Veri Katmanı HA (node5 + node6) | [ ] |
| Faz 5 | Core App (node5 + node6) | [ ] |
| Faz 6 | Storage (node7 + node8) | [ ] |
| Faz 7 | Gateway (gateway1 + gateway2) | [ ] |
| Faz 8 | Stream + AI Proxy | [ ] |
| Faz 9 | Guardian Koordinatör | [ ] |
| Faz 10 | Monitoring + Backup + ClickHouse (node9) | [ ] |
| Faz 11 | Staging (node3) | [ ] |
| Faz 12 | Prodüksiyon + Mobile | [ ] |
| Faz 13 | node9 Doğrulama + Tam Entegrasyon | [ ] |
