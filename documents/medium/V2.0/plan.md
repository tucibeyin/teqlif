# Teqlif Media Limitleri — V2.0 Plan

**Amaç:** Kısıtlı kaynaklarla endüstri standartlarına yaklaşmak.  
Sıkıştırma, açık kaynak kütüphaneler ve codec optimizasyonu kullanılacak.  
**Referans cihaz:** iPhone 15 Pro (default kamera/ses ayarları)  
**Tarih:** 2026-09-06

---

## 1. Mevcut Teqlif Limitleri (Başlangıç Noktası)

### Backend — `backend/app/constants/media_limits.py`

| Değişken | Değer |
|----------|-------|
| `IMAGE_MAX_BYTES` | 5 MB |
| `VIDEO_MAX_BYTES` | 20 MB (DM) |
| `LISTING_VIDEO_MAX_BYTES` | 100 MB (İlan, ham input) |
| `VOICE_MAX_BYTES` | 512 KB |
| `FILE_MAX_BYTES` | 5 MB |
| `VIDEO_MAX_SECS` | 15 sn |
| `VOICE_MAX_SECS` | 30 sn |

### Flutter — `mobile/lib/core/media_constants.dart`

| Sabit | Değer |
|-------|-------|
| `imageMaxBytes` | 5 MB |
| `videoMaxBytes` | 20 MB |
| `listingVideoMaxBytes` | 100 MB |
| `voiceMaxBytes` | 512 KB |
| `fileMaxBytes` | 5 MB |
| `videoMaxSecs` | 15 sn |
| `voiceMaxSecs` | 30 sn |

### Flutter Picker Ayarları

| Ekran | Medya | imageQuality | maxWidth/Height | Sıkıştırma |
|-------|-------|-------------|-----------------|------------|
| İlan Ver / Düzenle | Fotoğraf | 85 | 1200×1200 | image_picker resize |
| İlan Ver / Düzenle | Video | — | — | ffmpeg backend |
| Mesajlaşma | Fotoğraf | 85 | **YOK** | yok |
| Mesajlaşma | Video | — | — | MediumQuality (720p) |
| Mesajlaşma | Dosya | — | — | yok |
| Mesajlaşma | Ses | — | — | m4a/AAC default |
| Profil | Fotoğraf | 85 | **YOK** | yok |

---

## 2. Endüstri Karşılaştırma Matrisi

### Fotoğraf — Mesajlaşma

| Kriter | Teqlif | WhatsApp | Telegram | Signal | Instagram DM |
|--------|--------|----------|----------|--------|-------------|
| Upload limiti | 5 MB | 16 MB | 10 MB / 2 GB (dosya) | 100 MB | ~4 MB |
| Gönderilen çıktı | Orijinal | ~100–300 KB (sıkıştırılmış) | ~400 KB | Orijinal | ~400 KB |
| maxWidth/Height | **YOK** | N/A | N/A | N/A | N/A |
| iPhone 15 Pro uyumu | ⚠️ Sınırda | ✅ | ✅ | ✅ | ✅ |

### Video — Mesajlaşma

| Kriter | Teqlif | WhatsApp | Telegram | Signal | Instagram DM |
|--------|--------|----------|----------|--------|-------------|
| Upload limiti | 20 MB | 16 MB | 2 GB | 1 GB | ~100 MB |
| Süre limiti | **15 sn** | ~90 sn | Süresiz | Süresiz | 5 dk |
| Sıkıştırma | MediumQuality 720p | Kendi | Seçime bağlı | Kendi | Kendi |
| iPhone 15 Pro uyumu | ✅ (sıkıştırma sonrası ~4 MB) | ✅ | ✅ | ✅ | ✅ |

### Sesli Mesaj

| Kriter | Teqlif | WhatsApp | Telegram | Signal |
|--------|--------|----------|----------|--------|
| Boyut limiti | **512 KB** | Belirtilmiyor | Belirtilmiyor | Belirtilmiyor |
| Süre limiti | **30 sn** | **16 dk** | 60 dk | Süresiz |
| Format | m4a/AAC | .opus | .ogg | .opus |
| iPhone 30 sn uyumu | ⚠️ Riskli | ✅ | ✅ | ✅ |

### Dosya — Mesajlaşma

| Kriter | Teqlif | WhatsApp | Telegram | Signal | Discord (free) |
|--------|--------|----------|----------|--------|----------------|
| Boyut limiti | **5 MB** | **2 GB** | **2 GB** | 1 GB | 25 MB |
| İzin verilen formatlar | pdf, doc, docx, xls, xlsx, txt | Tümü | Tümü | Tümü | Tümü |
| Gerçek kullanım uyumu | ❌ Kısıtlayıcı | ✅ | ✅ | ✅ | ⚠️ |

### İlan Fotoğrafı

| Kriter | Teqlif | Sahibinden | Facebook Marketplace | eBay |
|--------|--------|------------|---------------------|------|
| Max boyut/fotoğraf | 5 MB | 10 MB | ~4 MB | 7 MB |
| Max fotoğraf adedi | **10** | 20 | 10 | 24 |
| Resize (picker) | maxWidth: 1200 | — | — | — |
| iPhone 15 Pro uyumu | ✅ (~1–2 MB sonuç) | ✅ | ✅ | ✅ |

### İlan Videosu

| Kriter | Teqlif | Sahibinden | Facebook Marketplace | eBay |
|--------|--------|------------|---------------------|------|
| Ham upload limiti | 100 MB | Belirtilmiyor | 4 GB | 500 MB |
| Süre limiti | **15 sn** | ~1 dk | 10 dk | 30 sn |
| iPhone 15 Pro 4K 30fps | ⚠️ Sınırda (~100 MB) | ✅ | ✅ | ✅ |
| iPhone 15 Pro 4K 60fps | ❌ Reddedilir | ✅ | ✅ | ✅ |

---

## 3. Kritik Açıklar — Öncelik Sırası

| # | Sorun | Teqlif | Endüstri Standardı | Önem |
|---|-------|--------|--------------------|------|
| A | Sesli mesaj süresi | 30 sn | WhatsApp: 16 dk | 🔴 Kritik |
| B | Dosya boyutu | 5 MB | WhatsApp/Telegram: 2 GB | 🔴 Kritik |
| C | Mesajlaşma video süresi | 15 sn | WhatsApp: ~90 sn | 🟠 Önemli |
| D | Fotoğraf maxWidth/Height yok | yok | — | 🟠 Önemli |
| E | İlan video süresi | 15 sn | eBay: 30 sn, FB: 10 dk | 🟡 Değerlendirilebilir |
| F | İlan video ham limiti | 100 MB | 4K 60fps aşar | 🟡 Değerlendirilebilir |
| G | Sesli mesaj boyutu | 512 KB | Süre bazlı olmalı | 🟡 A ile çözülür |

---

## 4. Kararlar

---

### A — Sesli Mesaj ✅ KARAR VERİLDİ

**Karar: Seçenek B — Opus codec, ffmpeg_kit_flutter_audio**

#### Codec Karşılaştırması

| Codec | 10 dk boyut | Kalite | Kim kullanıyor |
|-------|-------------|--------|----------------|
| AAC 64 kbps (mevcut) | 4.8 MB | İyi | — |
| AAC 24 kbps / 16 kHz | 1.8 MB | Yeterli | — |
| **Opus 16 kbps** | **1.2 MB** | **Çok iyi** | **WhatsApp, Telegram** |
| Opus 24 kbps | 1.8 MB | Mükemmel | Signal |

#### Pipeline

```
KAYIT           COMPRESS                TRANSFER    DEPOLAMA    OYNATMA
─────           ─────────               ────────    ────────    ───────
record pkg  →   m4a geçici (AAC)   →   ffmpeg_kit  →  HTTP  →  MinIO  →  audioplayers
                                        opus 16kbps               .opus    (.opus)
                                        (1-2 sn işlem)
```

#### Depolama / Network Etkisi

| | 10 dk ses | 1000 mesaj/gün | Aylık depolama |
|-|-----------|----------------|----------------|
| Mevcut (AAC 64k) | 4.8 MB | 4.8 GB | 144 GB |
| **Opus 16k (yeni)** | **1.2 MB** | **1.2 GB** | **36 GB** |
| Tasarruf | — | %75 | %75 |

#### Yeni Limitler

| Parametre | Eski | Yeni |
|-----------|------|------|
| `VOICE_MAX_BYTES` | 512 KB | 2 MB |
| `VOICE_MAX_SECS` | 30 sn | 10 dk (600 sn) |
| `voiceMaxBytes` (Flutter) | 512 KB | 2 MB |
| `voiceMaxSecs` (Flutter) | 30 sn | 600 sn |
| Format | m4a (AAC) | .opus |
| Bitrate | ~64 kbps | 16 kbps (VBR) |
| Kütüphane | `record` | `record` + `ffmpeg_kit_flutter_audio` |

#### İzin verilecek MIME types (backend)
- `audio/ogg`
- `audio/opus`
- `audio/mp4` (m4a fallback)

---

### B — Dosya Boyutu ✅ KARAR VERİLDİ

**Karar: 50 MB, .zip eklenmeyecek**

**Gerekçe:**
- 3 günlük medya silme politikası → anlık max depolama ~15 GB (yönetilebilir)
- docx/xlsx/pdf zaten dahili sıkıştırma kullanıyor — client-side sıkıştırma ROI'si sıfır
- .zip kullanıcı ihtiyacı belirsiz, izin listesi sade kalıyor

**Yeni limitler:**

| Parametre | Eski | Yeni |
|-----------|------|------|
| `FILE_MAX_BYTES` | 5 MB | 50 MB |
| `fileMaxBytes` (Flutter) | 5 MB | 50 MB |
| İzin verilen formatlar | pdf, doc, docx, xls, xlsx, txt | Aynı (zip eklenmedi) |

**Depolama etkisi (3 günlük retention ile):**

| | Günlük yük | Anlık max depolama |
|-|------------|-------------------|
| Eski (5 MB) | 500 MB/gün | 1.5 GB |
| **Yeni (50 MB)** | **5 GB/gün** | **15 GB** |

### C + D + Genel — Generic MediaCompressor Pipeline ✅ KARAR VERİLDİ

**Karar: Tüm medya giriş noktaları tek bir `MediaCompressor` servisinden geçecek.**

---

#### Codebase'deki Tüm Medya Giriş Noktaları

| # | Dosya | Satır | Tip | Mevcut Sıkıştırma | Pipeline'a giriyor mu? |
|---|-------|-------|-----|-------------------|------------------------|
| 1 | `profile_screen.dart` | 2469 | image | imageQuality:85, **maxW/H yok** | ✅ ffmpeg |
| 2 | `create_listing_screen.dart` | 770/779 | image | imageQuality:85, maxW/H:1200 | ✅ ffmpeg |
| 3 | `create_listing_screen.dart` | 662/666 | video | maxDuration:15s, **sıkıştırma yok** | ✅ ffmpeg (CRF23 1080p) |
| 4 | `edit_listing_screen.dart` | 573/583 | image | imageQuality:85, maxW/H:1200 | ✅ ffmpeg |
| 5 | `edit_listing_screen.dart` | 456/461 | video | maxDuration:15s, **sıkıştırma yok** | ✅ ffmpeg (CRF23 1080p) |
| 6 | `messages_screen.dart` | 1571 | image | imageQuality:85 + FlutterImageCompress (çift!) | ✅ ffmpeg (ikisi birden kalkar) |
| 7 | `messages_screen.dart` | 1629 | video | VideoCompress MediumQuality | ✅ ffmpeg |
| 8 | `messages_screen.dart` | 1691 | file | yok | ❌ (sıkıştırma anlamsız) |
| 9 | `messages_screen.dart` | 1723 | voice | AAC 64kbps 44.1kHz stereo | ✅ ffmpeg → Opus |
| 10 | `story_tray.dart` | 99 | image | imageQuality:85, maxW/H:1920 | ✅ ffmpeg |
| 11 | `story_tray.dart` | 145 | video | VideoCompress DefaultQuality | ✅ ffmpeg |
| 12 | `host_stream_screen.dart` | 969 | thumbnail (PNG capture) | yok | ⚠️ ffmpeg önerilmez (in-memory) |
| 13 | `host_stream_screen.dart` | 1003 | proof (PNG capture) | yok | ⚠️ ffmpeg önerilmez (in-memory) |

**12–13 neden pipeline dışı:** `RepaintBoundary.toImage()` in-memory PNG üretir, geçici dosya gerektirmeyen doğrudan bytes upload'u daha hızlı. ffmpeg disk I/O eklemesi bu küçük dosyalar için anlamsız.

---

#### Kaldırılacak Paketler

| Paket | Durum | Neden |
|-------|-------|-------|
| `video_compress` | **Kaldırılır** | ffmpeg_kit ile ikame |
| `flutter_image_compress` | **Kaldırılır** | ffmpeg_kit ile ikame |

---

#### Eklenecek Paket

| Paket | Neden |
|-------|-------|
| `ffmpeg_kit_flutter_min` | Hem H.264 (video) hem Opus (ses) hem JPEG (foto) desteği, ~20–25 MB |

---

#### MediaCompressor Servis Tasarımı

**`mobile/lib/services/media_compressor.dart`**

```dart
enum MediaCompressType { voice, dmVideo, dmPhoto, listingPhoto, listingVideo, storyPhoto, storyVideo }

class CompressedMedia {
  final File file;
  final String mimeType;      // image/jpeg | video/mp4 | audio/ogg
  final String extension;     // jpg | mp4 | opus
  final int originalBytes;
  final int compressedBytes;
  final int? durationMs;
  final int? width;
  final int? height;
}

class MediaCompressor {
  static Future<CompressedMedia> compress(String inputPath, MediaCompressType type);
}
```

---

#### ffmpeg Komutları (tip bazında)

```bash
# VOICE: m4a → opus 16kbps VBR, mono, 16kHz
-i input.m4a -c:a libopus -b:a 16k -vbr on -application voip
-ac 1 -ar 16000 output.opus

# DM VIDEO: original → mp4, H.264 CRF28, 720p, max 90s
-i input.mov -c:v libx264 -crf 28 -preset fast
-vf scale=-2:720 -c:a aac -b:a 64k -t 90 output.mp4

# DM / PROFİL / İLAN FOTO: herhangi → jpeg, max 1200px, EXIF temiz
-i input.heic -vf scale='min(1200\,iw):-2' -q:v 4 -map_metadata -1 output.jpg

# STORY FOTO: herhangi → jpeg, max 1920px, EXIF temiz
-i input.heic -vf scale='min(1920\,iw):-2' -q:v 3 -map_metadata -1 output.jpg

# STORY VIDEO: original → mp4, H.264 CRF28, 720p, max 15s
-i input.mov -c:v libx264 -crf 28 -preset fast
-vf scale=-2:720 -c:a aac -b:a 64k -t 15 output.mp4

# İLAN VİDEOSU: original → mp4, H.264 CRF23, 1080p, max 60s, EXIF temiz
-i input.mov -c:v libx264 -crf 23 -preset fast
-vf scale=-2:1080 -c:a aac -b:a 128k -t 60 -map_metadata -1 output.mp4
```

---

#### Yeni Limitler (C ve D dahil)

| Medya | Süre | Boyut | Değişiklik |
|-------|------|-------|------------|
| Sesli mesaj | **10 dk** | **2 MB** | A kararı |
| DM video | **90 sn** | **30 MB** | C kararı |
| DM fotoğraf | — | **5 MB** | D kararı (ffmpeg resize ile sorun kalmaz) |
| Profil fotoğrafı | — | **5 MB** | ffmpeg 1200px ile sorun kalmaz |
| İlan fotoğrafı | — | **5 MB** | ffmpeg 1200px (mevcut ile aynı) |
| Story fotoğraf | — | **5 MB** | ffmpeg 1920px |
| Story video | 15 sn | **20 MB** | ffmpeg CRF28 |
| İlan videosu | **60 sn** | **50 MB** | E+F kararı |
| Dosya | — | **50 MB** | B kararı |

---

#### Backend Değişiklikleri

| Parametre | Eski | Yeni |
|-----------|------|------|
| `VIDEO_MAX_BYTES` | 20 MB | 30 MB |
| `VIDEO_MAX_SECS` | 15 sn | 90 sn |
| `VOICE_MAX_BYTES` | 512 KB | 2 MB |
| `VOICE_MAX_SECS` | 30 sn | 600 sn |
| `FILE_MAX_BYTES` | 5 MB | 50 MB |
| `LISTING_VIDEO_MAX_BYTES` | 100 MB | 50 MB |
| `LISTING_VIDEO_MAX_SECS` | 15 sn | 60 sn |
| Kabul edilen voice MIME | audio/mp4 | audio/ogg, audio/opus, audio/mp4 |

---

### E — İlan Video Süresi ✅ KARAR VERİLDİ

**Karar: 60 saniye (15s → 60s)**

İlan videosu pipeline'a giriyor: `MediaCompressType.listingVideo` → CRF23, 1080p, max 60s, EXIF temizlenir.

| | Süre | Çıktı boyutu (tahmin) |
|-|------|----------------------|
| Eski | 15 sn | 100 MB ham (sıkıştırma yoktu) |
| **Yeni** | **60 sn** | **~25–40 MB** (CRF23 H.264 1080p) |

Backend `_process_listing_video` değişikliği: artık sadece **remux + faststart + thumbnail** (`-c:v copy`) — sıkıştırma client tarafında yapıldığı için backend re-encode yapmaz.

### F — İlan Video Ham Limiti ✅ KARAR VERİLDİ

**Karar: 50 MB** (100 MB → 50 MB)

Client CRF23 1080p sıkıştırdıktan sonra 60 saniyelik bir video ~25–40 MB olur. 50 MB bol kesimden yeterli ve MinIO/bant genişliği maliyetini düşürür.

| Parametre | Eski | Yeni |
|-----------|------|------|
| `LISTING_VIDEO_MAX_BYTES` | 100 MB | **50 MB** |
| `LISTING_VIDEO_MAX_SECS` | 15 sn | **60 sn** |

---

## UI/UX Kararları

### İ1 — İki Fazlı Progress (Sıkıştırma + Yükleme) ✅ KARAR VERİLDİ

**Karar: Tek bar, değişen etiket (Seçenek A)**

Sıkıştırma ve yükleme tek bir `LinearProgressIndicator` üzerinden gösterilir. Faz etiketi değişir:

```
[████████░░░░░░░░░░░░] %45   "Hazırlanıyor..."
[████████████████░░░░] %72   "Yükleniyor..."
```

**Etkilenen ekranlar:**
- `create_listing_screen.dart` — mevcut `LinearProgressIndicator` korunur, etiket eklenir
- `edit_listing_screen.dart` — aynı
- `messages_screen.dart` — video için yeni progress bar eklenir (şu an yok)
- `story_tray.dart` — spinner yerini progress bar alır

**State akışı:**
- `compressionProgressProvider` (0.0–1.0) → etiket "Hazırlanıyor..."
- Upload progress (0.0–1.0) → etiket "Yükleniyor..."
- `null` → bar gizlenir

### İ2 — İptal Butonu ✅ KARAR VERİLDİ

**Karar: Yalnızca video sıkıştırmasında iptal butonu gösterilir.**

| Ekran | Medya | İptal UI |
|-------|-------|----------|
| `create_listing_screen.dart` | İlan videosu | Progress bar yanında "İptal" butonu |
| `edit_listing_screen.dart` | İlan videosu | Progress bar yanında "İptal" butonu |
| `messages_screen.dart` | DM video | Attach butonu yerini iptal butonuna bırakır |
| `messages_screen.dart` | Foto / Ses | ❌ gösterilmez (< 1 sn) |
| `story_tray.dart` | Story video | ❌ gösterilmez (< 3 sn, akışı kesmez) |

### İ3 — Ses Kaydı Uyarı Eşiği ✅ KARAR VERİLDİ

**Karar: 30 saniye** (`messages_screen.dart:2648` → `remaining <= 30`)

10 dk kayıtta 10 sn çok ani, 60 sn fazla erken. 30 sn kullanıcıya son cümlesini tamamlamak için yeterli süre verir.

### İ4 — DM Video Progress UI ✅ KARAR VERİLDİ

**Karar: Chat bubble'da optimistik thumbnail + progress bar (Seçenek A)**

Foto ile tutarlı pattern — kullanıcı video gönderirken chatı görmeye devam eder.

```
[Video thumbnail (lokal önizleme)]
[████████░░░░░░░░░░░░] %45  Hazırlanıyor...
```

- Sıkıştırma başlar başlamaz bubble optimistik olarak chat listesine eklenir
- `compressionProgressProvider` → "Hazırlanıyor..." + %
- Upload başlayınca → "Yükleniyor..." + %
- Tamamlanınca thumbnail + play ikonu gösterilir
- İptal edilirse bubble kaldırılır
- Video bubble'da thumbnail yüklenirken `ShimmerBox` placeholder gösterilir (`messages_screen.dart:2001` — şu an placeholder yok, siyah boşluk görünüyor)

### İ5 — Story Tray Progress UI ✅ KARAR VERİLDİ

**Karar: `storyProcessing` snackbar kaldırılır, avatar spinner yeterli.**

`story_tray.dart:168` snackbar silinir. Avatar üzerindeki `CircularProgressIndicator` (satır 424–432) sıkıştırma + yükleme süresince görünmeye devam eder. Story akışı < 5 sn toplam — ek progress UI gerekmez.

### İ6 — ARB Key Güncellemeleri ✅ KARAR VERİLDİ

4 dilde (TR/EN/AR/RU) güncellenmesi gereken key'ler:

| Key | Eski | Yeni |
|-----|------|------|
| `attachLimitVideo` | "15 sn • 20 MB" | "90 sn • 30 MB" |
| `attachLimitVoice` | "30 sn • 512 KB" | "10 dk • 2 MB" |
| `attachLimitFile` | "5 MB" | "50 MB" |
| `attachLimitImage` | değişmez | — |

`videoLabel` ve `createPickCamera` key'leri `{sec}` parametresi kullandığından `_maxVideoDurationSecs` sabiti güncellenince otomatik düzelir — ARB değişikliği gerekmez.

---

## Display Bug Listesi

Media pipeline ile birlikte ele alınacak mevcut display sorunları.

### B1 — `retargeting_screen.dart` — `Image.network()` yerine `CachedNetworkImage`

**Satırlar:** 169, 1013

`Image.network()` kullanılıyor — disk/memory cache yok, placeholder yok, ağ değişiminde yeniden indirilir. `CachedNetworkImage` + `TeqlifCacheManager` + `ShimmerBox` placeholder ile değiştirilecek.

---

### B2 — `profile_screen.dart:4496` — Hardcoded domain

```dart
// YANLIŞ — staging/prod'da kırılır
'https://teqlif.com$imageUrl'

// DOĞRU
imgUrl(imageUrl)
```

`imgUrl()` helper'ı relative path'i ortama göre çözümler. Push notification detay bottom sheet'inde kullanılıyor.

---

### B3 — `swipe_live_screen.dart:2014` — Listing thumbnail placeholder yok

DM listing thumbnail gösteriminde `placeholder` ve `errorWidget` tanımlı değil — thumbnail yüklenirken siyah boşluk görünüyor. `ShimmerBox` placeholder + `ColoredBox(Colors.black)` errorWidget eklenecek.

---

### B4 — `NetworkImage` → `CachedNetworkImage` geçişleri

Cache yok, tekrar tekrar ağdan indiriliyor, OOM riski var. Aşağıdaki ekranlarda `NetworkImage` → `CachedNetworkImage(cacheManager: TeqlifCacheManager())` yapılacak:

| Dosya | Satır | Bağlam |
|-------|-------|--------|
| `public_profile_screen.dart` | 797 | Kullanıcı baş avatarı |
| `public_profile_screen.dart` | 1358 | Değerlendirme yapanın avatarı |
| `listing_detail_screen.dart` | 1558 | Satıcı profil avatar |
| `listing_detail_screen.dart` | 2526 | Teklif yapanların avatarları |
| `my_ratings_screen.dart` | 206 | Yorum avatarları |
| `blocked_users_screen.dart` | 57 | Bloklanmış kullanıcı avatarları |
| `search_screen.dart` | 379 | Kullanıcı arama sonuçları avatarı |
| `profile_screen.dart` | 2649 | Avatar edit anlık önizleme |

---

### B5 — `follow_list_screen.dart:73` — Avatar hiç gösterilmiyor

API `profile_image_thumb_url` alanını dönüyor ama widget `CircleAvatar(child: Text(initial))` kullanıyor — resim hiç bağlanmıyor. `CachedNetworkImageProvider` ile avatar gösterimi eklenecek, resim yoksa initial letter fallback kalır.
