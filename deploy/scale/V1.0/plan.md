# Teqlif Scale Planı — V1.0
> **Hostname eşleştirme:** `node1` = OVH Limburg (ana backend) | `gateway` = Netcup Nürnberg (edge proxy + observability)
> **Tarih:** 2026-09-07 | **Durum:** ✅ UYGULAMAYA ALINDI (2026-09-07)

## Uygulama Özeti

Tüm adımlar `deploy/scale/V1.0/task.md`'de belgelenmiştir. Temel sonuçlar:

| Bileşen | Durum |
|---|---|
| WireGuard (node1↔gateway) | ✅ Aktif — handshake ve ping doğrulandı |
| gateway nginx + SSL | ✅ Let's Encrypt (certbot, teqlif.com+www+staging) |
| Prometheus + Loki + promtail | ✅ gateway'de, tüm target'lar `up` |
| DNS: teqlif.com → gateway | ✅ Cloudflare Proxied 94.16.105.135 |
| DNS: uploads.teqlif.com → node1 | ✅ DNS Only 135.125.175.223 |
| node1 UFW sertleştirme | ✅ 8000/8001/9100/9187/7881 sadece gateway'e açık |
| Mobil imgUrl() | ✅ /uploads/ → uploads.teqlif.com (gateway bypass) |

**Uygulama dışı kalan:** Adım 4b (promtail→gateway Loki), 4c (node1 Prometheus+Loki durdur), 4d (node_exporter WireGuard IP) — bunlar task.md'de de tamamlandı.

**Önemli düzeltmeler uygulama sırasında:**
- `teqlif.service --host 0.0.0.0` (127.0.0.1 değil) — gateway WireGuard üzerinden erişebilsin
- `teqlif-staging.service` WorkingDirectory: `/var/www/teqlif-staging.com/` değil `/var/www/teqlif.com/`, EnvironmentFile: `.env.staging`
- gateway certbot: `staging.teqlif.com` cert altında tüm domainler birleştirildi; livekit deploy hook silindi

---

---

## 1. Mevcut Durum — node1 (OVH Limburg)

### Donanım
| Parametre | Değer |
|---|---|
| CPU | Intel Haswell 6 çekirdek @ 3.09 GHz |
| RAM | 11.4 GiB + 12 GiB Swap |
| Disk | 98.3 GiB NVMe |
| Ağ | **2 Gbps / unmetered** (kota yok) |
| Geekbench 6 | 1058 single / 4404 multi |

### node1 Kaynak Tüketicileri (Büyükten Küçüğe)

**1. LiveKit — Bant Genişliği + CPU**
WebRTC SFU; sesli/görüntülü aramada gerçek zamanlı UDP medya akışları işler. Aktif arama başına ~1-4 Mbps upstream + downstream. OVH'ın unmetered 2Gbps hattının doğrudan faydalanıcısı. Kesinlikle node1'de kalmalı — UDP proxy edilemez, bant genişliği kritik.

**2. ARQ Workers (ML) — CPU + RAM**
`worker.py`'de ML ağırlıklı görevler:
- `generate_embedding_task` / `generate_listing_embedding_task` — PyTorch sentence-transformer (384 boyutlu vektör). Kod yorumu: *"thread-blocking yaptığı için FastAPI'den ayrı çalışmalıdır"*
- `update_user_preference_embedding` — numpy ağırlıklı ortalama vektör hesabı
- `train_bpr_task` (Cumartesi 03:00) — BPR collaborative filtering modeli
- `train_item2vec_task` (Pazar 04:00) — Item2Vec modeli
- `train_kmeans_cold_start_task` (Pazar 05:00) — 50-cluster K-Means
- `train_listing_quality_model_task` (Pazar 02:30) — GradientBoostingRegressor

Bu işler PostgreSQL + ClickHouse'a doğrudan, düşük gecikmeli erişim gerektirir. Gateway'e taşınamaz (2 vCPU + 1.9GB RAM yetersiz; PyTorch model tek başına ~300-500MB alır).

**3. ClickHouse — RAM + CPU**
Her 5 dakikada `flush_interactions_to_db` bulk insert. Her 15-20 dakikada karmaşık analitik sorgular (`compute_user_interests`, `sync_swipelive_interests`). Columnar engine RAM'e agresif; PostgreSQL ve Redis ile RAM rekabeti yaşar.

**4. PostgreSQL — RAM + Disk I/O**
`shared_buffers`, bağlantı havuzu, worker sorgularının çoğu buraya yüklenip buradan okunur. Disk I/O analitik yazma + normal OLTP yazmayla paylaşılıyor.

**5. Redis — RAM**
4 GB `maxmemory`. Relationship cache, feed cache, call presence, ARQ kuyrukları, interaction queue, Thompson Sampling parametreleri, embedding cursor. Tüm sistem buraya bağlı — tek SPOF.

**6. MinIO — Disk + Bant Genişliği**
`teqlif` (public) + `teqlif-dm` (private) bucket. Upload/download trafiği; DM medya temizlik worker'ı her gün MinIO'ya erişir. OVH unmetered hat dolaylı faydalanıcı.

**7. FastAPI (prod + staging) — Orta CPU/RAM**
Stateless; tüm durumu Redis/PostgreSQL'de. Gecikmesi düşük tutulmalı → DB/Redis ile aynı node'da kalması avantajlı.

**8. Prometheus + Loki — RAM + Disk**
Prometheus TSDB scrape + retention. Loki log indexing. Her ikisi de RAM tüketir (~500MB-1GB toplam) ve üretim yükünden bağımsız olmalı — monitoring, izlediği sistemin kaynaklarını yememeli. **Bu servislerin gateway'e taşınması node1'e ~500MB-1GB RAM iade eder.**

### node1 Mevcut nginx Yapılandırması (Referans)

| Domain | Tip | Hedef | Not |
|---|---|---|---|
| `teqlif.com` | Reverse proxy | uvicorn :8000 | Rate limiting, bot engeli, güvenlik header'ları |
| `live.teqlif.com` | LiveKit proxy | :7880 | Ayrı SSL cert, WebRTC için DNS only |
| `minio.teqlif.com` | MinIO proxy | :9010 | DNS only, 500M upload |
| `staging.teqlif.com` | Reverse proxy | uvicorn :8001 | Staging MinIO bucket |
| `mottosoft.com` | Static site | `/var/www/mottosoft.com` | Plan dışı |
| `tucibeyin.com` | Static site | `/var/www/tucibeyin.com` | Plan dışı |
| `thevetaris.com` | Vetaris proxy | :8801 | Plan dışı |

**`/uploads/` Cache-Control:** `expires 30d; Cache-Control "public, no-transform"` — zaten ayarlı. Cloudflare CDN aktif. İyileştirme: `no-transform` kaldırılıp `immutable` eklenebilir.

**`/rtc` location:** node1 nginx'te zaten mevcut (`proxy_pass 127.0.0.1:7880`). gateway nginx'te aynı yapı kurulacak.

**MinIO gerçek portu:** nginx config'den doğrulandı → **9010** (settings.py default 9000, `.env` override ediyor).

### node1 Firewall Durumu (UFW)

**⛔ Grafana silinecek:** `3000/tcp ALLOW IN Anywhere` açığı güvenlik riski. Grafana kaldırılınca bu port zaten kapanacak (`apt remove grafana` + `ufw delete allow 3000/tcp`).

**Cloudflare IP whitelist:** UFW'de zaten tanımlı (tüm Cloudflare IPv4/IPv6 aralıkları).

**LiveKit açık portlar:**
```
50000:60000/udp  WebRTC medya (livekit.yaml port_range)
7882/udp          LiveKit UDP (RTC)
7882/tcp          LiveKit TCP fallback
7880/tcp          LiveKit HTTP sinyalizasyon (nginx /rtc proxy ile kapatılabilir)
5349/tcp+udp      TURN TLS
3478/udp          STUN/TURN UDP
```

### fail2ban Jail'leri

| Jail | Tetikleyici | Süre | Ban |
|---|---|---|---|
| `sshd` | 5 başarısız giriş | 60s | 1 saat |
| `nginx-req-limit` | 10 rate limit hit | 60s | 24 saat |
| `nginx-botscan` | 8 bot tarama isteği | 5 dakika | 7 gün |

---

## 2. Yeni Makine — gateway (Netcup Nürnberg)

### Donanım
| Parametre | Değer |
|---|---|
| CPU | 2 vCore (QEMU @ 2.29 GHz) |
| RAM | 2 GB + 1 GB Swap |
| Disk | 60 GB SSD (genişletilemiyor) |
| Ağ | 1 Gbps interface — **24h ortalama >100 Mbps → geçici throttle (100 Mbps)** |
| Geekbench 6 | 645 single / 1210 multi |

### Değerlendirme
1.9 GB RAM, ML worker, PostgreSQL replica veya ClickHouse barındırmak için yetersiz. Ağır iş yapacak bir backend node'u değil.

**Güçlü yanları:**
- 1 Gbps interface → nginx proxy için fazlasıyla yeterli; monitoring trafiği 24h ortalaması 100 Mbps'nin çok altında kalır
- 60 GB SSD → Prometheus TSDB + Loki log storage için ideal (node1'in daralan diski yerine)
- Düşük işletim maliyeti → daimi servis için uygun
- node1'den bağımsız çalışır → monitoring node1 çöktüğünde de ayakta kalabilir

**Ağ kısıtı — dikkat:**
24 saatlik ortalama trafik 100 Mbps'yi aşarsa Netcup geçici throttle uygular (ortalama düşünce otomatik kalkar). Bu nedenle büyük dosya upload/download trafiğinin gateway üzerinden **geçmemesi** kritik. Video yükleme gibi burst trafik `uploads.teqlif.com` → node1 doğrudan yönlendirmesiyle gateway'i atlamalı.

**Rol: Edge Proxy + Observability Node**

---

## 3. Önerilen Mimari — V1.0

```
İnternet
    │
    ▼
[gateway — Netcup Nürnberg]          [node1 — OVH Limburg]
  nginx  (SSL termination)    ──────▶   FastAPI prod
  WireGuard (VPN tüneli)      ◀──────   FastAPI staging
  Prometheus (scrape her ikisini)        PostgreSQL
  Loki  (her ikisinden log)              Redis
  promtail                               MinIO
  node_exporter                          ClickHouse
  fail2ban                               LiveKit  (UDP — gateway bypass)
                                         ARQ Workers (ML + DB)
                                         nginx (iç)
                                         WireGuard
                                         node_exporter
                                         promtail → gateway Loki
                                         fail2ban
```

### Trafik Akışı
```
Client  ──HTTP/WS──▶  gateway:443 (nginx SSL)
                            │ WireGuard şifreli tünel
                            ▼
                       node1:8000 (FastAPI)

LiveKit WebRTC medya (UDP):
Client  ──UDP──▶  node1 doğrudan  (gateway bypass — proxy edilemez)

Monitoring:
node1 node_exporter/promtail  ──WireGuard──▶  gateway Prometheus/Loki
```

### LiveKit İstisnası (Kritik)
WebRTC medya UDP kullanır, nginx üzerinden proxy **edilemez**. LiveKit sinyalizasyonu (`/rtc` WSS) gateway üzerinden proxy edilir; medya akışı (STUN/TURN/ICE) için node1'in public IP'si doğrudan erişilebilir kalır. node1 firewall'unda LiveKit UDP portları herkese açık tutulur.

---

## 4. Servis Dağılımı

| Servis | node1 (OVH) | gateway (Netcup) | Karar Gerekçesi |
|---|---|---|---|
| PostgreSQL | ✅ | ❌ | RAM + disk, worker'ların doğrudan erişimi |
| Redis | ✅ | ❌ | Tüm sistem tek bağımlılık |
| MinIO | ✅ | ❌ | Disk + OVH unmetered bant |
| ClickHouse | ✅ | ❌ | RAM yoğun, worker entegrasyonu |
| LiveKit | ✅ | ❌ | UDP medya + OVH unmetered bant |
| FastAPI prod | ✅ | ❌ | DB/Redis yakınlığı kritik |
| FastAPI staging | ✅ | ❌ | Aynı nedenle |
| ARQ Worker (genel) | ✅ | ❌ | ML (PyTorch/numpy) + DB/ClickHouse erişimi |
| ARQ Worker (critical) | ✅ | ❌ | Push notification, outbid, loser cascade — bulkhead pattern |
| nginx (iç) | ✅ | — | Sadece iç yönlendirme |
| **nginx (public)** | ❌ → iç | ✅ | SSL termination, edge |
| **Prometheus** | ❌ → taşınır | ✅ | Observability bağımsızlığı; node1'e ~300MB RAM iade |
| **Loki** | ❌ → taşınır | ✅ | Log storage için 58.9GB disk avantajı |
| ~~Grafana~~ | ✅ SİLİNDİ | ❌ | 2026-09-07 kaldırıldı — ~2.3 GB disk, ~200 MB RAM geri döndü |
| promtail | ✅ (node1 log → gateway) | ✅ (kendi logu) | Her iki node'da, gateway Loki'ye gönderir |
| node_exporter | ✅ | ✅ | Her iki node'da, gateway Prometheus scrape eder |
| WireGuard | ✅ | ✅ | Özel ağ tüneli (kernel-native, SaaS yok) |
| fail2ban | ✅ | ✅ | Bağımsız |

---

## 5. Grafana — ✅ Silindi (2026-09-07)

Grafana sadece görselleştirme katmanı; veri üretmiyor, saklamıyor, alert pipeline'ına dokunmuyor. Prometheus alert kuralları + Loki alert kuralları Grafana olmadan tam işlevsel çalışır.

Alert kuralı olmadığı SQLite DB üzerinden doğrulandı. `apt remove --purge grafana` + `rm -rf` ile tamamen kaldırıldı. UFW port 3000 kapatıldı. Sahte `30000:40000/udp` UFW kuralı da bu süreçte temizlendi.

---

## 6. Değişiklik Gereksinimleri

### Uygulama kodu — sıfır değişiklik
- `settings.redis_url` → node1 localhost, değişmez
- `settings.database_url` → node1 localhost, değişmez
- `database_clickhouse.py` → `host="localhost"` hardcoded, ClickHouse node1'de kalır, değişmez
- `settings.minio_dm_external_url` → zaten dış domain, değişmez
- `ws_manager` → Redis Stream fan-out zaten multi-node hazır
- CORS → `main.py`'de `teqlif.com` / `www.teqlif.com` sabitleri, gateway IP CORS'u etkilemez

### Deploy config — 4 değişiklik gerekli

**1. `deploy/promtail-config.yml` — Loki hedefini gateway'e yönlendir**

`clients.url` şu an `http://localhost:3100/...`. Prometheus + Loki gateway'e taşınınca:
```yaml
clients:
  - url: http://10.10.0.2:3100/loki/api/v1/push
```

**2. node1 uvicorn — proxy IP güveni**

`teqlif.service` ve `teqlif-staging.service` ExecStart'ta şu an:
```
--forwarded-allow-ips 127.0.0.1
```
Gateway → WireGuard (wg0) → node1:8000 zincirine geçince bu değer güncellenmeli:
```bash
# teqlif.service ExecStart'ta 127.0.0.1 yerine:
--forwarded-allow-ips=10.10.0.2
```
Aynı değişiklik `teqlif-staging.service` için de gerekli. Bu olmadan sahte X-Forwarded-For kabul edilebilir; firewall sertleştirme bunu engeller ama defense-in-depth açısından zorunlu.

**3. Prometheus scrape config — tüm `localhost` hedefleri node1 WireGuard IP'sine taşınır**

`/etc/prometheus/prometheus.yml` şu an node1'de çalışıyor ve tüm hedefler `localhost:xxxx`. Prometheus gateway'e taşınınca:

```yaml
# /etc/prometheus/prometheus.yml — gateway'de bu hale gelecek
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']           # gateway'in kendisi

  - job_name: 'livekit'
    static_configs:
      - targets: ['10.10.0.1:7881']

  - job_name: 'node_node1'
    static_configs:
      - targets: ['10.10.0.1:9100']

  - job_name: 'node_gateway'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'postgres'
    static_configs:
      - targets: ['10.10.0.1:9187']
```

**4. gateway nginx — `/rtc` LiveKit sinyalizasyon proxy'si**

`settings.livekit_url = "wss://teqlif.com/rtc"` — istemciler WebSocket bağlantısını `/rtc` path'i üzerinden kurar. gateway nginx'e bu location **eksikse LiveKit sinyalizasyonu çalışmaz**. Detay Adım 3'te (nginx config bloğunda `/rtc` upstream ayrı tanımlandı).

---

## 7. Uygulama Adımları

### Adım 1 — WireGuard Kurulumu (Sıfır downtime)

> WireGuard ayrı bir `wg0` arayüzü açar — mevcut `eth0` ve SSH bağlantısına dokunmaz.
> Özel ağ adresleri: **node1 → `10.10.0.1`** | **gateway → `10.10.0.2`**

**node1'de:**
```bash
sudo apt install -y wireguard

# Key çifti üret
wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
sudo chmod 600 /etc/wireguard/privatekey

# Public key'i not al — gateway config'ine girecek
sudo cat /etc/wireguard/publickey
```

**gateway'de:**
```bash
sudo apt install -y wireguard

wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
sudo chmod 600 /etc/wireguard/privatekey

# Public key'i not al — node1 config'ine girecek
sudo cat /etc/wireguard/publickey
```

**node1'de `/etc/wireguard/wg0.conf`:**
```ini
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <NODE1_PRIVATE_KEY>

[Peer]
PublicKey = <GATEWAY_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32
```

**gateway'de `/etc/wireguard/wg0.conf`:**
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

```bash
# node1'de — WireGuard portunu UFW'e ekle
sudo ufw allow 51820/udp

# Her iki node'da — başlat ve boot'ta otomatik başlasın
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0

# Bağlantı testi
# gateway'den:
ping 10.10.0.1
# node1'den:
ping 10.10.0.2

# Tünel durumu
sudo wg show
```

### Adım 2 — gateway Taban Kurulumu (nginx + Prometheus + Loki + node_exporter)

> **Not:** gateway şu an tamamen çıplak — nginx dahil hiçbir servis kurulu değil. Her şey sıfırdan kurulacak.

```bash
# gateway'de — taban paketler
sudo apt update && sudo apt install -y nginx fail2ban

# Prometheus (binary kurulum)
wget https://github.com/prometheus/prometheus/releases/download/.../prometheus-*.linux-amd64.tar.gz
# Loki (binary kurulum)
wget https://github.com/grafana/loki/releases/download/.../loki-linux-amd64.zip
# node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/.../node_exporter-*.linux-amd64.tar.gz
```

`prometheus.yml` (gateway'de — Section 6 item 3 ile aynı):
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'livekit'
    static_configs:
      - targets: ['10.10.0.1:7881']

  - job_name: 'node_node1'
    static_configs:
      - targets: ['10.10.0.1:9100']

  - job_name: 'node_gateway'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'postgres'
    static_configs:
      - targets: ['10.10.0.1:9187']
```

node1'de `promtail.yml` hedefini gateway Loki'ye yönlendir:
```yaml
clients:
  - url: http://10.10.0.2:3100/loki/api/v1/push
```

### Adım 3 — gateway nginx Yapılandırması
```nginx
# /etc/nginx/sites-enabled/teqlif.conf

upstream node1_api {
    server 10.10.0.1:8000;
    keepalive 32;
}

# LiveKit sinyalizasyon (HTTP API) — sadece signaling, medya UDP doğrudan node1'e gider
upstream node1_livekit {
    server 10.10.0.1:7880;
    keepalive 8;
}

server {
    listen 443 ssl http2;
    server_name teqlif.com www.teqlif.com;

    ssl_certificate     /etc/letsencrypt/live/teqlif.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/teqlif.com/privkey.pem;

    # LiveKit WebSocket sinyalizasyon — settings.livekit_url = "wss://teqlif.com/rtc"
    # KRITIK: Bu location eksikse LiveKit sesli/görüntülü arama çalışmaz
    location /rtc {
        proxy_pass         http://node1_livekit;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # API + WebSocket (DM, bildirim, feed)
    location / {
        proxy_pass         http://node1_api;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Büyük dosya upload — buffer kapat
    location /api/upload {
        proxy_pass              http://node1_api;
        proxy_buffering         off;
        proxy_request_buffering off;
        client_max_body_size    500m;
    }

    location /uploads/ {
        proxy_pass      http://node1_api;
        proxy_buffering off;
    }
}
```

### Adım 4 — node1 Firewall Sertleştirme

> Grafana ve port 3000 zaten kaldırıldı (2026-09-07). Bu adım sadece WireGuard sonrası kural eklemelerini içerir.

```bash
# HTTP/HTTPS — gateway WireGuard IP + mevcut Cloudflare whitelist korunur
sudo ufw allow from 10.10.0.2 to any port 80
sudo ufw allow from 10.10.0.2 to any port 8000

# Monitoring — sadece gateway'den
sudo ufw allow from 10.10.0.2 to any port 9100  # node_exporter
sudo ufw allow from 10.10.0.2 to any port 9187  # postgres-exporter

# LiveKit — herkese açık (UDP proxy edilemez), livekit.yaml'dan doğrulandı:
# 50000:60000/udp  WebRTC medya (port_range_start/end)
# 7882/udp+tcp      RTC UDP + TCP fallback
# 5349/tcp+udp      TURN TLS (live.teqlif.com cert)
# 3478/udp          STUN/TURN UDP

# SSH — WireGuard kurulunca idealde kısıtlanır
# sudo ufw delete allow 22/tcp
# sudo ufw allow from <TAILSCALE_SUBNET> to any port 22
```

### Adım 5 — DNS Değişikliği (Cloudflare)

**Mevcut DNS durumu:**

| Alan adı | Tip | Hedef | Cloudflare Proxy |
|---|---|---|---|
| `teqlif.com` | A | 135.125.175.223 (node1) | ✅ Proxied |
| `www.teqlif.com` | CNAME | teqlif.com | ✅ Proxied |
| `live.teqlif.com` | A | 135.125.175.223 (node1) | ❌ DNS only |
| `minio.teqlif.com` | A | 135.125.175.223 (node1) | ❌ DNS only |
| `staging.teqlif.com` | A | 135.125.175.223 (node1) | ❌ DNS only |

**Gerekli değişiklikler:**

```
teqlif.com      A   <GATEWAY_PUBLIC_IP>    Proxied   ← gateway'e taşınıyor
uploads.teqlif.com  A   135.125.175.223   DNS only  ← yeni; upload bypass
```

`live.teqlif.com` DNS only olarak node1'de kalır — LiveKit STUN/TURN için gerekli.

**Upload bypass gerekçesi:** `uploads.teqlif.com` → node1 doğrudan (DNS only, Cloudflare proxy yok). Mobil uygulama dosya yükleme endpoint'lerini bu subdomain üzerinden gönderir. Böylece MB/GB boyutundaki upload trafiği gateway'i hiç geçmez — gateway 24h ortalama 100 Mbps throttle riskinden korunur.

**Mobil uygulama değişikliği:** Upload URL'i `teqlif.com` → `uploads.teqlif.com` olarak güncellenmeli. Diğer tüm API istekleri `teqlif.com` üzerinden aynı şekilde devam eder.

### Adım 6 — Doğrulama Checklist
- [ ] API endpoint'leri yanıt veriyor
- [ ] WebSocket (DM, bildirim, feed) bağlantıları kuruluyor
- [ ] LiveKit WebRTC ICE başarılı (sesli/görüntülü arama)
- [ ] `/uploads/` dosyaları erişilebilir
- [ ] MinIO presigned DM URL'leri çalışıyor
- [ ] Prometheus gateway'den node1 metriklerini scrape ediyor
- [ ] Loki node1 loglarını alıyor
- [ ] Prometheus alert kuralları aktif

---

## 8. node1'e Kazandırılan Kapasite

| Servis taşındı | Tahmini RAM kazancı |
|---|---|
| Prometheus | ~300 MB |
| Loki | ~200-400 MB |
| ~~Grafana~~ (2026-09-07 silindi ✅) | ~150-250 MB |
| **Toplam** | **~650 MB – 950 MB** |

Bu kazanç direkt olarak PostgreSQL `shared_buffers`, Redis maxmemory artışı veya ML worker'ların peak dönemlerinde kullanılabilir.

---

## 9. Cloudflare — Mevcut Durum ve CDN Fırsatı

### Mevcut Trafik Zinciri

`teqlif.com` ve `www.teqlif.com` zaten Cloudflare **Proxied** (turuncu bulut). Gerçek mimari şu an:

```
Client → Cloudflare edge (SSL + DDoS) → node1:135.125.175.223
```

V1.0 sonrası:
```
Client → Cloudflare edge (SSL + DDoS + CDN) → gateway → WireGuard → node1
```

Bu şu anlama gelir: node1'in IP'si (`135.125.175.223`) zaten Cloudflare tarafından gizleniyor — plan'daki "node1 IP'yi gizleme" argümanı büyük ölçüde Cloudflare tarafından karşılanıyor. gateway'in asıl değeri **observability node** rolü.

### gateway SPOF — Cloudflare Bağlamında

gateway düşerse trafik kesilir. Ancak Cloudflare üzerinden kolayca fallback kurulabilir:
- Cloudflare **Health Checks** (ücretsiz planda sınırlı) veya
- Cloudflare DNS TTL'ini 60 saniyeye çek; gateway sağlıklıyken `teqlif.com` → gateway, sorun varsa hızlıca node1'e döndür

### Cloudflare CDN — Public Görseller için Ücretsiz

`teqlif.com` proxied olduğu için `/uploads/...` üzerinden servis edilen tüm public listing görselleri Cloudflare edge'inden **zaten geçiyor**. Eksik tek parça: nginx'te `Cache-Control` header'ı.

```nginx
# node1 nginx'te /uploads/ location'ına ekle:
location /uploads/ {
    ...
    add_header Cache-Control "public, max-age=31536000, immutable";
    add_header Vary Accept-Encoding;
}
```

Bu ayarla:
- İlk istek: Client → Cloudflare → gateway → node1 → MinIO → yanıt → Cloudflare cache'e yazar
- Sonraki istekler: Client → Cloudflare edge (cache hit) — node1'e hiç ulaşmaz

**Neler cache'lenir, neler cache'lenmez:**

| İçerik | Cloudflare CDN | Gerekçe |
|---|---|---|
| Listing görselleri (`/uploads/...`) | ✅ Evet | Public, URL sabit, `Cache-Control` ile |
| Profil fotoğrafları (`/uploads/...`) | ✅ Evet | Aynı |
| DM görselleri (`minio.teqlif.com` presigned) | ❌ Hayır | DNS only + private + URL her seferinde değişiyor |
| Video (upload trafiği) | ❌ Kullanılmamalı | Cloudflare free plan 100MB upload sınırı var |
| WebSocket, API yanıtları | ❌ Cache'lenmez | Dinamik içerik |

**Cloudflare Images (resize/optimize):** Ücretli. Ücretsiz planda sadece statik servis + edge caching.

### Cloudflare Firewall — node1'i Koru

Cloudflare IP aralıklarını node1'de güvenilir proxy olarak tanımla. Böylece Cloudflare'i atlayan direkt istekler reddedilir:

```bash
# Cloudflare IP aralıkları (https://www.cloudflare.com/ips/)
# node1'de sadece Cloudflare + gateway WireGuard IP'sinden HTTP/HTTPS izin ver
sudo ufw allow from 103.21.244.0/22 to any port 80
sudo ufw allow from 103.22.200.0/22 to any port 80
# ... (tüm Cloudflare IPv4 aralıkları)
sudo ufw allow from 10.10.0.2 to any port 8000
```

---

## 10. Riskler

| Risk | Ağırlık | Önlem |
|---|---|---|
| **gateway SPOF** | Yüksek | DNS TTL kısalt (60s); node1 nginx'i hazır tut; gateway düşünce node1 doğrudan devreye girer |
| **WireGuard peer config hatası** | Düşük | Config dosyası yazılmadan önce key çiftleri not edilmeli; hata durumunda SSH erişimi kesilmez |
| **Ekstra gecikme** | Düşük-Orta | Limburg↔Nürnberg ~10-15ms RTT; mobil API için +20-30ms — kabul edilebilir |
| **Büyük upload gateway trafiği** | ~~Orta~~ → ✅ Çözüldü | `uploads.teqlif.com` → node1 doğrudan (V1.0'a alındı) |

---

## 11. Açık Sorular

1. **Nginx microcaching gateway'de** — Feed ve listing API yanıtları için 1-5 saniyelik mikro cache. WS ve chat endpoint'leri cache dışı. node1 yükünü ciddi ölçüde azaltır. V1.1 adayı.

2. **gateway SPOF fallback otomasyonu** — DNS TTL kısaltma yeterli mi, yoksa health-check tabanlı otomatik failover (Cloudflare health check) gerekli mi?

---

## 12. Sonraki Fazlar (V2.0+)

| Faz | Ne | Tetikleyici |
|---|---|---|
| V1.1 | gateway'de nginx microcaching | node1 CPU %70+ sürekli |
| V1.2 | DM video için pre-signed upload URL (MinIO doğrudan) | Çok büyük DM video yükleme sorun olursa |
| V2.0 | PostgreSQL streaming read replica (node3) | Okuma sorguları yavaşlarsa |
| V2.1 | FastAPI replika (node3, daha büyük RAM) | API yanıt süresi bozulursa |
| V2.2 | Redis Sentinel + Replica | Redis SPOF kabul edilemez hale gelirse |
| V3.0 | MinIO distributed mode | Disk dolumu yaklaşırsa |
