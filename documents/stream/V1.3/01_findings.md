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
recording → encoding → encoded → transferring → available → expired → archived
                  ↘                       ↘
                failed                  failed
```

### Durum Tanımları

| Durum | Aktör | Tetikleyici | Açıklama |
|-------|-------|-------------|----------|
| `recording` | teqlif-agent (recorder.py) | Stream `live` (her yayın — zorunlu) | FFmpeg WHEP bağlantısı açık, MKV `/var/recordings/raw/` yazılıyor |
| `encoding` | teqlif-agent (recorder.py) | FFmpeg kapanır (stream biter) | Ham MKV → H.264/AAC 720p MP4, `crf=23 preset=veryfast` |
| `encoded` | teqlif-agent (encoder.py) | Encode tamamlanır | Ham dosya silinir, transfer penceresi bekleniyor |
| `transferring` | teqlif-agent (encoder.py) | Transfer penceresi açılır | `mc cp` ile node1 MinIO'ya yükleniyor |
| `available` | teqlif-agent (encoder.py) | `mc cp` başarılı | `available_at=NOW()`, `expires_at=NOW()+24h`, lokal encoded silinir |
| `expired` | ARQ (node1, her 30 dk) | `expires_at < NOW()` | API 410 döner, dosya MinIO'da hâlâ var |
| `archived` | ARQ (node1, her saat :15) | `transferred_at + 4 gün` geçince | MinIO lifecycle dosyayı silmiş, node2 backup'ı almış |
| `failed` | teqlif-agent | Herhangi bir adımda hata | `error_message` dolu, `retry_count` artıyor |

### DB'den Silinme
`janitor.py` — `archived_at + 15 gün` sonra `stream_recordings` satırı silinir.

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

T+19g   janitor.py → DB satırı silinir
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
Kayıt (ham)   : /var/recordings/raw/{stream_id}_{timestamp}.mkv    (node3/4)
Encode        : /var/recordings/encoded/{stream_id}_{timestamp}.mp4 (node3/4)
MinIO (prod)  : teqlif/recordings/{stream_id}/{filename}.mp4        (node1)
Backup        : /project/teqlif/backups/minio/teqlif/recordings/…   (node2)
```

---

## 5. API Durumu

### Mevcut Endpoint

```
GET /streams/{stream_id}/recording
```

- Sadece `host_id == current_user.id` kontrolü var
- `status = 'available'` ise presigned URL döner (1 saat geçerli)
- `status = 'expired' / 'archived'` → 410 RECORDING_EXPIRED
- `recording_enabled = False` → 404
- Kayıt henüz hazır değilse (`recording/encoding/encoded`) → 404 RECORDING_NOT_FOUND

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

Bu özellik **PRO Araçları** ekranında "Yayın Tekrarları" bölümü olarak sunulacak.

### Kapsam
- Yalnızca PRO host'lar görür
- Kendi yaptığı yayınların kayıtları listelenir
- Kayıt `available` ise oynatılabilir; diğer durumlarda durum gösterimi

### Mobil Ekran Gereksinimleri

```
PRO Araçları
└── Yayın Tekrarları
    ├── [Hazırlanıyor]  status: recording / encoding / encoded
    ├── [İzle]          status: available  (expires_at'a kadar geri sayım)
    └── [Süresi Doldu]  status: expired / archived
```

---

## 8. Yapılacaklar

### Backend — Zorunlu Kayıt Migrasyonu

- [ ] Alembic: `live_streams.recording_enabled` kolonu kaldırılır
- [ ] `StartStreamRequest` şemasından `recording_enabled` kaldırılır
- [ ] `start_stream` use case'den `recording_enabled` parametresi kaldırılır
- [ ] `RecordingManager._sync_recordings()`: `AND ls.recording_enabled = TRUE` filtresi kaldırılır
- [ ] `GET /streams/{id}/recording`: `recording_enabled` kontrolü → PRO kontrolü ile değiştirilir

### Backend — Yeni Özellikler

- [ ] `GET /recordings/my` endpoint — host'un kayıtlarını listeler
  - Alanlar: `stream_id`, `status`, `duration_secs`, `encoded_size_bytes`, `available_at`, `expires_at`, `recording_started_at`
  - Filtre: `status IN ('recording','encoding','encoded','available','expired')`, son 30 gün

### Mobile

- [ ] PRO Araçları ekranına "Yayın Tekrarları" bölümü
- [ ] Kayıt durumu widget'ı (hazırlanıyor / izle / süresi doldu)
- [ ] Video oynatıcı ekranı (presigned URL → in-app player)
- [ ] ARB anahtarları (TR/EN/AR/RU)

---

## 9. Zorunlu Kayıt Mimarisi (Mimari Karar)

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

## 10. Bilinen Kısıtlar

| Kısıt | Açıklama |
|-------|----------|
| Transfer gecikme | Yayın gece bitiyor ve disk ≥15 GB ise kayıt sabah 03:00'a kadar hazır değil |
| Tek encode slot | `_MAX_PARALLEL = 1` — aynı anda birden fazla yayın biterse sıra oluşur |
| Agent restart | `recording` durumundaki kayıtlar `failed`'a çekilir; yeniden kayıt başlamaz |
| Presigned TTL | URL 1 saat geçerli; oynatma sırasında süresi dolarsa mobil yeniden istemeli |
| Staging | node5'te ayrı `teqlif-staging` bucket, aynı pipeline |
