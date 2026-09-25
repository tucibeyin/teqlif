# Teqlif Scale V1.5 - Mimari ve Orkestrasyon Kararları (Findings)

Bu belge, V1.4 altyapısına üç yeni node (gateway2, node6, node7) entegre edilirken alınan mimari kararları, darboğaz analizlerini ve sistematik tasarım seçimlerini özetlemektedir. V1.5'in tek hedefi **tek nokta hatası (SPOF) eliminasyonu** ve **orkestrasyon zekasının güçlendirilmesidir.**

---

## 1. Yeni Donanım ve Rol Dağılımı

### 1.1 Genel Bakış

| Node | Sağlayıcı | Konum | CPU | RAM | Disk | IPv4 | Geekbench 6 |
|------|-----------|-------|-----|-----|------|------|-------------|
| **gateway2** | DELUXHOST | Amsterdam, NL | 2× Xeon Platinum 8173M @ 2.0 GHz | 9.0 GiB | 78.7 GiB SSD | 185.205.194.232 | 559 / 1021 |
| **node6** | DELUXHOST | Amsterdam, NL | 3× Xeon Platinum 8173M @ 2.0 GHz | 7.7 GiB | 78.7 GiB SSD | 185.205.194.173 | 606 / 1390 |
| **node7** | DELUXHOST | Kerkrade, NL | 2× Xeon E5-2699 v4 @ 2.2 GHz | 2.9 GiB | 10 GiB SSD + 1 TB HDD | 82.39.86.94 | 766 / 1328 |

> **Önemli:** Tüm üç yeni node aynı sağlayıcıdadır (DELUXHOST, ASN214677). Bu, tek sağlayıcı riskini doğurur. V1.6'da çeşitlendirme planlanmalıdır.

### 1.2 Rol Ataması

| Node | V1.5 Rolü | Temel Karar Gerekçesi |
|------|-----------|----------------------|
| **gateway2** | Gateway #2 (Aktif-Aktif) | Tek gateway SPOF'unu ortadan kaldırır |
| **node6** | Core #2 (Aktif-Pasif) | node5 çöküşünde sıcak yedek |
| **node7** | Primary MinIO Storage | 1 TB HDD ile birincil medya deposu |

---

## 2. gateway / gateway2 — Aktif-Aktif Mimari

### 2.1 Karar: Aktif-Aktif (CF Multi-A)

İki gateway aynı anda trafik taşır. Cloudflare, her ikisine de A kaydı ile yönlendirir ve biri düşünce diğeri otomatik devreye girer.

**Trafik yönlendirme felsefesi:**

```
Cloudflare (teqlif.com, api.teqlif.com)
   ├── A → gateway  (185.x.x.x)      ← her zaman aktif
   └── A → gateway2 (185.205.194.232) ← her zaman aktif

Her gateway → node5 (10.10.0.5) upstream
             ↓ nginx backup direktifi
           node6 (10.10.0.7) backup upstream
```

**nginx upstream konfigürasyonu (her iki gateway'de aynı):**

```nginx
upstream teqlif_core {
    server 10.10.0.5:8000;          # node5 — birincil
    server 10.10.0.7:8000 backup;   # node6 — sadece node5 düşünce
}
```

`backup` direktifi: nginx, node5 yanıt vermediğinde (connection refused / timeout) otomatik olarak node6'ya geçer. Manuel müdahale gerekmez.

### 2.2 Güvenlik Kararı

Aktif-aktif yapı, DDoS / saldırı senaryolarında her iki gateway'i koruma altına almak için aynı nginx güvenlik stack'ini (Cloudflare IP allowlist, rate limiter, fail2ban) gerektirmektedir. gateway2 bootstrap'ı, gateway'in birebir güvenlik kopyası olarak hazırlanacaktır.

SSL sertifikaları: Let's Encrypt wildcard (*.teqlif.com) her iki gateway'de ayrı ayrı yönetilir; certbot ile otomatik yenileme.

### 2.3 Önerilen WireGuard IP

```
gateway2 → 10.10.0.9
```

---

## 3. node5 / node6 — Aktif-Pasif Core Mimarisi

### 3.1 Bileşen Bazlı Replikasyon Kararları

| Bileşen | Replikasyon Yöntemi | Failover Yöntemi | Not |
|---------|--------------------|--------------------|-----|
| **PostgreSQL** | Streaming Replication (async) | Keepalived VIP + promote | PgBouncer her iki node'da çalışır |
| **Redis** | `REPLICAOF` (async) | Keepalived VIP + `REPLICAOF NO ONE` | Sessions, metrics, cache |
| **ClickHouse** | ❌ Replika YOK | Manuel pg_dump benzeri yedek | Analitik veri; geçici kayıp kabul edilebilir |
| **FastAPI** | Her iki node'da aktif binary | nginx `backup` direktifi | node6 standby'da istatistiksel trafik almaz |
| **ARQ Worker** | node5'te aktif, node6'da pasif | Manuel veya Keepalived | Çift worker = çift iş işleme riski |

**ClickHouse Kararı Gerekçesi:** ClickHouse analitik veri tutar (izlenme, tıklama metrikleri). Failover anındaki kısa veri kaybı iş kritik değildir. Streaming replikasyon kurmak ClickHouse özelinde karmaşık (distributed table motoru) ve kaynakları harcayan bir işlemdir. V1.5 için kabul edilebilir risk.

### 3.2 Keepalived VIP Tasarımı

İki sanal IP node5 / node6 arasında dolaşır:

```
10.10.0.10  → PostgreSQL / PgBouncer VIP (port 5432)
10.10.0.11  → Redis VIP (port 6379)
```

**Keepalived senaryosu:**

```
Normal durum:
  node5 (MASTER, priority 100) → her iki VIP'i tutar
  node6 (BACKUP, priority 90)  → bekler

node5 çöktüğünde (~2-3 saniye):
  1. Keepalived: VIP'ler node6'ya taşınır
  2. notify_master script:
       redis-cli REPLICAOF NO ONE              # Redis primary'ye çevrilir
       pg_ctl promote -D /var/lib/postgresql/  # PostgreSQL primary'ye çevrilir
  3. nginx upstream (gateway + gateway2): backup direktifi node6'yı otomatik seçer
  4. edge-metrics-agents: 10.10.0.10/11 VIP'e yazıyor; adres değişmez
```

**Operatör müdahalesi sıfır.** Tüm geçiş ~3 saniyede otomatik gerçekleşir.

### 3.3 PostgreSQL Streaming Replication

```
node5 (primary, port 5433, PgBouncer :5432)
  └── async stream → node6 (replica, port 5433, PgBouncer :5432)
```

- `wal_level = replica` (node5 postgresql.conf)
- `max_wal_senders = 3`
- `hot_standby = on` (node6 — read-only sorgulara açık)
- WireGuard üzerinden: `primary_conninfo = 'host=10.10.0.5 port=5433 user=replicator'`

### 3.4 Redis REPLICAOF

```
node6 redis.conf:
  replicaof 10.10.0.5 6379
  replica-read-only yes
```

node5 ayaktayken tüm edge-metrics-agent'lar `10.10.0.11` (Redis VIP) adresine yazar. Hem node5 hem node6 bu metrikleri görür. Failover anında VIP node6'ya geçer, Redis primary olur, yazma devam eder.

### 3.5 Önerilen WireGuard IP

```
node6 → 10.10.0.7
```

---

## 4. node7 / node1 / node4 — Tiered MinIO Depolama

### 4.1 Strateji: DNS-Only Failover + EdgeOrchestrator Otomasyonu

Kullanıcıların upload ettiği medya dosyaları için üç katmanlı depolama:

```
Yazma yönlendirme (EdgeOrchestrator):
  node7 → primary  (1 TB HDD, disk_free_gb en yüksek başlangıçta)
  node1 → secondary (NVMe, ~180-200 GB free)
  node4 → tertiary  (NVMe, ~160-180 GB free)

Public URL yapısı:
  node7 → minio7.teqlif.com:9010/{bucket}/{key}
  node1 → minio1.teqlif.com:9010/{bucket}/{key}
  node4 → minio4.teqlif.com:9010/{bucket}/{key}
```

Her node farklı public domain'e sahip; dosyalar hangi node'a yazıldıysa o domain'in URL'ini taşır. Bu sayede:
- DNS failover gerekmez
- DB'deki URL'ler güncellenmez
- node7 çöktüğünde sadece node7 URL'li dosyalar geçici erişilemez olur (node1/node4'tekiler etkilenmez)

### 4.2 MinIO Site Replication Kararı (V1.5)

node7 ↔ node1 çift yönlü (bidirectional) site replication:

```
mc admin replicate add minio7/ minio1/
```

Bu yapıda node7'ye yazılan her dosya node1'e de kopyalanır (ve tersi). node7 tamamen çöktüğünde node1'deki kopya hemen erişilebilir hale getirilebilir; Cloudflare DNS kaydı `minio7.teqlif.com → node1 IP`'ye yönlendirilir, uygulama kodu hiç değişmez.

**node4 site replication'a dahil edilmez** (tertiary yedek; replikasyon yükü + 3. disk alanı tüketimi avantajı aşmaz).

### 4.3 node7 MinIO Konfigürasyonu

node7'nin 1 TB HDD'si yavaş SATA diski (fio: 1.19 GB/s sequential okuma). MinIO metadata ve indexing için:

```
MINIO_DATA_DIR=/mnt/hdd/minio   # 1 TB HDD
MINIO_STORAGE_QUOTA_PERCENT=85  # 850 GB efektif limit
```

10 GiB SSD → sistem diski (OS, MinIO binary, WAL); 1 TB HDD → veri diski.

### 4.4 Önerilen WireGuard IP

```
node7 → 10.10.0.8
```

---

## 5. EdgeOrchestrator — Tam Yeniden Tasarım

### 5.1 V1.4 Sorunları

| Sorun | Etki |
|-------|------|
| `MEDIA` → LiveKit seçimi; isim "medya dosyası" çağrışımı yapıyor | Kod okunurluğu bozuk |
| `STORAGE` → MinIO seçimi; `disk_percent` kullanıyor | Heterojen disk boyutlarında yanlış node seçimi |
| `MEDIA` stratejisi CPU kullanıyor | SFU bandwidth-bound; CPU yanıltıcı metrik |
| Tüm node'lar aynı havuzda | node7 yanlışlıkla LiveKit seçilebilir |
| AI routing backend'de hardcoded | Orchestrator dışında saçılmış mantık |

### 5.2 V1.5 ServiceType Yeniden Adlandırma

```python
class ServiceType(str, Enum):
    STREAM = "stream"   # LiveKit SFU  → node1, node4
    MEDIA  = "media"    # MinIO        → node7, node1, node4
    AI     = "ai"       # LLM Proxy    → node2, node3, node5
```

### 5.3 Capabilities Sistemi

Her node, edge-metrics-agent aracılığıyla kendi yetkinliklerini ilan eder:

```python
# node1 / node4
capabilities: ["stream", "media"]

# node2 / node3
capabilities: ["ai"]
priority: 1  # node2, 2  # node3

# node5
capabilities: ["ai"]
priority: 3

# node7
capabilities: ["media"]
```

Orchestrator allocate_node() içinde ilk adım capability filtresidir:

```python
capable = [m for m in metrics if service_type.value in m.get("capabilities", [])]
```

Bu filtre sayesinde node7 asla STREAM havuzuna girmez, node1/node4 asla AI havuzuna girmez.

### 5.4 Seçim Stratejileri

| ServiceType | Strateji | Metrik | Gerekçe |
|-------------|---------|--------|---------|
| `STREAM` | `min` | `network_out_percent` | SFU bandwidth-bound; CPU değil bant genişliği tüketir |
| `MEDIA` | `max` | `disk_free_gb` | Mutlak boş alan; yüzde heterojen disklerde yanıltıcı |
| `AI` | `priority + health` | `priority` alanı, CPU < 90% sağlık kontrolü | US IP önceliği; node2→node3→node5 sırası |

```python
strategies = {
    ServiceType.STREAM: lambda x: x.get("network_out_percent", 100.0),
    ServiceType.MEDIA:  lambda x: -x.get("disk_free_gb", 0.0),
    ServiceType.AI:     None,  # priority tabanlı özel metot
}
```

**AI özel metodu:**

```python
def _allocate_ai(self, capable: list[dict]) -> dict:
    healthy = [n for n in capable if n.get("cpu_percent", 100) < 90]
    pool = healthy if healthy else capable   # tümü doluysa yine de seç
    return min(pool, key=lambda x: x.get("priority", 999))
```

### 5.5 edge-metrics-agent Güncelleme

Her node'da agent aşağıdaki ek alanları raporlar:

```python
{
    # Mevcut (değişmez)
    "cpu_percent":    psutil.cpu_percent(),
    "disk_percent":   psutil.disk_usage(data_dir).percent,  # alarm için tutulur

    # Yeni — V1.5
    "disk_free_gb":   psutil.disk_usage(data_dir).free / (1024**3),
    "network_out_percent": (bytes_out_per_sec * 8 / 1e6) / interface_speed_mbps * 100,
    "capabilities":   ["stream", "media"],  # node'a özel, .env'den okunur
    "priority":       0,                    # AI node'ları için (diğerleri 0)

    # Mevcut (değişmez)
    "minio_url":      "http://10.10.0.X:9010",
    "livekit_url":    "https://live1.teqlif.com",
    "node_id":        "live1.teqlif.com",
}
```

`interface_speed_mbps` → her node'un `.env`'inde tanımlı (node1/node4: 2000, node7: 1000, node2: ~1000).

### 5.6 Dual Redis Write

edge-metrics-agent node5 düşüşünde metrik akışını kesmemek için her iki core Redis'ine yazar:

```python
REDIS_URLS = ["redis://10.10.0.10:6379", "redis://10.10.0.11:6379"]
# 10.10.0.10 = node5/node6 PostgreSQL VIP
# 10.10.0.11 = node5/node6 Redis VIP
```

Keepalived VIP yaklaşımında aslında tek URL yeterlidir (`10.10.0.11`). Dual write, VIP'siz kurulumlarda veya Keepalived devreye girmeden önce geçici güvencedir.

---

## 6. WireGuard Mesh Genişletme

### 6.1 Güncellenmiş IP Tablosu

| Node | WireGuard IP | Konum | Rol |
|------|-------------|-------|-----|
| node1 | 10.10.0.1 | OVH Frankfurt | Edge: Stream + Media |
| gateway | 10.10.0.2 | Netcup | Gateway #1 |
| node2 | 10.10.0.3 | RackNerd US | AI Proxy (priority 1) |
| node3 | 10.10.0.4 | ZAP Ashburn | AI Proxy + Staging + Monitor (priority 2) |
| node5 | 10.10.0.5 | ZAP Münster | Core #1 (Primary) |
| node4 | 10.10.0.6 | OVH Frankfurt | Edge: Stream + Media |
| **node6** | **10.10.0.7** | DELUXHOST Amsterdam | Core #2 (Passive) |
| **node7** | **10.10.0.8** | DELUXHOST Kerkrade | Primary MinIO |
| **gateway2** | **10.10.0.9** | DELUXHOST Amsterdam | Gateway #2 |

### 6.2 Sanal IP'ler (Keepalived)

| VIP | Servis | Tutucu (normal) |
|-----|--------|-----------------|
| 10.10.0.10 | PostgreSQL / PgBouncer | node5 |
| 10.10.0.11 | Redis | node5 |

---

## 7. DNS ve Cloudflare Kayıt Değişiklikleri

| Domain | Tip | Hedef | Proxy | Not |
|--------|-----|-------|-------|-----|
| `teqlif.com` | A | gateway IP | Proxied | Değişmez |
| `teqlif.com` | A | **gateway2 IP (ekle)** | Proxied | Aktif-aktif için |
| `api.teqlif.com` | A | gateway IP | Proxied | Değişmez |
| `api.teqlif.com` | A | **gateway2 IP (ekle)** | Proxied | Aktif-aktif için |
| `minio1.teqlif.com` | A | node1 IP | DNS Only | Değişmez |
| `minio4.teqlif.com` | A | node4 IP | DNS Only | Değişmez |
| `minio7.teqlif.com` | A | **node7 IP (ekle)** | DNS Only | Yeni primary MinIO |

---

## 8. Değişim Matrisi (V1.4 → V1.5)

| Node | V1.4 Rolü | V1.5 Ek Değişiklikler |
|------|-----------|----------------------|
| **gateway** | Gateway | nginx upstream'e node6 backup eklenir; Keepalived kurulur |
| **gateway2** | *(Yok)* | Sıfırdan kurulum; gateway'in tam kopyası |
| **node1** | Edge: Stream + Media | edge-metrics-agent güncellenir (capabilities, disk_free_gb, network_out_percent); MinIO site replication node7 ile açılır |
| **node2** | AI Proxy (primary) | edge-metrics-agent eklenir (capabilities: ["ai"], priority: 1) |
| **node3** | AI Proxy + Staging + Monitor | edge-metrics-agent güncellenir (capabilities: ["ai"], priority: 2) |
| **node4** | Edge: Stream + Media | node1 ile aynı agent güncellemesi |
| **node5** | Core (primary) | Keepalived kurulur; PostgreSQL streaming replication açılır; Redis REPLICAOF aktif |
| **node6** | *(Yok)* | Sıfırdan kurulum; node5'in hot standby kopyası |
| **node7** | *(Yok)* | Sıfırdan kurulum; MinIO primary storage; edge-metrics-agent (capabilities: ["media"]) |

---

## 9. Kod Tabanı Değişiklikleri

### 9.1 `edge_orchestrator.py`

- `ServiceType` enum: `MEDIA` → `STREAM`, `STORAGE` → `MEDIA`, `AI` eklenir
- `allocate_node()`: capabilities filtresi eklenir
- `_allocate_ai()`: priority tabanlı özel metot eklenir
- Strateji haritası güncellenir: `cpu_percent` → `network_out_percent` (STREAM), `disk_percent` → `-disk_free_gb` (MEDIA)

### 9.2 `edge_metrics_agent/`

- `capabilities` listesi `.env`'den okunur (`AGENT_CAPABILITIES=stream,media`)
- `network_out_percent` hesaplama eklenir (3 saniyelik delta, psutil)
- `disk_free_gb` raporlama eklenir
- `interface_speed_mbps` `.env`'den okunur (`INTERFACE_SPEED_MBPS=2000`)
- `priority` alanı `.env`'den okunur (AI node'ları için; diğerleri 0)
- Dual Redis write: `AGENT_REDIS_URLS` virgülle ayrılmış liste destekler

### 9.3 `config.py`

- `edge_minio_urls` listesine node7 URL eklenir (`.env.production`)
- `_build_public_url()` içinde `live` → `minio` dönüşümü `minio7.teqlif.com` için çalışır (node7'nin node_id'si `live7.teqlif.com` olarak belirlenmez; doğrudan `minio7.teqlif.com` kullanılır; `_build_public_url` buna göre güncellenir)

---

## 10. Failover Sonrası Kurtarma ve Veri Kaybı Analizi

### 10.1 Sorun: WAL Çatallaşması (Timeline Divergence)

node5 düşüp node6 promote edildiğinde iki WAL akışı birbirinden ayrılır:

```
T=0   node5 primary  — son LSN: 0/5A000100  (node6'ya iletilmemiş ~1-5ms veri var)
T=1   node5 çöktü
T=2   node6 promote  — son LSN: 0/5A000000  (birkaç ms geride)
T=3+  node6 yeni yazılar alıyor → 0/5B000000 (yeni timeline)

T=10  node5 geri geldi — LSN: 0/5A000100
      node6 LSN:         0/5B000000
      → İki WAL stream çatallaştı; direkt replica yapılamaz
```

### 10.2 Bileşen Bazlı Veri Kaybı ve Kurtarma

#### PostgreSQL — `pg_rewind` (kalıcı veri kaybı riski)

**Veri kaybı:** node5'in T=0→T=2 arasında aldığı, node6'ya yetişemeyen ~1-5ms'lik commit'ler **kalıcı olarak kaybolur.** Bu async replication'ın inherent tradeoff'udur.

```bash
# node5 geri geldiğinde:
sudo systemctl stop postgresql@16-main

# pg_rewind: divergence point'e geri sarar, node6 WAL'ını uygular
pg_rewind \
    --target-pgdata=/var/lib/postgresql/16/main \
    --source-server="host=10.10.0.7 port=5433 user=replicator"

# postgresql.conf: primary_conninfo → node6
echo "primary_conninfo = 'host=10.10.0.7 port=5433 user=replicator'" \
    >> /var/lib/postgresql/16/main/postgresql.auto.conf
echo "recovery_target_timeline = 'latest'" \
    >> /var/lib/postgresql/16/main/postgresql.auto.conf

sudo systemctl start postgresql@16-main
# node5 artık node6'nın replica'sı
```

> **Ön koşul (bootstrap'ta ayarlanmalı):** `wal_log_hints = on` — pg_rewind bu ayar olmadan çalışmaz.

#### Redis — PSYNC (otomatik, düşük kayıp)

Redis kendi partial sync mekanizmasıyla eksik veriyi doldurur:

```bash
# node5 geri geldiğinde tek komut yeterli:
redis-cli REPLICAOF 10.10.0.7 6379
```

`PSYNC` protokolü: node5'in replication offset'ini node6 ile karşılaştırır, eksik chunk'ı iletir. Repl buffer aşılmamışsa (~100 MB varsayılan) full SYNC gerekmez.

**Veri kaybı:** Session tokenları, metrics, gift log gibi kısa TTL'li veriler için önemsiz. Aktif oturumlar ~30-60 dakikada zaten yenilenir.

#### ClickHouse — Gap kabul edilir

ClickHouse replika kurulmadığı için failover süresindeki analitik yazılar (izlenme, tıklama, stream metrikleri) node5'e geri geldiğinde eksik olacaktır. Bu iş kritik değildir; dashboard'da kısa bir boşluk oluşur.

**Karar:** ClickHouse data gap V1.5 kapsamında kabul edilebilir risk olarak sınıflandırılmıştır.

### 10.3 Kritik Kural: Otomatik Failback Yoktur

node5 geri geldiğinde Keepalived onu **otomatik olarak primary yapmaz.** Bu kasıtlı bir tasarım kararıdır:

```
node5 geri gelir:
  Keepalived → node5 BACKUP (priority 90) olarak başlar
  VIP (10.10.0.10 / 10.10.0.11) node6'da kalmaya devam eder
  node6 primary olmaya devam eder

Otomatik failback neden tehlikelidir:
  - node5 henüz sync tamamlamadan primary olursa split-brain riski
  - Kısa süreli kesintilerde flip-flop (sürekli geçiş) oluşur
  - pg_rewind tamamlanmadan yazma başlarsa veri bozulur
```

### 10.4 Planlı Failback Prosedürü (Operatör Kararı)

node5'i tekrar primary yapmak istendiğinde:

```bash
# Adım 1: node5'in tam sync olduğunu doğrula
psql -h 10.10.0.7 -U postgres -c "SELECT * FROM pg_stat_replication;"
# write_lag, flush_lag, replay_lag → tümü 0 olana kadar bekle

# Adım 2: Planlı switchover (pg_ctl promote DEĞİL — bu için pg_rewind benzeri hazırlık gerek)
# node6'da:
sudo systemctl stop teqlif teqlif-worker  # yeni yazı gelmesin
# node5 otomatik yakalar (lag = 0 iken)

# Adım 3: Keepalived priority değiştir
# node5 /etc/keepalived/keepalived.conf → priority 100
# node6 /etc/keepalived/keepalived.conf → priority 90
sudo systemctl reload keepalived  # her iki node'da

# Adım 4: node6 Redis'i replica yap
redis-cli -h 10.10.0.6 REPLICAOF 10.10.0.5 6379

# Adım 5: node5 PostgreSQL primary (Keepalived notify_master script çalışır)
# node6 PostgreSQL → replica

# Adım 6: servisleri başlat
sudo systemctl start teqlif teqlif-worker
```

### 10.5 Veri Kaybı Özeti

| Bileşen | Failover Veri Kaybı | Kurtarma | Kabul Düzeyi |
|---------|---------------------|----------|--------------|
| **PostgreSQL** | ~1-5ms commit'ler | `pg_rewind` + replica | ⚠️ Düşük ama var — kabul edildi |
| **Redis** | ~1-5ms yazılar | `REPLICAOF` + PSYNC | ✅ Önemsiz (TTL'li veri) |
| **ClickHouse** | Tüm failover süresi | Yok (kabul) | ⚠️ Analitik gap — kabul edildi |
| **MinIO** | Yok | — | ✅ Edge node'larda bağımsız |

**PostgreSQL kaybını minimize etmek için:** `synchronous_commit = remote_write` ayarı ile async yerine yarı-sync replication yapılabilir. Ancak bu her yazma işlemine ~1-3ms latency ekler. V1.5 için async (mevcut) tercih edilmiştir; yük arttıkça V2.0'da değerlendirilebilir.

---

## 12. Operasyonel Prensipler (V1.4'ten Devam)

V1.4'te yerleşen prensipler V1.5'te de geçerlidir:

1. **Sıfır Statik Veri:** Tüm eşikler, IP'ler, kapasiteler `.env`'den okunur; kod içinde hardcoded değer yoktur.
2. **Idempotent Bootstrap:** `bootstrap_gateway2.sh`, `bootstrap_node6.sh`, `bootstrap_node7.sh` defalarca çalıştırılabilir olacaktır.
3. **WireGuard private key'leri git'e girmez:** Her node'da `wg genkey` ile üretilir.
4. **`.env` dosyaları git'e girmez:** Sadece boş şablonlar (`*.template`) commit edilir.
5. **Single Restart Komutu:** `sudo teqlif-restart` V1.5 node'larında da geçerli olacak; PgBouncer ve Keepalived dahil tüm stack'i yönetecek şekilde güncellenecektir.

---

*Belge tarihi: 2026-09-25 | Hazırlık: V1.5 mimari analiz seansı*
