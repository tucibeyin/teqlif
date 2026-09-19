# Teqlif Scale V1.4 — Sistem Haritası

> **Sürüm:** V1.4  
> **Durum:** Production-Ready  
> **Güncelleme:** 2026-09-19  
> **Kaynak dizin:** `deploy/scale/V1.4/`

---

## İçindekiler

1. [Genel Bakış ve Mimari Mantık](#1-genel-bakış-ve-mimari-mantık)
2. [Donanım Haritası](#2-donanım-haritası)
3. [Communication Architecture](#3-communication-architecture)
4. [Integration Architecture](#4-integration-architecture)
5. [Technology Architecture](#5-technology-architecture)
6. [Dependency Architecture](#6-dependency-architecture)
7. [Topology Architecture](#7-topology-architecture)
8. [Configuration Architecture](#8-configuration-architecture)
9. [Servis Dağılım Matrisi](#9-servis-dağılım-matrisi)
10. [Port Haritası](#10-port-haritası)
11. [DNS & Cloudflare Yapısı](#11-dns--cloudflare-yapısı)
12. [Güvenlik Mimarisi](#12-güvenlik-mimarisi)
13. [Monitoring & Observability](#13-monitoring--observability)
14. [Kritik Yapılandırma Notları](#14-kritik-yapılandırma-notları)
15. [Operasyon Rehberi](#15-operasyon-rehberi)

---

## 1. Genel Bakış ve Mimari Mantık

### Tek Cümlelik Özet

Gateway Cloudflare ile trafiği sonlandırır, Core (node5) iş mantığını ve veriyi işler, Edge'ler (node1/node4) yalnızca medyayı taşır, AI Proxy'ler (node2/node3) LLM çağrılarını yönetir, Monitor (node3) tüm sistemi izler.

### Genel Akış

```
İnternet → Cloudflare → Gateway (Nginx L7) → Core (node5) ⇄ Edge'ler (node1, node4)
```

### Core-Edge Ayrımının Mantığı

V1.4'ün temel prensibi: **medya trafiğini (WebRTC/dosya) ile işlem trafiğini (API/DB) fiziksel olarak ayırmak.**

| Sorun (öncesi) | Çözüm | Neden |
|----------------|-------|-------|
| WebRTC UDP yükü FastAPI worker'ları bloke ediyordu | LiveKit edge node'lara (node1/node4) taşındı | UDP stream ve HTTP worker aynı CPU kaynağını tüketmez |
| Büyük dosya upload'ları gateway'i doyuruyordu | MinIO DNS Bypass ile direkt edge'e yönleniyor | Gateway bant genişliği korunur; Cloudflare proxy maliyeti engellenir |
| node1 tek nokta arıza riskiydi | node4 eklendi (node1 ikizi) | node1 çökerse node4 devralır |
| DB bağlantıları edge'den yapılıyordu | node5 ayrıldı — sadece DB, API, cache | Edge'ler DB'ye hiç bağlanmaz; Core dışarıya kapalı |

### DNS Bypass Mantığı

```
live1.teqlif.com        → DNS Only → node1 direkt (LiveKit prod)
live2.teqlif.com        → DNS Only → node4 direkt (LiveKit prod yedek)
minio1.teqlif.com       → DNS Only → node1 direkt (MinIO prod)
minio2.teqlif.com       → DNS Only → node4 direkt (MinIO prod yedek)
live-staging.teqlif.com → DNS Only → node3 direkt (LiveKit staging)
minio-staging.teqlif.com→ DNS Only → node3 direkt (MinIO staging)
```

- WebRTC UDP: Cloudflare yalnızca TCP taşır — UDP medya akışı proxy'den geçemez
- MinIO yükleme: Büyük dosyalar Cloudflare bant genişliği ücretini tetikler; direkt bağlantı hem maliyet hem gecikme açısından avantajlı
- Gateway 24h ortalama 100Mbps throttle: Medya trafiği bu limiti tek başına doldurabileceğinden bypass zorunlu

### AI Proxy Mantığı

```
node5 Backend → node2 (primary, US IP)
              → node3 (secondary, US IP)
              → local Groq fallback
```

Gemini API yalnızca belirli coğrafi bölgelerden (ABD dahil) kabul eder. node2 (VPSHostingService ABD) ve node3 (Ashburn, VA) her ikisi de ABD IP'sidir.  
node2 yalnızca 1 GB RAM — başarısız olursa node3 devralır.  
Rate limit sayaçları: her iki proxy da node5 Core Redis'e bağlanır — tutarlılık sağlanır.

### node3'ün Çift Rolü

```
node3 = MONITOR + STAGING + AI PROXY (production secondary)
```

Monitoring stack kaynak tüketimi modest (~500 MB RAM). Staging trafik yükü düşük. Ashburn VA konumu ABD IP gereksinimi sağlar (AI Proxy için). Ayrı monitoring node tahsis etmek maliyet artışı getirir.

**node3 üzerinde çalışan servisler:**
1. `teqlif-staging` — port 8001 (staging uygulama, kendi DB/Redis/MinIO/LiveKit ile)
2. `teqlif-ai-proxy` — port 8080 (production trafiği alır — node5'ten gelen AI çağrıları)
3. Prometheus, Loki, Grafana, Alertmanager (tüm sistemin monitoring'i)

---

## 2. Donanım Haritası

| Node | Rol | Sağlayıcı | Konum | CPU | RAM | Disk | Ağ | WireGuard IP | Public IP |
|------|-----|-----------|-------|-----|-----|------|----|-------------|-----------|
| **gateway** | EDGE PROXY | Netcup | Nürnberg, DE | 2 vCore QEMU 2.29GHz | 1.9 GB + 1 GB Swap | 58.9 GB SSD | 1 Gbps *(24h ort. 100Mbps throttle!)* | 10.10.0.2 | Netcup IP |
| **node1** | EDGE 1 | OVHcloud | Limburg, DE | 6 Core Intel Haswell 3.09GHz | 11.4 GB + 8 GB Swap | 98.3 GB NVMe | 2 Gbps unmetered | 10.10.0.1 | OVH IP |
| **node2** | AI PROXY 1 | VPSHostingService | ABD | 1 Core | 1 GB | — | — | 10.10.0.3 | US IP |
| **node3** | MONITOR & STAGING | Zap-Hosting | Ashburn, VA, ABD | 4 Core AMD EPYC | ~4 GB + 4 GB Swap | — | 5 TB/ay *(10 Mbit sonrası throttle)* | 10.10.0.4 | **5.249.165.10** |
| **node4** | EDGE 2 | OVHcloud | Limburg, DE | 6 Core Intel Haswell | 11.4 GB + 8 GB Swap | 98.3 GB NVMe | 2 Gbps unmetered | 10.10.0.6 | OVH IP |
| **node5** | CORE | Zap-Hosting | — | 4 Core AMD EPYC | 7.8 GB + 8 GB Swap | 50 GB SSD | 1 Gbps unmetered | 10.10.0.5 | Zap IP |

**OS:** Tüm node'lar Debian GNU/Linux 13 (trixie) — Kernel 6.12.x  
**Sanallaştırma:** KVM — node3 nested VM desteklemiyor  
**Kullanıcı:** `tucibeyin` (tüm node'larda standart)

---

## 3. Communication Architecture

### WireGuard Mesh (Fiziksel İç Ağ)

Her node, diğer 5 node ile **tam mesh WireGuard VPN** üzerinden bağlı. İç servis trafiğinin tamamı bu tünel üzerinden akar.

```
WireGuard Subnet: 10.10.0.0/24
Interface: wg0

gateway  10.10.0.2
node1    10.10.0.1
node2    10.10.0.3
node3    10.10.0.4  (public: 5.249.165.10)
node4    10.10.0.6
node5    10.10.0.5
```

Config: `deploy/scale/V1.4/<node>/resources/wg0.conf`  
**Private key git'e gitmez** — bootstrap sırasında `wg genkey` ile her node'da üretilir.  
Onarım: `deploy/scale/V1.4/scripts/repair_wireguard.sh`

### Peer Tablosu

| Node | WireGuard IP | Peer'ları |
|------|-------------|-----------|
| gateway | 10.10.0.2 | node1, node2, node3, node4, node5 |
| node1 | 10.10.0.1 | gateway, node2, node3, node4, node5 |
| node2 | 10.10.0.3 | gateway, node1, node3, node4, node5 |
| node3 | 10.10.0.4 | gateway, node1, node2, node4, node5 |
| node4 | 10.10.0.6 | gateway, node1, node2, node3, node5 |
| node5 | 10.10.0.5 | gateway, node1, node2, node3, node4 |

### Trafik Katmanları

| Trafik Türü | Protokol | Yol |
|-------------|----------|-----|
| REST API (prod) | HTTPS → HTTP | İnternet → CF → Gateway:443 → node5:8000 (wg0) |
| REST API (staging) | HTTPS → HTTP | İnternet → CF → Gateway → node3:8001 (wg0) |
| WebRTC medya (prod) | UDP | İnternet → CF DNS Only → node1/node4 public IP:50000-60000 |
| WebRTC medya (staging) | UDP | İnternet → node3 public IP:50000-60000 |
| LiveKit API çağrıları | HTTP | node5 wg0 → node1/node4:7880 |
| Dosya upload/download | HTTPS | İnternet → CF DNS Only → node1/node4 public IP:9010 |
| Log akışı | HTTP | Tüm node'lar (wg0) → node3:3100 |
| Metrik scraping | HTTP | node3 (wg0) → tüm node'lar:9100 |
| DB erişimi | TCP | Yalnızca 127.0.0.1 — dışa kapalı |

### Erişim Yönetimi

```bash
ssh tucibeyin@<node-public-ip>         # Hepsi için
ssh tucibeyin@10.10.0.4               # WireGuard bağlıysa node3 iç IP
ssh tucibeyin@5.249.165.10            # node3 public IP (direkt)
```

---

## 4. Integration Architecture

### API Çağrı Haritası

```
Mobil App
  ├─ REST/WebSocket → api.teqlif.com → gateway → node5:8000
  ├─ LiveKit SDK    → live1.teqlif.com → node1:7880 (prod)
  │                 → live2.teqlif.com → node4:7880 (prod yedek)
  │                 → live-staging.teqlif.com → node3:7880 (staging)
  └─ MinIO S3 API  → minio1.teqlif.com → node1:9010 (prod)
                   → minio2.teqlif.com → node4:9010 (prod yedek)
                   → minio-staging.teqlif.com → node3:9010 (staging)
```

### Servisler Arası İletişim (WireGuard)

| Gönderen | Alıcı | Protokol | Amaç |
|----------|-------|----------|------|
| gateway | node5:8000 | HTTP proxy | Production API trafiği |
| gateway | node3:8001 | HTTP proxy | Staging API trafiği |
| node5 API | node1:7880 | HTTP (LiveKit API) | Oda oluşturma, token üretme |
| node5 API | node4:7880 | HTTP (LiveKit API) | Oda oluşturma, token üretme |
| node5 API | node1:9010 | HTTP (S3) | Dosya yükleme/indirme |
| node5 API | node4:9010 | HTTP (S3) | Dosya yükleme/indirme |
| node5 API | node2:8080 | HTTP | AI çağrısı (primary) |
| node5 API | node3:8080 | HTTP | AI çağrısı (secondary) |
| node2 AI Proxy | node5:6379/1 | Redis | Rate limit sayacı |
| node3 AI Proxy (prod) | node5:6379/1 | Redis | Rate limit sayacı |
| node1 edge-metrics | node5:6379/1 | Redis | CPU/RAM/disk/net metrikleri |
| node4 edge-metrics | node5:6379/1 | Redis | CPU/RAM/disk/net metrikleri |
| promtail (tüm node'lar) | node3:3100 | HTTP | Log akışı → Loki |
| Prometheus (node3) | tüm node'lar:9100 | HTTP scrape | Sistem metrikleri |

### AI Proxy Cascade Fallback

```
node5 Backend AI isteği
  1. node2:8080  (primary — US IP, Groq + Gemini)
     ↓ başarısız olursa
  2. node3:8080  (secondary — US IP, Ashburn VA)
     ↓ başarısız olursa
  3. Local Groq fallback (node5 üzerinden direkt Groq API)
```

Kimlik doğrulama: `Authorization: Bearer <AI_PROXY_INTERNAL_TOKEN>`

### Analytics Veri Akışı (Redis Buffer → ClickHouse)

```
API router analytics event alır
  → Redis RPUSH ch_buf:<tablo>  [< 1ms, fire-and-forget]
      → Flush loop (her 30s VEYA 5000 satır dolunca)
          → ClickHouse batch INSERT INTO <tablo>
```

Buffer key'leri: `ch_buf:user_events`, `ch_buf:search_events`, `ch_buf:direct_sale_events`  
`feed_analytics` ve `swipe_live_events` → doğrudan batch INSERT (Redis buffer bypass).

### Webhook & Harici Entegrasyonlar

| Servis | Yön | Endpoint / Not |
|--------|-----|----------------|
| LiveKit (prod) | → Core API | `https://api.teqlif.com/api/webhooks/livekit` |
| LiveKit (staging) | → Staging API | `https://staging.teqlif.com/api/webhooks/livekit` |
| cf-failover (node2) | → Cloudflare API | Gateway DNS kaydı güncelleme |
| Alertmanager (node3) | → Telegram Bot | Alarm bildirimleri |
| FCM | → Android cihaz | Push notification |
| APNS | → iOS cihaz | VoIP push (CallKit) |
| Brevo | ← Core API | E-posta gönderimi |
| Sentry | ← Core/Mobil | Hata izleme |
| Groq API | ← node2/node3 | LLM inference |
| Gemini API | ← node2/node3 | LLM inference (US IP zorunlu) |

---

## 5. Technology Architecture

### Gateway

| Bileşen | Teknoloji | Notlar |
|---------|-----------|--------|
| L7 Proxy | **nginx** | `teqlif.com.conf` — 4 server block |
| SSL | **Cloudflare** | Full mode — nginx sadece :80 dinler |
| Log ajanı | **promtail** | systemd-journal → node3:3100 |
| Metrik | **node_exporter** | :9100 |

Nginx upstream'leri:
```nginx
upstream teqlif_core    { server 10.10.0.5:8000; }  # node5
upstream teqlif_staging { server 10.10.0.4:8001; }  # node3
```

### node1 & node4 (Edge — Medya Katmanı)

| Bileşen | Teknoloji | Port | Notlar |
|---------|-----------|------|--------|
| WebRTC SFU | **LiveKit** | 7880 (API), UDP 50000-60000 (medya), 7881 (Prometheus) | `/etc/livekit/livekit.yaml` |
| Object Storage | **MinIO Standalone** | 9010 (S3 API), 9011 (Console) | `/var/lib/minio`, %80 disk kotası |
| Edge cache | **Redis 7** | 127.0.0.1:6379 | ACL şifreli |
| Yük metrikleri | **edge-metrics-agent** | — | Python daemon, her 3s node5 Redis DB1'e yazar |
| Log ajanı | **promtail** | 9080 | → node3:3100 |
| Metrik | **node_exporter** | 9100 | |

**MinIO bucket yapısı:**
```
node1 MinIO:   teqlif (prod ana)    teqlif-dm (prod DM)
node4 MinIO:   teqlif               teqlif-dm           (aynı adlar, bağımsız instance)
node3 MinIO:   teqlif-staging       teqlif-dm-staging   (staging, ayrı)
```

### node2 (AI Proxy — Primary)

| Bileşen | Teknoloji | Port | Notlar |
|---------|-----------|------|--------|
| AI Gateway | **FastAPI** (uvicorn, 1 worker) | 8080 (bind: 10.10.0.3) | `app.ai_proxy_main:app` |
| DNS Failover | **cf-failover** (bash daemon) | — | Gateway çökerse CF DNS günceller |
| Log ajanı | **promtail** | 9080 | → node3:3100 |
| Metrik | **node_exporter** | 9100 | |

1 worker: RAM 1 GB sınırı nedeniyle — daha fazlası OOM riski taşır.

### node3 (Monitor & Staging — Çift Rol)

#### Staging Uygulaması
| Bileşen | Teknoloji | Port | Notlar |
|---------|-----------|------|--------|
| Staging API | **FastAPI** (uvicorn, 2 worker) | 8001 (bind: 10.10.0.4) | `TEQLIF_ENV_FILE=.env.staging` |
| Staging worker | **ARQ** | — | `teqlif-worker-staging` |
| Staging worker-critical | **ARQ** | — | `teqlif-worker-critical-staging` |
| AI Proxy (prod secondary) | **FastAPI** (uvicorn, 1 worker) | 8080 (bind: 10.10.0.4) | **Production** trafiği alır |
| Veritabanı | **PostgreSQL 16** | 127.0.0.1:5432 | DB: `teqlif_staging` |
| Cache | **Redis 7** | 127.0.0.1:6379 | Yalnızca staging — Core Redis'e bağlanmaz |
| WebRTC SFU | **LiveKit** | 7880, UDP 50000-60000 | AYRI key grubu (production'dan farklı) |
| Object Storage | **MinIO** | 9010 | bucket: teqlif-staging, teqlif-dm-staging |
| Analytics | **ClickHouse** | 127.0.0.1:8123 | DB: `teqlif_staging_analytics` |

#### Monitoring Stack
| Bileşen | Teknoloji | Port | Notlar |
|---------|-----------|------|--------|
| Metrik toplama | **Prometheus** | 9090 | 7 scrape hedefi (6 node + kendisi) |
| Log toplama | **Loki** | 3100 | 14 gün retention; tüm node'lar buraya gönderir |
| Dashboard | **Grafana** | 3000 | |
| Alarm yönetimi | **Alertmanager** | 9093 | Telegram webhook |
| Log ajanı | **promtail** | 9080 | Kendi loglarını `localhost:3100`'e gönderir |
| Metrik | **node_exporter** | 9100 | |

### node5 (Core — İşlem & Veri Merkezi)

| Bileşen | Teknoloji | Port | Notlar |
|---------|-----------|------|--------|
| Production API | **FastAPI** (uvicorn, 4 worker, uvloop) | 8000 (bind: 0.0.0.0) | `--proxy-headers`, trusted: 10.10.0.2 |
| Worker | **ARQ** | — | `teqlif-worker` (CPUWeight=50) |
| Worker-critical | **ARQ** | — | `teqlif-worker-critical` (öncelikli) |
| Veritabanı | **PostgreSQL 16 + pgvector** | 127.0.0.1:5432 | DB: `teqlif`, pool: max 20/overflow 10 |
| Core Cache | **Redis 7** | 10.10.0.5:6379 | 4 GB maxmemory, AOF+RDB hybrid, ACL şifreli |
| Analytics | **ClickHouse** | 127.0.0.1:8123 | DB: `teqlif_prod_analytics` |

**node5 Startup Sırası:**
```
teqlif.service
  ExecStartPre: alembic upgrade head     (DB migration — her seferinde çalışır)
  ExecStartPre: python sync_main.py      (ARB dosyaları → Redis/DB çeviri sync)
  ExecStart:    uvicorn main:app ...     (API server başlar)
  Wants:        teqlif-worker.service + teqlif-worker-critical.service
```

**ARQ Worker Kuyruğu:**
- `default` kuyruğu: `teqlif-worker` — genel arka plan görevleri
- `critical` kuyruğu: `teqlif-worker-critical` — öncelikli (bildirimler, ödeme, webhooks)

Worker'lar `BindsTo + PartOf teqlif.service` — API restart ettiğinde otomatik restart eder.

**Redis Key Namespace'leri:**
```
DB 0 — Uygulama
  session:<token>       → Kullanıcı session verileri
  i18n:pack:<lang>      → Çeviri paketleri (sync_main.py yazar)
  i18n:ver:<lang>       → Çeviri versiyon sayacı
  ch_buf:<tablo>        → ClickHouse batch buffer (analytics)
  (pubsub kanalları)    → Gerçek zamanlı olaylar

DB 1 — Operasyon
  rate:<endpoint>       → AI Proxy rate limit sayaçları (node2/node3 paylaşır)
  edge_metrics:<nodeX>  → edge-metrics-agent verileri (node1/node4 yazar, her 3s)
```

**Backend API Router Kategorileri (30 router):**
```
Auth:      auth, admin_auth, onboarding, verify
Listing:   listings, catalog, categories, field_config, edit_listing
Search:    search, search_alerts, competitor_radar, demand_trends
Social:    follows, favorites, ratings, reports, moderation
Commerce:  auction, direct_sale, ads, leads
Media:     calls, live_stream
Messaging: chat, messages, notifications
Analytics: analytics, feed, client_log
Config:    config, i18n, admin_data
```

### Mobil Uygulama

| Özellik | Değer |
|---------|-------|
| Framework | Flutter 3.x / Dart SDK ^3.11.0 |
| Hedef platform | iOS + Android (min SDK 21) |
| Versiyon | 1.1.3+18 |
| Durum yönetimi | flutter_riverpod 2.4.9 |
| Yerel depolama | Hive 2.2.3 (offline queue, cache) |
| Gerçek zamanlı | livekit_client 2.3.1 |
| Push (Android) | firebase_messaging 16.1.2 |
| Push (iOS VoIP) | flutter_callkit_incoming |
| Hata izleme | sentry_flutter 9.14.0 |
| CAPTCHA | cloudflare_turnstile 3.7.1 |
| Ses | audio_service |

---

## 6. Dependency Architecture

### Backend Python Kütüphaneleri

| Kategori | Kütüphane | Kullanım |
|----------|-----------|---------|
| Web Framework | `fastapi==0.115`, `uvicorn[standard]==0.30.6`, `uvloop` | ASGI |
| ORM / DB | `sqlalchemy[asyncio]==2.0.35`, `asyncpg==0.30.0`, `alembic==1.13.3` | PostgreSQL async |
| Cache / Queue | `redis>=5.1.1`, `arq==0.25.0` | Redis client + background task queue |
| Analytics | `clickhouse-connect==0.8.15` | ClickHouse HTTP driver |
| Auth | `python-jose[cryptography]`, `passlib[bcrypt]`, `bcrypt==4.0.1` | JWT + bcrypt |
| Storage | `minio>=7.2.0` | MinIO S3 client |
| AI / Vektör | `sentence-transformers==3.4.1`, `pgvector`, `faiss-cpu`, `implicit`, `scikit-learn` | Anlamsal arama, öneri |
| Görsel | `pillow==10.4.0`, `imagehash`, `nudenet` | Resim işleme, içerik moderasyonu |
| Push | `aioapns==3.2` | iOS APNS VoIP push (token-based) |
| LiveKit | `livekit-api==0.8.2` | Token üretme, oda yönetimi |
| HTTP | `httpx==0.27.2`, `aiohttp>=3.9.0` | Async dış servis çağrıları |
| Monitoring | `prometheus-fastapi-instrumentator`, `python-json-logger`, `sentry-sdk[fastapi]` | |
| Güvenlik | `slowapi==0.1.9`, `bleach==6.1.0`, `better-profanity`, `Babel>=2.14.0` | Rate limit, XSS, i18n |

requirements: `deploy/scale/V1.4/node5/resources/node5_production_requirements.txt`

### Üçüncü Taraf Servisler

| Servis | Kullanım | Credential |
|--------|----------|------------|
| **Cloudflare** | DNS, WAF, SSL proxy, CDN | CF_API_TOKEN, CF_ZONE_ID |
| **Groq API** | LLM inference | GROQ_API_KEY |
| **Google Gemini API** | LLM inference (US IP zorunlu) | GEMINI_API_KEY |
| **Firebase FCM** | Android push | `firebase-service-account.json` (git'e girmez) |
| **Apple APNS** | iOS VoIP push | `.p8` key — token-based |
| **Brevo** | E-posta | BREVO_API_KEY |
| **Sentry** | Hata izleme | SENTRY_BACKEND_DSN |
| **Google OAuth** | Sosyal giriş | GOOGLE_CLIENT_ID |
| **Cloudflare Turnstile** | CAPTCHA | CAPTCHA_SECRET_KEY |
| **Telegram Bot** | Alarm bildirimleri | TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID |

Kritik dosya konumları:
```
/var/www/teqlif.com/backend/firebase-service-account.json   (git'e gitmez — .gitignore'da)
APNS .p8 key                                                 (node5'te güvenli konumda)
```

---

## 7. Topology Architecture

### Sistem Topoloji Diyagramı

```
                    ┌──────────────────────────────────┐
                    │         CLOUDFLARE EDGE           │
                    │   WAF · SSL/TLS · DNS Routing     │
                    └───┬──────┬──────┬─────┬───────────┘
                        │      │      │     │
                   Proxied  DNS Only DNS   Proxied
                 (api,teqlif) (live) (minio) (staging)
                        │      │      │     │
                        │   node1/4  node1/4  │
                        │   direkt   direkt   │
                        │                    │
               ┌────────▼────────────────────▼──────┐
               │          GATEWAY (nginx)             │
               │          10.10.0.2  :80/443          │
               │  → teqlif_core    10.10.0.5:8000    │
               │  → teqlif_staging 10.10.0.4:8001    │
               └─────────────────┬──────────────────┘
                                  │ WireGuard wg0
                    ┌─────────────┼──────────────┐
                    │             │              │
           ┌────────▼──────┐      │     ┌────────▼──────┐
           │ NODE1 — EDGE1  │      │     │ NODE4 — EDGE2  │
           │ 10.10.0.1      │      │     │ 10.10.0.6      │
           │ LiveKit :7880  │      │     │ LiveKit :7880  │
           │ MinIO :9010    │      │     │ MinIO :9010    │
           │ Redis :6379    │      │     │ Redis :6379    │
           │ edge-metrics   │      │     │ edge-metrics   │
           └───────┬────────┘      │     └──────┬─────────┘
                   │               │            │
                   └──────────┐    │   ┌────────┘
                              │    │   │
                     ┌────────▼────▼───▼──────┐
                     │      NODE5 — CORE        │
                     │      10.10.0.5           │
                     │  FastAPI :8000 (4w)      │
                     │  PostgreSQL :5432        │
                     │  ClickHouse :8123        │
                     │  Redis Core :6379 ◄──────┼── node2/node3 AI Proxy (rate limit)
                     │  ARQ Workers             │   node1/node4 edge-metrics
                     └──────────────────────────┘

 ┌──────────────────────────────────────────────────────────────────┐
 │  NODE3 — MONITOR & STAGING  10.10.0.4  (public: 5.249.165.10)   │
 │                                                                  │
 │  [STAGING — tam izole]              [MONITORING]                 │
 │  FastAPI staging :8001          Prometheus :9090                 │
 │  ARQ Workers (staging)          Loki :3100 ◄── tüm node'lar     │
 │  PostgreSQL :5432 (staging)     Grafana :3000                   │
 │  ClickHouse :8123 (staging)     Alertmanager :9093 → Telegram   │
 │  Redis :6379 (staging)                                          │
 │  LiveKit :7880 (STAGING KEY)    [AI PROXY — PROD SECONDARY]    │
 │  MinIO :9010 (staging)          FastAPI :8080 (prod trafiği)   │
 └──────────────────────────────────────────────────────────────────┘

 ┌───────────────────────────────────────┐
 │  NODE2 — AI PROXY 1  10.10.0.3 (US IP) │
 │  FastAPI ai-proxy :8080 (primary)      │
 │  cf-failover (bash daemon)             │
 └───────────────────────────────────────┘
```

### LiveKit Key Grupları

| Grup | Hangi Node'lar | Webhook |
|------|----------------|---------|
| **Production** | node1 livekit.yaml + node4 livekit.yaml + node5 .env.production — **aynı key** | `api.teqlif.com/api/webhooks/livekit` |
| **Staging** | node3 livekit.yaml + node3 .env.staging — **farklı key** | `staging.teqlif.com/api/webhooks/livekit` |

Production ve staging key'leri asla karışmamalı. Karışırsa staging odası production'ı etkiler.

### MinIO Credential Eşitliği

```
node1 MINIO_ROOT_USER     == node4 MINIO_ROOT_USER     == node5 MINIO_ACCESS_KEY
node1 MINIO_ROOT_PASSWORD == node4 MINIO_ROOT_PASSWORD == node5 MINIO_SECRET_KEY
```

MinIO'da `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` hem sunucu root hem de uygulama client credential görevi görür. node5 API node1/node4 MinIO'ya bu kimliklerle bağlanır.  
node3 staging MinIO bağımsız credential kullanır (staging izolasyonu).

---

## 8. Configuration Architecture

### .env Dosya Yapısı

| Node | Env Dosyası | Şablon |
|------|-------------|--------|
| node5 | `.env.production` | `V1.4/node5/resources/.env.production.template` |
| node1 | `.env.production` | `V1.4/node1/resources/.env.production.template` |
| node2 | `.env.production` | `V1.4/node2/resources/.env.production.template` |
| node3 (prod AI proxy) | `.env.production` | `V1.4/node3/resources/.env.production.template` |
| node3 (staging) | `.env.staging` | `V1.4/node3/resources/.env.staging.template` |
| node4 | `.env.production` | `V1.4/node4/resources/.env.production.template` |

Hangi .env yükleneceği: `TEQLIF_ENV_FILE` ortam değişkeni — systemd service dosyasındaki `Environment=TEQLIF_ENV_FILE=.env.staging` belirler.  
Kod: `backend/app/config.py` → `env_file=os.environ.get("TEQLIF_ENV_FILE", ".env.production")`

**.env dosyaları `.gitignore`'da — git'e gitmez.**

### /etc/ Config Dosyaları

Bootstrap'ta bir kez kopyalanır. `teqlif-restart` bunlara **dokunmaz**. Manuel değişiklik gerekir.

| Dosya | Node | Kaynak |
|-------|------|--------|
| `/etc/livekit/livekit.yaml` | node1, node3, node4 | `V1.4/<node>/resources/livekit.yaml` |
| `/etc/prometheus/prometheus.yml` | node3 | `V1.4/node3/resources/prometheus.yml` |
| `/etc/prometheus/prometheus-rules.yml` | node3 | `V1.4/node3/resources/prometheus-rules.yml` |
| `/etc/alertmanager/alertmanager.yml` | node3 | `alertmanager.yml.template` (envsubst ile .env'den) |
| `/etc/loki/config.yml` | node3 | `V1.4/node3/resources/loki-config.yml` |
| `/etc/promtail-config.yml` | tüm node'lar | `V1.4/<node>/resources/promtail-config.yml` |
| `/etc/nginx/sites-available/teqlif.com.conf` | gateway | `V1.4/gateway/resources/teqlif.com.conf` |
| `/etc/redis/redis.conf` | node1/3/4/5 | bootstrap'ta `requirepass` eklenir |

### teqlif-restart Davranışı

```
[1/2] git pull --ff-only
[2/2] systemctl restart <node servisleri> + durum tablosu (PID, RAM, Uptime)
```

Config kopyalanmaz. .env ezilmez. Yalnızca servisler restart edilir.

### Systemd Servis Bağımlılıkları (node5)

```
teqlif.service
  ExecStartPre: alembic upgrade head
  ExecStartPre: python sync_main.py
  Wants: teqlif-worker.service, teqlif-worker-critical.service

teqlif-worker.service        → BindsTo + PartOf teqlif.service
teqlif-worker-critical.service → BindsTo + PartOf teqlif.service
```

`sudo systemctl restart teqlif` komutu 3 servisi birlikte restart eder.  
(node3 staging'de aynı pattern: `teqlif-staging.service`, `teqlif-worker-staging.service`, `teqlif-worker-critical-staging.service`)

### Bootstrap Akışı

```bash
git clone https://github.com/tucibeyin/teqlif.git /tmp/teqlif
cd /tmp/teqlif/deploy/scale/V1.4/<node>/resources/
sudo bash bootstrap_<node>.sh
```

Bootstrap: apt kurulum → UFW → WireGuard (key üretir, public key'i ekrana yazar) → ikili dosyalar → systemd → .env şablonu kopyalama → teqlif-restart kurulumu → servisleri başlatma

**teqlif-restart kurulumu:** `bootstrap_nodeX.sh` scripti, `teqlif-restart.sh` içindeki `__REPO_DIR__` placeholder'ını gerçek repo yoluyla değiştirerek hem `/usr/local/bin/` hem `/usr/local/sbin/` konumuna kurar.

---

## 9. Servis Dağılım Matrisi

| Servis | gateway | node1 | node2 | node3 | node4 | node5 |
|--------|:-------:|:-----:|:-----:|:-----:|:-----:|:-----:|
| **nginx (L7 Proxy)** | ✓ | — | — | — | — | — |
| **FastAPI Production** | — | — | — | — | — | ✓ :8000 |
| **FastAPI Staging** | — | — | — | ✓ :8001 | — | — |
| **ARQ Worker (prod)** | — | — | — | — | — | ✓ ×2 |
| **ARQ Worker (staging)** | — | — | — | ✓ ×2 | — | — |
| **AI Proxy** | — | — | ✓ primary | ✓ secondary (prod) | — | — |
| **PostgreSQL** | — | — | — | ✓ staging | — | ✓ prod |
| **ClickHouse** | — | — | — | ✓ staging | — | ✓ prod |
| **Redis** | — | ✓ cache | — | ✓ staging | ✓ cache | ✓ core |
| **LiveKit SFU** | — | ✓ prod | — | ✓ staging | ✓ prod | — |
| **MinIO** | — | ✓ prod | — | ✓ staging | ✓ prod | — |
| **edge-metrics-agent** | — | ✓ | — | — | ✓ | — |
| **cf-failover** | — | — | ✓ | — | — | — |
| **Prometheus** | — | — | — | ✓ | — | — |
| **Loki** | — | — | — | ✓ | — | — |
| **Grafana** | — | — | — | ✓ | — | — |
| **Alertmanager** | — | — | — | ✓ | — | — |
| **node_exporter** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **promtail** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## 10. Port Haritası

### Public Portlar (Dış Dünyaya Açık)

| Port | Protokol | Servis | Node | Cloudflare |
|------|----------|--------|------|-----------|
| 80 | TCP | nginx HTTP | gateway | Proxied — CF'den gelir |
| 443 | TCP | nginx HTTPS | gateway | Proxied — CF SSL sonlandırır |
| 9010 | TCP | MinIO S3 API | node1, node4 | DNS Only — direkt |
| 9011 | TCP | MinIO Console | node1, node3, node4 | DNS Only |
| 7880 | TCP | LiveKit API/WS | node1, node3, node4 | DNS Only — direkt |
| 7882 | TCP/UDP | LiveKit TURN | node1, node3, node4 | DNS Only |
| 5349 | TCP | LiveKit TURN TLS | node3 | — |
| 3478 | UDP | STUN | node3 | — |
| 50000-60000 | UDP | LiveKit WebRTC medya | node1, node3, node4 | DNS Only |

### İç Portlar (Yalnızca WireGuard / Localhost)

| Port | Servis | Bind | Erişen |
|------|--------|------|--------|
| 8000 | FastAPI prod | 0.0.0.0 (wg0 üzerinden) | gateway nginx |
| 8001 | FastAPI staging | 10.10.0.4 | gateway nginx |
| 8080 | AI Proxy | node2:10.10.0.3, node3:10.10.0.4 | node5 backend |
| 5432 | PostgreSQL | 127.0.0.1 | Yalnızca lokal (API/worker) |
| 6379 | Redis Core | 10.10.0.5 | node5 API, node2/3 AI proxy, edge-metrics |
| 6379 | Redis Edge | 127.0.0.1 (node1, node4) | Yalnızca lokal LiveKit/cache |
| 6379 | Redis Staging | 127.0.0.1 (node3) | Yalnızca staging |
| 8123 | ClickHouse HTTP | 127.0.0.1 | Yalnızca lokal API |
| 9000 | ClickHouse Native | 127.0.0.1 | — |
| 9090 | Prometheus | 127.0.0.1 | Grafana |
| 3100 | Loki | 0.0.0.0 (wg0 erişilebilir) | Tüm node'lar promtail |
| 3000 | Grafana | — | WireGuard üzerinden erişim |
| 9093 | Alertmanager | 127.0.0.1 | Prometheus |
| 9100 | node_exporter | 0.0.0.0 (wg0 üzerinden) | node3 Prometheus |
| 9080 | promtail | 127.0.0.1 | — |
| 7881 | LiveKit Prometheus | — | node3 Prometheus |

---

## 11. DNS & Cloudflare Yapısı

### Cloudflare DNS Kayıtları

| Alt Alan | Hedef Node | Proxied | Trafik Türü |
|----------|-----------|---------|-------------|
| `teqlif.com` | gateway | ✓ Proxied | Frontend |
| `www.teqlif.com` | gateway | ✓ Proxied | |
| `api.teqlif.com` | gateway | ✓ Proxied | REST API |
| `staging.teqlif.com` | gateway | ✓ Proxied | Staging frontend |
| `api-staging.teqlif.com` | gateway | ✓ Proxied | Staging REST API |
| `live1.teqlif.com` | node1 public IP | ✗ DNS Only | LiveKit prod (node1) |
| `live2.teqlif.com` | node4 public IP | ✗ DNS Only | LiveKit prod (node4) |
| `minio1.teqlif.com` | node1 public IP | ✗ DNS Only | MinIO prod (node1) |
| `minio2.teqlif.com` | node4 public IP | ✗ DNS Only | MinIO prod (node4) |
| `live-staging.teqlif.com` | 5.249.165.10 (node3) | ✗ DNS Only | LiveKit staging |
| `minio-staging.teqlif.com` | 5.249.165.10 (node3) | ✗ DNS Only | MinIO staging |

### Nginx Server Block Özeti

```
server: teqlif.com / www.teqlif.com  → upstream teqlif_core    (10.10.0.5:8000)
server: api.teqlif.com               → upstream teqlif_core
server: staging.teqlif.com           → upstream teqlif_staging  (10.10.0.4:8001)
server: api-staging.teqlif.com       → upstream teqlif_staging
```

CF Real IP: `CF-Connecting-IP` header → nginx `set_real_ip_from` (Cloudflare CIDR listesi)

### cf-failover (node2)

Bash daemon, gateway'i periyodik ping atar. Gateway erişilemez olursa Cloudflare API üzerinden `api.teqlif.com` DNS kaydını günceller.

---

## 12. Güvenlik Mimarisi

### Katmanlı Savunma Modeli

```
Katman 1: Cloudflare WAF + DDoS filtresi
Katman 2: nginx rate limiting + .env/.git erişim engeli
Katman 3: WireGuard şifreli mesh (iç trafik)
Katman 4: UFW — DB portları (5432, 6379, 8123) dışa kapalı
Katman 5: Redis ACL şifresi
Katman 6: JWT Bearer token (API auth)
Katman 7: AI_PROXY_INTERNAL_TOKEN (AI proxy iç auth)
Katman 8: fail2ban (SSH brute force)
```

### Kimlik Doğrulama Akışları

| Akış | Yöntem |
|------|--------|
| Kullanıcı → REST API | Cloudflare Turnstile (CAPTCHA) + JWT Bearer |
| LiveKit webhook → API | LiveKit imzalı webhook token |
| node5 → AI Proxy | `Authorization: Bearer AI_PROXY_INTERNAL_TOKEN` |
| edge-metrics → Redis Core | Redis ACL şifre + DB 1 |
| Prometheus → node_exporter | Açık (WireGuard korumasında) |

### Credential Kuralları

| Kural | Açıklama |
|-------|---------|
| WireGuard private key | **GIT'E GİTMEZ** — node'da `wg genkey` ile üretilir |
| .env dosyaları | **GIT'E GİTMEZ** — `.gitignore`'da |
| `firebase-service-account.json` | **GIT'E GİTMEZ** — `.gitignore`'da |
| `AI_PROXY_INTERNAL_TOKEN` | node2 + node3 (her iki .env) + node5 — 4 dosyada aynı değer |
| LiveKit production key | node1 yaml == node4 yaml == node5 .env.production |
| LiveKit staging key | node3 yaml == node3 .env.staging — production'dan **FARKLI** |
| MinIO prod creds | node1 == node4 == node5 — aynı kullanıcı/şifre |

---

## 13. Monitoring & Observability

### Monitoring Mimarisinin Mantığı

```
Her node'da: node_exporter (sistem metrikleri) + promtail (sistem logları)
                  ↓                                        ↓
node3 Prometheus (metrik scraping)          node3 Loki (log aggregation)
                  ↓                                        ↓
            Alertmanager                          Grafana dashboards
                  ↓
            Telegram Bot
```

### Prometheus Scrape Hedefleri

| Job Adı | Adres | Ne Ölçülür |
|---------|-------|-----------|
| prometheus (kendisi) | localhost:9090 | Prometheus iç metrikleri |
| node-gateway | 10.10.0.2:9100 | gateway sistem |
| node-node1 | 10.10.0.1:9100 | node1 sistem |
| node-node2 | 10.10.0.3:9100 | node2 sistem |
| node-node3 | 10.10.0.4:9100 | node3 sistem |
| node-node4 | 10.10.0.6:9100 | node4 sistem |
| node-node5 | 10.10.0.5:9100 | node5 sistem |

Config: `/etc/prometheus/prometheus.yml`  
Rules: `/etc/prometheus/prometheus-rules.yml` (**tekil dosya** — `/etc/prometheus/rules/*.yml` değil)

### Alarm Kuralları

| Alert | Eşik | Süre | Severity |
|-------|------|------|----------|
| NodeDown | `up == 0` | 1 dakika | critical |
| HighMemoryUsage | RAM > %85 | 5 dakika | warning |
| DiskSpaceLow | Disk > %80 | 5 dakika | warning |
| HighSwapUsage | Swap > %50 | 5 dakika | warning |
| HighCPULoad | CPU > %90 | 10 dakika | warning |
| AIProxyDown | node2 AI proxy inactive | 1 dakika | critical |
| AIProxySecondaryDown | node3 AI proxy inactive | 1 dakika | warning |

Bildirim: Telegram Bot. Config: `/etc/alertmanager/alertmanager.yml`  
Group wait: 30s | Repeat interval: 4h

### Loki Log Yapısı

| Node | promtail hedefi | Label |
|------|----------------|-------|
| gateway | → 10.10.0.4:3100 | `node: gateway` |
| node1 | → 10.10.0.4:3100 | `node: node1` |
| node2 | → 10.10.0.4:3100 | `node: node2` |
| node3 | → localhost:3100 | `node: node3` |
| node4 | → 10.10.0.4:3100 | `node: node4` |
| node5 | → 10.10.0.4:3100 | `node: node5` |

Retention: 14 gün (336h), TSDB v13

---

## 14. Kritik Yapılandırma Notları

### ClickHouse Veritabanı İzolasyonu

| Ortam | Node | DB Adı | Tablolar |
|-------|------|--------|---------|
| Production | node5 | `teqlif_prod_analytics` | user_events, feed_analytics, search_events, swipe_live_events, direct_sale_events |
| Staging | node3 | `teqlif_staging_analytics` | (aynı 5 tablo) |

`default` DB **kullanılmaz.**

**Önemli bug:** Backend `init_clickhouse()` fonksiyonu tabloları `database` parametresi belirtmeden bağlanır → `default` DB'ye yazar. Çözüm: tablolar bootstrap'ta doğru DB içinde elle oluşturulur. `get_clickhouse_client()` ise `settings.clickhouse_db` kullanır — doğru DB'ye okur/yazar.

### node3 Zap-Hosting Panel Zorunluluğu

Panel'e **90 günde bir manuel giriş zorunlu.** Giriş yapılmazsa VM RAM'i 1.8 GB'a düşürülür (balloon).  
Son giriş: 2026-09-11 → **Sonraki deadline: 2026-12-10**

### gateway Bant Genişliği Limiti

Netcup 24 saatlik ortalama 100Mbps throttle. Bu yüzden medya subdomainleri (uploads/live/minio) DNS Only ile gateway'i atlar.

### Redis Core Mesh Erişimi

node5 Redis `10.10.0.5:6379` — WireGuard üzerinden node2 ve node3 AI Proxy bağlanabilir.  
UFW kuralı: Yalnızca `wg0` interface'inden 6379 portuna giriş.

### AI_PROXY_INTERNAL_TOKEN Tutarlılığı

```
node2/.env.production    → AI_PROXY_INTERNAL_TOKEN=X
node3/.env.production    → AI_PROXY_INTERNAL_TOKEN=X
node3/.env.staging       → AI_PROXY_INTERNAL_TOKEN=X  (staging da aynı token)
node5/.env.production    → AI_PROXY_INTERNAL_TOKEN=X
```

4 dosyada aynı değer olmalı. Biri değişirse diğerleri de güncellenmeli.

### alembic Kısıtlamaları

- Multi-statement SQL yasak: Her komut ayrı `op.execute()` (asyncpg prepared statement sınırı)
- `CREATE INDEX CONCURRENTLY` yasak: transaction içinde çalışamaz
- revision ID ≤ 32 karakter
- Staging DB ilk kurulumda: `pg_dump --schema-only` + `alembic stamp head` (alembic upgrade head bozuk başlangıç)

---

## 15. Operasyon Rehberi

### Tek Komutla Stack Restart

```bash
sudo teqlif-restart
```

Her node'da çalışır. WireGuard IP'sini okuyarak kendini tespit eder → git pull → servisleri restart eder → durum tablosu.

### Servis Logları

```bash
journalctl -u teqlif -f                    # prod API (node5)
journalctl -u teqlif-worker -f             # prod worker (node5)
journalctl -u teqlif-staging -f            # staging API (node3)
journalctl -u teqlif-ai-proxy -f           # AI proxy
journalctl -u livekit -f                   # LiveKit
journalctl -u prometheus -f                # Prometheus
```

### .env Manuel Düzenleme

```bash
nano /var/www/teqlif.com/backend/.env.production   # veya .env.staging
sudo systemctl restart <etkilenen-servis>
```

/etc/ config dosyaları için:
```bash
nano /etc/livekit/livekit.yaml
sudo systemctl restart livekit
```

### Monitoring Erişimi (WireGuard ile)

```
Grafana:      http://10.10.0.4:3000
Prometheus:   http://10.10.0.4:9090
Alertmanager: http://10.10.0.4:9093
Loki:         http://10.10.0.4:3100
```

### ClickHouse'a Bağlanma

```bash
# node5 — production
clickhouse-client --database teqlif_prod_analytics

# node3 — staging
clickhouse-client --database teqlif_staging_analytics
```

### WireGuard Onarımı

```bash
sudo bash /var/www/teqlif.com/deploy/scale/V1.4/scripts/repair_wireguard.sh
```

### Sistem Sağlık Testi

```bash
bash /var/www/teqlif.com/deploy/scale/V1.4/scripts/test_all.sh
```

Test kapsamı: auth bypass denemeleri, port izolasyonu, Redis auth, .env erişim engeli, OOM/Swap durumu.

### Yeni Node Bootstrap (Sıfırdan Kurulum)

```bash
git clone https://github.com/tucibeyin/teqlif.git /tmp/teqlif
cd /tmp/teqlif/deploy/scale/V1.4/<node>/resources/
sudo bash bootstrap_<node>.sh
# → WireGuard public key'i diğer node'lara elle ekle
# → .env şablonundan üret ve değerleri doldur
# → node5 ise: firebase-service-account.json'u kopyala
```

---

*Son güncelleme: 2026-09-19 · deploy/scale/V1.4/documents/final_V1.4.md*
