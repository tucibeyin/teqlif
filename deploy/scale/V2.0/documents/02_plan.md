# V2.0 Deployment Plan

**Durum:** Final  
**Bağlı belge:** [01_findings.md](01_findings.md)

---

## Temel Kurallar

1. **Sıfırdan kurulum.** Her node Debian 13 fresh install. Migration yok, backward compatibility yok, V1.4 geçmişi yok. Her adım temiz bir sistemden başlar.
2. **Gizlilik sınırı.** WireGuard private key, `.env.*` dosyaları, `firebase-service-account.json` ASLA repoya girmez. Repodaki template dosyaları `<placeholder>` değerleriyle commit edilir.
3. **Tasarım prensipleri.** `documents/teqlif_architectural_decisions.md`, Clean Architecture ve Clean Code esas alınır.

---

## Node Envanteri

| Node | WG IP | Rol | CPU / RAM / Disk | Ağ | Fiziksel |
|------|-------|-----|-----------------|-----|---------|
| gateway1 | 10.10.0.2 | Edge Proxy #1 | 2c / 1.9 GB / 59 GB | ~1 Gbps | Netcup NUE |
| gateway2 | 10.10.0.9 | Edge Proxy #2 | 2c / 9.0 GB / 79 GB | ~4–7 Gbps | DELUXHOST AMS |
| node1 | 10.10.0.1 | Stream #1 (LiveKit) | 6c / 11.4 GB / 98 GB NVMe | ~1.9 Gbps | OVH FRA |
| node2 | 10.10.0.3 | AI Proxy | 1c / 1.4 GB / 14.7 GB | ~300 Mbps | RackNerd BUF |
| node3 | 10.10.0.4 | Staging | 4c / 3.8 GB / 49 GB | ~400 Mbps | ZAP VA |
| node4 | 10.10.0.6 | Stream #2 (LiveKit) | 6c / 11.4 GB / 98 GB NVMe | ~1.9 Gbps | OVH FRA |
| node5 | 10.10.0.5 | Core #1 (Primary) | 4c AMD EPYC / 7.8 GB / 49 GB NVMe | ~1 Gbps | ZAP MUN |
| node6 | 10.10.0.7 | Core #2 (Standby) | 3c / 7.7 GB / 79 GB | ~2–4 Gbps | DELUXHOST AMS |
| node7 | 10.10.0.8 | Storage #1 | 2c / 2.9 GB / 10 GB SSD + 1 TB HDD | ~1.1 Gbps | DELUXHOST NL |
| node8 | 10.10.0.12 | Storage #2 | 2c / 2.9 GB / 10 GB SSD + 1 TB HDD | ~1.1 Gbps | DELUXHOST NL |
| node9 | 10.10.0.13 | Backup + Monitor + ClickHouse | 4c(8t) / 31 GB ECC / 3.5 TB HDD RAID-1 | ~480 Mbps | OVH LIM (KS-1-B) |

**Sanal IP'ler (Keepalived — wg0 üzerinde):**
- `10.10.0.10` → PostgreSQL VIP (node5 primary ↔ node6 standby)
- `10.10.0.11` → Redis VIP (node5 primary ↔ node6 standby)

---

## Dizin Yapısı ve Yetkiler

Her node'da uygulanacak standart dizin yapısı. Rol gerektirmedikçe oluşturulmaz.

### Tüm Node'lar (Ortak)

```
/var/www/teqlif.com/           # monorepo — git clone; 755 tucibeyin:tucibeyin
  backend/                     # FastAPI, ARQ, scripts
  deploy/                      # şablonlar, scriptler
  mobile/                      # Flutter
  frontend/                    # Web
  .venv/                       # Python virtualenv (tüm node'larda burada)

/etc/teqlif/                   # 755 root:root
  node.conf                    # 644 root:root  ← NODE_NAME, NODE_ROLE (sır değil)
  .env.production              # 600 tucibeyin:tucibeyin  ← tüm sırlar

/var/log/teqlif/               # 755 tucibeyin:tucibeyin  ← 755: promtail (system user) dizine girebilmeli
  api/
  worker/
  orchestrator/
  minio/                       # sadece storage node'larında (Faz 6.3)

/etc/wireguard/
  wg0.conf                     # 600 root:root  ← private key burada
```

### Gateway (gateway1, gateway2)

```
/etc/ssl/teqlif/               # 700 root:root  ← CF Origin cert
  cf-origin.crt                # 644 root:root
  cf-origin.key                # 600 root:root
```

### Core (node5 Primary + node6 Standby)

```
/var/lib/redis-core/           # 750 redis:redis  ← Redis RDB+AOF (core, port 6379)
                               # redis-orch ephemeral (save ""); dir ayarı yok, default /var/lib/redis

/etc/keepalived/
  secrets/                     # 700 root:root  ← failover.env burada; dizin de kilitli
    failover.env               # 600 root:root  ← Telegram token, Redis pass, WG pubkey'ler
  scripts/                     # 750 root:root
    wg_vip_node5.sh            # 750 root:root  (node5'te)
    wg_vip_failover.sh         # 750 root:root  (node6'da)
```

**node9'a özgü:**
```
/data/clickhouse/              # clickhouse:clickhouse  ← ClickHouse veri + backup (node9 lokal)
/opt/teqlif/backups/           # tucibeyin:tucibeyin 700 ← PG WAL/dump, Redis, off-site log
```

### Stream (node1, node4)

```
/etc/livekit/                  # 700 root:root  ← livekit.yaml (API key/secret)
```

### Storage (node7, node8)

```
/mnt/data/                     # 755 root:root  ← HDD/vdb mount noktası
  minio/                       # 700 tucibeyin:tucibeyin  ← MinIO verisi

/var/cache/nginx/storage       # www-data:www-data  ← nginx proxy cache
/etc/ssl/teqlif/               # 700 root:root  ← CF Origin cert (storage nginx TLS için)
  cf-origin.crt                # 644 root:root
  cf-origin.key                # 600 root:root
```

### Monitoring + Backup + ClickHouse (node9)

```
/opt/teqlif/
  backups/                     # 700 tucibeyin:tucibeyin  ← tüm backup verileri; repoya girmez
    postgres/
      wal/                     # pg_receivewal WAL segmentleri
      basebackup/              # pg_basebackup
      dump/                    # pg_dump
    redis/                     # redis-cli --rdb dump
    clickhouse/                # ClickHouse local backup
    minio/                     # MinIO cold archive (node7+8'den rsync)
    offsite-log/               # offsite rsync çıktıları
  scripts/                     # 750 tucibeyin:tucibeyin  ← backup scriptleri

# node9 disk yapısı:
# /          → 150 GB (OS + servisler)
# /data      → 3.5 TB (ClickHouse data + Prometheus TSDB + Loki chunks + backup arşivi)
```

### Staging (node3)

```
# node3: saf staging node — monitoring ve backup node9'a taşındı
# /var/www/teqlif.com aynı monorepo — /etc/teqlif/.env.staging (600 tucibeyin:tucibeyin)
```

---

**Kural:** Systemd `User=tucibeyin`. `.env.production` sahibi `tucibeyin`, mod `600` — root olarak `cp` yapılsa dahi `chown tucibeyin:tucibeyin` zorunlu; aksi halde servis okuyamaz. `wg0.conf` sahibi `root`, mod `600` — private key root'a kilitli. `/etc/keepalived/secrets/` dizini `700 root:root` — dosyanın 600 olması tek başına yeterli değil, dizin de kilitlenmeli. Tüm node'larda monorepo `/var/www/teqlif.com/`'da, `git pull` ile güncellenir.

---

## Faz Bağımlılık Haritası

```
Faz 0  (Kod — lokalde)
  └── Faz 1  (OS Temeli — tüm node'lar)
        └── Faz 2  (WireGuard Mesh — tüm node'lar)
              └── Faz 3  (Rol Bazlı OS Tuning — tüm node'lar)
                    ├── Faz 4  (Veri Katmanı HA — node5 + node6)
                    │     └── Faz 5  (Core App — node5 + node6)
                    ├── Faz 6  (Storage — node7 + node8)        ← paralel
                    ├── Faz 7  (Gateway — gateway1 + gateway2)  ← paralel
                    └── Faz 8  (Stream + AI Proxy)              ← paralel
                          ↓  (4+5+6+7+8 tamamlanınca)
                         Faz 9  (Orchestrator)
                           └── Faz 10  (node9 — Monitoring + Backup + ClickHouse)
                                 └── Faz 11  (Staging — node3)
                                       └── Faz 12  (Prod + Mobile)
                                             └── Faz 13  (node9 Doğrulama + Tam Entegrasyon)
```

---

## Faz 0 — Kod Hazırlığı (Lokalde)

**Amaç:** V2.0 mimarisine uygun tüm kod değişikliklerini VPS'e dokunmadan repoda hazırla. Bu fazın tamamı lokalde yapılır, merge + push edilir.

### 0.1 `edge_orchestrator.py` Kaldırma

- [ ] `backend/app/services/edge_orchestrator.py` sil
- [ ] Import eden tüm router/servis dosyalarında referanslar temizle (≈10 dosya)
- [ ] `config.py`'den kaldır: `edge_livekit_urls`, `edge_minio_urls`, `minio_storage_quota_percent`, `edge_metrics_interval_sec`

### 0.2 Guardian Altyapısı — Redis + Local Agent

#### 0.2.1 Redis Altyapısı

- [ ] `config.py`: `orch_redis_url: str`, `guardian_redis_url: str` ekle
- [ ] `redis_client.py`: `get_orch_redis()`, `get_guardian_redis()` fonksiyonları
- [ ] `backend/app/services/orch_client.py` oluştur — 3 kademeli fallback:
  ```
  1. Orch-redis (orch:routing:* keys) — normal yol
  2. /var/lib/teqlif/guardian_state.json okuma — orch-redis erişilemezse
     Okuma: async open + JSON parse; JSONDecodeError veya IOError → 3. kademeye geç
     Freshness: updated_at > 90s ise stale; stale dosya kabul edilmez → 3. kademeye geç
     İlk kurulum: dosya yoksa → 3. kademeye geç (hata değil, normal)
  3. config.py defaults — guardian_state.json de yoksa son çare
     Sadece zorunlu alanlar: stream_node, storage_nodes, ai_proxy_url
     Config olmaksızın başlatmayı ENGELLEME — app çalışmaya devam eder, capacity azalır
  ```
  - `get_stream_node()`, `get_storage_nodes()`, `get_ai_proxy_url()` — hepsi bu 3 kademeli zinciri kullanır

#### 0.2.2 Guardian Agent — `backend/scripts/guardian_agent.py`

`edge_metrics_agent.py` **kaldırılır**, yerine `guardian_agent.py` gelir. Her node'da `teqlif-guardian.service` adıyla çalışır. İki bağımsız goroutine:

**A) Local Agent** — her 3s, lider olsun olmasın:

```
node.conf oku (YAML) → node_id, env, guardian_priority, components, network, hardware
  │
  ├── Metrik topla (psutil):
  │     cpu_percent, cpu_cores, load_1m/5m/15m
  │     ram_used_percent, ram_free_gb, swap_used_gb
  │     disk_{total,used,free}_gb (tüm mount'lar için)
  │     net_out_mbps, net_in_mbps
  │     net_out_percent = net_out_mbps / network.speed_mbps * 100
  │     tcp_connections (ss -s)
  │
  ├── Component health kontrol (node.conf components listesinden):
  │     health_check.type == "http" → httpx GET, timeout=2s → ok/failed/timeout
  │     health_check.type == "cmd"  → subprocess, timeout=3s → ok/failed
  │     rol özel telemetri:
  │       stream    → livekit_active_rooms, livekit_participants (LiveKit API)
  │                   stream_score = net_out_percent*0.4 + cpu*0.3 + ram*0.3
  │       storage   → minio_health (HTTP), minio_io_reads/writes (MinIO metrics API)
  │       gateway   → nginx_active_connections, nginx_rps (nginx stub_status)
  │       core      → pg_replication_lag_sec, redis_replication_lag_sec (node6'da)
  │
  ├── Orch-redis'e yaz (guardian varsa):
  │     HSET edge:metrics:{node_id}  → tüm metrikler  EXPIRE 6
  │     HSET edge:health:{node_id}   → component sağlıkları  EXPIRE 6
  │     HSET edge:telemetry:{node_id}→ rol telemetrisi  EXPIRE 10
  │
  ├── guardian_state.json'u oku → lokal routing kararlarını önbelleğe al
  │     (guardian veya orch-redis erişilemez olsa bile uygulama bu dosyayı okur)
  │
  └── Local healer:
        component health == "failed" + systemd restart count > threshold
        → systemctl reset-failed {unit} && systemctl start {unit}
        → guardian:events'e "local_heal:{node_id}:{component}" yaz
```

**B) Heartbeat + Election** — her 5s UDP port 9901:

> **V2.0 kapsamı:** Lider seçimi guardian-redis NX (Adım 1) ve UDP heartbeat basit priority karşılaştırmasıyla (Adım 2) sınırlı tutulur. Tam Bully algorithm ve gelişmiş partition toleransı V2.1'e ertelenir. V2.0'da node5+node6 ikisi de down olursa lider seçilmez → coordinator çalışmaz → lokal agentlar orch-redis'e yazmaya devam eder, guardian_state.json güncellenmez. Bu kabul edilen bir sınırdır.

```
UDP broadcast → tüm WireGuard peer'larına:
  {"node_id":"node5","priority":100,"is_leader":false,"ts":1727500000}

Dinle → peer heartbeat'lerini tablo olarak tut:
  peers = {"node6": {"priority":90,"last_seen":ts}, ...}

Lider seçimi (2 adımlı — V2.0):

  Adım 1 — Guardian Redis varsa (hızlı yol):
    SET guardian:leader "{node_id}" EX 15 NX
    → başarılı: lider ol, koordinatörü başlat
    → başarısız: lideri takip et, TTL izle

  Adım 2 — Guardian Redis yoksa (yavaş yol — basit priority):
    son 10s içinde heartbeat gelen peer'ları bul
    kendi priority > tüm reachable peer'ların priority → lider ol (standalone)
    değilse → beklemeye devam et (split-brain riskinden kaçın)

  Adım 3 — Lider keepalive:
    Lider seçildi → SET guardian:leader EX 15 NX yenile (her 10s)
    Lider düştü (heartbeat kesildi + Redis TTL doldu) → yeniden seçim
```

**C) Command Executor** — guardian-redis pub/sub `guardian:cmd:{node_id}`:

```python
ALLOWED_COMMANDS = {
    "start_service":   lambda unit: systemctl("start", unit),
    "stop_service":    lambda unit: systemctl("stop", unit),
    "restart_service": lambda unit: systemctl("restart", unit),
    "reset_failed":    lambda unit: systemctl("reset-failed", unit),
    "reload_config":   lambda unit: systemctl("reload", unit),
    "cleanup_files":   lambda path, days: cleanup_old_files(path, days),
    "report_now":      lambda: force_metrics_push(),
}
# Sonuç: guardian:events XADD {"type":"cmd_result","node":...,"status":"ok/failed"}
```

- [ ] `deploy/scale/V2.0/node.conf.examples/` dizini oluştur — her rol için örnek şablon
- [ ] `.env.production` template'lerinden `NODE_CAPABILITIES`, `NODE_ROLE`, `INTERFACE_SPEED_MBPS` kaldır → bunlar artık `node.conf`'tan okunuyor
- [ ] `deploy/scale/V2.0/systemd/teqlif-guardian.service` şablonu oluştur (tüm node'larda aynı unit dosyası)

### 0.3 Storage Service + LiveKit Reconnect Fix

#### 0.3.1 LiveKit Reconnect — stream.livekit_url Sorunu

`stream.livekit_url` stream yaratılırken DB'ye yazılır ve sabit kalır. Bu node düşünce sorun yaratır:
- `routers/streams.py` reconnect endpoint'i DB'deki `stream.livekit_url`'yi döndürür → dead node URL
- Mobile'a gönderilen URL artık geçersiz → bağlantı başarısız

**Fix:** Reconnect endpoint DB'deki URL'yi değil, orch-redis'ten güncel stream node'u okur:

```python
# routers/streams.py — /streams/{id}/token (reconnect)
# ÖNCE: node_url = stream.livekit_url  ← DB'den; dead olabilir
# SONRA:
from app.services.orch_client import get_stream_node

async def reconnect_stream(stream_id, ...):
    node = await get_stream_node()          # orch-redis → guardian_state.json → config
    if node:
        node_url = node["livekit_url"]
    else:
        node_url = stream.livekit_url       # hiçbir kaynak yoksa DB fallback (son çare)
```

**Önemli sınır:** Aktif WebRTC session'ları taşınamaz. node1 düşerse o node'daki aktif stream'ler kesilir. Reconnect yeni token oluşturur → kullanıcı yeni node'a bağlanır ama aynı room'u değil, yeni bir session başlatır. Bu V2.0'da kabul edilen bir sınırdır; belgelenmeli.

- [ ] `routers/streams.py`: reconnect endpoint `stream.livekit_url` → `orch_client.get_stream_node()` ile değiştir
- [ ] `routers/calls.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `worker.py`: `allocate_node()` çağrıları → `orch_client.get_stream_node()`
- [ ] `tasks/video_tasks.py`: `allocate_node()` → `orch_client.get_stream_node()`
- [ ] `routers/webhooks.py`: stream node referansları → `orch_client`

#### 0.3.2 Storage Service — Dual-Write + URL Şeması

`storage_service.py` baştan yazılır:

- [ ] `_build_public_url()`: node_id kaldır → `settings.media_host/{bucket}/{key}` döndür
  (`uploads_host` yalnızca S3 PUT endpoint'i — DB'ye ve mobile'a dönen URL her zaman `media_host` olmalı)
- [ ] `upload_bytes()`: `orch_client.get_storage_nodes()` listesindeki tüm node'lara `asyncio.gather` ile paralel PUT
  Partial failure: her PUT sonucu ayrı ayrı kontrol edilir. En az 1 başarılı → yükleme başarılı. 0 başarılı → hata fırlat.
  Partial success log: "node7 ok, node8 failed" → guardian degraded alert üretir, veri kaybı olmaz.
- [ ] `upload_file_dm()`: aynı dual-write mantığı
- [ ] `delete_object()`: `storage_node_id` DB kolonunu okur, sadece o node'dan siler
- [ ] DB: `storage_node_id` kolonu için Alembic migration

### 0.4 Config Temizliği

- [ ] `config.py`: `site_url` hardcoded default kaldır
- [ ] `config.py`: `use_pgbouncer: bool = True` ekle
- [ ] `config.py`: `media_host`, `uploads_host`, `minio_bucket`, `minio_dm_bucket` ekle — default yok, boot'ta validate edilir
- [ ] `config.py`: `orch_redis_url` ekle
- [ ] `config.py`: `ai_proxy_url: str` ekle — default `http://10.10.0.3:8001` (node2); uygulama her AI çağrısı öncesi orch redis'ten `ai_proxy:active_url` okur; key yoksa bu default kullanılır. Statik env değil — orchestrator failover'da bu key'i günceller.

### 0.5 Node Template Dosyaları

```
deploy/scale/V2.0/
  gateway1/resources/.env.production.template
  gateway2/resources/.env.production.template
  node1/resources/.env.production.template
  node2/resources/.env.production.template
  node3/resources/.env.production.template
  node4/resources/.env.production.template
  node5/resources/.env.production.template
  node6/resources/.env.production.template
  node7/resources/.env.production.template
  node8/resources/.env.production.template
  node9/resources/.env.production.template
```

**node5 + node6 `.env` içeriği (ortak):**
```env
DATABASE_URL=postgresql+asyncpg://<user>:<pass>@10.10.0.10:6432/teqlif
REDIS_URL=redis://:<pass>@10.10.0.11:6379/0
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
USE_PGBOUNCER=True
MEDIA_HOST=https://media.teqlif.com
UPLOADS_HOST=https://uploads.teqlif.com
MINIO_BUCKET=teqlif
MINIO_DM_BUCKET=teqlif-dm
MINIO_ENDPOINT=http://10.10.0.8:9000
MINIO_ENDPOINT_DM=http://10.10.0.8:9000
CLICKHOUSE_HOST=10.10.0.13             # node9 WG IP — ClickHouse node9'da; failover'dan bağımsız
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>
EDGE_NODE_ID=node5                  # node6 için: node6
DATA_DISK_PATH=/
INTERFACE_SPEED_MBPS=1000           # node6 için: ~2000 (DELUXHOST AMS ~2–4 Gbps)
NODE_ROLE=core
NODE_CAPABILITIES=["core","ai_proxy"]
DATA_SOURCE_NAME=postgresql://teqlif:<pg_pass>@127.0.0.1:5432/teqlif?sslmode=disable
AI_PROXY_URL=http://10.10.0.3:8001   # node2 default; orchestrator ai_proxy:active_url ile override eder
AI_PROXY_INTERNAL_TOKEN=<placeholder> # node2 ile aynı değer
# ... Firebase, LiveKit, JWT
```

`DATABASE_URL` → PG VIP `10.10.0.10` üzerinden PgBouncer port `6432`.

**ClickHouse erişim notu:** ClickHouse node9'da çalışır (10.10.0.13:8123). Her node (node5, node6) WireGuard üzerinden node9'a bağlanır. node9 down olduğunda analytics yazmaları ve sorguları circuit breaker ile sessizce düşer — analytics non-critical, app çalışmaya devam eder.

**node7 + node8 `.env` içeriği (özdeş — sadece EDGE_NODE_ID farklı):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node7                  # node8 için: node8
DATA_DISK_PATH=/mnt/data
MINIO_VOLUMES=/mnt/data/minio
MINIO_ROOT_USER=<placeholder>
MINIO_ROOT_PASSWORD=<placeholder>
INTERFACE_SPEED_MBPS=1000
NODE_ROLE=storage
NODE_CAPABILITIES=["storage"]
# GOMEMLIMIT, GOGC, MINIO_API_REQUESTS_MAX systemd unit'te Environment= ile set edilir
```

**node1 + node4 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node1                  # node4 için: node4
LIVEKIT_API_KEY=<placeholder>
LIVEKIT_API_SECRET=<placeholder>
DATA_DISK_PATH=/
INTERFACE_SPEED_MBPS=2000
NODE_ROLE=stream
NODE_CAPABILITIES=["stream"]
```

**node2 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node2
AI_PROXY_INTERNAL_TOKEN=<placeholder>
DATA_DISK_PATH=/
INTERFACE_SPEED_MBPS=300
NODE_ROLE=ai_proxy
NODE_CAPABILITIES=["ai_proxy"]
```

**gateway1 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=gateway1
DATA_DISK_PATH=/
INTERFACE_SPEED_MBPS=1000
NODE_ROLE=gateway
NODE_CAPABILITIES=["gateway"]
```

**gateway2 `.env` içeriği (`INTERFACE_SPEED_MBPS` farklı — 4000, gerçek bant 4–7 Gbps; muhafazakar alt sınır; 1000 kullanılırsa net_out_percent=%700+ olur ve routing bozulur):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=gateway2
DATA_DISK_PATH=/
INTERFACE_SPEED_MBPS=4000
NODE_ROLE=gateway
NODE_CAPABILITIES=["gateway"]
```

**node9 `.env` içeriği:**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node9
DATA_DISK_PATH=/data
INTERFACE_SPEED_MBPS=480
NODE_ROLE=monitor
NODE_CAPABILITIES=["monitor","backup","clickhouse"]
# ClickHouse — node9 üzerinde lokal
CLICKHOUSE_HOST=127.0.0.1
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>
# Backup scriptleri (Faz 10.6)
CORE_REDIS_PASS=<core_redis_pass>
PG_PASSWORD=<teqlif_db_password>
REPLICATOR_PASSWORD=<replicator_password>
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID_OPS=<telegram_chat_id_ops>
```

### 0.10 Cloudflare Güvenlik Yapılandırması (Free Tier)

Bu adımlar VPS'e dokunmaz — Cloudflare Dashboard'da yapılır.

**SSL/TLS (Dashboard → SSL/TLS):**
- [ ] Mode → **Full (Strict)** — Origin Certificate zorunlu; "Flexible" MITM riski taşır
- [ ] HSTS → **Enable** (max-age 6 months, includeSubDomains) — CF edge'de header eklenir, nginx'e gerek kalmaz
- [ ] Minimum TLS Version → **TLS 1.2**

**Güvenlik (Dashboard → Security → Settings):**
- [ ] Security Level → **Low** — Medium/High JS challenge üretir; Flutter dart:io native HTTP client JS çözemez → 503/403; "Low" yalnızca en yüksek tehdit puanlı IP'leri bloklar
- [ ] Bot Fight Mode → **Etkinleştirme** ⚠️ — Free tier Bot Fight Mode non-browser UA'leri JS challenge'a sokar; `Dart/<ver> (dart:io)` taşıyan tüm mobil API istekleri bloklanır
- [ ] Browser Integrity Check → **Etkinleştirme** ⚠️ — Browser-tipik header eksikliğinde challenge üretir; native app trafiği Referer header taşımaz → bloklanabilir

**IP Access Rules — unlimited, 5 WAF kuralı harcanmaz (Security → WAF → IP Access Rules):**
- [ ] Tor → **Block** (CF ayrı kategori sunuyor)
- [ ] Bilinen tarayıcı ASN'leri → **Block** (örn. Shodan AS12876, Censys AS396982)
- [ ] Uygulama ülke dışı kullanımı yoksa: hizmet verilen ülkeler dışı → **Managed Challenge**

**WAF Custom Rules — 5 kuralı optimum dağıt (Security → WAF → Custom Rules):**

```
Kural 1 — Path Traversal + SQL Injection imzası (Block):
(http.request.uri.path contains "../" or
 http.request.uri.path contains "/etc/passwd" or
 http.request.uri.query contains "UNION SELECT" or
 http.request.uri.query contains "<script")

Kural 2 — Kötü niyetli tarayıcı parmak izi (Block):
(lower(http.user_agent) contains "sqlmap" or
 lower(http.user_agent) contains "nikto" or
 lower(http.user_agent) contains "masscan" or
 lower(http.user_agent) contains "zgrab" or
 lower(http.user_agent) contains "nuclei" or
 http.user_agent eq "")

Kural 3 — API auth endpoint'lerine yüksek tehdit skoru (Managed Challenge):
(http.request.uri.path contains "/api/auth" and cf.threat_score gt 15)

Kural 4 — Upload endpoint POST flood (JS Challenge):
(http.request.method eq "POST" and
 http.request.uri.path contains "/api/" and
 cf.threat_score gt 20)

Kural 5 — Header anomalisi (Managed Challenge):
(not http.request.headers["user-agent"][0] exists or
 http.request.headers["x-forwarded-for"][0] matches "^[0-9,. ]{50,}")
```

**Cache Rules — 3 Page Rule (Rules → Page Rules):**
- [ ] `media.teqlif.com/*` → Cache Level: **Cache Everything** + Edge TTL: 1 month
- [ ] `api.teqlif.com/api/*` → Cache Level: **Bypass** (API yanıtları cache'lenmemeli)
- [ ] `*.teqlif.com/*.min.js` → Cache Level: **Cache Everything** + Browser TTL: 1 year

**Önemli Not:** CF free'de Rate Limiting ayrı bir ücretli ürün. Uygulama seviyesi rate limiting tamamen nginx `limit_req` + `limit_conn` üzerinde — bu nedenle nginx real_ip konfigürasyonu kritik (CF-Connecting-IP okunmalı).

---

### 0.11 Mobil Kod Değişiklikleri

- [ ] `mobile/lib/services/image_cache_manager.dart`:
  `stalePeriod: Duration(days: 2)` → `Duration(days: 14)` (§15.10 kararı)
- [ ] `mobile/lib/services/video_cache_manager.dart`:
  `getTemporaryDirectory()` → `getApplicationSupportDirectory()` (OS tarafından rastgele silinmez)
- [ ] Logout akışı: `CacheService.clearData()` + `VideoCacheManager.instance.updateCache({}, {})` çağrıları ekle (DM içerikleri kullanıcıya bağlı — çıkışta silinmeli)
- [ ] `mobile/lib/core/config/app_config.dart` V2.0:
  - `mediaBaseUrl` türetme (`replaceAll`) kaldır
  - `uploadsHost`, `mediaHost`, `shareBaseUrl`, `captchaBaseUrl` alanları ekle
  - Tüm değerleri `String.fromEnvironment(...)` ile oku
- [ ] `mobile/lib/services/captcha_service.dart`: hardcoded `'https://www.teqlif.com'` → `appConfig.captchaBaseUrl`
- [ ] Hardcoded share URL'leri (listing, profil, yayin, pro-plan, support, kvkk — 14 nokta) → `appConfig.shareBaseUrl`
- [ ] `dart_defines/staging.json` + `release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` ekle
- [ ] Backend: `MessageOut.cache_key: Optional[str]` şema alanı ekle; `GetMessagesQuery._presign_if_dm()` hem `url` (pre-signed) hem `cache_key` (sabit S3 path) döndürsün
- [ ] Mobile: DM medya cache key olarak `msg['media_url']` değil `msg['media_cache_key']` kullan
- [ ] `frontend/.well-known/assetlinks.json` oluştur (Android App Links desteği)
- [ ] `frontend/.well-known/apple-app-site-association` oluştur (iOS Universal Links desteği)
  - `DeepLinkService` `https://www.teqlif.com/...` linklerini iOS'ta universal link olarak yakalar
  - `www.teqlif.com/.well-known/apple-app-site-association` → nginx statik dosya olarak serve eder
  - `Content-Type: application/json` header zorunlu

---

### 0.6 Guardian Koordinatör — `backend/app/guardian/`

Guardian koordinatör, **seçilmiş lider node'da** `teqlif-guardian.service` içinden otomatik olarak aktif olan global karar motoru. Keepalived MASTER olmak zorunda değil — `guardian_priority` ile seçilen herhangi bir node lider olabilir. Sistem 1 node'da da 10 node'da da aynı kod çalışır.

#### Veri Modeli — Guardian Redis (port 6382)

```
# ── Topology Registry ─────────────────────────────────────────────────
guardian:topology:{node_id}           Hash  TTL=60s (agent her 30s yeniler)
  node_id, env, guardian_priority
  public_ip, wg_ip, guardian_port, speed_mbps
  cpu_cores, ram_gb
  components   → JSON  [{"name":"minio","env":"production","role":"storage_primary",...}]
  registered_at

guardian:components:{name}:{env}      Set   → bu component:env'i çalıştıran node_id'ler
  örn. guardian:components:minio:production = {"node7","node8"}
       guardian:components:livekit:production = {"node1","node4"}
       guardian:components:teqlif:staging     = {"node3"}

guardian:role:{role}                  Set   → bu rolü üstlenen node_id'ler
  örn. guardian:role:storage_primary = {"node7","node8"}
       guardian:role:ai_proxy_fallback = {"node3"}

guardian:env:production               Set   → production component'i olan node_id'ler
guardian:env:staging                  Set   → staging component'i olan node_id'ler

# ── Service State (component bazlı, env bazlı) ────────────────────────
guardian:service:{name}:{env}         Hash
  state     → HEALTHY | DEGRADED | DOWN
  # HEALTHY: ≥1 capable node sağlıklı
  # DEGRADED: kısmi kapasite (örn. 2 storage'dan 1'i kaldı)
  # DOWN: 0 capable node — sistem o servisi veremez; alert gönderildi, bekleniyor
  alive_nodes   → JSON list (sağlıklı node'lar)
  degraded_since → unix ts (DEGRADED/DOWN olduğu an)
  last_healthy   → unix ts

# ── Job State Machine ──────────────────────────────────────────────────
guardian:job:{job_id}                 Hash
  type      → backup_postgres | backup_clickhouse | backup_redis | offsite_sync |
               failover_storage | failover_ai | failover_gateway |
               failover_core | stream_rebalance | service_heal | storage_rebalance
  state     → PENDING | RUNNING | INTERRUPTED | RESUMING | SUCCESS | FAILED | DEAD
  env       → production | staging (hangi ortam için)
  assigned  → node_id (yürüten node)
  trigger   → "scheduled" | "node_down:node7" | "service_down:minio:production" | "manual"
  checkpoint → JSON (kaldığı yer — interrupt → resume buradan)
  retry     → int
  max_retry → 3
  started_at, updated_at

guardian:jobs:active                  Set   → aktif job_id'ler
guardian:jobs:history                 ZSet  score=ts → son 500 iş

# ── Event Stream ──────────────────────────────────────────────────────
guardian:events                       Redis Stream (XADD — persistent, ordered)
  {type, node, component, env, severity, message, job_id, ts}
  severity: info | warn | alert | critical

# ── Local State Cache ─────────────────────────────────────────────────
# Lider her 30s tüm node'lara gönderir → /var/lib/teqlif/guardian_state.json
# Guardian redis ve lider erişilemez olsa bile uygulama bu dosyayı okur
{
  "schema_version": 1,
  "updated_at": 0,
  "leader": "node5",
  "routing": {
    "storage_nodes": [],        # → orch:routing:storage_nodes ile sync
    "stream_primary": "",       # → orch:routing:stream_primary
    "stream_backup": "",        # → orch:routing:stream_backup
    "ai_proxy_url": "",         # → orch:routing:ai_proxy_url
    "gateways": []              # → orch:routing:gateways
  },
  "service_states": {},         # guardian:service:* snapshot
  "system_state": "healthy"
}

# ── Komut Kanalları ───────────────────────────────────────────────────
guardian:cmd:{node_id}                PubSub → edge agent command executor dinler
guardian:cmd_result:{node_id}         Stream → komut sonucu (agent yazar, koordinatör okur)

# ── Backup Registry ───────────────────────────────────────────────────
guardian:backup:{type}:last_ok        String → unix ts (backup script tamamlandığında yazar)
guardian:backup:{type}:job            String → aktif job_id
```

#### Modül Yapısı — `backend/app/guardian/`

```
guardian/
  main.py           ← guardian_loop() — lider seçildiyse koordinatörü başlat
  election.py       ← Redis NX (hızlı) + UDP peer (yavaş) lider seçimi
  topology.py       ← guardian:topology:* yönetimi; component/role index güncelleme
  health_monitor.py ← edge:metrics + edge:health TTL izle; service state hesapla
  state_machine.py  ← HEALTHY/DEGRADED/DOWN geçişleri; event yayını
  job_manager.py    ← Job CRUD, checkpoint, retry, resume mantığı
  playbook_runner.py← playbook başlat, adım yürüt, interrupt/resume
  state_broadcaster.py ← guardian_state.json'u tüm node'lara gönder (her 30s)
                          ZORUNLU: atomik yazma — tmp dosyaya yaz → rename (os.replace)
                          Yarım JSON bırakmaz; uygulama her zaman tutarlı dosya okur
  routing/
    storage.py      ← role:storage_primary node'larından sağlıklı olanlar
    stream.py       ← stream_score (net_out_percent*0.4+cpu*0.3+ram*0.3) en düşük
    ai_proxy.py     ← ai_proxy_primary → fallback → last_resort öncelik zinciri
    gateway.py      ← gateway health; CF DNS Multi-A için alive list
  playbooks/
    node_down.py    ← component bazlı: StorageDown, GatewayDown, AIProxyDown, CoreDown
    service_heal.py ← node ayakta + servis bozuk → reset-failed + start
    recovery.py     ← node/servis geri gelince reverse işlemler; routing'e yeniden ekle
    backup.py       ← BackupJob checkpoint'li; kesilirse resume
  dns.py            ← CF API: gateway + storage DNS Multi-A yönetimi
  alerting.py       ← severity bazlı Telegram #ops (warn/info) / #alerts (critical)
  backup_monitor.py ← guardian:backup:*:last_ok freshness; eşik aşılınca alert + trigger
  edge.py           ← guardian:cmd:{node} pub/sub; cmd_result oku
  models.py         ← NodeState, ServiceState, Job, PlaybookContext, RoutingDecision dataclass
```

#### Koordinatör Ana Döngüsü (lider node'da)

```python
# guardian/main.py — sadece lider seçilmişse çalışır

async def coordinator_loop():
    while True:
        # 1. Topology refresh — stale node'ları çıkar
        await topology.refresh()                    # guardian:topology:* TTL kontrol

        # 2. Tüm service state'leri hesapla (component bazlı, env bazlı)
        await health_monitor.compute_service_states()
        # guardian:service:minio:production → HEALTHY/DEGRADED/DOWN

        # 3. Service state değişimi → playbook tetikle
        await state_machine.process_transitions()
        # minio:production DOWN → StorageNodeDownPlaybook başlat
        # minio:production DOWN→HEALTHY → RecoveryPlaybook başlat

        # 4. Routing kararları → orch-redis'e yaz (uygulama okur)
        await routing.update_all()

        # 5. Aktif job'ları tick et (INTERRUPTED → RESUMING)
        await job_manager.tick()

        # 6. Backup freshness kontrol
        await backup_monitor.check_all()

        # 7. DNS senkronizasyonu
        await dns.sync_if_changed()

        # 8. State.json broadcast (her 30s)
        await state_broadcaster.push_if_due()

        await asyncio.sleep(3)
```

#### Routing Eligibility Kuralı

Guardian bir componenti routing havuzuna **ancak dört şart birlikte sağlandığında** alır:

```
1. node.conf'ta traffic_eligible: true         ← insan onayı; default false
2. env eşleşmesi: production routing → sadece env=production component
3. systemd unit: active (systemctl is-active)
4. health_check: ok (HTTP 200 veya cmd exit 0)

Dördü de sağlanmadan → component izlenir, alert atılır, AMA routing yapılmaz.
```

```python
# guardian/topology.py — eligibility check
def is_routing_eligible(component: dict, target_env: str) -> bool:
    return (
        component.get("traffic_eligible", False)   # explicit human approval
        and component["env"] == target_env          # env must match
        # systemd + health checks: health_monitor'dan gelir
    )
```

Bu kural şunu engeller: node3'te developer staging için LiveKit başlattı → Guardian production routing'ine dahil etmez. Ya da node9 kuruldu ama `traffic_eligible` yazılmadı → Guardian izler ama trafik göndermez.

#### Playbook — Component Bazlı, Env-Aware

```python
# guardian/playbooks/node_down.py

class ComponentDownPlaybook:
    """Hangi node değil — hangi component:env down oldu?"""

    HANDLERS = {
        "minio:production":           StorageFailoverHandler,
        "livekit:production":         StreamRebalanceHandler,
        "teqlif-ai-proxy:production": AIProxyFailoverHandler,
        "nginx:production":           GatewayFailoverHandler,
        "teqlif:production":          CoreAppCrashHandler,
        # staging'deki bir servis düşerse: ayrı handler, prod'u etkilemez
        "teqlif:staging":             StagingDownHandler,
    }

    async def run(self, component_name, env, ctx: PlaybookContext):
        key = f"{component_name}:{env}"
        handler = self.HANDLERS.get(key)
        if handler:
            await handler(ctx).run()
        else:
            # Tanınmayan component → sadece alert; kod değişikliği gerekmez
            await ctx.alert(f"unknown component down: {key}", severity="warn")
```

> **Not — `teqlif-orchestrator.service` geçişi:** V2.0'da `teqlif-orchestrator.service` → `teqlif-guardian.service` olarak yeniden adlandırılır. Keepalived `notify_master/backup` scriptleri güncellenir: `systemctl start/stop teqlif-guardian` çağırır. Lider koordinasyon guardian içi election mekanizmasıyla yönetilir — Keepalived MASTER olmak artık zorunluluk değil, yüksek öncelikli yol.

- [ ] `deploy/scale/V2.0/systemd/teqlif-guardian.service` şablonu oluştur
- [ ] Keepalived `notify_master/backup` scriptleri güncelle: `teqlif-orchestrator` → `teqlif-guardian`

### 0.7 Ops Komutları

- [ ] `scripts/teqlif-restart.sh`: WireGuard IP → rol tespiti → uygun servisleri yeniden başlat
- [ ] `scripts/teqlif-refresh.sh`: git pull + sync (veri servislerine dokunmaz)
- [ ] Her iki script: node8 = `10.10.0.12` = storage olarak tanısın
- [ ] `deploy/scale/V2.0/node.conf.example`: tüm roller için örnek şablon

### 0.8 Güvenlik Düzeltmesi

- [ ] FastAPI `--forwarded-allow-ips 10.10.0.2,10.10.0.9` (gateway1 + gateway2 WG IP'leri)

### 0.9 Doğrulama (lokalde)

```bash
python -c "from app.config import settings; print(settings.model_fields.keys())"
grep -r "edge_orchestrator" backend/app/  # → 0 sonuç
grep -r "minio_storage_quota" backend/app/  # → 0 sonuç
dart analyze mobile/  # → 0 hata
```

---

## Faz 1 — OS Temeli (Tüm Node'lar)

**Her node için — sırayla veya paralel uygulanır.**

### 1.1 Temel Paketler

```bash
apt-get update && apt-get upgrade -y
apt-get install -y \
  curl wget git \
  ufw fail2ban \
  wireguard wireguard-tools \
  chrony \
  htop iotop nethogs \
  unattended-upgrades apt-listchanges \
  rsync logrotate \
  jq \
  python3 python3-pip python3-venv python3-dev \
  build-essential
```

### 1.2 Kullanıcı ve SSH

```bash
# Kullanıcı oluştur
adduser tucibeyin
usermod -aG sudo tucibeyin

# SSH key ekle
mkdir -p /home/tucibeyin/.ssh
echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
chmod 700 /home/tucibeyin/.ssh
chmod 600 /home/tucibeyin/.ssh/authorized_keys
chown -R tucibeyin:tucibeyin /home/tucibeyin/.ssh
```

`/etc/ssh/sshd_config` → değiştirilecek satırlar:
```
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
X11Forwarding no
AllowUsers tucibeyin
```

```bash
systemctl restart sshd
```

### 1.3 Dizin Yapısı

```bash
mkdir -p /var/www/teqlif.com
mkdir -p /etc/teqlif
mkdir -p /var/log/teqlif/{api,worker,orchestrator}
chown -R tucibeyin:tucibeyin /var/www/teqlif.com /var/log/teqlif
chmod 755 /var/log/teqlif   # 755: promtail (system user) log dizinine girebilmeli; dosyalar systemd tarafından 0644 oluşturulur
```

### 1.4 /etc/teqlif/node.conf

YAML formatında — Guardian agent başlangıçta okur. Her node kendini tam olarak tanımlar; orchestrator/guardian bu dosyayı okuyarak topolojiyi keşfeder, hardcoded bilgiye ihtiyaç duymaz.

```bash
apt-get install -y python3-yaml   # guardian_agent.py için (1.1'de eklenmemişse)
```

**Şema (her node'a uygun değerlerle doldurulur):**

```yaml
# /etc/teqlif/node.conf
# ── Kimlik ────────────────────────────────────────────────────────────
node_id: node5                  # benzersiz, değişmez
env: production                 # production | staging | hybrid

# ── Guardian lider önceliği ───────────────────────────────────────────
# Yüksek olan önce lider adayı olur. Tüm node'lar reachable ise en yüksek kazanır.
# Önerilen: node5=100, node6=90, node3=80, node1=70, node4=60,
#            node2=50, gateway1=40, gateway2=30, node7=20, node8=10, node9=5
# node9 kasıtlı düşük: backup/monitor rolü; asla guardian lideri olmamalı
guardian_priority: 100

# ── Ağ ───────────────────────────────────────────────────────────────
network:
  public_ip: <node5_public_ip>
  wg_ip: 10.10.0.5
  wg_port: 51820
  guardian_port: 9901          # UDP heartbeat — tüm node'larda aynı
  speed_mbps: 1000

# ── Donanım (sabit beyan — agent runtime'da live ölçer, burası referans) ──
hardware:
  cpu_cores: 4
  cpu_model: "AMD EPYC"
  ram_gb: 7.8
  disks:
    - mount: /
      size_gb: 49
      type: nvme
      role: system             # system | data | backup | cache

# ── Componentler ─────────────────────────────────────────────────────
# Her component için zorunlu alanlar:
#   name             → servis adı (teqlif, minio, livekit, redis-core, ...)
#   env              → production | staging
#                      NOT: node env=hybrid olabilir; component asla hybrid değildir.
#   systemd_unit     → systemctl ile yönetilen unit adı
#   role             → bu node'da bu componentin rolü (bkz. ROLE rehberi)
#
# İsteğe bağlı alanlar:
#   port             → dinlediği port (yoksa boş bırak)
#   health_check     → "http" veya "cmd" tipi sağlık kontrolü
#   autostart        → false: guardian komutu olmadan başlamaz (default: true)
#
# Trafik yapılandırması — SADECE insan yazar, guardian ASLA otomatik değiştirmez:
#
#   traffic_eligible → true: guardian bu componente trafik yönlendirebilir
#                      false veya YOK: guardian izler, alert atar ama routing YAPMAZ
#                      DEFAULT: false — hiç yazılmamışsa guardian trafiği göndermez
#                      KURAL: alive + eligible = routing; alive alone ≠ routing
#
#   traffic_type     → internal_mesh    : sadece WireGuard mesh içi erişim
#                                         (Redis, PG, ClickHouse — dış erişim yok)
#                      gateway_proxied  : gateway1/2 arkasında; dışarıdan direct erişim yok
#                                         (teqlif API, MinIO S3 API)
#                      direct_internet  : dışarıya açık port; client doğrudan bağlanır
#                                         (LiveKit, MinIO uploads endpoint, nginx/storage)
#
#   required_ports   → direct_internet componentler için: bu portlar açık olmalı
#                      Guardian bunu bilgiye yazar ama kontrol etmez — insan sorumlu
#
# ROLE rehberi:
#   db_primary / db_replica / db_pooler
#   cache_primary / cache_replica
#   orch_primary / orch_replica
#   guardian_primary / guardian_replica
#   api / worker / worker_critical
#   analytics
#   storage_primary / storage_fallback
#   stream_primary / stream_backup
#   ai_proxy_primary / ai_proxy_fallback / ai_proxy_last_resort
#   gateway / monitor / backup_coordinator

components:
  - name: postgresql
    env: production
    port: 5432
    systemd_unit: postgresql.service
    health_check:
      type: cmd
      cmd: "pg_isready -h 127.0.0.1 -p 5432 -q"
    role: db_primary
    traffic_eligible: true
    traffic_type: internal_mesh      # PG sadece mesh içi; dışarıya asla açılmaz

  - name: redis-core
    env: production
    port: 6379
    systemd_unit: redis-core.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6379 ping"
    role: cache_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: redis-orch
    env: production
    port: 6380
    systemd_unit: redis-orch.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6380 ping"
    role: orch_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: redis-guardian
    env: production
    port: 6382
    systemd_unit: redis-guardian.service
    health_check:
      type: cmd
      cmd: "redis-cli -p 6382 ping"
    role: guardian_primary
    traffic_eligible: true
    traffic_type: internal_mesh

  - name: pgbouncer
    env: production
    port: 6432
    systemd_unit: pgbouncer.service
    health_check:
      type: cmd
      cmd: "pg_isready -h 127.0.0.1 -p 6432 -q"
    role: db_pooler
    traffic_eligible: true
    traffic_type: internal_mesh

  # clickhouse → node9'a taşındı (bkz. §4.8 + Faz 13)

  - name: teqlif
    env: production
    port: 8000
    systemd_unit: teqlif.service
    health_check:
      type: http
      url: http://127.0.0.1:8000/health
    role: api
    traffic_eligible: true
    traffic_type: gateway_proxied    # gateway1/2 proxy'ler; dışarıdan direct erişim yok

  - name: teqlif-worker
    env: production
    systemd_unit: teqlif-worker.service
    role: worker
    traffic_eligible: false          # worker dışarıya trafik almaz; izleme için kayıt var

  - name: teqlif-worker-critical
    env: production
    systemd_unit: teqlif-worker-critical.service
    role: worker_critical
    traffic_eligible: false

  - name: teqlif-ai-proxy
    env: production
    port: 8001
    systemd_unit: teqlif-ai-proxy.service
    health_check:
      type: http
      url: http://10.10.0.5:8001/health
    role: ai_proxy_last_resort
    traffic_eligible: true
    traffic_type: internal_mesh      # AI proxy sadece mesh içi; API gateway üzerinden değil
    autostart: false                 # guardian start_service komutuyla başlar; boot'ta başlamaz
```

> **traffic_eligible kuralı:** Guardian bir node'da component adını tanısa bile `traffic_eligible: true` olmadan routing yapmaz. Bu alanı sadece insan yazar — component tam olarak konfigüre edilip, gerekli portlar açılıp, hazır olduğu doğrulandıktan sonra.
> **Component asla hybrid değildir:** `env: production` veya `env: staging` — ikisi aynı anda olamaz. Aynı node'da her ikisi de çalışabilir ama ayrı component girişleriyle (örn. hem `teqlif:production` hem `teqlif:staging`).
> **node.conf örnekleri** tüm roller için `deploy/scale/V2.0/node.conf.examples/` dizininde şablon olarak tutulur.

**node9 node.conf (monitor/backup/clickhouse rolü):**

```yaml
# /etc/teqlif/node.conf — node9
node_id: node9
env: production

# Kasıtlı düşük öncelik — backup/monitor, asla guardian lider adayı olmamalı
guardian_priority: 5

network:
  public_ip: <node9_public_ip>    # 135.125.223.43
  wg_ip: 10.10.0.13
  wg_port: 51820
  guardian_port: 9901
  speed_mbps: 480                 # YABS: ~480 Mbps outbound

hardware:
  cpu_cores: 8                    # Xeon D-2123IT 4c/8t
  cpu_model: "Intel Xeon D-2123IT"
  ram_gb: 31
  disks:
    - mount: /
      size_gb: 150
      type: hdd
      role: system
    - mount: /data
      size_gb: 3500
      type: hdd_raid1
      role: backup                # ClickHouse + WAL + backup

components:
  - name: clickhouse
    env: production
    port: 8123
    systemd_unit: clickhouse-server.service
    health_check:
      type: cmd
      cmd: "clickhouse-client --query='SELECT 1' 2>/dev/null"
    role: analytics
    traffic_eligible: true
    traffic_type: internal_mesh   # Sadece WG mesh; dış erişim yok

  - name: prometheus
    env: production
    port: 9090
    systemd_unit: prometheus.service
    health_check:
      type: http
      url: "http://127.0.0.1:9090/-/healthy"
    role: monitor
    traffic_eligible: false       # Monitoring araçları trafik routing'ine dahil değil

  - name: loki
    env: production
    port: 3100
    systemd_unit: loki.service
    health_check:
      type: http
      url: "http://127.0.0.1:3100/ready"
    role: monitor
    traffic_eligible: false

  - name: grafana
    env: production
    port: 3000
    systemd_unit: grafana-server.service
    health_check:
      type: http
      url: "http://127.0.0.1:3000/api/health"
    role: monitor
    traffic_eligible: false

  - name: teqlif-pg-receivewal
    env: production
    systemd_unit: teqlif-pg-receivewal.service
    health_check:
      type: cmd
      cmd: "systemctl is-active teqlif-pg-receivewal -q"
    role: backup_coordinator
    traffic_eligible: false
```

```bash
chmod 644 /etc/teqlif/node.conf
# guardian_agent.py okuma testi:
python3 -c "import yaml; c=yaml.safe_load(open('/etc/teqlif/node.conf')); print(c['node_id'], c['env'])"
```

### 1.5 fail2ban

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true

# nginx — gateway + storage node'larda anlamlı; diğerlerinde de zararı yok
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 5
findtime = 60
bantime  = 86400

[nginx-req-limit]
enabled  = true
filter   = nginx-req-limit
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 7200
```

```bash
# nginx-req-limit filtresi (fail2ban bunu bilmez, tanımla):
cat > /etc/fail2ban/filter.d/nginx-req-limit.conf << 'EOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
EOF

systemctl enable --now fail2ban
```

### 1.6 NTP + Timezone

```bash
timedatectl set-timezone UTC
systemctl enable --now chrony
chronyc tracking  # senkronize olduğunu doğrula
```

### 1.7 Otomatik Güvenlik Güncellemeleri

```bash
dpkg-reconfigure -plow unattended-upgrades
# Sadece security güncellemeleri aktif; reboot: kapalı (manual kontrol)
```

### 1.8 LimitNOFILE — Sistem Geneli

```ini
# /etc/security/limits.d/teqlif.conf
tucibeyin soft nofile 65535
tucibeyin hard nofile 65535
root      soft nofile 65535
root      hard nofile 65535
```

```ini
# /etc/systemd/system.conf (ve /etc/systemd/user.conf)
DefaultLimitNOFILE=65535
```

```bash
systemctl daemon-reload
```

### 1.9 Swap Dosyası (Core + Storage node'ları)

Core node'lar (node5: 7.8 GB RAM, 49 GB NVMe) ve storage node'lar (node7/8: 2.9 GB RAM, 2 GB swap önceden mevcut olabilir):

```bash
# Mevcut swap kontrolü:
swapon --show
# Swap yoksa oluştur (core node'lar için 8 GB — NVMe üzerinde düşük gecikme):
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
# Doğrula:
free -h | grep Swap
```

Storage node'larda kurulum sırasında 2 GB swap bölümü genellikle var; yoksa aynı adımlarla 2 GB swapfile oluştur.

### 1.10 Log Rotation — Teqlif Servisleri

```bash
cat > /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/**/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
# Test:
logrotate -d /etc/logrotate.d/teqlif
```

`copytruncate` kullanılır — `Restart=` tetiklemeden log dosyasını döndürür; `append:` ile açık log handle'ları kırılmaz.

### 1.11 Audit Logging (auditd)

```bash
apt-get install -y auditd

# Kritik dosya ve komutları izle:
cat > /etc/audit/rules.d/teqlif.rules << 'EOF'
-w /etc/teqlif/          -p wa -k teqlif_secrets
-w /etc/wireguard/       -p wa -k wireguard_config
-w /home/tucibeyin/.ssh/ -p wa -k ssh_keys
-w /etc/sudoers          -p wa -k sudoers_change
-w /bin/sudo             -p x  -k sudo_exec
-a always,exit -F arch=b64 -S execve -F uid=0 -k root_commands
EOF

systemctl enable --now auditd
# Doğrulama:
auditctl -l | wc -l  # kural sayısı > 0 olmalı
```

Log okuma: `ausearch -k teqlif_secrets -i | tail -20`

### 1.12 Transparent Hugepages Kapatma (Tüm Node'lar)

Kernel varsayılanı THP açık gelir. Redis startup'ta doğrudan uyarır; PostgreSQL write amplification yaşar. Kalıcı kapatma:

```bash
cat > /etc/systemd/system/thp-disable.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
systemctl daemon-reload
systemctl enable thp-disable.service

# Doğrula:
cat /sys/kernel/mm/transparent_hugepage/enabled
# → always madvise [never]
```

### 1.13 Doğrulama

```bash
ssh -o PasswordAuthentication=no tucibeyin@<node_ip>  # root girişi reddedilmeli
chronyc tracking | grep "System time"
free -h | grep Swap   # swap aktif görünmeli
```

---

## Faz 2 — WireGuard Mesh (Tüm Node'lar)

**Önkoşul:** Faz 1 tüm node'larda tamamlandı.

### 2.1 Anahtar Üretimi — Her Node'da Ayrı Ayrı

```bash
# Her node'da VPS üzerinde çalıştır — private key ASLA repoya gitmiyor:
cd /etc/wireguard
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/pubkey
chmod 600 /etc/wireguard/privatekey
```

Pubkey'i not et — tüm node'ların birbirini tanıması için gerekli.

### 2.2 wg0.conf Yapısı

WireGuard sadece `AllowedIPs`'de tanımlı adresler için trafik yönlendirir. Keepalived VIP'leri (`10.10.0.10`, `10.10.0.11`) edge node'lar tarafından erişilmesi gerektiğinden (ORCH_REDIS_URL, DATABASE_URL), bu VIP'ler **node5'in peer kaydına** eklenmeli.

**Kural:**
- **Tüm node'larda** `[Interface]` bloğunda `MTU = 1420` — WireGuard IPv4 overhead 60 byte; 1500-60=1440, güvenli değer 1420. Ayarlanmazsa cloud provider'lar arası büyük transferlerde fragmentation yaşanabilir.
- **Tüm non-core node'larda** (gateway1/2, node1/2/3/4/7/8): node5 peer'ında VIP'ler var, node6'da yok (node5 = başlangıçta primary)
- **node5'in kendi wg0.conf'unda**: node6 peer'ında VIP yok
- **node6'nın kendi wg0.conf'unda**: node5 peer'ında VIP'ler var (node6 de önce node5'e bağlanır)
- Failover olduğunda: `wg set` + wg0.conf güncellenmesi gerekir (→ §4.5 notify_master scripti)

**Tüm non-core node'lar için örnek — node7'nin wg0.conf:**
```ini
# /etc/wireguard/wg0.conf — node7 örneği (non-core node'lar için şablon)
# chmod 600 /etc/wireguard/wg0.conf  ← ZORUNLU

[Interface]
Address = 10.10.0.8/24
ListenPort = 51820
MTU = 1420
PrivateKey = <node7_private_key>

# gateway1
[Peer]
PublicKey = <gateway1_pubkey>
AllowedIPs = 10.10.0.2/32
Endpoint = <gateway1_public_ip>:51820
PersistentKeepalive = 25

# gateway2
[Peer]
PublicKey = <gateway2_pubkey>
AllowedIPs = 10.10.0.9/32
Endpoint = <gateway2_public_ip>:51820
PersistentKeepalive = 25

# node1
[Peer]
PublicKey = <node1_pubkey>
AllowedIPs = 10.10.0.1/32
Endpoint = <node1_public_ip>:51820
PersistentKeepalive = 25

# node2
[Peer]
PublicKey = <node2_pubkey>
AllowedIPs = 10.10.0.3/32
Endpoint = <node2_public_ip>:51820
PersistentKeepalive = 25

# node3
[Peer]
PublicKey = <node3_pubkey>
AllowedIPs = 10.10.0.4/32
Endpoint = <node3_public_ip>:51820
PersistentKeepalive = 25

# node4
[Peer]
PublicKey = <node4_pubkey>
AllowedIPs = 10.10.0.6/32
Endpoint = <node4_public_ip>:51820
PersistentKeepalive = 25

# node5 — PRIMARY CORE: direkt IP + iki Keepalived VIP
[Peer]
PublicKey = <node5_pubkey>
AllowedIPs = 10.10.0.5/32, 10.10.0.10/32, 10.10.0.11/32
Endpoint = <node5_public_ip>:51820
PersistentKeepalive = 25

# node6 — STANDBY CORE: sadece direkt IP (başlangıçta VIP yok)
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node8 (node7 için)
[Peer]
PublicKey = <node8_pubkey>
AllowedIPs = 10.10.0.12/32
Endpoint = <node8_public_ip>:51820
PersistentKeepalive = 25

# node9 — Backup + Monitor + ClickHouse (OVH LIM)
[Peer]
PublicKey = <node9_pubkey>
AllowedIPs = 10.10.0.13/32
Endpoint = <node9_public_ip>:51820
PersistentKeepalive = 25
```

**node5'in kendi wg0.conf'u** — node6 peer'ında VIP yok, diğer peerlar non-core şablonuyla aynı:
```ini
[Interface]
Address = 10.10.0.5/24
ListenPort = 51820
MTU = 1420
PrivateKey = <node5_private_key>

# ... (gateway1/2, node1/2/3/4/7/8 aynı şekilde) ...

# node6 — sadece direkt IP
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node9 — backup + monitor + clickhouse (Faz 10'da eklenir; hot-add ile wg set kullanılabilir)
[Peer]
PublicKey = <node9_pubkey>
AllowedIPs = 10.10.0.13/32
Endpoint = <node9_public_ip>:51820
PersistentKeepalive = 25
```

**node6'nın kendi wg0.conf'u** — non-core şablonuyla aynı (node5 peer'ında VIP'ler var).

### 2.3 Başlatma

```bash
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0
```

### 2.4 Mesh Doğrulama

```bash
# Her node'dan tüm peer'lara ping at (Faz 2 mesh — node9 Faz 10'da eklenir):
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 \
          10.10.0.5 10.10.0.6 10.10.0.7 10.10.0.8 \
          10.10.0.9 10.10.0.12; do
  ping -c 1 -W 2 $ip && echo "OK $ip" || echo "FAIL $ip"
done
# NOT: 10.10.0.13 (node9) bu aşamada henüz kurulmamış olabilir — §10.0.3'te doğrulanır.

wg show wg0  # handshake zamanları güncel olmalı
```

### 2.5 Failover Sudoers — Tüm Non-Core Node'lar

Failover scriptinin SSH ile remote node'lara ulaşıp `sudo wg set` / `sudo wg-quick save wg0` çalıştırabilmesi için **tüm non-core node'larda** (gateway1, gateway2, node1, node2, node3, node4, node7, node8, node9) aşağıdaki sudoers kuralı eklenmeli:

```bash
# gateway1, gateway2, node1, node2, node3, node4, node7, node8, node9 — her birinde:
cat > /etc/sudoers.d/wg-vip << 'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *
tucibeyin ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick save wg0
EOF
chmod 440 /etc/sudoers.d/wg-vip
# Doğrula:
visudo -c -f /etc/sudoers.d/wg-vip
```

> **NOT:** Faz 4.5'te node6 için oluşturulan `/etc/sudoers.d/wg-vip` bu dosyanın aynısıdır — orada zaten bulunduğundan node6 için bu adım atlanır.

---

## Faz 3 — Rol Bazlı OS Tuning (Tüm Node'lar)

**Önkoşul:** Faz 2 tamamlandı.

### 3.1 Gateway (gateway1, gateway2)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.core.netdev_max_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW — 80/443 yalnızca Cloudflare IP aralıklarına açık (gerçek IP bypass'ını engeller):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat — tüm node'larda açık

# Cloudflare IPv4 aralıkları (kaynak: https://www.cloudflare.com/ips-v4/)
# Bu aralıklar değişebilir — https://www.cloudflare.com/ips/ adresinden periyodik kontrol et
for CF_IP in \
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
  141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
  197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 \
  104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
  ufw allow from ${CF_IP} to any port 80 proto tcp
  ufw allow from ${CF_IP} to any port 443 proto tcp
done

ufw --force enable

# Doğrulama — CF IP dışından doğrudan istek engellenmiş olmalı:
ufw status numbered | grep -E "80|443"
```

**Not:** gateway1 + gateway2 Cloudflare proxy arkasında. Cloudflare'in gerçek IP'lerinizi keşfetmesini engellemenin tek yolu bu kısıtlamadır. CF IP aralıkları nadiren değişir ama `https://www.cloudflare.com/ips-v4/` adresi yılda bir kontrol edilmeli.

### 3.2 Core (node5, node6)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.swappiness = 1               # PostgreSQL buffer pool swap'a atılmasın; storage ile aynı kural
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
kernel.pid_max = 65536
net.core.somaxconn = 65535
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# node5/6 hiçbir servisi internete açmaz — tümü WireGuard üzerinden
ufw --force enable
```

### 3.3 Stream (node1, node4)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
# WebRTC UDP için büyük buffer
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.udp_rmem_min = 131072       # 128KB min per socket — LiveKit WebRTC
net.ipv4.udp_wmem_min = 131072
net.ipv4.udp_mem = 102400 873800 16777216
net.core.netdev_max_backlog = 65535
net.core.netdev_budget = 600         # tek NAPI poll'da daha fazla paket — yüksek PPS için
net.core.netdev_budget_usecs = 8000
fs.file-max = 500000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**UFW:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# LiveKit — internete açık portlar:
ufw allow 7880/tcp    # LiveKit API/WebRTC
ufw allow 7881/tcp    # LiveKit TCP fallback
ufw allow 7882/udp    # LiveKit UDP
ufw allow 3478/udp    # TURN UDP
ufw allow 5349/tcp    # TURN TLS
ufw allow 50000:60000/udp  # ICE UDP aralığı
ufw --force enable
```

### 3.4 Storage (node7, node8)

**Sysctl (node7 = node8 — özdeş):**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 50
vm.swappiness = 1              # NVMe olmasa da swap'tan kaç — 1 HDD üzerinde de doğru
fs.file-max = 200000
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**HDD Optimizasyonu (her iki node):**
```bash
# udev rule — HDD için scheduler + readahead + derin I/O kuyruğu
cat > /etc/udev/rules.d/60-teqlif-hdd.rules << 'EOF'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", \
  ATTR{queue/scheduler}="mq-deadline", \
  ATTR{queue/read_ahead_kb}="2048", \
  ATTR{queue/nr_requests}="128"
EOF
udevadm control --reload-rules && udevadm trigger
```

**Swap Doğrulama (her iki node):**
```bash
# node7 + node8: 2.0 GB SSD swap beklenir
swapon --show
cat /etc/fstab | grep swap
# Kalıcı değilse /etc/fstab'a ekle
```

**UFW + iptables connection limit — node7/8 DNS Only olduğundan CF koruması yok; kernel seviyesinde savunma:**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# uploads.teqlif.com DNS Only → doğrudan IP'ye gelir (CloudFlare koruması yok):
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# iptables hashlimit: tek IP'den 443'e max 60 yeni bağlantı/dakika (flood limiti)
# UFW zaten iptables kullandığından bu kural UFW kurallarından SONRA eklenmeli:
iptables -I INPUT -p tcp --dport 443 \
  -m hashlimit \
  --hashlimit-name https_flood \
  --hashlimit-above 60/min \
  --hashlimit-burst 80 \
  --hashlimit-mode srcip \
  -j DROP

iptables -I INPUT -p tcp --dport 80 \
  -m hashlimit \
  --hashlimit-name http_flood \
  --hashlimit-above 60/min \
  --hashlimit-burst 80 \
  --hashlimit-mode srcip \
  -j DROP

# Kalıcı hale getir:
apt-get install -y iptables-persistent
netfilter-persistent save
```

### 3.5 AI Proxy (node2) + Monitor (node9)

**Sysctl:**
```ini
# /etc/sysctl.d/99-teqlif.conf
vm.swappiness = 5
fs.file-max = 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.overcommit_memory = 1   # node9: Prometheus + Loki mmap — overcommit olmadan ENOMEM alır
```

**UFW (node2 — AI Proxy):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
ufw --force enable
```

**UFW (node9 — Monitor + Backup + ClickHouse):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Grafana sadece WireGuard üzerinden erişilir:
# (ufw allow 3000/tcp AÇILMAZ — sadece wg0'dan erişilir)
ufw --force enable
```

**UFW (node3 — Staging):**
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Staging uygulama portları sadece WireGuard üzerinden:
# (ufw allow 8000/tcp AÇILMAZ — sadece wg0'dan erişilir)
ufw --force enable
```

### 3.6 Sysctl Uygulama

```bash
sysctl --system  # tüm /etc/sysctl.d/*.conf dosyalarını yükle
```

---

## Faz 4 — Veri Katmanı HA (node5 Primary + node6 Standby)

**Önkoşul:** Faz 3 tamamlandı.

### 4.1 PostgreSQL 17 — node5 Primary

**Kurulum (PGDG repo üzerinden):**
```bash
apt-get install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
apt-get install -y postgresql-17
```

**Memory planlama (node5: 7.8 GB RAM):**
- shared_buffers: 2 GB (RAM'in %25'i)
- Core Redis: 2 GB maxmemory
- Orch Redis: 256 MB maxmemory
- Guardian Redis: 128 MB maxmemory
- FastAPI (4 worker × ~150 MB): ~600 MB
- ARQ workers: ~300 MB
- ClickHouse: ~~500 MB~~ → **node9'a taşındı, 0 MB**
- OS: ~500 MB
- Toplam: ~5.8 GB → 2.0 GB boş + 8 GB swap güvenlik neti

**`/etc/postgresql/17/main/postgresql.conf`:**
```ini
# Bağlantı
listen_addresses = '*'   # Tüm interface — Keepalived VIP (10.10.0.10) failover'da otomatik bind; UFW WG dışını blokluyor
port = 5432
max_connections = 100

# Bellek (node5: 7.8 GB RAM, NVMe)
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 256MB
work_mem = 20MB
wal_buffers = 64MB

# NVMe için kritik ayarlar:
random_page_cost = 1.1
effective_io_concurrency = 200

# Checkpoint
checkpoint_completion_target = 0.9
min_wal_size = 1GB
max_wal_size = 4GB

# Replikasyon
wal_level = replica
max_wal_senders = 5
wal_keep_size = 2GB
hot_standby = on
wal_log_hints = on           # pg_rewind için zorunlu (§5.6.1) — data checksums yoksa olmaz
max_replication_slots = 5    # pg_rewind + olası mantıksal replikasyon için

# Performans
default_statistics_target = 100
jit = off                    # PG17 OLTP: kısa tekrar sorgularda JIT compile overhead > execution time
```

**`/etc/postgresql/17/main/pg_hba.conf` — eklecek satırlar:**
```
# PgBouncer — lokal (node5 normal çalışma)
host  teqlif  teqlif     127.0.0.1/32     scram-sha-256
# PgBouncer — node6 IP (failover sonrası node6 PgBouncer → node6 PG)
host  teqlif  teqlif     10.10.0.7/32     scram-sha-256
# node9 — pg_dump (Faz 10.5 backup script)
host  teqlif  teqlif     10.10.0.13/32    scram-sha-256
# node6 streaming replication
host  replication  replicator  10.10.0.7/32  scram-sha-256
# node9 — pg_receivewal (sürekli WAL arşivleme) + pg_basebackup (haftalık fiziksel yedek)
host  replication  replicator  10.10.0.13/32 scram-sha-256
```

**Not:** `10.10.0.7/32` girişi olmadan node6 promote olduktan sonra kendi PgBouncer'ı `host=127.0.0.1 → listen_addresses=10.10.0.7` bağlantısında `pg_hba.conf` reddeder ve uygulama DB bağlantısı kuramaz.

**Kullanıcı ve DB:**
```sql
CREATE USER teqlif WITH PASSWORD '<password>';
CREATE USER replicator WITH REPLICATION PASSWORD '<password>';
CREATE DATABASE teqlif OWNER teqlif;
```

### 4.2 PgBouncer — node5 ve node6

**Kurulum:**
```bash
apt-get install -y pgbouncer

# PgBouncer process crash sonrası otomatik kurtarma — paket varsayılanı restart içermez
mkdir -p /etc/systemd/system/pgbouncer.service.d
cat > /etc/systemd/system/pgbouncer.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
systemctl daemon-reload
```

**`/etc/pgbouncer/pgbouncer.ini`:**
```ini
[databases]
teqlif = host=127.0.0.1 port=5432 dbname=teqlif

[pgbouncer]
listen_addr = *              # 0.0.0.0 — Keepalived VIP 10.10.0.10 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
log_connections = 0
log_disconnections = 0
```

**`/etc/pgbouncer/userlist.txt`:**
```
"teqlif" "SCRAM-SHA-256$4096:<base64-salt>$<base64-storedKey>:<base64-serverKey>"
```

`auth_type = scram-sha-256` ile PgBouncer `md5` hash kabul etmez — SCRAM verifier veya plaintext şifre gerekir. SCRAM verifier üretmek için: `psql -c "SELECT rolpassword FROM pg_authid WHERE rolname='teqlif';"` çalıştır (node5'te `postgres` user ile); çıktıyı doğrudan userlist.txt'e yapıştır. Alternatif olarak plaintext kullanılabilir: `"teqlif" "<plaintext_password>"` — ama tercih edilmez.

Uygulama `DATABASE_URL` olarak `10.10.0.10:6432` (PG VIP üzerinden PgBouncer) kullanır.

### 4.3 Core Redis — node5 (port 6379)

```bash
apt-get install -y redis-server
# Varsayılan redis-server.service port 6379'da başlar — özel servislerle çakışır; devre dışı bırak:
systemctl disable --now redis-server
cp /etc/redis/redis.conf /etc/redis/redis-core.conf
mkdir -p /var/lib/redis-core
chown redis:redis /var/lib/redis-core
chmod 750 /var/lib/redis-core
```

**`/etc/redis/redis-core.conf` — değiştirilecek satırlar:**
```
port 6379
bind 0.0.0.0                 # Keepalived VIP 10.10.0.11 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
requirepass <password>
dir /var/lib/redis-core       # RDB + AOF dizini — backup script bu yolu kullanır
maxmemory 2gb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
save 900 1
save 300 10
save 60 10000
tcp-keepalive 300
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
loglevel notice
logfile /var/log/redis/redis-core.log
```

```bash
# Ayrı systemd unit:
cp /lib/systemd/system/redis-server.service \
   /etc/systemd/system/redis-core.service
# ExecStart → redis-server /etc/redis/redis-core.conf
systemctl enable --now redis-core
```

### 4.4 Orch Redis — node5 (port 6380)

**`/etc/redis/redis-orch.conf`:**
```
port 6380
bind 0.0.0.0                 # Keepalived VIP 10.10.0.11 üzerinden erişim zorunlu; UFW WireGuard dışını blokluyor
requirepass <password>
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly no
save ""               # ephemeral — disk'e yazma
hz 20                 # daha sık arka plan işi
activedefrag yes
active-defrag-threshold-lower 10
active-defrag-threshold-upper 30
loglevel notice
logfile /var/log/redis/redis-orch.log
```

```bash
# Ayrı systemd unit: redis-orch.service
systemctl enable --now redis-orch
```

### 4.4.1 Guardian Redis — node5 (port 6382)

Guardian'ın özel veri kanalı. **Sadece `teqlif-guardian.service` okur ve yazar** — uygulama kodu, worker, başka hiçbir servis dokunmaz. Topology registry, job state machine, event stream, komut kanalları burada yaşar.

**`/etc/redis/redis-guardian.conf`:**
```
port 6382
bind 0.0.0.0
requirepass <guardian_redis_pass>       # .env.production'da GUARDIAN_REDIS_URL
maxmemory 128mb
maxmemory-policy allkeys-lru
appendonly yes                          # Guardian state kalıcı olmalı — job checkpoint'ler kaybolmamalı
appendfsync everysec
save 3600 1                             # 1h'de 1 değişiklik varsa snapshot
hz 20
activedefrag yes
loglevel notice
logfile /var/log/redis/redis-guardian.log
```

```bash
# Ayrı systemd unit — redis-orch ve redis-core ile aynı yapıda
systemctl enable --now redis-guardian
redis-cli -p 6382 -a <guardian_redis_pass> ping  # → PONG
```

> **node6'da da kurulur** (§4.7 redis replikasyon bölümünde) — Keepalived failover'da `REPLICAOF NO ONE` ile standalone'a geçer, tıpkı redis-orch gibi.

> **UFW:** guardian-redis portu (6382) sadece WireGuard mesh içinden erişilebilir — node5/node6 dışındaki node'larda guardian agent bağlanır. Dış dünyaya kapalı.

> **Heartbeat portu:** UDP 9901 tüm node'larda `ufw allow in on wg0 proto udp to any port 9901` ile açılır (§1.5 UFW kurallarına eklenir).

### 4.5 Keepalived — node5 (MASTER)

```bash
apt-get install -y keepalived
```

**`/etc/keepalived/keepalived.conf` — node5:**
```
vrrp_script chk_postgres {
    # pg_isready: postgresql-client paketiyle gelir — nagios-plugins bağımlılığı yok
    script "/usr/bin/pg_isready -h 127.0.0.1 -p 5432 -q"
    interval 2
    weight -20
}

vrrp_script chk_redis {
    script "/usr/bin/redis-cli -p 6379 -a <password> ping"
    interval 2
    weight -20
}

# VRRP sync group: VI_PG ve VI_Redis her zaman birlikte failover yapar.
# Biri düşse bile ikisi de geçer — split VIP routing'i engeller.
vrrp_sync_group VG_CORE {
    group {
        VI_PG
        VI_Redis
    }
    notify_master "/etc/keepalived/scripts/wg_vip_node5.sh MASTER"
    notify_backup "/etc/keepalived/scripts/wg_vip_node5.sh BACKUP"
}

# ⚠️ WireGuard üzerinde VRRP multicast çalışmaz.
# VRRP advertisement'ları 224.0.0.18'e gönderilir; WireGuard AllowedIPs'de
# multicast tanımlı değil → paketler iletilmez → her iki node MASTER olur (split-brain).
# Çözüm: unicast_src_ip + unicast_peer ZORUNLUdur.

vrrp_instance VI_PG {
    state MASTER
    interface wg0
    virtual_router_id 51
    priority 110
    nopreempt              # failback manüeldir: node5 boot edince otomatik preempt etmez
    advert_int 1
    unicast_src_ip 10.10.0.5        # node5 wg0 IP
    unicast_peer {
        10.10.0.7                   # node6 wg0 IP
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.10/32
    }
    track_script { chk_postgres chk_redis }
}

vrrp_instance VI_Redis {
    state MASTER
    interface wg0
    virtual_router_id 52
    priority 110
    nopreempt              # failback manüeldir: node5 boot edince otomatik preempt etmez
    advert_int 1
    unicast_src_ip 10.10.0.5
    unicast_peer {
        10.10.0.7
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.11/32
    }
    track_script { chk_postgres chk_redis }
}
```

> **`nopreempt` zorunludur:** Olmasa, node5 crash→boot sonrası keepalived otomatik priority 110'la preempt yapar. WG routing node6'nın notify_backup'ı tarafından güncellenir ama node5'te PgBouncer disabled, PostgreSQL diverged timeline'da → uygulama çalışmaz, split-brain riski. `nopreempt` ile failback tamamen manüel kontrol altında kalır.

**`/etc/keepalived/scripts/wg_vip_node5.sh` — node5'te:**
```bash
# node5'te kurulur; failback (node6→node5 VIP dönüşü) sırasında tetiklenir.
mkdir -p /etc/keepalived/scripts
cat > /etc/keepalived/scripts/wg_vip_node5.sh << 'SCRIPT'
#!/bin/bash
STATE="${1}"
SECRETS_FILE="/etc/keepalived/secrets/failover.env"
[ -f "${SECRETS_FILE}" ] && source "${SECRETS_FILE}"

if [ "$STATE" = "MASTER" ]; then
    # PostgreSQL failback sonrası recovery'deyse promote et
    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2
    fi

    # PgBouncer: standby'da disabled edilmişti
    systemctl enable pgbouncer
    systemctl start pgbouncer

    # Uygulama servislerini başlat (teqlif-guardian tüm node'larda her zaman aktif — başlatma)
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian

    # Telegram bildirimi
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILBACK TAMAMLANDI: node6→node5 VIP geri dönüşü* — servisler aktif" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true

else
    # node5 BACKUP: health check düşünce node6 MASTER oluyor
    # teqlif-guardian durdurulmuyor — agent tüm node'larda çalışır; sadece app servisleri durur
    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
    systemctl disable pgbouncer
fi

logger "wg_vip_node5: STATE=${STATE} completed"
SCRIPT
chmod 750 /etc/keepalived/scripts/wg_vip_node5.sh

# Secrets (node5'te):
mkdir -p /etc/keepalived/secrets
chmod 700 /etc/keepalived/secrets          # dizin de kilitli; 755 kalırsa dosya adı görünür
chown root:root /etc/keepalived/secrets
cat > /etc/keepalived/secrets/failover.env << 'EOF'
TELEGRAM_BOT_TOKEN="<telegram_bot_token>"
TELEGRAM_CHAT_ID_ALERTS="<telegram_chat_id_alerts>"
EOF
chmod 600 /etc/keepalived/secrets/failover.env
chown root:root /etc/keepalived/secrets/failover.env

systemctl enable --now keepalived
```

> **Not:** `wg_vip_node5.sh MASTER` WireGuard routing güncellemesi YAPMAZ — failback manüel akışında node6'nın `notify_backup`'ı WG routing'i zaten günceller (bkz. §4.5 node6 script). node5'in script'i yalnızca PostgreSQL promote + PgBouncer + servis başlatma sorumluluğunu üstlenir.

**`/etc/keepalived/keepalived.conf` — node6:** `state BACKUP`, `priority 100`; unicast_src_ip/peer ters; vrrp_script tanımları ve sync group notify callback'leri var:

```
vrrp_script chk_postgres {
    script "/usr/bin/pg_isready -h 127.0.0.1 -p 5432 -q"
    interval 2
    weight -20
}

vrrp_script chk_redis {
    script "/usr/bin/redis-cli -p 6379 -a <password> ping"
    interval 2
    weight -20
}

vrrp_sync_group VG_CORE {
    group {
        VI_PG
        VI_Redis
    }
    notify_master "/etc/keepalived/scripts/wg_vip_failover.sh MASTER"
    notify_backup "/etc/keepalived/scripts/wg_vip_failover.sh BACKUP"
}

vrrp_instance VI_PG {
    state BACKUP
    interface wg0
    virtual_router_id 51
    priority 100
    advert_int 1
    unicast_src_ip 10.10.0.7        # node6 wg0 IP
    unicast_peer {
        10.10.0.5                   # node5 wg0 IP
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.10/32
    }
    track_script { chk_postgres chk_redis }
}

vrrp_instance VI_Redis {
    state BACKUP
    interface wg0
    virtual_router_id 52
    priority 100
    advert_int 1
    unicast_src_ip 10.10.0.7
    unicast_peer {
        10.10.0.5
    }
    authentication {
        auth_type PASS
        auth_pass <keepalived_pass>
    }
    virtual_ipaddress {
        10.10.0.11/32
    }
    track_script { chk_postgres chk_redis }
}
```

**`/etc/keepalived/scripts/wg_vip_failover.sh` — node6'da:**

```bash
#!/bin/bash
# Keepalived sync group notify: WireGuard VIP AllowedIPs güncelleme + Redis config temizleme.
# node6 MASTER olunca: tüm non-core node'larda VIP'ler node5→node6'ya taşınır.
# node6 BACKUP olunca: ters işlem.

STATE=$1   # MASTER veya BACKUP

# Şifreler script içinde hardcoded değil — ayrı dosyadan okunur (600 root:root)
SECRETS_FILE="/etc/keepalived/secrets/failover.env"
if [ ! -f "${SECRETS_FILE}" ]; then
    logger "wg_vip_failover: HATA — secrets dosyası bulunamadı: ${SECRETS_FILE}"
    exit 1
fi
. "${SECRETS_FILE}"
# secrets dosyası içeriği (örnek — gerçek değerler VPS'te doldurulur):
# ORCH_REDIS_PASS="<orch_redis_pass>"
# NODE5_PUBKEY="<node5_pubkey>"
# NODE6_PUBKEY="<node6_pubkey>"

if [ "$STATE" = "MASTER" ]; then
    NEW_PRIMARY_PUBKEY="${NODE6_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.7/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE5_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.5/32"
else
    NEW_PRIMARY_PUBKEY="${NODE5_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.5/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE6_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.7/32"
fi

# 1. Tüm non-core node'larda live WG routing güncelle
ALL_WG_IPS="10.10.0.2 10.10.0.9 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.8 10.10.0.12 10.10.0.13"

for WG_IP in ${ALL_WG_IPS}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i /home/tucibeyin/.ssh/id_ed25519_failover \
        tucibeyin@${WG_IP} \
        "sudo wg set wg0 peer ${NEW_PRIMARY_PUBKEY} allowed-ips ${NEW_PRIMARY_IPS} && \
         sudo wg set wg0 peer ${NEW_STANDBY_PUBKEY} allowed-ips ${NEW_STANDBY_IPS}" \
        2>/dev/null || true   # down node atlanır; WG routing diğerleri için güncellenir
done

# 2. Yerel (node6) WG routing güncelle
sudo wg set wg0 peer "${NEW_PRIMARY_PUBKEY}" allowed-ips "${NEW_PRIMARY_IPS}"
sudo wg set wg0 peer "${NEW_STANDBY_PUBKEY}" allowed-ips "${NEW_STANDBY_IPS}"

# 3. MASTER olduğumuzda: Redis config'den replicaof kaldır (restart sonrası kendine bağlanmasın)
#    BACKUP olduğumuzda: yeniden ekle (node5 primary'ya replica ol)
if [ "$STATE" = "MASTER" ]; then
    # 3a. Core Redis'i canlı olarak standalone yap — config değişikliği tek başına yetmez,
    #     process replica modunda kalmaya devam eder (read-only → yazma başarısız)
    redis-cli -p 6379 -a "${CORE_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-core.conf   # restart sonrası da standalone kalır

    # 3b. Orch Redis'i canlı olarak standalone yap — DEL ve orchestrator SET NX bundan sonra çalışır
    redis-cli -p 6380 -a "${ORCH_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-orch.conf

    # 3c. Guardian Redis'i canlı olarak standalone yap — job checkpoint'leri ve lider seçimi buradan beslenir
    #     Sadece config değiştirmek yetmez: process replica modunda (read-only) kalmaya devam eder
    redis-cli -p 6382 -a "${GUARDIAN_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-guardian.conf

    # 4. PostgreSQL promote — standby → primary (zaten primary ise atla)
    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2  # promote'un tamamlanmasını bekle
    fi

    # 4a. WAL backup replication slotu oluştur — node9 pg_receivewal için
    # (slot node5'te oluşturulmuştu; pg_basebackup slot state'i kopyalamaz → node6'da yoktur)
    sudo -u postgres psql -c \
      "SELECT pg_create_physical_replication_slot('wal_backup_node9') \
       WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='wal_backup_node9');" \
      2>/dev/null || true

    # 5. PgBouncer başlat (standby'da disabled'dı)
    systemctl start pgbouncer

    # 6. Uygulama servislerini başlat (teqlif-guardian agent her zaman çalışır — sadece app servisleri başlar)
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian

    # 7. Uzak node'larda WireGuard config'i diske yaz (reboot sonrası da kalıcı olsun)
    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} \
            "sudo wg-quick save wg0" \
            2>/dev/null || true
    done
    # Yerel node6'da da diske yaz:
    wg-quick save wg0

    # 8. Telegram #alerts bildirimi (hata olsa da devam et)
    source "${SECRETS_FILE}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILOVER TAMAMLANDI: node5→node6 VIP geçişi* — PG promote + servisler aktif" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true

else
    # 3b. Failback: node5 VIP'i tekrar aldığında node6 replica olmalı
    # Servisleri durdur — node5 primary'ya geri döndü
    # teqlif-guardian durdurulmuyor — agent her node'da her zaman çalışır
    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true

    grep -q '^replicaof' /etc/redis/redis-core.conf || \
        echo "replicaof 10.10.0.11 6379" >> /etc/redis/redis-core.conf
    grep -q '^replicaof' /etc/redis/redis-orch.conf || \
        echo "replicaof 10.10.0.11 6380" >> /etc/redis/redis-orch.conf
    grep -q '^replicaof' /etc/redis/redis-guardian.conf || \
        echo "replicaof 10.10.0.5 6382" >> /etc/redis/redis-guardian.conf
    # NOT: guardian-redis VIP üzerinden replika olmaz (guardian-redis VIP'te değil, direkt IP'de)
    # Failback: node5 geri döndüğünde guardian-redis node5:6382'ye bağlanır
    # Redis'i yeniden başlat ki yeni primary'ya (node5 VIP/IP) bağlansın
    systemctl restart redis-core redis-orch redis-guardian
fi

logger "wg_vip_failover: STATE=${STATE} completed"
```

**SSH keypair — node6'da failover için ayrı anahtar üret:**
```bash
# node6'da:
su - tucibeyin -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_failover -N ''"
# Üretilen public key'i (~/.ssh/id_ed25519_failover.pub) diğer tüm node'ların
# /home/tucibeyin/.ssh/authorized_keys dosyasına ekle:
# Hedef node'lar: gateway1 (10.10.0.2), gateway2 (10.10.0.9), node1 (10.10.0.1),
#   node2 (10.10.0.3), node3 (10.10.0.4), node4 (10.10.0.6),
#   node7 (10.10.0.8), node8 (10.10.0.12), node9 (10.10.0.13)
# NOT: node9 Faz 10'da kurulur — o fazda authorized_keys ekleme adımı hatırlatılır (§10.6.1).
cat /home/tucibeyin/.ssh/id_ed25519_failover.pub
# → Bu çıktıyı her node'da: echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
```

```bash
# Secrets dizini + failover.env (600 root:root — script içinde hardcoded değil):
mkdir -p /etc/keepalived/secrets
chmod 700 /etc/keepalived/secrets          # dizin de kilitli; 755 kalırsa dosya adı görünür
chown root:root /etc/keepalived/secrets
cat > /etc/keepalived/secrets/failover.env << 'EOF'
CORE_REDIS_PASS="<core_redis_pass>"
ORCH_REDIS_PASS="<orch_redis_pass>"
GUARDIAN_REDIS_PASS="<guardian_redis_pass>"
NODE5_PUBKEY="<node5_pubkey>"
NODE6_PUBKEY="<node6_pubkey>"
TELEGRAM_BOT_TOKEN="<telegram_bot_token>"
TELEGRAM_CHAT_ID_ALERTS="<telegram_chat_id_alerts>"
EOF
chmod 600 /etc/keepalived/secrets/failover.env
chown root:root /etc/keepalived/secrets/failover.env

mkdir -p /etc/keepalived/scripts
chmod 750 /etc/keepalived/scripts/wg_vip_failover.sh
# sudoers: wg set (routing) + wg-quick save (diske yazma) — §2.5 ile aynı kural
cat > /etc/sudoers.d/wg-vip << 'EOF'
tucibeyin ALL=(ALL) NOPASSWD: /usr/bin/wg set wg0 peer * allowed-ips *
tucibeyin ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick save wg0
EOF
chmod 440 /etc/sudoers.d/wg-vip
visudo -c -f /etc/sudoers.d/wg-vip

systemctl enable --now keepalived
```

**Not:** `wg set` live config'i günceller ama `/etc/wireguard/wg0.conf` değişmez. Yukarıdaki adım 7 `wg-quick save wg0` ile kalıcı hale getirir. Remote node'larda bu komutun çalışması için §2.5'teki sudoers kuralı gereklidir.

### 4.6 PostgreSQL Streaming Replication — node6

```bash
# node6'da:
systemctl stop postgresql
su - postgres -c "pg_basebackup \
  -h 10.10.0.5 -U replicator \
  -D /var/lib/postgresql/17/main \
  -Xs -P -R"
# -R: standby.signal + primary_conninfo otomatik oluşturur

# pg_basebackup node5'in postgresql.conf'unu kopyalar.
# listen_addresses = '*' — node5'ten kopyalandı; node6 için de geçerli. Değiştirme gerekmez.
grep listen_addresses /var/lib/postgresql/17/main/postgresql.conf  # → * olmalı

systemctl start postgresql
```

> **ÖNEMLİ — node9 eklendiğinde (Faz 10):** pg_basebackup veri dizinini kopyalar; `pg_hba.conf` da bu kopyanın içindedir. Ancak Faz 10'da node9 eklendikten sonra node5'e eklenen pg_hba.conf girişleri **WAL streaming replication ile node6'ya otomatik yansımaz** — config dosyası değişiklikleri WAL kapsamı dışındadır. node9 backup bağlantıları başarısız olmasın diye §10.6.1'de node6 pg_hba.conf'u da güncellenir.

**Doğrulama:**
```bash
# node6'da:
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"
# → t

# node5'te:
psql -h 127.0.0.1 -U postgres -c "SELECT * FROM pg_stat_replication;"
# → node6'yı görmeli
```

### 4.7 Redis Replication — node6

```bash
# VIP üzerinden replication (10.10.0.11) — node5→node6 geçişinde replication hedefi değişmez
cat >> /etc/redis/redis-core.conf << 'EOF'
replicaof 10.10.0.11 6379
masterauth <password>
EOF

cat >> /etc/redis/redis-orch.conf << 'EOF'
replicaof 10.10.0.11 6380
masterauth <password>
EOF

# Guardian Redis — node5 direkt IP üzerinden replika (VIP'te değil)
# Guardian-redis VIP'e bağlanmaz çünkü guardian-redis Keepalived VIP kapsamı dışında
cat >> /etc/redis/redis-guardian.conf << 'EOF'
replicaof 10.10.0.5 6382
masterauth <guardian_redis_pass>
EOF

systemctl restart redis-core redis-orch redis-guardian

# Doğrula:
redis-cli -h 127.0.0.1 -p 6379 -a <password> info replication | grep role  # → role:slave
redis-cli -h 127.0.0.1 -p 6380 -a <password> info replication | grep role  # → role:slave
redis-cli -h 127.0.0.1 -p 6382 -a <guardian_redis_pass> info replication | grep role  # → role:slave
```

### 4.8 ClickHouse — node9

> **V2.0 mimarisi:** ClickHouse node5'ten node9'a taşındı. node5/6 ClickHouse'dan tamamen bağımsız — failover karmaşıklığı azaldı, node5 ~500 MB RAM serbest kaldı. App WireGuard üzerinden `10.10.0.13:8123`'e bağlanır.
> **Kurulum sırası:** Bu bölümdeki komutlar **Faz 10.0 (node9 Ön Kurulum)** adımı olarak çalıştırılır. node9 OS temel kurulumu (Faz 1), WireGuard mesh (Faz 2) ve OS tuning (§3.5) tamamlandıktan sonra bu adıma geçilir.

```bash
apt-get install -y apt-transport-https ca-certificates gnupg

# ClickHouse resmi Debian APT reposu:
curl -fsSL 'https://packages.clickhouse.com/deb/clickhouse.gpg' \
  | gpg --dearmor > /usr/share/keyrings/clickhouse-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] \
  https://packages.clickhouse.com/deb/ stable main" \
  > /etc/apt/sources.list.d/clickhouse.list

apt-get update
apt-get install -y clickhouse-server clickhouse-client
```

**`/etc/clickhouse-server/config.d/teqlif.xml`:**
```xml
<clickhouse>
  <listen_host>127.0.0.1</listen_host>
  <listen_host>10.10.0.13</listen_host>  <!-- node9 WG IP — tüm mesh node'ları buraya bağlanır -->
  <max_connections>100</max_connections>
  <!-- Data dizini — node9 /data partition'ında; 3.5 TB HDD RAID-1 -->
  <path>/data/clickhouse/</path>
  <tmp_path>/data/clickhouse/tmp/</tmp_path>
  <!-- Backup disk — yerel backup, ayrıca offsite'a gönderilir -->
  <storage_configuration>
    <disks>
      <backups>
        <type>local</type>
        <path>/data/clickhouse/backups/</path>
      </backups>
    </disks>
  </storage_configuration>
  <backups>
    <allowed_disk>backups</allowed_disk>
  </backups>
</clickhouse>
```

**`/etc/clickhouse-server/users.d/teqlif.xml` — kullanıcı tanımları + bellek sınırı:**
```xml
<clickhouse>
  <!-- default user: şifreli, sadece localhost, backup erişimi yok -->
  <users>
    <default>
      <password_sha256_hex><default_user_sha256></password_sha256_hex>
      <networks>
        <ip>127.0.0.1</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
    </default>

    <!-- uygulama kullanıcısı: WG ağından erişebilir -->
    <teqlif>
      <password_sha256_hex><teqlif_ch_sha256></password_sha256_hex>
      <networks>
        <ip>127.0.0.1</ip>
        <ip>10.10.0.0/24</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
      <allow_databases>
        <database>teqlif</database>
      </allow_databases>
    </teqlif>
  </users>

  <!-- Bellek sınırı — node9: 31 GB RAM, ClickHouse + Prometheus + Loki paylaşımlı -->
  <!-- ClickHouse: 12 GB | Prometheus: 4 GB | Loki: 6 GB | OS+diğer: ~9 GB -->
  <profiles>
    <default>
      <max_memory_usage>8000000000</max_memory_usage>        <!-- 8 GB tek sorgu limiti -->
      <max_memory_usage_for_all_queries>12000000000</max_memory_usage_for_all_queries>  <!-- 12 GB toplam -->
      <!-- Background merge kısıtı — gece backup ile çakışmasın -->
      <background_pool_size>2</background_pool_size>
      <background_merges_mutations_concurrency_ratio>1</background_merges_mutations_concurrency_ratio>
    </default>
  </profiles>
</clickhouse>
```

```bash
# SHA256 hash üretimi (kurulum sırasında yapılır):
# echo -n "<teqlif_ch_password>" | sha256sum
# Üretilen hash'i teqlif.xml'deki <teqlif_ch_sha256> yerine yaz

# Backup dizini node9'da /data/clickhouse/backups/ altında — bkz. §4.8 ClickHouse konfigürasyonu.
# node9 lokal backup: SSH/rsync veya sudoers gerekmez.

systemctl enable --now clickhouse-server
# Şema oluştur (teqlif kullanıcısıyla):
clickhouse-client --user=teqlif --password=<teqlif_ch_password> \
  < backend/db/clickhouse_schema.sql
# Doğrula:
clickhouse-client --user=teqlif --password=<teqlif_ch_password> \
  --query="SELECT count() FROM system.tables WHERE database='teqlif'"
```

### 4.9 Faz 4 Doğrulama

```bash
# node5
psql -h 127.0.0.1 -p 5432 -U teqlif -d teqlif -c "SELECT version();"
psql -h 127.0.0.1 -p 6432 -U teqlif -d teqlif -c "SELECT 1;"  # PgBouncer
redis-cli -p 6379 -a <pass> ping   # → PONG
redis-cli -p 6380 -a <pass> ping   # → PONG
clickhouse-client --query "SELECT 1"

# VIP üzerinden erişim
psql -h 10.10.0.10 -p 6432 -U teqlif -d teqlif -c "SELECT 1;"
redis-cli -h 10.10.0.11 -p 6379 -a <pass> ping
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ping
```

---

## Faz 5 — Core App (node5 Primary + node6 Standby)

**Önkoşul:** Faz 4 tamamlandı.

### 5.1 Repo ve Python Ortamı — node5

```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r backend/requirements.txt
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

### 5.1.1 Alembic — DB Şema Kurulumu (repo klonlandıktan sonra)

```bash
cd /var/www/teqlif.com/backend
source ../.venv/bin/activate
# ⚠️ PgBouncer (6432) transaction pooling modunda LOCK TABLE desteklemez.
# alembic için doğrudan PostgreSQL portunu (5432) kullan:
DATABASE_URL="postgresql+asyncpg://teqlif:<pass>@10.10.0.10:5432/teqlif" alembic upgrade head
python3 scripts/sync_translations.py
python3 scripts/sync_category_fields.py
```

**Not:** Bu adım repo klonundan (5.1) sonra ve servislerin başlatılmasından (5.3) önce gelir. PostgreSQL (Faz 4) hazır olmalı. Günlük operations teqlif restart sonrası alembic aynı şekilde çalıştırılmalı.

### 5.2 .env.production — node5

Template'den oluştur, gerçek değerleri doldur:

```bash
cp /var/www/teqlif.com/deploy/scale/V2.0/node5/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur: şifre, API key, token vb.
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

### 5.3 Systemd Servisleri — node5

**`/etc/systemd/system/teqlif.service`:**
```ini
[Unit]
Description=Teqlif API
After=network.target postgresql.service redis-core.service pgbouncer.service
Requires=pgbouncer.service redis-core.service
# 5 dakika içinde 10 crash → servis "failed" olur; genişletilmiş pencere crash-loop'u engeller
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.main:app \
  --workers 4 \
  --host 127.0.0.1 \
  --port 8000 \
  --proxy-headers \
  --forwarded-allow-ips 10.10.0.2,10.10.0.9
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:/var/log/teqlif/api/uvicorn.log
StandardError=append:/var/log/teqlif/api/uvicorn-error.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-worker.service`:**
```ini
[Unit]
Description=Teqlif ARQ Worker
After=redis-core.service pgbouncer.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/python3 -m arq app.worker.WorkerSettings
Restart=always
RestartSec=10
LimitNOFILE=65535
StandardOutput=append:/var/log/teqlif/worker/arq.log
StandardError=append:/var/log/teqlif/worker/arq-error.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-worker-critical.service`:** Aynı yapı, `CriticalWorkerSettings`; `StartLimitIntervalSec=300 StartLimitBurst=10` dahil.

**`/etc/systemd/system/teqlif-orchestrator.service`:**
```ini
[Unit]
Description=Teqlif Orchestrator
After=redis-orch.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/python3 -m app.orchestrator.main
Restart=always
RestartSec=5
StandardOutput=append:/var/log/teqlif/orchestrator/orch.log
StandardError=append:/var/log/teqlif/orchestrator/orch-error.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-metrics.service`:**
```ini
[Unit]
Description=Teqlif Edge Metrics Agent
After=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/python3 \
  /var/www/teqlif.com/backend/scripts/edge_metrics_agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif teqlif-worker teqlif-worker-critical \
  teqlif-orchestrator teqlif-metrics
```

### 5.3.1 teqlif-ai-proxy — node5 (Son Çare Fallback)

node5 AI proxy'yi **aktif olarak çalıştırmaz**; `teqlif-ai-proxy.service` kurulu ve disabled olarak bekler. Orchestrator node2 + node3 ikisi de down olduğunda bu servisi locally başlatır ve `ai_proxy:active_url=http://10.10.0.5:8001` yazar.

```ini
# /etc/systemd/system/teqlif-ai-proxy.service
[Unit]
Description=Teqlif AI Proxy (Fallback — node5)
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.ai_proxy.main:app \
  --host 10.10.0.5 \
  --port 8001 \
  --workers 1
Restart=always
RestartSec=5
MemoryMax=600M       # node5 memory baskısını sınırla — sadece son çare
MemorySwapMax=200M

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
# Disabled: sadece orchestrator başlatır; manuel ya da boot'ta aktif olmaz
# systemctl enable teqlif-ai-proxy  ← YAPMA; orchestrator yönetir
```

### 5.4 Ops Komutları Kurulumu

```bash
cp /var/www/teqlif.com/scripts/teqlif-restart.sh /usr/local/sbin/teqlif-restart
cp /var/www/teqlif.com/scripts/teqlif-refresh.sh  /usr/local/sbin/teqlif-refresh
chmod 750 /usr/local/sbin/teqlif-restart /usr/local/sbin/teqlif-refresh
```

### 5.5 node6 — Standby App Kurulumu

```bash
# node6'da — node5 ile aynı monorepo + .env (VIP'ler aynı)
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt

cp /var/www/teqlif.com/deploy/scale/V2.0/node6/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**node6 teqlif.service — worker count:** node5'ten 4 → node6 3 core'a sahip; teqlif.service'de `--workers 3` kullan (4 worker CPU oversubscription yaratır):
```bash
# node6'da teqlif.service ExecStart satırını düzelt:
sed -i 's/--workers 4/--workers 3/' /etc/systemd/system/teqlif.service
systemctl daemon-reload
```

**node6'da teqlif/worker/orchestrator servisleri:** Kurulu ama **disabled + stopped** — Keepalived VIP geçişinde `notify_master` scriptiyle aktif olur.

```bash
systemctl disable teqlif teqlif-worker teqlif-worker-critical
# teqlif-guardian tüm node'larda her zaman aktif — standby'da da çalışır (agent görevini yapar)
# keepalived aktif kalır; pgbouncer standby'da disabled — VIP geçişinde notify_master başlatır:
systemctl enable --now teqlif-guardian keepalived redis-core redis-orch redis-guardian
systemctl disable pgbouncer   # standby'da PgBouncer çalışmaz; failover sonrası notify_master tetikler
```

### 5.6 Failover Testi

`wg_vip_failover.sh MASTER` (node6'daki callback) PG promote, Redis promote, PgBouncer start ve teqlif servis başlatmayı otomatik yapar. Test yalnızca tetikleyici + doğrulama adımlarından oluşur.

```bash
# 1. node5'te keepalived durdur (simülasyon — notify_master node6'da tetiklenir, ~15-30s):
sudo systemctl stop keepalived

# 2. node6'da — otomatik çalışan adımları doğrula:

# VIP geçişi (~3s):
ip addr show wg0 | grep "10.10.0.10\|10.10.0.11"
# → her iki VIP node6'nın wg0'ında görünmeli

# WireGuard routing (notify_master step 1):
wg show wg0 | grep -A2 "peer"
# node5 peer → allowed-ips: 10.10.0.5/32  (VIP'ler kalkmış)
# Herhangi bir edge node'da (örn. gateway1):
ssh 10.10.0.2 "wg show wg0 | grep -A2 peer"
# node6 peer'ında 10.10.0.10/32 ve 10.10.0.11/32 görünmeli

# PostgreSQL promote (notify_master step 4):
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"
# → f (primary)

# Redis primary (notify_master step 3):
redis-cli -h 127.0.0.1 -p 6379 -a <pass> info replication | grep role
# → role:master

# PgBouncer + uygulama (notify_master step 5-6):
systemctl is-active pgbouncer teqlif teqlif-worker teqlif-worker-critical teqlif-orchestrator
# → hepsi active

# Health check:
curl -s http://127.0.0.1:8000/health | jq .  # → {"status":"ok"}
```

- [ ] Başarılı → failback prosedürü §5.6.1 adımlarıyla test et

### 5.6.1 Failback Prosedürü (node5 geri gelince)

node5 restore edildiğinde doğrudan primary olamaz — veri uyuşmazlığı vardır. `nopreempt` ile failback tamamen manüel kontrol altındadır; keepalived otomatik preempt etmez.

**ADIM 1 — node5'te keepalived durdur/disable et (sync öncesi zorunlu):**
```bash
# node5'te — ÖNCE yapılmalı: aksi hâlde PostgreSQL sync tamamlanmadan MASTER olur
systemctl stop keepalived
systemctl disable keepalived   # reboot'ta otomatik başlamasın; failback sonunda re-enable et
```

**ADIM 2 — node5'i PostgreSQL replica olarak node6'ya bağla:**
```bash
# node5'te:
systemctl stop postgresql

# pg_rewind dener (daha hızlı — ortak timeline checkpoint varsa):
su - postgres -c "pg_rewind \
  --target-pgdata=/var/lib/postgresql/17/main \
  --source-server='host=10.10.0.7 user=replicator password=<pass>'"

# pg_rewind başarısız olursa (örn. WAL uçtu): pg_basebackup ile taze başla
# su - postgres -c "rm -rf /var/lib/postgresql/17/main && \
#   pg_basebackup -h 10.10.0.7 -U replicator \
#   -D /var/lib/postgresql/17/main -Xs -P -R"

# standby.signal ve primary_conninfo kontrol — node6 IP'sini göstermeli:
cat /var/lib/postgresql/17/main/standby.signal
cat /var/lib/postgresql/17/main/postgresql.auto.conf
# primary_conninfo = 'host=10.10.0.7 ...'

systemctl start postgresql
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();"  # → t
```

**ADIM 3 — Replay lag sıfırlanana kadar bekle:**
```bash
# node6'da:
psql -h 127.0.0.1 -U postgres -c \
  "SELECT write_lag, flush_lag, replay_lag \
   FROM pg_stat_replication WHERE application_name='walreceiver';"
# → tüm lag sütunları NULL veya ~0
```

**ADIM 4 — node6'da servisleri durdur ve keepalived'ı kapat:**
```bash
# node6'da:
systemctl stop teqlif teqlif-worker teqlif-worker-critical \
  teqlif-orchestrator pgbouncer 2>/dev/null || true
# keepalived durdur → notify_backup tetiklenir:
#   WG routing VIP'leri node5'e yönlendirir, Redis replicaof eklenir
# node5 artık tek VRRP instance → otomatik MASTER olur → wg_vip_node5.sh MASTER tetiklenir
systemctl stop keepalived
```

**ADIM 5 — node5 keepalived başlat (MASTER olur):**
```bash
# node5'te:
systemctl enable keepalived
systemctl start keepalived
# wg_vip_node5.sh MASTER otomatik çalışır:
#   PostgreSQL promote (recovery'deyse) + PgBouncer enable+start + teqlif servisler start

# Doğrula:
ip addr show wg0 | grep "10.10.0.10\|10.10.0.11"               # VIP'ler node5'te
psql -h 127.0.0.1 -U postgres -c "SELECT pg_is_in_recovery();" # → f (primary)
curl -s http://127.0.0.1:8000/health | jq .                     # → {"status":"ok"}
```

**ADIM 6 — node6'yı BACKUP olarak hazırla:**
```bash
# node6'da — node5'in replikasyon bağlantısına izin ver:
echo "host replication replicator 10.10.0.5/32 scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
systemctl reload postgresql
# node6 keepalived'ı yeniden etkinleştir (BACKUP modunda bekler):
systemctl enable --now keepalived
```

### 5.6.2 Failover Sırasında Ulaşılamayan Node'ların WG Routing Düzeltmesi

`wg_vip_failover.sh` SSH loop'u `|| true` ile çalışır — geçici olarak down olan node atlanır. Uygulama servis kesmeden korunur; ancak node ayağa kalktığında WG routing'i eski primary'yı göstermeye devam eder.

**Kontrol (failover sonrası, node6 MASTER olduğunda):**
```bash
# node6'dan — tüm non-core node'larda VIP routing'i doğrula:
# Beklenen: NODE6_PUBKEY'in allowed-ips'inde 10.10.0.10 VE 10.10.0.11 var olmalı
NODE6_PUBKEY=$(wg show wg0 | awk '/public key/{print $3; exit}')
for WG_IP in 10.10.0.2 10.10.0.9 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.8 10.10.0.12 10.10.0.13; do
  printf "=== %s === " "${WG_IP}"
  ssh -o ConnectTimeout=5 -o BatchMode=yes \
      -i /home/tucibeyin/.ssh/id_ed25519_failover \
      tucibeyin@${WG_IP} \
      "wg show wg0 | grep -A3 '${NODE6_PUBKEY}' | grep allowed-ips" 2>/dev/null \
    || echo "ULAŞILAMADI veya routing eksik"
done
# Sağlıklı satır: allowed-ips: 10.10.0.7/32, 10.10.0.10/32, 10.10.0.11/32
```

**Stale veya ulaşılamayan node varsa manuel düzelt:**
```bash
# Eksik node'a SSH at (WG zaten bağlıysa WG IP'siyle, değilse public IP'siyle):
STALE_NODE_IP="<node_wg_ip>"

# failover.env'deki pubkey'leri node6'dan oku:
source /etc/keepalived/secrets/failover.env
NODE5_PUBKEY="${NODE5_PUBKEY}"   # node5 = artık standby
NODE6_PUBKEY="${NODE6_PUBKEY}"   # node6 = artık primary (VIP sahibi)

ssh -i /home/tucibeyin/.ssh/id_ed25519_failover tucibeyin@${STALE_NODE_IP} "
  sudo wg set wg0 peer ${NODE6_PUBKEY} allowed-ips 10.10.0.7/32,10.10.0.10/32,10.10.0.11/32 &&
  sudo wg set wg0 peer ${NODE5_PUBKEY} allowed-ips 10.10.0.5/32 &&
  sudo wg-quick save wg0
"
# Doğrula:
ssh tucibeyin@${STALE_NODE_IP} "wg show wg0 | grep -A3 '${NODE6_PUBKEY}'"
```

> **Not:** Düzeltme idempotenttir — aynı komut birden fazla çalıştırılabilir, sonuç değişmez. `wg set` live, `wg-quick save` kalıcı hale getirir.

### 5.7 Faz 5 Doğrulama

```bash
# node5
systemctl status teqlif teqlif-worker teqlif-worker-critical \
  teqlif-orchestrator teqlif-metrics
curl -s http://127.0.0.1:8000/health | jq .
```

---

## Faz 6 — Storage (node7 + node8)

**Önkoşul:** Faz 3 tamamlandı. (Faz 4+5 ile paralel yapılabilir.)

### 6.1 HDD Formatı ve Mount — Her İki Node

```bash
# Mevcut disk yapısını kontrol et:
lsblk
# HDD'yi belirle (genellikle /dev/sdb veya /dev/vdb)

# Format:
mkfs.xfs -L teqlif-data /dev/sdb

# Mount noktası:
mkdir -p /mnt/data

# /etc/fstab'a ekle (largeio+allocsize: büyük obje yazma throughput; inode64: 1TB+ fs üzerinde inode dağıtımı):
echo "LABEL=teqlif-data /mnt/data xfs defaults,noatime,largeio,inode64,allocsize=64m 0 2" >> /etc/fstab
mount -a

# MinIO dizini:
mkdir -p /mnt/data/minio
chown tucibeyin:tucibeyin /mnt/data/minio
chmod 700 /mnt/data/minio
```

**`noatime`:** HDD'de her okumada inode güncellenmesini engeller — performans için kritik.

### 6.2 MinIO Kurulumu

```bash
# MinIO binary indir (GitHub releases — dl.min.io kullanma, 410 döner):
# Pinned release — latest yerine belirli bir sürüm kullan (asset adı: minio.linux-amd64.RELEASE.YYYY-...Z):
MINIO_RELEASE="RELEASE.2024-11-07T00-52-20Z"   # kurulum sırasında https://github.com/minio/minio/releases adresinden son kararlı sürümü kontrol et
curl -fsSL "https://github.com/minio/minio/releases/download/${MINIO_RELEASE}/minio.linux-amd64.${MINIO_RELEASE}" \
  -o /usr/local/bin/minio
chmod +x /usr/local/bin/minio
/usr/local/bin/minio --version   # doğrula
```

### 6.3 node7 — MinIO Servisi

```bash
# Template'den oluştur — içerik Faz 0.5'te tanımlı (ORCH_REDIS_URL, EDGE_NODE_ID, MINIO_VOLUMES vb.):
cp /var/www/teqlif.com/deploy/scale/V2.0/node7/resources/.env.production.template \
   /etc/teqlif/.env.production
# Gerçek değerleri doldur: MINIO_ROOT_USER, MINIO_ROOT_PASSWORD vb.
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/systemd/system/minio.service`:**
```ini
[Unit]
Description=MinIO Object Storage
After=network.target
AssertFileIsExecutable=/usr/local/bin/minio

[Service]
User=tucibeyin
Group=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
Environment=GOMEMLIMIT=2GiB
Environment=GOGC=100
Environment=MINIO_API_REQUESTS_MAX=200
Environment=MINIO_API_REQUESTS_DEADLINE=30s
ExecStart=/usr/local/bin/minio server ${MINIO_VOLUMES} \
  --address "0.0.0.0:9000" \
  --console-address "127.0.0.1:9001"
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:/var/log/teqlif/minio/minio.log
StandardError=append:/var/log/teqlif/minio/minio-error.log

[Install]
WantedBy=multi-user.target
```

```bash
mkdir -p /var/log/teqlif/minio
systemctl enable --now minio
```

**Bucket oluşturma (node7 üzerinde, mc ile):**
```bash
mc alias set local http://127.0.0.1:9000 <user> <pass>
mc mb local/teqlif
mc mb local/teqlif-dm
mc anonymous set download local/teqlif  # public-read
# ILM (lifecycle) politikaları:
mc ilm add --expiry-days 120 local/teqlif    # listing media 120 gün
mc ilm add --expiry-days 60  local/teqlif-dm # DM media 60 gün
```

**Versioning ve ILM — node5'te mc ile (her iki node'a, minio7/minio8 alias'ları Faz 6.9'da tanımlanır):**
```bash
# Node7 — versioning etkinleştir:
mc version enable minio7/teqlif
mc version enable minio7/teqlif-dm
# Node8 — versioning etkinleştir:
mc version enable minio8/teqlif
mc version enable minio8/teqlif-dm

# Eski sürümler 90 günde silinsin (disk tasarrufu):
mc ilm rule add --noncurrent-expire-days 90 minio7/teqlif
mc ilm rule add --noncurrent-expire-days 90 minio7/teqlif-dm
mc ilm rule add --noncurrent-expire-days 90 minio8/teqlif
mc ilm rule add --noncurrent-expire-days 90 minio8/teqlif-dm

# Doğrula:
mc version info minio7/teqlif   # → Versioning: enabled
mc version info minio8/teqlif   # → Versioning: enabled
```

**Not:** Bu adım Faz 6.9 mc alias kurulumundan (minio7/minio8 alias'ları) sonra çalıştırılır.

### 6.4 node7 — nginx (S3 Proxy)

```bash
apt-get install -y nginx

# nginx process crash sonrası otomatik kurtarma:
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
systemctl daemon-reload

# nginx SSD cache dizini (root disk /dev/vda3 — 10GB SSD, 1GB cache ayrıl):
mkdir -p /var/cache/nginx/storage
chown www-data:www-data /var/cache/nginx/storage
```

**`/etc/nginx/nginx.conf` — http bloğuna cache zone ekle:**
```nginx
# Proxy cache: SSD üzerinde (root disk) — HDD'ye gitmeden hot dosyaları yakalar
proxy_cache_path /var/cache/nginx/storage
    levels=1:2
    keys_zone=storage_cache:10m
    max_size=1g
    inactive=7d
    use_temp_path=off;
```

**`/etc/nginx/conf.d/minio.conf`:**
```nginx
# Bağlantı limiti zone — uploads.teqlif.com DNS Only, doğrudan istemci erişimi
limit_conn_zone $binary_remote_addr zone=storage_conn:10m;
limit_req_zone  $binary_remote_addr zone=storage_req:10m rate=30r/s;

server {
    listen 80;
    server_name uploads.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name uploads.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    client_max_body_size 100m;
    proxy_read_timeout 300s;
    proxy_buffering off;

    # Bağlantı + istek limiti (DNS Only — doğrudan flood riski)
    limit_conn storage_conn 20;
    limit_req  zone=storage_req burst=60 nodelay;

    # GET isteklerini SSD'ye cache'le — HDD yükünü azaltır
    proxy_cache storage_cache;
    proxy_cache_valid 200 30d;
    proxy_cache_methods GET HEAD;
    proxy_cache_use_stale error timeout updating;
    proxy_cache_lock on;
    proxy_cache_background_update on;
    # proxy_cache_methods GET HEAD: PUT/POST/DELETE zaten cache'lenmez — bypass satırı gereksiz
    # (proxy_cache_bypass $request_method HATALI: "GET" her zaman truthy → cache hiç çalışmaz)
    add_header X-Cache-Status $upstream_cache_status;
    add_header Cache-Control "public, max-age=2592000, immutable";

    # node7 önce dener; dosya yoksa (404) VEYA MinIO down ise (502/503) node8'e düşer:
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        error_page 404 502 503 504 = @fallback_node8;
    }

    location @fallback_node8 {
        proxy_pass http://10.10.0.12:9000;  # node8 WireGuard IP
        proxy_set_header Host $host;
        # fallback yanıtlarını cache'leme (eksik nesne olabilir)
        proxy_cache_bypass 1;
        proxy_no_cache 1;
    }
}
```

**Not:** `proxy_cache_methods GET HEAD` — yalnızca GET/HEAD yanıtları cache'lenir; PUT/POST/DELETE nginx tarafından hiç cache'lenmez. `immutable` direktifi: aynı URL hiçbir zaman değişmez (MinIO object key değişmez, içerik değişince key değişir).

**Cloudflare Origin Certificate:**
```bash
mkdir -p /etc/ssl/teqlif
chmod 700 /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir → kopyala:
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

### 6.5 node8 — MinIO Servisi

node7 ile birebir aynı config; `.env.production`'da yalnızca `EDGE_NODE_ID=node8` farklı.

**`minio.service`:** node7 ile özdeş — aynı `GOMEMLIMIT=2GiB`, `GOGC=100`, `MINIO_API_REQUESTS_MAX=200`.

**Bucket oluşturma:** node7 ile aynı adımlar — dual-write ile her ikisine aynı içerik yazılacak.

### 6.6 node8 — nginx (S3 Proxy + 404 Fallback)

node7 ile aynı kurulum adımları (`apt-get install -y nginx`, cache dizini, nginx.conf proxy_cache_path bloğu).

**`/etc/nginx/conf.d/minio.conf`:** node7 ile aynı; yalnızca `proxy_pass` fallback hedefi `node7 → node8` yerine `node8 → node7`:

```nginx
limit_conn_zone $binary_remote_addr zone=storage_conn:10m;
limit_req_zone  $binary_remote_addr zone=storage_req:10m rate=30r/s;

server {
    listen 80;
    server_name uploads.teqlif.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name uploads.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    server_tokens       off;

    client_max_body_size 100m;
    proxy_read_timeout 300s;
    proxy_buffering off;

    limit_conn storage_conn 20;
    limit_req  zone=storage_req burst=60 nodelay;

    proxy_cache storage_cache;
    proxy_cache_valid 200 30d;
    proxy_cache_methods GET HEAD;
    proxy_cache_use_stale error timeout updating;
    proxy_cache_lock on;
    proxy_cache_background_update on;
    # proxy_cache_methods GET HEAD: PUT/POST/DELETE zaten cache'lenmez — bypass satırı gereksiz
    add_header X-Cache-Status $upstream_cache_status;
    add_header Cache-Control "public, max-age=2592000, immutable";

    # node8 önce dener; dosya yoksa (404) VEYA MinIO down ise (502/503) node7'ye düşer:
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        error_page 404 502 503 504 = @fallback_node7;
    }

    location @fallback_node7 {
        proxy_pass http://10.10.0.8:9000;   # node7 WireGuard IP
        proxy_set_header Host $host;
        proxy_cache_bypass 1;
        proxy_no_cache 1;
    }
}
```

### 6.7 edge_metrics_agent — node7 + node8

```bash
# Monorepo klon (tüm node'larda aynı):
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
# Storage node — yalnızca metrics agent için minimal venv:
python3 -m venv .venv
.venv/bin/pip install psutil redis
chown -R tucibeyin:tucibeyin /var/www/teqlif.com
```

**`/etc/systemd/system/teqlif-metrics.service`:** node5 ile aynı yapı; `EnvironmentFile=/etc/teqlif/.env.production`, `EDGE_NODE_ID` doğru set edilmeli. `.env.production` Faz 6.3'te oluşturuldu.

### 6.8 Cloudflare DNS — Storage

- [ ] `uploads.teqlif.com` → A → node7 public IP (DNS Only)
- [ ] `uploads.teqlif.com` → A → node8 public IP (DNS Only) ← Yeni
- [ ] `media.teqlif.com`   → A → node7 public IP (Proxied)
- [ ] `media.teqlif.com`   → A → node8 public IP (Proxied) ← Yeni

### 6.9 Storage Senkronizasyon Servisi (node7 ↔ node8)

**Sorun:** Dual-write sırasında bir node down olursa, o node eksik dosyayla geri gelir. Bu dosyaların tamamlanması gerekir.

**Çözüm:** `mc mirror` ile her gece 02:00'de çift yönlü senkronizasyon. `mc mirror` yalnızca eksik objeleri kopyalar — mevcut objelere dokunmaz, ETag kontrolü yapar.

**MinIO Client (`mc`) kurulumu — node5'te (orchestrator ile aynı node):**
```bash
MINIO_RELEASE="RELEASE.2024-11-07T00-52-20Z"   # minio binary ile aynı sürümden mc al
curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MINIO_RELEASE}" \
  -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# node7 ve node8'e alias ekle (WireGuard üzerinden):
mc alias set minio7 http://10.10.0.8:9000  <minio_user> <minio_pass>
mc alias set minio8 http://10.10.0.12:9000 <minio_user> <minio_pass>

# Test:
mc admin info minio7
mc admin info minio8
```

**`/var/www/teqlif.com/backend/scripts/storage_sync.sh`:**
```bash
#!/bin/bash
# Çift yönlü storage senkronizasyonu.
# Her iki node da tam senkronize olana kadar dosyalar tamamlanır.
# Orchestratör sağlıklı gördüğü node'ları bu script'ten bağımsız olarak belirler.

set -e
LOGFILE="/var/log/teqlif/storage_sync.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) storage_sync: start"

# node7 → node8: node8'de eksik olanları doldur
mc mirror --preserve --overwrite=false minio7/teqlif    minio8/teqlif
mc mirror --preserve --overwrite=false minio7/teqlif-dm minio8/teqlif-dm

# node8 → node7: node7'de eksik olanları doldur
mc mirror --preserve --overwrite=false minio8/teqlif    minio7/teqlif
mc mirror --preserve --overwrite=false minio8/teqlif-dm minio7/teqlif-dm

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) storage_sync: done"
```

```bash
chmod 750 /var/www/teqlif.com/backend/scripts/storage_sync.sh
```

**`/etc/systemd/system/teqlif-storage-sync.service`:**
```ini
[Unit]
Description=Teqlif Storage Sync (node7 ↔ node8)
After=network.target

[Service]
User=tucibeyin
ExecStart=/var/www/teqlif.com/backend/scripts/storage_sync.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/storage_sync.log
StandardError=append:/var/log/teqlif/storage_sync.log
```

**`/etc/systemd/system/teqlif-storage-sync.timer`:**
```ini
[Unit]
Description=Nightly storage sync timer

[Timer]
OnCalendar=*-*-* 02:00:00 UTC
RandomizedDelaySec=300   # 300s jitter — iki node aynı anda farklı işler yapmasın
Persistent=true          # node5 gece kapalıysa, açılınca kaçırılan sync çalışır

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif-storage-sync.timer
# Doğrula:
systemctl list-timers teqlif-storage-sync.timer
# Manuel test (ilk kurulumda):
systemctl start teqlif-storage-sync.service
journalctl -u teqlif-storage-sync.service -n 20
```

**Acil sync (orchestratörden tetikleme):** Orchestratör bir storage node'u sağlıklı olarak işaretlediğinde (`["node7"]` → `["node7","node8"]`), nightly timer (02:00 UTC) en geç 24 saatte eşitlenir.

**Logrotate ekle:**
```bash
cat >> /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/storage_sync.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
}
EOF
```

### 6.10 Faz 6 Doğrulama

```bash
# node7
curl -I http://10.10.0.8:9000/minio/health/live     # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node7  # → Hash alanları

# node8
curl -I http://10.10.0.12:9000/minio/health/live    # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node8  # → Hash alanları

# DNS
dig uploads.teqlif.com +short  # iki IP dönmeli
dig media.teqlif.com +short    # iki IP dönmeli

# nginx fallback testi — port 9000 (MinIO doğrudan) değil, nginx üzerinden test edilmeli:
# 1. Test objesi oluştur — sadece node7'ye yükle:
mc cp /tmp/test-fallback.txt minio7/teqlif/test-fallback.txt

# 2. node8 nginx üzerinden eriş (port 80) — node8 MinIO'da yok → @fallback_node7 tetiklenmeli:
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: uploads.teqlif.com" http://10.10.0.12:80/teqlif/test-fallback.txt
# → 200 (node8 nginx → node7 MinIO fallback)

# 3. node7 nginx üzerinden aynı mantıkla ters test (node8'e özgü bir obje):
mc cp /tmp/test-fallback2.txt minio8/teqlif/test-fallback2.txt
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: uploads.teqlif.com" http://10.10.0.8:80/teqlif/test-fallback2.txt
# → 200 (node7 nginx → node8 MinIO fallback)

# Sync timer aktif mi?
systemctl is-active teqlif-storage-sync.timer   # → active
```

---

## Faz 7 — Gateway (gateway1 + gateway2)

**Önkoşul:** Faz 3 tamamlandı. (Faz 4+5+6 ile paralel yapılabilir.)

### 7.1 nginx Kurulumu

```bash
apt-get install -y nginx

# nginx process crash sonrası otomatik kurtarma — paket varsayılanı Restart=on-failure, bu yetmez
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=5
EOF
systemctl daemon-reload
```

**`/etc/nginx/nginx.conf` — worker ayarları:**
```nginx
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;

    server_tokens off;

    gzip on;
    gzip_types text/plain application/json application/javascript text/css;
    gzip_min_length 1000;

    # Gerçek client IP (CF proxy arkasında) — limit_req $binary_remote_addr CF IP'si değil gerçek kullanıcı IP'si olsun:
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    set_real_ip_from 103.22.200.0/22;
    set_real_ip_from 103.31.4.0/22;
    set_real_ip_from 141.101.64.0/18;
    set_real_ip_from 108.162.192.0/18;
    set_real_ip_from 190.93.240.0/20;
    set_real_ip_from 188.114.96.0/20;
    set_real_ip_from 197.234.240.0/22;
    set_real_ip_from 198.41.128.0/17;
    set_real_ip_from 162.158.0.0/15;
    set_real_ip_from 104.16.0.0/13;
    set_real_ip_from 104.24.0.0/14;
    set_real_ip_from 172.64.0.0/13;
    set_real_ip_from 131.0.72.0/22;
    real_ip_header CF-Connecting-IP;
    real_ip_recursive on;

    # Rate limiting — http bloğunda tanımlanmalı, server içinde değil:
    limit_req_zone  $binary_remote_addr zone=api_limit:10m rate=30r/s;
    # Bağlantı limiti (connection exhaustion saldırısı engeli):
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # WebSocket upgrade map — Connection header'ı doğru set eder;
    # global "upgrade" ayarı upstream keepalive'ı kırar:
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    include /etc/nginx/conf.d/*.conf;
}
```

**`/etc/nginx/conf.d/teqlif.conf`:**
```nginx
upstream teqlif_core {
    server 10.10.0.5:8000 max_fails=3 fail_timeout=10s;   # node5 (primary)
    server 10.10.0.7:8000 backup max_fails=1 fail_timeout=10s;
    # ↑ node6 standby: node5 down olduğunda nginx buraya geçer.
    # Ancak node6'daki teqlif servisleri failover tamamlanana kadar kapalıdır.
    # Bu pencerede (~15-30s) node6'ya gelen istekler 502 döner — nginx bunu passive olarak öğrenir.
    # Kabul edilebilir: aktif-pasif HA tasarımında sıfır downtime garanti edilmez, kısa kesinti beklenir.
    keepalive 32;
}

server {
    listen 443 ssl;
    server_name api.teqlif.com teqlif.com www.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;  # map üzerinden — WS için upgrade, diğerleri için close

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-For   $http_cf_connecting_ip;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_connect_timeout 5s;
    proxy_read_timeout    300s;

    # Güvenlik headerları (CF proxy arkasında çalışır — HSTS CF seviyesinde de açık olmalı §0.11)
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), microphone=(), camera=()" always;

    # Bağlantı limiti — tek IP'den max 100 eşzamanlı bağlantı
    # CGNAT: mobil operatörlerde birden fazla kullanıcı aynı IP'yi paylaşır; 50 dar kalır
    limit_conn conn_limit 100;

    # WS: /api/messages/ws — daha spesifik eşleşme /api/'dan önce gelir
    # ws_service.dart: wss://api.teqlif.com/api/messages/ws — /ws/ path'i HİÇBİR ZAMAN eşleşmez
    location /api/messages/ws {
        proxy_pass http://teqlif_core;
        proxy_read_timeout 3600s;  # WS — 1 saat; client 25s ping gönderir
        # CGNAT: 20 → aynı IP'den birden fazla kullanıcının WS bağlantısı için yeterli
        limit_conn conn_limit 20;
    }

    location /api/ {
        limit_req zone=api_limit burst=60 nodelay;
        proxy_pass http://teqlif_core;
    }

    location / {
        proxy_pass http://teqlif_core;
    }
}

server {
    listen 80;
    server_name api.teqlif.com teqlif.com www.teqlif.com;
    return 301 https://$host$request_uri;
}
```

### 7.2 Cloudflare Origin Certificate

```bash
mkdir -p /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir (.pem formatı)
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

### 7.3 node_exporter + Promtail

`node_exporter` ve `promtail` **tüm 11 node'da** kurulur. Bu adım ilgili node'un faz kurulumu sırasında yapılır; gateway'ler için burada gösterilmektedir.

#### node_exporter

```bash
# Tüm node'larda (her birinin WG IP'sine göre):
NODE_EXPORTER_VER="1.8.2"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VER}/node_exporter-${NODE_EXPORTER_VER}.linux-amd64.tar.gz" \
  | tar -xz -C /usr/local/bin --strip-components=1 \
    node_exporter-${NODE_EXPORTER_VER}.linux-amd64/node_exporter

# WireGuard IP'ye kilitli systemd unit:
cat > /etc/systemd/system/node-exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=tucibeyin
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address="<NODE_WG_IP>:9100" \
  --collector.systemd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
# <NODE_WG_IP> yerine o node'un WG IP'si:
# gateway1=10.10.0.2, gateway2=10.10.0.9, node1=10.10.0.1, node2=10.10.0.3
# node3=10.10.0.4, node4=10.10.0.6, node5=10.10.0.5, node6=10.10.0.7
# node7=10.10.0.8, node8=10.10.0.12, node9=10.10.0.13

systemctl daemon-reload
systemctl enable --now node-exporter
```

#### Promtail

```bash
# Tüm node'larda — Grafana apt reposu ekle (node9'da Faz 10'da zaten yapılır):
apt-get install -y apt-transport-https software-properties-common
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor \
  | tee /usr/share/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y promtail
```

**`/etc/promtail/config.yml`** — `<NODE_ID>` ve `<NODE_WG_IP>` yerine o node'un değerleri:
```yaml
server:
  http_listen_port: 0   # scraping-only; HTTP endpoint kapalı
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://10.10.0.13:3100/loki/api/v1/push  # node9 Loki

scrape_configs:
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      labels:
        job: journal
        node: <NODE_ID>   # örn. gateway1, node5, node7
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: unit
      - source_labels: [__journal_priority_keyword]
        target_label: level

  - job_name: teqlif_file_logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: teqlif
          node: <NODE_ID>
          __path__: /var/log/teqlif/**   # ** recursive: api/, worker/, orchestrator/ + top-level backup log'ları
```

```bash
mkdir -p /var/lib/promtail

# Promtail systemd override — journal + file log okuma için grup üyeliği:
mkdir -p /etc/systemd/system/promtail.service.d
cat > /etc/systemd/system/promtail.service.d/override.conf << 'EOF'
[Service]
SupplementaryGroups=systemd-journal adm
EOF
# systemd-journal: journal socket okuma yetkisi
# adm: geleneksel /var/log erişim grubu (Debian/Ubuntu)

systemctl daemon-reload
systemctl enable --now promtail
# Doğrula:
journalctl -u promtail -n 20
```

### 7.4 Cloudflare DNS — Gateway

- [ ] `teqlif.com`     → A → gateway1 public IP (Proxied)
- [ ] `teqlif.com`     → A → gateway2 public IP (Proxied) ← Yeni
- [ ] `api.teqlif.com` → A → gateway1 public IP (Proxied)
- [ ] `api.teqlif.com` → A → gateway2 public IP (Proxied) ← Yeni

### 7.5 edge_metrics_agent — gateway1 + gateway2

```bash
# Monorepo klon (tüm node'larda aynı):
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
# Gateway node — yalnızca metrics agent için minimal venv:
python3 -m venv .venv
.venv/bin/pip install psutil redis
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/gateway1/resources/.env.production.template \
   /etc/teqlif/.env.production   # gateway2 için gateway2 template'i
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/systemd/system/teqlif-metrics.service`:** (node5'teki ile aynı yapı; sadece ORCH_REDIS_URL .env'den okunur)

```bash
systemctl enable --now teqlif-metrics

# Doğrula:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:gateway1
# primary_role, net_out_percent, cpu_percent alanları görünmeli
```

### 7.6 Faz 7 Doğrulama

```bash
nginx -t && systemctl reload nginx
curl -I https://api.teqlif.com/health  # → 200
dig api.teqlif.com +short             # iki IP dönmeli
```

---

## Faz 8 — Stream + AI Proxy

**Önkoşul:** Faz 3 tamamlandı. (Faz 4+5 ile paralel yapılabilir.)

### 8.1 LiveKit SFU — node1 ve node4

**Monorepo + venv (node1 ve node4'te aynı adımlar):**
```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install psutil redis   # minimal — sadece teqlif-metrics
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

# node1 için:
cp /var/www/teqlif.com/deploy/scale/V2.0/node1/resources/.env.production.template \
   /etc/teqlif/.env.production
# node4 için: deploy/scale/V2.0/node4/resources/.env.production.template kullan
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**Kurulum:**
```bash
# Pinned release — latest kullanma; https://github.com/livekit/livekit/releases adresinden kontrol et
LIVEKIT_VER="1.8.3"
curl -fsSL "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VER}/livekit_${LIVEKIT_VER}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin/ livekit-server
livekit-server version  # doğrula
```

```bash
mkdir -p /etc/livekit
chmod 700 /etc/livekit
```

**`/etc/livekit/livekit.yaml`:**
```yaml
port: 7880
bind_addresses:
  - ""  # tüm arayüzler
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
  ice_lite: false

turn:
  enabled: true
  domain: live1.teqlif.com  # node4 için: live2.teqlif.com
  tls_port: 5349
  udp_port: 3478
  # external_tls: true KULLANMA — önünde TLS proxy olmadan port 5349 plain TCP dinler ve çalışmaz.
  # CF Origin Cert *.teqlif.com kapsıyor; LiveKit bu cert'i doğrudan kullanır:
  cert_file: /etc/ssl/teqlif/cf-origin.crt
  key_file:  /etc/ssl/teqlif/cf-origin.key

redis:
  address: 10.10.0.11:6379     # Core Redis — kalıcı; Orch Redis (6380) persistence'sız olduğu için uygun değil
  db: 1                        # DB 1 — app DB 0 ile çakışmaz
  password: <core_redis_pass>

keys:
  <livekit_api_key>: <livekit_api_secret>

logging:
  level: info
  json: true
```

**`/etc/systemd/system/livekit.service`:**
```ini
[Unit]
Description=LiveKit SFU
After=network.target

[Service]
User=tucibeyin
ExecStart=/usr/local/bin/livekit-server --config /etc/livekit/livekit.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now livekit teqlif-metrics
```

**Cloudflare DNS:**
- [ ] `live1.teqlif.com` → A → node1 public IP (DNS Only — WebRTC UDP için proxy olmamalı)
- [ ] `live2.teqlif.com` → A → node4 public IP (DNS Only)

### 8.2 AI Proxy — node2

```bash
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/node2/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/systemd/system/teqlif-ai-proxy.service`:**
```ini
[Unit]
Description=Teqlif AI Proxy
After=network.target

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.ai_proxy.main:app \
  --host 10.10.0.3 \
  --port 8001 \
  --workers 1
Restart=always
RestartSec=5
MemoryMax=1200M      # node2: 1.4GB RAM — inference yükünde OOM önlemi
MemorySwapMax=400M

[Install]
WantedBy=multi-user.target
```

### 8.3 edge_metrics_agent — node2

```bash
# node2'de monorepo zaten 8.2'de klonlandı (/var/www/teqlif.com).
# teqlif-metrics.service için ek paket gerekmez — full requirements.txt psutil+redis içerir.
```

**`/etc/teqlif/.env.production` (node2 ek alanları — Faz 0.5'ten template'e eklendi):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node2
NODE_ROLE=ai_proxy
NODE_CAPABILITIES=["ai_proxy"]
INTERFACE_SPEED_MBPS=300
DATA_DISK_PATH=/
```

```bash
systemctl enable --now teqlif-ai-proxy teqlif-metrics
```

### 8.4 Faz 8 Doğrulama

```bash
# node1
curl -s http://10.10.0.1:7880/  # → LiveKit info JSON
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node1  # → Hash alanları

# node2
curl -s http://10.10.0.3:8001/health  # → 200
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node2  # → Hash alanları

# node4
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node4  # → Hash alanları
```

### 8.5 AI Proxy Fallback — node3 (İlk Yedek)

node3 AI proxy'yi **her zaman çalışır** durumda tutar — node2 düştüğünde orchestrator zaten aktif bir süreci hedef alır, başlatma gecikmesi olmaz. node5'ten farklı olarak `enable` edilir.

```bash
# node3'te — monorepo ve venv §10.1'de kurulur; bu adım §10.1 sonrasına yerleştirilmeli
# ama servis dosyasını §8 sırasında ya da §10 içinde kurabilirsin — bağımlılık yok.
```

**`/etc/systemd/system/teqlif-ai-proxy.service` (node3):**
```ini
[Unit]
Description=Teqlif AI Proxy (Fallback — node3)
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.ai_proxy.main:app \
  --host 10.10.0.4 \
  --port 8001 \
  --workers 1
Restart=always
RestartSec=5
MemoryMax=900M       # node3: 3.8GB RAM — monitoring+staging ile paylaşımlı; node2'den (1200M) düşük
MemorySwapMax=300M

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif-ai-proxy
# node3 her zaman çalışır ama ai_proxy:active_url=node2 olduğu sürece trafik almaz
# Orchestrator node2 down → node3'ü hedef alır, ai_proxy:active_url=http://10.10.0.4:8001 yazar
```

**Faz 8.5 Doğrulama:**
```bash
# node3 AI proxy ayakta mı?
curl -s http://10.10.0.4:8001/health  # → 200

# Orchestrator henüz ai_proxy:active_url yazmadıysa default (node2) kullanılır:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url  # → (nil) veya http://10.10.0.3:8001
```

---

## Faz 9 — Orchestrator

**Önkoşul:** Faz 5 (Core App) + Faz 6 (Storage) + Faz 7 (Gateway) + Faz 8 (Stream) tamamlandı.

### 9.1 edge-metrics Doğrulaması

```bash
# Tüm 10 node için metrik var mı?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"
# → edge:metrics:gateway1, gateway2, node1 ... node8 (10 anahtar)

# edge:metrics Hash tipi olmalı (JSON String değil):
redis-cli -h 10.10.0.11 -p 6380 -a <pass> type edge:metrics:node7
# → hash

# node7 ve node8 disk_free_gb doğru mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hget edge:metrics:node7 disk_free_gb
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hget edge:metrics:node8 disk_free_gb

# Tüm alanlar (20+ alan beklenir):
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node7
```

### 9.2 Orchestrator Aktif mi + AI Proxy Routing Doğrulama

```bash
# Orchestrator node5'te çalışıyor mu? (Keepalived MASTER → servis başlamış olmalı)
systemctl is-active teqlif-orchestrator  # → active

# AI proxy: node2 sağlıklıysa key yoktur (uygulama config default'u kullanır) veya node2 URL'si:
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → (nil) veya http://10.10.0.3:8001   (node2 aktif = normal durum)

# node2 edge:metrics TTL var mı? (6s TTL, yoksa node2 down sayılır)
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node2  # → 1-6 arası
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node3  # → 1-6 arası
redis-cli -h 10.10.0.11 -p 6380 -a <pass> ttl edge:metrics:node5  # → 1-6 arası
```

### 9.3 Dual-Write Routing Doğrulama

```bash
# Orchestrator storage_nodes yazıyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7","node8"]  (her ikisi sağlıklı)

# Bir test dosyası yükle (node5 API üzerinden):
curl -X POST http://127.0.0.1:8000/test/upload -F "file=@/tmp/test.jpg"

# Her iki storage node'da dosya var mı?
mc ls local/teqlif/<key>  # node7'de
# node8'de de aynı komut
```

### 9.4 Failover Simülasyonu — Storage

```bash
# node8 MinIO durdur:
ssh node8 "systemctl stop minio"

# Orchestrator fark etmeli (~6s):
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7"]

# DNS güncellemesi (~30s CF TTL sonrası):
dig uploads.teqlif.com +short  # sadece node7 IP görünmeli

# Telegram #ops bildirimi geldi mi?
# node8'i yeniden başlat ve recovery'yi doğrula
ssh node8 "systemctl start minio"
sleep 15
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get orch:best:storage_nodes
# → ["node7","node8"]
```

### 9.5 Failover Simülasyonu — AI Proxy

```bash
# node2 teqlif-ai-proxy durdur (node2 tamamen down gibi davranır):
ssh tucibeyin@10.10.0.3 "sudo systemctl stop teqlif-ai-proxy teqlif-metrics"

# Orchestrator edge:metrics:node2 TTL'si dolar → ~6s içinde node3'e geçiş:
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → http://10.10.0.4:8001  (node3)

# Uygulama AI proxy'yi node3 üzerinden kullanıyor mu?
curl -s http://127.0.0.1:8000/api/test/ai-call  # → 200, AI yanıtı

# node2'yi geri getir ve failback doğrula (otomatik):
ssh tucibeyin@10.10.0.3 "sudo systemctl start teqlif-ai-proxy teqlif-metrics"
sleep 10
redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url
# → http://10.10.0.3:8001  (node2 — otomatik failback)

# node3 + node5 ikisi de down olursa node5 devreye girer:
# systemctl start teqlif-ai-proxy  ← orchestrator node5'te bunu tetikler, sonra URL'yi günceller
```

---

## Faz 10 — Monitoring + Backup + ClickHouse (node9)

**Önkoşul:** Faz 9 tamamlandı.

> **node9 kurulum sırası:** §10.0 → §10.1 → §10.2 → §10.3 → §10.4 → §10.5 → §10.6 → §10.7 doğrulama.
> Faz 1 (OS temeli), Faz 2 (WireGuard), §3.5 (OS tuning) node9 için de uygulanır — §10.0 bu adımları takip eder.

### 10.0 node9 Ön Kurulum (OS + /data + WireGuard)

#### 10.0.1 OS Temeli

Faz 1 adımlarının tamamı node9'da da uygulanır (§1.1'den §1.13'e). node9'a özgü farklar:

```bash
# §1.9 Swap Dosyası — node9: /data üzerinde HDD, büyük swap OK
# Mevcut kurulumda sda4 swap=512MB (OVH partition). İsteğe bağlı olarak genişletilebilir:
# swapoff /dev/md_swap
# mkswap /dev/md_swap  # veya /data altında dosya-based swap
# Şimdilik 512 MB yeterli — node9 prod trafik almaz

# §1.3 Dizin yapısı — node9 ekstra:
mkdir -p /data/clickhouse/{data,tmp,backups,logs}
mkdir -p /data/loki/{chunks,rules,compactor}
mkdir -p /data/prometheus
mkdir -p /opt/teqlif/backups/{postgres/{wal,basebackup,dump},redis,clickhouse,offsite-log}
mkdir -p /opt/teqlif/scripts
mkdir -p /var/log/teqlif

chown clickhouse:clickhouse /data/clickhouse /data/clickhouse/data \
  /data/clickhouse/tmp /data/clickhouse/backups /data/clickhouse/logs
chmod 750 /data/clickhouse /data/clickhouse/data \
  /data/clickhouse/tmp /data/clickhouse/backups

chown loki:loki /data/loki /data/loki/chunks /data/loki/rules /data/loki/compactor
chown prometheus:prometheus /data/prometheus
chown -R tucibeyin:tucibeyin /opt/teqlif /var/log/teqlif
chmod 700 /opt/teqlif/backups
chmod 750 /opt/teqlif/scripts
chmod 755 /var/log/teqlif
```

#### 10.0.2 OS Tuning (node9'a özgü)

§3.5'in node9 bloğu (sysctl + UFW) burada uygulanır.

**Sysctl — node9:**
```bash
cat > /etc/sysctl.d/99-teqlif.conf << 'EOF'
vm.swappiness = 5
fs.file-max = 131072
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.overcommit_memory = 1          # Prometheus + Loki mmap için
# HDD RAID-1: I/O scheduler deadline performansı artırır (blk-mq için mq-deadline)
EOF
sysctl -p /etc/sysctl.d/99-teqlif.conf

# HDD I/O scheduler — her iki disk için
for disk in sda sdb; do
  echo mq-deadline > /sys/block/${disk}/queue/scheduler
  # Persist:
  echo 'ACTION=="add|change", KERNEL=="sd[ab]", ATTR{queue/scheduler}="mq-deadline"' \
    >> /etc/udev/rules.d/99-teqlif-io.rules
done
```

**UFW — node9:**
```bash
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow in on wg0 from 10.10.0.0/24   # mesh: ClickHouse, Prometheus, Loki, Grafana
ufw allow in on wg0 proto udp to any port 9901  # Guardian heartbeat
# Grafana, Prometheus, Loki sadece WG üzerinden — dışarıya AÇILMAZ
ufw --force enable
```

**LimitNOFILE — node9 (ClickHouse + Loki için):**
```bash
# ClickHouse servis override:
mkdir -p /etc/systemd/system/clickhouse-server.service.d
cat > /etc/systemd/system/clickhouse-server.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=262144
EOF
# Loki servis override:
mkdir -p /etc/systemd/system/loki.service.d
cat > /etc/systemd/system/loki.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65536
EOF
systemctl daemon-reload
```

#### 10.0.3 WireGuard — node9

node9 ağ mesh'e dahil edilir. Diğer tüm node'larda node9 peer zaten WG template'e eklendi (§2.2). Burada node9'un kendi wg0.conf'u kurulur ve mesh'e tanıtılır.

**node9 wg0.conf şablonu:**
```ini
# /etc/wireguard/wg0.conf — node9
[Interface]
PrivateKey = <node9_private_key>
Address = 10.10.0.13/24
ListenPort = 51820
MTU = 1420

# gateway1
[Peer]
PublicKey = <gateway1_pubkey>
AllowedIPs = 10.10.0.2/32
Endpoint = <gateway1_public_ip>:51820
PersistentKeepalive = 25

# gateway2
[Peer]
PublicKey = <gateway2_pubkey>
AllowedIPs = 10.10.0.9/32
Endpoint = <gateway2_public_ip>:51820
PersistentKeepalive = 25

# node1
[Peer]
PublicKey = <node1_pubkey>
AllowedIPs = 10.10.0.1/32
Endpoint = <node1_public_ip>:51820
PersistentKeepalive = 25

# node2
[Peer]
PublicKey = <node2_pubkey>
AllowedIPs = 10.10.0.3/32
Endpoint = <node2_public_ip>:51820
PersistentKeepalive = 25

# node3
[Peer]
PublicKey = <node3_pubkey>
AllowedIPs = 10.10.0.4/32
Endpoint = <node3_public_ip>:51820
PersistentKeepalive = 25

# node4
[Peer]
PublicKey = <node4_pubkey>
AllowedIPs = 10.10.0.6/32
Endpoint = <node4_public_ip>:51820
PersistentKeepalive = 25

# node5 — core (VIP'ler dahil)
[Peer]
PublicKey = <node5_pubkey>
AllowedIPs = 10.10.0.5/32,10.10.0.10/32,10.10.0.11/32
Endpoint = <node5_public_ip>:51820
PersistentKeepalive = 25

# node6 — standby (VIP'ler devralabilir)
[Peer]
PublicKey = <node6_pubkey>
AllowedIPs = 10.10.0.7/32
Endpoint = <node6_public_ip>:51820
PersistentKeepalive = 25

# node7
[Peer]
PublicKey = <node7_pubkey>
AllowedIPs = 10.10.0.8/32
Endpoint = <node7_public_ip>:51820
PersistentKeepalive = 25

# node8
[Peer]
PublicKey = <node8_pubkey>
AllowedIPs = 10.10.0.12/32
Endpoint = <node8_public_ip>:51820
PersistentKeepalive = 25
```

```bash
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0

# Mesh doğrulama — tüm node'lara ping:
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 \
          10.10.0.6 10.10.0.7 10.10.0.8 10.10.0.9 10.10.0.12; do
  ping -c1 -W2 "${ip}" > /dev/null && echo "OK: ${ip}" || echo "FAIL: ${ip}"
done
# → Tüm node'lar OK

# Diğer node'larda node9 peer'ı ekle — her node'da çalıştır:
# (§2.2 template'inde zaten var; kurulmamış node'larda wg set ile hot-add:)
# wg set wg0 peer <node9_pubkey> allowed-ips 10.10.0.13/32 \
#   endpoint <node9_public_ip>:51820 persistent-keepalive 25
# wg-quick save wg0
```

#### 10.0.4 node.conf + .env.production

```bash
mkdir -p /etc/teqlif
# node9 node.conf — §1.4'teki node9 şablonu kullan
cat > /etc/teqlif/node.conf << 'EOF'
# (§1.4 node9 node.conf içeriği buraya yapıştırılır)
EOF
chmod 644 /etc/teqlif/node.conf

# .env.production — §0.5 node9 template'i kullan
cp /var/www/teqlif.com/deploy/scale/V2.0/node9/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production

# Doğrula:
python3 -c "import yaml; c=yaml.safe_load(open('/etc/teqlif/node.conf')); print(c['node_id'], c['env'])"
# → node9 production
```

#### 10.0.5 ClickHouse Kurulumu

§4.8'deki tüm komutları bu aşamada çalıştır:
- APT repo ekle + `clickhouse-server clickhouse-client` kur
- `/etc/clickhouse-server/config.d/teqlif.xml` oluştur
- `/etc/clickhouse-server/users.d/teqlif.xml` oluştur
- `systemctl enable --now clickhouse-server`
- Schema'yı yükle: `clickhouse-client ... < backend/db/clickhouse_schema.sql`

```bash
# Doğrula:
clickhouse-client --user=teqlif --password=<pass> \
  --query="SELECT count() FROM system.tables WHERE database='teqlif'"
# → tablo sayısı (0 veya daha fazla)
curl -s "http://10.10.0.13:8123/?query=SELECT+1" --user teqlif:<pass>
# → 1
```

### 10.1 edge_metrics_agent — node9

```bash
# Monorepo klonla — full venv (node9 teqlif-metrics + ClickHouse ikisi de bu venv'i kullanır)
git clone <repo_url> /var/www/teqlif.com
cd /var/www/teqlif.com
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt   # full
chown -R tucibeyin:tucibeyin /var/www/teqlif.com

cp /var/www/teqlif.com/deploy/scale/V2.0/node9/resources/.env.production.template \
   /etc/teqlif/.env.production
chmod 600 /etc/teqlif/.env.production
chown tucibeyin:tucibeyin /etc/teqlif/.env.production
```

**`/etc/teqlif/.env.production` (node9 ek alanları — Faz 0.5'ten template'e eklendi):**
```env
ORCH_REDIS_URL=redis://:<pass>@10.10.0.11:6380/0
EDGE_NODE_ID=node9
NODE_ROLE=monitor
NODE_CAPABILITIES=["monitor","backup","clickhouse"]
INTERFACE_SPEED_MBPS=480
DATA_DISK_PATH=/data
# Backup scriptleri için:
CORE_REDIS_PASS=<core_redis_pass>
PG_PASSWORD=<teqlif_db_password>
REPLICATOR_PASSWORD=<replicator_password>
CLICKHOUSE_HOST=127.0.0.1
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=teqlif
CLICKHOUSE_PASSWORD=<teqlif_ch_password>
TELEGRAM_BOT_TOKEN=<telegram_bot_token>
TELEGRAM_CHAT_ID_OPS=<telegram_chat_id_ops>
```

```bash
systemctl enable --now teqlif-metrics
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node9  # → Hash alanları
```

### 10.2 Prometheus

```bash
apt-get install -y prometheus

# TSDB retention + bellek optimizasyonu (node9: 31GB RAM, Grafana + Loki + ClickHouse ile paylaşımlı):
mkdir -p /etc/systemd/system/prometheus.service.d
cat > /etc/systemd/system/prometheus.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/data \
  --storage.tsdb.retention.time=30d \
  --storage.tsdb.wal-compression \
  --web.enable-lifecycle \
  --storage.tsdb.max-block-duration=2h
EOF
systemctl daemon-reload
```

**`/etc/prometheus/prometheus.yml` — scrape config + alertmanager:**
```yaml
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - '127.0.0.1:9093'   # Alertmanager aynı node'da (node9)

rule_files:
  - /etc/prometheus/alert_rules.yml

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets:
        - '10.10.0.1:9100'   # node1
        - '10.10.0.2:9100'   # gateway1
        - '10.10.0.3:9100'   # node2
        - '10.10.0.4:9100'   # node3
        - '10.10.0.13:9100'  # node9
        - '10.10.0.5:9100'   # node5
        - '10.10.0.6:9100'   # node4
        - '10.10.0.7:9100'   # node6
        - '10.10.0.8:9100'   # node7
        - '10.10.0.9:9100'   # gateway2
        - '10.10.0.12:9100'  # node8
```

**`/etc/prometheus/alert_rules.yml`:**
```yaml
groups:
  - name: teqlif_infra
    rules:
      - alert: NodeDown
        expr: up{job="node_exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          description: "{{ $labels.instance }} erişilemiyor."

      - alert: StorageNodeDown
        expr: up{job="node_exporter", instance=~"10\\.10\\.0\\.(8|12):9100"} == 0
        for: 30s
        labels:
          severity: critical
          channel: ops
        annotations:
          description: "Storage node {{ $labels.instance }} down — dual-write etkilenebilir."

      - alert: Node5HighCPU
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle",instance="10.10.0.5:9100"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "node5 CPU {{ $value | printf \"%.1f\" }}% > 85%"

      - alert: StorageDiskHigh
        expr: (node_filesystem_size_bytes{instance=~"10\\.10\\.0\\.(8|12):9100",mountpoint="/mnt/data"} - node_filesystem_free_bytes{instance=~"10\\.10\\.0\\.(8|12):9100",mountpoint="/mnt/data"}) / node_filesystem_size_bytes{instance=~"10\\.10\\.0\\.(8|12):9100",mountpoint="/mnt/data"} * 100 > 85
        for: 10m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "Storage {{ $labels.instance }} disk doluluk: {{ $value | printf \"%.1f\" }}%"

      - alert: GatewayDown
        expr: up{job="node_exporter", instance=~"10\\.10\\.0\\.(2|9):9100"} == 0
        for: 30s
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "Gateway {{ $labels.instance }} erişilemiyor — trafik tek gateway'e düşüyor."

      # node9 disk: backup + WAL + Loki + ClickHouse verileri /data'yı doldurabilir
      - alert: MonitorDiskHigh
        expr: (node_filesystem_size_bytes{instance="10.10.0.13:9100",mountpoint="/data"} - node_filesystem_free_bytes{instance="10.10.0.13:9100",mountpoint="/data"}) / node_filesystem_size_bytes{instance="10.10.0.13:9100",mountpoint="/data"} * 100 > 80
        for: 10m
        labels:
          severity: warning
          channel: ops
        annotations:
          description: "node9 (monitor/backup) disk doluluk: {{ $value | printf \"%.1f\" }}% — backup ve WAL temizlenmeli."

      # Servis crash loop koruması: "failed" state Prometheus'ta up=0 göstermez,
      # node_systemd_unit_state ile izlenir (node_exporter --collector.systemd gerekir)
      - alert: ServiceFailed
        expr: node_systemd_unit_state{name=~"teqlif.*\\.service",state="failed"} == 1
        for: 1m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "{{ $labels.instance }} — {{ $labels.name }} failed state: StartLimitBurst aşıldı, manuel müdahale gerekli."
```

**postgres_exporter (node5) — replica lag + DB metrikleri:**

node5'te kurulur; node9 Prometheus'u `10.10.0.5:9187`'yi scrape eder (bkz. §10.1 scrape_configs ve alert_rules.yml — aşağıya PostgreSQLReplicaLag kuralı eklendi).

```bash
# node5'te:
PG_EXPORTER_VER="0.15.0"
curl -fsSL "https://github.com/prometheus-community/postgres_exporter/releases/download/v${PG_EXPORTER_VER}/postgres_exporter-${PG_EXPORTER_VER}.linux-amd64.tar.gz" \
  | tar -xz -C /usr/local/bin --strip-components=1 \
    postgres_exporter-${PG_EXPORTER_VER}.linux-amd64/postgres_exporter
```

**`/etc/systemd/system/postgres-exporter.service`:**
```ini
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/usr/local/bin/postgres_exporter \
  --web.listen-address="10.10.0.5:9187"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

> `DATA_SOURCE_NAME` `.env.production` içinde tanımlanır (aşağıya bakın). `Environment=` satırında parola olmasın — `systemctl show` çıktısında görünür.

```bash
systemctl enable --now postgres-exporter
```

**Prometheus scrape_configs'e ekle** (`/etc/prometheus/prometheus.yml`, node9):
```yaml
  - job_name: 'postgres'
    static_configs:
      - targets:
          - '10.10.0.5:9187'   # node5 postgres_exporter
```

**alert_rules.yml'e ekle:**
```yaml
      - alert: PostgreSQLReplicaLag
        expr: pg_stat_replication_pg_wal_lsn_diff{application_name="walreceiver"} > 10485760
        for: 1m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "PostgreSQL replica lag {{ $value | humanize1024 }}B > 10MB (~10s)"

      - alert: PostgreSQLStandbyMissing
        expr: absent(pg_stat_replication_pg_wal_lsn_diff{application_name="walreceiver"})
        for: 2m
        labels:
          severity: critical
          channel: alerts
        annotations:
          description: "node6 standby replikasyona bağlı değil — HA koruması yok."
```

```bash
# node9'da Prometheus'u reload et:
curl -s -X POST http://127.0.0.1:9090/-/reload
```

### 10.3 Grafana

```bash
# Grafana apt reposu — promtail ve loki da bu repo üzerinden kurulur (bkz. §7.3):
apt-get install -y apt-transport-https software-properties-common
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor \
  | tee /usr/share/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  | tee /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana
# Sadece WireGuard üzerinden erişilir:
sed -i 's/;http_addr =/http_addr = 10.10.0.13/' /etc/grafana/grafana.ini
systemctl enable --now grafana-server
```

Panel: CPU, RAM, disk (node7/node8 disk%), Redis replication, LiveKit bağlantı sayısı.

**Grafana Data Sources (UI üzerinden):**
- Prometheus: `http://127.0.0.1:9090`
- Loki: `http://127.0.0.1:3100`

### 10.4 Loki + Promtail (node9)

#### Loki — node9'da kurulum

```bash
# Grafana reposu Faz 10.2'de eklendi; buradan devam:
apt-get install -y loki
mkdir -p /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
chown -R loki:loki /var/lib/loki
```

**`/etc/loki/config.yml`:**
```yaml
auth_enabled: false

server:
  http_listen_address: 10.10.0.13   # WireGuard IP — sadece WG üzerinden erişilir
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h   # 7 gün

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 5m
  retention_enabled: true
  retention_delete_delay: 2h
```

```bash
systemctl enable --now loki
# Doğrula:
curl -s http://10.10.0.13:3100/ready  # → "ready"
```

#### Promtail — node9 dahil tüm node'larda

Tüm node'larda kurulum Faz 7.3'te belgelenmiştir. node9 için ek adım yok — Faz 7.3'teki adımları node9'da da uygula (`<NODE_ID>=node9`).

```bash
# node9'da doğrula:
journalctl -u promtail -n 20
# Loki'ye log geldi mi?
curl -s "http://10.10.0.13:3100/loki/api/v1/query?query=%7Bnode%3D%22node9%22%7D" | python3 -m json.tool
```

### 10.5 Alertmanager → Telegram

**Alert kanal mimarisi:**
| Alert | Kaynak | Kanal |
|-------|--------|-------|
| Node down, gateway down, storage down | Prometheus → Alertmanager | `#alerts` |
| node5 CPU > 85%, disk > 85% | Prometheus → Alertmanager | `#ops` |
| Keepalived VIP geçişi | `wg_vip_failover.sh` → doğrudan Telegram API | `#alerts` |
| Dual-write phase değişimi | Orchestrator backend → doğrudan Telegram API | `#ops` |
| PostgreSQL replica lag / standby kayıp | Prometheus → Alertmanager (postgres_exporter, bkz. §10.1) | `#alerts` |

#### Alertmanager kurulumu (node9)

```bash
apt-get install -y prometheus-alertmanager
```

**`/etc/alertmanager/alertmanager.yml`:**
```yaml
global:
  resolve_timeout: 5m

route:
  group_by: [alertname, instance]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: ops
  routes:
    - match:
        severity: critical
      receiver: alerts
      repeat_interval: 1h

receivers:
  - name: ops
    telegram_configs:
      - bot_token: '<TELEGRAM_BOT_TOKEN>'
        chat_id: <TELEGRAM_CHAT_ID_OPS>       # #ops kanalı chat ID
        parse_mode: Markdown
        message: |-
          *{{ .GroupLabels.alertname }}*
          {{ range .Alerts }}{{ .Annotations.description }}
          {{ end }}

  - name: alerts
    telegram_configs:
      - bot_token: '<TELEGRAM_BOT_TOKEN>'
        chat_id: <TELEGRAM_CHAT_ID_ALERTS>    # #alerts kanalı chat ID
        parse_mode: Markdown
        message: |-
          🚨 *CRITICAL: {{ .GroupLabels.alertname }}*
          {{ range .Alerts }}{{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: [alertname, instance]
```

```bash
systemctl enable --now prometheus-alertmanager
# Prometheus reload (alert_rules.yml eklendi, bkz. §10.1):
curl -s -X POST http://127.0.0.1:9090/-/reload
# Doğrula:
curl -s http://127.0.0.1:9093/#/alerts  # → Alertmanager UI (WG üzerinden)
```

**Keepalived VIP geçişi bildirimi** — `wg_vip_failover.sh` MASTER bloğu adım 8'de tanımlanmıştır (§4.5). `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID_ALERTS` `/etc/keepalived/secrets/failover.env`'den okunur — ayrıca ekleme gerekmez.

### 10.6 Yedekleme (node9)

**node9 disk:** 3.5 TB HDD RAID-1 — monitoring + backup + ClickHouse için yeterli alan. `/data` partition'ı tüm servislerin verisini taşır.

**RPO:** pg_receivewal ile dakika seviyesinde (PITR). pg_dump günlük mantıksal backup.

**Kapsam:**

| Veri | Yöntem | RPO | Öncelik |
|------|--------|-----|---------|
| PostgreSQL | pg_receivewal (sürekli) + pg_basebackup (haftalık) + pg_dump (günlük) | Dakika | Kritik |
| MinIO nesneleri | Bucket versioning (node7+8) + off-site rclone (günlük) | 24 saat | Yüksek |
| Redis Core | RDB günlük rsync (node5→node9) | 24 saat | Orta |
| ClickHouse | Günlük BACKUP komutu + off-site | 24 saat | Orta |
| WireGuard private key | Manuel → password manager | Tek seferlik | Kritik |

#### 10.6.1 Kurulum (node9)

```bash
# PGDG repo (node9'da postgresql-client-17 için — Faz 4.1'deki aynı adımlar):
apt-get install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh

# PostgreSQL client (pg_receivewal, pg_basebackup, pg_dump):
apt-get install -y postgresql-client-17

# rclone (off-site sync):
curl -fsSL https://rclone.org/install.sh | bash

# Dizin yapısı:
mkdir -p /opt/teqlif/backups/{postgres/{wal,basebackup,dump},redis,clickhouse,offsite-log}
mkdir -p /opt/teqlif/scripts
chown -R tucibeyin:tucibeyin /opt/teqlif/backups /opt/teqlif/scripts
chmod 700 /opt/teqlif/backups
chmod 750 /opt/teqlif/scripts
```

**Backup log rotasyonu (node9) — Faz 1.10 logrotate kuralı yalnızca alt dizin log'larını kapsar; backup scriptleri doğrudan `/var/log/teqlif/*.log`'a yazar:**
```bash
cat >> /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/pg_basebackup.log
/var/log/teqlif/pg_dump.log
/var/log/teqlif/redis_backup.log
/var/log/teqlif/clickhouse_backup.log
/var/log/teqlif/offsite_sync.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

**SSH kurulumu — node9→node5 rsync için (redis ve ClickHouse backup):**
```bash
# node9'da:
su - tucibeyin -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' 2>/dev/null || true"
# node9'un public key'ini node5'in authorized_keys'ine ekle (Faz 2 mesh'te yapılabilir):
cat /home/tucibeyin/.ssh/id_ed25519.pub
# → Bu çıktıyı node5'te: echo "<pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
# Test:
ssh -o BatchMode=yes -o StrictHostKeyChecking=no tucibeyin@10.10.0.5 hostname  # → node5 hostname
```

**node6 failover SSH key — §4.5'teki node6 authorized_keys adımı node9 kurulumunda tamamlanır:**
```bash
# node6'dan alınan ~/.ssh/id_ed25519_failover.pub değeri node9'a da eklenmeli:
# node9'da:
echo "<node6_failover_pubkey>" >> /home/tucibeyin/.ssh/authorized_keys
chmod 600 /home/tucibeyin/.ssh/authorized_keys
```

**node6 pg_hba.conf — node9 backup bağlantısı için:**
```bash
# pg_basebackup WAL replication üzerinden pg_hba.conf değişikliklerini yansıtmaz.
# node5'teki §4.1 girişleri node6'ya manuel eklenmeli:
# node6'da:
echo "host  teqlif      teqlif      10.10.0.13/32    scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
echo "host  replication replicator  10.10.0.13/32    scram-sha-256" \
  >> /etc/postgresql/17/main/pg_hba.conf
psql -h 127.0.0.1 -U postgres -c "SELECT pg_reload_conf();"
# Doğrula:
psql -h 127.0.0.1 -U postgres -c "SELECT line_number, rule_type, address FROM pg_hba_file_rules WHERE address = '10.10.0.13/32';"
```

#### 10.6.2 pg_receivewal — Sürekli WAL Arşivleme

pg_receivewal, node9'dan node5'e streaming protokolüyle bağlanır ve WAL segmentlerini gerçek zamanlı çeker. `archive_command` gerektirmez, SSH key gerektirmez.

```bash
# Replikasyon slotu oluştur (node5'te — slot WAL'ın silinmesini engeller):
psql -h 10.10.0.5 -p 5432 -U replicator -c \
  "SELECT pg_create_physical_replication_slot('wal_backup_node9');"
```

**`/etc/systemd/system/teqlif-pg-receivewal.service`:**
```ini
[Unit]
Description=PostgreSQL WAL Receiver (PITR backup)
After=network.target
Wants=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
Environment=PGPASSWORD=${REPLICATOR_PASSWORD}
ExecStart=/usr/lib/postgresql/17/bin/pg_receivewal \
  --host=10.10.0.10 \
  --port=5432 \
  --username=replicator \
  --slot=wal_backup_node9 \
  --directory=/opt/teqlif/backups/postgres/wal \
  --compress=9 \
  --synchronous
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now teqlif-pg-receivewal
# Doğrula:
journalctl -u teqlif-pg-receivewal -n 20
ls /opt/teqlif/backups/postgres/wal/   # → .gz.partial dosyası birikmeye başlar
```

**WAL temizleme (7 günden eski segmentler):**
```bash
cat >> /etc/cron.daily/teqlif-wal-cleanup << 'EOF'
#!/bin/bash
find /opt/teqlif/backups/postgres/wal/ -name "*.gz" -mtime +7 -delete
EOF
chmod +x /etc/cron.daily/teqlif-wal-cleanup
```

> **Failover sonrası WAL gap:** Failover sırasında failover script node6'da yeni `wal_backup_node9` slotu oluşturur; slotun `restart_lsn`'i o andaki node6 LSN'idir. pg_receivewal'ın node5'ten aldığı son WAL ile bu LSN arasındaki segment eksik kalır — PITR arşivinde gap oluşur. Kabul edilebilir bir sınırlıktır ancak **failover sonrasında §10.6.3'ten bir `pg_basebackup` çalıştırarak yeni bir PITR baseline oluşturulmalıdır.** Bu yapılmadan gap öncesine PITR yapılamaz.

#### 10.6.3 pg_basebackup — Haftalık Fiziksel Yedek

Fiziksel backup, PITR'ın başlangıç noktasıdır. pg_receivewal'ın WAL segmentleriyle birlikte kullanılır.

**`/opt/teqlif/scripts/pg_basebackup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/postgres/basebackup"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/pg_basebackup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: start"

export PGPASSWORD="${REPLICATOR_PASSWORD}"   # .env.production'dan — service EnvironmentFile ile yüklenir

# Geçici dizine yaz; hata/kesintide current geçerli kalır — yarım backup promote edilmez
TEMP_DIR="${BACKUP_DIR}/.current_tmp"
rm -rf "${TEMP_DIR}"
cleanup_temp() { rm -rf "${TEMP_DIR}"; }
trap cleanup_temp EXIT

pg_basebackup \
  --host=10.10.0.10 \
  --port=5432 \
  --username=replicator \
  --pgdata="${TEMP_DIR}" \
  --format=tar \
  --gzip \
  --compress=9 \
  --wal-method=none \
  --progress \
  --verbose

# Başarılıysa atomik rename; önceki current'i previous olarak sakla
trap - EXIT
[ -d "${BACKUP_DIR}/current" ] && mv "${BACKUP_DIR}/current" "${BACKUP_DIR}/previous_${DATE}"
mv "${TEMP_DIR}" "${BACKUP_DIR}/current"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_basebackup: OK — $(du -sh ${BACKUP_DIR}/current | cut -f1)"

# Bir haftalıktan eski previous_* dizinlerini sil:
find "${BACKUP_DIR}" -maxdepth 1 -name "previous_*" -mtime +7 -exec rm -rf {} +
```

```bash
chmod 750 /opt/teqlif/scripts/pg_basebackup.sh
```

**`/etc/systemd/system/teqlif-pg-basebackup.service`:**
```ini
[Unit]
Description=Teqlif PostgreSQL Physical Backup
After=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/opt/teqlif/scripts/pg_basebackup.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/pg_basebackup.log
StandardError=append:/var/log/teqlif/pg_basebackup.log
ExecStopPost=/bin/bash -c 'if [ "$$SERVICE_RESULT" != "success" ]; then \
  source /etc/teqlif/.env.production; \
  curl -s -X POST "https://api.telegram.org/bot$${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=$${TELEGRAM_CHAT_ID_OPS}" \
    -d "text=*BACKUP HATASI: pg_basebackup başarısız* (node9)" \
    -d "parse_mode=Markdown" > /dev/null 2>&1; fi'

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-pg-basebackup.timer`:**
```ini
[Unit]
Description=Weekly PostgreSQL physical backup

[Timer]
OnCalendar=Sun *-*-* 01:00:00 UTC
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now teqlif-pg-basebackup.timer
```

#### 10.6.4 pg_dump — Günlük Mantıksal Yedek

Bireysel tablo geri yüklemesi için kullanılır. pg_basebackup'tan bağımsız.

**`/opt/teqlif/scripts/pg_dump.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/postgres/dump"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/pg_dump.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_dump: start"

export PGPASSWORD="${PG_PASSWORD}"   # .env.production'dan — service EnvironmentFile ile yüklenir

# Geçici dosyaya yaz; tamamlanmadan final ismine geçme — kesintide yarım dosya kalmaz
TMPFILE="${BACKUP_DIR}/teqlif_${DATE}.sql.gz.tmp"
cleanup_tmp() { rm -f "${TMPFILE}"; }
trap cleanup_tmp EXIT

pg_dump -h 10.10.0.10 -p 5432 -U teqlif teqlif \
  | gzip -9 > "${TMPFILE}"

trap - EXIT
mv "${TMPFILE}" "${BACKUP_DIR}/teqlif_${DATE}.sql.gz"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_dump: OK — $(du -sh ${BACKUP_DIR}/teqlif_${DATE}.sql.gz | cut -f1)"
find "${BACKUP_DIR}" -name "teqlif_*.sql.gz" -mtime +7 -delete
```

```bash
chmod 750 /opt/teqlif/scripts/pg_dump.sh
```

**`/etc/systemd/system/teqlif-pg-dump.service`:**
```ini
[Unit]
Description=Teqlif PostgreSQL Logical Backup

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/opt/teqlif/scripts/pg_dump.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/pg_dump.log
StandardError=append:/var/log/teqlif/pg_dump.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-pg-dump.timer`:**
```ini
[Unit]
Description=Daily PostgreSQL logical backup

[Timer]
OnCalendar=*-*-* 03:00:00 UTC
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now teqlif-pg-dump.timer
```

#### 10.6.5 PITR Kurtarma Prosedürü

```bash
# Hedef: 2026-10-20 14:35:00 UTC tarihine geri dön

# 1. Yeni node'da (veya node5 sıfırlandıktan sonra) basebackup'ı aç:
mkdir -p /var/lib/postgresql/17/main
cd /var/lib/postgresql/17/main
tar -xzf /opt/teqlif/backups/postgres/basebackup/current/base.tar.gz
# (tablespace tar dosyaları da varsa aç)

# 2. PITR recovery config:
cat > /var/lib/postgresql/17/main/postgresql.conf << 'EOF'
restore_command = 'cp /opt/teqlif/backups/postgres/wal/%f %p'
recovery_target_time = '2026-10-20 14:35:00+00'
recovery_target_action = 'promote'
EOF
touch /var/lib/postgresql/17/main/recovery.signal

# 3. PostgreSQL'i başlat — WAL replay eder, hedef zamana gelince promote eder:
chown -R postgres:postgres /var/lib/postgresql/17/main
systemctl start postgresql
journalctl -u postgresql -f   # "recovery stopping before commit" → promote tamamlandı
```

#### 10.6.6 Redis RDB Yedekleme

Core Redis RDB dosyasını günlük node9'a çeker. Session kaybında kullanıcılar yeniden giriş yapar — düşük öncelikli ama temiz kurulumda yapmak kolay.

`redis-cli --rdb` komutu kullanılır: Redis protokolü üzerinden RDB'yi doğrudan hedef dosyaya yazar. BGSAVE+rsync yaklaşımı kullanılmaz çünkü `/var/lib/redis-core/dump.rdb` dosyası `redis:redis 640`'tır ve tucibeyin dosya sisteminden okuyamaz.

**`/opt/teqlif/scripts/redis_backup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/opt/teqlif/backups/redis"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/redis_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis_backup: start"

# redis-cli --rdb: Redis replikasyon protokolüyle RDB snapshot'ı doğrudan alır.
# Dosya sistemi erişimi gerekmez — /var/lib/redis-core/ izni sorun değil.
# VIP (10.10.0.11) üzerinden bağlanır; failover sonrası node6'da da çalışır.
TMPFILE="${BACKUP_DIR}/core_redis_${DATE}.rdb.tmp"
cleanup_tmp() { rm -f "${TMPFILE}"; }
trap cleanup_tmp EXIT

redis-cli -h 10.10.0.11 -p 6379 -a "${CORE_REDIS_PASS}" \
  --rdb "${TMPFILE}"

trap - EXIT
mv "${TMPFILE}" "${BACKUP_DIR}/core_redis_${DATE}.rdb"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) redis_backup: OK — $(du -sh ${BACKUP_DIR}/core_redis_${DATE}.rdb | cut -f1)"
find "${BACKUP_DIR}" -name "core_redis_*.rdb" -mtime +7 -delete
```

```bash
chmod 750 /opt/teqlif/scripts/redis_backup.sh
```

**`/etc/systemd/system/teqlif-redis-backup.service`:**
```ini
[Unit]
Description=Teqlif Redis RDB Backup
After=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/opt/teqlif/scripts/redis_backup.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/redis_backup.log
StandardError=append:/var/log/teqlif/redis_backup.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-redis-backup.timer`:**
```ini
[Unit]
Description=Daily Redis RDB backup

[Timer]
OnCalendar=*-*-* 03:30:00 UTC
RandomizedDelaySec=120
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now teqlif-redis-backup.timer
```

#### 10.6.7 ClickHouse Yedekleme

**`/opt/teqlif/scripts/clickhouse_backup.sh`:**
```bash
#!/bin/bash
set -euo pipefail
BACKUP_DIR="/data/clickhouse/backups"
DATE=$(date -u +%Y%m%d_%H%M%S)
LOGFILE="/var/log/teqlif/clickhouse_backup.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: start"

# node9: ClickHouse lokal — 127.0.0.1
CH_HOST="127.0.0.1"
CH_PORT="8123"
CH_USER="${CLICKHOUSE_USER}"
CH_PASS="${CLICKHOUSE_PASSWORD}"

# Başarısız/yarım backup'ı temizle — lokal disk şişmesini önle
cleanup_local() {
  rm -rf "${BACKUP_DIR}/ch_backup_${DATE}" 2>/dev/null || true
}
trap cleanup_local EXIT

# ClickHouse BACKUP komutu — lokal /data/clickhouse/backups/ altına yazar
curl -sf "http://${CH_HOST}:${CH_PORT}/?user=${CH_USER}&password=${CH_PASS}&query=BACKUP+DATABASE+teqlif+TO+Disk('backups','ch_backup_${DATE}')" > /dev/null

# Tamamlanana kadar bekle (max 120s):
STATUS="UNKNOWN"
for i in $(seq 1 24); do
  STATUS=$(curl -sf "http://${CH_HOST}:${CH_PORT}/?user=${CH_USER}&password=${CH_PASS}&query=SELECT+status+FROM+system.backups+WHERE+name%3D'ch_backup_${DATE}'+LIMIT+1" || echo "QUERY_ERROR")
  [ "${STATUS}" = "BACKUP_CREATED" ] && break
  sleep 5
done

if [ "${STATUS}" != "BACKUP_CREATED" ]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: HATA — backup tamamlanmadı (status=${STATUS})"
  exit 1   # trap cleanup_local çalışır
fi

trap - EXIT
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) clickhouse_backup: OK — $(du -sh ${BACKUP_DIR}/ch_backup_${DATE} | cut -f1)"
find "${BACKUP_DIR}" -maxdepth 1 -name "ch_backup_*" -mtime +7 -exec rm -rf {} +
```

```bash
chmod 750 /opt/teqlif/scripts/clickhouse_backup.sh
```

**`/etc/systemd/system/teqlif-clickhouse-backup.service`:**
```ini
[Unit]
Description=Teqlif ClickHouse Backup
After=network.target

[Service]
User=tucibeyin
EnvironmentFile=/etc/teqlif/.env.production
ExecStart=/opt/teqlif/scripts/clickhouse_backup.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/clickhouse_backup.log
StandardError=append:/var/log/teqlif/clickhouse_backup.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-clickhouse-backup.timer`:**
```ini
[Unit]
Description=Daily ClickHouse backup

[Timer]
OnCalendar=*-*-* 04:00:00 UTC
RandomizedDelaySec=120
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now teqlif-clickhouse-backup.timer
```

#### 10.6.8 Off-site Yedekleme (rclone)

**rclone remote kurulumu (node3'te — sağlayıcı seçimi serbesttir):**

```bash
# Örnek: Backblaze B2 (S3-compatible, $0.006/GB/ay):
rclone config create b2backup b2 \
  account "<B2_ACCOUNT_ID>" \
  key "<B2_APPLICATION_KEY>"

# Alternatif: Hetzner Storage Box (rsync/SFTP, 100GB = €3.81/ay):
rclone config create hetzner sftp \
  host "<STORAGE_BOX_HOST>.your-storagebox.de" \
  user "<STORAGE_BOX_USER>" \
  pass "<STORAGE_BOX_PASS>"
```

**`/opt/teqlif/scripts/offsite_sync.sh`:**
```bash
#!/bin/bash
set -euo pipefail
REMOTE="b2backup:teqlif-backup"   # Backblaze B2 bucket adı
LOGFILE="/var/log/teqlif/offsite_sync.log"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: start"

# PostgreSQL dump'ları (günlük — 7 gün)
rclone sync /opt/teqlif/backups/postgres/dump/ "${REMOTE}/postgres/dump/" \
  --max-age 7d --log-level INFO

# pg_basebackup (haftalık — 2 kopya)
rclone sync /opt/teqlif/backups/postgres/basebackup/ "${REMOTE}/postgres/basebackup/" \
  --log-level INFO

# WAL segmentleri (son 48 saat — PITR için yeterli off-site pencere)
rclone sync /opt/teqlif/backups/postgres/wal/ "${REMOTE}/postgres/wal/" \
  --max-age 48h --log-level INFO

# Redis RDB (günlük — 7 gün)
rclone sync /opt/teqlif/backups/redis/ "${REMOTE}/redis/" \
  --max-age 7d --log-level INFO

# ClickHouse (günlük — 7 gün)
rclone sync /opt/teqlif/backups/clickhouse/ "${REMOTE}/clickhouse/" \
  --max-age 7d --log-level INFO

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) offsite_sync: OK"
```

```bash
chmod 750 /opt/teqlif/scripts/offsite_sync.sh
```

**`/etc/systemd/system/teqlif-offsite-sync.service`:**
```ini
[Unit]
Description=Teqlif Off-site Backup Sync
After=network.target

[Service]
User=tucibeyin
ExecStart=/opt/teqlif/scripts/offsite_sync.sh
Type=oneshot
StandardOutput=append:/var/log/teqlif/offsite_sync.log
StandardError=append:/var/log/teqlif/offsite_sync.log

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-offsite-sync.timer`:**
```ini
[Unit]
Description=Daily off-site backup sync

[Timer]
OnCalendar=*-*-* 04:30:00 UTC
RandomizedDelaySec=120
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now teqlif-offsite-sync.timer
```

**MinIO off-site (node5'te — rclone ile):**
```bash
# rclone MinIO remote (node5'te):
rclone config create minio_local s3 \
  provider Minio \
  endpoint "http://127.0.0.1:9000" \
  access_key_id "<MINIO_ROOT_USER>" \
  secret_access_key "<MINIO_ROOT_PASSWORD>"

# Haftalık sync (node5'te cron — Pazar 05:00 UTC):
echo "0 5 * * 0 tucibeyin rclone sync minio_local:teqlif b2backup:teqlif-minio-backup --log-file=/var/log/teqlif/minio_offsite.log" \
  >> /etc/cron.d/teqlif-minio-offsite

# node5'te logrotate (Faz 1.10 **/*.log şablonu top-level dosyayı kapsamaz):
cat >> /etc/logrotate.d/teqlif << 'EOF'
/var/log/teqlif/minio_offsite.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

#### 10.6.9 Zamanlayıcı Özeti (node3)

| Saat (UTC) | Timer | İş |
|-----------|-------|-----|
| 02:00 | teqlif-storage-sync | MinIO node7↔node8 senkronizasyon (node5'te çalışır, bkz. Faz 6.9) |
| 03:00 | teqlif-pg-dump | PostgreSQL mantıksal yedek |
| 03:30 | teqlif-redis-backup | Redis RDB rsync |
| 04:00 | teqlif-clickhouse-backup | ClickHouse günlük backup |
| 04:30 | teqlif-offsite-sync | Tüm backup'ları off-site'a gönder |
| Her an | teqlif-pg-receivewal | Sürekli WAL stream (servis, zamanlayıcı değil) |
| Pazar 01:00 | teqlif-pg-basebackup | Haftalık fiziksel backup |
| Pazar 05:00 | minio_offsite (cron, node5) | MinIO off-site sync |

#### 10.6.10 WireGuard Private Key Kurtarma (Manuel — Tek Seferlik)

Her node kurulduktan **hemen sonra**:
```bash
# Her node'da:
wg showconf wg0 | grep PrivateKey
# → PrivateKey = <base64_key>
# Bu değeri password manager'a kaydet: "WireGuard PrivateKey — <node_adı>"
```

Kurtarma (node tamamen bozulursa):
```bash
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key
# 9 node'da o node'a ait peer kaydını yeni public key ile güncelle (Faz 2 wg set adımları)
```

#### 10.6.11 Disaster Recovery Tablosu

| Senaryo | RTO | Prosedür |
|---------|-----|---------|
| node5 geçici down | ~30s | Keepalived otomatik → node6 primary |
| node5 kalıcı arıza | ~2 saat | node6 permanent primary; yeni standby kur |
| node5 + node6 eş zamanlı | ~2 saat | pg_basebackup + WAL replay ile yeni node |
| Tablo/satır silme (DB) | < 5 dakika | PITR: `recovery_target_time` ile dakika hassasiyetli geri dön |
| node7 veya node8 geçici | 0 | nginx fallback → diğer node; nightly sync |
| MinIO nesne yanlış silindi | < 5 dakika | `mc cp --version-id <id>` ile geri yükle |
| Tüm node3 arızası | — | pg_dump + WAL off-site'ta; yeni node'a rclone'dan indir |
| node2 (AI Proxy) tamamen down | ~6s | Orchestrator `edge:metrics:node2` TTL → node3'e otomatik geçiş (`ai_proxy:active_url` güncellenir); kullanıcı bunu fark etmez |
| node2 + node3 (AI Proxy) eş zamanlı down | ~6s | Orchestrator node5'te `teqlif-ai-proxy` başlatır (disabled→enabled), `ai_proxy:active_url=http://10.10.0.5:8001`; node5 MemoryMax=600M kısıtlıdır |
| node1 + node4 eş zamanlı | dakikalar (OS) / manuel (OS arızası) | LiveKit tamamen kesilir — bilinen SPOF; `Restart=always` process crash'i kapatır |
| node7 + node8 eş zamanlı | — | Storage tamamen kesilir — bilinen SPOF; `Restart=always` process crash'i kapatır |
| gateway1 + gateway2 eş zamanlı | — | Tam erişilemezlik — bilinen SPOF; pratik olasılık çok düşük (farklı DC) |
| Servis crash-loop (StartLimitBurst aşıldı) | manuel | Prometheus ServiceFailed alert → `systemctl reset-failed <servis> && systemctl start <servis>` |

### 10.7 Faz 10 Doğrulama

```bash
# Prometheus:
curl -s http://10.10.0.13:9090/api/v1/targets | python3 -c \
  "import sys,json; targets=json.load(sys.stdin)['data']['activeTargets']; \
   [print(t['labels']['instance'], t['health']) for t in targets]"
# → 11 target (node9 dahil), hepsi "up"

# Loki:
curl -s http://10.10.0.13:3100/ready   # → ready

# Alertmanager:
curl -s http://127.0.0.1:9093/-/healthy  # → OK

# pg_receivewal:
systemctl is-active teqlif-pg-receivewal   # → active
ls /opt/teqlif/backups/postgres/wal/       # → .gz.partial dosyası birikmeye başlamış

# Tüm backup timer'ları:
systemctl list-timers "teqlif-pg-*" "teqlif-redis-*" "teqlif-clickhouse-*" "teqlif-offsite-*"
# → hepsi active/waiting

# Manuel pg_dump testi:
systemctl start teqlif-pg-dump.service
ls -lh /opt/teqlif/backups/postgres/dump/   # → dump dosyası

# Off-site bağlantısı:
rclone lsd b2backup:                         # → bucket listesi görünmeli

# MinIO versioning (node5'ten çalıştır — mc orada kurulu, Faz 6.9):
# ssh node5, sonra:
# mc version info minio7/teqlif   # → Versioning: enabled
# mc version info minio8/teqlif   # → Versioning: enabled
```

---

## Faz 11 — Staging (node3)

**Önkoşul:** Faz 10 tamamlandı.

**Tasarım:** node3 standalone staging node'u — tüm bağımlılıklar lokal. Monorepo, venv ve servis tanımları diğer node'larla aynı yapıda; sadece `/etc/teqlif/.env.staging` farklı. node5/node6'ya bağımlılık yok.

### 11.1 PostgreSQL — node3 lokal

```bash
# PGDG repo Faz 10.1'de zaten eklendi
apt-get install -y postgresql-17
systemctl enable --now postgresql

# Sadece lokal bağlantılar
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '127.0.0.1'/" \
  /etc/postgresql/17/main/postgresql.conf
systemctl restart postgresql

# Staging DB + user
sudo -u postgres psql <<'SQL'
CREATE USER teqlif WITH ENCRYPTED PASSWORD '<staging_pg_pass>';
CREATE DATABASE teqlif_staging OWNER teqlif;
SQL

psql -h 127.0.0.1 -U teqlif -d teqlif_staging -c '\conninfo'  # → bağlantı doğrula
```

### 11.2 Redis — node3 lokal

```bash
apt-get install -y redis-server

cat > /etc/redis/redis-staging.conf <<'EOF'
bind 127.0.0.1
port 6379
requirepass <staging_redis_pass>
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly no
save 900 1
save 300 10
EOF

cat > /etc/systemd/system/redis-staging.service <<'EOF'
[Unit]
Description=Redis Staging
After=network.target

[Service]
User=redis
ExecStart=/usr/bin/redis-server /etc/redis/redis-staging.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now redis-staging
redis-cli -h 127.0.0.1 -p 6379 -a <staging_redis_pass> ping  # → PONG
```

### 11.3 Staging App

```bash
# Monorepo zaten /var/www/teqlif.com'da (Faz 10.1'de klonlandı). Ayrı clone YOK.
cp /var/www/teqlif.com/deploy/scale/V2.0/node3/resources/.env.staging.template \
   /etc/teqlif/.env.staging
chmod 600 /etc/teqlif/.env.staging
```

**`/etc/teqlif/.env.staging`:**
```env
# node3 standalone staging — tüm servisler lokal; env değiştirerek başka hedefe taşınabilir
DATABASE_URL=postgresql+asyncpg://teqlif:<staging_pg_pass>@127.0.0.1:5432/teqlif_staging
REDIS_URL=redis://:<staging_redis_pass>@127.0.0.1:6379/1
ORCH_REDIS_URL=redis://:<staging_redis_pass>@127.0.0.1:6379/2
USE_PGBOUNCER=False
MINIO_ENDPOINT=http://10.10.0.8:9000
MINIO_ENDPOINT_DM=http://10.10.0.8:9000
MINIO_BUCKET=teqlif-staging
MINIO_DM_BUCKET=teqlif-dm-staging
UPLOADS_HOST=https://uploads-staging.teqlif.com
MEDIA_HOST=https://media-staging.teqlif.com
```

**Staging DB şeması:**
```bash
cd /var/www/teqlif.com/backend
source ../.venv/bin/activate
DATABASE_URL="postgresql+asyncpg://teqlif:<staging_pg_pass>@127.0.0.1:5432/teqlif_staging" \
  alembic upgrade head
```

**`/etc/systemd/system/teqlif-staging.service`:**
```ini
[Unit]
Description=Teqlif Staging
After=network.target postgresql.service redis-staging.service

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.staging
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.main:app \
  --host 127.0.0.1 \
  --port 8002 \
  --workers 1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/teqlif-worker-staging.service`:**
```ini
[Unit]
Description=Teqlif Worker Staging
After=network.target redis-staging.service

[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/etc/teqlif/.env.staging
ExecStart=/var/www/teqlif.com/.venv/bin/python3 -m arq app.worker.WorkerSettings
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now teqlif-staging teqlif-worker-staging
```

### 11.4 Nginx (staging erişimi — node3)

```bash
apt-get install -y nginx

mkdir -p /etc/ssl/teqlif
chmod 700 /etc/ssl/teqlif
# CF Origin Certificate'i CF panelinden indir → kopyala:
# /etc/ssl/teqlif/cf-origin.crt  (certificate)
# /etc/ssl/teqlif/cf-origin.key  (private key)
chmod 600 /etc/ssl/teqlif/cf-origin.key
```

**`/etc/nginx/sites-available/staging`:**
```nginx
server {
    listen 80;
    server_name staging.teqlif.com;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    server_name staging.teqlif.com;

    ssl_certificate     /etc/ssl/teqlif/cf-origin.crt;
    ssl_certificate_key /etc/ssl/teqlif/cf-origin.key;

    location / {
        proxy_pass http://127.0.0.1:8002;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

```bash
ln -s /etc/nginx/sites-available/staging /etc/nginx/sites-enabled/
nginx -t && systemctl enable --now nginx
```

### 11.5 Faz 11 Doğrulama

```bash
curl -s https://staging.teqlif.com/health  # → 200
psql -h 127.0.0.1 -U teqlif -d teqlif_staging -c '\dt'  # → alembic tabloları
redis-cli -h 127.0.0.1 -p 6379 -a <staging_redis_pass> ping  # → PONG
systemctl is-active teqlif-staging teqlif-worker-staging redis-staging postgresql
```

- [ ] `alembic upgrade head` (staging DB — lokal 127.0.0.1)
- [ ] Servisler: `teqlif-staging`, `teqlif-worker-staging`, `redis-staging`, `postgresql`
- [ ] MinIO staging bucket erişimi: `mc ls minio7/teqlif-staging`

**Cloudflare DNS:**
- [ ] `uploads-staging.teqlif.com` → node3 public IP (DNS Only)
- [ ] `media-staging.teqlif.com`   → node3 public IP (Proxied)
- [ ] `staging.teqlif.com`         → node3 public IP (Proxied)

### 11.6 Entegrasyon Testleri

- [ ] Kullanıcı akışı: kayıt → ilan oluştur → medya yükle → teklif ver → mesajlaş
- [ ] DM medya: upload → `cache_key` alanı mevcut → mobile cache doğru çalışıyor
- [ ] WebSocket bağlantısı + KeepAlive döngüsü
- [ ] Push notification (Firebase test token)
- [ ] OTA çeviri güncelleme
- [ ] Storage dual-write routing simülasyonu
- [ ] Keepalived failover staging'de tekrar

---

## Faz 12 — Prodüksiyon + Mobile

**Önkoşul:** Faz 11 tamamlandı, tüm testler geçiyor.

### 12.1 Son Kontrol Listesi

- [ ] CF DNS: `teqlif.com` + `api.teqlif.com` → iki A record aktif (gateway1 + gateway2)
- [ ] CF DNS: `uploads.teqlif.com` + `media.teqlif.com` → iki A record (node7 + node8)
- [ ] node5: teqlif + teqlif-worker + teqlif-worker-critical + teqlif-orchestrator → active
- [ ] `orch:best:storage_nodes = ["node7","node8"]` doğrula
- [ ] node6: keepalived active; teqlif/worker disabled; teqlif-metrics active
- [ ] node7 + node8: minio + teqlif-metrics → active
- [ ] Monitoring: tüm node'lar Prometheus'ta görünüyor (`curl -s http://10.10.0.13:9090/api/v1/targets | python3 -m json.tool`)
- [ ] Loki: tüm node'lardan log akıyor (`curl -s "http://10.10.0.13:3100/loki/api/v1/labels"` — node label'ları görünmeli)
- [ ] Alertmanager: test alert gönder (`curl -s -X POST http://127.0.0.1:9093/api/v1/alerts -d '[{"labels":{"alertname":"Test"}}]'`)
- [ ] Dual-write: bir medya yükle → her iki storage node'da mc ls ile doğrula
- [ ] MinIO versioning aktif: `mc version info minio7/teqlif` + `minio8/teqlif` → `Versioning: enabled`
- [ ] pg_receivewal aktif: `systemctl is-active teqlif-pg-receivewal` + WAL dosyaları birikmeye başladı
- [ ] İlk pg_dump başarılı: `ls -lh /opt/teqlif/backups/postgres/dump/` → dosya mevcut
- [ ] Off-site rclone bağlantısı: `rclone lsd b2backup:` → bucket görünüyor
- [ ] WireGuard private key'ler password manager'a kaydedildi (tüm 11 node)

### 12.2 Mobile Güncellemesi

- [ ] `dart_defines/release.json`: `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL`, `CAPTCHA_BASE_URL` güncelle (bkz. Faz 0.10)
- [ ] `dart_defines/staging.json`: aynı anahtarlar staging değerleriyle
- [ ] `frontend/.well-known/assetlinks.json` — Android App Links (bkz. Faz 0.10)
- [ ] `frontend/.well-known/apple-app-site-association` — iOS Universal Links (bkz. Faz 0.10)
- [ ] Android: Play Store internal track
- [ ] iOS: App Store TestFlight

---

## Faz 13 — node9 Doğrulama + Tam Entegrasyon

**Önkoşul:** Faz 12 tamamlandı. Prodüksiyon trafiği canlı, Faz 10'da kurulan tüm node9 servisleri ayakta.

> Bu faz tamamen doğrulama + entegrasyon testidir. Yeni kurulum komutu yoktur — Faz 10'da kurulan servisler prod trafik altında test edilir.

### 13.1 WireGuard Mesh Bütünlüğü

```bash
# node9'dan tüm node'lara ping:
for ip in 10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 \
          10.10.0.6 10.10.0.7 10.10.0.8 10.10.0.9 10.10.0.12; do
  ping -c1 -W2 "${ip}" > /dev/null && echo "OK: ${ip}" || echo "FAIL: ${ip}"
done
# → Tümü OK

# Diğer node'lardan node9'a ping:
# node5'te:
ping -c1 10.10.0.13  # → OK
# gateway1'de:
ping -c1 10.10.0.13  # → OK

# WireGuard handshake zamanları güncel mi?
wg show wg0  # her peer'da Latest handshake: < 5 dakika
```

### 13.2 ClickHouse — Prod Veri Akışı Doğrulaması

```bash
# node9'da: prod başladıktan sonra ilk yazma geldi mi?
clickhouse-client --user=teqlif --password=<pass> \
  --query="SELECT count(), max(created_at) FROM teqlif.analytics_events LIMIT 1"
# → satır sayısı > 0, max(created_at) son dakikalarda

# node5'ten ClickHouse'a erişim:
curl -sf "http://10.10.0.13:8123/?user=teqlif&password=<pass>&query=SELECT+1"
# → 1

# Circuit breaker durumu (node9 geçici kapatma testi):
# node9'da:
systemctl stop clickhouse-server
# node5'te bir analytics endpoint'e istek gönder — uygulama çalışmaya devam etmeli
curl -s https://api.teqlif.com/v1/ping  # → 200 (analytics degraded, app UP)
# node9'da:
systemctl start clickhouse-server
```

### 13.3 Prometheus — Tüm Node'lar Scrape Ediliyor

```bash
# node9'dan:
curl -s 'http://127.0.0.1:9090/api/v1/targets' | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']['activeTargets']
up = [t for t in data if t['health'] == 'up']
down = [t for t in data if t['health'] != 'up']
print(f'UP: {len(up)}, DOWN: {len(down)}')
for t in down: print('  FAIL:', t['labels']['instance'])
"
# → UP: 11, DOWN: 0  (node9 kendisi dahil)

# node9 scrape ediliyor mu?
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up%7Binstance%3D%2210.10.0.13%3A9100%22%7D' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['data']['result'])"
# → [{'metric': ..., 'value': [..., '1']}]  → 1 = up
```

### 13.4 Loki — Tüm Node'lardan Log Akışı

```bash
# node9'dan Loki: labels sorgusu
curl -s 'http://127.0.0.1:3100/loki/api/v1/labels' | python3 -m json.tool
# → "node" label'ı var

# Tüm node'lar loglanıyor mu?
curl -s 'http://127.0.0.1:3100/loki/api/v1/query_range?query=%7Bjob%3D%22journal%22%7D&limit=1&start=1h' \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
nodes = set(s['stream'].get('node','?') for s in r['data']['result'])
print('Nodes logging:', sorted(nodes))
"
# → Nodes logging: ['gateway1', 'gateway2', 'node1', 'node2', 'node3', 'node4',
#                   'node5', 'node6', 'node7', 'node8', 'node9']
```

### 13.5 Backup Sistemleri — İlk Tam Doğrulama

```bash
# pg_receivewal aktif:
systemctl is-active teqlif-pg-receivewal   # → active
ls /opt/teqlif/backups/postgres/wal/       # → .gz.partial dosyası mevcut
# pg_receivewal lag — 0 veya çok küçük:
psql -h 10.10.0.5 -p 5432 -U replicator \
  -c "SELECT slot_name, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes \
      FROM pg_replication_slots WHERE slot_name='wal_backup_node9';"
# → lag_bytes < 10MB (normal çalışma)

# İlk pg_dump manuel çalıştır:
systemctl start teqlif-pg-dump.service
systemctl is-active teqlif-pg-dump.service  # oneshot → inactive (tamamlandı)
ls -lh /opt/teqlif/backups/postgres/dump/  # → .sql.gz dosyası mevcut

# ClickHouse backup manuel çalıştır:
systemctl start teqlif-clickhouse-backup.service
ls /data/clickhouse/backups/               # → ch_backup_* dizini mevcut

# Redis backup manuel çalıştır:
systemctl start teqlif-redis-backup.service
ls /opt/teqlif/backups/redis/              # → core-redis-*.rdb.gz mevcut

# Tüm timer'lar aktif:
systemctl list-timers "teqlif-pg-*" "teqlif-redis-*" "teqlif-clickhouse-*" "teqlif-offsite-*"
# → hepsi active/waiting
```

### 13.6 Alertmanager — Telegram Testi

```bash
# Test alert gönder:
curl -s -X POST http://127.0.0.1:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "warning", "instance": "node9"},
    "annotations": {"description": "Faz 13 doğrulama: node9 Alertmanager çalışıyor."}
  }]'
# → Telegram #ops kanalında mesaj gelmeli (repeat_interval nedeniyle 4 saat sonra tekrarlanmaz)
```

### 13.7 Grafana — Dashboard Doğrulaması

```bash
# Grafana sağlık:
curl -s http://127.0.0.1:3000/api/health | python3 -m json.tool
# → {"commit": "...", "database": "ok", "version": "..."}

# Grafana WireGuard üzerinden erişim (lokal makineden, WG bağlantısı varsa):
# http://10.10.0.13:3000
# Data Sources: Prometheus → http://127.0.0.1:9090  ✓
#               Loki       → http://127.0.0.1:3100  ✓
```

### 13.8 Guardian — node9 Entegrasyon Durumu

```bash
# node5'te Guardian: node9'u görüyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> hgetall edge:metrics:node9
# → cpu_percent, mem_percent, disk_percent_data gibi alanlar güncel

# node9'un guardian_priority: 5 → lider seçilmemeli
redis-cli -h 10.10.0.11 -p 6382 -a <pass> get guardian:leader
# → "node5" veya "node6" (node9 asla lider olmamalı)

# Guardian node9'un ClickHouse component'ini HEALTHY görüyor mu?
redis-cli -h 10.10.0.11 -p 6380 -a <pass> \
  hget "edge:health:node9" "clickhouse"
# → "HEALTHY"
```

### 13.9 Faz 13 Son Kontrol Listesi

- [ ] WireGuard: node9 ↔ tüm diğer 10 node çift yönlü handshake OK
- [ ] ClickHouse: prod yazmaları node9'a geliyor (analytics_events satır sayısı artıyor)
- [ ] Prometheus: 11 target UP (node9 dahil)
- [ ] Loki: 11 node'dan log akışı görünüyor
- [ ] pg_receivewal: WAL lag < 10 MB, .gz.partial dosyaları birikmeye devam ediyor
- [ ] pg_dump: ilk dump dosyası mevcut, < 24 saatlik
- [ ] ClickHouse backup: `/data/clickhouse/backups/ch_backup_*` mevcut
- [ ] Redis backup: `/opt/teqlif/backups/redis/` dosyaları mevcut
- [ ] Alertmanager: Telegram #ops kanalına test mesajı gönderildi
- [ ] Grafana: her iki data source (Prometheus + Loki) bağlı, dashboard node9 metriklerini gösteriyor
- [ ] Guardian: node9 lider seçilmedi, edge:metrics:node9 güncel
- [ ] Circuit breaker test: ClickHouse kapatılınca app canlı kalıyor, yeniden açılınca yazma devam ediyor
- [ ] node9 guardian_priority: 5 → redis-cli confirm
- [ ] Off-site rclone bağlantısı: `rclone lsd b2backup:` → bucket görünüyor

---

## Özet Tablo

| Faz | Konu | Önkoşul | Paralel? |
|-----|------|---------|---------|
| 0 | Kod hazırlığı (lokalde) | — | — |
| 1 | OS temeli — tüm node'lar | 0 | — |
| 2 | WireGuard mesh | 1 | — |
| 3 | Rol bazlı sysctl + UFW | 2 | — |
| 4 | Veri katmanı HA (node5 + node6) | 3 | — |
| 5 | Core app (node5 primary + node6 standby) | 4 | — |
| 6 | Storage (node7 + node8) | 3 | ✅ 5, 7, 8 ile |
| 7 | Gateway (gateway1 + gateway2) | 3 | ✅ 5, 6, 8 ile |
| 8 | Stream (node1 + node4) + AI Proxy (node2) | 3 | ✅ 5, 6, 7 ile |
| 9 | Orchestrator | 5 + 6 + 7 + 8 | — |
| 10 | Monitoring + Backup + ClickHouse (node9) | 9 | — |
| 11 | Staging (node3) | 10 | — |
| 12 | Prodüksiyon + Mobile | 11 | — |
| 13 | node9 Doğrulama + Tam Entegrasyon | 12 | — |

---

*V2.0 uygulama planı — 02_plan.md · 2026-09-29 (rev33 — Config audit düzeltmeleri: redis-guardian.conf `save "3600 1"` → `save 3600 1` (Redis geçersiz syntax — startup hatası); Prometheus scrape_configs'e node3 (10.10.0.4) eklendi (11 target: 10→11); §4.3 redis-server.service `systemctl disable --now redis-server` eklendi (port 6379 çakışması engeli); `wg_vip_failover.sh` pg_ctl promote'a `pg_is_in_recovery()` guard eklendi (node5 scriptiyle tutarlılık) | rev32 — Ağ topolojisi + güvenlik audit: §3.5 UFW node2+node9 default deny/allow eklendi; §3.5 UFW node3 (Staging) yeni blok eklendi; §2.2 node5 wg0.conf kısayoluna node9 peer eklendi (explicit); §10.0.3 node9 wg0.conf MTU=1420 eklendi; §2.4 ping loop notuna node9 Faz 10 açıklaması eklendi; §7.3 "10 node"→"11 node" + IP listesine node9=10.10.0.13 eklendi; §7.3 Promtail notu "node3'te"→"node9'da" düzeltildi; §4.5 SSH key hedef listesine node9 eklendi; §4.6 pg_hba.conf WAL-replication uyarısı eklendi; §10.6.1 node6 pg_hba.conf güncelleme adımı + failover SSH key eklendi | rev31 — node9 tamamlama: §0.5 node9 .env template eklendi; §1.4 node9 node.conf örneği + guardian_priority=5 eklendi; §4.8 kurulum sırası notu; Faz 10'a §10.0 Ön Kurulum (OS+/data dirs+WireGuard+node.conf+ClickHouse) eklendi; Faz 13 tam bölümü eklendi (WG mesh, ClickHouse prod veri akışı, Prometheus 11 target, Loki 11 node, backup doğrulama, Alertmanager test, Grafana, Guardian entegrasyon, 15 maddelik kontrol listesi); Özet tablo Faz 12/13 sırası düzeltildi | rev30 — node9 entegrasyonu: node9 (10.10.0.13, OVH KS-1-B) eklendi; node3 rol: Monitor+Staging→Staging; ClickHouse node5→node9; Faz 10 Monitoring+Backup+ClickHouse node3→node9; Prometheus scrape+alert node9; Loki listen_address+push_url node9; pg_hba.conf node3→node9; wal_backup_node3→wal_backup_node9; clickhouse_backup.sh lokal (rsync+SSH kaldırıldı); Faz bağımlılık haritası Faz 13 eklendi; failover for loop+ALL_WG_IPS node9; node9 WG peer template; §2.5 sudoers node9; §3.5 Monitor node9; guardian-redis REPLICAOF NO ONE fix (rev29 önceden); LiveKit reconnect fix (rev29); orch_client 3-level fallback (rev29); atomic write guardian_state.json (rev29); UDP election V2.0 simple priority notu (rev29) | rev18 — Tutarlılık + config audit: node5/6 .env metrics alanları eklendi; gateway2 INTERFACE_SPEED_MBPS=4000 ayrı blok; Faz 6.10 fallback test nginx portuna çevrildi; §10.5 duplicate Telegram bildirimi kaldırıldı | rev19 — Dizin izin audit: /var/log/teqlif 750→755; ClickHouse backup dir 755+usermod; /etc/livekit mkdir; /etc/ssl/teqlif node7/8 mkdir; promtail SupplementaryGroups override+__path__ glob; redis_backup BGSAVE+rsync→redis-cli --rdb; backup logrotate node3+node5 | rev20 — Node cross-erişim audit: §2.5 tüm non-core node'larda wg sudoers eklendi; failover step7 sudo bash→wg-quick save; node5 clickhouse-backup sudoers+script sudo rm -rf; postgres_exporter Environment→EnvironmentFile+DATA_SOURCE_NAME env template; Faz 11.4 /etc/ssl/teqlif mkdir eklendi | rev21 — Failover strateji audit: node5 keepalived nopreempt+notify_master/backup eklendi; wg_vip_node5.sh tanımlandı; node6 keepalived.conf vrrp_script blokları eklendi; §5.6 test sadeleştirildi; §5.6.1 failback 6-adım prosedüre dönüştürüldü (keepalived disable→sync→node6 stop→node5 MASTER); §10.6.2 WAL gap uyarısı+pg_basebackup zorunluluğu | rev22 — Dizin yapısı audit: header rol-bazlı ayrıştırıldı (gateway/core/stream/storage/monitoring); /var/log/teqlif 750→755 header düzeltildi; /etc/keepalived/secrets/ chmod 700 eklendi (node5+node6); .env.production chown tucibeyin:tucibeyin 6 node'da eksikti eklendi (node6/node7/gateway1-2/node1/4/node2/node3) | rev23 — Cross-node kesinti kurtarma: §5.6.2 failover WG routing reconciliation prosedürü eklendi; clickhouse_backup.sh STATUS check+cleanup trap eklendi (node5 stale backup birikimi önlendi); pg_basebackup/pg_dump/redis_backup atomik write pattern eklendi (temp→rename) | rev24 — Failsafe audit: nginx Restart=always drop-in (gateway1/2+node7/8); PgBouncer Restart=always drop-in (node5); teqlif/worker/orchestrator StartLimitIntervalSec=300+Burst=10 eklendi; node_exporter --collector.systemd eklendi; Prometheus ServiceFailed+MonitorDiskHigh alert eklendi; DR tablosuna bilinen SPOF'lar+crash-loop recovery eklendi | rev25 — AI Proxy HA: node2→node3→node5 öncelik zinciri; §5.3.1 node5 teqlif-ai-proxy disabled (son çare); §8.5 node3 teqlif-ai-proxy always-on (ilk yedek); §9.2 ai_proxy:active_url doğrulama eklendi; §9.5 AI proxy failover simülasyonu eklendi; DR tablosunda node2 SPOF kaldırıldı → node2+node3 eş zamanlı satırı eklendi; wg_vip_failover.sh MASTER: redis-cli REPLICAOF NO ONE eksikliği düzeltildi (config değişikliği yetmez, live promote şart); failover.env CORE_REDIS_PASS eklendi | rev26 — leader.py kaldırıldı (clean architecture: mechanism duplication — Keepalived zaten lider seçimi yapıyor; Redis lock aynı garantiyi tekrar etmemeli); §0.6'ya tasarım kararı notu eklendi; wg_vip_failover.sh'den orchestrator:leader DEL kaldırıldı; §9.2 doğrulama orchestrator:leader→systemctl is-active ile güncellendi | rev27 — Guardian mimarisi: §0.2 edge_metrics_agent→guardian_agent (local agent+heartbeat+election+command executor); §0.6 orchestrator→Guardian koordinatör (topology-driven, component:env bazlı service state: HEALTHY/DEGRADED/DOWN, job state machine+checkpoint+resume, playbook sistemi, local state cache guardian_state.json, dağıtık lider seçimi Redis NX+UDP peer fallback); §1.4 node.conf YAML full self-description şeması (guardian_priority, network, hardware, components[]); §4.4.1 guardian-redis port 6382 (appendonly yes — job checkpoint kalıcı); tüm node UFW'ye UDP 9901 guardian heartbeat kuralı eklendi; teqlif-orchestrator.service → teqlif-guardian.service geçiş notu | rev28 — traffic_eligible + traffic_type alanları: node.conf her componente eklendi (default: false — insan onayı olmadan routing yapılmaz); routing eligibility kuralı §0.6'ya eklendi (4 şart: eligible+env+systemd+health); internal_mesh/gateway_proxied/direct_internet tipleri; component asla hybrid değildir notu; §0.6 routing modülüne is_routing_eligible() kuralı eklendi)*
