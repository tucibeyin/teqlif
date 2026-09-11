# Teqlif Scale V1.3 — Plan

> **Baseline:** V1.2 aktif  
> **Durum:** Planlama  
> **Amaç:** Bu doküman karar almadan önce mevcut altyapıyı ve sorunları tam olarak belgeler.  
> node3 rol kararı §9'da, uygulama adımları §10'da tamamlanacak.

---

## §1. Donanım Özeti

| Node | Sağlayıcı | Lokasyon | IP (Public) | IP (WG) | CPU | RAM | Disk | Ağ | Ödeme |
|---|---|---|---|---|---|---|---|---|---|
| **node1** | OVH SAS | Frankfurt, DE | 135.125.175.223 | 10.10.0.1 | Intel Haswell 6C @ 3.09 GHz | 11.4 GiB + 12 GiB swap | 98.3 GB NVMe | ~1.95 Gbps / unmetered | aylık |
| **node2** | RackNerd LLC | Buffalo, NY | 198.12.123.33 | 10.10.0.3 | Intel Xeon E5-2670 v2, 1C @ 2.50 GHz | 1.4 GiB + 2 GiB swap | 14.7 GB HDD/SSD | ~237–435 Mbps | aylık |
| **gateway** | Netcup GmbH | Nürnberg, DE | 94.16.105.135 | 10.10.0.2 | QEMU vCPU 2C @ 2.29 GHz | 1.9 GiB (efektif) | 58.9 GB NVMe | ~1.08 Gbps / 100 Mbps ort. aşılırsa throttle | aylık |
| **node3** | Zap-Hosting GmbH | Ashburn, VA | 5.249.165.10 | 10.10.0.4 | AMD EPYC 7763, 4C @ 2.45 GHz | 3.8 GiB (ballooning kapalı) | 25 GB NVMe | 1 Gbps / 33 TB/ay | $81.66 tek seferlik |

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
Disk        : 24.5 GiB NVMe
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
| 3 | **gateway RAM: 1.9 GiB** — Prometheus+Loki+alertmanager+Grafana+nginx ~1.0–1.4 GB kullanır | Gateway zaten sınırda; monitoring taşınmalı |
| 4 | **node3 bu tablonun en güçlü ikinci makinesi** — 4C EPYC, 3.8 GiB, 56k IOPS, 1 Gbps | Birden fazla rol taşıyabilir |
| 5 | **node2 disk: 14.7 GB** — bootstrap'ta "VPSHostingService.co" yazıyor; gerçek sağlayıcı RackNerd LLC | Bootstrap yorum satırları güncellenmeli |
| 6 | **node1 swap: 12 GiB** — bellek baskısında diske döküyor | Swap kullanım metriği izlenmeli |
| 7 | **node3 IPv6 yok** — Zap mevcut konfigürasyonda IPv6 vermiyor | Yalnızca IPv4 erişim; WireGuard için sorun değil |

### §1.4 Özel Notlar

- **node3 ballooning:** KVM dinamik RAM tahsisi — Zap panel'den devre dışı bırakıldı. Aksi hâlde 1.8 GiB görünür; dashboard restart sonrası 3.8 GiB kalıcı olarak onaylandı.
- **node3 panel girişi:** Her 90 günde bir giriş zorunlu — takvime hatırlatıcı eklenmeli.
- **gateway throttle:** Netcup 24 saatlik ortalama 100 Mbps'yi aşarsa bant genişliği throttle edilir.
- **node2 sağlayıcı adı:** `bootstrap_node2.sh` ve servis dosyalarında "VPSHostingService.co" yazıyor; gerçek sağlayıcı RackNerd LLC. V1.3'te düzeltilecek.

---

## §2. WireGuard Topolojisi (V1.2 Mevcut)

```
node1 (10.10.0.1) ──── node2 (10.10.0.3)
     │                      │
     └──── gateway (10.10.0.2) ─────┘
```

V1.2: 3-node full mesh — her node diğer ikisine de peer tanımlar. `PersistentKeepalive=25s` tüm bağlantılarda.

**Bilinen gecikme:**
- node1 ↔ node2: ~100ms (Frankfurt ↔ Buffalo)
- node1 ↔ gateway: ~15ms (Frankfurt ↔ Nürnberg)
- gateway ↔ node2: ~85ms
- node3 ↔ node1/gateway: ~80ms (Ashburn VA ↔ DE, WireGuard tünelinde)

**Bilinen public key'ler (V1.2 bootstrap'tan):**
- node1: `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=`
- node2: `t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k=`
- gateway: `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=`
- node3: `<üretilecek — git'e girmez>`

V1.3'te node3 eklenerek 4-node full mesh hedefleniyor.

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
| **Grafana** | — | — | ayrı kurulum | — |
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

## §3.2 AI Proxy Fallback Zinciri (V1.2 Mevcut)

```
POST /api/listings/generate-description  (node1)
  └─► ai_proxy_client.py: generate_via_node2()
        │
        ├─ NODE2_AI_PROXY_URL dolu ─────────────────────────────────────┐
        │   POST http://10.10.0.3:8080/generate                         │
        │   Header: X-Internal-Token: NODE2_INTERNAL_TOKEN              │
        │   Timeout: 45s                                                 │
        │                                                                ▼
        │                                              node2: ai_proxy_main.py
        │                                                ├─ Groq modelleri (registry sırası)
        │                                                └─ Gemini modelleri (Groq exhausted ise)
        │                                                     ABD IP → Gemini ✅
        │
        └─ node2 down / timeout / 503 ──────────────────────────────────┐
                                                                         │
                                                           node1 lokal fallback
                                                             Groq-only (EU IP)
                                                             Gemini ❌ (EU IP kısıtlı)
                                                                         │
                                                           Groq da exhausted ─► 503
```

**Redis shared state** (node1 ↔ node2 aynı key'i paylaşırken 429 koordinasyonu):
- `llm:exhausted:{model_id}` — TTL: retry-after saniyesi
- `llm:last_success` — TTL: 3600s (sıcak yol optimizasyonu)

**InMemoryCircuitBreaker:** Redis down olsa bile llm_service çalışmaya devam eder (3 hata → OPEN, 30s sonra half-open).

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
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

# node2 (AI proxy kodu değiştiyse)
cd /var/www/teqlif.com && git pull
sudo systemctl restart teqlif-ai-proxy
```

### Yeni node kurulum sırası

```bash
git clone <repo> /var/www/teqlif.com
sudo bash -c 'wg genkey | tee /etc/wireguard/<node>_private.key | wg pubkey > /etc/wireguard/<node>_public.key'
bash deploy/scale/resources/<node>/bootstrap_<node>.sh
nano deploy/scale/resources/<node>/.env.<node>.production
bash deploy/scale/resources/<node>/<node>_services.sh start
```

---

## §4. node1 Kaynak Öncelikleri

node1'de birden fazla servis aynı anda çalışır. OOM ve CPU yarışı bu hiyerarşiye göre çözülür:

| Servis | OOMScoreAdj | CPUWeight | Davranış |
|---|---|---|---|
| FastAPI prod | **-500** | 200 | OOM'da en son öldürülür |
| FastAPI staging | -200 | 80 | prod'dan önce kurban |
| ARQ critical | 100 | 100 | OOM'da erkenden kurban — kritik iş kaybı riski¹ |
| ARQ default | 200 | 50 | ilk kurban |

> ¹ Critical worker OOMScoreAdj=100 — staging FastAPI'den (-200) daha kurban olabilir. Baskı altında push bildirimleri kesilebilir.

---

## §5. Staging İzolasyon Durumu (V1.2 Mevcut)

Staging şu an node1'de prod ile aynı makinede çalışıyor.

| Bileşen | İzolasyon | Detay |
|---|---|---|
| FastAPI process | ✅ izole | ayrı process, ayrı port (8001), ayrı .env |
| Alembic | ⚠️ paylaşımlı | aynı venv — `ExecStartPre` prod ve staging aynı binary'yi çalıştırır |
| PostgreSQL | ⚠️ ayrı DATABASE_URL | aynı fiziksel instance — disk/CPU paylaşımlı |
| Redis | ❌ paylaşımlı instance | prod `db=0`, staging `db=1` — aynı bellek havuzu |
| MinIO | ⚠️ ayrı bucket | `teqlif-staging` / `teqlif-dm-staging` — aynı server, aynı disk |
| LiveKit | ❌ paylaşımlı | staging da prod LiveKit'i kullanıyor (node1) |
| AI proxy | ❌ paylaşımlı | staging da `NODE2_AI_PROXY_URL=http://10.10.0.3:8080` |
| ARQ worker | ❌ staging worker yok | staging background job'ları prod worker'da işleniyor — veri kirliliği riski |

---

## §6. Gözlenebilirlik Kapsamı (V1.2 Mevcut)

### Prometheus Scrape Hedefleri

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
| node3 | — | ❌ henüz yok |

### Log Akışı

```
node1/promtail ──┐
node2/promtail ──┼──► gateway:3100 (Loki) ──► Grafana
gateway/promtail ┘
```

- Loki saklama süresi: 7 gün (`168h`)
- Loki depolama: `/var/lib/loki` (gateway diski, filesystem)
- node3 henüz Loki'ye bağlı değil

---

## §7. Tespit Edilen Sorunlar

| # | Sorun | Risk Seviyesi | Etkilenen Alan |
|---|---|---|---|
| 1 | **Off-site yedek yok** — PostgreSQL ve Redis yalnızca node1'de | 🔴 Yüksek | Veri kaybı, kurtarma imkânsız |
| 2 | **AI proxy SPOF** — node2 düşerse Gemini tamamen kesilir | 🔴 Yüksek | Tüm AI özellikleri |
| 3 | **Staging prod ile aynı makinede** — Redis/PostgreSQL/MinIO/LiveKit paylaşımlı | 🟠 Orta | Staging yükü prod'u etkiler |
| 4 | **Staging ARQ worker yok** — staging job'ları prod worker'da işleniyor | 🟠 Orta | Veri kirliliği, test güvenilirliği |
| 5 | **Monitoring SPOF** — gateway düşerse izleme tamamen kör | 🟠 Orta | Olay anında görünürlük yok |
| 6 | **AI proxy uygulama metrikleri yok** — Groq/Gemini kota durumu izlenemiyor | 🟡 Düşük | Debug güçlüğü |
| 7 | **Redis metrikleri yok** — bellek baskısı sessizce büyür | 🟡 Düşük | Proaktif uyarı yok |

---

## §8. node3 Donanım Değerlendirmesi

### Mevcut RAM Kullanımı Tahmini (node3 boşta)

| Servis | Tahmini RAM |
|---|---|
| Sistem (kernel + systemd) | ~200 MB |
| WireGuard | ~10 MB |
| node_exporter + promtail | ~50 MB |
| — | — |
| **Kullanılabilir (AI proxy için)** | ~3.5 GB |

### Planlı Yük Senaryoları

Aşağıdaki senaryolar §9'daki rol kararından sonra kesinleşecek.

| Senaryo | Tahmini RAM | 3.8 GiB'a Oranı |
|---|---|---|
| Sadece AI proxy secondary | ~500 MB | %13 |
| AI proxy + backup | ~600 MB | %16 |
| AI proxy + backup + monitoring | ~1.1 GB | %29 |
| AI proxy + backup + monitoring + staging (izole) | ~3.0–3.3 GB | %79–87 |

---

## §8.1 V1.2'den Gelen V1.3 Adayları

V1.2/final.md §17'de ertelenen kalemler:

| Aday | Açıklama | Öncelik |
|---|---|---|
| Off-site backup | PostgreSQL + Redis → uzak node | 🔴 |
| AI proxy secondary | node2 SPOF'unu kır | 🔴 |
| Staging izolasyonu | Redis/PostgreSQL/ARQ worker ayrışması | 🟠 |
| Monitoring SPOF | gateway down → kör kalma | 🟠 |
| Redis metrikleri | redis_exporter node1'e eklenmesi | 🟡 |
| Gemini node1'den erişim | proxy üzerinden — maliyet/karmaşıklık gerekçesiyle ertelendi | 🟡 |
| Redis sentinel/replica | node1 Redis SPOF için replica | 🔵 (V2.0) |
| ARQ worker → node2 | AI iş yükü zaten orada — worker da taşınabilir | 🔵 (V2.0) |

---

## §9. node3 Rol Kararı

> Dört ana başlık altında değerlendiriliyor. Her başlık ayrı beyin fırtınasıyla olgunlaşacak, ardından nihai karara bağlanacak.

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
| `backend/app/config.py` | `node3_ai_proxy_url: str = ""` ve `node3_internal_token: str = ""` eklenir |
| `backend/app/services/ml/ai_proxy_client.py` | `generate_via_node2` → `generate_via_proxy` yeniden yazılır; proxy listesi iterate edilir |
| `backend/app/routers/listings.py:681` | import ve çağrı adı güncellenir |
| `deploy/scale/resources/node1/.env.node1.production` | `NODE3_AI_PROXY_URL=http://10.10.0.4:8080` ve `NODE3_INTERNAL_TOKEN=` eklenir |
| `deploy/scale/resources/node1/.env.node1.staging` | aynı |

**node3 (yeni dosyalar):**

| Dosya | İçerik |
|---|---|
| `deploy/scale/V1.3/node3/systemd/teqlif-ai-proxy.service` | node2 servisiyle aynı yapı; `--host 10.10.0.4 --port 8080`, `MemoryMax=768M` |
| `deploy/scale/resources/node3/.env.node3.production` | `GROQ_API_KEY`, `GEMINI_API_KEY`, `NODE3_INTERNAL_TOKEN`, `REDIS_URL=redis://10.10.0.1:6379` |
| `deploy/scale/resources/node3/node3_production_requirements.txt` | node2 ile aynı 7 paket |
| `deploy/scale/resources/node3/node3_services.sh` | `teqlif-ai-proxy node_exporter promtail` |

**node2 (mevcut dosya değişimi):**

| Dosya | Değişiklik |
|---|---|
| `backend/app/ai_proxy_main.py` | `settings.node2_internal_token` → `settings.node3_internal_token` token kontrolü **sorun — bkz. Trade-off #1** |

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

node3 eklenince gateway'deki `prometheus.yml`'ye scrape target eklenir. Bu §9.3 Monitoring başlığında işlenecek.

---

### §9.2 Off-site Backup

> **Durum:** Tartışılacak

PostgreSQL ve Redis yedeklerini node1'den WireGuard üzerinden node3'e alır. node1 disk arızasında veri kurtarma mümkün hale gelir.

**Çözülen sorun:** §7 #1 — Off-site yedek yok

---

### §9.3 Monitoring

> **Durum:** Tartışılacak

Prometheus + Loki + alertmanager + Grafana gateway'den node3'e taşınır. Gateway nginx-only kalır; 1.9 GiB RAM baskısı ortadan kalkar.

**Çözülen sorun:** §7 #5 — Monitoring SPOF, §1.3 #3 — gateway RAM sınırı

---

### §9.4 Staging İzolasyonu

> **Durum:** Tartışılacak

FastAPI staging + PostgreSQL staging + Redis staging + ARQ worker (staging) node3'e taşınır. node1'deki prod yükü azalır, staging testleri güvenilir hale gelir.

**Çözülen sorun:** §7 #3 — Staging prod ile aynı makinede, §7 #4 — Staging ARQ worker yok

---

## §10. Uygulama Adımları

> **Bu bölüm §9 tamamlandıktan sonra yazılacak.**

---

## §11. Güvenlik Kısıtları

- WireGuard private/public key'ler **git'e girmez** — VPS'te üretilir
- `.env` dosyaları git'e girmez — yalnızca boş değerli template'ler
- `NODE2_INTERNAL_TOKEN` node1 ve node2'de aynı değer (`openssl rand -hex 32`)
- CF_API_TOKEN, CF_ZONE_ID — kullanıcıda; template'lerde boş
- TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID — kullanıcıda; template'lerde boş
