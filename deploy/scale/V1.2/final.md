# Teqlif Scale V1.2 — Kapsamlı Mimari ve Uygulama Belgesi

> **Uygulama tarihi:** 2026-09-10  
> **Durum:** Aktif (production)  
> **Önceki sürüm:** `deploy/scale/V1.1/`  
> **Kaynak dosyalar:** `deploy/scale/V1.2/`, `deploy/scale/resources/`

---

## 1. Genel Bakış

Scale V1.2, V1.1 üzerine tek büyük mimari genişlemedir: **node2 (AI Proxy)** eklenir. Temel motivasyon, Groq API'sinin Avrupa IP'lerinden Gemini API'ye erişiminin kısıtlı olması ve AI açıklama üretiminde Gemini'nin devreye alınmak istenmesidir. node2, ABD IP'sine sahip VPSHostingService.co Buffalo sunucusudur; hem Groq hem Gemini'ye tam erişimi vardır.

### V1.2 ile gelen değişiklikler

| # | Değişiklik | Etki |
|---|---|---|
| 1 | node2 (VPSHostingService Buffalo) eklendi | AI proxy — Groq + Gemini desteği |
| 2 | `llm_service.py` yeniden yazıldı | Stateless registry, non-streaming, autonomous model discovery |
| 3 | Redis shared exhaustion state | node1 ve node2 aynı Groq key'i için 429 bilgisini paylaşır |
| 4 | `InMemoryCircuitBreaker` eklendi | Redis erişimi kesilse bile llm_service bozulmaz |
| 5 | `ai_proxy_client.py` eklendi | node1 → node2 yönlendirme + otomatik lokal fallback |
| 6 | `ai_proxy_main.py` eklendi | node2'nin çalıştırdığı minimal FastAPI uygulaması |
| 7 | SSE → JSON geçişi | Listing açıklama endpoint'i stream yerine tam JSON döner |
| 8 | Flutter `AiDescNotifier` MVVM | Typewriter animasyonu View'da, iş mantığı ViewModel'de |
| 9 | WireGuard 3-node mesh | node1 ↔ node2 ↔ gateway tam bağlantı |
| 10 | `deploy/scale/resources/` | Tüm `.env` şablonları ve requirements tek dizinde — version-independent |
| 11 | Bootstrap scriptleri | Her node için idempotent kurulum scripti |
| 12 | `TEQLIF_ENV_FILE` env var | `config.py` artık env dosya yolunu env var'dan okur |
| 13 | Tüm servisler `tucibeyin` kullanıcısına standardize edildi | node_exporter, promtail, prometheus, loki |
| 14 | Systemd servis optimizasyonları | LimitNOFILE, OOMScoreAdj, TimeoutStopSec, CPUWeight, MemoryMax |
| 15 | PostgreSQL tuning | shared_buffers 2GB, work_mem 16MB, NVMe planner (random_page_cost=1.1) |
| 16 | Kernel sysctl — tüm node'lar | swappiness, somaxconn, tcp_syn_backlog, tcp_tw_reuse |
| 17 | nginx optimizasyonu | worker_connections 4096, gzip tam config, ssl_session_cache, open_file_cache |
| 18 | journald limitleri | Her node'da disk kullanımı sınırlandırıldı |
| 19 | node1 nginx fallback (port 443) | Gateway down → CF doğrudan node1'e → uvicorn:8000 |
| 20 | Cloudflare DNS failover otomasyonu | node2 cf-failover daemon: 30s içinde DNS A → node1, geri dönüş otomatik |
| 21 | Bootstrap script'leri güncellendi | sysctl, journald, nginx fallback, cf-failover kurulumu otomasyona eklendi |

---

## 2. Donanım

### node1 — OVHcloud Frankfurt (Ana Backend)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **OVHcloud SAS** (FR) |
| Lokasyon | Frankfurt, Almanya |
| Public IP | 135.125.175.223 |
| WireGuard IP | 10.10.0.1 |
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 2 GiB Swap |
| Disk | 98.3 GiB NVMe |
| Ağ | **2 Gbps / unmetered** (kota yok) |
| SSH alias | `teqlif-node1` |

### gateway — netcup GmbH Nürnberg (Edge Proxy + Observability)

| Parametre | Değer |
|---|---|
| Sağlayıcı | **netcup GmbH** (DE) |
| Lokasyon | Nürnberg, Almanya |
| Public IP | 94.16.105.135 |
| WireGuard IP | 10.10.0.2 |
| CPU | 2 vCore (QEMU @ 2.29 GHz) |
| RAM | 2 GB + 1 GB Swap |
| Disk | 60 GB SSD |
| Ağ | 1 Gbps — **24h ortalama >100 Mbps → throttle** |
| SSH alias | `teqlif-gateway` |

### node2 — VPSHostingService.co Buffalo (AI Proxy) ← **V1.2'de eklendi**

| Parametre | Değer |
|---|---|
| Sağlayıcı | **VPSHostingService.co** (US) |
| Lokasyon | Buffalo, New York, ABD |
| Public IP | 198.12.123.33 |
| WireGuard IP | 10.10.0.3 |
| CPU | 1 vCore |
| RAM | 1 GB |
| Disk | 25 GB SSD |
| Ağ | ABD IP — Gemini API tam erişim |
| SSH alias | `teqlif-node2` |
| Hostname | `node2` |

**node2 seçim gerekçesi:** Groq API, Avrupa IP'lerinden Gemini endpoint'lerine kısıtlı erişim sağlar. node2 ABD IP'si sayesinde Gemini model listesini tam olarak keşfeder ve kullanır. node1 EU IP'siyle registry'de Gemini sonuçları boş döner — bu beklenen ve tasarım gereği davranıştır.

---

## 3. Topoloji ve Trafik Akışı

```
                    ┌─────────────────────────────────────────────┐
 İnternet           │           CLOUDFLARE EDGE                   │
                    │  (DDoS koruma, SSL proxy, CDN cache)        │
                    └──────────────┬──────────────────────────────┘
                                   │ HTTPS
                    ┌──────────────▼──────────────────────────────┐
                    │     gateway (netcup GmbH, 94.16.105.135)     │
                    │                                              │
                    │  nginx (SSL termination, rate limit,         │
                    │         microcaching)                        │
                    │  WireGuard (10.10.0.2)                       │
                    │  Prometheus  :9090                           │
                    │  Alertmanager :9093                          │
                    │  Loki        :3100  ← node1 + node2 push    │
                    │  promtail    → Loki (kendi logları)          │
                    │  node_exporter :9100                         │
                    └──────┬───────────────────────┬──────────────┘
                           │ WireGuard             │ WireGuard
              ┌────────────▼────────────┐  ┌───────▼─────────────────────┐
              │  node1 (OVHcloud, FR)   │  │  node2 (VPSHostingService.co, US)   │
              │                         │  │               ← V1.2        │
              │  FastAPI prod   :8000    │  │  AI Proxy  :8080            │
              │  FastAPI staging:8001    │  │    /generate (POST)         │
              │  PostgreSQL     :5432    │  │    /health  (GET)           │
              │  Redis          :6379    │◄─┤  Groq API (EU kısıtısız)   │
              │  MinIO          :9010    │  │  Gemini API (ABD IP)        │
              │  ClickHouse     :8123    │  │  node_exporter  :9100       │
              │  LiveKit SFU    :7880+   │  │  promtail → gateway:3100    │
              │  ARQ Workers             │  │  WireGuard (10.10.0.3)      │
              │  WireGuard (10.10.0.1)  │  └─────────────────────────────┘
              │  node_exporter  :9100    │
              │  promtail → gateway:3100 │
              └─────────────────────────┘
```

### AI Açıklama Üretim Akışı (V1.2)

```
Mobil → POST /api/listings/generate-description
  └─ node1: listings.py → generate_via_node2(params)
       └─ node2_ai_proxy_url doluysa:
            POST http://10.10.0.3:8080/generate
              X-Internal-Token: NODE2_INTERNAL_TOKEN
              timeout: 45s
            └─ node2: ai_proxy_main.py
                 └─ generate_listing_description(...)
                      ├─ Groq modelleri dene (registry sırası)
                      └─ Gemini modelleri dene (Groq exhausted ise)
       └─ node2 down / timeout → lokal Groq fallback (node1)
```

### Fallback Zinciri

```
node2 (Groq + Gemini)
    ↓  down / timeout / 503
node1 (Groq only — EU IP, Gemini çalışmaz)
    ↓  tüm Groq modelleri exhausted
AIServiceBusyException (503)
```

---

## 4. Servis Dağılımı

| Servis | node1 | gateway | node2 | Gerekçe |
|---|---|---|---|---|
| FastAPI prod (:8000) | ✅ | ❌ | ❌ | PostgreSQL/Redis yakınlığı |
| FastAPI staging (:8001) | ✅ | ❌ | ❌ | Aynı ortam, `.env.node1.staging` ile ayrılır |
| PostgreSQL | ✅ | ❌ | ❌ | Disk I/O + worker erişimi |
| Redis | ✅ | ❌ | ❌ | node2 WireGuard üzerinden bağlanır |
| MinIO | ✅ | ❌ | ❌ | Disk + OVHcloud unmetered bant |
| ClickHouse | ✅ | ❌ | ❌ | RAM yoğun |
| LiveKit SFU | ✅ | ❌ | ❌ | UDP medya + OVHcloud unmetered |
| ARQ Worker (genel) | ✅ | ❌ | ❌ | ML + DB/ClickHouse erişimi |
| ARQ Worker (critical) | ✅ | ❌ | ❌ | Bulkhead pattern |
| **AI Proxy (:8080)** | ❌ | ❌ | ✅ | **Gemini ABD IP gereksinimi ← V1.2** |
| nginx (public SSL) | ❌ | ✅ | ❌ | Edge proxy rolü |
| nginx (fallback, port 443) | ✅ | ❌ | ❌ | CF failover — gateway down → node1 direkt ← V1.2 |
| nginx (uploads) | ✅ | ❌ | ❌ | uploads.teqlif.com → MinIO |
| Prometheus | ❌ | ✅ | ❌ | Observability bağımsızlığı |
| Alertmanager | ❌ | ✅ | ❌ | Prometheus alerts → Telegram |
| Loki | ❌ | ✅ | ❌ | 60 GB SSD |
| promtail | ✅ | ✅ | ✅ | Her node — gateway Loki'ye push |
| node_exporter | ✅ | ✅ | ✅ | Her node |
| WireGuard | ✅ (10.10.0.1) | ✅ (10.10.0.2) | ✅ (10.10.0.3) | 3-node mesh ← V1.2 |

---

## 5. WireGuard 3-Node Mesh (V1.2)

```
node1  10.10.0.1  135.125.175.223:51820  ListenPort: 51820
gateway 10.10.0.2  94.16.105.135:51820   ListenPort: 51820
node2  10.10.0.3  198.12.123.33:51820   ListenPort: 51820
```

Her node diğer ikisine de peer tanımlar. PersistentKeepalive: 25s (tüm bağlantılar).

**Konfigürasyon dosyaları:**
- `deploy/scale/V1.2/wireguard/` — şablonlar (private key hariç, git'e girmez)
- Her node'da `/etc/wireguard/wg0.conf` — gerçek config (sunucularda)

**node1 ↔ node2 gecikme:** ~100ms (OVHcloud Frankfurt ↔ VPSHostingService.co Buffalo)

---

## 6. node2 AI Proxy

### Servis Konfigürasyonu

`deploy/scale/V1.2/node2/systemd/teqlif-ai-proxy.service`

```
WorkingDirectory: /var/www/teqlif.com/backend
ExecStart: /var/www/teqlif.com/venv/bin/uvicorn app.ai_proxy_main:app
           --host 10.10.0.3 --port 8080 --workers 1 --loop uvloop
Environment: TEQLIF_ENV_FILE=/var/www/teqlif.com/deploy/scale/resources/.env.node2.production
EnvironmentFile: (aynı dosya)
```

**Neden `--workers 1`:** node2 düşük RAM'e sahip (1 GB). AI çağrıları I/O-bound — tek worker yeterli.

### Endpoint'ler

| Method | Path | Açıklama |
|---|---|---|
| POST | `/generate` | AI açıklama üretimi — `X-Internal-Token` header zorunlu |
| GET | `/health` | Servis sağlık kontrolü |

### Authentication

`X-Internal-Token: NODE2_INTERNAL_TOKEN` — node1 ve node2 aynı değeri paylaşır. Sır yönetimi:
- `deploy/scale/resources/.env.node1.production` → `NODE2_INTERNAL_TOKEN=...`
- `deploy/scale/resources/.env.node2.production` → `NODE2_INTERNAL_TOKEN=...`
- Üretim: `openssl rand -hex 32`

### node2 Python Ortamı

node2 sadece AI proxy çalıştırır — ML/DB/LiveKit/MinIO paketleri yüklenmez.

```
Venv: /var/www/teqlif.com/venv/  (tüm node'lar için standart konum)
Requirements: deploy/scale/resources/node2_production_requirements.txt
Paketler (7): fastapi, uvicorn[standard], httpx, redis, sentry-sdk,
              pydantic-settings, python-dotenv
Boyut: ~30 MB  (node1'in ~1 GB'ına karşı)
```

---

## 7. AI Servis Mimarisi (Backend)

### `backend/app/services/ml/llm_service.py`

**Model Registry** — `start_registry_loop()` lifespan'da çağrılır, 24h'te bir yeniler:

```python
# Groq: API'den model listesi çekilir, parametrik skor ile sıralanır
# Gemini: API'den model listesi çekilir, her model probe ile doğrulanır
#         node1 EU IP → probe 403/fail → Gemini listesi boş (beklenen)
#         node2 ABD IP → probe başarılı → Gemini modelleri aktif
```

**Redis Shared State** — node1 ve node2 aynı Groq API key'ini paylaştığında 429'lar koordineli yönetilir:

```
Redis key: llm:exhausted:{model_id}  TTL: retry-after saniyesi
Redis key: llm:last_success          TTL: 3600s  → sıcak yol optimizasyonu
```

**`InMemoryCircuitBreaker`** (`backend/app/core/circuit_breaker.py`):
- Redis çağrılarını `asyncio.wait_for(timeout=2s)` ile sarar
- 3 başarısız çağrı → OPEN, 30s sonra half-open
- Redis down olsa bile `llm_service` çalışmaya devam eder

**`max_tokens`: 600** — JSON non-streaming modunda tam açıklama için (eski streaming'de 350 idi).

### `backend/app/services/ml/ai_proxy_client.py`

```python
async def generate_via_node2(params) -> tuple[str, str]:
    if settings.node2_ai_proxy_url:
        try:
            async with asyncio.timeout(45):
                r = await _client.post(f"{node2_ai_proxy_url}/generate", ...)
                return r.json()["text"], r.json()["provider"]
        except Exception:
            logger.warning("[AI-PROXY] node2 başarısız, lokal fallback")
    return await generate_listing_description(**params)  # node1 Groq-only
```

### `backend/app/ai_proxy_main.py`

node2'nin çalıştırdığı minimal FastAPI uygulaması. Bağımlılıkları: yalnızca `llm_service` + `config` + `logging_config`. PostgreSQL, Redis, MinIO, LiveKit import'u yok.

### `backend/app/routers/listings.py` — `/generate-description`

SSE (Server-Sent Events) → JSON geçişi yapıldı:
- `StreamingResponse` kaldırıldı
- `generate_via_node2(params)` → `(description, provider)` döner
- Kredi düşme başarılı yanıt sonrası gerçekleşir
- `tuci_spent` response'a eklendi (Flutter UI'da gösterilir)

### `backend/app/config.py`

```python
class Config:
    env_file = os.environ.get("TEQLIF_ENV_FILE", ".env")
```

Her servis kendi `.env` dosyasını `TEQLIF_ENV_FILE` env var ile belirtir. Symlink gerekmez.

---

## 8. Flutter — AiDescNotifier MVVM (ADR §8)

**Dosyalar:**
- `mobile/lib/providers/ai_desc_provider.dart` — `AiDescNotifier extends StateNotifier<AiDescState>`
- `mobile/lib/screens/create_listing_screen.dart` — View (render + dinleme)

**State:** `AiDescStatus { idle, loading, done, error }` + `text`, `provider`, `tuciSpent`

**İş mantığı (ViewModel):** API çağrısı, token yönetimi, `CacheService.clearData('user_wallet_data')`

**View sorumluluğu:** `ref.listen<AiDescState>` ile typewriter animasyonu, Gemini snackbar (`aiDescFallbackNotice`), kredi UI güncellemesi. `_typing` bool saf UI state — ViewModel'e girmez.

---

## 9. Deploy Konfigürasyonu — `deploy/scale/resources/`

Version-independent tek kaynak dizini. Her versiyonda path değişmez — node'lar hep bu dizine bakar.

```
deploy/scale/resources/
├── .env.node1.production          # node1 prod .env şablonu (git'te, değerler boş)
├── .env.node1.staging             # node1 staging .env şablonu
├── .env.node2.production          # node2 prod .env şablonu
├── node1_production_requirements.txt
├── node1_staging_requirements.txt  # production + Faker==25.0.1
├── node2_production_requirements.txt
├── bootstrap_node1.sh             # node1 idempotent kurulum scripti
├── bootstrap_node2.sh             # node2 idempotent kurulum scripti
├── bootstrap_gateway.sh           # gateway idempotent kurulum scripti
└── README.md
```

**Bootstrap scriptleri** şunları otomatize eder:
1. apt paketleri
2. `/var/www/teqlif.com/venv/` Python venv + pip install
3. Log dizini + symlink (`/var/log/teqlif` → `/var/www/teqlif.com/logs`)
4. node_exporter indir + kur
5. promtail indir + kur + config
6. Systemd servis dosyalarını kopyala + enable
7. UFW kuralları
8. WireGuard: node2 private key varsa wg0.conf otomatik yazar (node2); node2 peer ekler (node1, gateway)
9. `chmod 600` .env dosyaları
10. `hostnamectl set-hostname` (node2)
11. `usermod -aG systemd-journal adm tucibeyin` (promtail journal erişimi)

**Kapsam dışı (sır içerir):** WireGuard key üretimi, `.env` gerçek değerleri.

---

## 10. Systemd Servis Dosyaları

### node1 — `deploy/scale/V1.2/node1/systemd/`

| Dosya | Port | Workers |
|---|---|---|
| `teqlif.service` | 8000 | 4 |
| `teqlif-staging.service` | 8001 | 2 |
| `teqlif-worker.service` | — | 1 |
| `teqlif-worker-critical.service` | — | 1 |
| `node_exporter.service` | 9100 (wg0) | — |
| `promtail.service` | — | — |
| `redis-backup.service` + `.timer` | — | — |
| `livekit.service` | 7880/7881/7882 | — |
| `minio.service` | 9010 | — |

### node1 (ek) — `deploy/scale/V1.2/node1/nginx/`

| Dosya | Açıklama |
|---|---|
| `teqlif-fallback.conf` | Port 443, self-signed cert, CF failover için — gateway down → node1 direkt |

### node2 — `deploy/scale/V1.2/node2/systemd/`

| Dosya | Port | Workers |
|---|---|---|
| `teqlif-ai-proxy.service` | 8080 (wg0) | 1 |
| `cf-failover.service` | — | — |
| `node_exporter.service` | 9100 (wg0) | — |
| `promtail.service` | — | — |

### gateway — `deploy/scale/V1.2/gateway/systemd/`

| Dosya | Port |
|---|---|
| `prometheus.service` | 9090 (localhost) |
| `alertmanager.service` | 9093 (localhost) |
| `loki.service` | 3100 |
| `promtail.service` | — |
| `node_exporter.service` | 9100 (localhost) |

**Tüm servisler `User=tucibeyin` ile çalışır.** İstisnalar: `livekit.service` (User=livekit), `minio.service` (User=www-data).

---

## 11. Firewall (UFW)

### node1

```
22/tcp          ALLOW   Anywhere          # SSH
443/tcp         ALLOW   Cloudflare IPs    # HTTPS — CF failover fallback  ← V1.2
51820/udp       ALLOW   Anywhere          # WireGuard
8000/tcp on wg0 ALLOW   10.10.0.2         # API prod — gateway
8001/tcp on wg0 ALLOW   10.10.0.2         # API staging — gateway
9100/tcp on wg0 ALLOW   Anywhere (wg0)    # node_exporter — Prometheus
6379/tcp on wg0 ALLOW   10.10.0.3         # Redis — node2  ← V1.2
```

### node2

```
22/tcp          ALLOW   Anywhere          # SSH
51820/udp       ALLOW   Anywhere          # WireGuard
8080/tcp on wg0 ALLOW   Anywhere (wg0)    # AI proxy — node1
9100/tcp on wg0 ALLOW   Anywhere (wg0)    # node_exporter — gateway
```

### gateway

```
22/tcp          ALLOW   Anywhere          # SSH
80/tcp          ALLOW   Anywhere          # HTTP
443/tcp         ALLOW   Anywhere          # HTTPS
51820/udp       ALLOW   Anywhere          # WireGuard
3100/tcp on wg0 ALLOW   10.10.0.1         # Loki — node1
3100/tcp on wg0 ALLOW   10.10.0.3         # Loki — node2  ← V1.2
```

---

## 12. Monitoring Stack

| Bileşen | Versiyon | Konum | V1.2 Değişikliği |
|---|---|---|---|
| prometheus | 2.51.0 | gateway | `node-node2` scrape target eklendi |
| alertmanager | 0.27.0 | gateway | `AIProxyDown` alert kuralı eklendi |
| loki | 3.6.7 | gateway | node2 logları (job: teqlif-ai-proxy, systemd-journal) |
| promtail | 3.0.0 | her 3 node | node2 eklendi |
| node_exporter | 1.8.2 | her 3 node | node2 eklendi (`--collector.systemd`) |

### Prometheus — node2 Scrape (V1.2)

`deploy/scale/V1.2/gateway/prometheus.yml`:
```yaml
- job_name: 'node-node2'
  static_configs:
    - targets: ['10.10.0.3:9100']
      labels:
        node: node2
```

### Alertmanager — AIProxyDown Alert

`deploy/scale/V1.2/gateway/prometheus-rules.yml`:

```yaml
- alert: AIProxyDown
  expr: up{job="node-node2"} == 0
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "node2 AI Proxy erişilemiyor"
```

---

## 13. Deploy Workflow (V1.2)

### Rutin Deploy (kod değişikliği)

```bash
# Yerel
git push

# node1
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

# node2
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy
```

### node2 .env Güncelleme

```bash
# node2
nano /var/www/teqlif.com/deploy/scale/resources/.env.node2.production
sudo systemctl restart teqlif-ai-proxy
```

### gateway Prometheus/Rules Güncelleme

```bash
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.2/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo mkdir -p /etc/prometheus/rules
sudo cp deploy/scale/V1.2/gateway/prometheus-rules.yml /etc/prometheus/rules/teqlif.yml
sudo systemctl restart prometheus
```

### Sistem Optimizasyonlarını Yeniden Uygulama

```bash
# sysctl (herhangi bir node):
sudo cp deploy/scale/V1.2/<node>/sysctl/99-teqlif.conf /etc/sysctl.d/99-teqlif.conf
sudo sysctl -p /etc/sysctl.d/99-teqlif.conf

# journald (herhangi bir node):
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp deploy/scale/V1.2/<node>/journald/journald.conf /etc/systemd/journald.conf.d/99-teqlif.conf
sudo systemctl restart systemd-journald

# nginx.conf (gateway):
sudo cp deploy/scale/V1.2/gateway/nginx/nginx.conf /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx

# nginx fallback (node1):
sudo cp deploy/scale/V1.2/node1/nginx/teqlif-fallback.conf /etc/nginx/sites-available/
sudo nginx -t && sudo systemctl reload nginx
```

### Yeni Node Kurulumu

```bash
# Repo klonla
git clone <repo-url> /var/www/teqlif.com

# WireGuard key üret (manuel — sır)
sudo bash -c 'wg genkey | tee /etc/wireguard/<node>_private.key | wg pubkey > /etc/wireguard/<node>_public.key'

# Bootstrap çalıştır
bash /var/www/teqlif.com/deploy/scale/resources/bootstrap_<node>.sh

# .env değerlerini doldur
nano /var/www/teqlif.com/deploy/scale/resources/.env.<node>.production
```

---

## 14. Sistem Optimizasyonları (2026-09-10)

### 14.1 Systemd Servis Optimizasyonları

`deploy/scale/V1.2/node1/systemd/` ve `deploy/scale/V1.2/node2/systemd/` güncellendi.

| Servis | LimitNOFILE | OOMScoreAdj | TimeoutStopSec | CPUWeight | MemoryMax |
|---|---|---|---|---|---|
| teqlif | 65536 | -500 (korunan) | 30s | 200 | — |
| teqlif-staging | 65536 | -200 | 30s | 80 | — |
| teqlif-worker | — | +200 (ilk öldürülen) | 300s | 50 | — |
| teqlif-worker-critical | — | +100 | 600s | 100 | — |
| teqlif-ai-proxy | 4096 | 0 | 60s | — | 768M |

Tüm servislere `KillMode=mixed` (API) / `KillMode=process` (worker) + `StartLimitBurst=10` eklendi.

### 14.2 PostgreSQL Tuning (node1)

Konfigürasyon `ALTER SYSTEM` ile uygulandı — aktif değerler `/etc/postgresql/17/main/postgresql.auto.conf` içinde.
Referans dosya: `deploy/scale/V1.2/node1/postgres/postgresql-tuning.conf`

| Parametre | Önceki | Sonraki | Gerekçe |
|---|---|---|---|
| `shared_buffers` | 128MB | **2GB** | 11.4 GB RAM'in %17'si (Redis 4 GB aldığından dengeli) |
| `effective_cache_size` | 4GB | **6GB** | Planner tahmini |
| `work_mem` | 4MB | **16MB** | Sort/hash per-operation belleği |
| `maintenance_work_mem` | 64MB | **256MB** | VACUUM, CREATE INDEX |
| `wal_buffers` | ~3.8MB | **64MB** | WAL write buffer |
| `random_page_cost` | 4.0 | **1.1** | NVMe'de random/seq maliyet neredeyse eşit |
| `effective_io_concurrency` | 1 | **200** | NVMe paralel I/O |

### 14.3 Kernel sysctl

Tüm node'larda `/etc/sysctl.d/99-teqlif.conf` oluşturuldu.

**node1** (`deploy/scale/V1.2/node1/sysctl/99-teqlif.conf`):

| Parametre | Önceki | Sonraki |
|---|---|---|
| `vm.swappiness` | 60 | 10 |
| `vm.dirty_ratio` | 20 | 15 |
| `vm.dirty_background_ratio` | 10 | 5 |
| `net.core.somaxconn` | 4096 | 65535 |
| `net.ipv4.tcp_max_syn_backlog` | 1024 | 65535 |
| `net.ipv4.tcp_tw_reuse` | 2 | 1 |

**gateway** (`deploy/scale/V1.2/gateway/sysctl/99-teqlif.conf`):

| Parametre | Önceki | Sonraki |
|---|---|---|
| `net.ipv4.tcp_max_syn_backlog` | 128 | 65535 |
| `net.ipv4.tcp_tw_reuse` | 2 | 1 |

**node2** (`deploy/scale/V1.2/node2/sysctl/99-teqlif.conf`):

| Parametre | Önceki | Sonraki |
|---|---|---|
| `vm.swappiness` | 10 | 1 |
| `vm.overcommit_memory` | 0 | 1 |
| `net.ipv4.tcp_max_syn_backlog` | 128 | 4096 |

### 14.4 nginx Optimizasyonu (gateway)

`deploy/scale/V1.2/gateway/nginx/nginx.conf`

| Parametre | Önceki | Sonraki |
|---|---|---|
| `worker_connections` | 768 | 4096 |
| `multi_accept` | off | on |
| `tcp_nodelay` | — | on |
| `keepalive_timeout` | default | 65 |
| `ssl_session_cache` | — | shared:SSL:10m |
| `ssl_session_timeout` | — | 10m |
| `open_file_cache` | — | max=1000 inactive=20s |
| `gzip_vary/proxied/comp_level/types` | comment'te | aktif |

### 14.5 journald Limitleri

| Node | SystemMaxUse | SystemKeepFree | Önceki Kullanım |
|---|---|---|---|
| node1 | 500M | 2G | 442 MB |
| gateway | 300M | 1G | 91 MB |
| node2 | 200M | 200M | 40 MB |

### 14.6 WireGuard MTU

Tüm node'larda `mtu 1420` zaten doğru değerdeydi — değişiklik gerekmedi.

---

## 15. Rollback Planı

| Senaryo | Aksiyon |
|---|---|
| node2 çöker | node1 otomatik lokal Groq fallback'e geçer — kullanıcı etkilenmez |
| node2 Gemini kota doldu | Groq listesine düşer; node1 fallback devrede |
| AIProxyDown alert | `sudo systemctl restart teqlif-ai-proxy` (node2'de) |
| gateway çöker | **Otomatik:** node2 cf-failover daemon 30s içinde CF DNS A'yı node1'e çevirir. Gateway geri gelince 30s içinde otomatik geri döner. |
| WireGuard bozulur | `sudo systemctl restart wg-quick@wg0` |
| V1.1'e dönüş | `deploy/scale/V1.1/` config'lerini uygula; node2 servislerini durdur |

---

## 16. V1.2 Uygulama Sırasında Karşılaşılan Sorunlar

### 1. WireGuard heredoc'ta variable expansion çalışmadı

**Sorun:** `<< 'EOF'` (single-quoted) heredoc içinde `$(cat /etc/wireguard/node2_private.key)` expand edilmedi. wg0.conf'a literal `$(cat ...)` yazıldı.

**Çözüm:** Private key önce shell değişkenine atandı (`NODE2_PRIV=$(sudo cat ...)`), ardından `printf '%s'` ile dosyaya yazıldı.

### 2. `config.py` `.env` dosyasını bulamadı

**Sorun:** `env_file = ".env"` hardcoded — backend/ altında `.env` olmayınca ayarlar yüklenmedi.

**Çözüm:** `env_file = os.environ.get("TEQLIF_ENV_FILE", ".env")` — her systemd servisi kendi `Environment=TEQLIF_ENV_FILE=...` satırıyla belirtir.

### 3. node2'de `python3 -m venv` başarısız

**Sorun:** `ensurepip not available` — python3.13-venv paketi kurulu değildi.

**Çözüm:** `sudo apt install python3.13-venv -y` önce çalıştırıldı. bootstrap_node2.sh'a eklendi.

### 4. node_exporter UFW'da kapalı kaldı

**Sorun:** UFW kurallarında 9100 portu unutuldu — Prometheus node2 target'ı `down` görüldü.

**Çözüm:** `sudo ufw allow in on wg0 to any port 9100 proto tcp` eklendi. bootstrap_node2.sh güncellendi.

### 5. `max_tokens: 350` JSON modunda yeterli değil

**Sorun:** Eski streaming kodu için düşük tutulan limit, non-streaming modda uzun açıklamaları yarıda kesiyor.

**Çözüm:** `max_tokens: 600` (Groq) ve `maxOutputTokens: 600` (Gemini) — `backend/app/services/ml/llm_service.py:443,463`.

### 6. `sudo` hostname çözümleme uyarısı

**Sorun:** `hostnamectl set-hostname node2` sonrası `/etc/hosts`'ta kayıt olmadığı için her `sudo` komutunda `unable to resolve host node2` uyarısı.

**Çözüm:** `echo "127.0.1.1 node2" >> /etc/hosts`. bootstrap_node2.sh'a eklendi.

---

## 17. V1.3 Adayları

- **Gemini erişim kontrolü:** node1, proxy üzerinden Gemini kullanabilir — bu bir seçim değil, şu an maliyet/karmaşıklık gerekçesiyle ertelendi.
- **node2 auto-scaling:** Yük arttığında birden fazla AI proxy instance'ı — şu an tek worker yeterli.
- **Redis sentinel / replica:** node1 Redis SPOF — yüksek erişilebilirlik için replica adayı.
- **ARQ worker node2'ye taşıma:** AI işler zaten node2'ye yönleniyor — ARQ da taşınabilir (V2.0 adayı).

---

## 18. Commit Referansları

| Hash | İçerik |
|---|---|
| `1f582199` | Scale V1.2 başlangıç — plan + node2 ilk tasarım |
| `89b3f9da` | llm_service stateless registry, ai_proxy_main, ai_proxy_client, SSE→JSON, Flutter |
| `3c104a6b` | Redis shared exhaustion + last_success state |
| `84b7002e` | InMemoryCircuitBreaker |
| `d57af7ee` | Flutter AiDescNotifier MVVM refactor |
| `002d23da` | TEQLIF_ENV_FILE config.py |
| `a86e9041` | deploy/scale/resources/ tek kaynak yapısı |
| `2e8ea50b` | bootstrap_node1.sh + bootstrap_node2.sh |
| `c3a247f3` | bootstrap_gateway.sh |
| `3ee6664f` | WireGuard otomasyonu bootstrap scriptlerine eklendi |
| `5b0516b6` | max_tokens 350→600 |
| `03feac31` | Tüm servisler tucibeyin kullanıcısına standardize edildi |
| `f3d2e4b7` | Systemd servis optimizasyonları — LimitNOFILE, OOMScoreAdj, TimeoutStopSec, CPUWeight |
| `f5be2e77` | Sistem optimizasyonları — PostgreSQL tuning, sysctl, nginx, journald |
| `07e85c1d` | CF failover: node2 cf-failover daemon + node1 nginx fallback (port 443) |

---

## 19. Dosya Referansları

```
deploy/scale/V1.2/
├── plan.md                                   # Mimari kararlar
├── task.md                                   # Adım adım uygulama logu
├── final.md                                  # Bu belge
├── wireguard/                                # wg0.conf şablonları
├── gateway/
│   ├── prometheus.yml                        # node-node2 scrape eklendi
│   ├── prometheus-rules.yml                  # AIProxyDown alert
│   ├── alertmanager.yml.template
│   ├── loki-config.yml
│   ├── promtail-config.yml
│   ├── journald/
│   │   └── journald.conf                     # SystemMaxUse=300M, SystemKeepFree=1G
│   ├── nginx/
│   │   ├── nginx.conf                        # worker_connections=4096, gzip, ssl_session_cache
│   │   └── teqlif.conf                       # /cf-health endpoint + location / redirect  ← V1.2
│   ├── sysctl/
│   │   └── 99-teqlif.conf                    # tcp_max_syn_backlog=65535, tcp_tw_reuse=1
│   └── systemd/
│       ├── prometheus.service                # User=tucibeyin
│       ├── loki.service                      # User=tucibeyin
│       ├── alertmanager.service
│       ├── promtail.service                  # User=tucibeyin + SupplementaryGroups
│       └── node_exporter.service             # User=tucibeyin
├── node1/
│   ├── promtail-config.yml
│   ├── journald/
│   │   └── journald.conf                     # SystemMaxUse=500M, SystemKeepFree=2G
│   ├── nginx/
│   │   └── teqlif-fallback.conf              # Port 443, self-signed cert, uvicorn:8000 — CF failover
│   ├── postgres/
│   │   └── postgresql-tuning.conf            # shared_buffers=2GB, work_mem=16MB, NVMe tuning
│   ├── sysctl/
│   │   └── 99-teqlif.conf                    # swappiness=10, somaxconn=65535, dirty_ratio
│   └── systemd/
│       ├── teqlif.service                    # LimitNOFILE=65536, OOMScoreAdj=-500, CPUWeight=200
│       ├── teqlif-staging.service            # LimitNOFILE=65536, OOMScoreAdj=-200
│       ├── teqlif-worker.service             # OOMScoreAdj=+200, TimeoutStopSec=300
│       ├── teqlif-worker-critical.service    # OOMScoreAdj=+100, TimeoutStopSec=600
│       ├── node_exporter.service             # User=tucibeyin
│       ├── promtail.service                  # User=tucibeyin + SupplementaryGroups
│       ├── redis-backup.service + .timer
│       ├── livekit.service                   # User=livekit (değişmez)
│       └── minio.service                     # User=www-data (değişmez)
└── node2/
    ├── promtail-config.yml
    ├── cf-failover/
    │   ├── cf-failover.sh                    # DNS failover daemon scripti
    │   └── cf-failover.env.template          # CF_ZONE_ID + CF_API_TOKEN şablonu (git'te, değerler boş)
    ├── journald/
    │   └── journald.conf                     # SystemMaxUse=200M, SystemKeepFree=200M
    ├── sysctl/
    │   └── 99-teqlif.conf                    # swappiness=1, overcommit_memory=1
    └── systemd/
        ├── teqlif-ai-proxy.service           # MemoryMax=768M, TimeoutStopSec=60
        ├── cf-failover.service               # CF DNS failover daemon
        ├── node_exporter.service             # User=tucibeyin
        └── promtail.service                  # User=tucibeyin + SupplementaryGroups

deploy/scale/resources/                       # Version-independent, kalıcı
├── .env.node1.production                     # Şablon (git'te, değerler boş)
├── .env.node1.staging
├── .env.node2.production
├── node1_production_requirements.txt
├── node1_staging_requirements.txt
├── node2_production_requirements.txt
├── bootstrap_node1.sh
├── bootstrap_node2.sh
├── bootstrap_gateway.sh
└── README.md

backend/app/
├── config.py                                 # TEQLIF_ENV_FILE, node2 alanları
├── ai_proxy_main.py                          # node2 FastAPI uygulaması (yeni)
├── core/circuit_breaker.py                   # InMemoryCircuitBreaker (yeni)
├── routers/listings.py                       # /generate-description SSE→JSON
└── services/ml/
    ├── llm_service.py                        # Stateless registry, Redis state, max_tokens=600
    └── ai_proxy_client.py                    # generate_via_node2 + fallback (yeni)

mobile/lib/
├── providers/ai_desc_provider.dart           # AiDescNotifier (yeni)
└── screens/create_listing_screen.dart        # ref.listen typewriter, _typing
```

---

## 20. Cloudflare Gateway Failover (V1.2)

Gateway SPOF tamamen otomasyona alındı. Cloudflare Free plan kullanılarak gerçekleştirildi.

### Mimari

```
node2 cf-failover.sh
  │  (her 10s bir kontrol)
  └─► http://94.16.105.135/cf-health
         │
    gateway UP  → sessiz izleme devam eder
    gateway DOWN → 3 ardışık hata (30s) → CF DNS API → A record → node1
    gateway UP  → 3 ardışık başarı (30s) → CF DNS API → A record → gateway
```

### Bileşenler

| Bileşen | Konum | Açıklama |
|---|---|---|
| `/cf-health` endpoint | gateway nginx | port 80, `location = /cf-health`, `200 OK` döner |
| `teqlif-fallback.conf` | node1 nginx | port 443, self-signed cert, uvicorn:8000 proxy |
| `cf-failover.sh` | `/usr/local/bin/` node2 | bash daemon, CF API v4 kullanır |
| `cf-failover.service` | node2 systemd | `EnvironmentFile=/etc/cf-failover.env`, Restart=always |
| `/etc/cf-failover.env` | node2 | `CF_ZONE_ID` + `CF_API_TOKEN` — git'e girmez |

### Failover Parametreleri

| Parametre | Değer | Açıklama |
|---|---|---|
| `CHECK_INTERVAL` | 10s | Health check sıklığı |
| `FAIL_THRESHOLD` | 3 | Ardışık hata sayısı → failover tetiklenir |
| `RECOVER_THRESHOLD` | 3 | Ardışık başarı sayısı → geri dönüş tetiklenir |
| Toplam failover süresi | ~30s | 3 × 10s |
| Toplam recovery süresi | ~30s | 3 × 10s |

### CF SSL Modu

`Full` — Cloudflare ile node1 arası self-signed cert yeterli. `Full (Strict)` gerektirmez.

### node1 nginx Fallback Kısıtlamaları

Failover sırasında çalışmayan özellikler (gateway down iken):
- staging.teqlif.com (fallback config'de staging upstream yok)
- LiveKit SFU websocket /rtc, /livekit/ (LiveKit doğrudan WS, nginx proxy gerekmiyor)
- nginx microcaching ve rate limiting (uvicorn doğrudan yanıtlar)

### CF DNS Record Yönetimi

Script sadece `teqlif.com` A record'unu günceller. `www.teqlif.com` CNAME → `teqlif.com` olduğundan otomatik takip eder.

### Test (2026-09-11)

```
gateway nginx durduruldu:
  00:47:08  Gateway erişilemiyor (1/3)
  00:47:18  Gateway erişilemiyor (2/3)
  00:47:28  Gateway erişilemiyor (3/3)
  00:47:28  === SWITCH: gateway → node1 (135.125.175.223) ===
  00:47:29    teqlif.com → 135.125.175.223: OK

gateway nginx başlatıldı:
  00:48:10  Gateway geri geldi (1/3)
  00:48:20  Gateway geri geldi (2/3)
  00:48:30  Gateway geri geldi (3/3)
  00:48:30  === SWITCH: node1 → gateway (94.16.105.135) ===
  00:48:31    teqlif.com → 94.16.105.135: OK
```

Failover: 20s, Recovery: 20s (3 check × 10s, ilk check anında geldi).
