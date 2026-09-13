# Teqlif Scale V1.0 — Kapsamlı Mimari ve Uygulama Belgesi

> **Uygulama tarihi:** 2026-09-07  
> **Durum:** Aktif (production)  
> **Kaynak dosyalar:** `deploy/scale/V1.0/`

---

## 1. Genel Bakış

Scale V1.0, Teqlif'in monolith (tek-sunucu) mimarisinden iki-sunuculu (gateway + node1) mimariye geçişidir. Amaç:

- **node1'e RAM iade etmek** — Prometheus + Loki node1'de çalışıyordu, backend ile kaynak rekabeti yapıyordu.
- **Edge proxy ayrımı** — SSL terminasyonu, rate limiting ve güvenlik kuralları gateway'e taşındı.
- **Observability bağımsızlığı** — Monitoring, izlediği sistemden (node1) bağımsız ayrı bir makinede çalışır.
- **Upload trafiğini gateway'den ayırmak** — Netcup 100 Mbps 24h ortalama throttle sınırını aşmamak için medya trafiği node1'e direkt yönlendirildi.

---

## 2. Donanım

### node1 — OVH Limburg (Ana Backend)

| Parametre | Değer |
|---|---|
| Public IP | 135.125.175.223 |
| WireGuard IP | 10.10.0.1 |
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 2 GiB Swap |
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

**Netcup throttle kuralı hakkında:** 24 saatlik rolling average 100 Mbps'yi aşarsa throttle başlar, düşünce otomatik kalkar. Bu nedenle büyük medya transferleri (görsel yükleme, video) gateway'den geçirilmez — `uploads.teqlif.com` DNS Only → node1 doğrudan.

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
                    │  nginx (SSL termination, rate limit)     │
                    │  WireGuard (10.10.0.2)                   │
                    │  Prometheus  :9090                       │
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

### Trafik Akışı Detayı

```
API/WebSocket:
  Mobil → Cloudflare → gateway:443 (nginx SSL) → WireGuard → node1:8000 (FastAPI)

uploads.teqlif.com (medya indirme):
  Mobil → DNS Only → node1:443 (nginx) → localhost:9010 (MinIO)
  ↑ Cloudflare yok, gateway yok — node1'e direkt

Medya yükleme (POST /api/upload):
  Mobil → Cloudflare → gateway:443 → WireGuard → node1:8000 → MinIO

LiveKit WebRTC sinyalizasyon (/rtc WSS):
  Mobil → Cloudflare → gateway:443 (nginx /rtc proxy) → WireGuard → node1:7880

LiveKit WebRTC medya (UDP — PROXY EDİLEMEZ):
  Mobil → node1:50000-60000/udp  (doğrudan, gateway bypass)
  Mobil → node1:7882/udp+tcp     (RTC)
  Mobil → node1:3478/udp         (STUN/TURN)

Monitoring (WireGuard üzerinden):
  gateway Prometheus → 10.10.0.1:9100 (node1 node_exporter)
  gateway Prometheus → 10.10.0.1:9187 (postgres-exporter)
  gateway Prometheus → 10.10.0.1:7881 (livekit metrics)
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
| Prometheus | ❌ (durduruldu) | ✅ | Observability bağımsızlığı; node1'e ~300 MB RAM iade |
| Loki | ❌ (durduruldu) | ✅ | Log storage için 60 GB SSD; node1'e ~200 MB RAM iade |
| promtail | ✅ (→ gateway Loki) | ✅ (→ localhost Loki) | Her iki node'da |
| node_exporter | ✅ | ✅ | Her iki node'da |
| WireGuard | ✅ (10.10.0.1) | ✅ (10.10.0.2) | Özel ağ tüneli |
| fail2ban | ✅ | ✅ | Bağımsız |

**node1'e kazandırılan kapasite:** ~500–700 MB RAM (Prometheus + Loki kaldırıldı).

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

**Cloudflare SSL/TLS modu:** Full (Strict) — gateway kendi Let's Encrypt sertifikasını sunar.

**Silinen kural:** `teqlif.com → www.teqlif.com` Cloudflare Redirect Rule. Bu kural `/api/health` gibi endpoint'leri 301'e yönlendirip kırıyordu.

---

## 6. WireGuard VPN Tüneli

**Amaç:** gateway ↔ node1 arası şifreli özel ağ. Monitoring trafiği, API proxy trafiği hepsi bu tünelden geçer. Dış dünyaya sadece WireGuard UDP portu (51820) açılır.

### node1 — `/etc/wireguard/wg0.conf`

```ini
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <NODE1_PRIVATE_KEY>
PostUp   = ufw allow 51820/udp
PostDown = ufw delete allow 51820/udp

[Peer]
PublicKey = <GATEWAY_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32
```

### gateway — `/etc/wireguard/wg0.conf`

```ini
[Interface]
Address = 10.10.0.2/24
ListenPort = 51820
PrivateKey = <GATEWAY_PRIVATE_KEY>

[Peer]
PublicKey = <NODE1_PUBLIC_KEY>
AllowedIPs = 10.10.0.1/32
Endpoint = 135.125.175.223:51820
PersistentKeepalive = 25
```

**Gerçek public key'ler (referans):**
- node1: `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=`
- gateway: `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=`

**Kurulum:**
```bash
sudo apt install -y wireguard
wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
sudo chmod 600 /etc/wireguard/privatekey /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

---

## 7. gateway nginx Yapılandırması

### Rate Limit Zone'ları — `/etc/nginx/conf.d/http-zones.conf`

```nginx
limit_req_zone $binary_remote_addr zone=general:10m  rate=60r/m;
limit_req_zone $binary_remote_addr zone=auth:10m     rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m      rate=1800r/m;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
limit_req_status 429;
```

### Upstream Tanımları

```nginx
upstream teqlif_backend {
    server 10.10.0.1:8000;
    keepalive 32;
}

upstream livekit_backend {
    server 10.10.0.1:7880;
    keepalive 8;
}
```

### SSL Sertifika Notu

Certbot gateway'de `certonly --nginx -d teqlif.com -d www.teqlif.com -d staging.teqlif.com` ile çalıştırıldı. Sertifika **`staging.teqlif.com/`** dizini altına kaydedildi (expand seçildi — o cert zaten mevcuttu):

```nginx
ssl_certificate     /etc/letsencrypt/live/staging.teqlif.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/staging.teqlif.com/privkey.pem;
```

**Dikkat:** `teqlif.com/` değil, `staging.teqlif.com/` — certbot ilk expand edilen sertifikanın ismini esas alır.

### Önemli Location Blokları

```nginx
# LiveKit sinyalizasyon — settings.livekit_url = "wss://teqlif.com/rtc"
location /rtc { proxy_pass http://livekit_backend; ... }

# DM/bildirim/feed WebSocket
location ~* /ws$ { proxy_pass http://teqlif_backend; ... upgrade; }

# Chat WebSocket
location /api/chat/ { proxy_pass http://teqlif_backend; ... upgrade; }

# Büyük upload (100M limit)
location /api/upload { client_max_body_size 100M; ... }

# Auth rate limit sıkı
location /api/auth { limit_req zone=auth burst=3 nodelay; ... }

# /uploads/ fallback — tercih edilen yol uploads.teqlif.com
location /uploads/ { proxy_pass http://10.10.0.1:9010/teqlif/; }

# Staging (ayrı server block)
server { server_name staging.teqlif.com; proxy_pass http://10.10.0.1:8001; }
```

---

## 8. node1 Servis Konfigürasyonları

### FastAPI prod — `teqlif.service`

```ini
[Service]
User=tucibeyin
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/var/www/teqlif.com/backend/.env
ExecStartPre=/var/www/teqlif.com/venv/bin/python -m alembic upgrade head
ExecStartPre=/var/www/teqlif.com/venv/bin/python /var/www/teqlif.com/backend/scripts/sync_main.py
ExecStart=/var/www/teqlif.com/venv/bin/uvicorn main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 4 \
    --loop uvloop \
    --proxy-headers \
    --forwarded-allow-ips 10.10.0.2
```

**Kritik noktalar:**
- `--host 0.0.0.0` — gateway WireGuard (10.10.0.1) üzerinden erişebilsin. `127.0.0.1` olursa gateway ulaşamaz.
- `--forwarded-allow-ips 10.10.0.2` — Sadece gateway'in WireGuard IP'sinden gelen X-Forwarded-For başlığını güven. Sahte başlık kabul edilmez.
- `ExecStartPre` alembic — Her restart'ta migration otomatik çalışır.

### FastAPI staging — `teqlif-staging.service`

```ini
[Service]
WorkingDirectory=/var/www/teqlif.com/backend
EnvironmentFile=/var/www/teqlif.com/backend/.env.staging
ExecStart=... --port 8001 --workers 2 --forwarded-allow-ips 10.10.0.2
```

**Dikkat:** WorkingDirectory `/var/www/teqlif.com/backend` — production ile aynı dizin. `.env.staging` ile Redis, DB ve MinIO bucket'ı ayrışır. `/var/www/teqlif-staging.com/` diye bir dizin yoktur.

### uploads.teqlif.com nginx — node1'de

```nginx
server {
    listen 443 ssl;
    server_name uploads.teqlif.com;
    ssl_certificate /etc/letsencrypt/live/uploads.teqlif.com/fullchain.pem;

    location / {
        proxy_pass http://127.0.0.1:9010/teqlif/;
        proxy_buffering off;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
```

URL dönüşümü: `https://uploads.teqlif.com/abc.jpg` → MinIO `teqlif` bucket'ındaki `abc.jpg` objesi.

---

## 9. node1 Firewall (UFW) Kuralları

```bash
# WireGuard
ufw allow 51820/udp

# Gateway'e API erişimi — sadece WireGuard IP'den
ufw allow from 10.10.0.2 to any port 8000   # prod API
ufw allow from 10.10.0.2 to any port 8001   # staging API
ufw allow from 10.10.0.2 to any port 9100   # node_exporter
ufw allow from 10.10.0.2 to any port 9187   # postgres-exporter
ufw allow from 10.10.0.2 to any port 7881   # livekit metrics

# Public'ten 8000/8001 kapat (sıra önemli — allow önce, deny sonra)
ufw deny 8000
ufw deny 8001

# LiveKit — herkese açık (UDP proxy edilemez)
# 50000:60000/udp  WebRTC medya
# 7882/udp+tcp     RTC
# 5349/tcp+udp     TURN TLS
# 3478/udp         STUN/TURN
```

**Loopback (127.0.0.1) UFW tarafından varsayılan olarak izinlidir** — node1'in iç nginx → MinIO bağlantısı etkilenmez.

---

## 10. Monitoring Stack

### Prometheus — gateway'de

**Config:** `deploy/scale/V1.0/gateway/prometheus.yml`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs: [{targets: ['localhost:9090']}]

  - job_name: 'node-gateway'
    static_configs: [{targets: ['localhost:9100'], labels: {node: gateway}}]

  - job_name: 'node-node1'
    static_configs: [{targets: ['10.10.0.1:9100'], labels: {node: node1}}]

  - job_name: 'livekit'
    static_configs: [{targets: ['10.10.0.1:7881'], labels: {node: node1}}]

  - job_name: 'postgres'
    static_configs: [{targets: ['10.10.0.1:9187'], labels: {node: node1}}]
```

node1'deki node_exporter `0.0.0.0:9100`'de dinliyor — WireGuard üzerinden gateway scrape edebilir. UFW: `allow from 10.10.0.2 to any port 9100`.

### Loki — gateway'de

- Port: 3100 (0.0.0.0 — WireGuard'dan push kabul eder)
- Storage: `/var/lib/loki/` (60 GB SSD)
- Retention: 720 saat (30 gün)
- Schema: TSDB v13

### Promtail

**node1** (`/etc/promtail-config.yml`): Logları `http://10.10.0.2:3100/loki/api/v1/push`'a gönderir.
- Kaynaklar: `/var/log/teqlif/*.log`, `/var/log/nginx/access.log`, `/var/log/nginx/error.log`, systemd journal, worker logları

**gateway** (`/etc/promtail-config.yml`): Logları `http://localhost:3100/loki/api/v1/push`'a gönderir.
- Kaynaklar: kendi nginx ve systemd journal logları

### Binary Sürümleri

| Binary | Sürüm |
|---|---|
| prometheus | 2.51.0 |
| loki | 3.6.7 |
| promtail | 3.0.0 |
| node_exporter | 1.8.2 |

Binary'ler node1'den `scp` ile gateway'e kopyalandı (node1 WireGuard üzerinden).

---

## 11. Mobil Uygulama — imgUrl() Değişikliği

Scale V1.0 ile `uploads.teqlif.com` eklendi. Mobil uygulamada tüm görsel URL'leri `imgUrl()` fonksiyonu üzerinden geçer.

### `mobile/lib/config/api.dart`

```dart
const String kBaseHost = String.fromEnvironment(
  'BASE_HOST',
  defaultValue: 'https://www.teqlif.com',
);
const String kBaseUrl = '$kBaseHost/api';

const String kUploadsHost = String.fromEnvironment(
  'UPLOADS_HOST',
  defaultValue: 'https://uploads.teqlif.com',
);

/// /uploads/abc.jpg → https://uploads.teqlif.com/abc.jpg (node1 direkt, gateway bypass)
/// http ile başlıyorsa → olduğu gibi
/// Diğer relative → kBaseHost prefix'i
String imgUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  if (path.startsWith('/uploads/')) {
    return '$kUploadsHost${path.substring('/uploads'.length)}';
  }
  return '$kBaseHost$path';
}
```

**Dönüşüm örneği:**
- `/uploads/abc.jpg` → `https://uploads.teqlif.com/abc.jpg` (gateway bypass ✅)
- `https://example.com/img.jpg` → aynen geçer
- `/api/foo` → `https://www.teqlif.com/api/foo`

**Neden gerekli:** Eski `_buildImageUrl()` implementasyonu `kBaseUrl` prefix'i ile `https://www.teqlif.com/uploads/abc.jpg` oluşturuyordu. Bu URL Cloudflare → gateway → node1:9010 (MinIO) zincirinden geçiyor, gateway `/uploads/` → MinIO proxy için UFW port 9010 gerektirir ve büyük dosyalarda gateway throttle riski taşır.

---

## 12. Backend — Önemli Davranışlar

### storage_service.py — URL Format

`upload_bytes()` ve `upload_file()` her zaman **relative path** döner:
```python
return f"/uploads/{key}"  # Örnek: /uploads/a18c57995dde4e5cb75147c88215ceb5.jpg
```

Mobil `imgUrl()` bu relative path'i `uploads.teqlif.com` ile çözer.

### auto_mod.py — İçerik Filtresi

`analyze_listing_text()` ilan başlık + açıklamasını filtreler. **better_profanity substring matching Türkçe metinde false-positive üretir** (örn: "fakat", "analiz" gibi normal kelimeler içinde İngilizce küfür bulur). Bu nedenle `analyze_listing_text`'te `better_profanity.contains_profanity()` kaldırıldı — JSON bad_words sözlüğü + tam kelime (token) eşleşmesi kullanılır.

```python
def analyze_listing_text(title: str, description: str = "") -> bool:
    combined = f"{title} {description or ''}".strip()
    if not combined:
        return False
    return analyze_text_all(combined)  # JSON sözlük, tam kelime eşleşmesi
```

### teqlif/teqlif-staging Farkı

Production ve staging aynı kod tabanı, aynı venv, aynı WorkingDirectory. Fark `.env` ve `.env.staging` dosyalarında:
- Redis URL
- PostgreSQL DB adı
- MinIO bucket adı (`teqlif` vs `teqlif-staging`, `teqlif-dm` vs `teqlif-dm-staging`)

---

## 13. SSL Sertifika Yapısı

### gateway

Certbot `staging.teqlif.com` sertifikasına `teqlif.com` ve `www.teqlif.com` expand etti:
```
/etc/letsencrypt/live/staging.teqlif.com/
├── fullchain.pem   # teqlif.com + www.teqlif.com + staging.teqlif.com
└── privkey.pem
```

node1'de var olan livekit deploy hook (`/etc/letsencrypt/renewal-hooks/deploy/livekit-cert.sh`) node1'den kopyalandığında gateway'e de geldi — gateway'de LiveKit yok, `sudo rm` ile silindi.

### node1 — uploads.teqlif.com

```
/etc/letsencrypt/live/uploads.teqlif.com/
├── fullchain.pem
└── privkey.pem
```

`certbot certonly --nginx -d uploads.teqlif.com` ile alındı. DNS Only → gateway bypass → certbot HTTP-01 challenge node1'e doğrudan ulaştı.

---

## 14. Deploy Workflow

### node1'de Rutin Deploy

```bash
cd /var/www/teqlif.com
git pull
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif teqlif-staging
```

### Migration Varsa

```bash
git pull && cd backend && alembic upgrade head && cd .. && \
python3 backend/scripts/sync_translations.py && \
sudo systemctl restart teqlif teqlif-staging
```

### gateway'de Config Güncelleme (nginx değiştiyse)

```bash
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.0/gateway/nginx/teqlif.conf /etc/nginx/sites-available/teqlif.conf
sudo nginx -t && sudo systemctl reload nginx
```

### Monitoring Config Güncelleme (gateway'de)

```bash
sudo cp deploy/scale/V1.0/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus

sudo cp deploy/scale/V1.0/gateway/loki-config.yml /etc/loki/config.yml
sudo systemctl restart loki
```

---

## 15. Uygulama Sırasında Karşılaşılan Sorunlar

### 1. `--host 127.0.0.1` — gateway erişemiyordu

**Sorun:** `teqlif.service` ve `teqlif-staging.service`'de uvicorn `127.0.0.1`'de dinliyordu. gateway WireGuard'dan (10.10.0.1 adresiyle) bağlanmaya çalışınca 502 alıyordu.

**Çözüm:** `--host 0.0.0.0`. UFW `deny 8000` ile public erişim zaten kapalı; loopback hariç sadece `10.10.0.2`'ye izin var.

### 2. `teqlif-staging.service` yanlış WorkingDirectory

**Sorun:** `WorkingDirectory=/var/www/teqlif-staging.com/backend` — bu dizin mevcut değil. Service başlamıyordu.

**Çözüm:** `WorkingDirectory=/var/www/teqlif.com/backend` + `EnvironmentFile=/var/www/teqlif.com/backend/.env.staging`.

### 3. gateway'de livekit deploy hook

**Sorun:** node1 letsencrypt dizini gateway'e `scp` ile kopyalanırken `renewal-hooks/deploy/livekit-cert.sh` de geldi. gateway'de LiveKit yok; renewal sırasında hook çalışıp hata veriyordu.

**Çözüm:** `sudo rm /etc/letsencrypt/renewal-hooks/deploy/livekit-cert.sh`

### 4. gateway certbot — cert path yanlış

**Sorun:** nginx config'de `ssl_certificate /etc/letsencrypt/live/teqlif.com/fullchain.pem` yazılıydı. Certbot sertifikayı `staging.teqlif.com/` altına kaydetti (expand).

**Çözüm:** Cert path'i `staging.teqlif.com/` olarak güncellendi.

### 5. Cloudflare Redirect Rule

**Sorun:** `teqlif.com → www.teqlif.com` redirect kuralı Cloudflare'de mevcuttu. `/api/health` 301 dönüyordu.

**Çözüm:** Cloudflare panelinde Redirect Rule silindi.

### 6. `sudo git pull` gateway'de başarısız

**Sorun:** `root` kullanıcısının GitHub SSH key'i yok. `sudo git pull` permission denied.

**Çözüm:** `git pull` (sudo'suz). Repo `tucibeyin` kullanıcısına ait.

### 7. avatar görünmüyordu — `_buildImageUrl()` hatası

**Sorun:** `profile_screen.dart`'ta `_buildImageUrl()` şöyle çalışıyordu:
```dart
final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
return '$origin$url';  // https://www.teqlif.com/uploads/abc.jpg
```
Bu URL Cloudflare → gateway → MinIO zincirinden geçiyor. MinIO'ya `10.10.0.1:9010` üzerinden ulaşmaya çalışıyor ama UFW izni yoktu + gateway throttle riski.

**Çözüm:** `_buildImageUrl()` → `imgUrl()`. Artık `uploads.teqlif.com` → node1 direkt.

### 8. İlan content policy false-positive

**Sorun:** `better_profanity` kütüphanesi İngilizce substring matching yapıyor. "fakat", "analiz" gibi normal Türkçe kelimeler `CONTENT_POLICY_VIOLATION` üretiyordu.

**Çözüm:** `analyze_listing_text`'ten `better_profanity.contains_profanity()` çağrısı kaldırıldı. JSON sözlük tabanlı tam kelime eşleşmesi yeterli.

---

## 16. Rollback Planı

| Senaryo | Aksiyon |
|---|---|
| gateway çöker | Cloudflare'de `teqlif.com` A → node1 (135.125.175.223). TTL 60s → ~1 dk yayılır |
| WireGuard bozulur | `sudo systemctl stop wg-quick@wg0` — SSH etkilenmez, tünel kapanır |
| nginx config hatası | `sudo nginx -t` hata verir, reload gerçekleşmez — eski config devrede kalır |
| Servise geçiş sonrası | `deploy/scale/monolith/systemd/teqlif.service` ile eski konfigürasyona dön |

---

## 17. Açık Konular ve V1.1 Adayları

### Doğrulanmayı Bekleyen (Adım 8 artıklar)
- [x] WebSocket (DM, bildirim, feed) bağlantısı — doğrulandı ✅
- [x] LiveKit WebRTC ICE — canlı arama ile doğrulandı ✅
- [x] MinIO presigned DM URL'leri — canlı DM ile doğrulandı ✅

### V1.1 Adayları
- **nginx microcaching:** Gateway'de feed + listing API yanıtları için 1-5 saniyelik mikro cache. WS ve chat hariç. node1 yükünü ciddi ölçüde azaltır.
- **gateway SPOF fallback otomasyonu:** Cloudflare Health Check veya TTL-60s DNS failover.
- **Cache-Control `immutable`:** `uploads.teqlif.com` nginx'te `no-transform` yerine `immutable` — Cloudflare CDN cache hit oranını artırır.

### V2.0+
| Faz | Ne | Tetikleyici |
|---|---|---|
| V2.0 | PostgreSQL streaming read replica | Okuma sorguları yavaşlarsa |
| V2.1 | FastAPI replika (node3) | API yanıt süresi bozulursa |
| V2.2 | Redis Sentinel + Replica | Redis SPOF kabul edilemez hale gelirse |
| V3.0 | MinIO distributed mode | Disk dolumu yaklaşırsa |

---

## 18. Commit Referansları

| Hash | İçerik |
|---|---|
| `f535a48e` | Prometheus + Loki node1'den gateway'e taşındı — node1 RAM iade |
| `074fc885` | `deploy/` klasörü oluşturuldu — monolith + scale/V1.0 yapısı |
| `7c4577ad` | WireGuard config dosyaları |
| `f69a3f02` | gateway monitoring stack config'leri |
| `e29e5ddd` | gateway nginx + SSL, UFW sertleştirme |
| `ed96b11b` | node1 servisleri — `--host 0.0.0.0`, `--forwarded-allow-ips`, staging fix |
| `b5d5ddbc` | DNS değişikliği tamamlandı — tüm adımlar done |
| `207fd8c3` | Adım 7 — imgUrl(), uploads.teqlif.com, certbot gateway |
| `cd92a8e2` | task.md + plan.md tam uygulama kaydı |
| `6ce08fa3` | profile_screen.dart `_buildImageUrl()` → `imgUrl()` fix |
| `de41ed52` | auto_mod.py — better_profanity false-positive fix |

---

## 19. Dosya Referansları

```
deploy/scale/V1.0/
├── plan.md                                  # Mimari kararlar + planlama
├── task.md                                  # Adım adım uygulama logu
├── wireguard/
│   ├── node1-wg0.conf                       # node1 WireGuard şablonu
│   └── gateway-wg0.conf                     # gateway WireGuard şablonu
├── gateway/
│   ├── prometheus.yml                       # Prometheus scrape config
│   ├── loki-config.yml                      # Loki storage + retention
│   ├── promtail-config.yml                  # gateway promtail (→ localhost Loki)
│   ├── nginx/
│   │   ├── teqlif.conf                      # Ana nginx config (SSL, proxy, WS)
│   │   └── nginx-http-zones.conf            # Rate limit zone tanımları
│   └── systemd/
│       ├── prometheus.service
│       ├── loki.service
│       ├── promtail.service
│       └── node_exporter.service
└── node1/
    ├── promtail-config.yml                  # node1 promtail (→ 10.10.0.2 Loki)
    ├── nginx/
    │   └── uploads.teqlif.com               # uploads subdomain nginx config
    └── systemd/
        ├── teqlif.service                   # prod — --host 0.0.0.0, 4 workers
        ├── teqlif-staging.service           # staging — --host 0.0.0.0, 2 workers
        ├── node_exporter.service
        ├── promtail.service
        ├── minio.service
        ├── livekit.service
        ├── teqlif-worker.service
        ├── teqlif-worker-critical.service
        ├── redis-backup.service
        └── redis-backup.timer

mobile/lib/config/api.dart                   # kUploadsHost + imgUrl()
backend/app/core/auto_mod.py                 # İçerik filtresi — better_profanity fix
backend/app/services/storage_service.py      # upload_bytes → /uploads/{key} döner
```
