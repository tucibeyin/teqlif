# Stream Recording Strategy — V1.2 Findings

Tarih: 2026-10-04  
Durum: **İmplementasyon tamamlandı** (2026-10-04)

---

## 1. Altyapı Analizi

### Streaming Node'ları (node3 / node4)

| Özellik | Değer |
|---------|-------|
| CPU | 6-core Haswell |
| RAM | 11.4 GB |
| NVMe SSD | 99 GB (≈88 GB boş) |
| Ağ | ≈2 Gbps |

**Kritik gözlem:** Kayıt bandwith yükü yayıncının upload hızına (2–4 Mbps) bağlıdır, viewer fanout bandwith'ine değil. Node tüm kapasitesiyle dolu yayın yapsa bile raw kayıt günde ≈90 GB üretir — bu rakam tüm günün birikimi, aynı anda diskte bulunmaz.

### node1 (MinIO — kullanıcı erişimi)
- SSD-backed MinIO, `teqlif` bucket
- Presigned URL ile kullanıcıya servis edilir

### node2 (Backup merkezi)
- Günlük 4 timer (pg/ch/redis/minio)
- `minio_backup` timer zaten çalışıyor; ayrı mekanizma gerekmez

---

## 2. Boyut Hesabı

| Aşama | node3 | node4 | Toplam |
|-------|-------|-------|--------|
| Raw MKV (prime time tam kapasite, günlük birikimi) | ≈90 GB | ≈90 GB | ≈180 GB |
| Encoded MP4 (×0.4 sıkıştırma) | ≈36 GB | ≈36 GB | ≈72 GB |
| node1'e gönderilen (encoded, off-peak) | 36 GB | 36 GB | **72 GB/gece** |

Raw MKV hiçbir zaman streaming node'larından çıkmaz. Encode edilmiş MP4 off-peak pencerede node1'e taşınır.

### Gerçek zamanlı disk kullanımı (en kötü senaryo, gün içi peak)

| Kalem | Boyut |
|-------|-------|
| 10 aktif stream, 2'şer saat raw | ≈36 GB |
| 1 encode job (raw + output aynı anda) | ≈7 GB |
| Encode bekleyen önceki kayıtlar | ≈10 GB |
| **Toplam** | **≈53 GB / 88 GB** |

Encode hemen yapıldığı ve raw silindiği sürece 88 GB sınırına yaklaşılmaz.

---

## 3. Lifecycle Kararları

### 3a. Kullanıcı erişim süresi: **24 saat**

- Kayıt node1/MinIO'ya geçince kullanıcıya açılır.
- 24 saat içinde izleyebilir.
- 24 saat sonra MinIO'dan silinir, kullanıcı erişimi kapanır.
- Sorun olursa kullanıcı e-posta ile bildirir, sisteme müdahale edilir.

### 3b. Kim izleyebilir?

- Yayıncı **ve** izleyiciler 24 saatlik pencerede erişebilir.

### 3c. Backup ve saklama süresi: **15 gün**

- Nightly backup otomatik olarak node2'ye alır.
- 5. günden itibaren MinIO lifecycle (4 günlük TTL) dosyayı siler, backup node2'de yaşamaya devam eder.
- 15. günün sonunda node2'deki backup imha edilir.

### 3d. Tüm işlemler 03:00–08:00 UTC penceresinde

**Bu pencere dışında hiçbir transfer veya backup çalışmaz.**

| Aşama | Zamanlama |
|-------|-----------|
| Encode | Stream biter bitmez (hemen) — disk yönetimi için kritik |
| node1'e transfer | 03:00–08:00 UTC |
| Nightly backup (node1 → node2) | 03:00–08:00 UTC (zaten bu pencerede) |
| Kayıt kullanıcıya açılır (`available_at`) | Transfer tamamlanınca, sabah 03:00–08:00 arasında |
| Push bildirimi | `available_at` anında |

**Gerekçe:** Kullanıcı trafiğinin yoğun olduğu saatlerde transfer ve backup yapmak istemiyoruz. Sabah uyanan kullanıcı önceki geceki kaydı hazır bulur.

### 3e. Disk guard — kademeli model

Transfer penceresi dışında çalışmayı tetikleyebilecek tek istisna, kademeli eşiklerle yönetilir:

| Disk boş alan | Aksiyon |
|---------------|---------|
| ≥ 15 GB | Normal — transfer 03:00 UTC'de |
| 10–15 GB | Erken tetik — transfer 02:00 UTC'de başlar |
| < 10 GB | Acil — hemen başlat (pencere yok) |

02:00 UTC erken tetik de pratikte hâlâ "gece sessiz saati" kapsamındadır; o saatte yayın yapan kullanıcı sayısı yok denecek kadar azdır ve node3/4 bandwidth'i transfere fazlasıyla yeterlidir.

**Implementasyon:**
- `disk_guard.py` (teqlif-agent): periyodik disk izleme, Redis'e `teqlif:recording:transfer_trigger` yazar (`early` / `emergency`)
- `transfer_recordings_task` (ARQ): 02:00 UTC'de sadece flag varsa çalışır; 03:00 UTC'de her koşulda çalışır
- Flag transfer tamamlanınca silinir

### 3f. Gece 03:00 transfer + aktif yayın çakışması

Gece 03:00'de aktif yayın olan edge case mümkün ama çok nadirdir. Transfer yine de başlatılır çünkü:
- Az sayıda aktif stream en fazla 6–12 Mbps kullanır
- Transfer iç ağdan gider (WireGuard 10.10.0.x), kullanıcı trafiğiyle rekabet etmez
- node3/4'ün 2 Gbps kapasitesine kıyasla yük görünmez düzeyde

---

## 4. Lifecycle Aşamaları

```
Phase 1: RECORDING
  → FFmpeg, yayıncının WHEP endpoint'inden raw MKV yazıyor (node3/4)
  → Disk kullanımı: raw dosya sürekli büyüyor

Phase 2: ENCODING
  → Stream bitti, FFmpeg encode hemen başladı (node3/4 üzerinde)
  → Raw MKV → encoded MP4 (×0.4 boyut)

Phase 3: ENCODED  ← YENİ (transfer penceresini bekliyor)
  → Encode tamamlandı, raw MKV silindi (disk temizlendi)
  → Encoded MP4 diskte bekliyor, 03:00 UTC'yi bekliyor

Phase 4: TRANSFERRING
  → 03:00 UTC penceresi açıldı, encoded MP4 node1/MinIO'ya yükleniyor

Phase 5: AVAILABLE
  → MinIO'da, kullanıcıya açık
  → Push bildirimi: "Dünkü yayınınızın kaydı izlemeye hazır"
  → available_at = şimdi (sabah 03:00–08:00 arası)
  → expires_at = available_at + 24h

Phase 6: EXPIRED
  → expires_at geçti, MinIO'dan silindi
  → Kullanıcı erişimi yok
  → Sadece sistem tarafından kullanılabilir (node2 backup üzerinden)

Phase 7: ARCHIVED
  → Nightly backup node2'ye kopyaladı
  → Sistem gerektiğinde geri çağırabilir

Phase 8: DELETED
  → archived_at + 15 gün sonra tamamen imha edildi
```

---

## 5. Veritabanı Şeması

### 5a. Mevcut tabloya ekleme: `live_streams`

```sql
ALTER TABLE live_streams
    ADD COLUMN recording_enabled BOOLEAN DEFAULT FALSE;
```

Yayıncı stream başlatırken toggle açıksa `TRUE`. Sadece bu bir kolon eklenir.

### 5b. Yeni tablo: `stream_recordings`

```sql
CREATE TABLE stream_recordings (
    id                   BIGSERIAL PRIMARY KEY,
    stream_id            INTEGER      NOT NULL REFERENCES live_streams(id),
    host_id              INTEGER      NOT NULL REFERENCES users(id),

    -- Mevcut durum
    status               VARCHAR(20)  NOT NULL DEFAULT 'recording',
    -- recording | encoding | encoded | transferring | available | expired | archived | deleted | failed

    -- Dosya konumları
    recording_node       VARCHAR(10),          -- 'node3' veya 'node4'
    raw_path             TEXT,                 -- /var/recordings/raw/{stream_id}.mkv
    encoded_path         TEXT,                 -- /var/recordings/encoded/{stream_id}.mp4
    minio_key            TEXT,                 -- recordings/{stream_id}.mp4

    -- Boyutlar
    raw_size_bytes       BIGINT,
    encoded_size_bytes   BIGINT,
    duration_secs        INTEGER,

    -- Lifecycle zaman damgaları
    recording_started_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    encoding_started_at   TIMESTAMPTZ,
    encoded_at            TIMESTAMPTZ,         -- raw silindi, transfer bekliyor
    transferred_at        TIMESTAMPTZ,         -- MinIO'ya yüklendi (sabah 03-08)
    available_at          TIMESTAMPTZ,         -- kullanıcıya açıldı
    expires_at            TIMESTAMPTZ,         -- available_at + 24h
    archived_at           TIMESTAMPTZ,         -- node2 backup'a geçti
    deleted_at            TIMESTAMPTZ,

    -- Bildirim
    notified_at           TIMESTAMPTZ,         -- "kayıt hazır" push gönderildi

    -- Hata yönetimi
    error_message         TEXT,
    retry_count           INTEGER  DEFAULT 0,

    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_stream_recordings_stream_id ON stream_recordings(stream_id);
CREATE INDEX ix_stream_recordings_host_id   ON stream_recordings(host_id);
CREATE INDEX ix_stream_recordings_status    ON stream_recordings(status);
CREATE INDEX ix_stream_recordings_expires   ON stream_recordings(expires_at)
    WHERE status = 'available';
```

### 5c. Status geçiş makinesi

```
recording     → encoding      (stream bitti, FFmpeg encode hemen başladı)
encoding      → encoded       (encode tamamlandı, raw silindi, transfer penceresi bekleniyor)
encoded       → transferring  (03:00 UTC penceresi açıldı, transfer başladı)
transferring  → available     (MinIO yüklendi, available_at + expires_at atandı, push gönderildi)
available     → expired       (ARQ cron: expires_at < NOW(), MinIO'dan sil)
expired       → archived      (nightly minio_backup sonrası ARQ günceller)
archived      → deleted       (ARQ cron: archived_at + 15 gün geçti)
herhangi biri → failed        (hata — retry_count ile izlenir)
failed        → encoding      (retry)
failed        → encoded       (retry — encode OK ama transfer başarısız)
```

---

## 6. MinIO Bucket Lifecycle

- Bucket: `teqlif`, prefix: `recordings/`
- Object expiry: **4 gün**
- Gerekçe: Nightly backup'ın dosyayı yakalamaya vakti olsun. `expires_at` (24h) DB layer'da zorunlu kılınır — MinIO'nun 4 günlük TTL'i kullanıcıya değil, depolama temizliğine yöneliktir.

---

## 7. Sistem Davranışı — Hangi Durumda Ne Olur

### Kullanıcı kaydı izlemek istediğinde

```python
recording = await db.scalar(
    select(StreamRecording)
    .where(StreamRecording.stream_id == stream_id)
    .where(StreamRecording.status == 'available')
    .where(StreamRecording.expires_at > datetime.now(timezone.utc))
)
if not recording:
    raise NotFoundException("RECORDING_EXPIRED")

url = minio_client.presigned_get_object(
    "teqlif", recording.minio_key, expires=timedelta(hours=2)
)
return {"url": url, "duration_secs": recording.duration_secs, "expires_at": recording.expires_at}
```

### ARQ cron: süresi dolan kayıtları işaretle (her saat)

```sql
UPDATE stream_recordings SET status = 'expired'
WHERE status = 'available' AND expires_at < NOW()
-- + MinIO'dan sil (mc rm)
```

### ARQ cron: transfer job (03:00 UTC, günlük)

```python
# status='encoded' olan tüm dosyaları MinIO'ya yükle
# Transfer başarılı → status='available', available_at=NOW(), expires_at=NOW()+24h
# Push bildirimi gönder → notified_at=NOW()
# Encoded dosyayı node'dan sil
```

### ARQ cron: archive temizliği (07:30 UTC, günlük)

```sql
UPDATE stream_recordings SET status = 'deleted', deleted_at = NOW()
WHERE status = 'archived' AND archived_at < NOW() - INTERVAL '15 days'
-- + node2 dosyasını sil
```

### Disk guard (teqlif-agent, sürekli izleme)

```python
FREE_SPACE_THRESHOLD_GB = 15

if free_gb < FREE_SPACE_THRESHOLD_GB:
    # Alert gönder
    # status='encoded' dosyaları için acil transfer başlat (pencere dışı istisna)
    # Yeni kayıt başlatmayı durdur
```

---

## 8. Tetikleme Noktaları (Backend)

| Olay | Tetiklenecek Aksiyon |
|------|---------------------|
| `ConfirmLiveCommand` (yayın başladı) | `INSERT stream_recordings (status='recording')`, Redis PUBLISH `teqlif:recording:start` |
| `finalize_stream` (yayın bitti) | `UPDATE status='encoding'`, Redis PUBLISH `teqlif:recording:stop` |
| Encode tamamlandı (janitor) | `UPDATE status='encoded', encoded_at`, raw dosyayı sil |
| 03:00 UTC transfer job | `UPDATE status='transferring'` → yükle → `UPDATE status='available'`, push gönder |

### Redis pub/sub kanalları

```
teqlif:recording:start   → payload: {stream_id, room_name, node, raw_path}
teqlif:recording:stop    → payload: {stream_id}
teqlif:recording:encoded → payload: {stream_id, encoded_path, size_bytes, duration_secs}
```

---

## 9. Implementasyon Sırası (Gelecek Sprint)

1. **Alembic migration** — `live_streams.recording_enabled` + `stream_recordings` tablosu
2. **MinIO lifecycle rule** — `recordings/` prefix, 4 günlük expiry
3. **Backend:** `ConfirmLiveCommand` → Redis PUBLISH `teqlif:recording:start`
4. **Backend:** `finalize_stream` → Redis PUBLISH `teqlif:recording:stop`
5. **teqlif-agent:** `recorder.py` modülü — Redis subscribe, FFmpeg WHEP kaydı
6. **teqlif-agent:** `encoder.py` modülü — encode + raw sil (hemen çalışır, pencere beklemez)
7. **teqlif-agent:** `disk_guard.py` — sürekli disk izleme, < 15 GB acil transfer
8. **ARQ task:** `transfer_recordings_task` — 03:00 UTC, status='encoded' → MinIO yükle → available
9. **ARQ task:** `expire_recordings_task` — saatlik cron, expires_at < NOW() → expired + MinIO sil
10. **ARQ task:** `cleanup_archived_recordings_task` — 07:30 UTC, archived + 15 gün → deleted
11. **Backend API:** `GET /streams/{id}/recording` — presigned URL endpoint
12. **Push notification:** "Dünkü yayınınızın kaydı izlemeye hazır" bildirimi
13. **schedule.yaml:** Yeni ARQ cron job'larını ekle + watchdog_m değerleri

---

## 10. Stream Analitiği — Mevcut Durum ve Kapasite Planlama

### Şu an ne izleniyor?

| Veri | Nerede | Durum |
|------|--------|-------|
| `started_at`, `ended_at` | PostgreSQL `live_streams` | ✅ Var |
| `viewer_count`, `peak_viewer_count` | PostgreSQL `live_streams` | ✅ Var |
| Viewer giriş/çıkış zamanları (`left_at`) | PostgreSQL `live_stream_viewers` | ✅ Var |
| SwipeLive ürün etkileşimleri | ClickHouse `swipe_live_events` | ✅ Var |
| Saate göre aktif stream dağılımı | — | ❌ Yok |
| Stream başlangıç/bitiş ClickHouse pipeline | — | ❌ Yok |

**`StreamAnalyticsProjector`** (`backend/app/use_cases/streams/projectors/stream_projector.py`): Faz 7.4'te Redis stats kaldırılmış, yerine ClickHouse yazımı konulmamış. Şu an sadece log yazıyor, veri persist etmiyor.

### Canlıya çıkınca kullanılacak sorgu

İlk 2–4 haftalık production verisiyle PostgreSQL'den peak saat analizi:

```sql
SELECT
    EXTRACT(hour FROM started_at AT TIME ZONE 'UTC') AS hour_utc,
    COUNT(*)                                          AS stream_count,
    AVG(EXTRACT(epoch FROM (ended_at - started_at)) / 3600.0) AS avg_duration_h
FROM live_streams
WHERE started_at > NOW() - INTERVAL '30 days'
  AND ended_at IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

Bu sorgu:
- Hangi saatlerde en çok yayın başlıyor
- Ortalama yayın süresini
- Gece 02:00–03:00 UTC'deki gerçek yoğunluğu gösterir

### Karar: şimdi ekstra altyapı gerekmez

`started_at`/`ended_at` PostgreSQL verisi kapasite planlaması için yeterlidir. Canlıya çıkıp **2–4 hafta** sonra bu sorguyu çalıştır:
- Peak saatler gerçek veriden doğrulanırsa → transfer penceresi ve disk guard eşikleri `schedule.yaml`'dan güncellenir
- Gece saatlerinde beklenmedik yoğunluk varsa → erken tetik eşiği (10–15 GB arası) düşürülür
- ClickHouse time-series pipeline ancak daha granüler analiz gerekirse eklenir

---

## 11. teqlif-agent Mimari Kararları

### Mevcut agent yapısı — recording için ne hazır

| Modül | Durum | Açıklama |
|-------|-------|----------|
| `janitor.py` | ⚠️ Yarım | `stream_recording_encode_queue` + `stream_recording_transfer_queue` policy'leri var, ama sadece Redis sinyal atıyor — FFmpeg veya `mc cp` çalıştırmıyor |
| `cleaner.py` | ⚠️ Hatalı | `stream_recordings` temizliği var ama kolon adı yanlış (`recorded_at` → `archived_at`) ve süre yanlış (30d → 15d) |
| `health.py` | ⚠️ Eksik | Disk %82 eşiğinde alert var, ama disk guard transfer trigger yok |
| `recorder.py` | ❌ Yok | Yeni yazılacak |
| `encoder.py` | ❌ Yok | Yeni yazılacak |

### Servis-bazlı modül keşfi — mimari karar

**Karar: agent, fiziksel node kimliğine değil — üzerinde çalışan servislere göre davranır.**

Gerekçe: Fiziksel node ↔ servis eşleşmesi operasyonel bir karardır, mimari bir sabit değil. Bugün node3/4'te LiveKit çalışıyor; yarın 3 güçlü node'da her birinde LiveKit + MinIO + PostgreSQL birlikte çalışabilir. Sistem bu değişikliği sıfır kod değişikliğiyle kaldırabilmeli.

```python
# agent.py — servis-bazlı modül yükleme
_SERVICE_MODULES = {
    "livekit":    lambda cfg, db: [StreamRecorder(cfg, db), StreamEncoder(cfg, db)],
    "clickhouse": lambda cfg, db: [AnalyticsWorker(cfg, db)],
    # ileride genişletilebilir
}

running = await detect_local_services()   # health.py zaten systemd'den çekiyor

for svc, factory in _SERVICE_MODULES.items():
    if svc in running:
        modules.extend(factory(cfg, db))
```

**`node_id` kontrolü kullanılmaz.** Hiçbir modülde `if cfg.node_id in ("node3", "node4")` olmaz.

### `cluster.yaml` — küme geneli single source of truth

`schedule.yaml` ile aynı pattern. `deploy/scale/V2.1/cluster.yaml`:

```yaml
recording:
  enabled: true          # tek satırla tüm sistemde kaydı aç/kapat
  primary_minio: 10.10.0.1:9000
  bucket: teqlif
  disk_warn_gb: 15
  disk_emergency_gb: 10
  transfer_window: {start_utc: 2, end_utc: 8}
  user_access_hours: 24
  retention_days: 15
  raw_dir: /var/recordings/raw
  encoded_dir: /var/recordings/encoded
```

Her node'un `config.yaml`'ı yalnızca kimlik bilgilerini tutar:
```yaml
node_id: node3
wg_ip: 10.10.0.3
gossip_token: "..."
redis_url: redis://10.10.0.1:6379/0
```

### Propagasyon akışı

Agent `cluster.yaml`'ı her cycle'da (60s) yeniden okur. Değişiklik akışı:

```
cluster.yaml güncellendi (örn. recording.enabled: false)
  → git push
  → sudo teqlif-restart → tüm node'larda git pull
  → bir sonraki agent cycle'ında (≤60s) yeni config aktif
  → sıfır restart gerekmez*

* cluster.yaml değişikliği için restart gerekmez.
  Sadece agent binary değişirse restart gerekir.
```

### Yeni modüller — sorumluluk dağılımı

```
node (LiveKit çalışıyor) — teqlif-agent
├── recorder.py   Redis sub → FFmpeg WHEP → raw MKV → DB status='recording'
├── encoder.py    status='recording' biter → FFmpeg encode → raw sil → DB status='encoded'
└── janitor.py+   02:00/03:00 penceresi → mc cp → DB status='available' → Redis push trigger

node1 — ARQ backend
├── transfer_recordings_task   Redis'ten 'available' sinyali → push notification
├── expire_recordings_task     saatlik: expires_at < NOW() → MinIO sil → status='expired'
└── cleanup_archived_task      07:30 UTC: archived + 15 gün → status='deleted'

node2 — mevcut timer (dokunma)
└── minio_backup               recordings/ prefix otomatik kopyalanır
```

### Implementasyon sırası (agent tarafı)

1. `cluster.yaml` oluştur (`deploy/scale/V2.1/cluster.yaml`)
2. `config.py` — `cluster.yaml` okuyucu + `AgentConfig`'e `cluster` alanı ekle
3. `agent.py` — `_SERVICE_MODULES` dict + servis-bazlı modül yükleme
4. `recorder.py` — yeni modül (FFmpeg WHEP, Redis sub/pub)
5. `encoder.py` — yeni modül (FFmpeg encode, hemen çalışır)
6. `janitor.py` — transfer window kontrolü + gerçek `mc cp` + DB update
7. `health.py` — disk guard: < 15 GB / < 10 GB → Redis flag
8. `cleaner.py` — `recorded_at` → `archived_at`, 30d → 15d düzelt

---

## 12. nodeMonitor Analizi

### Çalışan servisler

| Servis | Port | Açıklama |
|--------|------|----------|
| Prometheus | 9090 | 7 node'dan 15s'de bir metrik toplar, 30 gün saklar |
| Loki | 3100 | Log aggregation, 30 gün retention |
| Grafana | 3000 | Dashboard — Prometheus + Loki datasource |
| Alertmanager | 9093 | Telegram alert yönlendirme |
| Uptime Kuma | 3001 | Uptime izleme, MariaDB backend |
| node-exporter | 9100 | Kendi metriklerini sunar |
| teqlif-agent | — | **priority=1 — gossip lider adayı** |

Yerel DB: sadece MariaDB (Uptime Kuma için). PostgreSQL yok, Redis yok, MinIO yok, LiveKit yok.

### Recording pipeline açısından kritik tasarım hatası

teqlif-agent priority=1 olduğundan nodeMonitor çoğunlukla **lider**'dir. Lider TTLJanitor'ü çalıştırır. Mevcut `janitor.py`'daki `_trigger_transfer_check()`:

```python
encoded_dir = "/var/recordings/encoded/"
files = os.listdir(encoded_dir)   # nodeMonitor'de bu dizin YOK
```

nodeMonitor lider olduğunda bu kontrol boş döner — transfer asla tetiklenmez. Bu mevcut bir tasarım hatasıdır. **Servis-bazlı modül yükleme bu hatayı köklü çözer:** encoder ve transfer modülleri yalnızca LiveKit çalışan node'larda yüklenir, nodeMonitor'de hiç çalışmaz.

### Lider-gated vs lokal modüller

Recording pipeline bu ayrımı zorunlu kılıyor:

| Modül | Çalışma koşulu | Gerekçe |
|-------|---------------|---------|
| TTLJanitor (DB sorguları) | Lider (nodeMonitor olabilir) | Küme geneli DB operasyonu |
| ScheduledCleaner | Lider | Küme geneli temizlik |
| `recorder.py`, `encoder.py` | Lokal — LiveKit varsa | Dosyalar ve FFmpeg burada |
| `disk_guard` | Lokal — LiveKit varsa | Lokal disk izleme |
| Transfer job | Lokal — LiveKit varsa, zaman penceresi | Dosyalar burada, lider değil |
| HealthMonitor | Her node kendisi | Lokal donanım |

**Kural:** Recording modülleri lider seçimine bağlı değildir — lokal servis varlığına bağlıdır.

### nodeMonitor + recording sorumluluğu

```
nodeMonitor (lider)
  ✅ TTLJanitor DB sorguları    — stream_recordings archived+15d → deleted
  ✅ ScheduledCleaner           — archived_at + 15 gün temizliği
  ❌ recorder.py                — yüklenmez (LiveKit yok)
  ❌ encoder.py                 — yüklenmez (LiveKit yok)
  ❌ transfer job               — çalışmaz (dosyalar burada değil)

node3 / node4 (LiveKit çalışıyor)
  ✅ recorder.py                — LiveKit keşfedildi, yüklendi
  ✅ encoder.py                 — LiveKit keşfedildi, yüklendi
  ✅ disk_guard                 — lokal disk izleme
  ✅ transfer job               — lokal timer, lider gerektirmez
```

### Fırsat: alert_rules.yml'e recording disk alert'i

nodeMonitor zaten node3/4'ü scrape ediyor. Eklenecek kural:

```yaml
- alert: RecordingDiskCritical
  expr: node_filesystem_avail_bytes{node=~"node3|node4", mountpoint="/"} < 10737418240
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "{{ $labels.node }} kayıt diski kritik"
    description: "{{ $labels.node }} kayıt diski 10 GB altına düştü — acil transfer gerekiyor"
```

Prometheus zaten veriyi çekiyor, Telegram alert sıfır ekstra maliyet.

---

## 13. Canlı Node Envanteri — Tam Tablo

### Donanım ve disk durumu (2026-10-04)

| Node | IP | RAM (toplam/boş) | Disk (toplam/boş) | Disk tipi |
|------|-----|-----------------|------------------|-----------|
| node1 | 10.10.0.1 | 31 GB / 20 GB | 467 GB / 428 GB | SSD RAID |
| node2 | 10.10.0.2 | 31 GB / 19 GB | 3.6 TB / 3.4 TB | HDD RAID-1 |
| node3 | 10.10.0.3 | 11 GB / 10 GB | 99 GB / 88 GB | NVMe |
| node4 | 10.10.0.4 | 11 GB / 10 GB | 99 GB / 88 GB | NVMe |
| node5 | 10.10.0.5 | 7.8 GB / 4.9 GB | 50 GB / 28 GB ⚠️ | SSD |
| node6 | 10.10.0.6 | 3.8 GB / 3.3 GB | 50 GB / 32 GB | SSD |
| nodeMonitor | 10.10.0.99 | 1.9 GB / 737 MB ⚠️ | 58 GB / 49 GB | SSD (VM) |

### Çalışan servisler ve keşfedilen roller

**node1** — App + Storage
```
postgresql@17-main  → 10.10.0.1:5432 (WireGuard'dan erişilebilir)
pgbouncer           → 127.0.0.1:6432
teqlif-minio        → *:9000 (tüm arayüzler — WireGuard dahil)
teqlif-redis-core   → 10.10.0.1:6379 (primary)
teqlif.service      → uygulama
teqlif-worker       → ARQ worker (batch)
teqlif-worker-critical → ARQ worker (push notification)
nginx, promtail, crowdsec, pgbouncer
```
→ Service discovery: `teqlif-minio` + `postgresql` + `teqlif.service` → app/storage node

**node2** — Backup + Analytics + Email
```
clickhouse-server   → 10.10.0.2:8123 (HTTP) / 10.10.0.2:9000 (native)
teqlif-redis-replica → 10.10.0.2:6379
haproxy             → Redis HA proxy
stalwart-mail       → e-posta sunucusu
nginx, php8.4-fpm   → web (muhtemelen yönetim paneli)
```
Disk: 3.6 TB HDD RAID-1 — backup hedefi. **Promtail yok** (loglar Loki'ye gitmiyor).
→ Service discovery: `clickhouse-server` → analytics node; `haproxy` + `teqlif-redis-replica` → backup/HA node

**node3 / node4** — Streaming (özdeş)
```
teqlif-livekit      → *:7880 (HTTP/WHEP) / *:7881 (TLS)
haproxy             → 127.0.0.1:8080 (LiveKit önünde proxy)
promtail            → log gönderimi
```
RAM: 11 GB, kullanılan yalnızca ~480 MB (yayın yokken). Disk: 88 GB boş.
→ Service discovery: **`teqlif-livekit`** → recorder + encoder modülleri yüklenir

**node5** — Staging (all-in-one)
```
postgresql@17-main  → 127.0.0.1:5432
teqlif-minio-staging → 127.0.0.1:9000
teqlif-redis-staging → 127.0.0.1:6379
teqlif-livekit-staging → staging LiveKit
clickhouse-server   → staging analytics
teqlif-staging      → staging app (10.10.0.5:8000)
teqlif-worker-staging
teqlif-ai-proxy
```
**Disk: %41 dolu, 28 GB boş — izlenmeli.**
Node5, "yarın 3 güçlü node'da her şey çalışır" senaryosunun mevcut kanıtı: tüm servisler tek node'da.
→ Service discovery: **`teqlif-livekit-staging`** → recorder + encoder yüklenir (staging config ile)

**nodeMonitor** — Observability (VM, 10.10.0.99)
```
grafana-server      → :3000 (dashboard)
teqlif-prometheus   → 10.10.0.99:9090 (veri: 113 MB, 30 gün)
teqlif-loki         → 10.10.0.99:3100 (veri: 16 MB, 30 gün)
teqlif-alertmanager → 127.0.0.1:9093
uptime-kuma         → :3001 (MariaDB backend)
mariadb             → Uptime Kuma için
node-exporter       → 10.10.0.99:9100
teqlif-agent        → priority=1, gossip lideri
```
RAM: **1.9 GB toplam, 737 MB available** — sıkışık. Sanal makine (qemu-guest-agent).
Disk: 58 GB, 7.2 GB kullanılmış. **Promtail yok** — kendi logları Loki'ye gitmiyor.
→ Service discovery: kayıt modülleri yüklenmez (LiveKit yok)
→ teqlif-agent lider olarak TTLJanitor DB sorgularını çalıştırır (hafif async — RAM sorunu olmaz)

**node6** — AI Inference
```
teqlif-ai-proxy     → AI model proxy
```
Minimal RAM (3.8 GB). Başka servis yok.
→ Service discovery: özel modül gerekmez

### Service discovery — `_SERVICE_MODULES` eşleme tablosu

```python
_SERVICE_MODULES = {
    "teqlif-livekit":         lambda cfg, db: [StreamRecorder(cfg, db), StreamEncoder(cfg, db)],
    "teqlif-livekit-staging": lambda cfg, db: [StreamRecorder(cfg, db, staging=True), StreamEncoder(cfg, db, staging=True)],
}
```

Staging/production ayrımı `cluster.yaml`'dan okunur:

```yaml
recording:
  teqlif-livekit:
    minio_host: 10.10.0.1:9000
    bucket: teqlif
    raw_dir: /var/recordings/raw
    encoded_dir: /var/recordings/encoded
  teqlif-livekit-staging:
    minio_host: 127.0.0.1:9000
    bucket: teqlif-staging
    raw_dir: /var/recordings/raw
    encoded_dir: /var/recordings/encoded
```

Agent `teqlif-livekit-staging` çalıştığını görür → `cluster.yaml`'dan staging config'i çeker → staging MinIO'ya gönderir. **Sıfır hardcoded değer.**

### Recording pipeline — gerçek network yolları

```
node3 (FFmpeg WHEP → raw MKV → encode → MP4)
  → mc cp  →  node1:9000 (MinIO, WireGuard üzerinden)
               ↓ (nightly minio_backup)
             node2 (3.4 TB HDD RAID)

node4 (aynı)
  → mc cp  →  node1:9000
               ↓
             node2
```

node1 MinIO `*:9000` dinliyor — WireGuard arayüzünden (10.10.0.1) direkt erişilebilir. Ayrıca yapılandırma gerekmez.

### Dikkat edilecekler

| Node | Sorun | Öneri |
|------|-------|-------|
| node5 | Disk %41, 28 GB boş — büyüme riski | Periyodik izle; staging kayıt aktifleşirse dikkatli ol |
| node2 | Promtail yok — loglar Loki'ye gitmiyor | Sonraki maintenance'ta ekle |
| node3/4 | HAProxy LiveKit önünde (`127.0.0.1:8080`) | WHEP kayıt için doğrudan `*:7880` kullanılmalı, HAProxy değil |
| nodeMonitor | RAM 1.9 GB, ~280 MB available — sanal makine | Ağır iş yükü verme; TTLJanitor DB sorguları hafif, sorun yok. Orta vadede RAM upgrade değerlendirilebilir |
| nodeMonitor | Swap 2 GB → **4 GB'a yükseltildi** (2026-10-04) | `/swapfile` dosyası, `/etc/fstab` ile kalıcı |
| nodeMonitor | Kendi logları Loki'ye gitmiyor (promtail yok) | Sonraki maintenance'ta ekle |

---

## 14. İmplementasyon Özeti (2026-10-04)

### Agent tarafı (tamamlandı)

| Dosya | Değişiklik |
|-------|------------|
| `deploy/scale/V2.1/cluster.yaml` | **YENİ** — single source of truth: servis→MinIO eşlemesi, transfer penceresi, disk eşikleri |
| `deploy/scale/V2.1/teqlif-agent/config.py` | `load_cluster_config()` + `AgentConfig.recording_config_for()` + `.cluster_recording` |
| `deploy/scale/V2.1/teqlif-agent/agent.py` | `_active_recording_services()` — systemd servis keşfi → recorder+encoder modülleri yüklenir |
| `deploy/scale/V2.1/teqlif-agent/modules/recorder.py` | **YENİ** — FFmpeg WHEP kayıt yöneticisi, orphan recovery, DB polling |
| `deploy/scale/V2.1/teqlif-agent/modules/encoder.py` | **YENİ** — FFmpeg H.264 encode, mc cp transfer, disk guard, transfer penceresi |
| `deploy/scale/V2.1/teqlif-agent/modules/health.py` | `_recording_disk_status()` + `_eval_recording_disk()` — tiered disk guard alert |
| `deploy/scale/V2.1/teqlif-agent/modules/janitor.py` | `_trigger_transfer_check()` → PostgreSQL COUNT sorgusu (filesystem check değil) |
| `deploy/scale/V2.1/teqlif-agent/modules/cleaner.py` | `stream_recordings` 15d + `archived_at` düzeltmeleri |

### Backend tarafı (tamamlandı)

| Dosya | Değişiklik |
|-------|------------|
| `backend/alembic/versions/zzzzzb_stream_recordings.py` | **YENİ** — `stream_recordings` tablosu + `live_streams.recording_enabled` + teqlif_agent GRANT |
| `backend/app/models/stream.py` | `recording_enabled: Mapped[bool]` eklendi |
| `backend/app/schemas/stream.py` | `StreamStart.recording_enabled: bool = False` eklendi |
| `backend/app/use_cases/streams/commands/start_stream.py` | `recording_enabled` parametresi ve stream_data'ya aktarım |
| `backend/app/routers/streams.py` | `recording_enabled` pass-through + `GET /{id}/recording` endpoint (presigned URL) |
| `backend/app/tasks/stream_recording_tasks.py` | **YENİ** — `expire_recordings_task`, `archive_recordings_task` ARQ görevleri |
| `backend/app/worker.py` | Import + `functions` listesi + cron: her 30dk expire, her saat archive |

### Ops (tamamlandı)

| Eylem | Açıklama |
|-------|----------|
| FFmpeg 7.1.5 | node3 + node4'e apt ile kuruldu |
| mc | node3 + node4'e node1'den kopyalandı |
| MinIO lifecycle | `teqlif` bucket `recordings/` prefix → **4 gün sonra expire** (rule ID: db0usckkndqcpvdusp30) |
| nodeMonitor swap | 2 GB → 4 GB (2026-10-04) |

### Kalan adımlar

1. **Alembic migration uygula** — VPS'te `sudo teqlif-restart` + migration otomatik çalışır
2. **`/etc/teqlif-agent/config.yaml`** — node3/4'e `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` env ekle
3. **Flutter:** `StreamStart` isteğine `recording_enabled: true` desteği
4. **Staging test:** node3/4'te `teqlif-livekit-staging` servis adı varsa staging bucket'ına gider
5. **node2 MinIO backup:** `minio_backup` timer zaten `teqlif` bucket'ını alıyor — `recordings/` prefix otomatik kapsanır

---

## 15. Teknik Referanslar

- `backend/app/tasks/video_tasks.py` → `capture_hype_highlight()` — mevcut FFmpeg WHEP kayıt örneği
- `backend/app/use_cases/streams/stream_finalizer.py` → `finalize_stream()` — LiveKit room silme WHEP'i kapatır → FFmpeg çıkar
- `deploy/scale/V2.1/schedule.yaml` → gerekirse ek cron job eklenebilir
