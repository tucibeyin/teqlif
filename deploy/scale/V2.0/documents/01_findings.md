# Teqlif Scale V2.0 — Findings (Fikir Belgesi)

> **Durum:** Tamamlandı — plan aşamasına hazır  
> **Yaklaşım:** Sıfırdan kurulum · migration yok · kullanıcıya açılmamış sistem  
> **Odak:** Lightweight · loosely coupled · minimal dependency · dinamik config  
> **Son güncelleme:** 2026-09-27

---

## Temel Prensipler

1. **Sıfırdan kurulum** — kurtarılacak veri yok, migration yok, gerekirse tüm node'lara format
2. **Tek rol, tek sorumluluk** — her node tipinin sabit bir ana rolü var, karışmaz
3. **Failback = geçici durum** — ikinci bir rol değil, arıza sırasında devreye giren tanımlı davranış
4. **Loosely coupled** — bir node düşünce sadece o rolün işlevi etkilenir, zincirleme çöküş olmaz
5. **Orchestrator merkezi beyin** — sistem durumu kararları tek servis tarafından verilir
6. **Dinamik config** — yeni node = config'e bir blok, kod değişikliği yok
7. **Sıfır ek dependency** — mevcut araçlarla (Redis, nginx, WireGuard, MinIO, LiveKit) çözülür
8. **Operatör = son çare** — rutin işler otomatik, yıkıcı/geri alınamaz işlemler onay gerektirir

---

## 1. Rol Taksonomisi (Kesinleşti)

### 1.1 Ana Roller

| Rol | Node'lar | Servisler | Başka iş alır mı? |
|-----|---------|-----------|------------------|
| **Gateway** | gateway, gateway2 | nginx, promtail, node_exporter | ❌ Asla |
| **Core** | node5, node6 | FastAPI, ARQ, PostgreSQL, Redis, ClickHouse, PgBouncer, Orchestrator | ❌ Asla |
| **Staging + Monitor + Backup** | node3 | Prometheus, Loki, Grafana, Alertmanager, staging stack, teqlif-ai-proxy | ❌ Kendi rolü dışında değil |
| **Stream** | node1, node4 | LiveKit SFU, edge-metrics-agent | ❌ Asla |
| **Storage** | node7, node8 | MinIO (1TB HDD × 2), edge-metrics-agent, Loki/Promtail | ❌ Tek rol, başka iş almaz |
| **AI Proxy** | node2 | teqlif-ai-proxy | ❌ Sadece AI |

**Gerekçe (Core node'lar):** FastAPI + ARQ + PostgreSQL + Redis + ClickHouse birlikte aynı node'da çalışması zorunlu — bunları ayırmanın yararı şu an maliyetini karşılamıyor.

**Gerekçe (Gateway node'lar):** DMZ'de çalışır, business logic girmez. CF Multi-A zaten gateway failover'ını hallediyor.

**Gerekçe (node7):** 2.9 GB RAM, MinIO dışında anlamlı iş çalıştıramaz.

**Gerekçe (node8):** node7 ile birebir aynı donanım (2c / 2.9 GB RAM / 1TB HDD, DELUXHOST NL, AS214677) — aynı datacenter, düşük latans, symmetric dual-write için ideal eş. MinIO dışında anlamlı iş çalıştıramaz (RAM sınırı).

### 1.2 Failover Matrisi

| Node düşerse | Otomatik geçiş | Etki |
|-------------|----------------|------|
| gateway | CF Multi-A → gateway2 tek başına | Şeffaf |
| gateway2 | CF Multi-A → gateway tek başına | Şeffaf |
| node1 | Orchestrator → stream → node4 | Koordineli |
| node4 | Orchestrator → stream → node1 | Koordineli |
| node7 | node8 zaten aynı verileri taşıyor → node8 tek başına; orchestrator node7'yi DNS'ten çıkarır | ~30s DNS (~6s tespit) |
| node8 | node7 zaten aynı verileri taşıyor → node7 tek başına; orchestrator node8'i DNS'ten çıkarır | ~30s DNS (~6s tespit) |
| node5 | Keepalived (~3s) → node6 promote | Otomatik |
| node6 | Pasif, etkisiz | — |
| node2 | Orchestrator → AI → node3 → node5 | Cascade |
| node3 | Monitor yok, staging durur | Kabul edilebilir |
| **node5 + node6** | **Sistem erişilemez** | **Kabul — yedekten restore** |

---

## 2. Trafik Mimarisi

```
İnternet
  │
  ├─[CF Proxied]─────────────────────────────────────────────┐
  │  teqlif.com · api.teqlif.com · media.teqlif.com          │
  │         ↓ CF Cache (public images/video)                 │
  │   gateway  ←── CF Multi-A ──→  gateway2                  │
  │         ↓ nginx upstream (backup direktifi)              │
  │   node5 (primary)  /  node6 (standby)                    │
  │                                                           │
  ├─[DNS Only]───────────────────────────────────────────────┤
  │  live1.teqlif.com   → node1 (WebRTC UDP, LiveKit)        │
  │  live2.teqlif.com   → node4 (WebRTC UDP, LiveKit)        │
  │  uploads.teqlif.com → node7 + node8 (S3 PUT, Multi-A)   │
  │                                                           │
  └─[WireGuard Mesh]─────────────────────────────────────────┘
       Tüm iç trafik: DB, Orch Redis, metrics, logs
```

---

## 3. teqlif-orchestrator Servisi (Kesinleşti)

### 3.1 Nerede Çalışır

**node5 + node6 — sadece bu ikisi.**

- Edge node'lar (node1, node4, node7) hakkında karar veriyor — orada çalışırsa self-referential failure
- Gateway DMZ, business logic girmez
- node2 RAM 1.4 GB dar
- node3 izole, farklı sorumluluk

### 3.2 Leader Election

```python
# Her 10s:
SET orchestrator:leader "node5"  EX 30  NX   # atomik — tek kazanan

# Kilit sahibi  → aktif orchestrator, kararları o verir
# Kilit alamayan → standby, izler, hazırda bekler

# node5 düşünce:
#   30s içinde TTL düşer → node6 NX ile alır → aktif olur
```

Keepalived `notify_master` script'ine satır eklenerek senkronize edilebilir — opsiyonel.

### 3.3 Sorumluluklar

**Otomatik (sıfır dokunuş):**

| Görev | Tetikleyici | Eylem |
|-------|------------|-------|
| node7 veya node8 ↓ tespiti | `edge:metrics:{node}` TTL düşer (6s) | Down node'u uploads + media DNS'inden çıkar; `orch:best:storage_nodes = ["kalan_node"]` |
| node7 veya node8 ↑ tespiti | `edge:metrics:{node}` geri gelir | Operatöre Telegram bildir (manuel mc sync sonrası DNS'e geri al → dual-write'a dön) |
| Her iki node disk > 85% | `edge:metrics:{node7,node8}`.disk_percent | Telegram URGENT — node9 eklenme zamanı |
| Redis REPLICAOF kurulum | node5 geri döndü | `REPLICAOF node6 6379` — idempotent, güvenli |
| Stream node seçimi | FastAPI isteği | `network_out_percent` min seçimi |
| Storage node(lar) seçimi | FastAPI isteği | `orch:best:storage_nodes` listesini oku; listedeki tüm node'lara yaz |
| AI node seçimi | FastAPI isteği | Priority sırası: node2 → node3 → node5 |

**Yarı otomatik (Telegram onayı):**

| Görev | Orchestrator | Operatör |
|-------|-------------|---------|
| pg_rewind | Koşulları kontrol et, komutu hazırla, Telegram gönder | [Onayla] → orchestrator çalıştırır |
| Planned failback (node5 → primary) | sync lag = 0 doğrula, hazır bildir | [Failback Başlat] butonu |

**Asla otomatik olmaz:**
- node5 + node6 her ikisi çöküşü → manuel yedekten restore
- Deploy / schema migration → CI/CD pipeline'ı

### 3.4 cf-failover Kaldırılıyor

V2.0'da `teqlif.com` ve `api.teqlif.com` CF Multi-A ile aktif-aktif. CF kendi health check ile düşen gateway'i bypass eder.

node2'daki `cf-failover` bash script servisi **kaldırılır.** node2 saf AI Proxy olarak kalır.

Orchestrator DNS yönetimi sadece şunları kapsar: `uploads.teqlif.com` ve `media.teqlif.com`.

---

## 4. İki Redis — İki Sorumluluk (Kesinleşti)

### 4.1 Ayrım

```
Core Redis     (port 6379, Keepalived VIP 10.10.0.11):
  └── Uygulama verisi: sessions, ARQ queue, rate limits, cache
  └── Bağlananlar: FastAPI, ARQ worker — SADECE
  └── Kalıcılık: AOF + RDB aktif

Orchestrator Redis  (port 6380, Keepalived VIP 10.10.0.11):
  └── Altyapı durumu: edge metrics, komutlar, pub/sub
  └── Bağlananlar: edge-metrics-agent (tüm node'lar), teqlif-orchestrator
  └── Kalıcılık: YOK — in-memory only (maxmemory-policy allkeys-lru)
  └── Restart'ta hızla yeniden dolar (TTL'ler 6s–30s)
```

**Edge node'lar Core Redis adresini bilmez.** Core Redis adresi yalnızca FastAPI ve ARQ worker `.env`'inde bulunur.

### 4.2 Pub/Sub Kanal Tasarımı (Orchestrator Redis)

```
edge:metrics:{node_id}     → her node 3s'de bir yazar (TTL 6s)
orch:events                → orchestrator durum değişikliği yayınlar
orch:cmd:{node_id}         → orchestrator o node'a komut gönderir
node:ack:{node_id}         → node komut alındısı / tamamlandı bildirir
```

Örnek storage geçiş akışı:

```
node7 veya node8 TTL düştü
  → orchestrator CF API: down node'u uploads.teqlif.com + media.teqlif.com DNS'inden çıkar
  → SET orch:best:storage_nodes '["kalan_node"]'
  → Telegram #ops: "🔴 {node} erişilemez — DNS güncellendi, {kalan_node} tek başına"
```

### 4.3 RAM Maliyeti (node5 örneği)

```
Core Redis:           ~300 MB
Orchestrator Redis:   ~20  MB   ← minimal ek yük
FastAPI + ARQ:        ~1.5 GB
PostgreSQL:           ~2.0 GB
ClickHouse:           ~1.0 GB
PgBouncer + diğer:    ~0.2 GB
Boş tampon:           ~2.7 GB
```

### 4.4 .env Ayrımı

```bash
# Tüm node'lar (edge-metrics-agent için):
ORCH_REDIS_URL=redis://10.10.0.11:6380

# Sadece Core node'lar (FastAPI + ARQ için):
CORE_REDIS_URL=redis://10.10.0.11:6379
```

---

## 5. Merkezi Orchestrator Config (nodes.yaml)

Tek config dosyası — kod değişikliği yok, node ekleme/çıkarma bu dosyadan:

```yaml
# /etc/teqlif-orchestrator/nodes.yaml
# node5 ve node6'da aynı dosya

nodes:
  node1:
    wg_ip: 10.10.0.1
    primary_role: stream
    failback: null                 # storage failback yok — LiveKit tek rol
    metrics_key: edge:metrics:node1

  node4:
    wg_ip: 10.10.0.6
    primary_role: stream
    failback: null                 # storage failback yok — LiveKit tek rol
    metrics_key: edge:metrics:node4

  node7:
    wg_ip: 10.10.0.8
    primary_role: storage
    storage_peer: node8            # dual-write eşi
    disk_capacity_gb: 1000
    disk_threshold_percent: 85    # ~850 GB efektif kota
    failback: null
    metrics_key: edge:metrics:node7

  node8:
    wg_ip: 10.10.0.12
    primary_role: storage
    storage_peer: node7            # dual-write eşi
    disk_capacity_gb: 1000
    disk_threshold_percent: 85    # ~850 GB efektif kota — node7 ile aynı
    failback: null
    metrics_key: edge:metrics:node8

  node2:
    wg_ip: 10.10.0.3
    primary_role: ai
    ai_priority: 1
    metrics_key: edge:metrics:node2

  node3:
    wg_ip: 10.10.0.4
    primary_role: monitor
    ai_priority: 2                 # monitor rolüne ek AI secondary
    metrics_key: edge:metrics:node3

storage:
  dual_write_nodes: [node7, node8]   # her ikisi sağlıklı → dual-write
  alert_threshold_percent: 85        # her iki node > %85 → URGENT: node9 ekle
  exhausted_threshold_percent: 95    # HTTP 507

selection:
  stream:
    metric: network_out_percent
    strategy: min                  # en az dolu bandwidth
  storage:
    key: orch:best:storage_nodes   # orchestrator pre-computes; liste döner
  ai:
    metric: cpu_percent
    strategy: priority             # önce priority, sonra cpu < 90%
    cpu_threshold: 90
```

---

## 6. Medya Katmanı (Kesinleşti)

### 6.1 İki Domain

| Domain | CF Proxy | Kullanım |
|--------|---------|---------|
| `uploads.teqlif.com` | DNS Only | S3 PUT — direkt node7, CF bypass |
| `media.teqlif.com` | Proxied | S3 GET — CF önbelleği etkin |

### 6.2 Bucket Politikası

| Bucket | Erişim | URL | CF Cache |
|--------|--------|-----|---------|
| `teqlif` (listing, profil) | Public-read | Basit, signature yok | ✅ Tam cache |
| `teqlif-dm` (DM medyası) | Private | Pre-signed, `uploads.teqlif.com` | ❌ CF bypass |

### 6.3 Storage Node Diskleri

**node7 (DELUXHOST NL):**
```
/dev/vda3  →  /  (10 GB SSD): OS + servisler
swap       →  2.0 GB (SSD)
/dev/vdb   →  /mnt/data (1TB HDD): MinIO DATA_DIR
  └── teqlif/         (public)
  └── teqlif-dm/      (private)
  Kota: %85 → ~850 GB efektif
```

**node8 (DELUXHOST NL — aynı datacenter, node7 ile identical):**
```
/dev/vda3  →  /  (10 GB SSD): OS + servisler
swap       →  2.0 GB (SSD)
/dev/vdb   →  /mnt/data (1TB HDD): MinIO DATA_DIR
  └── teqlif/         (public)
  └── teqlif-dm/      (private)
  Kota: %85 → ~850 GB efektif

MinIO config: GOMEMLIMIT=2GiB, GOGC=100 — node7 ile aynı (2.9 GB RAM + 2 GB swap)
```

### 6.4 Dual-Write Storage Stratejisi

**Temel kural:** node7 + node8 birebir aynı donanım — aynı datacenter (DELUXHOST NL, AS214677). Her upload her iki node'a yazılır; bir node düşerse diğeri devam eder — DNS değişikliğiyle şeffaf geçiş.

İkisi identical olduğundan capacity-based phase switching anlamsız: aynı hızda dolarlar, biri %90'a ulaştığında diğeri de %90'dadır. Bu nedenle strateji **sadece failure-based**'dir.

#### Normal Durum — Dual Write

Orchestrator `orch:best:storage_nodes = ["node7", "node8"]` yazar. FastAPI her upload'u her iki node'a paralel gönderir.

```python
# FastAPI upload akışı (dual-write)
storage_nodes = json.loads(await orch_redis.get("orch:best:storage_nodes"))
# → ["node7", "node8"]
await asyncio.gather(*[minio_client(n).put_object(...) for n in storage_nodes])
```

**nginx 404 fallback:** Her iki node'da da aktif — bir node DEGRADED modundayken veya sync gecikmesinde GET isteklerini karşılar:

```nginx
# node8 MinIO nginx — node7 WireGuard IP fallback
location / {
    proxy_pass http://127.0.0.1:9000;
    error_page 404 = @fallback_node7;
}
location @fallback_node7 {
    proxy_pass http://10.10.0.8:9000;
    proxy_set_header Host $host;
}
```

#### Kapasite Senaryosu

```
   0 – 850 GB:   DUAL_WRITE — node7 + node8, her ikisinde aynı data
       > 850 GB:  ALERT — node9 ekle (her iki node %85+)
       > 950 GB:  EXHAUSTED — HTTP 507
```

Efektif kapasite: 850 GB unique data (1TB fiziksel × %85 kota × 2 kopya).

#### Storage State Machine

```
DUAL_WRITE    node7 + node8 sağlıklı
              → her iki node'a yaz (orch:best:storage_nodes = ["node7","node8"])

DEGRADED      Bir node down (TTL düşer, ~6s tespit)
              → kalan node tek başına yazar
              → down node DNS'ten çıkar (~30s CF prop.)
              → orch:best:storage_nodes = ["kalan_node"]

RECOVERY      Down node geri geldi
              → Telegram bildir: "manuel mc sync gerekiyor"
              → Operatör sync tamamlar → DNS'e geri al → DUAL_WRITE

ALERT         Her iki node disk > %85
              → Telegram URGENT: "node9 ekleme zamanı"
              → Hâlâ dual-write devam eder

EXHAUSTED     Her iki node disk > %95
              → HTTP 507 + Telegram URGENT
```

#### Failback Neden Yok?

node1/node4 storage failback V2.0'da kaldırıldı:

| Gerekçe | Açıklama |
|---------|---------|
| node1/node4 sadece 98 GB NVMe | Production medya için yetersiz |
| Dual storage yeterli yedeklilik | node7+node8 farklı disk → tek arıza anında diğeri devam eder |
| "Tek rol" prensibi | node1/node4 yalnızca LiveKit SFU çalıştırır |
| Sync karmaşıklığı | 3 node sync (node1+node4→node7) → hata riski yüksek |

---

## 7. Core Katmanı

Keepalived VIP:
```
10.10.0.10 → PostgreSQL / PgBouncer (port 5432)
10.10.0.11 → Core Redis (port 6379) + Orchestrator Redis (port 6380)
```

node5 primary, node6 replica. Keepalived failover ~3s, otomatik.

**node5 + node6 ikisi birden çöküşü:** Kabul edilen senaryo. Günlük yedek (02:45 UTC → node3) üzerinden restore. RPO ~24h, RTO ~2–6h. node3'ü geçici production core yapmak istemiyoruz.

---

### 7.1 Aktif-Pasif Servis Matrisi

Her node'un hangi servislerinin hangi durumda çalışacağı.

#### node5 — Primary (her zaman aktif)

| Servis | Çalışır mı? | Not |
|--------|-------------|-----|
| `postgresql` | ✅ | Primary — tüm yazmaları alır |
| `pgbouncer` | ✅ | Uygulama bağlantıları buraya gelir |
| `redis-6379` (Core) | ✅ | Master |
| `redis-6380` (Orch) | ✅ | Master |
| `clickhouse-server` | ✅ | Tüm analytics yazmaları |
| `teqlif` (FastAPI) | ✅ | Tüm API trafiği |
| `teqlif-worker` (ARQ default) | ✅ | 45+ cron job + event-driven tasks |
| `teqlif-worker-critical` (ARQ critical) | ✅ | Push, outbid, auction cascade |
| `teqlif-backup.timer` | ❌ | Primary'ye yük bindirme — standby'da çalışır |
| `teqlif-healthcheck.timer` | ✅ | Günlük sağlık raporu |
| `node_exporter`, `promtail` | ✅ | Her zaman |

#### node6 — Standby (pasif, failover için bekler)

| Servis | Çalışır mı? | Not |
|--------|-------------|-----|
| `postgresql` | ✅ | Streaming replica — read-only, node5'ten sürekli sync |
| `pgbouncer` | ❌ | Uygulama yok — gereksiz |
| `redis-6379` (Core) | ✅ | Replica of node5:6379 |
| `redis-6380` (Orch) | ✅ | Replica of node5:6380 |
| `clickhouse-server` | ❌ | ARQ worker çalışmıyor, yazma yok — failover sonrası node3 backup'ından restore |
| `teqlif` (FastAPI) | ❌ | Replica DB'ye write yapamaz |
| `teqlif-worker` (ARQ default) | ❌ | Cron job + task yazmaları replica'ya gider, crash |
| `teqlif-worker-critical` | ❌ | Aynı gerekçe |
| `teqlif-backup.timer` | ✅ | Replica'dan backup alır — primary'e sıfır yük |
| `teqlif-healthcheck.timer` | ❌ | Uygulama servisleri çalışmıyor |
| `node_exporter`, `promtail` | ✅ | Her zaman |

#### ClickHouse — Neden Replike Edilmiyor?

ClickHouse native replication ZooKeeper/Keeper gerektirir — fazla bağımlılık. Analytics verileri (user_interactions, feed_analytics) transaction-critical değil; RPO ~24h (backup sıklığıyla aynı) kabul edilebilir. Failover sonrası node3'teki günlük backup'tan restore edilir. ML modelleri zaten haftalık yeniden eğitiliyor — bir günlük eksik analytics verisinin etkisi önemsiz.

---

### 7.2 Failover Aktivasyon Sırası

Keepalived VIP'leri ~3s içinde node6'ya otomatik taşır. Ama servis başlatma için operatör adımları gerekir:

```
1. Keepalived — otomatik
   VIP 10.10.0.10 + 10.10.0.11 → node6

2. PostgreSQL promote (operatör)
   sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
   # veya: sudo touch /var/lib/postgresql/17/main/failover.trigger

3. Redis promote (operatör)
   redis-cli -p 6379 replicaof no one
   redis-cli -p 6380 replicaof no one

4. Servis başlatma
   sudo teqlif-restart
   # Script pg_is_in_recovery()=false görür → alembic + sync_translations + teqlif restart

5. Doğrulama
   Durum tablosu: tüm servisler ACTIVE
   node3 Grafana: node6 trafik alıyor, node5 erişilemiyor
```

> **Not:** PostgreSQL promote adımı Keepalived'ın `notify_master` hook'una bağlanabilir — tam otomatik failover mümkün ama V2.0 için opsiyonel.

---

### 7.3 Failback (node5 geri döndüğünde)

node5 onarıldığında:
1. node5 PostgreSQL → node6'nın replica'sı olarak başlatılır (yeni primary = node6)
2. node5 Redis → node6 replica olarak
3. Sync tamamlanınca rolleri ters çevirmek için yeni bir failover (isteğe bağlı)

Yüksek trafik olmadığı bir pencerede yapılır — zorunlu değil. node6 primary olarak kalmaya devam edebilir.

---

## 8. DNS Kayıtları

### 8.1 Mevcut Durum (V1.4 — Cloudflare)

| Domain | Tip | IP | CF Proxy | V2.0 Durumu |
|--------|-----|----|----------|-------------|
| `teqlif.com` | A | 94.16.105.135 (gateway) | Proxied | 🔄 gateway2 için **2. A kaydı ekle** |
| `api.teqlif.com` | A | 94.16.105.135 (gateway) | Proxied | 🔄 gateway2 için **2. A kaydı ekle** |
| `api-staging.teqlif.com` | A | 94.16.105.135 (gateway) | Proxied | ✅ Kalır |
| `staging.teqlif.com` | A | 94.16.105.135 (gateway) | Proxied | ✅ Kalır |
| `live1.teqlif.com` | A | 135.125.175.223 (node1) | DNS Only | ✅ Kalır |
| `live2.teqlif.com` | A | 51.75.74.124 (node4) | DNS Only | ✅ Kalır |
| `live-staging.teqlif.com` | A | 5.249.165.10 (node3) | DNS Only | ✅ Kalır |
| `minio1.teqlif.com` | A | 135.125.175.223 (node1) | DNS Only | ❌ **Silinecek** |
| `minio2.teqlif.com` | A | 51.75.74.124 (node4) | DNS Only | ❌ **Silinecek** |
| `minio-staging.teqlif.com` | A | 5.249.165.10 (node3) | DNS Only | ❌ **Silinecek** |

**Gözlem:** `teqlif.com` tek A kaydı var — gateway2 için ikinci kayıt henüz eklenmemiş. CF Multi-A aktif değil, failover çalışmıyor.

---

### 8.2 V2.0 Hedef DNS Tablosu

| Domain | Tip | Hedef | CF Proxy | Notlar |
|--------|-----|-------|----------|--------|
| `teqlif.com` | A | gateway1 IP | Proxied | |
| `teqlif.com` | A | gateway2 IP | Proxied | **Yeni** — CF Multi-A |
| `api.teqlif.com` | A | gateway1 IP | Proxied | |
| `api.teqlif.com` | A | gateway2 IP | Proxied | **Yeni** — CF Multi-A |
| `live1.teqlif.com` | A | node1 IP | DNS Only | Değişmez |
| `live2.teqlif.com` | A | node4 IP | DNS Only | Değişmez |
| `uploads.teqlif.com` | A | node7 IP | DNS Only | **Yeni** — S3 PUT, CF bypass |
| `uploads.teqlif.com` | A | node8 IP | DNS Only | **Yeni** — S3 PUT, Multi-A (node8) |
| `media.teqlif.com` | A | node7 IP | Proxied | **Yeni** — CF cache |
| `media.teqlif.com` | A | node8 IP | Proxied | **Yeni** — CF cache, Multi-A (node8) |
| `uploads-staging.teqlif.com` | A | node3 IP | DNS Only | **Yeni** — staging tam izolasyon |
| `media-staging.teqlif.com` | A | node3 IP | Proxied | **Yeni** — staging CF cache |
| `staging.teqlif.com` | A | gateway1 IP | Proxied | Değişmez |
| `api-staging.teqlif.com` | A | gateway1 IP | Proxied | Değişmez |
| `live-staging.teqlif.com` | A | node3 IP | DNS Only | Değişmez |

**Kaldırılanlar:** `minio1.teqlif.com`, `minio2.teqlif.com`, `minio-staging.teqlif.com`

---

### 8.3 DNS Değişiklik Özeti

| Aksiyon | Domain | Gerekçe |
|---------|--------|---------|
| ➕ Ekle | `teqlif.com` (A → gateway2) | CF Multi-A gateway failover |
| ➕ Ekle | `api.teqlif.com` (A → gateway2) | CF Multi-A gateway failover |
| ➕ Ekle | `uploads.teqlif.com` (A → node7) | S3 PUT — CF bypass zorunlu |
| ➕ Ekle | `uploads.teqlif.com` (A → node8) | S3 PUT — Multi-A, node8 storage |
| ➕ Ekle | `media.teqlif.com` (A → node7) | MinIO public okuma — CF cache |
| ➕ Ekle | `media.teqlif.com` (A → node8) | CF cache, Multi-A, node8 storage |
| ➕ Ekle | `uploads-staging.teqlif.com` | Staging/prod tam izolasyon |
| ➕ Ekle | `media-staging.teqlif.com` | Staging CF cache |
| ❌ Sil | `minio1.teqlif.com` | V2.0'da bu domain şeması yok |
| ❌ Sil | `minio2.teqlif.com` | V2.0'da bu domain şeması yok |
| ❌ Sil | `minio-staging.teqlif.com` | V2.0'da bu domain şeması yok |

> **Zamanlama:** `minio*.teqlif.com` kayıtları yalnızca node7 kurulup `uploads.teqlif.com` / `media.teqlif.com` yayına girdikten sonra silinir. Erken silmek V1.4 prod trafiğini keser.

---

## 9. WireGuard Mesh

10 node, tam mesh. Her node diğer 9 node ile peer.

| Node | WG IP | Rol |
|------|-------|-----|
| node1 | 10.10.0.1 | Stream #1 |
| gateway | 10.10.0.2 | Edge Proxy #1 |
| node2 | 10.10.0.3 | AI Proxy #1 |
| node3 | 10.10.0.4 | Monitor + Staging + AI #2 |
| node5 | 10.10.0.5 | Core #1 (Primary) |
| node4 | 10.10.0.6 | Stream #2 |
| node6 | 10.10.0.7 | Core #2 (Passive) |
| node7 | 10.10.0.8 | Storage #1 (1TB HDD) |
| gateway2 | 10.10.0.9 | Edge Proxy #2 |
| — | 10.10.0.10 | VIP: PostgreSQL/PgBouncer |
| — | 10.10.0.11 | VIP: Core Redis + Orch Redis |
| node8 | 10.10.0.12 | Storage #2 (1TB HDD) |

---

## 10. FastAPI ↔ Orchestrator İletişimi (Kesinleşti)

### 10.1 Strateji: Pre-computed Redis Keys

Orchestrator her 3s'de metrikleri okur, en iyi node'u hesaplar ve Orch Redis'e yazar. FastAPI sadece okur — ikisi hiç doğrudan konuşmaz.

```
Orchestrator  →  yazar  →  Orch Redis
FastAPI        ←  okur   ←  Orch Redis
```

```python
# FastAPI isteği gelir (her seferinde <1ms):
node_id = await orch_redis.hget("orch:best", "stream")   # → "node1"
endpoint = nodes_config[node_id]["livekit_url"]           # → nodes.yaml'dan
```

**Neden?**
- Sıfır senkron bağımlılık — orchestrator crash'lese son değer TTL süresince geçerli
- FastAPI orchestrator'ın varlığını bilmiyor, sadece Redis okuyor
- Sub-millisecond seçim

### 10.2 FastAPI .env

```bash
CORE_REDIS_URL = redis://10.10.0.11:6379   # sessions, ARQ, cache
ORCH_REDIS_URL = redis://10.10.0.11:6380   # node seçimi, read-only
```

### 10.3 Orchestrator API Güvenliği

Pre-computed model benimsediğimizde orchestrator dışarıya HTTP port açmaz. Telegram onaylı işlemler için Telegram Bot API'ye ÇIKIŞ yapar — gelen bağlantı almaz. WireGuard + Redis ACL yeterli.

---

## 11. Orch Redis Şeması (Kesinleşti)

Orch Redis, tüm sistemin canlı kaynak haritası. Her node tam resource verisi yazar; orchestrator bu veriyi okuyarak hem servis seçimi hem durum yönetimi yapar.

### 11.1 edge:metrics:{node_id} — Her Node'un Canlı Kaynakları

```
Key    : edge:metrics:{node_id}   (Hash)
TTL    : 6s  (agent 3s'de bir yazar; 6s = 2 × interval)
Yazar  : edge-metrics-agent (her node)
Okur   : teqlif-orchestrator
```

| Alan | Örnek | Açıklama |
|------|-------|---------|
| `cpu_percent` | 34.2 | Anlık CPU kullanımı |
| `cpu_cores` | 6 | Toplam çekirdek |
| `load_1m` | 1.4 | 1 dakika yük ortalaması |
| `load_5m` | 1.2 | 5 dakika yük ortalaması |
| `ram_total_gb` | 11.4 | Toplam RAM |
| `ram_used_gb` | 4.2 | Kullanılan RAM |
| `ram_free_gb` | 7.2 | Boş RAM |
| `ram_percent` | 36.8 | RAM kullanım yüzdesi |
| `swap_used_gb` | 0.3 | Swap kullanımı |
| `disk_total_gb` | 98.3 | Veri diski toplam (DATA_DISK_PATH) |
| `disk_used_gb` | 28.1 | Veri diski kullanılan |
| `disk_free_gb` | 70.2 | Veri diski boş — **storage seçim metriği** |
| `disk_percent` | 28.6 | Veri diski kullanım yüzdesi |
| `net_out_mbps` | 124.5 | Anlık çıkış bant genişliği |
| `net_in_mbps` | 45.2 | Anlık giriş bant genişliği |
| `net_out_percent` | 6.2 | `(out_mbps / interface_speed) × 100` — **stream seçim metriği** |
| `interface_speed_mbps` | 2000 | `.env`'den: node1/node4=2000, diğerleri=1000 |
| `primary_role` | stream | Bu node'un ana rolü |
| `capabilities` | ["stream","media"] | Aktif yetenekler |
| `node_id` | node1 | — |
| `wg_ip` | 10.10.0.1 | — |
| `timestamp` | 1727308800.1 | Unix epoch |

**node7 özel alan — iki disk:**

```
disk_ssd_free_gb   → /  (SSD, OS diski)
disk_free_gb       → /mnt/data  (HDD, MinIO DATA_DIR) ← seçim metriği bu
```

Agent hangi diski `disk_free_gb` olarak raporlayacağını `.env`'den alır:

```bash
DATA_DISK_PATH=/mnt/data       # node7
DATA_DISK_PATH=/var/lib/minio  # node1, node4
```

### 11.2 orch:best — Orchestrator'ın Pre-computed Seçimleri

```
Key    : orch:best   (Hash)
TTL    : 10s
Yazar  : teqlif-orchestrator (her metrics döngüsünde günceller)
Okur   : FastAPI (HGET)
```

| Field | Değer örneği | Açıklama |
|-------|-------------|---------|
| `stream` | `node1` | En düşük `net_out_percent` |
| `ai` | `node2` | En düşük priority, CPU < 90% |

> **Storage seçimi** `orch:best` Hash'inde değil, ayrı `orch:best:storage_nodes` String key'inde: JSON liste döner — `["node7","node8"]` (dual-write, normal) veya `["kalan_node"]` (DEGRADED — bir node down).

### 11.3 orch:state:{node_id} — Orchestrator'ın Node Durum Kaydı

```
Key    : orch:state:{node_id}   (Hash)
TTL    : yok — orchestrator yazar, kalıcı
Yazar  : teqlif-orchestrator
Okur   : teqlif-orchestrator, FastAPI (isteğe bağlı)
```

| Alan | Değerler | Açıklama |
|------|---------|---------|
| `status` | `up` `down` `failback` `degraded` `exhausted` | Node'un güncel durumu |
| `primary_role` | `stream` `storage` `ai` `core` `gateway` `monitor` | — |
| `failback_active` | `true` `false` | Geçici görev üstlendi mi |
| `failback_role` | `storage` veya boş | Üstlenilen geçici rol |
| `down_since` | Unix epoch | Ne zaman düştü |
| `last_seen` | Unix epoch | Son metrics timestamp |

### 11.4 Pub/Sub Kanallar

```
orch:events              → orchestrator durum değişikliği yayınlar (broadcast)
orch:cmd:{node_id}       → orchestrator o node'a komut gönderir
node:ack:{node_id}       → node komut alındısı / tamamlandı bildirir
orchestrator:leader      → String, TTL 30s — leader election key
```

### 11.5 Tam Orch Redis Haritası

```
edge:metrics:node1           Hash  TTL:6s   → node1 canlı kaynaklar
edge:metrics:node2           Hash  TTL:6s   → node2 canlı kaynaklar
edge:metrics:node3           Hash  TTL:6s   → ...
edge:metrics:node4           Hash  TTL:6s
edge:metrics:node5           Hash  TTL:6s
edge:metrics:node6           Hash  TTL:6s
edge:metrics:node7           Hash  TTL:6s
edge:metrics:node8           Hash  TTL:6s   → node8 canlı kaynaklar (storage #2)
edge:metrics:gateway         Hash  TTL:6s
edge:metrics:gateway2        Hash  TTL:6s

orch:best                    Hash  TTL:10s  → stream/ai seçimleri
orch:best:storage_nodes      String TTL:10s → JSON list: ["node7","node8"] (normal) veya ["kalan_node"] (DEGRADED)
orch:state:node1         Hash  no-TTL   → node durumları
orch:state:node2         Hash  no-TTL
...

orchestrator:leader      String TTL:30s → hangi core node aktif orchestrator

orch:events              Pub/Sub channel
orch:cmd:{node_id}       Pub/Sub channel
node:ack:{node_id}       Pub/Sub channel
```

---

## 12. Medya Erişim Mimarisi (Kesinleşti)

### 12.1 İki Domain, Net Sorumluluk

```
uploads.teqlif.com  →  DNS Only  →  node7   (yazmak — CF bypass)
media.teqlif.com    →  CF Proxied →  node7  (okumak — CF cache)
```

`uploads.teqlif.com` URL'i **hiçbir zaman DB'ye yazılmaz.** Yalnızca upload işlemi sırasında geçici kullanılır. DB'ye ve client'a her zaman `media.teqlif.com` URL'i gider.

### 12.2 Public vs DM Ayrımı

| İçerik | Bucket | Download URL | CF Cache | Erişim |
|--------|--------|-------------|---------|--------|
| Listing/profil görseli | `teqlif` (public) | `media.teqlif.com/teqlif/{key}` — param yok | ✅ 7 gün | Herkes |
| DM medyası | `teqlif-dm` (private) | `media.teqlif.com/teqlif-dm/{key}?X-Amz-...` — pre-signed | ❌ no-store | Sahip kullanıcı |

Her iki içerik tipi de `media.teqlif.com` üzerinden CF'den geçer. Fark: public URL imzasız → CF cache'ler; DM URL pre-signed → CF geçirir, cache'lemez.

### 12.3 Pre-signed URL Üretimi

```python
# Upload (her iki tip):
upload_url = s3.generate_presigned_url(
    "put_object",
    endpoint_url="https://uploads.teqlif.com",   # DNS Only
)

# DM download:
download_url = s3.generate_presigned_url(
    "get_object",
    endpoint_url="https://media.teqlif.com",      # CF Proxied
    ExpiresIn=3600,
)

# Backend'in DM yanıtında döndürdüğü:
{
    "url":       "https://media.teqlif.com/teqlif-dm/.../photo.jpg?X-Amz-...",
    "cache_key": "teqlif-dm/user_123/msg_456/photo.jpg",   # mobile cache anahtarı
    "expires_at": 1727312400
}
```

`cache_key` sabit S3 path — pre-signed URL expire olsa bile mobile cache anahtarı geçerliliğini korur.

### 12.4 CF Cache Rules (media.teqlif.com)

```
Kural: media.teqlif.com
  Eşleşme: dosya uzantısı ∈ {jpg, jpeg, png, webp, gif, mp4, mov, mp3, m4a, pdf}
  Edge Cache TTL:    7 gün (görsel/ses) · 1 gün (video)
  Browser Cache TTL: 1 gün
  Cache-Control:     public, max-age=604800, immutable  (MinIO'dan döner)

  Pre-signed URL'ler (DM, ?X-Amz-* param'lı):
    MinIO Cache-Control: no-store → CF geçirir, önbelleklemez
```

### 12.5 Üç Katmanlı Cache Mimarisi

```
Device Cache  →  CF Edge (300+ PoP)  →  node7 veya node8 (Kerkrade, NL)
  1. katman          2. katman               3. katman

İstek sırası:
  1. Device cache'de var mı?  → evet: anında göster, ağa gitme
  2. CF edge'de var mı?       → evet: CF'den al, device'a kaydet
  3. Her ikisi de yok          → CF Multi-A: node7 veya node8'den al → CF'e + device'a kaydet
```

---

## 13. Mobile Cache Stratejisi (Backend API Notu)

### 13.1 Otomatik Eviction — Kullanıcı Müdahalesi Gerekmez

Cache kendini yönetir: TTL + LRU (Least Recently Used) kombinasyonu.

- **TTL**: öğe ne kadar süre "canlı" kalır
- **LRU**: limit dolduğunda en uzun süre erişilmeyen öğe çıkar
- **Her erişimde** öğenin `last_accessed` timestamp'i güncellenir → aktif içerik hayatta kalır

### 13.2 Cache Politikaları (İçerik Tipine Göre)

| Cache | İçerik | TTL | Max Boyut | Eviction |
|-------|--------|-----|----------|---------|
| **Public Cache** | Profil, listing, thumbnail | 14 gün | 200 MB | LRU — limitde en eskisi çıkar |
| **DM Cache** | DM fotoğraf, ses, kısa video | 30 gün | 150 MB | LRU — thread açılmayan önce çıkar |
| **Video Cache** | Listing video önizleme | 3 gün | 100 MB | LRU — boyut öncelikli eviction |

**Toplam cihaz kullanımı:** ~450 MB üst sınır. Modern akıllı telefon için makul.

**Kapasite örnekleri:**
```
200 MB public cache:
  ~800 listing görseli (250 KB ort.)
  ~2000 profil fotoğrafı (100 KB ort.)

150 MB DM cache:
  ~400 DM fotoğrafı (300 KB ort.)
  ~200 DM ses dosyası (500 KB ort. / 30s)
```

### 13.3 Eviction Mantığı

```
Her uygulama başlangıcında (arka planda):
  1. TTL geçmiş öğeler silinir
  2. Cache boyutu limiti aşılmışsa LRU sırasına göre silinir

Her içerik erişiminde:
  last_accessed = now()   ← LRU sıralaması güncellenir

Sonuç:
  Kullanıcının sık açtığı DM thread medyası → hep cache'de
  Aylar önce bakılan ilan görseli → TTL geçince otomatik gider
  Aktif konuşmaların medyası → LRU eviction'da korunur
```

### 13.4 Özel Durumlar

**DM thread silindiğinde:** Uygulama o thread'in cache key'lerini temizler.  
**Kullanıcı çıkış yaptığında:** DM cache tamamen temizlenir (özel içerik).  
**Public cache:** Çıkışta temizlenmez — anonimdir, başka kullanıcı da aynı içeriğe erişebilir.  
**Manuel temizleme:** Ayarlar sayfasında seçenek sunulabilir, zorunlu değil.

### 13.5 Prefetch (Proaktif Cache)

```
Feed scroll        → görünür alanın 1 sayfa ilerisini prefetch
Listing detay açıl → diğer görselleri arka planda indir
DM thread açıl     → son 20 mesajın medyasını prefetch
```

Bu kararlar tamamen mobile implementasyona aittir; infrastructure değişikliği gerektirmez.

---

## 14. Telegram Bot (Kesinleşti)

### Tek Bot, İki Kanal

Ayrı bot yönetmek overhead — aynı bot token, farklı `chat_id`:

| Gönderen | Kanal | Mesaj türü |
|----------|-------|-----------|
| Alertmanager | `#alerts` | Metric uyarıları (CPU, disk, node down) — tek yönlü |
| Orchestrator | `#ops` | Onay gerektiren eylemler + bilgi mesajları — interaktif |

### Callback Mekanizması: Long-Polling

Orchestrator dışarıya port açmaz (WireGuard-internal). Telegram API'yi kendisi sorgular:

```python
while True:
    updates = await telegram.get_updates(offset=last_update_id)
    for update in updates:
        if update.callback_query:
            await handle_approval(update.callback_query)
    await asyncio.sleep(2)
```

### Mesaj Tipleri

```
#alerts (Alertmanager — pasif):
  🔴 node7 disk %90 — 85 GB kaldı
  🟡 node3 CPU %85
  🔴 node1 erişilemez

#ops (Orchestrator — interaktif):
  ⚠️  node7/node8 disk %85+ — node9 ekleme zamanı
  🔴  node8 ↓ — DNS'ten çıkarıldı, node7 tek başına devam ediyor
  🔴  node7 ↓ — DNS'ten çıkarıldı, node8 tek başına devam ediyor
  ✅  node8 ↑ — mc sync gerekiyor, onay sonrası DNS'e geri alınacak
  ⚠️  node7 geri döndü — mc sync tamamlandıktan sonra DNS'e geri alın
        [DNS'e Ekle]  [Ertele]
  ⚠️  pg_rewind hazır — node5 sync lag = 0
        [pg_rewind Başlat]  [Ertele]
  🚨  Storage EXHAUSTED — yeni upload'lar reddediliyor (HTTP 507)
```

---

## 15. TTL & Zamanlama Tasarımı (Taslak — Plan Aşamasında Onaylanacak)

> Tüm süreler birbiriyle tutarlı ve race condition'sız tasarlandı.  
> V1.4'teki çakışmalar giderildi. Plan oluşturulurken bu değerler gözden geçirilecek.

---

### 15.1 Auth & Session

| Key | TTL | V1.4 | Değişiklik |
|-----|-----|------|-----------|
| JWT Access Token | **15 dk** | 15 dk / 30 dk çakışıyordu | 15 dk'ya standardize |
| Refresh Token | **7 gün** | 30 gün / 7 gün çakışıyordu | 7 gün'e standardize |
| `session:user:{uid}` | **15 dk** | 15 dk | Aynı |
| `verify:{email\|phone}` | **10 dk** | 10 dk | Aynı |
| `phone_verify_token:{uid}` | **30 dk** | 30 dk | Aynı |
| `reset_pwd:{email}` | **10 dk** | 10 dk | Aynı |

---

### 15.2 Güvenlik & Rate Limit

| Key | TTL | Not |
|-----|-----|-----|
| `ip_rate:{ip}` penceresi | **60s** | Aynı |
| `ipblk:{ip}` | **10 dk** | Aynı |
| `ws_session:{...}` | **2 saat** | Aynı |
| `act_lock:{uid}:{action}` | **3s** | V1.4'te 2s — sınır ihlali riskine karşı 1s artırıldı |
| `idem:{...}` | **30s** | Aynı |
| `call_ended_sent:{call_id}` | **300s** | ⚠️ V1.4: webhook 60s / API 300s çakışıyordu — **ikisi de 300s** |

---

### 15.3 Canlı Yayın & Arama

| Key | TTL | V1.4 | Değişiklik |
|-----|-----|------|-----------|
| LiveKit token | **4 saat** | 24 saat | Azaltıldı — 24 saat gereksiz uzun |
| `live:host_reconnect:{id}` | **10 dk** | 10 dk | Aynı |
| Hype decay | **5s döngü** | 5s | Aynı |
| Call ring timeout | **20s** / backup **30s** | 15s / 25s | Artırıldı — zayıf ağda yeterli süre |
| `ws_dm_online:{uid}` | **90s** | 90s | Aynı (heartbeat ile yenilenir) |
| `call_presence:{uid}` | **10 dk** | 10 dk | Aynı |
| `stream_pos:{listener}` | **24 saat** | 24 saat | Aynı |
| `dlq:{listener}:{id}` | **7 gün** | 7 gün | Aynı |

---

### 15.4 Müzayede

| Key | TTL | V1.4 | Değişiklik |
|-----|-----|------|-----------|
| `auction:state:{id}` | **12 saat** | 24 saat | Azaltıldı — müzayedeler bu kadar sürmez |
| `auction:bidders:{id}` | **12 saat** | 24 saat | Aynı indirim |
| `bin_cooldown:{...}` | **60s** | 60s | Aynı |
| `auction_outbox:{id}` | **12 saat** | 24 saat | Tutarlılık için indirildi |

---

### 15.5 Cache

| Key | TTL | V1.4 | Değişiklik |
|-----|-----|------|-----------|
| `foryou:{uid}` | **6 saat** | 6 saat | Aynı — cron 6 saatte bir yeniler, mükemmel hizalama |
| `listing:{id}` | **7 gün** | 7 gün | Aynı — kod `listing:` prefix kullanıyor (belge `listing_cache:` yazıyordu, düzeltildi) |
| `relationship:{uid}` | **1 saat** | 1 saat | Aynı |
| `affinity:{uid}` | **15 dk** | 15 dk | Aynı |
| `campaign:{id}` | **24 saat** | 48 saat | Azaltıldı — kampanya değişiklikleri daha hızlı yansır |
| `analytics_resp:{...}` | **5 dk** | 5 dk | Aynı |
| `catalog_schema:{...}` | **24 saat** | 24 saat | Aynı |
| `feed_vec:{uid}` | **30 dk** | 30 dk | Aynı |
| `feed_hist:{uid}` | **14 gün** | 14 gün | Aynı |
| `read_cache:{...}` | **30s** | 30s | Aynı |
| `whale:{uid}:{id}` | **1 saat** | 1 saat | Aynı |

---

### 15.6 ML Model TTL (Kritik Düzeltme)

V1.4'te ALS model TTL 25 saatti — haftalık eğitimde 6 gün modelsiz kalınıyordu.

| Model | TTL | Eğitim Sıklığı | Gerekçe |
|-------|-----|---------------|---------|
| `als_model:swipe_live` | **192 saat (8 gün)** | Haftalık (Pazar 01:00) | Eğitim arasını kapsar + 1 gün tampon |
| `als_model:feed` | **192 saat (8 gün)** | Haftalık (Pazar 01:30) | Aynı |
| `item2vec_sim:{id}` | **192 saat (8 gün)** | Haftalık (Pazar 02:00) | Aynı |
| `bpr_model:{...}` | **60 saat** | Pzt/Çrş/Cum 00:30 | Eğitim arası max ~48s + tampon |
| `thompson:{...}` | **30 gün** | — | Aynı |
| `influence:{uid}` | **7 gün** | — | Aynı |

---

### 15.7 PostgreSQL Veri Yaşam Döngüsü

| Veri | Yaşam | Temizleyici |
|------|-------|------------|
| Story | **24 saat** | `cleanup_expired_stories` (her saat :01) |
| İlan aktif | **30 gün** | `deactivate_expired_listings` (05:00 UTC) |
| İlan pasif→sil | **60 gün ek** (toplam 90 gün) | `delete_expired_inactive_listings` (05:30 UTC) |
| Mesaj şifreleme | **2 yıl** | Yasal gereklilik |
| DM medya kaydı | **90 gün** | Dosya MinIO'da kalabilir, DB kaydı silinir |
| Session log | **30 gün** | — |
| Güvenlik log | **1 yıl** | — |

---

### 15.8 ClickHouse

| Parametre | Değer |
|-----------|-------|
| Flush aralığı | **30s** |
| Max batch | **5000 satır** |
| Tablo TTL | **1 yıl** (tüm tablolar) |
| Atomiklik | `pipeline(transaction=True)` — MULTI/EXEC |

---

### 15.9 Orchestrator & edge-metrics

| Parametre | Değer |
|-----------|-------|
| edge-metrics write interval | **3s** |
| `edge:metrics:{node}` TTL | **6s** (2 × interval) |
| `orch:best` TTL | **10s** |
| `orchestrator:leader` TTL | **30s** |
| Leader renew interval | **10s** |

---

### 15.10 Mobile Cache (§13 ile Tutarlı)

| Cache | TTL | Eviction |
|-------|-----|---------|
| Public medya (device) | **14 gün** | LRU, 200 MB limit |
| DM medya (device) | **30 gün** | LRU, 150 MB limit |
| Video önizleme (device) | **3 gün** | LRU, 100 MB limit |
| CF Edge cache | **7 gün** (görsel) / **1 gün** (video) | CF yönetir |

Hizalama: CF 7 gün → device 14 gün. Device cache CF'den daha uzun yaşar — CF'den düşen içerik device'da kalmaya devam eder.

---

### 15.11 ARQ Cron Takvimi (Race-Condition-Free)

**Temel kural:** Aynı dakikada iki ağır iş çalışmaz. Minimum 5 dakika aralık.

**V1.4 sorunu:** Her gece 00:00'da 4 iş aynı anda patlar. V2.0'da dağıtıldı.

#### Yüksek Frekanslı

| Görev | Zamanlama | Sıklık |
|-------|-----------|--------|
| `cleanup_stale_streams` | Her 2 dk | 30×/saat |
| `flush_interactions_to_db` | Her 5 dk (:00,:05,...) | 12×/saat |
| `cleanup_ghost_calls` | :00,:15,:30,:45 | 4×/saat |
| `sync_ad_campaigns` | :03,:18,:33,:48 | 4×/saat — :00'dan kaçırıldı |
| `invalidate_swipe_live_configs` | :07,:27,:47 | 3×/saat |
| `sync_swipelive_interests` | :13,:33,:53 | 3×/saat |

#### Saatlik

| Görev | Dakika | Not |
|-------|--------|-----|
| `cleanup_expired_stories` | :01 | :00'dan 1 dk kaçırıldı |
| `cleanup_hype_highlights` | :02 | — |
| `backfill_listing_quality_scores` | :45 | — |

#### 4× Günlük (Her 6 Saatte, Dağıtılmış)

| Görev | Saatler (UTC) |
|-------|--------------|
| `compute_user_interests` | 00:10, 06:10, 12:10, 18:10 |
| `compute_trending_categories` | 00:20, 06:20, 12:20, 18:20 |
| `compute_user_condition_preferences` | 00:30, 06:30, 12:30, 18:30 |
| `populate_foryou_feed` | 00:40, 06:40, 12:40, 18:40 |
| `compute_trending_listings` | 00:50, 06:50, 12:50, 18:50 |

#### 2× Günlük

| Görev | Saatler (UTC) |
|-------|--------------|
| `rebuild_faiss_index` | 01:00, 13:00 |

#### Günlük (UTC, Dağıtılmış)

| Görev | Saat |
|-------|------|
| `cleanup_old_stream_likes` | 01:30 |
| `compute_seller_badges` | 02:00 |
| `calculate_user_budgets` | 02:30 |
| `backfill_listing_embeddings` (1. geçiş) | 03:00 |
| `compute_trust_scores` | 03:15 |
| `cleanup_hidden_messages` | 03:30 |
| `teqlif-backup.timer` (systemd) | **02:45** — ARQ işleri arasına yerleştirildi |
| `cleanup_old_notifications` | 04:00 |
| `process_churn_and_airdrop` | 04:30 |
| `deactivate_expired_listings` | 05:00 |
| `optimize_notification_timing` | 05:15 |
| `delete_expired_inactive_listings` | 05:30 |
| `cleanup_old_impressions` | 06:00 |
| `nsfw_backfill` | 06:15 |
| `backfill_phash` | 06:30 |
| `teqlif-healthcheck.timer` (systemd) | **06:00** |
| `hesitation_retarget` | 07:00 |
| `cleanup_old_media_messages` | 07:30 |
| `backfill_listing_embeddings` (2. geçiş) | 08:00 |

#### Haftalık

| Görev | Gün + Saat (UTC) |
|-------|-----------------|
| `train_swipe_live_als` | Pazar 01:00 |
| `train_feed_als` | Pazar 01:30 |
| `train_item2vec` | Pazar 02:00 |
| `train_listing_quality_model` | Pazar 02:30 |
| `train_churn_model` | Pazartesi 02:30 |
| `train_bpr` | Pzt, Çrş, Cum 00:30 |
| `train_kmeans_cold_start` | Çrş, Paz 02:15 |
| `cleanup_old_analytics` | Pazartesi 04:00 |

#### Gece Yük Dağılımı (V1.4 vs V2.0)

```
V1.4 — 00:00 UTC'de patlama:
  compute_user_interests     00:00 ┐
  compute_trending_categories 00:00 ├── 4 ağır iş aynı anda
  rebuild_faiss_index        00:00 │
  flush_interactions         00:00 ┘

V2.0 — dağıtılmış:
  flush_interactions         00:00  (her zaman çalışır, hafif)
  compute_user_interests     00:10  ← 10 dk sonra
  compute_trending_categories 00:20  ← 10 dk sonra
  compute_user_condition_prefs 00:30
  populate_foryou_feed       00:40
  compute_trending_listings  00:50
  rebuild_faiss_index        01:00  ← tam saat sonra
```

---

### 15.12 Tutarlılık Kontrol Listesi

| Çift | Kontrol | Sonuç |
|------|---------|-------|
| ForYou TTL (6s) ↔ ForYou cron (6s) | Cron tam TTL dolumunda yeniliyor | ✅ Mükemmel hizalama |
| ALS TTL (8 gün) ↔ ALS eğitim (haftalık) | TTL > eğitim aralığı | ✅ Model her zaman Redis'te |
| BPR TTL (60s) ↔ BPR eğitim (2 günde 1) | TTL > eğitim aralığı | ✅ |
| `call_ended_sent` webhook (300s) ↔ API (300s) | Artık aynı | ✅ Race condition giderildi |
| CF cache (7 gün) ↔ Device cache (14 gün) | Device > CF | ✅ Device, CF'den düşeni tutar |
| Listing aktif (30 gün) ↔ `listing:` TTL (7 gün) | Cache < Listing ömrü | ✅ Cache expire'da tazelenecek |
| `feed:recent` ZSET ↔ max 2000 eleman | TTL yok, count-based yönetim | ✅ `invalidate_listing()` kaldırma sağlar |
| ARQ sync window (04:00-05:00) ↔ yük dağılımı | Bu pencerede ağır iş yok | ✅ MinIO sync rahat çalışır |

---



| # | Konu | Durum |
|---|------|-------|
| 7 | TTL değerleri — V1.4 TTL'leri korunacak mı, V2.0 için yeniden tasarlanacak mı? | ✅ §15 |
| 8 | Race condition analizi — V1.4'te tespit edilenler V2.0'a taşınıyor mu? | ✅ §15 |
| 9 | Backend / mobil değişiklik notları — yeni domain'ler, endpoint değişiklikleri | ✅ §16 |

---

## 16. Backend & Mobil Değişiklik Notları

### 16.1 Domain Değişiklikleri

| V1.4 | V2.0 | Rol |
|------|------|-----|
| `minio1.teqlif.com` | `uploads.teqlif.com` | S3 PUT (yükleme) — DNS Only |
| `minio4.teqlif.com` | `uploads.teqlif.com` | aynı domain, storage routing Orch Redis'e taşındı |
| `minio7.teqlif.com` | `uploads.teqlif.com` | aynı domain |
| — | `media.teqlif.com` | S3 GET (servis) — CF Proxied, cache |

**Kurallar:**
- Yükleme her zaman `uploads.teqlif.com` → backend, `orch:best:storage`'dan aktif storage node'u okur
- Public içerik URL'si: `https://media.teqlif.com/{bucket}/{key}` — sabit, CF önbelleğe alır
- DM içerik: backend pre-signed URL üretir (`uploads.teqlif.com` üzerinden) + `cache_key` döner

---

### 16.2 DM Media API Response — `cache_key` Alanı

V1.4'te mobile, pre-signed URL'yi hem fetch hem de yerel cache key olarak kullanıyordu. Pre-signed URL her istek üretiminde değişir → cache her seferinde miss oluyor.

**V2.0 çözümü:** API response'a `cache_key` (sabit S3 path) eklenir.

```json
{
  "url": "https://uploads.teqlif.com/teqlif-dm/messages/abc123.jpg?X-Amz-Signature=...",
  "cache_key": "teqlif-dm/messages/abc123.jpg",
  "expires_in": 3600,
  "content_type": "image/jpeg",
  "size_bytes": 204800
}
```

| Alan | Kullanım |
|------|---------|
| `url` | HTTP fetch için — her çağrıda yeni imza üretilir |
| `cache_key` | Yerel disk cache'de dosya adı — değişmez, persistent |
| `expires_in` | Mobil, URL'nin ne zaman yenileneceğini bilir |

---

### 16.3 Backend Değişiklikleri (FastAPI)

#### Env Değişkenleri

| Eklenecek | Kaldırılacak |
|-----------|-------------|
| `UPLOADS_HOST=https://uploads.teqlif.com` | `MINIO1_URL` |
| `MEDIA_HOST=https://media.teqlif.com` | `MINIO4_URL` |
| | `MINIO7_URL` (internal erişim için saklanabilir) |

Internal MinIO erişimi (backend → MinIO) hâlâ WireGuard IP + port üzerinden devam eder. Değişen sadece mobil'e döndürülen URL'ler.

#### Storage Node Routing

V1.4: `MINIO_URL` sabit env var → hangi node'a yazılacağı kod içinde hardcoded.

V2.0: `orch:best:storage` Orch Redis key'inden okunur → aktif storage node host'u alınır → pre-signed URL o host üzerinden üretilir.

```python
# Pseudo-code
storage_host = await orch_redis.hget("orch:best", "storage")
# storage_host = "10.10.0.7:9000" (node7) ya da "10.10.0.1:9000" (failback)
presigned = minio_client(storage_host).presigned_put_object(...)
```

#### URL Üretim Kuralı

| İçerik tipi | Döndürülen URL | Not |
|-------------|----------------|-----|
| Public medya (ilan, profil, story) | `https://media.teqlif.com/{bucket}/{key}` | Sabit, CF cache |
| DM medya (download) | Pre-signed `uploads.teqlif.com` + `cache_key` | `cache_key` sabit |
| Upload pre-signed PUT | Pre-signed `uploads.teqlif.com` | Tek kullanım |

---

### 16.4 Mobil Değişiklikleri (Flutter / api.dart)

#### Sabit Güncellemeleri

```dart
// V1.4
const kUploadsHost = 'https://minio1.teqlif.com';

// V2.0
const kUploadsHost = 'https://uploads.teqlif.com';   // PUT
const kMediaHost   = 'https://media.teqlif.com';      // GET (public)
```

`kMinio4Host`, `kMinio7Host` sabitleri kaldırılır.

#### `imgUrl()` Fonksiyonu

V1.4: `/uploads/` path'ini strip edip `kUploadsHost` ekler.

V2.0:
- Public içerik: API zaten `media.teqlif.com` URL döner → `imgUrl()` sadece pass-through
- DM içerik: `url` ve `cache_key` ayrı field olarak döner → imgUrl() çağrılmaz

#### Cache Key Kuralı

```dart
// YANLIŞ (V1.4 davranışı)
final cacheKey = message.mediaUrl;  // pre-signed URL, her seferinde değişir → cache miss

// DOĞRU (V2.0)
final cacheKey = message.mediaCacheKey;  // sabit S3 path → persistent cache
```

#### DM Logout Cache Temizleme

`dm_media` cache klasörü logout sırasında silinir (§13.4 ile tutarlı). `cache_key` path'leri bu klasörün altında saklanır.

---

## 17. Node Provisioning Mimarisi

### 17.1 Temel Prensipler

- **Tam izolasyon:** Her node'un `resources/` dizini kendi başına çalışır. Dış dependency yok.
- **Spec-driven optimizasyon:** Tüm config değerleri her node'un `specs.md` dosyasından türetilir, runtime hesaplama yapılmaz.
- **Önce dizin:** Bootstrap'ın ilk bölümü tüm dizinleri oluşturur ve izinleri ayarlar. Paket kurulumu sonra gelir.
- **`.env` şablonu:** Değerler olmadan `resources/` altında yaşar. Bootstrap ilk kurulumda `backend/.env`'e kopyalar. Yeni key eklendiğinde sadece eksik key'ler eklenir, mevcut değerler korunur.
- **Diğer config'ler:** systemd unit'leri, nginx config'leri, redis.conf, postgresql.conf vb. doğrudan `resources/` altından okunur/kopyalanır.
- **venv:** Her zaman `/var/www/teqlif.com/` altında kurulur.

### 17.2 Dizin Yapısı

```
deploy/scale/V2.0/
  {node}/
    specs.md                        # donanım spec'i (değişmez)
    resources/
      bootstrap_{node}.sh           # tek entrypoint — tamamen self-contained
      systemd/                      # systemd unit dosyaları
      nginx/                        # nginx config (gateway'lerde)
      postgresql/                   # postgresql.conf, pg_hba.conf, pgbouncer.ini (core'larda)
      redis/                        # redis-6379.conf, redis-6380.conf (core'larda)
      minio/                        # config.env (storage node'larında)
      wireguard/                    # wg0.conf.template
      sysctl/                       # teqlif.conf
      ulimits/                      # teqlif.conf
      .env.template                 # değersiz şablon
```

### 17.3 Bootstrap Çalışma Sırası

```
1. Dizinler & izinler    ← ilk adım, izin sorunu burada yakalanır
2. sysctl & ulimits      ← sistem optimizasyonu
3. apt paket kurulumu
4. Komponent config kopyala (postgresql.conf, redis.conf, nginx.conf, minio config...)
5. venv kur, pip install
6. .env.template → .env  (yoksa kopyala / varsa eksik key'leri ekle)
7. WireGuard key üret    (wg genkey → pubkey ekrana + /etc/wireguard/pubkey.txt)
8. systemd unit kopyala + enable
9. Smoke test
```

### 17.4 Donanım Özeti & Hesaplanan Optimizasyon Değerleri

**Tüm node'ların swap dahil gerçek bellek kapasitesi:**

| Node | CPU | RAM | Swap | Toplam | Disk | Ağ |
|------|-----|-----|------|--------|------|----|
| gateway1 | 2c @ 2.3GHz | 1.9 GB | 1.0 GB | 2.9 GB | 59 GB virt | ~1 Gbps |
| gateway2 | 2c @ 2.0GHz | 9.0 GB | 4.0 GB | 13.0 GB | 79 GB virt | ~4-7 Gbps |
| node1 | 6c @ 3.1GHz | 11.4 GB | 2.0 GB | 13.4 GB | 98 GB NVMe | ~2 Gbps |
| node2 | 1c @ 2.5GHz | 1.4 GB | 2.0 GB | 3.4 GB | 15 GB HDD | ~450 Mbps |
| node3 | 4c @ 2.45GHz | 3.8 GB | 4.0 GB | 7.8 GB | 49 GB NVMe | ~1 Gbps |
| node4 | 6c @ 3.1GHz | 11.4 GB | 2.0 GB | 13.4 GB | 98 GB NVMe | ~2 Gbps |
| node5 | 4c @ 2.45GHz | 7.8 GB | 8.0 GB | 15.8 GB | 49 GB NVMe | ~1 Gbps |
| node6 | 3c @ 2.0GHz | 7.7 GB | 8.0 GB | 15.7 GB | 79 GB virt | ~4 Gbps |
| node7 | 2c @ 2.2GHz | 2.9 GB | 2.0 GB | 4.9 GB | 10GB SSD + 1TB HDD | ~1 Gbps |
| node8 | 2c @ 2.2GHz | 2.9 GB | 2.0 GB (SSD) | 4.9 GB | 10GB SSD + 1TB HDD | ~1 Gbps |

**Notlar:**
- node1 = node4: birebir aynı donanım (OVH Frankfurt, 6c, 11.4GB, 2GB swap, NVMe) → config özdeş
- **node7 = node8:** birebir aynı donanım (DELUXHOST NL, 2c, 2.9GB, 2GB SSD swap, 1TB HDD) → config özdeş, symmetric dual-write
- gateway1 ≠ gateway2: aynı rol, çok farklı donanım → ayrı config zorunlu
- node5 vs node6: node6'da 1 core eksik (3 vs 4) → PostgreSQL/FastAPI config'i ayrı
- node7/node8: MinIO için RAM kritik kısıt (2.9 GB) → `GOMEMLIMIT=2GiB` zorunlu

**Hesaplanan komponent değerleri:**

| Node | Komponent | Değer | Gerekçe |
|------|-----------|-------|---------|
| gateway1 | `worker_connections` | 1024 | RAM kısıtlı (1.9 GB) |
| gateway1 | `proxy_buffers` | 8 16k | — |
| gateway1 | `vm.swappiness` | 10 | Gateway, swap güvenli kullanabilir |
| gateway2 | `worker_connections` | 4096 | 9 GB RAM + 7 Gbps ağ |
| gateway2 | `proxy_buffers` | 16 32k | — |
| gateway2 | `net.core.rmem_max` | 16777216 | 7 Gbps hatta uygun |
| node1/4 | `WEB_CONCURRENCY` | 6 | = CPU core (LiveKit SFU) |
| node1/4 | `vm.swappiness` | 1 | NVMe — swap'tan kaç |
| node2 | `WEB_CONCURRENCY` | 1 | tek core |
| node2 | `vm.swappiness` | 60 | RAM çok az (1.4GB) — swap kullanılabilir olsun |
| node3 | Prometheus retention | 15d / 20GB | 49GB disk sınırı |
| node3 | Loki retention | 168h (7 gün) | proje kararı |
| node3 | `vm.swappiness` | 10 | — |
| node5 | `shared_buffers` | 2048 MB | 25% × 7.8 GB |
| node5 | `effective_cache_size` | 5888 MB | 75% × 7.8 GB |
| node5 | `work_mem` | 48 MB | (5940MB / 100 conn / 2) |
| node5 | `maintenance_work_mem` | 512 MB | — |
| node5 | `max_connections` | 100 | PgBouncer pooling |
| node5 | `wal_buffers` | 64 MB | — |
| node5 | `random_page_cost` | 1.1 | NVMe |
| node5 | `effective_io_concurrency` | 200 | NVMe |
| node5 | `max_worker_processes` | 4 | = CPU core |
| node5 | `huge_pages` | try | — |
| node5 | Redis :6379 `maxmemory` | 2gb | Core Redis |
| node5 | Redis :6380 `maxmemory` | 512mb | Orch Redis |
| node5 | Redis :6380 `save` | `""` | in-memory only — persistence yok |
| node5 | Redis :6380 `hz` | 20 | pub/sub için yüksek tick |
| node5 | PgBouncer `pool_mode` | transaction | — |
| node5 | PgBouncer `max_client_conn` | 200 | — |
| node5 | PgBouncer `default_pool_size` | 25 | — |
| node5 | PgBouncer `max_db_connections` | 80 | max_connections - 20 |
| node5 | `WEB_CONCURRENCY` | 4 | = CPU core |
| node5 | `vm.swappiness` | 1 | — |
| node5 | `vm.overcommit_memory` | 1 | Redis zorunlu |
| node5 | `kernel.shmmax` | 4294967296 | PostgreSQL shared memory |
| node5 | `net.core.somaxconn` | 65535 | — |
| node6 | `shared_buffers` | 1920 MB | 25% × 7.7 GB |
| node6 | `effective_cache_size` | 5760 MB | 75% × 7.7 GB |
| node6 | `max_worker_processes` | 3 | = CPU core |
| node6 | `max_parallel_workers` | 3 | — |
| node6 | `hot_standby` | on | replica modu |
| node6 | `hot_standby_feedback` | on | — |
| node6 | Redis :6379 | `replicaof 10.10.0.11 6379` | VIP üzerinden |
| node6 | Redis :6380 | `replicaof 10.10.0.11 6380` | — |
| node6 | `WEB_CONCURRENCY` | 3 | = CPU core |
| node7 | `GOMEMLIMIT` | 2GiB | 2.9GB RAM — OOM koruması |
| node7 | `MINIO_API_REQUESTS_MAX` | 200 | HDD bottleneck |
| node7 | `MINIO_API_REQUESTS_DEADLINE` | 30s | HDD yavaş |
| node7 | HDD scheduler | mq-deadline | /dev/vdb için udev rule |
| node7 | `read_ahead_kb` | 2048 | sequential okuma iyileşir |
| node7 | `vm.swappiness` | 1 | — |
| node7 | `vm.vfs_cache_pressure` | 50 | dentry/inode cache koru — küçük dosyalarda kritik |
| node8 | `GOMEMLIMIT` | 2GiB | node7 ile aynı (2.9 GB RAM) |
| node8 | `GOGC` | 100 | node7 ile aynı |
| node8 | `MINIO_API_REQUESTS_MAX` | 200 | node7 ile aynı |
| node8 | `MINIO_API_REQUESTS_DEADLINE` | 30s | HDD yavaş |
| node8 | HDD scheduler | mq-deadline | /dev/vdb için udev rule |
| node8 | `vm.swappiness` | 1 | node7 ile aynı |
| node8 | `vm.vfs_cache_pressure` | 50 | node7 ile aynı |

---

## 18. Kod Tutarlılık Analizi (Backend & Mobil)

> Mevcut V1.4 kodu incelendi. Aşağıdaki bulgular V2.0'da ele alınmadan sistem çalışmaz ya da tutarsız davranır.

---

### 18.1 `storage_service.py` — Kritik, Baştan Yazılacak

**Sorun 1 — `_build_public_url` V2.0 ile tamamen uyumsuz:**

```python
# V1.4 — kırık
def _build_public_url(node_id: str, bucket: str, key: str) -> str:
    domain = node_id.replace("live", "minio")
    return f"http://{domain}:9010/{bucket}/{key}"
    # Üretilen: http://minio1.teqlif.com:9010/teqlif/stories/foo.jpg
```

V2.0'da public URL: `https://media.teqlif.com/{bucket}/{key}` (node adı yok, port yok).
DM upload sonucu DB'ye yazılan URL de bu pattern — V2.0'da node domain'i artık yok.

**Sorun 2 — `_get_client_from_public_url` routing kırık:**

```python
# V1.4 — URL'den node_id türetiyor
expected_nid = domain.replace("minio", "live")  # minio1 → live1
```

V2.0'da URL `media.teqlif.com` — domain'den node türetilemez. Delete, presign operasyonları için doğru MinIO node'u bulunamaz.

**Sorun 3 — Delete routing çözülmeli:**

V2.0'da bir nesneyi silmek için hangi node'da olduğunu bilmek gerekiyor. İki seçenek:

| Yaklaşım | Açıklama | Tercih |
|----------|----------|--------|
| A) DB'de `storage_node_id` kolonu | Upload sırasında `node7` kaydedilir, delete sırasında doğrudan o node'a gidilir | ✅ |
| B) Tüm node'larda dene | node7'de yoksa node1'de dene | ❌ Yavaş, kötü pattern |

**Karar (plan aşamasında onaylanacak):** DB'deki media kayıtlarına `storage_node_id` kolonu eklenir. `upload_bytes()` ve `upload_file_dm()` bu değeri döner. `delete_object()` bu değerden doğrudan node'a gider.

**Sorun 4 — DM upload sonucu yanlış:**

`upload_file_dm()` şu an `_build_public_url()` döndürüyor — DM bucket public erişilebilir değil. DB'ye yazılan değer key olmalı, URL değil. `presign_get()` her seferinde key'den URL üretmeli.

---

### 18.2 Mobile — `TeqlifCacheManager` TTL Uyumsuzluğu

`image_cache_manager.dart`:
```dart
stalePeriod: const Duration(days: 2),   // §15 kararı: 14 gün
maxNrOfCacheObjects: 300,               // byte-based limit yok
```

§15.10'da kararlaştırılan:

| Cache | Karar | Mevcut | Fark |
|-------|-------|--------|------|
| Public medya | 14 gün, 200 MB | 2 gün, 300 dosya (byte limit yok) | ❌ |
| DM medya | 30 gün, 150 MB | Yok | ❌ |
| Video önizleme | 3 gün, 100 MB | Temp dir (OS temizler) | ❌ |

`flutter_cache_manager` paketi byte-based limit desteklemez — ya özel implementasyon ya da ek paket gerekir. Plan aşamasında kararlaştırılacak.

`VideoCacheManager` `getTemporaryDirectory()` kullanıyor — OS istediğinde siliyor. DM video cache'i için `getApplicationSupportDirectory()` kullanılmalı.

---

### 18.3 Mobile — DM Cache Temizleme Mevcut Değil

§13.4 kararı: logout sırasında DM medya cache silinir.
Mevcut `auth_service.dart` ya da `logout` akışında bu yok. Plan aşamasında eklenmeli.

---

### 18.4 Mobile — `cache_key` Alanı Yok

`messages_screen.dart` DM medyasını `msg['media_url']` üzerinden erişiyor:
```dart
final mediaUrl = msg['media_url'] as String?;
// Bu pre-signed URL — her istek üretiminde değişir
// Bugün cache key olarak kullanılamaz
```

§16.2'de kararlaştırılan `cache_key` alanı:
- Backend: `GetMessagesQuery._presign_if_dm()` hem `url` (pre-signed) hem `cache_key` (sabit S3 path) döndürmeli
- Backend schema: `MessageOut.cache_key: Optional[str]`
- Mobil: `msg['media_cache_key']` dosya sistemi key'i olarak kullanılmalı

---

### 18.5 Mobile — `dart_defines` Eksik Sabitler

`dart_defines/release.json` şu an:
```json
{ "BASE_HOST": "https://api.teqlif.com" }
```

V2.0'da gerekli:
```json
{
  "BASE_HOST": "https://api.teqlif.com",
  "UPLOADS_HOST": "https://uploads.teqlif.com",
  "MEDIA_HOST": "https://media.teqlif.com"
}
```

`AppConfig.mediaBaseUrl` şu an `api.teqlif.com` → `www.teqlif.com` olarak türetiliyor, pratikte kullanılmıyor (tüm URL'ler API'den absolute döndüğü için). V2.0'da `MEDIA_HOST` dart-define'dan alınmalı.

---

### 18.6 Backend — Upload Akışı Büyük Dosyalarda Çift Bant Genişliği

Mevcut akış:
```
Mobil → (50 MB video) → api.teqlif.com (FastAPI) → MinIO node
```
FastAPI hem alıyor hem tekrar gönderiyor → upload node'unda 2× bant genişliği tüketimi.

V2.0 için **opsiyonel** optimizasyon:
```
Mobil → GET /upload/presign-put → pre-signed PUT URL
Mobil → (50 MB video) → uploads.teqlif.com (doğrudan MinIO)
Mobil → POST /upload/confirm → backend kayıt oluştur
```
Büyük dosyalar (>5 MB) için doğrudan MinIO upload. Plan aşamasında değerlendirilecek.

---

### 18.7 Mobile — Offline Queue Sadece Text Destekliyor

`offline_queue_service.dart` yalnızca text DM kuyruğa alıyor:
```dart
static Future<String> enqueue(int receiverId, String content, ...)
// Media mesajlar offline kuyruklanmıyor — sessizce başarısız olur
```

V2.0'da değişmeyecek (kapsam dışı), ama bilgi olarak not edildi.

---

### 18.8 Share URL & Deep Link Analizi

#### Mevcut Share URL'leri

| Kullanım | URL | Dosya |
|----------|-----|-------|
| İlan paylaş | `https://www.teqlif.com/ilan/$id` | listing_detail_screen.dart:1257 |
| Profil paylaş | `https://www.teqlif.com/profil/$username` | public_profile_screen.dart:206 |
| Canlı yayın paylaş | `https://www.teqlif.com/yayin/$streamId` | viewer_top_bar.dart:127 |
| Destek | `https://www.teqlif.com/support.html` | profile_screen.dart:2122 |
| KVK | `https://www.teqlif.com/kullanim-sartlari.html` | profile_screen.dart:2143 |
| Gizlilik | `https://www.teqlif.com/gizlilik-politikasi` | profile_screen.dart:2155 |
| Pro plan | `https://www.teqlif.com/pro-plan.html` | pro_hub_screen.dart |
| CAPTCHA baseUrl | `https://www.teqlif.com` | captcha_service.dart:16 |

#### V2.0 Uyumluluk Durumu

**✅ Share URL'leri — V2.0 uyumlu**
V2.0'da `www.teqlif.com` gateway tarafından serve edilmeye devam ediyor. Tüm share URL'leri geçerli.

**✅ Universal Links (iOS AASA) — V2.0 uyumlu**
`frontend/.well-known/apple-app-site-association` kayıtlı path'ler:
```
/invite*  /ilan/*  /profil/*  /yayin/*
```
CF Multi-A yapısında Apple, `www.teqlif.com` üzerinden AASA'ya erişir — gateway1 veya gateway2 herhangi biri yanıt verebilir. Frontend her iki gateway'e de deploy edildiği sürece sorun yok. **Her iki gateway'de frontend dosyaları aynı olmalı** — deploy adımında not edilecek.

**❌ Android `assetlinks.json` — MEVCUT DEĞİL**
`frontend/.well-known/assetlinks.json` dosyası yok. Android App Links (universal link) çalışmıyor — yalnızca custom scheme (`teqlif://`) devrede. V2.0 öncesi mevcut sorun, V2.0'da düzeltilmeli.

**⚠️ Share URL'leri `AppConfig` kullanmıyor — staging tutarsızlığı**
`listing_detail_screen.dart` gibi tüm share URL'leri `'https://www.teqlif.com/...'` hardcoded. Staging build'da share edilen linkler `www.teqlif.com`'a açılır (prod), `staging.teqlif.com`'a değil.

Düzeltme: Share URL base'ini `AppConfig.mediaBaseUrl` (zaten `www.teqlif.com` / `staging.teqlif.com` döndürüyor) üzerinden oluşturmak. Öncelik: düşük.

**✅ Deep link regex — V2.0 uyumlu**
```dart
r'(https?://[^\s]+/ilan/(\d+)|teqlif://auction/(\d+)|teqlif://direct-sale/(\d+))'
```
Domain değişmediği için çalışmaya devam eder.

**✅ CAPTCHA — V2.0 uyumlu**
`captcha_service.dart` hardcoded `https://www.teqlif.com` baseUrl kullanıyor. Turnstile site key bu domain'e kayıtlı — V2.0'da domain değişmiyor, sorun yok.

---

### 18.9 Generic Config & Staging İzolasyonu

**Prensip:** Her URL, IP, dizin, bucket adı doğrudan config değeridir. Başka bir değerden türetilmez. Aynı binary, farklı `.env` / `dart_defines` ile staging veya prod olarak çalışır — veri karışması imkânsız.

#### dart_defines — Tam İzole

```json
// dart_defines/staging.json
{
  "BASE_HOST":        "https://api-staging.teqlif.com",
  "UPLOADS_HOST":     "https://uploads-staging.teqlif.com",
  "MEDIA_HOST":       "https://media-staging.teqlif.com",
  "SHARE_BASE_URL":   "https://staging.teqlif.com",
  "CAPTCHA_BASE_URL": "https://staging.teqlif.com"
}

// dart_defines/release.json
{
  "BASE_HOST":        "https://api.teqlif.com",
  "UPLOADS_HOST":     "https://uploads.teqlif.com",
  "MEDIA_HOST":       "https://media.teqlif.com",
  "SHARE_BASE_URL":   "https://www.teqlif.com",
  "CAPTCHA_BASE_URL": "https://www.teqlif.com"
}
```

#### AppConfig — Türetme Yok

```dart
// V1.4 — kırılgan türetme (kaldırılacak)
String mediaHost = host.replaceAll('api-staging.', 'staging.').replaceAll('api.', 'www.');

// V2.0 — doğrudan oku
class AppConfig {
  final String baseHost;
  final String baseUrl;
  final String uploadsHost;    // S3 PUT
  final String mediaHost;      // S3 GET (CF cache)
  final String shareBaseUrl;
  final String captchaBaseUrl;

  factory AppConfig.fromEnvironment() {
    const baseHost       = String.fromEnvironment('BASE_HOST');
    const uploadsHost    = String.fromEnvironment('UPLOADS_HOST');
    const mediaHost      = String.fromEnvironment('MEDIA_HOST');
    const shareBaseUrl   = String.fromEnvironment('SHARE_BASE_URL');
    const captchaBaseUrl = String.fromEnvironment('CAPTCHA_BASE_URL');
    if (baseHost.isEmpty) throw AssertionError('BASE_HOST is not defined!');
    return AppConfig._(
      baseHost: baseHost, baseUrl: '$baseHost/api',
      uploadsHost: uploadsHost, mediaHost: mediaHost,
      shareBaseUrl: shareBaseUrl, captchaBaseUrl: captchaBaseUrl,
    );
  }
}
```

#### Share URL'leri — Config'den

```dart
// V1.4 — hardcoded (14 noktada)
url: 'https://www.teqlif.com/ilan/$id'

// V2.0
url: '${ref.read(appConfigProvider).shareBaseUrl}/ilan/$id'
```

Aynı değişiklik: `/profil/$username`, `/yayin/$streamId`, `pro-plan.html`, `support.html`, `kullanim-sartlari.html`, `gizlilik-politikasi` — hepsi `shareBaseUrl` üzerinden.

#### CaptchaService — Config'den

```dart
// V1.4 — hardcoded const
static const String _baseUrl = 'https://www.teqlif.com';

// V2.0 — AppConfig'den
// CaptchaService static olmaktan çıkar, AppConfig inject edilir
final String _baseUrl; // = appConfig.captchaBaseUrl
```

#### Backend config.py — Eklencek Alanlar

```python
# V2.0'da eklenecek — default değer YOK, .env'de tanımlı olmazsa boot validation patlar
media_host: str = ""      # https://media.teqlif.com          | https://media-staging.teqlif.com
uploads_host: str = ""    # https://uploads.teqlif.com         | https://uploads-staging.teqlif.com
minio_bucket: str = ""    # teqlif                             | teqlif-staging
minio_dm_bucket: str = "" # teqlif-dm                          | teqlif-dm-staging
```

Mevcut hardcoded default'lar (`minio_bucket: str = "teqlif"`) kaldırılır.

#### storage_service.py — Generic URL Üretimi

```python
# V1.4 — node_id'den domain türetme (kaldırılacak)
def _build_public_url(node_id: str, bucket: str, key: str) -> str:
    domain = node_id.replace("live", "minio")           # live1 → minio1.teqlif.com
    return f"http://{domain}:9010/{bucket}/{key}"

# V2.0 — doğrudan config
def _build_public_url(bucket: str, key: str) -> str:
    return f"{settings.media_host}/{bucket}/{key}"
    # Staging: https://media-staging.teqlif.com/teqlif-staging/key
    # Prod:    https://media.teqlif.com/teqlif/key
```

#### Tek Node'da Staging + Prod Çalışması

node3 hem staging hem de başka bir şey çalıştırsa — aynı binary, farklı `.env`:

```
/var/www/teqlif.com/backend/.env.production  → MINIO_BUCKET=teqlif,        MEDIA_HOST=https://media.teqlif.com
/var/www/teqlif.com/backend/.env.staging     → MINIO_BUCKET=teqlif-staging, MEDIA_HOST=https://media-staging.teqlif.com
```

`TEQLIF_ENV_FILE` env değişkeni hangi dosyanın yükleneceğini belirler — `config.py`'da zaten bu mekanizma mevcut.

---

### 18.12 `edge_orchestrator.py` — V1.4 Kaldırılıyor, Yerini Ayrı Servis Alıyor

**Mevcut durum (V1.4):**
- FastAPI içinde gömülü `EdgeOrchestrator` sınıfı
- `settings.edge_livekit_urls` ve `settings.edge_minio_urls` static config listelerinden çalışıyor
- `get_redis()` (Core Redis 6379) üzerinden `edge:metrics:*` key'lerini okuyor
- `edge-metrics-agent` `CORE_REDIS_URL` env değişkeniyle aynı Core Redis'e metric yazıyor

**V2.0'daki durum:**
- `edge_orchestrator.py` tüm dosya silinir
- `teqlif-orchestrator` ayrı systemd servisi bu görevi üstlenir
- Metriklerin **Orch Redis** (6380) üzerinden akması gerekiyor — Core Redis kirletilmemeli
- `edge-metrics-agent` env değişkeni: `CORE_REDIS_URL` → `ORCH_REDIS_URL`

**config.py'den kaldırılacaklar:**
```python
# V1.4 — silinecek
edge_livekit_urls: str | list[str] = []
edge_minio_urls: str | list[str] = []
minio_storage_quota_percent: int = 80
edge_metrics_interval_sec: int = 3
```

---

### 18.13 `orch_redis_url` — config.py ve redis_client.py'de Eksik

**§10 kararı:** FastAPI, teqlif-orchestrator ile doğrudan konuşmaz. Orchestrator Orch Redis'e yazar, FastAPI okur. Ama:

- `config.py`'de `orch_redis_url` alanı yok
- `redis_client.py`'de `get_orch_redis()` client yok
- FastAPI şu an `get_redis()` (Core Redis 6379) üzerinden Orchestrator çıktılarını okuyamaz

**V2.0'da eklenmesi gerekenler:**

```python
# config.py
orch_redis_url: str = ""  # redis://:<pass>@10.10.0.11:6380/0 (Orch Redis VIP)
```

```python
# redis_client.py
_orch_redis: aioredis.Redis | None = None

async def get_orch_redis() -> aioredis.Redis:
    global _orch_redis
    if _orch_redis is None:
        _orch_redis = aioredis.from_url(
            settings.orch_redis_url, decode_responses=True, max_connections=20
        )
    return _orch_redis
```

FastAPI'nin node seçimi yapan tüm noktaları `get_orch_redis()` kullanacak.

---

### 18.14 `--forwarded-allow-ips` — gateway2 Eksik

**teqlif.service içindeki mevcut değer:**
```
--forwarded-allow-ips 10.10.0.2
```

V2.0'da gateway2 de trafik gönderiyor (`10.10.0.9`). gateway2 üzerinden gelen isteklerde uvicorn X-Forwarded-For header'ına güvenmez → gerçek istemci IP'si görünmez → IP bazlı rate limiting ve log kayıtları bozulur.

**V2.0 düzeltmesi:**
```
--forwarded-allow-ips 10.10.0.2,10.10.0.9
```

---

### 18.15 VIP: `REDIS_URL` ve `DATABASE_URL` Şablonlarda Direkt IP Kullanıyor

**V1.4 şablon (node5):**
```bash
REDIS_URL="redis://:<pass>@10.10.0.5:6379/0"   # node5 direkt IP
DATABASE_URL=                                    # boş, elle doldurulacak
USE_PGBOUNCER=False
```

**V2.0 problemi:**
- Failover sırasında node6 primary olduğunda `10.10.0.5:6379` artık yanıt vermez
- Bağlantı havuzundaki tüm bağlantılar kesilir — uygulama restart olmadan toparlanamaz
- PgBouncer da benzer şekilde etkilenir

**V2.0 şablon olması gereken:**
```bash
REDIS_URL="redis://:<pass>@10.10.0.10:6379/0"   # Core Redis VIP
ORCH_REDIS_URL="redis://:<pass>@10.10.0.11:6380/0"  # Orch Redis VIP (yeni)
DATABASE_URL="postgresql+asyncpg://<user>:<pass>@10.10.0.10:5432/<db>"  # PgBouncer VIP
USE_PGBOUNCER=True
```

Keepalived VIP'leri failover sonrası otomatik taşınır — bağlantılar VIP üzerinden kurulduğundan kısa bir kesintiden sonra yeniden çalışır.

---

### 18.16 `site_url` — Hardcoded Default Kaldırılmalı

**config.py mevcut:**
```python
site_url: str = "https://www.teqlif.com"
```

Staging ortamında `.env` dosyasına `SITE_URL` yazılmazsa staging backend `www.teqlif.com`'u işaret eder — captcha ve diğer site-referanslı işlemler proddan etkilenir.

**V2.0 düzeltmesi:**
```python
site_url: str = ""  # .env'de zorunlu — boş bırakılırsa startup validation'da patlar
```

---

### 18.17 Backup: node5'ten node6'ya Taşınmalı

**V1.4 node5 şablonunda:**
```bash
BACKUP_REMOTE_HOST=10.10.0.4  # node3
```

**V2.0 problemi:** Backup primary node'da çalışmamalı — replica (standby) üzerinden alınmalı. Büyük dump'lar sırasında production DB'ye I/O baskısı yapar.

**V2.0 değişikliği:**
- `teqlif-backup.timer` + `teqlif-backup.service` → node6'da aktif
- node5'in `.env` şablonunda backup config bölümü yok
- node6'nın `.env` şablonuna eklenir:
```bash
BACKUP_REMOTE_HOST=10.10.0.4  # node3
BACKUP_REMOTE_USER=tucibeyin
BACKUP_REMOTE_PATH=/var/backups/teqlif
BACKUP_RETENTION_LOCAL_DAYS=2
BACKUP_RETENTION_REMOTE_DAYS=7
```

---

### 18.18 WebSocket Failover Davranışı — Mevcut Kod Yeterli

Keepalived failover süresi ~3s. `ws_service.dart` içindeki `_scheduleReconnect()` varsayılan 3s gecikmeyle yeniden bağlanır. Toplam kullanıcı kesintisi ~6–10s — kabul edilebilir. Kod değişikliği gerektirmiyor.

---

### 18.19 ClickHouse Standby Davranışı — Mevcut Kod Yeterli

node6 standby'da `clickhouse-server` çalışmıyor. `init_clickhouse()` hata verirse `_client = None` atanıyor, tüm sonraki çağrılar circuit breaker üzerinden sessizce atlanıyor. ARQ worker'ları zaten standby'da çalışmıyor — yazma denemesi de yok. Kod değişikliği gerektirmiyor.

---

### 18.20 `edge_metrics_agent.py` — Hash Tipi Uyumsuzluğu ve Eksik Alanlar

**Sorun 1 — Veri tipi:** §11.1'de `edge:metrics:{node_id}` **Hash** olarak tanımlandı. Ancak mevcut agent JSON String olarak yazıyor:

```python
# V1.4 — JSON String (yanlış)
r.set(redis_key, json.dumps(metrics), ex=ttl)

# V2.0 — Hash olmalı
r.hset(redis_key, mapping=metrics_dict)
r.expire(redis_key, ttl)
```

Orchestrator Hash field'larını `HGET edge:metrics:node7 disk_percent` ile okuyacak; JSON string olarak yazılmışsa parse edilemez.

**Sorun 2 — Eksik alanlar:** Mevcut agent yalnızca şunları yazıyor:
`cpu_percent`, `ram_percent`, `disk_percent`, `net_bytes_sent`, `net_bytes_recv`, `livekit_url`, `minio_url`

§11.1 şemasının gerektirdiği ek alanlar:

| Eksik Alan | Kaynak | Orchestrator Kullanımı |
|-----------|--------|----------------------|
| `cpu_cores` | `psutil.cpu_count()` | Oran normalize etmek için |
| `load_1m`, `load_5m` | `psutil.getloadavg()` | CPU spike tespiti |
| `ram_total_gb`, `ram_used_gb`, `ram_free_gb` | `psutil.virtual_memory()` | Bellek baskısı tespiti |
| `swap_used_gb` | `psutil.swap_memory()` | Swap baskısı |
| `disk_total_gb`, `disk_used_gb`, `disk_free_gb` | `psutil.disk_usage(DATA_DISK_PATH)` | Kapasite yönetimi |
| `net_out_mbps`, `net_in_mbps` | delta hesap | Bant genişliği kullanımı |
| `net_out_percent` | `(out_mbps / interface_speed) × 100` | **Stream node seçim metriği** |
| `interface_speed_mbps` | `.env`'den: `INTERFACE_SPEED_MBPS` | node1/4=2000, diğerleri=1000 |
| `primary_role` | `.env`'den: `NODE_ROLE` | Orchestrator için node tipi |
| `capabilities` | `.env`'den: `NODE_CAPABILITIES` | Aktif yetenekler listesi |
| `wg_ip` | WireGuard interface'den | Routing doğrulaması |
| `timestamp` | `time.time()` | Zaten var ✅ |

`livekit_url` ve `minio_url` alanları kaldırılır — V2.0'da node routing statik config (nodes.yaml) üzerinden.

**`DATA_DISK_PATH` env değişkeni node tipine göre:**
```bash
# node7, node8
DATA_DISK_PATH=/mnt/data

# node1, node4 — artık storage yok; `/` kullanılabilir ama metrics irrelevant
DATA_DISK_PATH=/
```

Agent V2.0 için baştan yazılacak (plan §Faz 0 kapsamı).

---

### 18.21 `listing_cache_service.py` — Prefix Tutarsızlığı ve `feed:recent` TTL Eksikliği

**Sorun 1 — Prefix tutarsızlığı:** Kod `listing:` prefix'i kullanıyor, §15.5'te `listing_cache:{id}` belgelenmiş.

```python
# Kod (listing_cache_service.py)
LISTING_CACHE_PREFIX = "listing:"       # → "listing:123"

# §15.5 TTL tablosu
# listing_cache:{id}  |  7 gün
```

Her iki kayıt da Core Redis'te aynı TTL ile aynı veriyi tutuyor — işlevsel fark yok, ama belgeler güncellenmeli. §15.5'teki `listing_cache:{id}` kaydı `listing:{id}` olarak düzeltilecek.

**Sorun 2 — `feed:recent` ZSET TTL yok ve TTL tablosunda tanımsız:**

```python
# listing_cache_service.py
await redis.zadd("feed:recent", {str(listing.id): score})
# TTL set edilmiyor — key kalıcı (Core Redis'te)
```

Core Redis `allkeys-lru` eviction politikasıyla çalışmadığı için (`maxmemory-policy noeviction` veya benzer) bu ZSET hiçbir zaman temizlenmez. Max 2000 eleman koruması var ama **zaman bazlı eviction yok**.

Kapasite etkisi: 2000 integer entry ≈ ~50 KB — RAM için önemsiz. Ancak pasife alınan/silinen ilanların ID'leri bu ZSET'te kalır — `invalidate_listing()` çağrısı olmadan temiz çıkarılmaları garanti değil.

**§15 eklentisi gerekiyor:** `feed:recent` ZSET TTL tablosuna eklenecek:

| Key | TTL | Not |
|-----|-----|-----|
| `feed:recent` ZSET | **TTL yok** — max 2000 eleman, `zremrangebyrank` ile yönetilir | Pasif ilanlar `invalidate_listing()` ile kaldırılır |

---

### 18.11 Tutarlılık Özeti

| # | Konu | Etki | Plan'da |
|---|------|------|---------|
| 1 | `storage_service.py` baştan yazılacak | Kritik — yeni URL şeması çalışmaz | ✅ |
| 2 | Delete routing için `storage_node_id` DB kolonu | Kritik — media silinemez | ✅ |
| 3 | DM upload: key döndür, URL değil | Kritik — presign bozulur | ✅ |
| 4 | `edge_orchestrator.py` silinecek + yeni `orch_redis_url` / `get_orch_redis()` | Kritik — Orchestrator iletişimi çalışmaz | ✅ |
| 5 | `REDIS_URL` ve `DATABASE_URL` VIP'e taşınmalı | Kritik — failover sonrası uygulama toparlanamaz | ✅ |
| 6 | `--forwarded-allow-ips` gateway2 eksik | Önemli — IP-based rate limiting bozuk | ✅ |
| 7 | `edge-metrics-agent` `ORCH_REDIS_URL` kullanmalı | Önemli — metrikler yanlış Redis'te | ✅ |
| 8 | Backup node6'ya taşınmalı | Önemli — primary DB'ye yük bindiriyor | ✅ |
| 9 | `site_url` hardcoded default kaldırılmalı | Orta — staging/prod karışıklığı | ✅ |
| 10 | `USE_PGBOUNCER=True` şablonda | Orta — V2.0 PgBouncer kullanıyor | ✅ |
| 11 | `TeqlifCacheManager` TTL & boyut | Önemli | ✅ |
| 12 | `VideoCacheManager` persistent dir | Önemli — DM video kaybolur | ✅ |
| 13 | DM logout cache temizle | Orta — gizlilik riski | ✅ |
| 14 | `cache_key` alanı (backend + mobil) | Önemli — DM cache çalışmaz | ✅ |
| 15 | `dart_defines` + `AppConfig` güncelle | Düşük — URL'ler zaten absolute | ✅ |
| 16 | Android `assetlinks.json` eksik | Orta — Android App Links çalışmıyor | ✅ |
| 17 | Share URL base hardcoded — staging tutarsızlığı | Düşük | ✅ |
| 18 | AASA her iki gateway'de erişilebilir olmalı | Deploy notu | ✅ |
| 19 | Direct-to-MinIO upload (opsiyonel) | Optimizasyon | Sonra |
| 20 | Offline media queue | Bilgi notu | Kapsam dışı |
| 21 | `edge_metrics_agent.py` Hash tipi + eksik 12 alan | Kritik — Orchestrator metrik okuyamaz | ✅ |
| 22 | `listing:` prefix belgelerde `listing_cache:` olarak yanlış | Belge düzeltmesi | ✅ |
| 23 | `feed:recent` TTL tablosunda tanımsız | Düşük — max 2000 eleman yeterli | ✅ |

---

## 19. Operasyon Komutları — `teqlif-restart` / `teqlif-refresh`

> Her node'da `/usr/local/sbin/` altında kurulu iki komut. Node rolü ve aktif/pasif durumu runtime'da tespit edilir — statik flag yok.

---

### 19.1 Komut Ayrımı

| Komut | Ne zaman kullanılır | Downtime |
|-------|---------------------|----------|
| `teqlif-restart` | Yeni kod deploy edilecek (git pull + servis restart) | Kısa (~5–30s arası) |
| `teqlif-refresh` | Kod değişikliği yok, sadece servisleri yeniden başlat | Kısa (~5s) |

**teqlif-restart** = git pull → pre-start hooks (alembic, sync_translations) → servis restart → durum tablosu

**teqlif-refresh** = git pull yok → sadece uygulama katmanı restart → veri servisleri (PG, Redis, MinIO, ClickHouse) dokunulmaz → durum tablosu

---

### 19.2 Node Rolü Tespiti

Script her çalıştığında iki şeyi dinamik olarak tespit eder:

**1. Node tipi** — WireGuard IP'sinden:
```bash
wg_ip=$(ip -4 addr show wg0 | grep -oP '(?<=inet\s)10\.10\.0\.\d+')
# 10.10.0.2/9  → gateway  | 10.10.0.1/6 → stream  | 10.10.0.5/7 → core
# 10.10.0.3    → ai_proxy | 10.10.0.4   → monitor  | 10.10.0.8/12 → storage
```

**2. Core node aktif/pasif durumu** — PostgreSQL'den:
```bash
IS_PRIMARY=$(psql -h 127.0.0.1 -U postgres -t -c \
  "SELECT NOT pg_is_in_recovery();" | tr -d ' \n')
# t → primary (aktif)   f → replica (pasif/standby)
```

Bu yaklaşımın faydası: failover sonrası node6 primary olduğunda `IS_PRIMARY=t` döner, script kendiliğinden tam restart davranışına geçer — node.conf değiştirmek gerekmez.

---

### 19.3 Node Başına Davranış Tablosu

#### gateway1 / gateway2

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | git pull → `systemctl restart nginx` |
| `teqlif-refresh` | `nginx -s reload` (sıfır kesinti, config reload) |

#### node5 / node6 — Primary (IS_PRIMARY=true)

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | git pull → `alembic upgrade head` → `sync_translations.py` → `systemctl restart teqlif` (teqlif-worker + teqlif-worker-critical BindsTo ile otomatik gelir) |
| `teqlif-refresh` | `systemctl restart teqlif` (workers BindsTo ile otomatik gelir) |

> **BindsTo davranışı:** `teqlif-worker` ve `teqlif-worker-critical` servislerinde `BindsTo=teqlif.service` tanımlı. `teqlif` restart edildiğinde her iki worker otomatik olarak yeniden başlar — ayrıca restart komutuna gerek yok.

> **Worker graceful shutdown:** `teqlif-worker-critical` için `TimeoutStopSec=600s` — uçuşta push bildirimi, outbid işlemleri var. Stop sinyali gelince ARQ SIGTERM alır, çalışan task'lar tamamlanmaya çalışır. Refresh bu süreyi bekler.

#### node5 / node6 — Standby (IS_PRIMARY=false)

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | git pull → alembic ATLA (replica read-only) → servis başlatma YOK → `"STANDBY — kod güncellendi, failover sonrası alembic + servisler çalışacak"` |
| `teqlif-refresh` | `"Bu node standby modunda, aktif değil"` uyarısı → çık |

#### node2 — AI Proxy

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | git pull → `systemctl restart teqlif-ai-proxy` |
| `teqlif-refresh` | `systemctl restart teqlif-ai-proxy` |

#### node3 — Monitor + Staging

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | git pull → `systemctl restart teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging teqlif-ai-proxy` → monitoring stack restart (prometheus, loki, grafana, alertmanager) |
| `teqlif-refresh` | `systemctl restart teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging` — monitoring stack **dokunulmaz** (sistem kör kalmasın) |

#### node1 / node4 — Stream

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | `systemctl restart livekit edge-metrics-agent` — git pull YOK (bu node'da backend kodu yok) |
| `teqlif-refresh` | `systemctl restart edge-metrics-agent` — LiveKit canlı bağlantılar var, restart dikkatli |

> **Not:** LiveKit aktif stream varken restart edilmemeli — `teqlif-restart` öncesi Orchestrator bu node'a yeni stream göndermemeye başlar. V2.0 plan aşamasında koordinasyon mekanizması netleşecek.

#### node7 — Storage #1 (1TB HDD)

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | `systemctl restart minio` — git pull yok (MinIO binary, repo'da değil) |
| `teqlif-refresh` | `systemctl restart minio` (aynı — MinIO için reload/restart ayrımı anlamsız) |

#### node8 — Storage #2 (1TB HDD — node7 ile identical)

| Komut | Adımlar |
|-------|---------|
| `teqlif-restart` | `systemctl restart minio edge-metrics-agent promtail` — git pull yok |
| `teqlif-refresh` | `systemctl restart minio edge-metrics-agent` — promtail dokunulmaz |

---

### 19.4 Durum Tablosu (Her İki Komut Sonrası)

Her iki komut da bitişte V1.4'teki servis durum tablosunu gösterir:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  node5  ·  CORE #1 (PRIMARY)  ·  2026-09-26 03:15:00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SERVİS                           DURUM        PID    RAM       UPTIME
  ─────────────────────────────────────────────────────────────
  postgresql                       ● ACTIVE      1234   180 MB    00m 12s
  pgbouncer                        ● ACTIVE      1235   12 MB     00m 11s
  redis-6379                       ● ACTIVE      1236   95 MB     00m 10s
  redis-6380                       ● ACTIVE      1237   48 MB     00m 10s
  clickhouse-server                ● ACTIVE      1238   420 MB    00m 09s
  teqlif                           ● ACTIVE      1240   310 MB    00m 08s
  teqlif-worker                    ● ACTIVE      1241   180 MB    00m 07s
  teqlif-worker-critical           ● ACTIVE      1242   95 MB     00m 06s
```

---

### 19.5 node.conf — Her Node'un Kendi Tanımı

`/etc/teqlif/node.conf` bootstrap tarafından oluşturulur, script tarafından okunur. `IS_PRIMARY` yok — runtime'da tespit edilir.

```bash
# /etc/teqlif/node.conf — bootstrap tarafından oluşturulur, manuel değiştirilmez

NODE_NAME=node5
NODE_ROLE=core          # gateway | core | stream | ai_proxy | monitor | storage

# teqlif-restart'ta restart edilir; teqlif-refresh'te ATLANIR
DATA_SERVICES="postgresql pgbouncer redis-6379 redis-6380 clickhouse-server"

# Her iki komutta da restart edilir (primary'de)
APP_SERVICES="teqlif"
# Not: teqlif-worker ve teqlif-worker-critical BindsTo=teqlif.service ile otomatik gelir

# teqlif-restart öncesi çalıştırılır (boşsa atlanır)
PRE_RESTART_HOOKS="alembic_upgrade sync_translations"

# İzleme — her iki komutta da restart ATLANIR (durum tablosunda görünür)
INFRA_SERVICES="node_exporter promtail teqlif-backup.timer teqlif-healthcheck.timer"

IS_GATEWAY=false
```

Gateway için:
```bash
NODE_NAME=gateway1
NODE_ROLE=gateway
DATA_SERVICES=""
APP_SERVICES=""
PRE_RESTART_HOOKS=""
INFRA_SERVICES="node_exporter promtail"
IS_GATEWAY=true
GATEWAY_SERVICE="nginx"
```

---

### 19.6 Script Mantığı (Özet)

```
teqlif-restart / teqlif-refresh
  │
  ├─ node.conf oku
  ├─ WireGuard IP'den NODE_ROLE tespit et
  │
  ├─ IS_GATEWAY=true?
  │   ├─ restart: git pull + nginx restart
  │   └─ refresh: nginx -s reload
  │
  ├─ NODE_ROLE=core?
  │   ├─ pg_is_in_recovery() kontrol et
  │   ├─ PRIMARY:
  │   │   ├─ restart: git pull → PRE_RESTART_HOOKS → APP_SERVICES restart
  │   │   └─ refresh: APP_SERVICES restart
  │   └─ STANDBY:
  │       ├─ restart: git pull → "STANDBY" uyarısı → çık
  │       └─ refresh: "STANDBY" uyarısı → çık
  │
  ├─ NODE_ROLE=monitor?
  │   ├─ restart: git pull + staging servisler + monitoring stack
  │   └─ refresh: sadece staging servisler (monitoring dokunulmaz)
  │
  ├─ NODE_ROLE=stream?
  │   ├─ restart: livekit + edge-metrics-agent restart (MinIO YOK — V2.0'da stream node'larında MinIO çalışmıyor)
  │   └─ refresh: edge-metrics-agent restart (LiveKit dokunulmaz)
  │
  ├─ NODE_ROLE=storage?
  │   ├─ restart: minio + edge-metrics-agent + promtail (node8'de) restart
  │   └─ refresh: minio + edge-metrics-agent restart (promtail dokunulmaz)
  │
  └─ NODE_ROLE=ai_proxy?
      └─ her iki komut: ilgili tek servis restart
```

---

## 11. V1.4 → V2.0 Fark Özeti

| Alan | V1.4 | V2.0 |
|------|------|------|
| Gateway | Tek (SPOF) | Aktif-aktif (CF Multi-A) |
| Core failover | Yok | Keepalived + node6 passive replica |
| Core standby servisleri | — | PG replica + Redis replica + teqlif-backup; teqlif/workers çalışmaz |
| ClickHouse standby | — | Çalışmaz; failover sonrası node3 backup'ından restore |
| Media storage | node1 + node4 (NVMe, ikisi eşit) | node7 + node8 (1TB HDD × 2, identical) dual-write; node1/4 artık storage almaz |
| Media URL | `minio1.teqlif.com` DNS Only | `uploads.teqlif.com` (DNS Only) + `media.teqlif.com` (CF cache) |
| Redis | Tek instance, DB 0/1 karma | Core Redis (uygulama) + Orch Redis (altyapı) ayrı instance |
| Orchestrator | FastAPI içi, node seçimi | Bağımsız servis, DNS + sync + komut + node seçimi |
| cf-failover | node2'de bash daemon | Kaldırıldı (CF Multi-A yeterli) |
| Edge → Core Redis bağlantısı | Var | Yok — edge'ler sadece Orch Redis'i bilir |
| Node ekleme | Kod değişikliği | nodes.yaml'a bir blok |
| Operasyon komutları | `teqlif-restart` (tek komut, tüm servisler) | `teqlif-restart` (git pull + alembic + restart) + `teqlif-refresh` (uygulama katmanı restart) — node rolü + PG primary/replica durumu dinamik tespit |
| Edge Orchestrator | FastAPI içi `EdgeOrchestrator` sınıfı, Core Redis'te metrik | Ayrı `teqlif-orchestrator` servisi, Orch Redis'te metrik — FastAPI `get_orch_redis()` ile okur |
| Redis bağlantısı | `REDIS_URL=10.10.0.5:6379` (direkt IP) | VIP: `10.10.0.10:6379` (Core) + `10.10.0.11:6380` (Orch) |
| Backup | node5 (primary) çalışır | node6 (standby/replica) çalışır — primary'e yük yok |
| `forwarded-allow-ips` | Sadece gateway1 (`10.10.0.2`) | gateway1 + gateway2 (`10.10.0.2,10.10.0.9`) |

---

*Belge tarihi: 2026-09-28 · Durum: Tamamlandı — backend/mobile/node spec tutarlılık analizi eklendi (§18.20–21, §19.3/6 stale fix, §15.5 prefix düzeltmesi) · 02_plan.md yazılmaya hazır*
