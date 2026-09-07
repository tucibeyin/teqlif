# Teqlif Scale Planı — V1.0
> **Hostname eşleştirme:** `node1` = OVH Frankfurt (ana backend) | `gateway` = Netcup Nürnberg (edge proxy + observability)
> **Tarih:** 2026-09-07 | **Durum:** Taslak

---

## 1. Mevcut Durum — node1 (OVH Frankfurt)

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
[gateway — Netcup Nürnberg]          [node1 — OVH Frankfurt]
  nginx  (SSL termination)    ──────▶   FastAPI prod
  Tailscale (VPN tüneli)      ◀──────   FastAPI staging
  Prometheus (scrape her ikisini)        PostgreSQL
  Loki  (her ikisinden log)              Redis
  promtail                               MinIO
  node_exporter                          ClickHouse
  fail2ban                               LiveKit  (UDP — gateway bypass)
                                         ARQ Workers (ML + DB)
                                         nginx (iç)
                                         Tailscale
                                         node_exporter
                                         promtail → gateway Loki
                                         fail2ban
```

### Trafik Akışı
```
Client  ──HTTP/WS──▶  gateway:443 (nginx SSL)
                            │ Tailscale şifreli tünel
                            ▼
                       node1:8000 (FastAPI)

LiveKit WebRTC medya (UDP):
Client  ──UDP──▶  node1 doğrudan  (gateway bypass — proxy edilemez)

Monitoring:
node1 node_exporter/promtail  ──Tailscale──▶  gateway Prometheus/Loki
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
| ARQ Workers | ✅ | ❌ | ML (PyTorch/numpy) + DB/ClickHouse erişimi |
| nginx (iç) | ✅ | — | Sadece iç yönlendirme |
| **nginx (public)** | ❌ → iç | ✅ | SSL termination, edge |
| **Prometheus** | ❌ → taşınır | ✅ | Observability bağımsızlığı; node1'e ~300MB RAM iade |
| **Loki** | ❌ → taşınır | ✅ | Log storage için 58.9GB disk avantajı |
| **Grafana** | ⛔ node1'den SİLİNECEK | ❌ | `apt remove grafana` + UFW 3000 kapat |
| promtail | ✅ (node1 log → gateway) | ✅ (kendi logu) | Her iki node'da, gateway Loki'ye gönderir |
| node_exporter | ✅ | ✅ | Her iki node'da, gateway Prometheus scrape eder |
| Tailscale | ✅ | ✅ | Özel ağ tüneli |
| fail2ban | ✅ | ✅ | Bağımsız |

---

## 5. Grafana — Silinecek

Grafana sadece görselleştirme katmanı; veri üretmiyor, saklamıyor, alert pipeline'ına dokunmuyor. Prometheus alert kuralları + Loki alert kuralları Grafana olmadan tam işlevsel çalışır.

**Ek güvenlik gerekçesi:** Şu an `3000/tcp` tüm internete açık — Grafana doğrudan erişilebilir durumda. Bu kabul edilemez bir risk.

**Uygulama sırası (V1.0 geçişinde):**
```bash
sudo systemctl stop grafana-server
sudo systemctl disable grafana-server
sudo apt remove grafana -y
sudo ufw delete allow 3000/tcp
```

---

## 6. Değişiklik Gereksinimleri

### Uygulama kodu — sıfır değişiklik
- `settings.redis_url` → node1 localhost, değişmez
- `settings.database_url` → node1 localhost, değişmez
- `database_clickhouse.py` → `host="localhost"` hardcoded, ClickHouse node1'de kalır, değişmez
- `settings.minio_dm_external_url` → zaten dış domain, değişmez
- `ws_manager` → Redis Stream fan-out zaten multi-node hazır
- CORS → `main.py`'de `teqlif.com` / `www.teqlif.com` sabitleri, gateway IP CORS'u etkilemez

### Deploy config — 3 değişiklik gerekli

**1. `deploy/promtail-config.yml` — Loki hedefini gateway'e yönlendir**

`clients.url` şu an `http://localhost:3100/...`. Prometheus + Loki gateway'e taşınınca:
```yaml
clients:
  - url: http://<GATEWAY_TAILSCALE_IP>:3100/loki/api/v1/push
```

**2. node1 uvicorn — proxy IP güveni**

`teqlif.service` ve `teqlif-staging.service` ExecStart'ta şu an:
```
--forwarded-allow-ips 127.0.0.1
```
Gateway → Tailscale → node1:8000 zincirine geçince bu değer güncellenmeli:
```bash
# teqlif.service ExecStart'ta 127.0.0.1 yerine:
--forwarded-allow-ips=<GATEWAY_TAILSCALE_IP>
```
Aynı değişiklik `teqlif-staging.service` için de gerekli. Bu olmadan sahte X-Forwarded-For kabul edilebilir; firewall sertleştirme bunu engeller ama defense-in-depth açısından zorunlu.

**3. gateway nginx — `/rtc` LiveKit sinyalizasyon proxy'si**

`settings.livekit_url = "wss://teqlif.com/rtc"` — istemciler WebSocket bağlantısını `/rtc` path'i üzerinden kurar. gateway nginx'e bu location **eksikse LiveKit sinyalizasyonu çalışmaz**. Detay Adım 3'te (nginx config bloğunda `/rtc` upstream ayrı tanımlandı).

---

## 7. Uygulama Adımları

### Adım 1 — Tailscale Kurulumu (Sıfır downtime)
```bash
# Her iki node'da
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Bağlantı testi (gateway'den)
ping <NODE1_TAILSCALE_IP>
```

### Adım 2 — Prometheus + Loki'yi gateway'e Kur
```bash
# gateway'de
# Prometheus
wget https://github.com/prometheus/prometheus/releases/download/.../prometheus-*.linux-amd64.tar.gz
# Loki
wget https://github.com/grafana/loki/releases/download/.../loki-linux-amd64.zip
```

`prometheus.yml` (gateway'de):
```yaml
scrape_configs:
  - job_name: node1
    static_configs:
      - targets: ['<NODE1_TAILSCALE_IP>:9100']
    labels: {node: node1}

  - job_name: gateway
    static_configs:
      - targets: ['localhost:9100']
    labels: {node: gateway}

  - job_name: postgres
    static_configs:
      - targets: ['<NODE1_TAILSCALE_IP>:9187']
```

node1'de `promtail.yml` hedefini gateway Loki'ye yönlendir:
```yaml
clients:
  - url: http://<GATEWAY_TAILSCALE_IP>:3100/loki/api/v1/push
```

### Adım 3 — gateway nginx Yapılandırması
```nginx
# /etc/nginx/sites-enabled/teqlif.conf

upstream node1_api {
    server <NODE1_TAILSCALE_IP>:8000;
    keepalive 32;
}

# LiveKit sinyalizasyon (HTTP API) — sadece signaling, medya UDP doğrudan node1'e gider
upstream node1_livekit {
    server <NODE1_TAILSCALE_IP>:7880;
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

```bash
# Grafana'yı kaldır ve portunu kapat (Tailscale üzerinden de erişilmeyecek — servis siliniyor)
sudo systemctl stop grafana-server
sudo systemctl disable grafana-server
sudo apt remove grafana -y
sudo ufw delete allow 3000/tcp

# HTTP/HTTPS — gateway Tailscale IP + mevcut Cloudflare whitelist korunur
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 80
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 8000

# Monitoring — sadece gateway'den
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 9100  # node_exporter
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 9187  # postgres-exporter

# LiveKit — herkese açık (UDP proxy edilemez), livekit.yaml'dan doğrulandı:
# 50000:60000/udp  WebRTC medya (port_range_start/end)
# 7882/udp+tcp      RTC UDP + TCP fallback
# 5349/tcp+udp      TURN TLS (live.teqlif.com cert)
# 3478/udp          STUN/TURN UDP

# SSH — Tailscale kurulunca idealde kısıtlanır
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

**Gerekli değişiklik:** Sadece `teqlif.com` A record'unu gateway IP'sine güncelle. Proxy durumu ve diğer tüm kayıtlar değişmez.

```
teqlif.com   A   <GATEWAY_PUBLIC_IP>   Proxied  ← bu satır değişiyor
```

`live.teqlif.com` DNS only olarak node1'de kalır — LiveKit STUN/TURN için gerekli.

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
| Grafana (**silinecek** — node1'den kaldırılıyor) | ~150-250 MB |
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
Client → Cloudflare edge (SSL + DDoS + CDN) → gateway → Tailscale → node1
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
# node1'de sadece Cloudflare + gateway Tailscale IP'sinden HTTP/HTTPS izin ver
sudo ufw allow from 103.21.244.0/22 to any port 80
sudo ufw allow from 103.22.200.0/22 to any port 80
# ... (tüm Cloudflare IPv4 aralıkları)
sudo ufw allow from <GATEWAY_TAILSCALE_IP> to any port 8000
```

---

## 11. Riskler

| Risk | Ağırlık | Önlem |
|---|---|---|
| **gateway SPOF** | Yüksek | DNS TTL kısalt (60s); node1 nginx'i hazır tut; gateway düşünce node1 doğrudan devreye girer |
| **Tailscale SaaS bağımlılığı** | Orta | Alternatif: WireGuard manuel kurulum (daha fazla efor, tam kontrol) |
| **Ekstra gecikme** | Düşük-Orta | Frankfurt↔Nürnberg ~10-15ms RTT; mobil API için +20-30ms — kabul edilebilir |
| **Büyük upload Tailscale tünelinden geçer** | Orta | Değerlendirme: `uploads.teqlif.com` subdomain'ini node1'e doğrudan yönlendirmek |

---

## 12. Açık Sorular

1. **Büyük upload bypass'ı** — Video yükleme (MB-GB boyutunda) Tailscale tünelinden geçmek zorunda. `uploads.teqlif.com` subdomain'i node1'e doğrudan A record bağlanabilir; upload trafiği gateway'i atlar.

2. **Nginx microcaching gateway'de** — Feed ve listing API yanıtları için 1-5 saniyelik mikro cache. WS ve chat endpoint'leri cache dışı. node1 yükünü ciddi ölçüde azaltır. V1.1 adayı.

3. **gateway SPOF fallback otomasyonu** — DNS TTL kısaltma yeterli mi, yoksa health-check tabanlı otomatik failover (Cloudflare, Route53 health check) gerekli mi?

---

## 13. Sonraki Fazlar (V2.0+)

| Faz | Ne | Tetikleyici |
|---|---|---|
| V1.1 | gateway'de nginx microcaching | node1 CPU %70+ sürekli |
| V1.2 | Büyük upload bypass (`uploads.teqlif.com` → node1 doğrudan) | Upload latency sorun olursa |
| V2.0 | PostgreSQL streaming read replica (node3) | Okuma sorguları yavaşlarsa |
| V2.1 | FastAPI replika (node3, daha büyük RAM) | API yanıt süresi bozulursa |
| V2.2 | Redis Sentinel + Replica | Redis SPOF kabul edilemez hale gelirse |
| V3.0 | MinIO distributed mode | Disk dolumu yaklaşırsa |
