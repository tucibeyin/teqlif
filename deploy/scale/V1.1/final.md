# Teqlif Scale V1.1 — Kapsamlı Mimari ve Uygulama Belgesi

> **Uygulama tarihi:** 2026-09-08  
> **Durum:** Aktif (production)  
> **Önceki sürüm:** `deploy/scale/V1.0/`  
> **Kaynak dosyalar:** `deploy/scale/V1.1/`

---

## 1. Genel Bakış

Scale V1.1, V1.0 üzerine 4 operasyonel iyileştirmedir. Mimari değişmez; gateway + node1 topolojisi korunur.

### V1.1 ile gelen değişiklikler

| # | Değişiklik | Etki |
|---|---|---|
| 1 | Staging nginx block güçlendirme | Rate limiting + security header eklendi |
| 2 | uploads.teqlif.com `immutable` | V1.0'da zaten mevcuttu, doğrulandı |
| 3 | nginx microcaching (gateway) | Public GET istekleri 5s cache; node1 yükü azalır |
| 4 | Alertmanager (gateway) | Telegram bildirimleri; 5 alert kuralı |
| + | Duplicate security header fix | Backend middleware'den statik başlıklar kaldırıldı |

---

## 2. Donanım

### node1 — OVH Limburg (Ana Backend)

| Parametre | Değer |
|---|---|
| Public IP | 135.125.175.223 |
| WireGuard IP | 10.10.0.1 |
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + **2 GiB Swap** (V1.1'de 12 GiB'dan düşürüldü) |
| Disk | 98.3 GiB NVMe |
| Ağ | **2 Gbps / unmetered** (kota yok) |
| Geekbench 6 | 1058 single / 4404 multi |

### gateway — Netcup Nürnberg (Edge Proxy + Observability)

| Parametre | Değer |
|---|---|
| Public IP | 94.16.105.135 |
| WireGuard IP | 10.10.0.2 |
| CPU | 2 vCore (QEMU @ 2.29 GHz) |
| RAM | 2 GB + 1 GB Swap |
| Disk | 60 GB SSD |
| Ağ | 1 Gbps — **24h ortalama >100 Mbps → geçici throttle (100 Mbps)** |
| Geekbench 6 | 645 single / 1210 multi |

**Netcup throttle kuralı:** 24 saatlik rolling average 100 Mbps'yi aşarsa throttle başlar. Büyük medya transferleri gateway'den geçirilmez — `uploads.teqlif.com` DNS Only → node1 doğrudan.

---

## 3. Topoloji ve Trafik Akışı

```
                    ┌─────────────────────────────────────────┐
 İnternet           │           CLOUDFLARE EDGE               │
                    │  (DDoS koruma, SSL proxy, CDN cache)    │
                    └──────────────┬──────────────────────────┘
                                   │ HTTPS
                    ┌──────────────▼──────────────────────────┐
                    │         gateway (Netcup, 94.16.105.135)  │
                    │                                          │
                    │  nginx (SSL termination, rate limit,     │
                    │         microcaching)          ← V1.1    │
                    │  WireGuard (10.10.0.2)                   │
                    │  Prometheus  :9090                       │
                    │  Alertmanager :9093            ← V1.1    │
                    │  Loki        :3100                       │
                    │  promtail    → Loki (kendi logları)      │
                    │  node_exporter :9100                     │
                    │  fail2ban                                │
                    └──────────────┬──────────────────────────┘
                                   │ WireGuard (10.10.0.0/24)
                    ┌──────────────▼──────────────────────────┐
                    │         node1 (OVH, 135.125.175.223)     │
                    │                                          │
                    │  FastAPI prod    :8000  (4 workers)      │
                    │  FastAPI staging :8001  (2 workers)      │
                    │  PostgreSQL      :5432                   │
                    │  Redis           :6379                   │
                    │  MinIO           :9010                   │
                    │  ClickHouse      :8123                   │
                    │  LiveKit SFU     :7880/:7881/:7882       │
                    │  ARQ Workers     (genel + critical)      │
                    │  nginx           (uploads.teqlif.com)    │
                    │  WireGuard       (10.10.0.1)             │
                    │  node_exporter   :9100                   │
                    │  promtail        → gateway Loki          │
                    │  fail2ban                                │
                    └─────────────────────────────────────────┘
```

### Trafik Akışı

```
API/WebSocket:
  Mobil → Cloudflare → gateway:443 (nginx SSL + microcache) → WireGuard → node1:8000

uploads.teqlif.com (medya indirme):
  Mobil → DNS Only → node1:443 (nginx) → localhost:9010 (MinIO)
  ↑ Cloudflare yok, gateway yok — node1'e direkt

Medya yükleme (POST /api/upload):
  Mobil → Cloudflare → gateway:443 → WireGuard → node1:8000 → MinIO

LiveKit WebRTC sinyalizasyon (/rtc WSS):
  Mobil → Cloudflare → gateway:443 (nginx /rtc proxy) → WireGuard → node1:7880

LiveKit WebRTC medya (UDP — PROXY EDİLEMEZ):
  Mobil → node1:50000-60000/udp  (doğrudan, gateway bypass)

Monitoring (WireGuard üzerinden):
  gateway Prometheus → 10.10.0.1:9100 (node1 node_exporter)
  gateway Prometheus → 10.10.0.1:9187 (postgres-exporter)
  gateway Prometheus → 10.10.0.1:7881 (livekit metrics)
  gateway Alertmanager ← Prometheus alerts → Telegram
  node1 promtail → 10.10.0.2:3100 (gateway Loki push)
```

---

## 4. Servis Dağılımı

| Servis | node1 | gateway | Gerekçe |
|---|---|---|---|
| FastAPI prod (:8000) | ✅ | ❌ | PostgreSQL/Redis yakınlığı |
| FastAPI staging (:8001) | ✅ | ❌ | Aynı ortam, `.env.staging` ile ayrılır |
| PostgreSQL | ✅ | ❌ | Disk I/O + worker doğrudan erişim |
| Redis | ✅ | ❌ | Tüm sistemin tek SPOF — node1'de kalmalı |
| MinIO | ✅ | ❌ | Disk + OVH unmetered bant |
| ClickHouse | ✅ | ❌ | RAM yoğun, worker entegrasyonu |
| LiveKit SFU | ✅ | ❌ | UDP medya + OVH unmetered 2Gbps |
| ARQ Worker (genel) | ✅ | ❌ | ML (PyTorch, numpy) + DB/ClickHouse erişimi |
| ARQ Worker (critical) | ✅ | ❌ | Push notification, outbid, loser cascade — bulkhead pattern |
| nginx (public SSL) | ❌ | ✅ | Edge proxy rolü |
| nginx (uploads) | ✅ | ❌ | uploads.teqlif.com, MinIO direkt |
| Prometheus | ❌ | ✅ | Observability bağımsızlığı |
| Alertmanager | ❌ | ✅ | Prometheus alerts → Telegram ← **V1.1** |
| Loki | ❌ | ✅ | Log storage için 60 GB SSD |
| promtail | ✅ (→ gateway Loki) | ✅ (→ localhost Loki) | Her iki node'da |
| node_exporter | ✅ | ✅ | Her iki node'da |
| WireGuard | ✅ (10.10.0.1) | ✅ (10.10.0.2) | Özel ağ tüneli |
| fail2ban | ✅ | ✅ | Bağımsız |

---

## 5. DNS Yapısı (Cloudflare)

| Domain | IP | Mod | Açıklama |
|---|---|---|---|
| `teqlif.com` | 94.16.105.135 | **Proxied** | gateway'e yönlenir; Cloudflare DDoS + CDN |
| `www.teqlif.com` | CNAME → teqlif.com | **Proxied** | Aynı |
| `staging.teqlif.com` | 94.16.105.135 | **Proxied** | gateway → node1:8001 |
| `uploads.teqlif.com` | 135.125.175.223 | **DNS Only** | node1 direkt — gateway bypass; medya indirme |
| `live.teqlif.com` | 135.125.175.223 | **DNS Only** | LiveKit STUN/TURN için gerekli |
| `minio.teqlif.com` | 135.125.175.223 | **DNS Only** | MinIO admin UI |

**Cloudflare SSL/TLS modu:** Full (Strict)

---

## 6. WireGuard VPN Tüneli

V1.0 ile aynı. Değişiklik yok.

```
node1  WireGuard IP: 10.10.0.1  ListenPort: 51820
gateway WireGuard IP: 10.10.0.2  ListenPort: 51820
PersistentKeepalive: 25 (gateway → node1)
```

---

## 7. gateway nginx Yapılandırması (V1.1)

### Rate Limit Zone'ları + Microcache — `/etc/nginx/conf.d/http-zones.conf`

```nginx
limit_req_zone $binary_remote_addr zone=general:10m  rate=60r/m;
limit_req_zone $binary_remote_addr zone=auth:10m     rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m      rate=1800r/m;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
limit_req_status 429;

proxy_cache_path /var/cache/nginx/teqlif
    levels=1:2
    keys_zone=teqlif_cache:10m
    max_size=256m
    inactive=60s
    use_temp_path=off;
```

### Production Server Block — Önemli Değişiklikler (V1.1)

```nginx
# Duplicate header önleme — backend Starlette statik başlıkları gizlenir
proxy_hide_header X-Frame-Options;
proxy_hide_header X-Content-Type-Options;
proxy_hide_header Strict-Transport-Security;

# Microcaching — /api/ location'a eklendi
proxy_cache teqlif_cache;
proxy_cache_methods GET HEAD;
proxy_cache_key "$request_method$host$request_uri";
proxy_cache_valid 200 5s;
proxy_cache_bypass $http_authorization $http_pragma;
proxy_no_cache $http_authorization $http_pragma;
proxy_cache_use_stale error timeout updating;
add_header X-Cache-Status $upstream_cache_status always;
```

**Cache kuralları:**
- `Authorization` header varsa → `BYPASS` (authenticated istek, asla cache'lenmez)
- Auth yok, GET/HEAD → ilk istek `MISS`, 5s içindeki aynı istek `HIT`
- POST/PUT/DELETE → asla cache'lenmez (`proxy_cache_methods GET HEAD`)
- WebSocket, auth, upload endpoint'leri → ayrı location block'larda, cache yok

### Staging Server Block — V1.1 ile eklenenler

```nginx
proxy_hide_header X-Frame-Options;
proxy_hide_header X-Content-Type-Options;
proxy_hide_header Strict-Transport-Security;

# Security headers
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Rate limiting
location /api/auth { limit_req zone=auth burst=5 nodelay; ... }
location /api/     { limit_req zone=api burst=300 nodelay; ... }
location /         { limit_req zone=general burst=60 nodelay; ... }

# Ayrı WebSocket location'ları (/api/chat/, ~* /ws$)
# Ayrı upload location (/api/upload, client_max_body_size 100M)
```

**Not:** Staging'de microcaching yok — test ortamında caching hata ayıklamayı zorlaştırır.

---

## 8. Backend — Güvenlik Başlığı Değişikliği (V1.1)

`backend/app/security/middleware.py` — `security_headers` middleware güncellendi.

**Önceki durum (V1.0):** Backend her response'a X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy, X-XSS-Protection, Permissions-Policy ekliyordu. nginx de `add_header` ile aynı başlıkları ekliyordu → **duplicate header** sorunu.

**V1.1 çözümü:** Statik başlıklar backend'den kaldırıldı. Yalnızca uygulama-spesifik, koşullu `Content-Security-Policy` kaldı.

```python
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    is_phone_verify_page = (
        request.url.path == "/api/auth/phone-verify/confirm"
        and request.method == "GET"
    )
    # Statik başlıklar nginx'te — sadece CSP burada
    response.headers["Content-Security-Policy"] = (
        _PHONE_VERIFY_CSP if is_phone_verify_page else _DEFAULT_CSP
    )
    return response
```

**Neden CSP backend'de kaldı:** `/api/auth/phone-verify/confirm` endpoint'i için farklı bir CSP gerekli (`unsafe-inline` izinli). Bu koşullu mantık nginx'te yönetmek yerine backend'de tutuldu.

---

## 9. Alertmanager (V1.1)

### Kurulum — gateway

```
Binary: /usr/local/bin/alertmanager (v0.27.0)
Config: /etc/alertmanager/alertmanager.yml  (envsubst ile oluşturulur)
Template: deploy/scale/V1.1/gateway/alertmanager.yml.template
Secrets: /etc/alertmanager/alertmanager.env  (git'e girmez)
Storage: /var/lib/alertmanager
Servis: alertmanager.service (systemd)
Port: 9093
```

### Credentials Yönetimi

`alertmanager.yml.template` git'tedir ve `${TELEGRAM_BOT_TOKEN}` / `${TELEGRAM_CHAT_ID}` placeholder'ları içerir. Deploy sırasında `envsubst` ile gerçek config oluşturulur:

```bash
set -a && source /etc/alertmanager/alertmanager.env && set +a
envsubst '$TELEGRAM_BOT_TOKEN $TELEGRAM_CHAT_ID' \
  < deploy/scale/V1.1/gateway/alertmanager.yml.template \
  | sudo tee /etc/alertmanager/alertmanager.yml > /dev/null
```

`/etc/alertmanager/alertmanager.env` gateway'de elle oluşturulur, git'e girmez:
```
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
```

**Not:** `--config.expand-env` flag'ı 0.27.0 build'inde mevcut değil. `envsubst` deploy-time alternatifi olarak kullanılır.

### Alert Kuralları — `/etc/prometheus/rules/teqlif.yml`

| Alert | Koşul | Süre | Severity |
|---|---|---|---|
| `NodeDown` | `up == 0` | 1m | critical |
| `HighMemoryUsage` | RAM kullanımı > %85 | 5m | warning |
| `DiskSpaceLow` | Disk doluluk > %80 | 5m | warning |
| `HighSwapUsage` | Swap kullanımı > %50 | 5m | warning |
| `HighCPULoad` | CPU > %90 | 10m | warning |

### Prometheus Entegrasyonu

`prometheus.yml`'e eklenenler:
```yaml
global:
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules/*.yml
```

### inhibit_rules

`critical` severity bir alert ateşlendiğinde, aynı `alertname` + `node` için `warning` alertlar susturulur. Örn: `NodeDown` (critical) ateşlenince `HighMemoryUsage` (warning) bildirim göndermez.

---

## 10. node1 Servis Konfigürasyonları

V1.0 ile aynı. Değişiklik yok.

- FastAPI prod: `--host 0.0.0.0 --port 8000 --workers 4 --forwarded-allow-ips 10.10.0.2`
- FastAPI staging: `--host 0.0.0.0 --port 8001 --workers 2 --forwarded-allow-ips 10.10.0.2`
- `ExecStartPre` alembic migration her restart'ta çalışır

---

## 11. node1 Firewall (UFW)

V1.0 ile aynı. Değişiklik yok.

```bash
ufw allow 51820/udp           # WireGuard
ufw allow from 10.10.0.2 to any port 8000   # prod API
ufw allow from 10.10.0.2 to any port 8001   # staging API
ufw allow from 10.10.0.2 to any port 9100   # node_exporter
ufw allow from 10.10.0.2 to any port 9187   # postgres-exporter
ufw allow from 10.10.0.2 to any port 7881   # livekit metrics
ufw deny 8000
ufw deny 8001
```

---

## 12. Monitoring Stack

| Bileşen | Versiyon | Konum | V1.1 Değişikliği |
|---|---|---|---|
| prometheus | 2.51.0 | gateway | `evaluation_interval`, `alerting`, `rule_files` eklendi |
| alertmanager | 0.27.0 | gateway | **Yeni** |
| loki | 3.6.7 | gateway | Değişiklik yok |
| promtail | 3.0.0 | her iki node | Değişiklik yok |
| node_exporter | 1.8.2 | her iki node | Değişiklik yok |

---

## 13. Deploy Workflow (V1.1)

### node1'de Rutin Deploy

```bash
cd /var/www/teqlif.com
git pull
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif teqlif-staging
```

### gateway'de nginx Config Güncelleme

```bash
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.1/gateway/nginx/http-zones.conf /etc/nginx/conf.d/http-zones.conf
sudo cp deploy/scale/V1.1/gateway/nginx/teqlif.conf /etc/nginx/sites-available/teqlif.conf
sudo nginx -t && sudo systemctl reload nginx
```

### gateway'de Alertmanager Config Güncelleme

```bash
cd /var/www/teqlif.com && git pull
set -a && source /etc/alertmanager/alertmanager.env && set +a
envsubst '$TELEGRAM_BOT_TOKEN $TELEGRAM_CHAT_ID' \
  < deploy/scale/V1.1/gateway/alertmanager.yml.template \
  | sudo tee /etc/alertmanager/alertmanager.yml > /dev/null
sudo systemctl restart alertmanager
```

### Microcache Dizini (ilk kurulumda bir kez)

```bash
sudo mkdir -p /var/cache/nginx/teqlif
sudo chown www-data:www-data /var/cache/nginx/teqlif
```

---

## 14. Rollback Planı

| Senaryo | Aksiyon |
|---|---|
| gateway çöker | Cloudflare'de `teqlif.com` A → node1 (135.125.175.223). TTL 60s |
| WireGuard bozulur | `sudo systemctl stop wg-quick@wg0` |
| nginx config hatası | `nginx -t` hata verir, reload gerçekleşmez — eski config devrede |
| Alertmanager çöker | Prometheus çalışmaya devam eder, sadece bildirim gitmez |
| V1.0'a dönüş | `deploy/scale/V1.0/` config'lerini uygula |

---

## 15. V1.1 Uygulama Sırasında Karşılaşılan Sorunlar

### 1. proxy_hide_header çalışmadı

**Sorun:** `proxy_hide_header X-Frame-Options` server block'a eklendi ama backend başlıkları hâlâ geçiyordu.

**Çözüm:** Kaynakta düzeltildi — `backend/app/security/middleware.py`'den statik başlıklar kaldırıldı.

### 2. alertmanager --config.expand-env flag'ı yok

**Sorun:** 0.27.0 build'i `--config.expand-env` flag'ını tanımıyor.

**Çözüm:** Deploy sırasında `envsubst` ile template'ten gerçek config oluşturuluyor.

### 3. gateway'de .env yok

**Sorun:** `EnvironmentFile=/var/www/teqlif.com/backend/.env` gateway'de mevcut değil (.env gitignore'da).

**Çözüm:** `/etc/alertmanager/alertmanager.env` gateway'de elle oluşturulur. `envsubst` bu dosyayı kaynak alır.

### 4. Push yapılmadan deploy denemesi

**Sorun:** Local commit push edilmeden gateway'de `git pull` çekildi, dosyalar bulunamadı.

**Çözüm:** Deploy öncesi mutlaka `git push` yapılmalı.

---

## 16. V1.2 Adayları

- **gateway SPOF fallback otomasyonu:** Cloudflare Health Check veya TTL-60s DNS failover.
- **Prometheus alert kanalı genişletme:** Email fallback (SMTP) Alertmanager'a eklenebilir.
- **nginx cache hit oranı izleme:** `X-Cache-Status` loglanıp Prometheus metric'e dönüştürülebilir.
- **PostgreSQL read replica:** Okuma sorguları yavaşlarsa (V2.0 adayı).

---

## 17. Commit Referansları

| Hash | İçerik |
|---|---|
| `bec02286` | Adım 1 — staging nginx block güçlendirme |
| `0c021a2f` | proxy_hide_header eklendi (sonradan yetersiz bulundu) |
| `8b07e89a` | Backend security middleware'den statik başlıklar kaldırıldı |
| `90aedd4b` | Adım 3 — nginx microcaching (256MB zone, 5s TTL) |
| `ef23a889` | Adım 4 — Alertmanager config (envsubst yaklaşımı) |
| `fcaeeedb` | alertmanager.service EnvironmentFile düzeltmesi |
| `4f02f00f` | V1.1 tüm adımlar tamamlandı |

---

## 18. Dosya Referansları

```
deploy/scale/V1.1/
├── plan.md                                  # Mimari kararlar + planlama
├── task.md                                  # Adım adım uygulama logu
├── wireguard/
│   ├── node1-wg0.conf                       # V1.0 ile aynı
│   └── gateway-wg0.conf                     # V1.0 ile aynı
├── gateway/
│   ├── prometheus.yml                       # alerting + rule_files eklendi
│   ├── prometheus-rules.yml                 # Alert kuralları (5 kural)
│   ├── alertmanager.yml.template            # Telegram config template
│   ├── loki-config.yml                      # V1.0 ile aynı
│   ├── promtail-config.yml                  # V1.0 ile aynı
│   ├── nginx/
│   │   ├── teqlif.conf                      # Microcache + staging block güçlendirme
│   │   └── nginx-http-zones.conf            # proxy_cache_path eklendi
│   └── systemd/
│       ├── alertmanager.service             # Yeni
│       ├── prometheus.service               # V1.0 ile aynı
│       ├── loki.service                     # V1.0 ile aynı
│       ├── promtail.service                 # V1.0 ile aynı
│       └── node_exporter.service            # V1.0 ile aynı
└── node1/
    ├── promtail-config.yml                  # V1.0 ile aynı
    ├── nginx/
    │   └── uploads.teqlif.com               # immutable (V1.0'da zaten mevcuttu)
    └── systemd/
        ├── teqlif.service                   # V1.0 ile aynı
        ├── teqlif-staging.service           # V1.0 ile aynı
        └── ...                              # Diğerleri V1.0 ile aynı

backend/app/security/middleware.py           # Statik header'lar kaldırıldı (V1.1)
```
