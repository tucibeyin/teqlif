# Teqlif Scale V1.3 — Plan

> **Baseline:** V1.2 aktif  
> **Durum:** Hazır — tüm dosyalar ve kod değişiklikleri tamamlandı; uygulama adımları `task.md`'de  
> **Amaç:** node3 (Zap-Hosting, Ashburn VA) eklenerek 4 sorun çözülür: AI proxy SPOF, off-site yedek yok, staging izolasyonu, monitoring SPOF. Tüm kararlar §9'da alındı; §9.5 her node'un değişiklik listesini özetler.

---

## §1. Donanım Özeti

| Node | Sağlayıcı | Lokasyon | IP (Public) | IP (WG) | CPU | RAM | Disk | Ağ | Ödeme |
|---|---|---|---|---|---|---|---|---|---|
| **node1** | OVH SAS | Frankfurt, DE | 135.125.175.223 | 10.10.0.1 | Intel Haswell 6C @ 3.09 GHz | 11.4 GiB + 2 GiB swap | 98.3 GB NVMe | ~1.95 Gbps / unmetered | aylık |
| **node2** | RackNerd LLC | Buffalo, NY | 198.12.123.33 | 10.10.0.3 | Intel Xeon E5-2670 v2, 1C @ 2.50 GHz | 1.4 GiB + 2 GiB swap | 15 GB SSD | ~237–435 Mbps | aylık |
| **gateway** | Netcup GmbH | Nürnberg, DE | 94.16.105.135 | 10.10.0.2 | QEMU vCPU 2C @ 2.29 GHz | 1.9 GiB (efektif) | 58.9 GB NVMe | ~1.08 Gbps / 100 Mbps ort. aşılırsa throttle | aylık |
| **node3** | Zap-Hosting GmbH | Ashburn, VA | 5.249.165.10 | 10.10.0.4 | AMD EPYC 7763, 4C @ 2.45 GHz | 3.8 GiB (ballooning kapalı) | 50 GB NVMe | 1 Gbps / 33 TB/ay | $81.66 tek seferlik |

> **node2 disk notu:** RackNerd 25 GB SSD olarak satıyordu; `df -h` ile doğrulanan gerçek partition boyutu 15 GB (`/dev/vda1`). 25 GB tam olarak tahsis edilmemiş.

### §1.1 Benchmark Karşılaştırması

| Node | Geekbench 6 Single | Geekbench 6 Multi | Disk 4k IOPS (R/W) | Ağ (uplink, yakın) |
|---|---|---|---|---|
| node1 | 1058 | 4404 | ~60.2k (123 MB/s) | ~1.95 Gbps |
| node2 | **206** | **199** | ~7.8k (32 MB/s) | ~237–435 Mbps |
| gateway | 645 | 1210 | ~750–800 MB/s (1M blok) | ~1.08 Gbps |
| node3 | — (çalıştırılmadı) | — | **56.2k (230 MB/s)** | **1.04 Gbps** (NYC, 7ms) |

> node2 single-core 206 — 2013 donanımı, Raspberry Pi 4 seviyesi.

### §1.2 node3 YABS Detayları (2026-09-11, ballooning kapalı öncesi)

```
YABS tarihi : 2026-09-11 05:08 EDT  (ballooning henüz kapalı değil → RAM 1.8 GiB gösteriyor)
Gerçek RAM  : 3.8 GiB  (ballooning kapatıldıktan sonra free -h ile doğrulandı)
Swap        : 0 KiB
Disk        : 24.5 GiB NVMe  → sonradan 50 GB'a yükseltildi (plan baz alır: 50 GB)
VM type     : KVM
AES-NI      : ✔  (WireGuard için önemli)
AMD-V       : ✔  (nested virt mümkün)
IPv6        : ❌ Offline
ISP/ASN     : ZAP-Hosting GmbH / AS206996
Coğrafi konum: Reston, VA (Ashburn'ün hemen yanı, aynı AWS/datacenter bölgesi)
```

**Disk (fio, mixed R/W 50/50):**

| Blok | Okuma | Yazma | Toplam |
|---|---|---|---|
| 4k | 115 MB/s (28k IOPS) | 115 MB/s (28k IOPS) | 230 MB/s (56k IOPS) |
| 64k | 158 MB/s | 158 MB/s | 316 MB/s |
| 512k | 150 MB/s | 158 MB/s | 309 MB/s |
| 1m | 149 MB/s | 158 MB/s | 307 MB/s |

**Ağ (iperf3 IPv4):**

| Hedef | Ping | Gönderme | Alma |
|---|---|---|---|
| NYC, NY (Leaseweb) | 7.4 ms | **1.04 Gbps** | 976 Mbps |
| Los Angeles, CA | 52 ms | 516 Mbps | 935 Mbps |
| London, UK | 77 ms | busy | 927 Mbps |
| Amsterdam, NL | 82 ms | 405 Mbps | 863 Mbps |
| Tashkent, UZ | 172 ms | 296 Mbps | 757 Mbps |

> Türkiye/Avrupa'ya ~80ms, ~400–900 Mbps. WireGuard tüneli üzerinden node1/gateway'e bu gecikme beklenir.

### §1.3 Spec'lerden Çıkan Kritik Gözlemler

| # | Gözlem | Etki |
|---|---|---|
| 1 | **node2 RAM: 1.4 GiB** — AI proxy `MemoryMax=768M`; swap+sistem ile tamamen dolu | node2 başka hiçbir şey taşıyamaz |
| 2 | **node2 CPU tek çekirdek, Geekbench 206** — E5-2670 v2, 2013 donanımı | AI proxy dışında iş yüklenmemeli |
| 3 | **gateway RAM: 1.9 GiB** — Prometheus+Loki+alertmanager+nginx ~1.0–1.3 GB kullanır | ✅ §9.3 — monitoring node3'e taşındı |
| 4 | **node3 bu tablonun en güçlü ikinci makinesi** — 4C EPYC, 3.8 GiB, 56k IOPS, 1 Gbps | 4 rol: AI proxy secondary, backup hedef, monitoring, staging |
| 5 | **node2 disk: 14.7 GB** — bootstrap'ta "VPSHostingService.co" yazıyor; gerçek sağlayıcı RackNerd LLC | ✅ bootstrap_node2.sh düzeltildi (§9.5 node2) |
| 6 | **node1 swap: 2 GiB** — bellek baskısında diske dökülür (`free -h` ile doğrulandı) | Swap kullanım metriği izlenmeli |
| 7 | **node3 IPv6 yok** — Zap mevcut konfigürasyonda IPv6 vermiyor | Yalnızca IPv4 erişim; WireGuard için sorun değil |

### §1.4 Özel Notlar

- **node3 ballooning:** KVM dinamik RAM tahsisi — Zap panel'den devre dışı bırakıldı. Aksi hâlde 1.8 GiB görünür; dashboard restart sonrası 3.8 GiB kalıcı olarak onaylandı.
- **node3 panel girişi:** Her 90 günde bir giriş zorunlu — takvim hatırlatıcısı ekle (ilk giriş 2026-09-11, sonraki: ~2026-12-10).
- **gateway throttle:** Netcup 24 saatlik ortalama 100 Mbps'yi aşarsa bant genişliği throttle edilir.
- **node2 sağlayıcı adı:** ✅ `bootstrap_node2.sh` "VPSHostingService.co" → "RackNerd LLC" olarak düzeltildi (§9.5 node2).

---

## §2. WireGuard Topolojisi

### V1.2 (3-node mesh)

```
node1 (10.10.0.1) ──── node2 (10.10.0.3)
     │                      │
     └──── gateway (10.10.0.2) ─────┘
```

### V1.3 Hedef (4-node full mesh)

```
node1 (10.10.0.1) ──────────── node2 (10.10.0.3)
     │    \                       │    /
     │      \                     │  /
     │        node3 (10.10.0.4)───┘/
     │              │
     └── gateway (10.10.0.2) ──────┘
```

Her node diğer üçüne de peer tanımlar. `PersistentKeepalive=25s` tüm bağlantılarda.

**Bilinen gecikme:**

| Bağlantı | Gecikme | Not |
|---|---|---|
| node1 ↔ gateway | ~15ms | Frankfurt ↔ Nürnberg |
| node1 ↔ node2 | ~100ms | Frankfurt ↔ Buffalo |
| node1 ↔ node3 | ~80ms | Frankfurt ↔ Ashburn VA |
| gateway ↔ node2 | ~85ms | |
| gateway ↔ node3 | ~80ms | |
| node2 ↔ node3 | ~10ms | Buffalo ↔ Ashburn VA |

**Public key'ler:**

| Node | Public Key | Durum |
|---|---|---|
| node1 | `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=` | Mevcut |
| node2 | `t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k=` | Mevcut |
| gateway | `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=` | Mevcut |
| node3 | `<üretilecek — git'e girmez>` | bootstrap_node3.sh'den sonra elle tüm node'lara eklenir |

**Peer config dosyası:** `deploy/scale/V1.3/wireguard/node3-wg0.conf` oluşturuldu. Diğer node'ların mevcut wg0.conf'larına node3 [Peer] bloğu eklenmeli — §9.5 her node için listeler.

---

## §3. Servis ve Port Haritası (V1.2 Mevcut)

| Servis | node1 | node2 | gateway | node3 |
|---|---|---|---|---|
| **FastAPI prod** | `:8000` — 4 worker | — | — | — |
| **FastAPI staging** | `:8001` — 2 worker | — | — | — |
| **ARQ default worker** | `WorkerSettings` (1 process) | — | — | — |
| **ARQ critical worker**¹ | `WorkerSettingsCritical` (1 process) | — | — | — |
| **AI proxy** | son çare (local Groq) | `:8080` WG, 1 worker | — | — |
| **CF failover daemon** | — | ✅ | — | — |
| **nginx** | `:443` CF fallback | — | `:80/:443` prod+staging | — |
| **PostgreSQL** | `:5432` | — | — | — |
| **postgres_exporter** | `:9187` | — | — | — |
| **Redis** | `:6379` | — | — | — |
| **ClickHouse** | `:8123` (HTTP) / `:9000` (native) | — | — | — |
| **MinIO** | `:9010` (prod + staging bucket) | — | — | — |
| **nginx (uploads)** | `:80` → uploads.teqlif.com | — | — | — |
| **LiveKit** | `:7880-7882`, metrics `:7881` | — | — | — |
| **Prometheus** | — | — | `:9090` (15s scrape) | — |
| **Loki** | — | — | `:3100` (0.0.0.0) | — |
| **alertmanager** | — | — | `:9093` | — |
| **node_exporter** | `:9100` | `:9100` (WG) | `:9100` | — |
| **promtail** | → gateway:3100 | → gateway:3100 | local | — |
| **WireGuard** | `:51820` | `:51820` | `:51820` | `:51820` |

> ¹ Critical worker: push bildirimi, outbid bildirimi, loser cascade — `TimeoutStopSec=600`

---

## §3.1 Trafik Akışı (V1.2 Mevcut)

```
İnternet
   │ HTTPS
   ▼
Cloudflare Edge  (DDoS, SSL proxy, CDN cache)
   │ HTTPS
   ▼
gateway :443  (nginx — SSL termination, rate limit, microcaching)
   │ WireGuard (10.10.0.2 → 10.10.0.1)
   ├──► node1 :8000  FastAPI prod
   └──► node1 :8001  FastAPI staging

node1 :8000/8001
   ├──► PostgreSQL :5432   (local)
   ├──► Redis :6379         (local)
   ├──► MinIO :9010         (local)
   ├──► ClickHouse :8123    (local)
   ├──► LiveKit :7880+      (local)
   └──► node2 :8080         (WireGuard — AI proxy)

uploads.teqlif.com
   │  (Cloudflare bypass — direkt node1)
   └──► node1 :80  nginx → MinIO :9010
```

**CF failover aktifken (gateway down):**
```
Cloudflare → node1 :443  (nginx fallback, self-signed cert)
   └──► FastAPI prod :8000  ✅
   staging ❌ / LiveKit WS ❌ / microcaching ❌
```

---

## §3.2 AI Proxy Fallback Zinciri

### V1.2

```
generate_via_node2()
  ├─ node2 :8080  (X-Internal-Token: NODE2_INTERNAL_TOKEN, 45s timeout)
  │     └─ başarısız → node1 Groq-only (EU IP, Gemini ❌)
  └─ exhausted ─► 503
```

### V1.3 Hedef

```
generate_via_proxy(params)
  ├─ node2 :8080  (X-Internal-Token: AI_PROXY_INTERNAL_TOKEN, 30s)
  │   ABD IP → Groq + Gemini ✅
  │     └─ başarısız → devam
  ├─ node3 :8080  (X-Internal-Token: AI_PROXY_INTERNAL_TOKEN, 30s)
  │   ABD IP → Groq + Gemini ✅
  │     └─ başarısız → devam
  └─ node1 local Groq  (son çare — EU IP, Gemini ❌)
       └─ exhausted ─► 503
```

**Redis shared state** (tüm node'lar node1 Redis'i kullanır — 429 koordinasyonu):
- `llm:exhausted:{model_id}` — TTL: retry-after saniyesi
- `llm:last_success` — TTL: 3600s

**InMemoryCircuitBreaker:** Redis down olsa bile çalışır (3 hata → OPEN, 30s sonra half-open).

**Token:** `AI_PROXY_INTERNAL_TOKEN` — node1, node2, node3 `.env`'lerinde aynı değer. WireGuard arkasında; dışarıdan erişilmez.

**API key paylaşımı:** `GROQ_API_KEY` ve `GEMINI_API_KEY` staging ve prod için aynı. Staging kota tüketirse `llm:exhausted:{model_id}` Redis key'i prod'u da etkiler — bilinçli karar; yoğun staging testi peak saatlerde yapılmaz.

---

## §3.3 Cloudflare Failover Mimarisi (V1.2 Mevcut)

Gateway tek hata noktasıydı — V1.2'de otomatik CF DNS failover eklendi.

```
node2/cf-failover.sh  (her 10s gateway health check)
  │
  ├─ GET http://94.16.105.135/cf-health
  │      ├─ OK → sessiz izleme
  │      └─ 3 ardışık hata (~30s) ──► CF DNS API → A record: gateway → node1
  │
  └─ Recovery: 3 ardışık başarı (~30s) ──► CF DNS API → A record: node1 → gateway
```

| Parametre | Değer |
|---|---|
| Check interval | 10s |
| Failover eşiği | 3 ardışık hata (~30s toplam) |
| Recovery eşiği | 3 ardışık başarı (~30s toplam) |
| Test sonucu (2026-09-11) | Failover: 20s, Recovery: 20s |

**Failover sırasında çalışmayan özellikler:**
- `staging.teqlif.com` (fallback config'de yok)
- nginx microcaching ve rate limiting
- node1 nginx fallback'te yalnızca prod :8000 proxy'leniyor

**İlgili dosyalar:**
- `deploy/scale/V1.2/node2/cf-failover/cf-failover.sh`
- `deploy/scale/V1.2/node1/nginx/teqlif-fallback.conf`
- `deploy/scale/resources/node2/.env.node2.cfFailover`

---

## §3.4 Firewall (UFW) Özeti (V1.2 Mevcut)

| Node | Kural | Hedef |
|---|---|---|
| node1 | 22/tcp | SSH |
| node1 | 443/tcp | CF IPs — fallback |
| node1 | 51820/udp | WireGuard |
| node1 | 8000/tcp (wg0) | 10.10.0.2 gateway |
| node1 | 8001/tcp (wg0) | 10.10.0.2 gateway |
| node1 | 9100/tcp (wg0) | WireGuard mesh (node_exporter — Prometheus) |
| node1 | 6379/tcp (wg0) | 10.10.0.3 node2 (Redis) |
| node2 | 22/tcp | SSH |
| node2 | 51820/udp | WireGuard |
| node2 | 8080/tcp (wg0) | WireGuard mesh (AI proxy) |
| node2 | 9100/tcp (wg0) | WireGuard mesh (node_exporter) |
| gateway | 22/tcp, 80/tcp, 443/tcp | herkese |
| gateway | 51820/udp | WireGuard |
| gateway | 3100/tcp (wg0) | 10.10.0.1, 10.10.0.3 (Loki) |

---

## §3.5 Deploy Workflow (V1.2 Mevcut)

### Rutin deploy (kod değişikliği)

```bash
# Yerel
git push

# node1
cd /var/www/teqlif.com && git pull
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

# node2 (AI proxy kodu değiştiyse)
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy
```

### Deploy (migration varsa)

```bash
# node1
cd /var/www/teqlif.com && git pull
alembic upgrade head
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical
```

> `sync_translations.py`: 4 ARB dosyasını okur → `translations` tablosuna UPSERT → Redis `i18n:*` cache'lerini temizler (ADR §6).

### Yeni node kurulum sırası

```bash
git clone <repo> /var/www/teqlif.com
sudo bash -c 'wg genkey | tee /etc/wireguard/<node>_private.key | wg pubkey > /etc/wireguard/<node>_public.key'
bash deploy/scale/resources/<node>/bootstrap_<node>.sh
nano deploy/scale/resources/<node>/.env.<node>.production
bash deploy/scale/resources/<node>/<node>_services.sh start
```

---

## §3.6 Servis ve Port Haritası (V1.3 Hedef)

| Servis | node1 | node2 | gateway | node3 |
|---|---|---|---|---|
| **FastAPI prod** | `:8000` — 4 worker | — | — | — |
| **FastAPI staging** | — | — | — | `:8001` — 2 worker |
| **ARQ default worker** | prod | — | — | staging |
| **ARQ critical worker** | prod | — | — | staging |
| **AI proxy** | son çare (local Groq) | `:8080` primary | — | `:8080` secondary |
| **CF failover daemon** | — | ✅ | — | — |
| **nginx** | `:443` CF fallback, `:80` uploads.teqlif.com | — | `:80/:443` prod+staging | `:80/:443` uploads-staging.teqlif.com |
| **PostgreSQL** | `:5432` prod | — | — | `:5432` staging |
| **postgres_exporter** | `10.10.0.1:9187` | — | — | — |
| **Redis** | `:6379` prod | — | — | `:6379` staging |
| **ClickHouse** | `:8123/:9000` | — | — | — |
| **MinIO** | `:9010` prod buckets | — | — | `:9010` staging buckets |
| **LiveKit** | `:7880-7882`, `:7881` metrics | — | — | — |
| **Prometheus** | — | — | — | `localhost:9090` |
| **Loki** | — | — | — | `0.0.0.0:3100` |
| **alertmanager** | — | — | — | `localhost:9093` |
| **node_exporter** | `10.10.0.1:9100` | `10.10.0.3:9100` | `10.10.0.2:9100` | `10.10.0.4:9100` |
| **promtail** | → node3:3100 | → node3:3100 | → node3:3100 | local:3100 |
| **WireGuard** | `:51820` | `:51820` | `:51820` | `:51820` |

### Trafik Akışı (V1.3 Hedef)

```
İnternet
   │ HTTPS
   ▼
Cloudflare Edge  (DDoS, SSL proxy, CDN cache)
   │ HTTPS
   ▼
gateway :443  (nginx — SSL termination, rate limit, microcaching)
   │ WireGuard
   ├──► node1 :8000  FastAPI prod
   └──► node3 :8001  FastAPI staging   ← V1.3'te değişti

node1 :8000
   ├──► PostgreSQL :5432   (local)
   ├──► Redis :6379         (local)
   ├──► MinIO :9010         (local)
   ├──► ClickHouse :8123    (local)
   ├──► LiveKit :7880+      (local)
   ├──► node2 :8080         (WireGuard — AI proxy primary)
   └──► node3 :8080         (WireGuard — AI proxy secondary)   ← yeni

node3 :8001 (staging)
   ├──► PostgreSQL :5432   (local — staging instance)
   ├──► Redis :6379         (local — staging instance)
   ├──► MinIO :9010         (local — staging buckets)
   ├──► LiveKit :7880+      (node1 — staging için ayrı LiveKit yok)
   ├──► node2 :8080         (WireGuard — AI proxy primary)
   └──► node3 :8080         (WireGuard — AI proxy secondary, kendisi)

uploads.teqlif.com          (CF bypass → node1 :80 nginx → MinIO prod)
uploads-staging.teqlif.com  (CF bypass → node3 :80 nginx → MinIO staging)   ← yeni
```

**CF failover aktifken (gateway down) — V1.3'te değişmez:**
```
Cloudflare → node1 :443  (nginx fallback, self-signed cert)
   └──► FastAPI prod :8000  ✅
   staging ❌ / LiveKit WS ❌ / microcaching ❌
```

### UFW Özeti (V1.3 Hedef)

| Node | Kural | Hedef |
|---|---|---|
| node1 | 22/tcp | SSH |
| node1 | 443/tcp | CF IPs — fallback |
| node1 | 51820/udp | WireGuard |
| node1 | 8000/tcp (wg0) | 10.10.0.2 gateway (prod FastAPI) |
| node1 | ~~8001/tcp (wg0)~~ | ~~gateway~~ — **kaldırıldı §9.4** |
| node1 | 6379/tcp (wg0) | 10.10.0.3 node2 + 10.10.0.4 node3 (Redis) |
| node1 | 9187/tcp (wg0) | 10.10.0.4 node3 (postgres_exporter scrape) |
| node1 | 7881/tcp (wg0) | 10.10.0.4 node3 (LiveKit metrics scrape) |
| node2 | 22/tcp | SSH |
| node2 | 51820/udp | WireGuard |
| node2 | 8080/tcp (wg0) | WireGuard mesh (AI proxy) |
| node2 | 9100/tcp (wg0) | WireGuard mesh (node_exporter) |
| gateway | 22/tcp, 80/tcp, 443/tcp | herkese |
| gateway | 51820/udp | WireGuard |
| gateway | ~~3100/tcp (wg0)~~ | ~~Loki~~ — **kaldırıldı §9.3** |
| gateway | 9100/tcp (wg0) | 10.10.0.4 node3 (node_exporter scrape) |
| node3 | 22/tcp | SSH |
| node3 | 51820/udp | WireGuard |
| node3 | 80/tcp, 443/tcp | herkese (uploads-staging.teqlif.com) |
| node3 | 8001/tcp (wg0) | 10.10.0.2 gateway (staging FastAPI) |
| node3 | 8080/tcp (wg0) | WireGuard mesh (AI proxy) |
| node3 | 3100/tcp (wg0) | WireGuard mesh (Loki push hedefi) |
| node3 | 9100/tcp (wg0) | WireGuard mesh (node_exporter) |

### Deploy Workflow (V1.3 Hedef)

#### Rutin prod deploy (kod değişikliği)

```bash
# Yerel
git push

# node1
cd /var/www/teqlif.com && git pull
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif
# Workers kod değiştiyse:
sudo systemctl restart teqlif-worker teqlif-worker-critical

# node2 (AI proxy kodu değiştiyse)
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy
```

#### Prod deploy (migration varsa)

```bash
# node1
cd /var/www/teqlif.com && git pull
alembic upgrade head
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif
```

#### Staging deploy (ihtiyaç olunca, ayrı SSH)

```bash
# node3
cd /var/www/teqlif.com && git pull
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif-staging
# Staging workers kod değiştiyse:
sudo systemctl restart teqlif-worker-staging teqlif-worker-critical-staging
```

#### Staging deploy (migration varsa)

```bash
# node3
cd /var/www/teqlif.com && git pull
alembic upgrade head
python3 backend/scripts/sync_translations.py
sudo systemctl restart teqlif-staging
```

> Staging deploy prod deploy'dan bağımsızdır — her prod push'ta zorunlu değil. Staging test hazırlığında veya staging-specific değişikliklerde yapılır.

---

## §4. Kaynak Öncelikleri

### node1 (V1.3 — sadece prod)

§9.4 ile staging node3'e taşındı. node1 prod servislerine odaklanır:

| Servis | OOMScoreAdj | CPUWeight | Davranış |
|---|---|---|---|
| FastAPI prod | **-500** | 200 | OOM'da en son öldürülür |
| ARQ critical | 100 | 100 | OOM'da erkenden kurban — push bildirimleri kesilebilir¹ |
| ARQ default | 200 | 50 | İlk kurban |

> ¹ Critical worker OOMScoreAdj=100: baskı altında push bildirimleri ve outbid cascade kesilebilir.

### node3 (V1.3 — staging + AI proxy secondary + monitoring)

3.8 GB RAM + 4 GB swap, 13 servis. Görev önceliği: staging doğruluk > AI proxy erişilebilirliği > monitoring.

| Servis | OOMScoreAdj | CPUWeight | Davranış |
|---|---|---|---|
| FastAPI staging | **-200** | 150 | Staging ana servis — korunur |
| ARQ critical staging | 100 | 100 | OOM'da erkenden kurban |
| AI proxy | 0 | 100 | node1 fallback zincirinde secondary |
| ARQ default staging | 200 | 50 | İlk kurban |
| Monitoring stack (Prometheus/Loki/Alertmanager) | 300 | 50 | Son kurban olabilir — kısa kör kalma kabul edilebilir |

> PostgreSQL, Redis, MinIO: sistem servisleri — kendi OOM ayarları geçerli; servis dosyalarında override yok.

---

## §5. Staging İzolasyon Durumu

### V1.2 (node1'de prod ile birlikte)

| Bileşen | İzolasyon | Detay |
|---|---|---|
| FastAPI process | ✅ izole | ayrı process, ayrı port (8001), ayrı .env |
| Alembic | ⚠️ paylaşımlı | aynı venv — prod ve staging aynı binary |
| PostgreSQL | ⚠️ kısmi | aynı fiziksel instance — disk/CPU paylaşımlı |
| Redis | ❌ paylaşımlı | prod `db=0`, staging `db=1` — aynı bellek havuzu |
| MinIO | ⚠️ kısmi | ayrı bucket ama aynı server |
| LiveKit | ❌ paylaşımlı | staging prod LiveKit'i kullanıyor |
| AI proxy | ❌ paylaşımlı | staging da node2'ye gidiyor |
| ARQ worker | ❌ yok | staging job'ları prod worker'da işleniyor |

### V1.3 Hedef (node3'te tam izole)

§9.4 ile tüm staging bileşenleri node3'e taşındı:

| Bileşen | İzolasyon | Detay |
|---|---|---|
| FastAPI process | ✅ tam izole | node3 :8001 — ayrı node |
| Alembic | ✅ izole | node3 ExecStartPre → teqlif_staging DB'ye |
| PostgreSQL | ✅ tam izole | node3:5432 — ayrı fiziksel instance |
| Redis | ✅ tam izole | node3:6379 db=0 — ayrı instance |
| MinIO | ✅ tam izole | node3:9010 — ayrı server, ayrı disk |
| LiveKit | ⚠️ paylaşımlı | staging prod LiveKit'i (node1) kullanıyor — kabul edilen trade-off |
| AI proxy | ✅ ortak (tasarım) | node2 primary + node3 secondary — her ortam kullanır |
| ARQ worker | ✅ tam izole | `teqlif-worker-staging` + `teqlif-worker-critical-staging` (node3) |

---

## §6. Gözlenebilirlik Kapsamı (V1.2 Mevcut)

### Prometheus Scrape Hedefleri

**V1.2 (gateway'de çalışır, 6 hedef):**

| Hedef | Adres | Durum |
|---|---|---|
| gateway (OS) | localhost:9100 | ✅ |
| node1 (OS) | 10.10.0.1:9100 | ✅ |
| node1 (PostgreSQL) | 10.10.0.1:9187 | ✅ |
| node1 (LiveKit) | 10.10.0.1:7881 | ✅ |
| node2 (OS) | 10.10.0.3:9100 | ✅ |
| node2 (AI proxy uygulama) | — | ❌ yok |
| node1 (MinIO) | — | ❌ yok |
| node1 (Redis) | — | ❌ yok |

**V1.3 Hedef (node3'te çalışır, 6 hedef):**

| Hedef | Adres | Durum |
|---|---|---|
| node1 (OS) | 10.10.0.1:9100 | ✅ |
| node2 (OS) | 10.10.0.3:9100 | ✅ |
| gateway (OS) | 10.10.0.2:9100 | ✅ — artık WG IP'de dinler |
| node3 (OS + systemd) | 10.10.0.4:9100 | ✅ yeni |
| node1 (PostgreSQL) | 10.10.0.1:9187 | ✅ |
| node1 (LiveKit) | 10.10.0.1:7881 | ✅ |
| node2/node3 (AI proxy uygulama) | — | ❌ V2.0 |
| node1 (MinIO) | — | ❌ V2.0 |
| node1 (Redis) | — | ❌ V2.0 |

### Log Akışı (V1.2 Mevcut)

```
node1/promtail ──┐
node2/promtail ──┼──► gateway:3100 (Loki)
gateway/promtail ┘
```

- Loki saklama süresi: 7 gün (`168h`)
- Loki depolama: `/var/lib/loki` (gateway diski, filesystem)
- node3 henüz Loki'ye bağlı değil

### Log Akışı (V1.3 Hedef)

```
node1/promtail ──┐
node2/promtail ──┤
gateway/promtail ┼──► node3:3100 (Loki)
node3/promtail ──┘  (lokal — kendisi)
```

- Her node yalnızca `systemd-journal` job'u ile push eder (dosya bazlı job'lar kaldırılır — §9.3)
- Loki saklama süresi: 14 gün (`336h`)
- Loki depolama: `/var/lib/loki` (node3, 50 GB NVMe)

---

## §7. Tespit Edilen Sorunlar ve V1.3 Çözümleri

| # | Sorun | Risk | V1.3 Çözümü |
|---|---|---|---|
| 1 | **Off-site yedek yok** — PostgreSQL/Redis yalnızca node1'de | 🔴 | §9.2 — pg + Redis → node3, 03:00 UTC rsync |
| 2 | **AI proxy SPOF** — node2 düşerse Gemini kesilir | 🔴 | §9.1 — node3 secondary proxy, 3-adım fallback zinciri |
| 3 | **Staging prod ile aynı makinede** | 🟠 | §9.4 — tüm staging bileşenleri node3'e taşındı |
| 4 | **Staging ARQ worker yok** | 🟠 | §9.4 — teqlif-worker-staging + worker-critical-staging oluşturuldu |
| 5 | **Monitoring SPOF** — gateway düşerse kör | 🟠 | §9.3 — Prometheus/Loki/Alertmanager node3'e taşındı |
| 6 | **AI proxy uygulama metrikleri yok** | 🟡 | V2.0 kapsam dışı |
| 7 | **Redis metrikleri yok** | 🟡 | V2.0 kapsam dışı |

---

## §8. node3 Kaynak Değerlendirmesi (V1.3 Yük)

3.8 GB RAM + 4 GB swap (bootstrap_node3.sh), 13 servis:

| Servis | Tahmini RAM |
|---|---|
| Sistem (kernel + systemd + WireGuard) | ~300 MB |
| PostgreSQL staging | ~200–400 MB |
| Redis staging | ~50–100 MB |
| MinIO | ~100–200 MB |
| FastAPI staging (2 uvicorn worker) | ~300–500 MB |
| ARQ worker-staging + worker-critical-staging | ~200–400 MB |
| AI proxy (1 uvicorn worker + ML cache) | ~500–800 MB |
| Prometheus | ~100–200 MB |
| Loki | ~150–300 MB |
| Alertmanager | ~30 MB |
| node_exporter + promtail + nginx | ~80 MB |
| **Toplam** | **~2.0–3.3 GB** → 3.8 GB RAM yeterli; spike'larda swap devreye girer |

> VM swappiness=10 (sysctl/99-teqlif.conf) — kernel sadece baskı altında swap'a gider. Kaynak öncelikleri §4'te.

### V2.0 Ertelenenler

| Aday | Gerekçe |
|---|---|
| Redis metrikleri (redis_exporter) | V1.3 kapsam dışı — V2.0 |
| AI proxy uygulama metrikleri | V1.3 kapsam dışı — V2.0 |
| Redis sentinel/replica | node1 Redis SPOF için replica — V2.0 |
| ARQ worker → node2 | AI iş yükü zaten orada; worker taşınabilir — V2.0 |

---

## §9. node3 Rol Kararları

> Tüm başlıklar planlandı ✓ — §9.5 her node'un tam değişiklik listesini içerir.

---

### §9.1 AI Proxy Secondary

> **Durum:** Planlandı ✓

node3 ABD IP'sine sahip — Gemini erişimi tam. node2 SPOF'unu kırar; fallback zincirinde ikinci halka olur.

**Çözülen sorun:** §7 #2 — AI proxy SPOF

#### Yeni Fallback Zinciri

```
POST /api/listings/generate-description  (node1)
  └─► generate_via_proxy(params)
        ├─ node2 :8080  (primary, ~100ms WG gecikme)
        │     └─ başarısız → devam
        ├─ node3 :8080  (secondary, ~80ms WG gecikme)
        │     └─ başarısız → devam
        └─ node1 local Groq  (son çare — Gemini yok, EU IP)
```

#### Değişecek Dosyalar

**Backend (node1 deploy gerektirir):**

| Dosya | Değişiklik |
|---|---|
| `backend/app/config.py` | `node3_ai_proxy_url: str = ""` eklenir; `node2_internal_token` → `ai_proxy_internal_token` (Trade-off #1) |
| `backend/app/services/ml/ai_proxy_client.py` | `generate_via_node2` → `generate_via_proxy` yeniden yazılır; proxy listesi iterate edilir; hata sınıfları `AppException` subclass olmalı — düz `HTTPException` yasak (ADR §6) |
| `backend/app/routers/listings.py:681` | import ve çağrı adı güncellenir |
| `deploy/scale/resources/node1/.env.node1.production` | `NODE3_AI_PROXY_URL=http://10.10.0.4:8080`, `AI_PROXY_INTERNAL_TOKEN=`, `LOG_NODE=node1` eklenir |

**node3 (yeni dosyalar):**

| Dosya | İçerik |
|---|---|
| `deploy/scale/V1.3/node3/systemd/teqlif-ai-proxy.service` | ✅ node2 servisiyle aynı yapı; `--host 10.10.0.4 --port 8080`, `MemoryMax=768M` |
| `deploy/scale/resources/node3/.env.node3.production` | ✅ `GROQ_API_KEY`, `GEMINI_API_KEY`, `AI_PROXY_INTERNAL_TOKEN`, `REDIS_URL=redis://10.10.0.1:6379` |
| `deploy/scale/resources/node3/node3_production_requirements.txt` | ✅ node2 ile aynı 7 paket |
| `deploy/scale/resources/node3/node3_services.sh` | ✅ tüm node3 servisleri dahil |

**node2 (mevcut dosya değişimi):**

| Dosya | Değişiklik |
|---|---|
| `backend/app/ai_proxy_main.py` | `settings.node2_internal_token` → `settings.ai_proxy_internal_token` (Trade-off #1 ✓) |

#### UFW (node3)

```
8080/tcp on wg0  ALLOW  WireGuard mesh   # AI proxy — node1'den
9100/tcp on wg0  ALLOW  WireGuard mesh   # node_exporter — Prometheus
```

#### Ön Koşul

**WireGuard 4-node mesh kurulumu zorunlu.** node3, node1'in Redis'ine WireGuard üzerinden bağlanır (`REDIS_URL=redis://10.10.0.1:6379`). WireGuard olmadan proxy çalışmaz.

#### Trade-off #1 — Token Adı ✓ Karara Bağlandı

**Seçenek A seçildi:** `node2_internal_token` → `ai_proxy_internal_token` olarak yeniden adlandırılır. Her iki proxy aynı token değerini kullanır. Token WireGuard arkasında olduğu için dışarıdan ulaşılamaz — ayrı token gerçek güvenlik artışı sağlamaz. Tüm node'lar aynı repodan git pull aldığı için node2 dahil her node restart edilebilir.

**Env var adı değişimi:**
- `NODE2_INTERNAL_TOKEN` → `AI_PROXY_INTERNAL_TOKEN` (node1, node2, node3 env dosyaları)
- `config.py`: `node2_internal_token` → `ai_proxy_internal_token`
- `ai_proxy_main.py:42`: `settings.node2_internal_token` → `settings.ai_proxy_internal_token`

#### Trade-off #2 — Timeout ✓ Karara Bağlandı

**30s/proxy seçildi.** 45s → 30s. Worst-case: 30s + 30s = **60s**. AI üretimi için yeterli, kullanıcı deneyimi açısından kabul edilebilir.

#### Prometheus Güncelleme

node3 eklenince `prometheus.yml`'ye scrape target olarak eklenir. Prometheus §9.3'te gateway'den node3'e taşındığı için hedef dosya `deploy/scale/V1.3/node3/prometheus.yml`'dir — gateway'deki dosya değil.

---

### §9.2 Off-site Backup

> **Durum:** Planlandı ✓

PostgreSQL ve Redis yedeklerini node1'den WireGuard üzerinden node3'e alır. node1 disk arızasında veri kurtarma mümkün hale gelir.

**Çözülen sorun:** §7 #1 — Off-site yedek yok

#### Mevcut Durum (V1.2)

| Veri | Mevcut Durum | Risk |
|---|---|---|
| PostgreSQL | Yedek yok | Disk arızası = tam veri kaybı |
| Redis | `redis-backup.sh` — yerel `/var/backups/redis/`, 3 gün, rsync yok | AOF+RDB hybrid çalışıyor (everysec fsync) — anlık kayıp az ama off-site yok |
| ClickHouse | Yedek yok | Analytics/fire-and-forget — kabul edilebilir |
| MinIO | Yedek yok | Kullanıcı medyası — boyut bilinmiyor |

> Redis AOF+RDB hybrid çalıştığı için `/var/lib/redis/` zaten sürekli diske yazıyor. Backup asıl olarak off-site disaster recovery için gerekli.

#### Backup Kapsamı (V1.3)

| Veri | Kararı | Gerekçe |
|---|---|---|
| **PostgreSQL** | ✅ Backup alınacak | Finansal veri (tuci_transaction, purchase, bid, auction) — kritik |
| **Redis RDB** | ✅ Backup alınacak | Mevcut script uzatılır + rsync eklenir; ARQ critical queue recovery için değerli |
| **ClickHouse** | ❌ V1.3'te skip | `flush_all_buffers` açıkça fire-and-forget; veri kaybı tasarım gereği kabul edilebilir |
| **MinIO** | ✅ node3'te MinIO kurulur (staging için) | §9.4 staging izolasyonu — prod media node1'de kalır, mirror yok |

#### Mimari

```
node1 (her gece 02:00 UTC)
  redis-backup.timer → /var/backups/redis/dump-YYYY-MM-DD.rdb  (mevcut, değişmez)

node1 (her gece 03:00 UTC)
  teqlif-backup.service  (systemd one-shot)
    │
    ├─ pg_dump teqlif     | gzip → /var/backups/pg/teqlif-YYYY-MM-DD.sql.gz
    │       (teqlif_staging artık node3'te — node1 bu dump'ı almaz)
    │
    └─ rsync -az /var/backups/ tucibeyin@10.10.0.4:/var/backups/teqlif/
             (WireGuard 10.10.0.4 — plain internet değil)
```

> **MinIO prod mirror yok.** Prod media (`teqlif` / `teqlif-dm` bucket'ları) node1'de kalır, node3'e kopyalanmaz. node3 MinIO yalnızca staging bucket'ları için çalışır (`teqlif-staging` / `teqlif-dm-staging`).

#### Değişecek / Yeni Dosyalar

| Dosya | Değişiklik |
|---|---|
| `deploy/scripts/redis-backup.sh` | Değişmez — 02:00'da çalışmaya devam eder |
| `deploy/scripts/pg-backup.sh` | **Yeni** — pg_dump + gzip + retention |
| `deploy/scripts/offsite-rsync.sh` | **Yeni** — node3'e rsync, bağlantı kontrolü |
| `deploy/scale/V1.3/node1/systemd/teqlif-backup.service` | **Yeni** — pg-backup + rsync çalıştırır |
| `deploy/scale/V1.3/node1/systemd/teqlif-backup.timer` | **Yeni** — `OnCalendar=*-*-* 03:00:00` |
| `deploy/scale/V1.3/node3/systemd/minio.service` | **Yeni** — node3 MinIO servisi (staging) |

#### Disk Bütçesi (node3, ~47 GB kullanılabilir — 50 GB)

| Alan | Tahmini Boyut |
|---|---|
| OS + tüm servisler | ~3 GB |
| Python venv (ML paketleri dahil) | ~4 GB |
| ML model cache (~/.cache/huggingface) | ~1–2 GB (ilk AI proxy çağrısında indirilir) |
| Swap dosyası | 4 GB |
| Prometheus TSDB 30 gün | ~1–3 GB |
| Loki logs 14 gün | ~1–4 GB |
| backend/logs/ (7g rotation) | ~500 MB |
| Staging stack data (PostgreSQL + Redis AOF) | ~0.5–1 GB |
| PostgreSQL backup × 7 gün | ~3.5–14 GB |
| Redis backup × 14 gün | ~0.7–2.8 GB |
| MinIO staging data | < 0.5 GB |
| Tampon | ~13–28 GB |

#### Retention Kararı

| Konum | PostgreSQL | Redis |
|---|---|---|
| node1 (yerel) | 3 gün | 3 gün |
| node3 (off-site) | 7 gün | 14 gün |

#### SSH Erişimi (node1 → node3)

```bash
# node1'de (WireGuard kurulumundan sonra):
ssh-keygen -t ed25519 -f ~/.ssh/id_backup -N ""
ssh-copy-id -i ~/.ssh/id_backup.pub tucibeyin@10.10.0.4
```

`offsite-rsync.sh`: `rsync -e "ssh -i ~/.ssh/id_backup" ...`

> WireGuard mesh kurulduktan sonra uygulanır (ön koşul).

#### Doğrulama (Opsiyonel ama Önemli)

```bash
# node3'te — haftalık pg restore testi
createdb teqlif_verify
zcat /var/backups/teqlif/pg/teqlif-latest.sql.gz | psql teqlif_verify
psql teqlif_verify -c "SELECT COUNT(*) FROM users;"
dropdb teqlif_verify
```

> `pg_restore` değil `psql` — dump SQL formatında (plain text gzip), binary format değil.

Systemd timer ile haftada bir otomatikleştirilebilir (nice to have).

---

### §9.3 Monitoring

> **Durum:** Planlandı ✓

Prometheus + Loki + Alertmanager gateway'den node3'e taşınır (Grafana yok). Gateway nginx-only kalır; RAM baskısı ortadan kalkar. Aynı zamanda loglama stratejisi düzeltilir: dosya handler'ları korunur (lokal hata ayıklama için), node'a özgü log dosyası isimlendirmesi eklenir, worker.log double-write bug'ı giderilir, Loki duplikasyonu için yalnızca dosya bazlı promtail job'ları kaldırılır, journald kısaltılır, Loki retention uzatılır.

**Çözülen sorun:** §7 #5 — Monitoring SPOF, §1.3 #3 — gateway RAM sınırı

#### Mevcut Sorunlar (V1.2)

| # | Sorun | Etki |
|---|---|---|
| 1 | node1 ERROR logları Loki'ye **3×** yazılıyor | `teqlif-backend` + `teqlif-errors` + `systemd-journal` job'ları örtüşüyor |
| 2 | node1 WARNING logları **2×** yazılıyor | Dosya job'u + journal job'u aynı satırı gönderiyor |
| 3 | `worker.log` app.log ile örtüşüyor (`propagate=True`) | ARQ logları Loki'de 2× |
| 4 | Log yazma yolu uyuşmazlığı | Uygulama `backend/logs/`'a yazıyor, promtail `/var/log/teqlif/`'i okuyor — symlink yoksa dosya job'ları boşa çalışıyor |
| 5 | INFO logları Loki'ye gidiyor | Gereksiz depolama ve gürültü; WARNING+ yeterli |
| 6 | journald retention = Loki retention (7 gün) | Her node'da aynı veri iki yerde — journald kısa vadeli yedek olmalı |
| 7 | Grafana V1.0'da silindi ama plan referansları kaldı | Stale referans — temizlendi (§9.5) |

#### Loglama Stratejisi Düzeltmesi (V1.3)

**Hedef mimari — dosya log + journal, sıfır duplikasyon:**

```
Uygulama dosya log (INFO+)        Uygulama stdout (WARNING+)
backend/logs/{LOG_NODE}-*.log          ↓
(lokal hata ayıklama)             systemd journal  (2 gün — kısa vadeli yerel yedek)
                                       ↓
                                  promtail  (yalnızca systemd-journal job'u)
                                       ↓
                                  Loki node3:3100  (14 gün — tek Loki kaynağı)
```

**logging_config.py değişikliği (backend/app/logging_config.py):**

**Düzeltme 1 — worker.log double-write bug:**

```python
# YANLIŞ (mevcut — V1.2):
root.addHandler(_make_json_handler("worker.log", INFO))   # ← root'a fazladan ekleme
worker_logger = logging.getLogger("arq")
worker_file = _make_json_handler("worker.log", INFO)
worker_logger.addHandler(worker_file)
worker_logger.propagate = True  # ← root'a da gidiyor → worker.log 2× yazılıyor

# DOĞRU (V1.3):
# root.addHandler(...worker.log...)  ← bu satır kaldırılır
worker_logger = logging.getLogger("arq")
worker_logger.addHandler(_make_json_handler(f"{LOG_NODE}-worker.log", INFO))
worker_logger.propagate = False  # ← root'a geçmiyor, tek yazma
```

**Düzeltme 2 — node'a özgü dosya isimlendirmesi:**

```python
# V1.3 ekleme — setup_logging() başına:
LOG_NODE = os.getenv("LOG_NODE", "node")

# Dosya isimleri artık node prefix'li:
root.addHandler(_make_json_handler(f"{LOG_NODE}-app.log", INFO))
root.addHandler(_make_json_handler(f"{LOG_NODE}-error.log", ERROR))
# root'a worker.log YOK — sadece arq logger'a eklenir (yukarıdaki düzeltme)
```

**Sonuç — hangi node hangi dosyayı yazar:**

| Servis | LOG_NODE değeri | Üretilen dosyalar |
|---|---|---|
| node1 `teqlif.service` (prod) | `node1` | `node1-app.log`, `node1-error.log` |
| node1 `teqlif-worker*.service` (prod) | `node1` | `node1-app.log`, `node1-error.log`, `node1-worker.log` |
| node3 `teqlif-staging.service` | `staging` | `staging-app.log`, `staging-error.log` |
| node3 `teqlif-worker*-staging.service` | `staging` | `staging-app.log`, `staging-error.log`, `staging-worker.log` |

> Tüm servisler `LOG_NODE` env var'ını `.env.*` dosyasından okur. Node1 servis dosyaları `EnvironmentFile=/var/www/teqlif.com/.env`, node3 staging servis dosyaları `EnvironmentFile=/var/www/teqlif.com/.env.staging` kullanır.

> Lokal hata ayıklama: `ssh node1 "tail -f /var/www/teqlif.com/backend/logs/node1-error.log"` — hangi node'dan geldiği dosya adında belli.

**promtail değişikliği — node1:**

Kaldırılan job'lar: `teqlif-backend`, `teqlif-errors`, `teqlif-worker-log` (dosya bazlı — Loki duplikasyonunu önler; log dosyaları `backend/logs/` altında lokal hata ayıklama için korunur)

Kalan job'lar:
```yaml
- job_name: systemd-journal   # tek Loki log kaynağı (WARNING+)
- job_name: nginx-access       # GeoIP enrichment korunur
- job_name: nginx-error
```

**promtail değişikliği — node2:**

Kaldırılan job'lar: `teqlif-ai-proxy` (dosya bazlı — aynı sebep)

Kalan job'lar:
```yaml
- job_name: systemd-journal
```

**journald retention — tüm node'lar:**

| Node | V1.2 | V1.3 | Gerekçe |
|---|---|---|---|
| node1 | 1 hafta, 500 MB | **2 gün, 200 MB** | Loki kaynak; journald yedek |
| node2 | 1 hafta, 200 MB | **2 gün, 100 MB** | Aynı |
| gateway | 1 hafta, 300 MB | **2 gün, 100 MB** | Aynı |
| node3 | — | **2 gün, 200 MB** | Yeni node aynı politika |

**Loki retention:**

`V1.2: 168h (7 gün)` → `V1.3: 336h (14 gün)` — node3 50 GB disk bütçesi karşılar.

#### Monitoring Stack — Gateway → node3 Taşıma

**node3'te yeni çalışacaklar:**

| Servis | Listen | Notlar |
|---|---|---|
| Prometheus | `localhost:9090`, 30d TSDB | Dışarıya kapalı — Grafana yok |
| Loki | `0.0.0.0:3100`, 14d | WireGuard mesh'ten push kabul eder |
| Alertmanager | `localhost:9093` | Telegram — env var'lar node3 env'den |
| node_exporter | `10.10.0.4:9100` + `--collector.systemd` | Servis durumu metrikleri için |
| promtail | → `localhost:3100` | Kendi logları |

**Prometheus scrape hedefleri (yeni prometheus.yml):**

```yaml
- job_name: 'node-gateway'
  targets: ['10.10.0.2:9100']   # gateway node_exporter artık WG IP'de

- job_name: 'node-node1'
  targets: ['10.10.0.1:9100']   # değişmez

- job_name: 'node-node2'
  targets: ['10.10.0.3:9100']   # değişmez

- job_name: 'node-node3'
  targets: ['10.10.0.4:9100']   # yeni

- job_name: 'livekit'
  targets: ['10.10.0.1:7881']   # değişmez

- job_name: 'postgres'
  targets: ['10.10.0.1:9187']   # değişmez
```

**Yeni alert kuralı — node3 AI Proxy:**

```yaml
- alert: AIProxySecondaryDown
  expr: |
    node_systemd_unit_state{node="node3", name="teqlif-ai-proxy.service", state="active"} == 0
  for: 1m
  labels:
    severity: warning          # secondary — critical değil
  annotations:
    summary: "AI Proxy secondary durdu (node3)"
    description: "node2 primary hâlâ çalışıyor olabilir; zincir node2 → local Groq'a düştü."
```

#### UFW Değişiklikleri

**node1 (ekle):**
```bash
ufw allow in on wg0 from 10.10.0.4 to any port 9187 proto tcp  # postgres_exporter — node3 Prometheus
ufw allow in on wg0 from 10.10.0.4 to any port 7881 proto tcp  # LiveKit metrics — node3 Prometheus
ufw allow in on wg0 from 10.10.0.4 to any port 6379 proto tcp  # Redis — node3 AI proxy (§9.1)
```

**gateway (değiştir):**
```bash
# Kaldır:
ufw delete allow in on wg0 to any port 3100          # Loki artık gateway'de yok

# Ekle:
ufw allow in on wg0 from 10.10.0.4 to any port 9100  # node_exporter — node3 Prometheus
```

**node3 (yeni):**
```bash
ufw allow in on wg0 to any port 3100 proto tcp        # Loki — tüm mesh push eder
ufw allow in on wg0 to any port 9100 proto tcp        # node_exporter — Prometheus self
ufw allow in on wg0 from 10.10.0.1 to any port 8080  # AI proxy — node1 (§9.1)
```

**gateway node_exporter — listen address değişimi:**

`--web.listen-address=localhost:9100` → `--web.listen-address=10.10.0.2:9100`

Prometheus artık gateway'de değil, node3'ten WireGuard üzerinden scrape ediyor.

#### Değişecek / Yeni Dosyalar

**Backend (kod değişikliği):**

| Dosya | Değişiklik |
|---|---|
| `backend/app/logging_config.py` | `LOG_NODE` env var eklenir; dosya isimleri `{LOG_NODE}-app/error/worker.log` olur; `root`'tan `worker.log` handler kaldırılır; `arq` logger `propagate=False` (double-write fix) |

**node1:**

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V1.3/node1/promtail-config.yml` | ✅ `teqlif-backend`, `teqlif-errors`, `teqlif-worker-log` job'ları kaldırıldı; push URL `10.10.0.4:3100` |
| `deploy/scale/V1.3/node1/journald/journald.conf` | ✅ `MaxRetentionSec=2d`, `SystemMaxUse=200M` |

**node2:**

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V1.3/node2/promtail-config.yml` | ✅ `teqlif-ai-proxy` job'u kaldırıldı; push URL `10.10.0.4:3100` |
| `deploy/scale/V1.3/node2/journald/journald.conf` | ✅ `MaxRetentionSec=2d`, `SystemMaxUse=100M` |

**gateway:**

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V1.3/gateway/systemd/node_exporter.service` | ✅ `--web.listen-address=10.10.0.2:9100` |
| `deploy/scale/V1.3/gateway/promtail-config.yml` | ✅ push URL `localhost:3100` → `10.10.0.4:3100` |
| `deploy/scale/V1.3/gateway/journald/journald.conf` | ✅ `MaxRetentionSec=2d`, `SystemMaxUse=100M` |
| `deploy/scale/resources/gateway/gateway_services.sh` | `SERVICES` listesinden `prometheus loki alertmanager` çıkar |
| `deploy/scale/resources/gateway/bootstrap_gateway.sh` | `SCALE_VERSION="V1.2"` → `"V1.3"`; prometheus/loki/alertmanager install blokları kaldırılır; stale "Grafana ayrı kurulmali" notu kaldırılır |

**node3 (yeni):**

| Dosya | İçerik |
|---|---|
| `deploy/scale/V1.3/node3/systemd/prometheus.service` | ✅ `localhost:9090`, 30d retention |
| `deploy/scale/V1.3/node3/systemd/loki.service` | ✅ `0.0.0.0:3100` |
| `deploy/scale/V1.3/node3/systemd/alertmanager.service` | ✅ envsubst template, node3 env'den TELEGRAM_* okur |
| `deploy/scale/V1.3/node3/systemd/node_exporter.service` | ✅ `10.10.0.4:9100 --collector.systemd` |
| `deploy/scale/V1.3/node3/systemd/promtail.service` | ✅ → `localhost:3100` |
| `deploy/scale/V1.3/node3/prometheus.yml` | ✅ 6 scrape target (gateway WG IP dahil) |
| `deploy/scale/V1.3/node3/prometheus-rules.yml` | ✅ Mevcut kurallar + `AIProxySecondaryDown` |
| `deploy/scale/V1.3/node3/loki-config.yml` | ✅ `retention_period: 336h` (14 gün) |
| `deploy/scale/V1.3/node3/alertmanager.yml.template` | ✅ gateway'den uyarlandı — path güncellendi |
| `deploy/scale/V1.3/node3/promtail-config.yml` | ✅ `systemd-journal` job'u, push `localhost:3100` |
| `deploy/scale/V1.3/node3/journald/journald.conf` | `MaxRetentionSec=2d`, `SystemMaxUse=200M` (mevcut ✅) |

---

### §9.4 Staging İzolasyonu

> **Durum:** Planlandı ✓

FastAPI staging + PostgreSQL staging + Redis staging + MinIO staging + ARQ worker (staging) node1'den node3'e taşınır. node1 tamamen prod'a ayrılır; staging testleri bağımsız ortamda çalışır.

**Çözülen sorun:** §7 #3 — Staging prod ile aynı makinede, §7 #4 — Staging ARQ worker yok

#### Taşınan Bileşenler

| Bileşen | V1.2 (node1) | V1.3 (node3) |
|---|---|---|
| FastAPI staging | `:8001`, 2 worker, `node1` | `:8001`, 2 worker, `node3` |
| PostgreSQL staging | `node1:5432/teqlif_staging` | `node3:5432/teqlif_staging` (yeni instance) |
| Redis staging | `node1:6379 db=1` | `node3:6379 db=0` (ayrı instance) |
| MinIO staging | `node1:9010 teqlif-staging` bucket | `node3:9010 teqlif-staging` bucket |
| ARQ worker default | **yok** | `teqlif-worker-staging.service` |
| ARQ worker critical | **yok** | `teqlif-worker-critical-staging.service` |

#### Servis Davranışı — restart sırasında ne çalışır

`systemctl restart teqlif-staging` dediğinde sırasıyla:

```
ExecStartPre → alembic upgrade head   (node3 teqlif_staging DB'ye migration)
ExecStartPre → sync_main.py           (kategoriler, lokasyonlar, çeviriler staging DB'ye yazılır)
ExecStart    → uvicorn :8001 başlar
```

Workers ayrı restart gerektirir — `teqlif-staging.service` restart'ında otomatik yeniden başlamaz.

#### Medya — uploads-staging.teqlif.com

Staging MinIO tam izole. Flutter build komutları:

| Ortam | Komut |
|---|---|
| Staging | `flutter run --release --dart-define-from-file=dart_defines/staging.json` |
| Production | `flutter run --release --dart-define-from-file=dart_defines/release.json` |
| Lokal dev | `flutter run` (dart-define yok — prod URL'leri kullanır) |

`mobile/dart_defines/staging.json` → `BASE_HOST=staging.teqlif.com` + **`UPLOADS_HOST=uploads-staging.teqlif.com`** ✅  
`mobile/dart_defines/release.json` → `BASE_HOST=www.teqlif.com` + `UPLOADS_HOST=uploads.teqlif.com` ✅

> **V1.3 öncesi bug:** `staging.json`'da `UPLOADS_HOST` yoktu — staging build, `kUploadsHost` default'u olan `uploads.teqlif.com`'u (prod MinIO/node1) kullanıyordu. Artık düzeltildi.

DNS: `uploads-staging.teqlif.com` A → `5.249.165.10` (DNS only, CF proxy kapalı — node1 ile aynı politika).

node3 nginx `uploads-staging.teqlif.com` config:
- `/` → `node3 MinIO:9010/teqlif-staging/`
- `/dm/` → `node3 MinIO:9010/teqlif-dm-staging/`

#### AI API Keys

Staging `.env.staging` içindeki `GROQ_API_KEY` ve `GEMINI_API_KEY` prod ile **aynı değerdir** — bilinçli karar.

**Sonuç:** staging'de Groq/Gemini kotası tüketilirse `llm:exhausted:{model_id}` Redis key'i prod tarafından da okunur ve prod AI feature'ı da geçici olarak yavaşlar/düşer. Bu kabul edilmiş trade-off.

**Önlem:** Yoğun AI testi (toplu listing oluşturma vb.) prod peak saatlerinin dışında yapılmalı.

#### LiveKit

Staging `LIVEKIT_URL` prod LiveKit'i (node1) gösterir — ayrı staging LiveKit yok. Test odaları prod LiveKit üzerinde çalışır; kabul edilebilir trade-off.

#### Disk Notu (node3)

`node1_staging_requirements.txt` ML paketleri içeriyor (`sentence-transformers`, `faiss-cpu`, `nudenet`, `scipy`). İlk venv kurulumu ~3-5 GB disk kullanır. ML model cache (~/.cache/huggingface) ilk AI proxy çağrısında ek ~1-2 GB indirir. §9.2 disk bütçesi buna göre güncellenmiştir.

**node3 swap:** 3.8 GB RAM, 13 servis. `bootstrap_node3.sh` kurulum sırasında 4 GB `/swapfile` oluşturur. `vm.swappiness=10` (99-teqlif.conf) — swap yalnızca bellek baskısı altında devreye girer.

#### node1 Temizliği

§9.4 uygulandıktan sonra node1'den kaldırılacaklar:

| Öğe | Aksiyon |
|---|---|
| `teqlif-staging.service` | `systemctl stop teqlif-staging && systemctl disable teqlif-staging` |
| `/etc/systemd/system/teqlif-staging.service` | Sil |
| PostgreSQL `teqlif_staging` DB | `sudo -u postgres dropdb teqlif_staging` |
| Redis `db=1` (staging) | `redis-cli -n 1 FLUSHDB` |
| MinIO `teqlif-staging` + `teqlif-dm-staging` bucket | `mc rb --force node1/teqlif-staging && mc rb --force node1/teqlif-dm-staging` |

> MinIO bucket silmeden önce medyayı arşivlemek istiyorsan `mc mirror node1/teqlif-staging /tmp/staging-backup/`.

#### UFW Değişiklikleri

**node3 (ekle — staging için):**
```bash
ufw allow in on wg0 from 10.10.0.2 to any port 8001 proto tcp  # staging FastAPI — gateway
```

**gateway (node1:8001 kuralını kaldır — artık node3'te):**
```bash
ufw delete allow in on wg0 from 10.10.0.2 to any port 8001
# node1'de bu kural: 8001/tcp ALLOW 10.10.0.2 — kaldırılır
```

> node1 UFW'de `8001/tcp` kuralı varsa silinir; prod `:8000` kalır.

#### Değişecek / Yeni Dosyalar

**node3 (yeni):**

| Dosya | İçerik |
|---|---|
| `deploy/scale/V1.3/node3/systemd/teqlif-staging.service` | node3 staging FastAPI — `forwarded-allow-ips 10.10.0.2` |
| `deploy/scale/V1.3/node3/systemd/teqlif-worker-staging.service` | ARQ default worker, `.env.staging` |
| `deploy/scale/V1.3/node3/systemd/teqlif-worker-critical-staging.service` | ARQ critical worker, `.env.staging` |
| `deploy/scale/V1.3/node3/systemd/minio.service` | Staging MinIO `:9010` |
| `deploy/scale/V1.3/node3/nginx/uploads-staging.teqlif.com` | nginx proxy → staging MinIO |
| `deploy/scale/resources/node3/.env.node3.staging` | Staging env şablonu (node3 lokal DB/Redis/MinIO) |
| `deploy/scale/resources/node3/bootstrap_node3.sh` | PostgreSQL 17 + Redis + MinIO + staging stack kurulumu |

**gateway:**

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V1.3/gateway/nginx/teqlif.conf` | `staging.teqlif.com` upstream: `10.10.0.1:8001` → `10.10.0.4:8001` |

**node1:**

| Dosya | Değişiklik |
|---|---|
| `deploy/scale/V1.3/node1/systemd/teqlif-staging.service` | Dosya kaldırıldı — node1'de staging servisi artık yok |
| `deploy/scale/resources/node1/node1_services.sh` | `teqlif-staging` listeden çıkarılır |

---

### §9.5 Node Değişiklik Özeti

> **Durum:** §9.x kapandıkça güncellenir — §10 implementation adımlarının kaynağı

Her §9.x kararının mevcut node'larda ne gerektirdiğini listeler. Sadece node3'e eklenen şeyler değil, kaynak node'larda kaldırılan veya değiştirilen her şey buraya girer.

#### node1

| Alan | Değişiklik | Kaynak § |
|---|---|---|
| `teqlif-staging.service` | Durdurulur, devre dışı bırakılır, servis dosyası silinir | §9.4 |
| PostgreSQL `teqlif_staging` DB | `dropdb teqlif_staging` — node3'e taşındı | §9.4 |
| Redis db=1 (staging) | `redis-cli -n 1 FLUSHDB` — node3 ayrı instance kullanıyor | §9.4 |
| MinIO `teqlif-staging` + `teqlif-dm-staging` bucket | Arşivle (opsiyonel), sonra sil | §9.4 |
| `node1_services.sh` | ✅ `SERVICES` listesinden `teqlif-staging` çıkarıldı | §9.4 |
| `deploy/scale/resources/node1/.env.node1.staging` | **Silinecek** — staging node3'e taşındı; şablonun yerine `resources/node3/.env.node3.staging` geçti | §9.4 |
| `pg-backup.sh` | **Yeni oluşturulur** — pg_dump + gzip | §9.2 |
| `offsite-rsync.sh` | **Yeni oluşturulur** — node3'e rsync | §9.2 |
| `teqlif-backup.timer/service` | **Yeni oluşturulur** — 03:00 UTC | §9.2 |
| `config.py` — `node2_internal_token` | `ai_proxy_internal_token` olarak yeniden adlandırılır | §9.1 |
| `ai_proxy_main.py` — token kontrolü | `node2_internal_token` → `ai_proxy_internal_token` | §9.1 |
| `ai_proxy_client.py` — fallback zinciri | node3 secondary proxy eklenir | §9.1 |
| `.env.node1.production` | `NODE3_AI_PROXY_URL=`, `AI_PROXY_INTERNAL_TOKEN=` eklenir; `LOG_NODE=node1` eklenir | §9.1, §9.3 |
| `backend/app/logging_config.py` | `LOG_NODE` env var; `{LOG_NODE}-app/error/worker.log`; worker double-write fix (`propagate=False`) | §9.3 |
| `promtail-config.yml` | `teqlif-backend`, `teqlif-errors`, `teqlif-worker-log` job'ları kaldırılır; push URL `10.10.0.4:3100` | §9.3 |
| `journald/journald.conf` | `MaxRetentionSec=2d`, `SystemMaxUse=200M` | §9.3 |
| UFW | `9187/tcp`, `7881/tcp`, `6379/tcp` on wg0 — `10.10.0.4`'e açılır | §9.3 + §9.1 |

#### gateway

| Alan | Değişiklik | Kaynak § |
|---|---|---|
| Prometheus/Loki/Alertmanager servisleri | Durdurulur ve kaldırılır (node3'e taşınır) | §9.3 |
| `node_exporter.service` | `localhost:9100` → `10.10.0.2:9100` | §9.3 |
| `promtail-config.yml` | push URL `localhost:3100` → `10.10.0.4:3100` | §9.3 |
| `journald/journald.conf` | `MaxRetentionSec=2d`, `SystemMaxUse=100M` | §9.3 |
| `gateway_services.sh` | `SERVICES` listesinden `prometheus loki alertmanager` çıkar | §9.3 |
| `bootstrap_gateway.sh` | `SCALE_VERSION="V1.3"`; monitoring install blokları kaldırılır; stale Grafana notu kaldırılır | §9.3 |
| UFW | `3100/tcp` Loki kuralları silinir; `9100/tcp ALLOW 10.10.0.4` eklenir | §9.3 |
| nginx staging routing | node1 → node3 olarak güncellenir | §9.4 |

#### node2

| Alan | Değişiklik | Kaynak § |
|---|---|---|
| `.env.node2.production` | `NODE2_INTERNAL_TOKEN` → `AI_PROXY_INTERNAL_TOKEN` | §9.1 |
| `ai_proxy_main.py` | node2'deki kopya da aynı değişikliği alır (git pull) | §9.1 |
| `promtail-config.yml` | `teqlif-ai-proxy` job'u kaldırılır; push URL `10.10.0.4:3100` | §9.3 |
| `journald/journald.conf` | `MaxRetentionSec=2d`, `SystemMaxUse=100M` | §9.3 |
| `deploy/scale/resources/node2/bootstrap_node2.sh` | ✅ "VPSHostingService.co" → "RackNerd LLC" düzeltildi | §1.4 |

#### mobile (Flutter)

| Dosya | Değişiklik | Kaynak § |
|---|---|---|
| `mobile/dart_defines/staging.json` | ✅ `UPLOADS_HOST=https://uploads-staging.teqlif.com` eklendi | §9.4 |
| `mobile/dart_defines/release.json` | ✅ `UPLOADS_HOST=https://uploads.teqlif.com` açıkça yazıldı (default'a güvenmeme) | §9.4 |

#### node3 (net yeni kurulumlar)

| Servis / Dosya | Amaç | Kaynak § |
|---|---|---|
| WireGuard peer | Mesh'e katılır | Ön koşul |
| PostgreSQL 17 (`localhost:5432/teqlif_staging`) | Staging DB izolasyonu | §9.4 |
| Redis (`localhost:6379 db=0`) | Staging cache/queue izolasyonu | §9.4 |
| MinIO (`:9010`, `teqlif-staging` + `teqlif-dm-staging`) | Staging storage | §9.4 |
| nginx (`uploads-staging.teqlif.com`) | Staging medya erişimi | §9.4 |
| `teqlif-staging.service` (FastAPI `:8001`) | Staging uygulama sunucusu | §9.4 |
| `teqlif-worker-staging.service` | Staging ARQ default worker | §9.4 |
| `teqlif-worker-critical-staging.service` | Staging ARQ critical worker | §9.4 |
| AI Proxy (FastAPI `:8080`) | Secondary proxy | §9.1 |
| Prometheus (`localhost:9090`) | Metrik toplama | §9.3 |
| Loki (`0.0.0.0:3100`, 14g) | Merkezi log deposu | §9.3 |
| Alertmanager (`localhost:9093`) | Telegram alert | §9.3 |
| node_exporter (`:9100` + `--collector.systemd`) | Sistem + servis metrikleri | §9.3 |
| promtail → `localhost:3100` | Kendi logları | §9.3 |
| Backup hedef `/var/backups/teqlif/` | pg + redis off-site hedefi | §9.2 |
| `journald/journald.conf` | `MaxRetentionSec=2d`, `SystemMaxUse=200M` | §9.3 |
| `.env.node3.staging` | `LOG_NODE=staging` eklenir | §9.3 |
| Swap (`/swapfile`, 4 GB) | `bootstrap_node3.sh` tarafından oluşturulur; `vm.swappiness=10` | §9.4 |

---

## §10. Güvenlik Kısıtları

- WireGuard private/public key'ler **git'e girmez** — VPS'te üretilir
- `.env` dosyaları git'e girmez — yalnızca boş değerli template'ler
- `AI_PROXY_INTERNAL_TOKEN` node1, node2 ve node3'te aynı değer (`openssl rand -hex 32`)
- CF_API_TOKEN, CF_ZONE_ID — kullanıcıda; template'lerde boş
- TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID — kullanıcıda; template'lerde boş
