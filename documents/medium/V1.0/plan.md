# Mesajlaşma Medya Sistemi — Uygulama Planı

**Versiyon:** 1.0  
**Tarih:** 2026-09-05  
**Kapsam:** Teqlif DM ekranlarında medya gönderme sisteminin endüstri standardına taşınması

---

## Mevcut Durum Özeti

| Alan | Mevcut | Sorun |
|---|---|---|
| Storage | MinIO, public-read bucket | URL herkese açık, kalıcı |
| Upload akışı | Multipart POST → backend | Presigned URL yok |
| Validation | Backend: magic byte + boyut | Frontend: ses boyutu eksik, video sonrası kontrol yok |
| Thread güvenliği | Block kontrolü var | Declined thread'e gönderim yapılabiliyor |
| Upload UX | Global bool flag | State machine yok, optimistik UI yok |
| Mimari | 3500 satır messages_screen.dart | Upload, compress, player, recorder tek dosyada |
| Localization | Kısmi | 5 yeni ARB anahtarı eksik |

---

## Faz 1 — Kritik Güvenlik & Doğruluk

> **Efor:** ~1 gün | **Risk:** Düşük | **Etki:** Yüksek  
> **Öncelik:** Hemen yapılacak

### 1.1 Backend: Declined thread engeli

**Dosyalar:**
- `backend/app/use_cases/messages/commands/send_media_message_command.py`
- `backend/app/use_cases/messages/commands/send_direct_message.py`

**Yapılacak:**  
Her iki command'da thread okunurken `status == "declined"` kontrolü ekle. Declined ise `ForbiddenException(code="MESSAGING_FORBIDDEN")` fırlat.

```python
if existing_thread and existing_thread.status == "declined":
    raise ForbiddenException(code="MESSAGING_FORBIDDEN")
```

**Kural:** Declined thread'de ne metin ne medya gönderilebilir. Blok kontrolüyle aynı seviyede.

---

### 1.2 Frontend: Ses kaydı boyut kontrolü

**Dosya:** `mobile/lib/screens/messages_screen.dart`

**Yapılacak:**  
Ses kaydı tamamlandıktan sonra (kayıt bitişinde) bytes boyutunu kontrol et.

```dart
// Kayıt bitti, bytes okundu:
if (bytes.length > 512 * 1024) {
  TeqToast.error(loc.t('errVoiceTooLarge'));
  return;
}
```

**Kural:** 512 KB üstü ses → kullanıcıya açıklayıcı hata, yükleme denenmez.

---

### 1.3 Frontend: Video sıkıştırma sonrası boyut kontrolü

**Dosya:** `mobile/lib/screens/messages_screen.dart`

**Yapılacak:**  
`VideoCompress.compressVideo()` sonrası `File.length()` ile boyut kontrol et.

```dart
final compressedFile = File(info.path!);
final size = await compressedFile.length();
if (size > 5 * 1024 * 1024) {
  TeqToast.error(loc.t('errVideoTooLargeAfterCompress'));
  return;
}
```

**Kural:** 5 MB üstü sıkıştırılmış video → kullanıcıya net mesaj, yükleme denenmez.

---

### 1.4 Frontend: Bilinmeyen dosya uzantısı pre-check

**Dosya:** `mobile/lib/screens/messages_screen.dart`

**Yapılacak:**  
`FilePicker` sonrası extension whitelist kontrolü. Whitelist dışı → hata toast + desteklenen formatlar listesi.

```dart
const _allowedExtensions = {'pdf','doc','docx','xls','xlsx','txt'};
final ext = path.extension(file.path).replaceFirst('.', '').toLowerCase();
if (!_allowedExtensions.contains(ext)) {
  TeqToast.error(loc.t('errUnsupportedFile'));
  return;
}
```

---

### 1.5 ARB: Yeni lokalizasyon anahtarları

**Eklenecek anahtarlar** (TR / EN / AR):

| Anahtar | TR | EN |
|---|---|---|
| `errVoiceTooLarge` | "Ses kaydı 512 KB sınırını aşıyor" | "Voice message exceeds 512 KB limit" |
| `errVideoTooLargeAfterCompress` | "Video sıkıştırma sonrası 5 MB sınırını aşıyor. Daha kısa bir video deneyin." | "Video exceeds 5 MB after compression. Try a shorter clip." |
| `errUnsupportedFile` | "Desteklenen formatlar: PDF, DOC, DOCX, XLS, XLSX, TXT" | "Supported formats: PDF, DOC, DOCX, XLS, XLSX, TXT" |
| `mediaCompressing` | "Sıkıştırılıyor..." | "Compressing..." |
| `mediaUploadFailed` | "Yükleme başarısız. Tekrar dene." | "Upload failed. Tap to retry." |

**Workflow:** ARB → `sync_translations.py` → DB → Redis → mobile (Hive cache).

---

## Faz 2 — UX & Upload State Machine

> **Efor:** ~2-3 gün | **Risk:** Orta | **Etki:** Yüksek  
> **Öncelik:** Faz 1 sonrası

### 2.1 Upload State Machine

**Yeni dosya:** `mobile/lib/features/messaging/domain/models/upload_state.dart`

```dart
sealed class MediaUploadState {
  const MediaUploadState();
}
class UploadIdle     extends MediaUploadState { const UploadIdle(); }
class UploadPicking  extends MediaUploadState { const UploadPicking(); }
class UploadCompress extends MediaUploadState { const UploadCompress(); }
class UploadSending  extends MediaUploadState {
  final double progress; // 0.0 – 1.0
  const UploadSending(this.progress);
}
class UploadDone     extends MediaUploadState { const UploadDone(); }
class UploadFailed   extends MediaUploadState {
  final String errorKey;
  final Object? retryPayload;
  const UploadFailed(this.errorKey, {this.retryPayload});
}
```

**Notifier:** `MediaUploadNotifier` (AutoDispose Riverpod family, key = otherUserId)  
Upload mantığını `messages_screen.dart`'tan tamamen çıkarır. Ekran sadece state'i dinler.

---

### 2.2 Optimistik Medya Baloncuğu

**Yeni widget:** `mobile/lib/features/messaging/widgets/message_bubble/pending_media_bubble.dart`

Strateji:
1. Upload başlar → mesaj listesine geçici balonc (tempId = negatif timestamp) eklenir.
2. State güncellendikçe balon güncellenir (`UploadSending` → progress bar).
3. API 200 dönünce tempId yerine gerçek mesaj swap edilir (WS broadcast ile çakışma koruması zaten var).
4. `UploadFailed` → kırmızı kenar + "Tekrar dene" butonu.

| Medya türü | Optimistik gösterim |
|---|---|
| Resim | `MemoryImage(bytes)` 200×200 thumbnail |
| Video | İlk frame thumbnail bytes (sıkıştırma çıktısından) |
| Ses | Statik dalga formu + süre etiketi |
| Dosya | Dosya adı + boyut + CircularProgressIndicator |

---

### 2.3 Ses Kaydı UI İyileştirmesi

**Mevcut:** Kırmızı nokta + MM:SS timer + metin ipucu  
**Hedef:**

- `record` paketi `amplitude` stream'inden gerçek zamanlı dalga formu (CustomPainter, 40px yükseklik)
- Kalan süre countdown bar (10s, LinearProgressIndicator)
- Kayıt biterken gönder butonu aktif (dur + gönder tek hamle)
- Swipe-to-cancel animasyonu için `GestureDetector` + `AnimatedContainer`

---

## Faz 3 — Güvenlik: Presigned URL

> **Efor:** ~2 gün | **Risk:** Orta | **Etki:** Çok yüksek (güvenlik)  
> **Öncelik:** Faz 2 sonrası

### 3.1 MinIO bucket → private

Bucket policy public-read'den kaldırılır. Nginx `/uploads/` proxy endpoint'i kapatılır.

**Etki:** Tüm mevcut DM medya URL'leri (`/uploads/messages/...`) artık çalışmaz. Geçiş planı:
- Eski mesajlar için URL'ler DB'de `/uploads/` prefix'li kalır.
- `PresignedUrlService` bu prefix'i görünce presign endpoint'ini çağırır.
- Yeni yüklemeler aynı key yapısını korur; yalnızca erişim mekanizması değişir.

---

### 3.2 Backend: Presign endpoint

**Yeni endpoint:** `GET /api/media/presign`

```
Authorization: Bearer <token>
Query: key=messages/abc.jpg

Response: { "url": "https://...", "expires_at": "ISO8601" }
```

**Güvenlik kuralı:** Token sahibi bu medyanın `sender_id` veya `receiver_id` değilse → 403.  
**TTL:** MinIO presigned URL = 1 saat.

**Redis cache:** `presign:{user_id}:{key}` → URL, TTL 55 dakika.  
Aynı dosyayı tekrar tekrar açan kullanıcı için DB sorgusu ve MinIO SDK çağrısı yapılmaz.

---

### 3.3 Frontend: PresignedUrlService

**Yeni dosya:** `mobile/lib/features/messaging/services/presigned_url_service.dart`

```dart
class PresignedUrlService {
  // Hive box: key → PresignedEntry {url, expiresAt}

  Future<String> resolve(String rawPath) async {
    if (!rawPath.startsWith('/uploads/messages/')) return imgUrl(rawPath);
    final key = rawPath.replaceFirst('/uploads/', '');
    final cached = _box.get(key);
    if (cached != null && cached.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return cached.url;
    }
    final fresh = await _fetchPresigned(key);
    await _box.put(key, fresh);
    return fresh.url;
  }
}
```

**Cache politikası:** TTL 55 dakika (MinIO'nun 60 dakikasından 5 dakika önce expire et).

---

### 3.4 Widget entegrasyonu

Tüm medya render eden widget'lar `PresignedUrlService.resolve()` üzerinden geçer:

- `CachedNetworkImage` → `FutureBuilder<String>` + resolve
- Video player: resolve → `VideoPlayerController.network(url)`
- Ses oynatıcı: `UrlSource(await resolve(url))`
- Dosya indirme: `Dio.download(await resolve(url), localPath)`

---

## Faz 4 — Clean Architecture Refactor

> **Efor:** ~1 hafta | **Risk:** Düşük | **Etki:** Teknik borç  
> **Öncelik:** Faz 3 sonrası (veya paralel olarak kademeli)

### Hedef klasör yapısı

```
mobile/lib/features/messaging/
  domain/
    models/
      media_message.dart        ← tip güvenli MediaMessage entity
      upload_state.dart          ← sealed class (Faz 2'den)
  services/
    media_upload_service.dart    ← compress + upload + retry mantığı
    presigned_url_service.dart   ← Faz 3'ten
    offline_upload_queue.dart    ← Hive tabanlı offline retry
  viewmodels/
    media_upload_notifier.dart   ← Riverpod (Faz 2'den)
    messages_notifier.dart       ← mesaj listesi (messages_screen'den çıkarılır)
  widgets/
    message_bubble/
      image_bubble.dart
      video_bubble.dart
      voice_bubble.dart
      file_bubble.dart
      pending_media_bubble.dart  ← Faz 2'den
    attach_sheet.dart            ← bottom sheet ayrı widget
    voice_recorder_widget.dart   ← recorder UI ayrı widget
```

### Offline upload queue

`Hive` tabanlı `MediaUploadQueue`:
- Bağlantı kesilince upload isteği (bytes + metadata) kuyruğa alınır.
- `ConnectivityService` stream bağlantı geldiğinde kuyruğu tüketir.
- Retry: exponential backoff, max 3 deneme, sonrası kullanıcıya "başarısız" göster.

---

## Özet: Öncelik ve Efor Tablosu

| Faz | İçerik | Efor | Risk | Etki | Durum |
|---|---|---|---|---|---|
| **1** | Declined guard, frontend validation, ARB | ~1 gün | Düşük | Yüksek | ⬜ Bekliyor |
| **2** | State machine, optimistik UI, ses UI | ~3 gün | Orta | Yüksek | ⬜ Bekliyor |
| **3** | Presigned URL (MinIO + backend + mobile) | ~2 gün | Orta | Çok Yüksek | ⬜ Bekliyor |
| **4** | Clean arch refactor, offline queue | ~1 hafta | Düşük | Teknik borç | ⬜ Bekliyor |

---

## Bağımlılık Grafiği

```
Faz 1 ──► Faz 2 ──► Faz 3 ──► Faz 4
  │                               ▲
  └───────────────────────────────┘
  (Faz 1 ARB anahtarları Faz 2-3'te de kullanılır)
```

Faz 3 ve 4 birbirinden bağımsız paralel başlatılabilir.
