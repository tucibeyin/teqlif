# teqlif V2.1 — Mimari Dokümanı

---

## 1. Node Envanteri

| Node | WG IP | Public IP | Tip | Sağlayıcı / Lokasyon | Rol |
|------|-------|-----------|-----|----------------------|-----|
| node1 | 10.10.0.1 | 193.70.46.74 | Bare metal | OVH Gravelines FR | Core — PG, Redis, MinIO, App |
| node2 | 10.10.0.2 | 135.125.223.43 | Bare metal | OVH Saarbrücken DE | Backup + ClickHouse + Mail |
| node3 | 10.10.0.3 | 51.75.74.124 | KVM VPS | OVH Frankfurt DE | LiveKit Streaming #1 |
| node4 | 10.10.0.4 | 135.125.175.223 | KVM VPS | OVH Frankfurt DE | LiveKit Streaming #2 |
| node5 | 10.10.0.5 | 45.146.252.165 | KVM VPS | ZAP Münster DE | Staging + AI Secondary |
| node6 | 10.10.0.6 | 5.249.165.10 | KVM VPS | ZAP Virginia US | AI Primary (Gemini) |
| nodeMonitor | 10.10.0.99 | 94.16.105.135 | KVM VPS | Netcup Karlsruhe DE | Merkezi İzleme (Prometheus + Loki + Grafana + Uptime Kuma) |
| streaming-N | 10.10.0.20+ | - | KVM VPS | herhangi | LiveKit Streaming #N (plug-and-play) |

---

## 2. Communication Architecture

### 2.1 Fiziksel Bağlantı

```
İnternet
  │
  ├── Cloudflare CDN/Proxy
  │     └── api.teqlif.com → node1:443 (API trafiği)
  │
  ├── Cloudflare DNS Only (direkt)
  │     ├── uploads.teqlif.com → node1:443 (MinIO media)
  │     ├── live1.teqlif.com   → node3:443 (LiveKit WebRTC)
  │     └── live2.teqlif.com   → node4:443 (LiveKit WebRTC)
  │
  └── Direkt (dahili)
        └── WireGuard mesh 10.10.0.0/24
```

### 2.2 Sanal Ağ (WireGuard Mesh)

- **Protokol:** WireGuard UDP, port 51820 (istisna: node5 port **443** — Zap-Hosting DDoS filtresi OVH kaynaklı UDP 51821'i engelliyor; UDP 443/QUIC geçiyor)
- **Subnet:** 10.10.0.0/24
- **Topoloji:** Full mesh — her node diğer tüm node'lara P2P tünel
- **Şifreleme:** ChaCha20-Poly1305 (WireGuard yerleşik)
- **Sabit node'lar:** 10.10.0.1–10.10.0.6 (node1–6), 10.10.0.99 (nodeMonitor)
- **Streaming pool:** 10.10.0.20–10.10.0.50 (plug-and-play)

```
node1 ←──────────────────────────────────── node2
  │ ↖                                          ↑
  │   ╲                                        │
  │    node3 ────────────────────────────────→ │
  │    node4 ────────────────────────────────→ │
  │    node5 ────────────────────────────────→ │
  │    node6 ────────────────────────────────→ │
  └──→ streaming-N (10.10.0.20+) ───────────→ │
```

### 2.3 Servis Erişim Noktaları

| Servis | Dinlediği arayüz | Port | Erişim |
|--------|-----------------|------|--------|
| FastAPI (node1) | 127.0.0.1 | 8000 | nginx üzerinden |
| PostgreSQL (node1) | 127.0.0.1 + 10.10.0.1 | 5432 | WG mesh (node2 backup) |
| PgBouncer (node1) | 127.0.0.1 + 10.10.0.1 | 6432 | WG mesh |
| Redis core (node1) | 127.0.0.1 + 10.10.0.1 | 6379 | WG mesh (tüm node'lar) |
| MinIO (node1) | 0.0.0.0 | 9000/9001 | nginx + WG |
| LiveKit (node3/4) | 0.0.0.0 | 7880/7881/443 | İnternet + WG |
| LiveKit staging (node5) | 127.0.0.1 | 7890 | nginx proxy → live-staging.teqlif.com |
| AI Proxy (node5/6) | 0.0.0.0 | 8001 | WG mesh |
| ClickHouse (node2) | 127.0.0.1 + 10.10.0.2 | 8123/9000 | WG mesh |
| ClickHouse (node5) | 127.0.0.1 | 8123/9000 | staging dahili — WG mesh'e kapalı |
| Prometheus (nodeMonitor) | 10.10.0.99 | 9090 | WG mesh |
| Grafana (nodeMonitor) | 10.10.0.99 | 3000 | WG mesh |
| Loki (nodeMonitor) | 10.10.0.99 | 3100 | WG mesh (Promtail) |
| Alertmanager (nodeMonitor) | 127.0.0.1 | 9093 | nodeMonitor dahili |
| Uptime Kuma (nodeMonitor) | 10.10.0.99 | 3001 | WG mesh |
| node-exporter (tüm node'lar) | WG arayüzü | 9100 | WG mesh (Prometheus scrape) |

---

## 3. Integration Architecture

### 3.1 API Katmanı

```
Mobil/Web İstemci (Production)
  │
  ├── REST API  → POST/GET/PATCH https://api.teqlif.com/v1/...
  ├── WebSocket → wss://api.teqlif.com/ws/...
  ├── Media     → https://uploads.teqlif.com/...
  └── LiveKit   → wss://live1.teqlif.com (node3) / wss://live2.teqlif.com (node4)

Mobil/Web İstemci (Staging — node5)
  │
  ├── REST API  → https://api-staging.teqlif.com/v1/...
  ├── WebSocket → wss://api-staging.teqlif.com/ws/...
  ├── Media     → https://staging.uploads.teqlif.com/...
  └── LiveKit   → wss://live-staging.teqlif.com (node5:7890)
```

- **Auth:** JWT (HS256, `secret_key` node1'de)
- **Rate limit:** nginx (Cloudflare WAF + nginx limit_req)
- **SSL termination:** nginx (Cloudflare origin cert)

### 3.2 Servisler Arası İletişim

| Kaynak | Hedef | Protokol | Amaç |
|--------|-------|----------|------|
| FastAPI | PostgreSQL | asyncpg (TCP) | ORM sorguları |
| FastAPI | Redis core | aioredis (TCP) | Cache, session, ARQ queue |
| FastAPI | MinIO | S3 API (HTTP) | Presigned URL üretimi |
| FastAPI | AI Proxy | HTTP | AI özellik çağrıları |
| FastAPI | LiveKit | LiveKit SDK | Room token üretimi |
| ARQ Worker | Redis core | aioredis | Job queue |
| ARQ Worker | PostgreSQL | asyncpg | analytics_events buffer yazma (aktif saatlerde) |
| ARQ Worker | ClickHouse | clickhouse-driver | Gece batch sync (01:50 UTC, `sync_pg_to_clickhouse_task`) |
| LiveKit (node3/4) | Redis core (node1) | TCP 6379 | Node koordinasyonu |
| AI Proxy (node5/6) | Groq/Gemini API | HTTPS | LLM çağrıları |
| Promtail (tüm node'lar) | Loki (nodeMonitor 10.10.0.99:3100) | HTTP Push | Log iletimi |
| Prometheus (nodeMonitor) | node-exporter :9100 (tüm node'lar) | HTTP Scrape | Metrik toplama |
| Uptime Kuma (nodeMonitor) | HTTP/TCP (tüm uç noktalar) | HTTP/TCP Probe | Uptime & health |
| pg_receivewal (node2) | PG (node1) | Replication protocol | WAL stream |
| Metrics Agent (tüm node'lar) | Redis core (node1) | TCP 6379 WG | Servis sağlığı + kaynak metrik yazma + Telegram alert |

### 3.3 Harici Servis Entegrasyonları

| Servis | Amaç | Kimlik doğrulama |
|--------|------|-----------------|
| Cloudflare | CDN, DDoS, DNS | API Token |
| LiveKit Cloud | WebRTC SFU | API Key/Secret |
| Groq API | LLM (AI proxy) | API Key |
| Google Gemini | LLM (AI proxy, US) | API Key |
| Stalwart SMTP | E-posta gönderimi (aiosmtplib → mail.teqlif.com:465) | SMTP Credentials |
| Apple APNS | iOS push bildirimi | AuthKey .p8 |
| Firebase FCM | Android push bildirimi | Service Account JSON |
| Google OAuth | Sosyal giriş | Client ID/Secret |
| Cloudflare Turnstile | CAPTCHA | Site/Secret Key |
| Sentry | Hata izleme | DSN |
| Telegram Bot API | AlertManager (Metrics Agent) | Bot Token + Chat ID |

### 3.4 AI Proxy Failover Zinciri

```
FastAPI (node1)
  │
  ├── Primary  → node6:8001 (Virginia, Gemini kısıtsız)
  │     │ başarısız olursa
  └── Fallback → node5:8001 (Münster EU, Groq + Gemini limitli)
```

### 3.5 Dağıtık Metrics Agent + AlertManager

Her node'da `teqlif-metrics-agent.service` olarak çalışır (`backend/scripts/edge_metrics_agent.py`).

**Görevleri:**
- Yerel servislerin sağlık kontrolü (HTTP ping + systemd unit durumu)
- CPU / RAM / Disk kaynak metrikleri
- Tüm metrikleri Redis core'a (node1 `10.10.0.1:6379`) yazar → EdgeOrchestrator buradan okur

**AlertManager (gömülü):**
- Servis durumu değişiminde (DOWN / kurtarıldı) Telegram bildirimi
- Kaynak eşik aşımında Telegram uyarısı: CPU >%90, RAM >%90, Disk >%85
- İlk döngüde baseline alır — restart sonrası false positive yok
- Servis alertleri: 5 dk cooldown; kaynak alertleri: 30 dk cooldown
- Config: `.env.metrics-agent` → `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`

**Not:** nodeMonitor'deki Prometheus Alertmanager (port 9093, 127.0.0.1'de çalışır) ayrı bir bileşendir — Prometheus kural tabanlı alertler için. Metrics Agent AlertManager ise servis/kaynak bazlı anlık bildirim içindir.

### 3.6 Backup Veri Akışı

```
node1 PostgreSQL ──WAL stream──→ node2 pg_receivewal → /project/teqlif/backups/pg_wal/  [AKTİF ✓ RPO ~1dk]
                                  slot: node2_receivewal | cleanup: günlük 05:30 UTC (7g retention)
node1 PostgreSQL ──pg_dump─────→ node2 /project/teqlif/backups/pg_dump/     (günlük 03:00 UTC)
node2 ClickHouse ──yerel dump──→ node2 /project/teqlif/backups/clickhouse/  (günlük 03:20 UTC)
node2 Redis rep. ──BGSAVE──────→ node2 /project/teqlif/backups/redis/       (günlük 03:40 UTC)
node2 Stalwart   ──rsync────────→ node2 /project/mail/backups/               (günlük 03:45 UTC)
node1 MinIO      ──mc mirror───→ node2 /project/teqlif/backups/minio/       (günlük 04:00 UTC)
                                  └─ mirror sonrası PG stream_recordings.node2_confirmed_at setler
```

---

## 4. Technology Architecture

### 4.1 node1 — Core

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 13 Trixie | 6.12 kernel |
| CPU | Intel Xeon E-2236 | 6c/12t, 3.4/4.8GHz |
| RAM | 32GB ECC DDR4 | 2666MHz |
| Disk | 2×512GB NVMe RAID-1 | ~940MB/s 4k |
| Web server | nginx | 1.26.3 |
| App server | uvicorn (ASGI) | 0.x |
| Framework | FastAPI | 0.x |
| Runtime | Python | 3.13 |
| ORM | SQLAlchemy (async) | 2.x |
| DB | PostgreSQL | 17.11 |
| Connection pool | PgBouncer | latest |
| Cache/Queue | Redis | 7.x |
| Object storage | MinIO | RELEASE.2025-09-07T16-13-09Z |
| Task queue | ARQ | latest |
| Process manager | systemd | - |

**Disk layout:**
```
/ (md3, ext4, RAID-1)  — 467GB — OS + tüm servis binary + veri
```

**Kritik OS ayarları:**
- `io_scheduler=none` (NVMe)
- `vm.swappiness=10`
- `vm.dirty_ratio=15`
- `kernel.pid_max=4194304`
- THP = `never`
- `net.core.somaxconn=65535`
- CPU governor = `performance`

---

### 4.2 node2 — Backup + ClickHouse + Mail

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 13 Trixie | 6.12 kernel |
| CPU | Intel Xeon D-2123IT | 4c/8t, 2.2/3.0GHz |
| RAM | 32GB ECC DDR4 | 2400MHz |
| Disk | 2×4TB HDD RAID-1 | ~70MB/s seq, ~440 IOPS (4k random) |
| Analitik DB | ClickHouse | 26.9 |
| Log shipper | Promtail | 3.x |
| Mail server | Stalwart | latest |
| Backup PG | pg_receivewal + pg_dump | PG17 tools |
| Backup MinIO | mc (MinIO client) | latest |
| Backup Redis | redis-cli + rdb | - |

**Disk layout:**
```
/ (md3, ext4, RAID-1)  — 3.6TB — OS + tüm servis veri
  ├── /var/lib/clickhouse/
  ├── /project/teqlif/data/mail/
  └── /var/backups/
       ├── pg_wal/
       ├── pg_dump/
       ├── redis/
       └── minio/
```

**Kritik OS ayarları:**
- `io_scheduler=mq-deadline` (HDD sıralı yazım)
- `blockdev --setra 8192` (readahead)
- `vm.dirty_ratio=40`
- THP = `never`
- Mount: `noatime,nodiratime`

---

### 4.3 node3, node4 — LiveKit Streaming

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 13 Trixie | 6.12 kernel |
| CPU | 6 vCPU (KVM) | Intel Haswell |
| RAM | 11.4GB | DDR4 |
| Disk | 99GB SSD | ~1GB/s |
| SFU | LiveKit Server | v1.13.7 |
| Flutter SDK | livekit_client | v2.5.4 (pubspec: ^2.3.0) |
| TURN proxy | nginx | UDP 443 |
| Redis client | → node1:6379 | koordinasyon |

**Kritik OS ayarları (UDP-yoğun):**
- `net.core.rmem_max=26214400`
- `net.core.wmem_max=26214400`
- `net.ipv4.ip_local_port_range=10000 65535`
- `net.netfilter.nf_conntrack_max=262144`
- `vm.swappiness=5`
- THP = `never`

**UFW:**
```
22/tcp     SSH
51820/udp  WireGuard
443/tcp    TURN/TLS
443/udp    TURN/DTLS
7880/tcp   LiveKit API    (WG only: 10.10.0.0/24)
7881/tcp   LiveKit RTC    (WG only)
50000:60000/udp  WebRTC media
```

---

### 4.4 node5 — Staging + AI Secondary

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 13 Trixie | 6.12 kernel |
| CPU | 4 vCPU AMD EPYC 7763 | KVM |
| RAM | 7.8GB | DDR4 |
| Disk | 50GB SSD | - |
| nginx | Staging ingress | latest stable |
| Staging stack | PG (5432) + Redis (6379) + MinIO (9100) + CH (8123) + LiveKit (7890) | lokal, izole |
| AI Proxy | uvicorn + FastAPI | port 8001 |

**Kritik OS ayarları:**
- `vm.swappiness=20` (7.8GB kısıtlı)
- THP = `never`

**Staging nginx blokları:**
- `staging.teqlif.com` → FastAPI staging :8000 (Cloudflare Proxy)
- `api-staging.teqlif.com` → FastAPI staging :8000 (Cloudflare Proxy)
- `staging.uploads.teqlif.com` → MinIO staging :9100 (DNS Only, Let's Encrypt)
- `live-staging.teqlif.com` → LiveKit staging :7890 (DNS Only, Let's Encrypt)

**WireGuard:** ListenPort = **443** (Zap-Hosting DDoS filtresi UDP 51821'i engelliyor)

**UFW:**
```
22/tcp     SSH
80/tcp     HTTP (nginx → HTTPS redirect, certbot webroot)
443/tcp    HTTPS nginx (staging stack)
443/udp    WireGuard (Zap-Hosting DDoS bypass — UDP 443/QUIC)
8001/tcp   AI Proxy  (WG only: 10.10.0.0/24)
```

---

### 4.5 node6 — AI Primary

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 13 Trixie | 6.12 kernel |
| CPU | 4 vCPU AMD EPYC 7763 | KVM |
| RAM | 3.8GB | DDR4 |
| Disk | 49GB SSD | - |
| AI Proxy | uvicorn + FastAPI | - |
| LLM | Gemini (kısıtsız, US) + Groq | harici API |

**Kritik OS ayarları:**
- `vm.swappiness=20`
- THP = `never`

**UFW:**
```
22/tcp     SSH
51820/udp  WireGuard
8001/tcp   AI Proxy  (WG only: 10.10.0.0/24)
```

---

### 4.6 nodeMonitor — Merkezi İzleme

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| OS | Debian 12 Bookworm | - |
| CPU | 2 vCPU | Netcup KVM |
| RAM | 2GB | DDR4 |
| Disk | 60GB SSD | - |
| Public IP | 94.16.105.135 | Netcup Karlsruhe DE |
| WireGuard IP | 10.10.0.99 | - |
| Metrics | Prometheus | 2.x |
| Dashboard | Grafana | 11.x |
| Log agg. | Loki | 3.x |
| Alerting | Alertmanager | 0.x |
| Uptime | Uptime Kuma | latest |
| Uptime DB | MariaDB | latest |
| Log shipper | Promtail | 3.x |

**Monitoring Stack Mimarisi:**

```
WireGuard mesh (10.10.0.0/24)
  │
  ├── Prometheus :9090  ← scrape node-exporter :9100 (tüm node'lar: node1–6 + nodeMonitor)
  │     └── Alertmanager 127.0.0.1:9093 (Telegram alerts)
  │
  ├── Loki :3100         ← Promtail push (tüm node'lardan)
  │
  ├── Grafana :3000      ← Prometheus + Loki datasource
  │     └── Provisioning: /var/www/teqlif.com/deploy/scale/V2.1/nodeMonitor/config/shared/grafana-provisioning/
  │
  └── Uptime Kuma :3001  ← HTTP/TCP probe (13 monitor)
        └── MariaDB 127.0.0.1:3306
```

**Disk layout:**
```
/opt/monitor/
  ├── shared/
  │   ├── grafana/data/       ← Grafana data + plugins + logs
  │   ├── loki/data/          ← Loki TSDB chunks
  │   ├── prometheus/data/    ← Prometheus TSDB
  │   └── uptime-kuma/        ← Uptime Kuma app + data
  └── teqlif/
      └── alertmanager/data/  ← Alertmanager state

/project/
  ├── shared/config/
  │   ├── grafana.ini                 ← Grafana config (WG bind, provisioning path)
  │   └── uptime-kuma.env             ← MariaDB credentials (600 perm)
  └── teqlif/config/
      ├── prometheus.yml              ← Scrape targets (7 node)
      ├── loki.yml                    ← Loki config (retention 30d)
      ├── alertmanager.yml            ← Telegram credentials
      └── alert_rules.yml             ← Prometheus alerting rules
```

**node-exporter (tüm node'larda):**
- Binary: `/usr/local/bin/node_exporter` v1.8.2
- Servis: `deploy/scale/V2.1/common/systemd/node-exporter.service`
- Dinlediği adres: WireGuard IP:9100 (dinamik tespit: `ip -4 addr show wg0`)
- UFW: `allow proto tcp from 10.10.0.0/24 to any port 9100`

**Uptime Kuma Monitörler (13 adet):**

| Grup | Monitor | Tip |
|------|---------|-----|
| Production API | api.teqlif.com/health | HTTP |
| Production API | api.teqlif.com WebSocket | TCP |
| Storage | uploads.teqlif.com/minio/health/live | HTTP |
| Streaming | node3 nginx :443 | TCP |
| Streaming | node4 nginx :443 | TCP |
| Staging | api-staging.teqlif.com/health | HTTP |
| AI Proxy | node6 AI Proxy :8001 | TCP |
| AI Proxy | node5 AI Proxy :8001 | TCP |
| Mail | mail.teqlif.com SMTP :25 | TCP |
| Mail | mail.teqlif.com IMAP :993 | TCP |
| Internal | node1 nginx :80 | TCP |
| Internal | node5 nginx :80 | TCP |
| Internal | nodeMonitor Prometheus :9090 | TCP |

**Grafana override.conf** (nodeMonitor'de, `/etc/systemd/system/grafana-server.service.d/override.conf`):
- `User=tucibeyin`, `Group=tucibeyin`
- `CONF_FILE=/project/shared/config/grafana.ini`
- `cfg:default.paths.bundled_plugins=/usr/share/grafana/plugins-bundled` (Prometheus plugin için zorunlu)
- `/etc/grafana/` dizini `o+rX` izni gerektirir (grafana user'a ait)

**Güvenlik:**
- SSH 2FA: key + şifre (Google Authenticator)
- UFW: sadece 22/tcp + 51820/udp açık; tüm monitoring portları WG-only
- Alertmanager `127.0.0.1:9093` — dışarıya kapalı

**Kritik OS ayarları:**
- `vm.swappiness=20` (2GB kısıtlı)
- THP = `never`

**UFW:**
```
22/tcp     SSH (2FA)
51820/udp  WireGuard
```

---

## 5. Dependency Architecture

### 5.1 Backend (Python) — Temel Bağımlılıklar

| Kütüphane | Amaç |
|-----------|------|
| FastAPI | ASGI web framework |
| SQLAlchemy (async) | ORM |
| asyncpg | PostgreSQL async driver |
| aioredis | Redis async client |
| ARQ | Async task queue |
| Pydantic v2 | Data validation |
| python-jose | JWT |
| passlib + bcrypt | Şifre hash |
| httpx | Async HTTP client |
| boto3 / aiobotocore | MinIO S3 client |
| livekit-server-sdk | LiveKit room token |
| clickhouse-driver | ClickHouse client |
| sentry-sdk | Hata izleme |
| alembic | DB migration |

### 5.2 3. Taraf Servis Bağımlılıkları

| Servis | Bağımlı node'lar | Kritiklik |
|--------|-----------------|-----------|
| Cloudflare | Tüm (DNS/CDN) | Kritik |
| LiveKit Cloud | node3/4 | Kritik (stream) |
| Groq API | node5/6 | Yüksek (AI) |
| Google Gemini | node6 | Yüksek (AI primary) |
| Stalwart SMTP (node2) | node1 (aiosmtplib) | Orta (e-posta) |
| Apple APNS | node1 | Orta (iOS push) |
| Firebase FCM | node1 | Orta (Android push) |
| Google OAuth | node1 | Orta (sosyal giriş) |
| Sentry | node1/5 | Düşük (izleme) |

---

## 6. Topology Architecture

### 6.1 Ağ Katmanları

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1 — İnternet / Cloudflare Edge                                      │
│  teqlif.com, api.teqlif.com → Cloudflare Proxy (prod)                      │
│  staging.teqlif.com, api-staging.teqlif.com → Cloudflare Proxy (staging)   │
│  uploads.teqlif.com, live1/live2.teqlif.com → DNS Only (prod, direkt)      │
│  staging.uploads.teqlif.com, live-staging.teqlif.com → DNS Only (staging)  │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  LAYER 2 — Edge / Ingress (node1 nginx)                      │
│  SSL termination, rate limit, routing                        │
│  → /api/* → FastAPI :8000                                    │
│  → /uploads/* → MinIO :9000                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  LAYER 3 — Application (node1)                               │
│  FastAPI + ARQ Workers                                       │
│  → PostgreSQL (PgBouncer :6432)                              │
│  → Redis :6379                                               │
│  → MinIO :9000                                               │
│  → AI Proxy (node6 → node5 fallback)                        │
└──────────────────────┬──────────────────────────────────────┘
                       │ WireGuard
        ┌──────────────┼──────────────────────┬──────────────────┐
        │              │                      │                  │
┌───────▼──────┐ ┌─────▼───────┐ ┌──────────▼──────┐ ┌────────▼────────┐
│ LAYER 4a     │ │ LAYER 4b    │ │ LAYER 4c         │ │ LAYER 4d        │
│ Streaming    │ │ AI Proxy    │ │ Backup + Mail    │ │ Monitoring      │
│ node3, node4 │ │ node6, node5│ │ node2            │ │ nodeMonitor     │
│ LiveKit SFU  │ │ Gemini/Groq │ │ ClickHouse +     │ │ Prometheus/Loki │
│              │ │             │ │ Stalwart + PG/   │ │ Grafana +       │
│              │ │             │ │ Redis/MinIO      │ │ Uptime Kuma     │
│              │ │             │ │ Backup           │ │ Alertmanager    │
└──────────────┘ └─────────────┘ └─────────────────┘ └─────────────────┘
```

### 6.2 Veri Akışı Topolojisi

```
Kullanıcı Cihazı
  │
  ├─[API]──→ Cloudflare ──→ node1:443
  │                              │
  │                         [nginx]
  │                              │
  │                         [FastAPI]──→ PG/Redis/MinIO (lokal)
  │                              │
  │                              └──→ AI Proxy (node6/5, WG)
  │
  ├─[Media]─→ node1:443 (uploads.teqlif.com, DNS only)
  │
  └─[Stream]─→ node3:443 (live1.teqlif.com) / node4:443 (live2.teqlif.com)
                    │
                    └──→ Redis node1:6379 (WG mesh, koordinasyon)
```

---

## 7. Configuration Architecture

### 7.0 Multi-Project İzolasyon Modeli

node1 ve node2 çok projeli bare metal. Her proje kendi sandbox'ında çalışır:

```
/project/
├── teqlif/              ← bu proje
│   ├── config/          ← .env.*, redis.conf, livekit.yaml, promtail.yml
│   ├── data/            ← Redis RDB, MinIO object storage
│   │   ├── redis/core/
│   │   └── minio/data/
│   ├── logs/            ← uygulama logları
│   └── backups/         ← node2: pg_dump, pg_wal, redis, minio
│
└── other-project/       ← gelecekteki proje (aynı yapı)
    ├── config/
    ├── data/
    ├── logs/
    └── backups/

/var/www/teqlif.com/     ← monorepo (tüm node'larda)
```

**Bileşen bazlı izolasyon stratejisi:**

| Bileşen | Strateji | Teqlif | Diğer proje |
|---------|----------|--------|-------------|
| Redis | Ayrı instance / port | 6379, `/project/teqlif/data/redis/` | 6383+, `/project/other/data/redis/` |
| MinIO | Ayrı instance / port | 9000, `/project/teqlif/data/minio/` | 9010+, `/project/other/data/minio/` |
| PostgreSQL | Ayrı DB + kullanıcı | DB: `teqlif`, user: `teqlif` | DB: `other`, user: `other` |
| ClickHouse | Ayrı DB + kullanıcı | `teqlif_analytics` | `other_analytics` |
| Prometheus | Paylaşımlı + `project` label | `external_labels: {project: teqlif}` | `{project: other}` |
| Loki | Paylaşımlı + tenant ID | `tenant_id: teqlif` (promtail) | `tenant_id: other` |
| Grafana | Organization per project | Org: teqlif | Org: other |
| systemd | Paylaşımlı + isimlendirme | `teqlif-*` | `other-*` |
| WireGuard | Paylaşımlı (altyapı) | — | — |

### 7.1 Config Katmanları

```
secrets.env (lokal makine, git'e girmez)
  │
  ├── bootstrap_nodeX.sh çalıştırılırken SECRETS_FILE ile verilir
  │     └── apply_secrets() → tüm <placeholder>'ları doldurur
  │
  ├── /project/teqlif/config/.env.production  (node1, 600 perm)
  ├── /project/teqlif/config/.env.staging     (node5, 600 perm)
  ├── /project/teqlif/config/redis/redis-core.conf
  ├── /etc/wireguard/wg0.conf                 (sistem seviyesi, 600 perm)
  └── /etc/systemd/system/teqlif-*.service    (sistem seviyesi, zorunlu)
```

### 7.2 Secrets Kategorileri

| Kategori | Örnekler | Kaynak |
|----------|---------|--------|
| Otomatik üretilen | DB/Redis/MinIO şifreleri, JWT key | `openssl rand` |
| Harici panel | LiveKit, APNS, FCM, Google, Groq, Gemini, Sentry | İlgili servis paneli |
| SMTP | Stalwart kullanıcı adı/şifre (mail.teqlif.com:465) | node2 Stalwart admin |
| WireGuard pubkey'ler | nodeX_pubkey | Bootstrap sonrası `cat /etc/wireguard/pubkey` |

### 7.3 Config Dağıtım Akışı

```
1. secrets.env doldur (lokal)
2. scp secrets.env root@<node>:/tmp/teqlif-secrets.env
3. SECRETS_FILE=/tmp/teqlif-secrets.env bash bootstrap_nodeX.sh
4. Bootstrap: apply_secrets() → placeholder'ları doldur → shred secrets
5. Bootstrap sonrası: pubkey topla → secrets.env Bölüm 3'ü tamamla
6. wg_mesh_apply.sh → tüm node'lara pubkey dağıt → WG başlat
```

### 7.4 Plug-and-Play Streaming Config

Yeni streaming node eklemek için tek komut:
```bash
STREAMING_WG_IP=10.10.0.20 \
NEW_NODE_HOST=<ip> \
SECRETS_FILE=./secrets.env \
bash scripts/add_streaming_node.sh
```

Script otomatik:
1. bootstrap_streaming.sh çalıştırır
2. WG pubkey toplar
3. Tüm node'lara yeni peer ekler (`wg set wg0 peer ...`)
4. LiveKit Redis koordinasyonu ile otomatik devreye girer

---

## 8. Network Security

### 8.1 UFW Kuralları — Her Node

| Node | İzin verilen portlar |
|------|---------------------|
| node1 | 22/tcp, 51820/udp, 80/tcp, 443/tcp, WG-only: 5432/6432/6379/9000/8000/9100 |
| node2 | 22/tcp, 51820/udp, 25/tcp, 443/tcp+udp, 465/tcp, 587/tcp, 993/tcp, WG-only: 8123/9100 |
| node3/4 | 22/tcp, 51820/udp, 443/tcp+udp, WG-only: 7880/7881/9100, 50000-60000/udp |
| node5 | 22/tcp, 80/tcp, 443/tcp (nginx), 443/udp (WireGuard), WG-only: 8001/9100 |
| node6 | 22/tcp, 51820/udp, WG-only: 8001/9100 |
| nodeMonitor | 22/tcp, 51820/udp — monitoring portları sadece WG-only (3000/3001/3100/9090) |

### 8.2 Güvenlik Katmanları

1. **Cloudflare WAF** — DDoS, bot koruması (API trafiği)
2. **nginx rate limiting** — IP başına istek sınırı
3. **UFW** — port bazlı erişim kontrolü
4. **WireGuard** — iç servis trafiği şifreli
5. **SSH** — sadece key-based, root girişi kapalı, şifre sadece yerel ağdan
6. **Fail2ban** — brute force koruması
7. **Veri sınırı** — kullanıcı datası sadece EU node'larında (node1-5)

---

## 9. Yüksek Erişilebilirlik ve Failover

### 9.1 Mevcut Durum (V2.1)

| Bileşen | HA Durumu | Açıklama |
|---------|-----------|----------|
| PostgreSQL | **Tek node** (node1) | node2 WAL stream ile kurtarma mümkün, otomatik failover yok. **Not:** node2 HDD (~440 IOPS) — failover hedefi olarak node1 NVMe (~5000 IOPS) performansına ulaşamaz |
| Redis | **Aktif/Standby** (node1+2) | HAProxy + async replica; otomatik failover (bkz. §9.3) |
| MinIO | **Tek node** (node1) | node2 mirror ile kurtarma mümkün |
| LiveKit | **Çift node** (node3+4) | DNS round-robin, birisi düşerse diğeri devam eder |
| AI Proxy | **Çift node** (node5+6) | node6 → node5 failover, kod içinde |
| App server | **Tek node** (node1) | Cloudflare cache ile kısa süreli ayakta kalır |

### 9.2 RTO / RPO

| Senaryo | RTO | RPO |
|---------|-----|-----|
| node1 reboot | ~2 dk | 0 (WAL anlık) |
| node1 disk hatası | ~30 dk (node2'den restore) | Son WAL segmenti |
| node1 Redis çöküşü | ~30 sn (3 başarısız check × 10 sn) | Son write (async replica gecikmesi) |
| node3 veya node4 çöküşü | 0 (DNS TTL sonrası) | 0 |
| node6 çöküşü | ~5 sn (app retry) | 0 |

### 9.3 Redis HA Mimarisi

```
node3/4: LiveKit  ──→ HAProxy 127.0.0.1:6379 ──→ node1:6379 (veya node2:6379 failover)
node1:   FastAPI/ARQ ──────────────────────────→ Redis 127.0.0.1:6379 (direkt, HAProxy yok)

node3/4 — HAProxy (active):
  ┌────────────────────────┐
  │  balance first         │
  │  → 10.10.0.1:6379 (✅)│
  │  → 10.10.0.2:6379 (⏸) │
  └────────────────────────┘
               │
 ┌─────────────┴─────────────┐
 ↓                           ↓
node1: Redis core          node2: Redis replica
(10.10.0.1:6379)  ─async→ (10.10.0.2:6379)
4GB maxmemory               replicaof node1
AOF+RDB hybrid              save "" (no persistence)
```

**Bileşenler:**
- **HAProxy** (node3/4 — `haproxy.service` active): `127.0.0.1:6379`'u dinler, `balance first` ile node1'i tercih eder; node1 3 kontrolde başarısız olursa node2'ye geçer. **node1'de HAProxy çalışmaz** — FastAPI/ARQ kendi Redis'ine (`127.0.0.1:6379`) direkt bağlanır.
- **Redis replica** (node2): `/etc/redis/redis-replica.conf`, `teqlif-redis-replica.service` ile yönetilir
- **Auto-promote** (node2): `redis-failover.timer` her 10 saniyede çalışır; Redis + ICMP 3 kez başarısız olursa `REPLICAOF NO ONE` → master'a terfi + Telegram bildirimi
- **Geri dönüş**: node1 kurtarıldıktan sonra manuel `REPLICAOF 10.10.0.1 6379` ile yeniden replica yapılır

---

### 9.4 PostgreSQL Manuel Failover Prosedürü

> **Uyarı:** node2 HDD (~440 IOPS) ile node1 NVMe (~5000 IOPS) arasında ciddi performans farkı var. node2'ye failover, yoğun yazım altında yavaşlama yaratır. Patroni otomasyonu henüz devreye alınmadı (node2 SSD almadan anlamlı değil).

**Senaryo: node1 tamamen erişilemez, node2'de pg_receivewal güncel**

```bash
# 1. node2'de WAL stream durumunu doğrula
ssh node2
ls -lth /var/backups/pg_wal/ | head -5
# Son segment < 5 dk önce olmalı

# 2. pg_receivewal servisini durdur
sudo teqlif-restart  # veya sadece pg servisini
# NOT: pg_receivewal önce durmalı, aksi halde pg_wal dizini açık kalır

# 3. WAL'ı PostgreSQL data dizinine uygula (recovery moduna geç)
sudo -u postgres pg_ctl stop -D /var/lib/postgresql/17/main   # varsa
# Data dizini boşsa pg_basebackup ile kurul (aşağıya bak)

# 4. Son pg_dump yedeğinden geri yükle (WAL mevcut değilse)
ls /var/backups/pg_dump/ | tail -3
sudo -u postgres psql -h 127.0.0.1 -c "CREATE DATABASE teqlif;" postgres
sudo -u postgres pg_restore -h 127.0.0.1 -d teqlif /var/backups/pg_dump/<en_son>.dump

# 5. DNS/nginx'te bağlantı noktasını node2'ye yönlendir
# node1'deki /project/teqlif/config/.env.production içinde DATABASE_URL güncelle
# (node1 erişilemezse node2'den servis kaldır: teqlif-app.service başlat)

# 6. node1 kurtarıldıktan sonra geri dönüş
# node2'den pg_dump al → node1'e restore → pg_receivewal yeniden başlat
sudo teqlif-restart   # node1'de
```

**RTO tahmini:** ~30–60 dk (pg_dump boyutuna bağlı) | **RPO:** Son WAL segmenti (genellikle < 1 dk)

---

### 9.5 Operasyonel Runbook

#### node1 Tamamen Çevrimdışı

1. **Telegram uyarısını al** (Metrics Agent veya Uptime Kuma)
2. OVH panelinden node1 konsol erişimi dene
3. Soft reboot: `sudo reboot` (SSH erişimi varsa)
4. Hard reboot: OVH Manager → Server → Reboot
5. ~2 dk sonra `sudo teqlif-restart` otomatik çalışır (ExecStartPre → alembic + sync_main → uvicorn)
6. Eğer disk hatası: RAID durumunu kontrol et: `cat /proc/mdstat`

#### Redis node1 Çökmesi

1. HAProxy otomatik node2'ye geçer (~30 sn, 3×10 sn check)
2. node2 `redis-failover.timer` → `REPLICAOF NO ONE` → master terfi
3. Telegram bildirimi gelir
4. node1 kurtarıldıktan sonra: `redis-cli -h 10.10.0.2 REPLICAOF 10.10.0.1 6379`

#### LiveKit node3 veya node4 Çökmesi

1. DNS TTL süresi (genellikle 60 sn) sonrası trafik sağlam node'a yönelir
2. Aktif stream'ler kesilir → istemci otomatik yeniden bağlanma dener (30 sn timeout)
3. Çöken node'u OVH'dan yeniden başlat: `sudo teqlif-restart`

#### node1 Redis → WAL Gecikmesi

```bash
# node2'de WAL gecikmesini kontrol et
sudo -u postgres psql -h 127.0.0.1 -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;" teqlif
# > 5 dk ise pg_receivewal servisini yeniden başlat
ssh node1
sudo systemctl status teqlif-pg-receivewal.service
```

#### MinIO Erişim Sorunu (node1)

```bash
# MinIO sağlığını kontrol et
curl -sf http://127.0.0.1:9000/minio/health/live && echo "OK"
# Servis durumu
sudo systemctl status teqlif-minio.service
sudo teqlif-restart
```

---

## 10. Mail Server

### 10.1 Genel Bakış

| Özellik | Değer |
|---------|-------|
| Yazılım | Stalwart Mail Server (Rust, tek binary) |
| Node | node2 (135.125.223.43) |
| FQDN | mail.teqlif.com |
| Protokoller | SMTP (25), Submission (587/465), IMAP (993) |
| Yönetim | `stalwart-cli` — CLI, web UI isteğe bağlı |
| Admin HTTP | `10.10.0.2:8080` (WireGuard only) |
| TLS | Let's Encrypt ACME (tls-alpn-01, port 443) |
| Depolama | RocksDB (index/meta) + filesystem (blobs) |
| Backup | `teqlif-mail-backup.timer` — 02:30 UTC, 7 gün |

### 10.2 Mimari

```
İnternet (MTA)
     │  port 25
     ▼
node2: stalwart-mail
  ├── SMTP  :25   → gelen mail
  ├── Sub   :587  → istemci gönderme (STARTTLS)
  ├── Sub   :465  → istemci gönderme (TLS)
  ├── IMAP  :993  → istemci okuma (TLS)
  └── Admin :8080 → sadece 10.10.0.2 (WireGuard)

Depolama:
  /project/teqlif/data/mail/db/     ← RocksDB (index + meta)
  /project/teqlif/data/mail/blobs/  ← Mail gövdeleri

Config:
  /project/teqlif/config/stalwart/config.toml
  /project/teqlif/config/stalwart/dkim/       ← DKIM özel anahtarları
  /project/teqlif/config/stalwart/acme/       ← Let's Encrypt cache
  /project/teqlif/config/.env.mail            ← Secrets (repoya girmez)
```

### 10.3 Güvenlik Katmanları

| Katman | Mekanizma |
|--------|-----------|
| Ağ | UFW: sadece 25/443/465/587/993 açık |
| Brute force | Fail2ban (SMTP + IMAP) — 5 denemede 1 saat ban |
| Kimlik doğrulama | SMTP AUTH zorunlu (open relay yok) |
| Şifreleme (transit) | TLS 1.2+ zorunlu, STARTTLS enforce |
| MTA bütünlüğü | SPF + DKIM + DMARC (her domain için) |
| Gelen spam | Stalwart dahili spam filtresi + greylisting |
| Admin erişimi | WireGuard (10.10.0.0/24) ile kısıtlı |
| IP kara liste | Spamhaus DNSBL dahili entegrasyon |

### 10.4 Multi-Domain Yönetimi

Tüm yönetim `stalwart-cli` ile yapılır:

```bash
export STALWART_URL=http://10.10.0.2:8080
export STALWART_CREDENTIALS="admin:<SIFRE>"

# Domain ekle
stalwart-cli domain create yenidomain.com

# DKIM üret ve DNS'e ekle
stalwart-cli dkim generate rsa yenidomain.com mail

# Hesap aç
stalwart-cli account create info@yenidomain.com --name "Info"

# Alias
stalwart-cli alias create destek@yenidomain.com info@yenidomain.com
```

### 10.5 Gerekli DNS Kayıtları (Her Domain için)

```
A     mail.teqlif.com     →  135.125.223.43      (DNS Only)
MX    teqlif.com          →  mail.teqlif.com  10  (DNS Only)
TXT   teqlif.com          →  "v=spf1 mx -all"
TXT   mail._domainkey...  →  "v=DKIM1; k=rsa; p=..."  (stalwart-cli dkim list)
TXT   _dmarc.teqlif.com   →  "v=DMARC1; p=reject; rua=mailto:dmarc@teqlif.com"
PTR   135.125.223.43      →  mail.teqlif.com     (OVH panelinden)
```

### 10.6 Backup Takvimi

| Timer | Saat (UTC) | İçerik |
|-------|-----------|--------|
| `teqlif-mail-backup.timer` | **03:45** | RocksDB + blobs + DKIM anahtarları, 7 gün saklanır |

---

## 11. Redis Cache Mimarisi ve Analytics

### 11.1 Aktif Kullanıcı Saatlerinde node2 İzolasyonu

node2 HDD disk ve backup rolü nedeniyle aktif kullanıcı isteklerinden izole edilmiştir. Temel strateji: **aktif saatlerde CH okuma/yazma sıfır**, tüm veri node1 Redis cache'inden servis edilir.

```
Aktif saatler (yaklaşık 07:00–01:00 UTC)
  │
  ├─ Analytics endpoint isteği
  │       → Redis cache hit (TTL dolmamış)  ✅ node2'ye hiç gidilmez
  │       → Redis cache miss (soğuk başlangıç veya ilk istek)
  │              → CH sorgusu (node2)  ⚠️ yalnızca nadir durum
  │
  ├─ Feed event (impression / click / skip / swipe)
  │       → PG analytics_events (node1 NVMe)  ✅ node2'ye hiç gidilmez
  │
  └─ user_interactions (flush)
          → PG user_interactions (node1 NVMe)  ✅ node2'ye hiç gidilmez

Gece penceresi (01:00–07:00 UTC)
  ── Analytics pre-compute (node2 HDD boş, çakışma yok) ──────────────────
  ├─ 01:50  sync_pg_to_clickhouse_task   ← PG buffer → CH + 48h cleanup
  ├─ 02:30  compute_analytics_cache_task ← CH → Redis (market_trends, demand_radar)
  ├─ 02:45  precompute_premium_user_analytics_task ← CH → Redis (pro_insights)
  ── Backup penceresi — HDD seri yazma (03:00–04:45) ─────────────────────
  ├─ 03:00  PG backup     (pg_dump → node2 HDD)
  ├─ 03:20  CH backup     (node2 lokal HDD)
  ├─ 03:40  Redis backup  (node2 HDD, hızlı ~5dk)
  ├─ 03:45  Mail backup   (node2 HDD)
  ├─ 04:00  MinIO backup  (node2 HDD, ~45dk)
  ── ARQ batch (node1 NVMe, node2'ye az dokunur) ─────────────────────────
  ├─ 03:00  Hafif cleanup batch'leri (node1 PG only)
  ├─ 03:40  CH bağımlı işler (user_interests, trending_categories)
  ├─ 04:00  CPU ağır işler (FAISS rebuild, churn, trending_listings)
  ├─ 05:00  Ağır backfill (nsfw, phash, embeddings) + haftalık temizlik
  └─ 05:15  ML training (BPR/ALS/item2vec) — 06:30 UTC'de biter

Kullanıcılar 08:00+ UTC = 11:00+ TR'de gelir — sistem taze, cache'ler dolu
```

Tam zamanlama çizelgesi: bkz. §12.

### 11.2 Redis Cache TTL Tablosu

#### Aktif Saatler — Cache'den Servis Edilen Endpointler

| Endpoint | Cache key deseni | TTL | Kaynak (cache miss) | Invalidasyon |
|----------|-----------------|-----|---------------------|--------------|
| `market_trends` | `cache:market_trends_global_{locale}` | **25 saat** (90000s) | CH sorgusu | 02:30 gece pre-compute |
| `pro_insights` | `cache:pro_insights:{uid}:{locale}::` | **25 saat** (90000s) | CH sorgusu | Yayın bitişinde + 02:45 pre-compute |
| `demand_radar` | `cache:demand_radar:{days}:{cat}:{sub}` | **25 saat** (90000s) | CH sorgusu | 02:30 gece pre-compute |
| `pro_metrics` | `cache:pro_metrics:{uid}` | **25 saat** (90000s) | CH sorgusu | Yayın bitişinde sil |
| `video_roi` | `cache:video_roi:{uid}:{start}:{end}:{cat}` | **4 saat** (14400s) | CH sorgusu | — |
| `gallery_stats` | `cache:gallery_stats:{uid}:{...}` | **4 saat** (14400s) | CH sorgusu | — |
| `video_performance` | `cache:video_perf:{uid}:{...}` | **4 saat** (14400s) | CH sorgusu | — |
| `seller_report` (biten yayın) | `cache:seller_report:{stream_id}` | **7 gün** (604800s) | CH sorgusu | — (immutable) |
| `seller_report` (canlı yayın) | `cache:seller_report:{stream_id}` | **2 dakika** (120s) | CH sorgusu | — |
| `category_report` | `cache:category_report:{...}` | **30 dakika** (1800s) | PG sorgusu | — |
| ForYou feed | Redis key per user | **24 saat** (86400s) | ML pipeline | 03:55 + 15:55 UTC yeniden hesap |
| Embedding | `cache:embedding:{hash}` | **7 gün** (604800s) | ML pipeline | — |

#### Gece Pre-Compute (node2 CH aktif olduğu pencere)

| Task | Saat (UTC) | Yazdığı cache | TTL |
|------|-----------|---------------|-----|
| `sync_pg_to_clickhouse_task` | 01:50 | — (CH'a yazar, cache değil) | — |
| `compute_analytics_cache_task` | 02:30 | `cache:market_trends_global_{tr/en/ru/ar}` × 4 locale | 25 saat |
| `compute_analytics_cache_task` | 02:30 | `cache:demand_radar:{7,30,90}:*` | 25 saat |
| `precompute_premium_user_analytics_task` | 02:45 | `cache:pro_insights:{uid}:{locale}::` (premium kullanıcılar) | 25 saat |

### 11.3 PG Buffer Mimarisi (analytics_events)

Aktif saatlerde feed/swipe event'leri doğrudan CH yerine PG `analytics_events` tablosuna yazılır. Gece 01:50'de bulk transfer yapılır.

```
İstek yolu (aktif saatler)
  ingest_feed_events      → PG analytics_events  (event_type: feed_impression/click/skip)
  ingest_swipe_live_events → PG analytics_events (event_type: swipelive_raw)
  flush_interactions_to_db → PG user_interactions

Gece penceresi
  sync_pg_to_clickhouse_task (01:50 UTC)
    ├─ PG user_interactions  → CH user_events       (son 24h, LIMIT 200K)
    ├─ PG analytics_events   → CH feed_analytics    (feed_impression/click/skip)
    ├─ PG analytics_events   → CH swipe_live_events (swipelive_raw)
    └─ Cleanup: analytics_events WHERE created_at < NOW() - 48h  (PG bloat önlemi)
```

**PG analytics_events indeksleri:**

| İndeks | Kolonlar | Amaç |
|--------|---------|------|
| `ix_analytics_events_user_created` | `(user_id, created_at)` | Kullanıcı bazlı sorgular |
| `ix_analytics_events_type_created` | `(event_type, created_at)` | Toplu event_type taramaları (sync + swipelive) |
| `ix_analytics_events_session_type` | `(session_id, event_type)` | Seans bazlı sorgular |

**Beklenen tablo boyutu:** ~10K aktif kullanıcıda ~1-2M satır/gün; 48h cleanup ile maksimum ~4M satır sabit kalır.

### 11.4 Stream Sonu Cache Invalidasyonu

Yayın bittiğinde (`stream_finalizer.py`) yayıncıya ait analytics cache'i temizlenir:

```python
# pro_insights tüm locale varyantları silinir (pattern match)
keys = await redis.keys(f"cache:pro_insights:{stream.host_id}:*")
# pro_metrics da silinir
await redis.delete(*keys, f"cache:pro_metrics:{stream.host_id}")
```

Bir sonraki istek fresh CH sorgusu tetikler ve cache 25 saatlik TTL ile yeniden dolar.

---

## 12. Sistem Zamanlama Çizelgesi

Bu bölüm `system_timing/V1.0/01_findings.md` verilerini kapsayan ve sistemin tek zamanlama kaynağı olan bölümdür. `schedule.yaml` ve `worker.py` ile senkronize tutulur.

### 12.1 Sürekli Çalışan ARQ İşler (node1 — programlamasız)

| Sıklık | İş | Kaynak |
|--------|----|--------|
| Her 2 dakika | `cleanup_stale_streams_task` | PG |
| Her 5 dakika | `flush_interactions_to_db` | Redis → PG |
| Her 10 dakika | `sync_ad_campaigns_task` | PG |
| Her 15 dakika | `cleanup_ghost_calls_task` | PG |
| Her 15 dakika | `check_search_alerts_task` | PG |
| Her 15 dakika | `invalidate_swipe_live_configs_task` | Redis |
| Her 20 dakika | `sync_swipelive_interests_task` | PG (analytics_events) |
| Her 30 dakika | `expire_recordings_task` | PG — `available` → `expired` (expires_at geçince) |
| Her saat :00 | `cleanup_expired_stories_task` | PG |
| Her saat :00 | `cleanup_hype_highlights_task` | PG |
| Her 15 dakika | `archive_recordings_task` | PG — `expired` → `archived` (node2_confirmed_at IS NOT NULL + transferred_at < NOW()-2g) |
| Her saat :45 | `backfill_listing_quality_scores_task` | PG |

### 12.2 node2 — Backup Timer'ları (MEVCUT, UTC)

| Saat | Timer | İçerik | I/O |
|------|-------|--------|-----|
| **03:00** | `teqlif-pg-dump.timer` | node1 PG → WireGuard → node2 HDD | Seri yazma |
| **03:20** | `teqlif-clickhouse-backup.timer` | node2 CH → node2 HDD (yerel) | Seri yazma |
| **03:40** | `teqlif-redis-backup.timer` | node2 Redis replica BGSAVE → node2 HDD | Seri yazma |
| **03:45** | `teqlif-mail-backup.timer` | Stalwart RocksDB + blobs → node2 HDD | Seri yazma |
| **04:00** | `teqlif-minio-backup.timer` | node1 MinIO → WireGuard → node2 HDD; tamamlanınca PG `stream_recordings.node2_confirmed_at` setler | Seri yazma |
| ~~05:00~~ | `teqlif-offsite-sync.timer` | **DISABLED** — ofsite hedef yapılandırılmamış | — |

**Not — Backup penceresi tasarım ilkeleri:**
- Backup timer'ları 03:00–04:45 UTC penceresine taşındı; analytics pre-compute (01:50–02:45) artık tamamen temiz bir pencerede çalışıyor.
- node2 HDD kafası iki eşzamanlı yazma isteği alırsa random I/O = hız 10-20 MB/s'ye düşer. Timer'ların sıralı dizilimi HDD'nin sequential write kapasitesini (~150 MB/s) tam kullanır.
- CH backup (03:20) ile sync_pg_to_clickhouse (01:50) artık ayrı pencerelerde: **çakışma yok**.
- mail backup (03:45) ile compute_analytics_cache (02:30) artık ayrı pencerelerde: **çakışma yok**.
- minio backup (04:00–04:45) ağ bağlantılı (WireGuard) sequential write; bu pencerede CH okuma (compute_trending_listings 04:00) yapılıyor — minor overlap, ancak minio I/O network-bound olduğu için HDD head movement az.

**pg_receivewal durumu:** `teqlif-pg-receivewal.service` node2'de **AKTİF**. RPO = ~1 dakika. Replication slot `node2_receivewal` node1'de aktif. WAL segmentleri `/project/teqlif/backups/pg_wal/`'a akar; `teqlif-pg-wal-cleanup.timer` günlük 05:30 UTC'de 7 günden eskilerini siler. node2 HDD etkisi: aktif saatlerde ~0.5–2 MB/s seri yazma (kapasitenin %1–3'ü).

**Not — offsite sync:** `rclone config` boş, hedef yapılandırılmamış. Timer disable + inactive. Ofsite hedef belirlendikten sonra `offsite_sync.sh` güncellenerek devreye alınır.

### 12.3 node1 — ARQ Günlük Batch İşler (UTC, schedule.yaml)

#### Analytics Penceresi (01:50–02:45)

| Saat | İş | Kaynak | Not |
|------|-----|--------|-----|
| **01:50** | `sync_pg_to_clickhouse_task` | PG → CH | PG buffer → CH + 48h cleanup |
| **02:30** | `compute_analytics_cache_task` | CH → Redis | market_trends + demand_radar (4 locale) |
| **02:45** | `precompute_premium_user_analytics_task` | CH → Redis | pro_insights premium kullanıcılar |

#### Temizlik ve Hesap Penceresi (03:00–04:30)

| Saat | İş | Kaynak | Ağırlık |
|------|-----|--------|---------|
| **03:00** | `cleanup_old_notifications_task` | PG | Hafif |
| **03:00** | `cleanup_old_stream_likes_task` | PG | Hafif |
| **03:20** | `compute_seller_badges_task` | PG | Orta |
| **03:20** | `calculate_user_budgets_task` | PG | Orta |
| **03:20** | `compute_trust_scores_task` | PG | Orta |
| **03:40** | `compute_user_interests_task` | CH + Redis | Orta |
| **03:40** | `compute_trending_categories_task` | CH + PG | Orta |
| **03:50** | `compute_user_condition_preferences_task` | PG + Redis | Hafif |
| **03:55** | `populate_foryou_feed_task` | Redis only | Hafif — **2× günlük** |
| **04:00** | `compute_trending_listings_task` | CH + PG | Orta |
| **04:00** | `process_churn_and_airdrop` | CH + PG + FCM | Orta |
| **04:10** | `optimize_notification_timing_task` | CH + Redis | Orta |
| **04:15** | `deactivate_expired_listings_task` | PG | Hafif |
| **04:20** | `delete_expired_inactive_listings_task` | PG + MinIO | Orta |
| **04:30** | `cleanup_old_impressions_task` | PG | Hafif |
| **04:30** | `rebuild_faiss_index_task` | PG + bellek | **Ağır** (~20 dk) |

#### Ağır Backfill Penceresi (05:00–05:10)

| Saat | İş | Kaynak | Ağırlık |
|------|-----|--------|---------|
| **05:00** | `nsfw_backfill_task` | PG + AI-proxy | Ağır |
| **05:00** | `backfill_phash_task` | PG + MinIO | Ağır |
| **05:00** | `backfill_listing_embeddings_task` | PG + MinIO + GPU | **Çok Ağır** |
| **05:00** | `hesitation_retarget_task` | CH + PG | Orta |
| **05:10** | `cleanup_old_media_messages_task` | PG | Hafif |
| **05:10** | `cleanup_hidden_messages_task` | PG | Hafif |

### 12.4 node1 — ARQ Haftalık Batch İşler (UTC)

| Gün | Saat | İş | Kaynak | Ağırlık |
|-----|------|-----|--------|---------|
| **Pazartesi** | 05:00 | `cleanup_old_analytics_task` | CH (büyük silme) | Ağır |
| **Pazartesi** | 05:15 | `train_bpr_task` | PG + bellek | **Çok Ağır** (~45 dk) |
| **Pazartesi** | 05:45 | `train_churn_model_task` | CH + PG + bellek | Ağır — CH delete bittikten sonra |
| **Salı** | 05:00 | `cleanup_old_user_interactions_task` | PG | Hafif |
| **Çarşamba** | 05:15 | `train_bpr_task` | PG + bellek | **Çok Ağır** |
| **Çarşamba** | 05:45 | `train_kmeans_cold_start_task` | PG + bellek | Ağır |
| **Perşembe** | 05:00 | `cleanup_old_stream_viewers_task` | PG | Hafif |
| **Cuma** | 05:00 | `cleanup_old_calls_task` | PG | Hafif |
| **Cuma** | 05:15 | `train_bpr_task` | PG + bellek | **Çok Ağır** |
| **Cumartesi** | 05:00 | `cleanup_old_listing_offers_task` | PG | Hafif |
| **Pazar** | 05:00 | `cleanup_empty_message_threads_task` | PG | Hafif |
| **Pazar** | 05:15 | `cleanup_inactive_search_alerts_task` | PG | Hafif |
| **Pazar** | 05:15 | `train_swipe_live_als_task` | PG + CH + bellek | **Çok Ağır** (~60 dk) |
| **Pazar** | 05:30 | `train_item2vec_task` | PG + bellek | **Çok Ağır** (~30 dk) |
| **Pazar** | 05:45 | `train_kmeans_cold_start_task` | PG + bellek | Ağır (~20 dk) |
| **Pazar** | 06:00 | `train_feed_als_task` | PG + CH + bellek | **Çok Ağır** (~60 dk) |
| **Pazar** | 06:30 | `train_listing_quality_model_task` | PG + CH + bellek | **Çok Ağır** (~30 dk) |
| **Pazar** | 06:30 | `compute_influence_scores_task` | PG (PageRank) | Ağır (~20 dk) |

**Pazar en ağır gün:** ~08:00 UTC'ye kadar sürer (TR: 11:00) — sabah commute başlamadan önce biter.

**train_bpr weekday:** `{0,2,4}` = Pazartesi/Çarşamba/Cuma. Önceki hatalı değer `{0,2,5}` = Pzt/Çar/**Cumartesi** idi; Python `datetime.weekday()` 5=Cumartesi'dir.

### 12.5 node1 — ARQ Aylık İşler

| Koşul | Saat | İş | Kaynak |
|-------|------|-----|--------|
| Ayın 1'i | 05:00 | `cleanup_old_exchange_rates_task` | PG |
| Ayın 1'i | 05:10 | `cleanup_old_streams_task` | PG + MinIO |

### 12.6 ForYou Feed Zamanlama

| Parametre | Değer | Kaynak |
|-----------|-------|--------|
| `_FORYOU_TTL` | **86400 s (24 saat)** | `schedule.yaml → ttl.foryou_feed_seconds` |
| 1. çalışma | 03:55 UTC | user_interests hesaplandıktan hemen sonra |
| 2. çalışma | **15:55 UTC** = **18:55 TR** | Prime time (20:00–23:00 TR) başlamadan ~1 saat önce |
| Watchdog interval | 720 dk (12 saat) | 2× günlük, max boşluk ~12 saat |

2. çalışma saat seçimi: sabah ilgi vektörleri + günün yeni ilanları prime time öncesi cache'e alınır. 15:55–03:55 arası en uzun açık ~12 saat (gece saatleri, düşük aktivite).

### 12.7 Tam Günlük Çizelge Diyagramı (UTC)

```
SAAT    NODE     İŞ / OLAY                          KAYNAK
────────────────────────────────────────────────────────────────────
── Analytics pre-compute — node2 HDD boş, CH writes/reads çakışmasız ──
01:50   node1    sync_pg_to_clickhouse_task          PG → CH write (node2 HDD)
02:30   node1    compute_analytics_cache_task        CH read → Redis
02:45   node1    precompute_premium_user_analytics   CH read → Redis
── Backup penceresi — node2 HDD seri yazma (03:00-04:45) ───────────
03:00   node2    pg_dump BAŞLAR                      node1 PG → node2 HDD write
03:00   node1    cleanup_old_notifications           PG (hafif)
03:00   node1    cleanup_old_stream_likes            PG (hafif)
03:20   node2    clickhouse_backup BAŞLAR            node2 CH → node2 HDD write
03:20   node1    compute_seller_badges               PG
03:20   node1    calculate_user_budgets              PG
03:20   node1    compute_trust_scores                PG
03:40   node2    clickhouse_backup BİTER (tahmini)
03:40   node2    redis_backup BAŞLAR                 BGSAVE → node2 HDD write (~5dk)
03:40   node1    compute_user_interests              CH read (node2 HDD)
03:40   node1    compute_trending_categories         CH read + PG
03:45   node2    minio_backup BİTER (tahmini)
03:45   node2    redis_backup BİTER
03:45   node2    mail_backup BAŞLAR                  Stalwart → node2 HDD write (~10dk)
03:50   node1    compute_user_condition_preferences  PG + Redis
03:55   node1    populate_foryou_feed (1. tur)       Redis only
03:55   node2    mail_backup BİTER (tahmini)
04:00   node2    minio_backup BAŞLAR                 node1 MinIO → node2 HDD sequential write
04:00   node1    compute_trending_listings           CH read (node2 HDD)
04:00   node1    process_churn_and_airdrop           CH read + PG + FCM
04:10   node1    optimize_notification_timing        CH + Redis
04:15   node1    deactivate_expired_listings         PG
04:20   node1    delete_expired_inactive_listings    PG + MinIO
04:30   node1    cleanup_old_impressions             PG
04:30   node1    rebuild_faiss_index                 PG + bellek (ağır)
05:00   node1    nsfw_backfill                       PG + AI-proxy (ağır)
05:00   node1    backfill_phash                      PG + MinIO (ağır)
05:00   node1    backfill_listing_embeddings         PG + MinIO + GPU (çok ağır)
05:00   node1    hesitation_retarget                 CH + PG
05:00   node1    [Pzt] cleanup_old_analytics         CH (büyük silme)
05:00   node1    [Sal] cleanup_old_user_interactions PG
05:00   node1    [Per] cleanup_old_stream_viewers    PG
05:00   node1    [Cum] cleanup_old_calls             PG
05:00   node1    [Cmt] cleanup_old_listing_offers    PG
05:00   node1    [Paz] cleanup_empty_message_threads PG
05:10   node1    cleanup_old_media_messages          PG
05:10   node1    cleanup_hidden_messages             PG
05:15   node1    [Pzt/Çar/Cum] train_bpr             PG + bellek (çok ağır, ~45 dk)
05:15   node1    [Paz] cleanup_inactive_search_alerts PG
05:15   node1    [Paz] train_swipe_live_als           PG + CH + bellek (çok ağır)
05:30   node1    [Paz] train_item2vec                PG + bellek
05:45   node1    [Pzt] train_churn_model             CH + PG + bellek
05:45   node1    [Çar/Paz] train_kmeans_cold_start   PG + bellek
06:00   node1    [Paz] train_feed_als                PG + CH + bellek (çok ağır)
06:30   node1    [Paz] train_listing_quality_model   PG + CH + bellek
06:30   node1    [Paz] compute_influence_scores      PG (PageRank)
── 07:00–08:00 TÜM İŞLER TAMAM (Pazar ~08:00) ──────────────────────
08:00+ = 11:00+ TR   Kullanıcılar gelir — sistem taze, tüm cache'ler dolu
────────────────────────────────────────────────────────────────────
15:55   node1    populate_foryou_feed (2. tur)       Redis only — prime time hazırlığı
────────────────────────────────────────────────────────────────────
```

### 12.8 Kaynak Modeli

```
node1 (12 core / 32GB / NVMe SSD)
  ├── CPU  : ML training (ALS, BPR, item2vec, kmeans) → ağır, 05:15–07:00
  ├── CPU  : backfill (nsfw, phash, embeddings) → ağır, 05:00–06:00
  ├── RAM  : FAISS index rebuild → embedding boyutuna göre değişken
  ├── PG   : pg_dump sırasında (01:00) hafif ek yük — PG eşzamanlılık sorun değil
  └── Ağ   : MinIO backup WireGuard trafiği (03:00–03:45)

node2 (8 core / 32GB / HDD RAID-1)
  ├── HDD  : seri yazma (01:00→01:30→02:00→02:30→03:00) → sequential write
  ├── CH   : sorgu yanıtları HDD nedeniyle SSD'den ~5× yavaş
  └── Ağ   : node1'den WireGuard backup trafiği

node3/4 (6 core / 11GB / SSD)
  ├── Ağ   : LiveKit SFU — gün boyunca yayın trafiği
  └── CPU  : ffmpeg encode (gündüz değil, gece boşta)
```

### 12.9 teqlif-agent Entegrasyonu

`teqlif-agent` zamanlama sistemini şu modüllerle izler:

| Modül | Katkı |
|-------|-------|
| `watchdog.py` | ARQ cron job'larının `teqlif:agent:job_ok` sinyallerini okur; beklenen interval'den %50 geç gelirse Telegram uyarısı. `schedule.yaml`'daki `watchdog_m` değerleri kullanılır. |
| `janitor.py` | Her 60 saniyede lider tarafından çalışır. TTL politikalarını değerlendirir. Kayıt pipeline encode + transfer trigger mekanizması mevcut. |
| `healer.py` | Servis `failed` durumuna düşerse otomatik `reset-failed` + `start`. Batch penceresi boyunca servisleri çalışır halde tutar. |

**Backup script'leri job_ok entegrasyonu:** `pg_dump`, `clickhouse_backup`, `redis_backup`, `mail_backup`, `minio_backup` script'leri tamamlanınca `teqlif:agent:job_ok` Redis hash'ine UTC timestamp yazar. `schedule.yaml`'da `watchdog_m: 1500` ile izlenir — 25 saati aşan gecikme Telegram uyarısı tetikler.

### 12.10 Bilinen Durumlar

| # | Durum | Önem |
|---|-------|------|
| 1 | `teqlif-pg-receivewal.service` node2'de **AKTİF** ✓ | RPO ~1 dakika. Slot: `node2_receivewal`. WAL cleanup günlük 05:30 UTC. |
| 2 | `teqlif-offsite-sync.timer` **disabled** | rclone hedef yapılandırılmamış. Timer ve script mevcut; hedef belirlendikten sonra aktive edilir. |
| 3 | 04:00 minio_backup + CH okuma minor örtüşmesi | minio_backup (04:00–04:45) sequential write, network-bound; compute_trending_listings (04:00) CH read. Aynı HDD ama minio I/O WireGuard hızıyla sınırlı → minor. Kritik çakışmalar (CH backup+sync, mail+analytics) çözüldü. |
| 4 | Pazar training CPU spike | 06:00–07:00 UTC = 09:00–10:00 TR; Pazar sabahı commute başlamadan biter; Prom p99 izlenir |

---

## 13. Veri Yaşam Döngüsü

### 13.1 Stream Kayıt Yaşam Döngüsü

#### Statüler ve Geçişler

```
recording → encoding → encoded → transferring → available → expired → archived → deleted
```

#### Zaman Damgaları

| Damga | Kim set eder | Ne zaman |
|-------|-------------|----------|
| `recording_started_at` | `recorder.py` (stream node) | Kayıt başladığında |
| `encoding_started_at` | `recorder.py` (stream node) | Encode başladığında |
| `encoded_at` | `encoder.py` (stream node) | Encode tamamlandığında |
| `transferred_at` | `encoder.py` (stream node) | node1 MinIO'ya transfer tamamlandığında |
| `available_at` | `encoder.py` (stream node) | Kullanıcıya açıldığında |
| `expires_at` | `encoder.py` (stream node) | `available_at + 24 saat` |
| `node2_confirmed_at` | `minio_backup.sh` (node2) | node2 `mc mirror` başarıyla bitince |
| `archived_at` | `archive_recordings_task` (node1 ARQ) | PG `archived` statüsüne geçince |

#### Arşiv Güvenlik Garantisi

`archive_recordings_task` iki koşul birlikte sağlanmadan geçiş yapmaz:
1. `node2_confirmed_at IS NOT NULL` — node2 dosyayı gördüğünü onayladı
2. `transferred_at < NOW() - INTERVAL '2 days'` — MinIO ILM (2 gün expiry) büyük olasılıkla tetiklendi

**Başarısızlık modu:** node2 backup başarısız → `node2_confirmed_at` set edilmez → task bekler → node1 MinIO ILM tetiklenmez → dosya korunur → bir sonraki başarılı backup'ta onaylanır.

#### MinIO ILM (node1)

| Bucket | Prefix | Expiry | Kural ID |
|--------|--------|--------|----------|
| `teqlif` | `recordings/` | **2 gün** | `db3tiuskndq8as06c0e0` |

Transfer penceresi: **03:00–08:00 UTC** (stream node'larında `encoder.py`, `free_gb` kontrollü).

---

### 13.2 DM Arşiv (A2 — Tiered Storage)

#### Tasarım

| Katman | Depolama | Süre | Format |
|--------|----------|------|--------|
| Hot | PostgreSQL `messages` tablosu | 1 yıl | Satır bazlı |
| Cold | MinIO `teqlif-dm` bucket | Süresiz | `dm-archive/{küçük_id}_{büyük_id}/{yıl}.json.gz` |

#### PG Schema

```sql
-- message_threads tablosuna eklendi:
has_archive BOOLEAN NOT NULL DEFAULT FALSE
-- True: bu konuşmanın MinIO'da arşiv dosyası var
```

#### ARQ İşi

`archive_dm_messages_task` (günlük, gece penceresi):
- 1 yıldan eski mesajları PG'den okur
- MinIO'daki ilgili yıl dosyasına gzip JSON olarak ekler (varsa merge, yoksa yeni oluşturur)
- PG'den siler, `message_threads.has_archive = TRUE` setler

#### Flutter UI

`DirectChatScreen(hasArchive: bool)`:
- `has_archive = true` ise konuşma ekranının **üstünde** "Eski mesajları yükle" butonu gösterilir
- Butona basınca `GET /messages/{id}/archive` çağrılır, arşiv mesajlar listenin başına eklenir
- Yükleme sırasında buton yerine `CircularProgressIndicator` gösterilir
- Arşiv bir kez yüklendikten sonra buton kaybolur (`_archiveLoaded = true`)

