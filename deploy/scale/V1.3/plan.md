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

V1.2'de node3 mesh'te yok. Tüm node'lar birbirini WireGuard üzerinden görüyor (full mesh).

**Bilinen public key'ler (V1.2 bootstrap'tan):**
- node1: `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=`
- node2: `t+lw3dW45sVklF3wsbji7WGA6jN4+StcwK6nKmJi21k=`
- gateway: `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=`
- node3: `<üretilecek — git'e girmez>`

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
| **MinIO** | prod + staging bucket | — | — | — |
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

## §9. node3 Rol Kararı

> **Bu bölüm doldurulacak.**  
> Hangi sorunları (§7) çözeceği ve hangi bileşenlerin node3'e taşınacağı / ekleneceği burada netleşecek.

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
