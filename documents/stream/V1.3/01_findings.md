# Stream Kayıt Sistemi — V1.3 Bulgular

**Tarih:** 2026-10-08  
**Kapsam:** Kayıt yaşam döngüsü, node dağılımı, erişim kuralları, zorunlu kayıt mimarisi, eksik parçalar

---

## 1. Genel Mimari

Stream kayıt sistemi üç fiziksel katmana yayılmış:

| Katman | Node | Sorumluluk |
|--------|------|------------|
| Kayıt + Encode | node3 / node4 | FFmpeg WHEP kayıt, H.264 encode, MinIO transfer |
| Servis + API | node1 | Presigned URL üretimi, ARQ durum geçişleri |
| Backup | node2 | Günlük MinIO mirror (04:00 UTC) |

Her LiveKit node (3/4) kendi stream'lerini bağımsız kaydeder. `RecordingManager` lider seçimine bağlı değil.

---

## 2. Durum Makinesi

```
recording → encoding → encoded ⇄ transferring → available → expired → archived
                  ↘         ↗          ↘ (dosya yok)
                failed              failed
```

- `encoding → failed`: FFmpeg encode hatası
- `transferring → encoded`: `mc cp` hatası — bir sonraki pencerede yeniden denenir (retry döngüsü)
- `transferring → failed`: sadece encoded dosya fiziksel olarak kaybolmuşsa (nadir)
- `archived` son durum — satır silme (`deleted`) henüz implement edilmemiş (bkz. §2 DB'den Silinme)

### Durum Tanımları

| Durum | Aktör | Tetikleyici | Açıklama |
|-------|-------|-------------|----------|
| `recording` | teqlif-agent (recorder.py) | Stream `live` (her yayın — zorunlu) | FFmpeg WHEP bağlantısı açık, MKV `/var/recordings/raw/` yazılıyor |
| `encoding` | teqlif-agent (recorder.py) | FFmpeg kapanır (stream biter) | Ham MKV → H.264/AAC 720p MP4, `crf=23 preset=veryfast` |
| `encoded` | teqlif-agent (encoder.py) | Encode tamamlanır | Ham dosya silinir, transfer penceresi bekleniyor |
| `transferring` | teqlif-agent (encoder.py) | Transfer penceresi açılır | `mc cp` ile node1 MinIO'ya yükleniyor; hata → `encoded`'a geri döner |
| `available` | teqlif-agent (encoder.py) | `mc cp` başarılı | `available_at=NOW()`, `expires_at=NOW()+24h`, lokal encoded silinir |
| `expired` | ARQ (node1, her 30 dk, :00 ve :30) | `expires_at < NOW()` | API 410 döner, dosya MinIO'da hâlâ var |
| `archived` | ARQ (node1, her saat :15) | `transferred_at + 4 gün` geçince | MinIO lifecycle dosyayı silmiş, node2 backup'ı almış |
| `failed` | teqlif-agent | encoding hatası veya encoded dosya kaybolması | `error_message` dolu |

### DB'den Silinme

`janitor.py` `stream_recordings_15d` policy'si `archived_at + 15 gün` geçen satırları **sayar ve loglar**, silmez. "Gerçek silme cleanup_actions.sh ile" notu var ama bu script mevcut değil. `deleted_at` kolonu DB şemasında tanımlı, `deleted` durumu janitor.py comment'inde belirtilmiş — ancak geçiş kodu henüz implement edilmemiş. Mevcut sistemde satırlar `archived` olarak kalır.

---

## 3. Zaman Çizelgesi (Tipik Senaryo)

```
T+0h    Stream biter → recording → encoding başlar
T+?h    Encode tamamlanır → encoded
        (süre: yayın uzunluğuna bağlı, kısa yayınlarda dakikalar)

T+3h    Transfer penceresi açılır (UTC 03:00)
        → transferring → available

T+27h   expires_at geçer → expired
        (ARQ expire_recordings_task, her 30 dk çalışır)

T+4g    MinIO lifecycle siler
        node2 günlük 04:00 backup'ı almış
        → archived  (ARQ archive_recordings_task, her saat :15)

T+19g   janitor.py satırı sayar/loglar — silme implement edilmemiş (archived kalır)
```

### Transfer Penceresi Kuralları (UTC)

| Disk Durumu | Transfer Penceresi |
|-------------|-------------------|
| ≥ 15 GB boş | 03:00 – 08:00 |
| 10–15 GB boş | 02:00 – 08:00 (erken tetik) |
| < 10 GB boş | Her an (acil mod) |

---

## 4. Dosya Yolları

```
Kayıt (ham)   : /var/recordings/raw/{stream_id}_{timestamp}.mkv         (node3/4)
Encode        : /var/recordings/encoded/{stream_id}_{timestamp}.mp4      (node3/4)
minio_key     : recordings/{stream_id}/{filename}.mp4                    (bucket-relative)
MinIO (prod)  : bucket=teqlif  key=recordings/{stream_id}/{filename}.mp4 (node1)
Backup        : /project/teqlif/backups/minio/teqlif/recordings/…        (node2)
```

`minio_key` DB'de bucket adı **olmadan** saklanır (`recordings/…`). Bucket adı (`teqlif`) config'den (`minio_bucket`) ayrı gelir.

---

## 5. API Durumu

### Mevcut Endpoint

```
GET /streams/{stream_id}/recording
```

- Sadece `host_id == current_user.id` kontrolü var
- `status = 'available'` ise presigned URL döner (1 saat geçerli)
- `status = 'expired' / 'archived'` → 410 RECORDING_EXPIRED
- `recording_enabled = False` → 404 RECORDING_NOT_ENABLED
- Kayıt hazır değilse (`recording/encoding/encoded/transferring`) → 404 RECORDING_NOT_FOUND (sorgu sadece `available/expired/archived` döner)
- Yanıt: `{ recording_id, url, available_at, expires_at }` — `duration_secs` dönmüyor

### Eksik Endpoint'ler

1. **`GET /recordings/my`** — Host'un tüm kayıtlarını listeler (durum + süre + tarih)
2. **Durum polling** — Kayıt `encoding`/`encoded` aşamasındayken mobil "hazırlanıyor" gösteremez; 404 ile hazır arasındaki fark anlaşılamıyor

---

## 6. Erişim Kuralları (Karar)

| Kural | Açıklama |
|-------|----------|
| Sadece host | `host_id == current_user.id`; izleyiciler erişemez |
| Sadece PRO | Host PRO üye olmalı; mevcut endpoint'e PRO kontrolü **henüz eklenmedi** |
| 24 saat | `available_at` → `expires_at` arası; bu pencere dışında erişim yok |
| Sadece `available` | `expired`/`archived` durumunda presigned URL verilmez |

**İzleyici erişimi**: Bilinçli olarak kapsam dışı bırakıldı.  
*Gerekçe:* Müzayede yayınları gibi hassas içeriklerde host gizliliği, hukuki risk, içerik kontrolü.

---

## 7. PRO Araçları Entegrasyonu

Bu özellik **PRO Araçları** ekranında "Canlı Yayın & Kitle" accordion'ı altında "Canlı Yayınlarım" kartı olarak sunulacak.

### Kapsam
- Yalnızca PRO host'lar görür
- Kendi yaptığı yayınların kayıtları listelenir
- Kayıt `available` ise oynatılabilir; diğer durumlarda durum gösterimi

### PRO Hub Yerleşimi

"Yayın & Kitle" accordion'ı (`proHubTabAudience`, renk `0xFF14B8A6`) içinde 4. kart:

```dart
_ToolCard(
  icon: Icons.video_library_outlined,
  iconColor: const Color(0xFFF97316),  // turuncu — mevcut teal/purple/blue'dan farklı
  title: loc.t('proToolMyRecordingsTitle'),
  description: loc.t('proToolMyRecordingsDesc'),
  isPremium: isPremium,
  onTap: isPremium
      ? () => Navigator.push(...)
      : () => _showUpgrade(context),
)
```

Mevcut sıra: BestStreamTime → StreamAnalytics → Retargeting → **Canlı Yayınlarım**

### Ekran Yapısı

```
┌─────────────────────────────────┐
│  ← Canlı Yayınlarım             │
├─────────────────────────────────┤
│  ┌───────────────────────────┐  │
│  │  "12 Ekim — Sabah"        │  │
│  │  48:32  •  720p           │  │
│  │  [● Hazırlanıyor...]      │  │  ← recording/encoding/encoded
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  "11 Ekim — Öğlen"        │  │
│  │  1s 12dk  •  720p         │  │
│  │  [▶ İzle]  Son: 3s 14dk  │  │  ← available + countdown
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │  "10 Ekim — Akşam"        │  │
│  │  22:10  •  720p           │  │
│  │  Süresi Doldu             │  │  ← expired/archived, opacity 0.5
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### Status Chip Tasarımı

| `status` | Chip | Renk | Davranış |
|----------|------|------|---------|
| `recording / encoding / encoded` | `● Hazırlanıyor` | amber, pulse animasyonu | dokunulamaz |
| `available` | `▶ İzle` | teal button | player'a git |
| `available`, son 2 saat | `▶ İzle · 1s 45dk` | orange, countdown | player'a git |
| `expired / archived` | `Süresi Doldu` | tertiary, opacity 0.5 | dokunulamaz |

Countdown: `expires_at - DateTime.now()`, `Timer.periodic(1min)` ile UI güncellenir. Oynatma sırasında expire olursa card anında `expired` state'e geçer.

---

## 8. Mobil Caching Stratejisi

### Karar: Video Dosyasını Değil, Presigned URL'i Cache'le

Video dosyasını indirip saklamak uygunsuz:
- 720p 1 saatlik yayın ≈ 2–4 GB — telefon depolaması ve izin yönetimi gerektirir
- Kayıt genellikle bir kez izleniyor; çevrimdışı kullanım senaryosu yok
- `flutter_downloader` + dosya temizliği ek karmaşıklık

**Doğru yaklaşım:** Presigned URL'i Hive'da cache'le; `expires_at` API hit öncesi guard görevi yapsın.

### Cache Katmanları

**Katman 1 — Liste cache** (`GET /recordings/my`)
```
CacheService.saveData('recordings:my', data, ttl: Duration(minutes: 3))
```
Mevcut `CacheService` (Hive + TTL zarfı) doğrudan kullanılabilir.

**Katman 2 — Presigned URL cache** (oynatma isteği)
```
key:  'recording_url:{stream_id}'
data: { url: "https://...", expires_at: <unix ms> }
ttl:  55 dakika  (presigned URL 60dk — 5dk güvenlik payı)
```

**Katman 3 — `expires_at` guard** (API'ye gitmeden önce kontrol)
```dart
Future<String?> getPlayUrl(String streamId) async {
  final cached = CacheService.getData('recording_url:$streamId');
  if (cached != null) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(cached['expires_at']);
    if (DateTime.now().isAfter(expiresAt)) {
      await CacheService.clearData('recording_url:$streamId');
      return null; // süresi doldu, API'ye bile gitme
    }
    return cached['url']; // cache hit — node1'e istek yok
  }
  // cache miss → API çağrısı + kaydet
}
```

**Katman 4 — 403 recovery** (oynatma sırasında URL expire olursa)
```dart
// video_player error callback:
if (error.contains('403')) {
  await CacheService.clearData('recording_url:$streamId');
  final freshUrl = await getPlayUrl(streamId);
  controller.setDataSource(freshUrl);
}
```

### Node1 Yük Azalması

| Senaryo | Mevcut | Cache sonrası |
|---------|--------|---------------|
| Liste açılır | Her seferinde API | 3 dk içinde 0 istek |
| Aynı video tekrar oynatılır | Her seferinde presigned URL isteği | 55 dk içinde 0 istek |
| Süresi dolmuş video açılır | API isteği + 410 yanıtı | API'ye bile gitmez |
| İlk kez oynatma | 1 API isteği | 1 API isteği (kaçınılmaz) |

---

## 9. Yapılacaklar

### Backend — Zorunlu Kayıt Migrasyonu

- [ ] Alembic: `live_streams.recording_enabled` kolonu kaldırılır
- [ ] `StartStreamRequest` şemasından `recording_enabled` kaldırılır
- [ ] `start_stream` use case'den `recording_enabled` parametresi kaldırılır
- [ ] `RecordingManager._sync_recordings()`: `AND ls.recording_enabled = TRUE` filtresi kaldırılır
- [ ] `GET /streams/{id}/recording`: `recording_enabled` kontrolü → PRO kontrolü ile değiştirilir

### Backend — Yeni Özellikler

- [ ] `encoder.py`: encode sonrası `ffprobe` ile `duration_secs` hesaplanıp DB'ye yazılır (şu an daima NULL)
- [ ] `GET /recordings/my` endpoint — host'un kayıtlarını listeler
  - Alanlar: `stream_id`, `status`, `duration_secs`, `encoded_size_bytes`, `available_at`, `expires_at`, `recording_started_at`
  - Filtre: `status IN ('recording','encoding','encoded','available','expired')`, son 30 gün

### Mobile

- [ ] `pro_hub_screen.dart`: "Yayın & Kitle" accordion'ına 4. `_ToolCard` eklenir (`video_library_outlined`, `0xFFF97316`)
- [ ] `MyRecordingsScreen`: kayıt listesi + `RecordingCard` widget (status chip + countdown)
- [ ] `RecordingsCacheService`: 4 katmanlı cache, mevcut `CacheService` üzerine
- [ ] Video oynatıcı ekranı (presigned URL → `video_player` + `chewie`)
- [ ] ARB anahtarları (TR/EN/AR/RU): `proToolMyRecordingsTitle`, `proToolMyRecordingsDesc`, `recordingStatusPreparing`, `recordingStatusWatch`, `recordingStatusExpired`, `recordingStatusExpiresIn`

---

## 10. Zorunlu Kayıt Mimarisi (Mimari Karar)

### Karar

Canlı yayın kaydı **host tercihine bırakılmıyor**. Her yayın sistem tarafından otomatik kaydedilir. Bu bir hukuki ve operasyonel zorunluluktur:

- Müzayede anlaşmazlıkları, fiyat itirazları
- İçerik moderasyonu ve kullanıcı şikayetleri
- Platform koruması, dolandırıcılık tespiti

### Mevcut Tasarımın Sorunu

Şu an kayıt yapılması ile kayda erişim izni tek bir boolean'a (`recording_enabled`) bağlanmış:

```
recording_enabled = True  →  HEM kayıt yap  HEM izlemeye izin ver   ← YANLIŞ
recording_enabled = False →  NE kayıt yap   NE izlemeye izin ver    ← YANLIŞ
```

Bu iki bağımsız karar aynı alana sıkıştırılmış.

### Doğru Ayrım

| Karar | Kim verir | Kural |
|-------|-----------|-------|
| Kayıt yap | **Sistem** | Her yayın, her zaman |
| İzleme izni | **PRO statüsü** | Sadece PRO host, 24h penceresi |

### recording_enabled Kolonuna Etkisi

`recording_enabled` kolonu dört yerde kullanılıyor; tamamı değişmeli:

| Yer | Mevcut | Hedef |
|-----|--------|-------|
| `live_streams` DB kolonu | `default=False` | Kaldırılacak (alembic migration) |
| `StartStreamRequest` şeması | İsteğe bağlı alan | Kaldırılacak |
| `start_stream` use case | DB'ye yazıyor | Kaldırılacak |
| `RecordingManager._sync_recordings()` | `AND ls.recording_enabled = TRUE` | Filtre kaldırılacak — tüm live stream'ler kaydedilir |
| `GET /streams/{id}/recording` | `recording_enabled` kontrolü | PRO kontrolü ile değiştirilecek |

### Depolama Etkisi

Tüm yayınların kaydedilmesi depolama baskısı yaratmaz çünkü:
- node3/4 lokal disk: encode biter bitmez MinIO'ya taşınıp silinir (geçici)
- MinIO: 4 günlük lifecycle — otomatik silinme
- node2 backup: 04:00 UTC mirror, 15 günlük DB retention

Ek önlem: `duration_secs < 60` olan yayınlar encode adımında atlanabilir (terk edilmiş kısa yayınlar).

### Mobile Etkisi

`recording_enabled` mobil kodda kullanılmıyor (grep: sıfır sonuç). Mobil tarafında değişiklik gerekmez.

---

## 11. Bilinen Kısıtlar

| Kısıt | Açıklama |
|-------|----------|
| Transfer gecikme | Yayın gece bitiyor ve disk ≥15 GB ise kayıt sabah 03:00'a kadar hazır değil |
| Tek encode slot | `_MAX_PARALLEL = 1` — aynı anda birden fazla yayın biterse sıra oluşur |
| Agent restart | `recording` durumundaki kayıtlar `failed`'a çekilir; yeniden kayıt başlamaz |
| Transfer retry | `mc cp` hatası → `encoded`'a geri döner + Telegram alert; bir sonraki transfer penceresi yeniden dener |
| `duration_secs` NULL | encoder.py `ffprobe` çalıştırmıyor; alan her zaman NULL — `GET /recordings/my` önce bu alanı doldurmalı |
| Satır silme yok | `archived` final durum; `deleted` geçişi implement edilmemiş (`cleanup_actions.sh` mevcut değil) |
| Presigned TTL | URL 1 saat geçerli; oynatma sırasında süresi dolarsa mobil yeniden istemeli |
| Staging | node5'te ayrı `teqlif-staging` bucket, aynı pipeline |
