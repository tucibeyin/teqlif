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
  │     └── stream.teqlif.com  → node3/4:443 (LiveKit WebRTC)
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
  └── LiveKit   → wss://stream.teqlif.com (node3/4 round-robin)

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
| ARQ Worker | ClickHouse | clickhouse-driver | Event log yazma |
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
| Brevo | E-posta gönderimi | API Key |
| Apple APNS | iOS push bildirimi | AuthKey .p8 |
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
node1 PostgreSQL ──WAL stream──→ node2 pg_receivewal → /var/backups/pg_wal/
node1 PostgreSQL ──pg_dump─────→ node2 /var/backups/pg_dump/ (günlük 01:00)
node1 Redis      ──RDB copy────→ node2 /var/backups/redis/ (günlük 02:00)
node1 MinIO      ──mc mirror───→ node2 /var/backups/minio/ (günlük 03:00)
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
| Web server | nginx | latest stable |
| App server | uvicorn (ASGI) | 0.x |
| Framework | FastAPI | 0.x |
| Runtime | Python | 3.12 |
| ORM | SQLAlchemy (async) | 2.x |
| DB | PostgreSQL | 17 |
| Connection pool | PgBouncer | latest |
| Cache/Queue | Redis | 7.x |
| Object storage | MinIO | RELEASE.2024-11-07... |
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
| Disk | 2×4TB HDD RAID-1 | ~70MB/s seq |
| Analitik DB | ClickHouse | 24.x |
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
| Disk | 98GB SSD | ~1GB/s |
| SFU | LiveKit Server | v1.7.2 |
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
| Disk | 49GB SSD | - |
| nginx | Staging ingress | latest stable |
| Staging stack | PG (5433) + Redis (6390) + MinIO (9100) + LiveKit (7890) | lokal, izole |
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
  ├── Prometheus :9090  ← scrape node-exporter :9100 (tüm 7 node)
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
| Brevo | node1 | Orta (e-posta) |
| Apple APNS | node1 | Orta (iOS push) |
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
│  uploads.teqlif.com, stream.teqlif.com → DNS Only (prod, direkt)           │
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
  └─[Stream]─→ node3 veya node4:443 (stream.teqlif.com, round-robin DNS)
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
| Otomatik üretilen | DB/Redis/MinIO şifreleri, JWT key, keepalived pass | `openssl rand` |
| Harici panel | LiveKit, Brevo, APNS, Google, Groq, Gemini, Sentry | İlgili servis paneli |
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
| PostgreSQL | **Tek node** (node1) | node2 WAL stream ile kurtarma mümkün, otomatik failover yok |
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
node3/4: LiveKit  ──────────┐
node1:   FastAPI/ARQ ───────┤
                             ↓
                   127.0.0.1:6379 (HAProxy)
                   ┌────────────────────────┐
                   │  balance first         │
                   │  → node1:6379 (active) │
                   │  → node2:6379 (backup) │
                   └────────────────────────┘
                             │
               ┌─────────────┴─────────────┐
               ↓                           ↓
      node1: Redis core            node2: Redis replica
      (10.10.0.1:6379)   ─async→  (10.10.0.2:6379)
      4GB maxmemory                replicaof node1
      AOF+RDB hybrid               save "" (no persistence)
```

**Bileşenler:**
- **HAProxy** (node3/4 + node1): `127.0.0.1:6379`'u dinler, `balance first` ile node1'i tercih eder; node1 3 kontrolde başarısız olursa node2'ye geçer
- **Redis replica** (node2): `/etc/redis/redis-replica.conf`, `teqlif-redis-replica.service` ile yönetilir
- **Auto-promote** (node2): `redis-failover.timer` her 10 saniyede çalışır; Redis + ICMP 3 kez başarısız olursa `REPLICAOF NO ONE` → master'a terfi + Telegram bildirimi
- **Geri dönüş**: node1 kurtarıldıktan sonra manuel `REPLICAOF 10.10.0.1 6379` ile yeniden replica yapılır

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

| Timer | Saat | İçerik |
|-------|------|--------|
| `teqlif-mail-backup.timer` | 02:30 UTC | RocksDB + blobs + DKIM anahtarları, 7 gün |

