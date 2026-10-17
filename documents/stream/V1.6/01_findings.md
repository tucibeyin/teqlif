# V1.6 — Streaming Kayıt Encoding Mimarisi

## Bağlam

Bu döküman, `teqlif-agent` streaming kayıt pipeline'ının encoding aşamasının ne zaman ve nasıl çalışması gerektiğine dair production mimarî analizini kapsar. Konu; SFU kalitesini korurken atıl CPU'yu verimli kullanmak ve bakım penceresinde birikmiş kuyruğu temizlemektir.

---

## Tam Pipeline

```
AŞAMA 1 — Canlı Kayıt (yayın sırasında, gerçek zamanlı, her an)
─────────────────────────────────────────────────────────────────
LiveKit RTP VP8 akışı
  → BGRA pixel buffer    (VP8 decode, CPU #1)
  → np.rot90 rotation    (telefon kamerası landscape→portrait, CPU #2)
  → libvpx VP8 @2 Mbps   (re-encode, deadline=realtime cpu-used=4, CPU #3)
  → MKV container        /var/recordings/raw/{stream_id}_{ts}.mkv

DB: status = 'recording'

Bu üç CPU adımı zorunludur; atlanamazlar. Rotation için piksel
düzeyinde işlem gerekir; RTP bitstream'i doğrudan MKV'ye yazmak
yanlış yönlendirme üretir.

─────────────────────────────────────────────────────────────────
AŞAMA 2 — H.264 Encode (stream bittikten sonra)
─────────────────────────────────────────────────────────────────
ffmpeg -i raw.mkv
  -vf scale=-2:720
  -c:v libx264 -crf 23 -preset veryfast
  -c:a aac -b:a 128k
  -movflags +faststart
  → /var/recordings/encoded/{stream_id}_{ts}.mp4

Raw MKV silinir. DB: status = 'encoded'

─────────────────────────────────────────────────────────────────
AŞAMA 3 — MinIO Transfer (02:00–05:00 UTC)
─────────────────────────────────────────────────────────────────
mc cp encoded.mp4 → teqlif-prod/teqlif/recordings/...
(node1, 10.10.0.1:9000, WireGuard)

Encoded MP4 node3/4'den silinir.
DB: status='available', available_at=NOW(), expires_at=NOW()+24h

─────────────────────────────────────────────────────────────────
AŞAMA 4 — node2 MinIO Backup (05:30 UTC)
─────────────────────────────────────────────────────────────────
minio_backup.sh: mc mirror node1 → node2 local
DB: node2_confirmed_at = NOW()

─────────────────────────────────────────────────────────────────
AŞAMA 5 — MinIO ILM Silme (2 gün)
─────────────────────────────────────────────────────────────────
recordings/ prefix: MinIO ILM, 2 gün sonra otomatik siler.
archive_recordings_task: node2_confirmed_at IS NOT NULL koşulunu
bekler, ardından DB: status = 'archived'

─────────────────────────────────────────────────────────────────
AŞAMA 6 — DB Temizlik (03:00 UTC, cleaner.py)
─────────────────────────────────────────────────────────────────
DELETE FROM stream_recordings
WHERE archived_at < NOW() - 15 days AND status = 'archived'
```

---

## Encoding Neden Atlanamaz (iOS Kısıtı)

Flutter `video_player` iOS'ta AVFoundation kullanır. AVFoundation yalnızca H.264 ve HEVC oynatır — VP8/WebM desteği yoktur.

| Platform | VP8/WebM | H.264/MP4 |
|----------|----------|-----------|
| Android (ExoPlayer) | ✅ | ✅ |
| iOS (AVFoundation) | ❌ | ✅ |

**H.264 encode zorunludur.** WebM remux iOS'u kırar.

MKV container HTTP'de seek edilemez; moov atom eşdeğeri yoktur. MP4 `-movflags +faststart` moov atom'u başa taşır — progressive HTTP streaming, CDN uyumluluğu ve video player seek'i bu sayede çalışır.

---

## Encoding Zamanı Kullanıcı Erişimini Etkilemez

Transfer penceresi `transfer_window_start_utc: 2` (cluster.yaml) ile 02:00 UTC'de açılır. Kullanıcı kaydına transfer tamamlanana kadar erişemez. Encoding hemen yapılsa da gece yapılsa da kullanıcı bekleme süresi değişmez — belirleyici olan transfer penceresidir.

Bu, encoding zamanlamasını kullanıcı deneyiminden bağımsız bir infrastructure kararına dönüştürür.

---

## Altyapı

### Donanım (ölçülen değerler, 2026-10-17)

| Node | Tip | CPU | RAM | Disk Toplam | Load |
|------|-----|-----|-----|-------------|------|
| node1 | Fiziksel OVH SYS-1 | 12 vCPU Xeon E-2236 @3.4GHz | 31 GB | 467 GB NVMe RAID | 0.15 |
| node3 | KVM VPS | 6 vCPU @3.1GHz | 11 GB | 86 GB SSD | 0.03 |
| node4 | KVM VPS | 6 vCPU @3.1GHz | 11 GB | ~86 GB SSD | ~0.03 |

WireGuard bant genişliği node1↔node3: ~1 Gbps teorik. Encoder transfer hızı `mc cp --limit-upload 30M` ile sınırlıdır (LiveKit bant genişliğini korumak için). Encoded MP4 (300–500 MB): ~10–17 saniye transfer.

### node1 Bakım Penceresi Yükü (schedule.yaml)

node1 02:00–05:00 UTC'de boş değil:

```
01:50  sync_pg_to_clickhouse_task
02:30  compute_analytics_cache_task
02:45  precompute_premium_user_analytics_task
03:00  pg_dump (node2 bağlantısı — node1 PG sorgu yükü alır)
03:20  clickhouse_backup
04:30  rebuild_faiss_index_task (CPU yoğun ~15 dk)
05:00  nsfw_backfill, backfill_phash, backfill_embeddings (ağır blok)
```

Bu nedenle encoding node1'e taşınmaz; kritik servislerle (PG, Redis, MinIO) CPU paylaşımı risklidir.

---

## Concurrent Encode Benchmark (node3, 2026-10-17)

Test: 60 saniyelik VP8 @2Mbps MKV, ffmpeg CRF23 veryfast 720p H.264.

```
N=1:  5.1s   ~1 core meşgul  →  5 core serbest
N=2:  7.2s   ~2-3 core       →  3-4 core serbest
N=3:  10.4s  ~3-4 core       →  2-3 core serbest (sınırda)
N=4:  13.7s  CPU saturasyonu başlar
N=6:  19.6s  6 core tamamen dolu
```

Gerçek zamanlı hız: **12× gerçek zamanlı** — 1 saatlik yayın ~5 dakikada encode olur.

---

## Karma Kullanım: Streaming + Encoding CPU Baskısı

### SFU Yük Modeli — İzleyici Fan-out

LiveKit SFU bir video işleyici değil, RTP paket çoğaltıcısıdır. Yük iki değişkene bağlıdır: yayıncı sayısı (N) ve izleyici sayısı (M).

```
SFU forwarding:        N stream × ~0.3 vCPU   (M=0, saf baseline)
                       + M izleyici ×  ~0.01 vCPU/izleyici/stream

İzleyici Fan-out Örnekleri (tek stream için):
  M=10  →  ~0.3 + 0.1  =  ~0.4 vCPU
  M=50  →  ~0.3 + 0.5  =  ~0.8 vCPU
  M=150 →  ~0.3 + 1.5  =  ~1.8 vCPU
```

VP8 subscriber encode (livekit_subscriber.py): BGRA decode + numpy rot90 + libvpx realtime encode = **~0.8–1.2 vCPU** (cpu-used=4, deadline=realtime; yayın çözünürlüğüne ve frame rate'e bağlı).

### Bir Node'da Eşzamanlı Yük (N yayın, M izleyici)

```
Aşama 1 (aktif kayıt):
  SFU forwarding:        N × (0.3 + M×0.01) vCPU
  VP8 subscriber encode: N × ~1.0 vCPU
  Toplam (N=2, M=100):   2×(0.3+100×0.01) + 2×1.0 = ~4.6 vCPU

Aşama 2 (post-encode, ffmpeg H.264 — aktif kayıt varken N=1):
  N=1 encode:            ~1.0 vCPU

Aktif kayıt + encoding toplamı (N=2, M=100, post-encode=1):
  ~5.6 vCPU  →  6 vCPU KVM sınırına yakın
```

### Cluster Kapasitesi — EdgeOrchestrator Dağılımı

Her yeni yayın `StartStreamCommand` aracılığıyla `EdgeOrchestrator.allocate_node(ServiceType.MEDIA)` çağırır. `_pick_media` fonksiyonu composite score ile en az yüklü node'u seçer:

```python
score = cpu_percent * 0.3 + (participants / 500 * 100) * 0.7
```

Node3 yoğunlaşınca score yükselir, yeni yayınlar otomatik olarak node4'e yönlendirilir. İki node birlikte çalıştığında cluster toplam kapasitesi:

| Senaryo | Node başına | Cluster (node3+4) |
|---------|------------|-------------------|
| Boş yayınlar (M≈0) | ~5 stream | ~10 stream |
| Orta izleyici (M≈50) | ~3 stream | ~6 stream |
| Yoğun izleyici (M≈150) | ~2 stream | ~4 stream |

Üçüncü yayın aynı node'a düşmez; EdgeOrchestrator diğer node'a yönlendirir.

Aktif kayıt yokken (stream aralarında veya gün boyu sakin saatlerde) node3 load 0.00–0.04 — CPU tamamen atıl.

Türkiye kullanım deseni göz önüne alındığında:
- Peak streaming: 15:00–21:00 UTC (18:00–00:00 TR)
- Atıl dönem: 21:00–15:00 UTC arası ~18 saat — bu sürenin büyük kısmı encode için kullanılabilir

---

## Encoding Stratejisi — Dinamik Parallelism

Saat tabanlı kısıtlama atıl dönemleri yakalayamaz. Doğru ölçüt, **bu node'da aktif kayıt var mı?**

### Karar Matrisi

| Durum | `_MAX_PARALLEL` | Gerekçe |
|-------|----------------|---------|
| Aktif kayıt var (`status='recording'` bu node'da) | **1** | SFU + subscriber VP8 encode zaten CPU kullanıyor; 1 post-encode ≈ 1 core, risk minimumdur |
| Aktif kayıt yok, normal saat | **2** | Atıl CPU değerlendirilir; birikme önlenir; SFU hiç çalışmıyor |
| Aktif kayıt yok + bakım penceresi (02:00–05:00 UTC) | **4** | Node gerçekten boş; kalan kuyruk hızla temizlenir |

### Uygulama Mantığı

`RecordingManager` ve `EncoderManager` aynı Python process'i (agent.py) içinde, aynı asyncio event loop'unda çalışır. Aktif kayıt durumunu öğrenmek için PostgreSQL'e TCP bağlantısı açmak gereksiz ağ bağımlılığı ve gecikme yaratır. `RecordingManager._procs` (rec_id → subprocess) zaten sürecin içindedir; bu dict'in referansı `EncoderManager`'a geçirilir.

**agent.py** — aynı servise ait modüller oluşturulurken:

```python
rec_mgr = RecordingManager(cfg, db, svc)
enc_mgr = EncoderManager(cfg, db, svc, recording_procs=rec_mgr._procs)
modules.append(rec_mgr)
modules.append(enc_mgr)
```

**EncoderManager.__init__** — yeni parametre:

```python
def __init__(
    self,
    cfg: AgentConfig,
    db: AgentDB,
    service_name: str,
    recording_procs: dict,   # RecordingManager._procs referansı
) -> None:
    self._recording_procs = recording_procs
    ...
```

**_resolve_max_parallel** — DB'ye gitmeden in-memory okuma:

```python
def _resolve_max_parallel(self, rec_cfg: dict) -> int:
    active = len(self._recording_procs)
    if active > 0:
        return 1                        # canlı yayın var → CPU koru

    # Disk acil: encode penceresi ve parallelism kısıtı kalkar
    enc_dir = Path(rec_cfg.get("encoded_dir", "/data/recordings/encoded"))
    if _free_gb(enc_dir) < float(rec_cfg.get("disk_emergency_gb", 10)):
        return 4

    now_h = datetime.now(timezone.utc).hour
    start = int(rec_cfg.get("transfer_window_start_utc", 2))
    end   = int(rec_cfg.get("transfer_window_end_utc",   5))
    if start <= now_h < end:
        return 4                        # bakım penceresi → kuyruğu hızla bitir

    return 2                            # normal atıl → arka planda işle
```

`_run_encodes()` başında `_MAX_PARALLEL` sabit değeri yerine `self._resolve_max_parallel(rec_cfg)` çağrılır. Sıfır ağ gecikmesi, DB bağlantısı yok.

Transfer penceresi için `_can_transfer_now()` ayrı çalışır — aynı `disk_emergency_gb` eşiğini kontrol eder ancak encode parallelism'den bağımsızdır.

---

## Disk Kapasitesi

### Boyut Referansı

| İçerik | Raw MKV | Encoded H.264 |
|--------|---------|--------------|
| 720p @2Mbps, 1 saat | ~900 MB | ~300–500 MB |
| 6 stream × 2 saat | ~10.8 GB | ~3.6 GB |
| 6 stream × 9 saat (aşırı senaryo) | ~48 GB | ~16 GB |

### Dinamik Parallelism ile Disk Baskısı

Dinamik stratejiyle gün boyunca 2 paralel encode çalışır — birikme oluşmadan dosyalar küçülür. 02:00 UTC'ye geldiğinde kuyruğun büyük kısmı zaten encoded MP4 (küçük). 4 paralel encode ile kalan kuyruk hızla tamamlanır.

Karşılaştırma:

| Strateji | 02:00 UTC'de diskte | 05:00 UTC'de durum |
|----------|--------------------|--------------------|
| Saf windowing (önceki öneri) | Tüm raw MKV birikmiş | Zaman yetmeyebilir |
| Dinamik parallelism (karar) | Büyük kısım encoded | Hızla tamamlanır |

---

## Bakım Penceresi Zaman Çizelgesi

```
UTC    TR (UTC+3)   Olay
────────────────────────────────────────────────────────────
00:00  03:00        DB temizlik (bildirimler, hikayeler)
01:50  04:50        PG → ClickHouse sync
02:00  05:00        ★ Transfer penceresi açılır
                    ★ _resolve_max_parallel() → 4 (aktif kayıt yoksa)
                    Kalan encoded MP4'ler → node1 MinIO
02:30  05:30        Analytics cache hesaplama
03:00  06:00        pg_dump, batch cleanup
                    stream_recordings 15d DB temizliği
04:30  07:30        rebuild_faiss_index (CPU yoğun)
05:00  08:00        Ağır batch blok başlar
05:30  08:30        minio_backup.sh → node2_confirmed_at set
```

Türkiye'de akşam 22:00'de yayın yapan bir kullanıcı kaydına en erken 05:00 yerel saatte (02:00 UTC sonrası transfer tamamlanınca) erişebilir. Bu kasıtlı tasarım kararıdır.

---

## agent.py Modül Yükleme

`_active_recording_services()` ile node'da aktif olan LiveKit servisleri tespit edilir. Her servis için ayrı `RecordingManager` + `EncoderManager` çifti yüklenir. 60 saniyelik her agent döngüsünde her modülün `run()` metodu çağrılır.

```
teqlif-agent (her 60s)
  ├── RecordingManager.run()   → aktif stream'leri izler, subscriber başlatır
  └── EncoderManager.run()     → _resolve_max_parallel() → encode + transfer
```

`RecordingManager._procs`: aktif subscriber process'leri tutar (rec_id → Process). Bu dict'in referansı agent.py'de `EncoderManager`'a geçirilir; aktif kayıt sayısı `len(self._recording_procs)` ile anlık okunur.

---

## SFU + Encoding Kaynak Rekabeti

| Kaynak | `nice 19` etkisi | Durum |
|--------|-----------------|-------|
| CPU cycles | Linux scheduler FFmpeg'i LiveKit SFU'nun arkasına iter | `encoder.py` ffmpeg komutuna `nice -n 19` ön eki eklenecek |
| Disk I/O | ionice ile G/Ç önceliği düşer | node2 backup servislerine uygulandı; node3/4 encoding'e uygulanmadı |
| Bellek bant genişliği | Etkilemez | H.264 encode bellek yoğun, risk devam eder |
| L3 cache | Etkilemez | Cache thrashing riski devam eder |

Dinamik parallelism ana savunma hattıdır: aktif kayıt varken N=1 ile FFmpeg hiç başlamaz. CPU rekabeti yalnızca N=1 encode koşarken geçerlidir; `nice -n 19` bu senaryoda garantili koruma sağlar.

`encoder.py`'de FFmpeg komutuna `nice` ön eki:

```python
cmd = ["nice", "-n", "19", "ffmpeg", "-hide_banner", "-loglevel", "warning", ...]
```

---

## cluster.yaml — Mevcut Kayıt Yapılandırması

```yaml
recording:
  enabled: true
  services:
    teqlif-livekit:
      livekit_ws_url:  ws://127.0.0.1:7880
      minio_host:      10.10.0.1:9000
      minio_bucket:    teqlif
      minio_alias:     teqlif-prod
      raw_dir:         /var/recordings/raw
      encoded_dir:     /var/recordings/encoded

  transfer_window_start_utc: 2
  transfer_window_end_utc:   5
  disk_warn_gb:      15
  disk_emergency_gb: 10
  user_access_hours: 24
  retention_days:    15
  minio_expiry_days: 2
```

Encoding penceresi transfer penceresiyle örtüşür; `transfer_window_*` değerleri yeniden kullanılır, ayrı alan gerekmez.

---

## Karar Özeti

### Post-Encoding Parallelism

| Durum | Parallelism | Kural |
|-------|------------|-------|
| Aktif kayıt var | 1 | SFU + subscriber VP8 encode CPU'yu paylaşıyor |
| Atıl (kayıt yok, normal saat) | 2 | Boşa harcanan CPU değerlendirilir |
| Atıl + bakım penceresi | 4 | Kuyruğu hızla temizle |
| Disk acil (< 10 GB) | 4 + pencere atla | Disk baskısı her şeyin önünde |

### Cluster Kapasite Sınırları

| İzleyici yoğunluğu | Node başına maks. eşzamanlı yayın | Cluster (node3+4) |
|--------------------|----------------------------------|-------------------|
| Boş / test (M≈0) | ~5 | ~10 |
| Normal (M≈50) | ~3 | ~6 |
| Yoğun mezat (M≈150) | ~2 | ~4 |

EdgeOrchestrator composite scoring (cpu %30 + katılımcı %70) ile yeni yayınları her zaman en az yüklü node'a yönlendirir. Sınırlar her node için bağımsız geçerlidir; cluster toplamı otomatik dağılımla belirlenir.
