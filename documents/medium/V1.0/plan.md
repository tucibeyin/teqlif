# Mesajlaşma Medya Sistemi — Uygulama Planı

**Versiyon:** 1.2  
**Tarih:** 2026-09-05  
**Kapsam:** Teqlif DM ekranlarında medya gönderme/alma sisteminin endüstri standardına taşınması  
**Güncelleme notu v1.2:** UI/UX analizi entegre edildi — tasarım sistemi çakışması, dark mode hataları, animasyon eksiklikleri, erişilebilirlik ve UX akışları Faz 3 ve Faz 7 olarak plana eklendi.

---

## Mevcut UI/UX Sistem Kuralları

Projede iki katman var: **Tasarım sistemi** (UI Library) ve **Ekranlar**.  
Ekranlar henüz tasarım sistemini tam olarak kullanmıyor — bu planın UI ayağının özeti bu.

### Renk Token Sistemi

| Token dosyası | Kullanım yeri | Sorun |
|---|---|---|
| `lib/config/app_colors.dart` (AppColors) | Ekranlar | Context-based, eski sistem |
| `lib/ui_library/foundation/teq_colors.dart` (TeqColors) | UI Library component'leri | Const-based, yeni sistem |

**Kural:** Yeni yazılacak tüm widget ve ekranlar `TeqColors` kullanır. `AppColors` silinmez ama yeni kod yazılmaz. Geçiş kademeli.

### Typography Kuralları

`lib/ui_library/foundation/teq_typography.dart` — mevcut scale:

| Token | Size | Weight | Kullanım |
|---|---|---|---|
| `h1` | 24 | w700 | Ekran başlıkları |
| `h2` | 20 | w700 | Section başlıkları |
| `h3` | 18 | w600 | Card başlıkları |
| `bodyLarge` | 16 | w400 | Ana içerik metni |
| `bodyMedium` | 14 | w400 | İkincil içerik |
| `bodySmall` | 12 | w400 | Yardımcı metin, caption |
| `labelLarge` | 16 | w600 | Birincil butonlar |
| `labelMedium` | 14 | w600 | İkincil butonlar, tab label |
| `labelSmall` | 12 | w600 | Badge, chip |

**Kural:** Scale dışı `fontSize` değerleri (`10`, `11`) yasak — en yakın token kullanılır.  
**Mesajlaşmaya özel ek:** Timestamp için `bodySmall` (12), kayıt süre göstergesi için `labelMedium` (14).

### Spacing & Radius Kuralları

`lib/ui_library/foundation/teq_spacing.dart`:

| Token | px | Kullanım |
|---|---|---|
| `xxs` | 4 | İkon-metin arası, inline boşluk |
| `xs` | 8 | Component içi padding |
| `s` | 12 | Küçük padding, card iç boşluk |
| `m` | 16 | Standart padding, section arası |
| `l` | 24 | Büyük section arası |
| `xl` | 32 | Ekran kenar boşluğu (landing) |
| `xxl` | 48 | Hero section arası |

| Radius token | px | Kullanım |
|---|---|---|
| `radiusS` | 4 | Input, küçük eleman |
| `radiusM` | 8 | Card, chip |
| `radiusL` | 12 | Bottom sheet handle, modal |
| `radiusXl` | 16 | Mesaj baloncuğu büyük köşe |
| `radiusMax` | 999 | Avatar, pill badge |

**Kural:** Magic number padding/margin yasak — `TeqSpacing` token'ı kullanılır.

### UI Library Component Kuralları

| Component | Dosya | Kural |
|---|---|---|
| Primary button | `teq_button.dart` | 4 tip: primary/secondary/outline/text; loading state built-in |
| Async button | `teq_async_button.dart` | Future-driven; double-tap koruması var, doğrudan kullan |
| Text field | `teq_text_field.dart` | label, hint, error, prefix/suffix dahil; custom TextField yasak |
| Bottom sheet | `teq_bottom_sheet.dart` | `showModalBottomSheet` direkt çağrısı yasak; `TeqBottomSheet.show()` kullan |
| Dialog | `teq_dialog.dart` | `showDialog` direkt çağrısı yasak; `TeqDialog.show()` kullan |
| Toast | `teq_toast.dart` | Context-free; `TeqToast.error/success/warning/info()` kullan |
| Snackbar | `teq_snackbar.dart` | `TeqToast` wrapper'ı; ikisi birbirinin yerine kullanılabilir, yeni kodda `TeqToast` tercih et |
| Card | `teq_card.dart` | `hasBorder`, `elevation`, `onTap` destekli; custom Container kart yasak |

### Dark Mode Kuralları

- Her renk tanımı hem light hem dark değeri içermelidir.
- `Colors.grey.shade*` ve `Color(0xFF...)` literal kullanımı yasak — `TeqColors` veya `AppColors.*` kullanılır.
- `Theme.of(context).brightness` kontrolü ekran kodunda yapılmaz; `AppColors.*` veya `TeqColors` token'ı bunu içerir.
- Dark modda okunabilirlik: minimum kontrast oranı 4.5:1 (WCAG AA).

### Animasyon / Motion Kuralları

| Süre | Kullanım |
|---|---|
| 150–200ms | Micro-interaction (buton press, toggle) |
| 250–300ms | Component geçişi (bottom sheet, dialog) |
| 350–400ms | Ekran geçişi |

- `Curves.easeOutCubic` — standart çıkış eğrisi.
- `Curves.easeInOut` — expand/collapse için.
- `prefers-reduced-motion` eşdeğeri: `MediaQuery.of(context).disableAnimations` kontrol edilir, animasyon varsa 0 süreye indirilir.

---

## Mevcut Durum — Tespit Edilen Sorunlar

### Güvenlik

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| S-1 | `upload.py`, `messages.py` | 150, 125 | `await file.read()` tüm dosyayı belleğe alıyor — streaming yok |
| S-2 | `send_media_message_command.py` | 340–350 | DOC/DOCX/XLS için magic byte doğrulaması yok |
| S-3 | `messages_screen.dart` | 1769–1783 | İndirmede auth token yok; path traversal riski |
| S-4 | `upload.py` | 79–94 | `ffprobe` yoksa video süre limiti sessizce devre dışı |
| S-5 | `storage_service.py` | 19–31 | MinIO singleton thread-safe değil |
| S-6 | MinIO | — | Public-read bucket — URL bilen herkes erişiyor |

### Clean Architecture

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| A-1 | `send_media_message_command.py` | 19–25 | Use case → router ters bağımlılık |
| A-2 | `get_messages_query.py` | 61–76 | Query write yapıyor — CQRS ihlali |
| A-3 | `messages.py` router | 187–214 | Raw `db: AsyncSession` + UoW karışımı |
| A-4 | `send_media_message_command.py` | 257–352 | `_process_media` 95 satır, Strategy yok |

### Design Patterns

| ID | Dosya | Sorun |
|---|---|---|
| D-1 | `send_media_message_command.py` | `_msg_out()` ve `_media_payload()` DRY ihlali |
| D-2 | `storage_service.py` | Abstract interface yok — test edilemez |
| D-3 | `messages_screen.dart` | `_uploadMedia` God method |

### API Design

| ID | Dosya | Sorun |
|---|---|---|
| API-1 | `messages.py` | `/messages/upload` non-REST URL |
| API-2 | Birden fazla | Limit değerleri dağınık ve tutarsız |
| API-3 | `get_messages_query.py:57` | `limit(100)` hardcoded, pagination yok |
| API-4 | `schemas/message.py` | `content_type: str` Literal değil |

### Clean Code

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| C-1 | `messages_screen.dart` | 1787–1989 | `_buildMsgContent` 202 satır |
| C-2 | Birden fazla | — | Magic number'lar dağınık |
| C-3 | `messages_screen.dart` | 1694 | Ses: client 10s vs backend 60s |
| C-4 | `send_media_message_command.py` | 303–338 | 4 seviye iç içe nesting |
| C-5 | `send_media_message_command.py` | 257 | Orphan file riski; tuple return |

### UI/UX Sorunları

| ID | Konum | Sorun |
|---|---|---|
| U-1 | `messages_screen.dart` | `showModalBottomSheet` direkt kullanımı — `TeqBottomSheet` kullanılmıyor |
| U-2 | Attach sheet | Handle rengi `Colors.grey.shade300` — dark modda görünmez |
| U-3 | `_RequestBanner`, `_ContextBanner` | `Color(0xFFF3F4F6)` hardcode — dark modda beyaz |
| U-4 | Voice mesaj baloncuğu | `Colors.grey.shade200` — dark modda çok açık |
| U-5 | Voice progress bar | `width: 100` sabit — responsive değil |
| U-6 | Ses süresi formatı | `${n}s` ham — `01:23` formatı olmalı |
| U-7 | Dosya boyutu | `${n}KB` kaba — MB geçişi yok |
| U-8 | Resim placeholder | `CircularProgressIndicator` — shimmer olmalı |
| U-9 | Kayıt iptal butonu | `Colors.red.shade50` — dark modda soluk |
| U-10 | Yeni mesaj | Liste animasyonu yok — mesaj anında belirir |
| U-11 | Pending → sent | Durum geçiş animasyonu yok |
| U-12 | `TeqSpacing`/`TeqTypography` | Ekran kodunda kullanılmıyor, inline değerler |
| U-13 | Ses kaydı UI | Dalga formu yok, countdown yok |
| U-14 | Dosya ikonları | Tek jenerik ikon — PDF/DOC/XLS ayırt edilmiyor |
| U-15 | Upload sırasında | Medya yükleniyor iken ekranda hiçbir şey görünmüyor |

---

## Hedef Mimari

### Presigned URL — Doğru Desen (N+1 kaldırıldı)

```
Mobile → GET /api/messages/{other_id}
Backend → mesajları çek → batch presign (Redis 6 gün cache) → URL payload'a gömülü
Mobile → CachedNetworkImage(presigned_url)   ← ekstra istek yok
```

### Bucket Stratejisi

```
teqlif (mevcut, public-read)     — profil, ilan, story, stream
teqlif-dm (YENİ, private)        — messages/* (presigned URL)
```

### Limit Merkezi

```
backend: app/config/media_limits.py
mobile:  lib/constants/media_constants.dart
```

---

## Faz 1 — Kritik Güvenlik & Doğruluk

> **Efor:** ~1 gün | **Risk:** Düşük | **Öncelik:** İlk

### 1.1 Merkezi limit tanımı (C-2, API-2)

**`backend/app/config/media_limits.py`:**
```python
IMAGE_MAX_BYTES = 5 * 1024 * 1024   # 5 MB
VIDEO_MAX_BYTES = 5 * 1024 * 1024   # 5 MB
VOICE_MAX_BYTES = 512 * 1024         # 512 KB
FILE_MAX_BYTES  = 5 * 1024 * 1024   # 5 MB
VIDEO_MAX_SECS  = 15
VOICE_MAX_SECS  = 60
MSG_PAGE_SIZE   = 50
```

**`lib/constants/media_constants.dart`:**
```dart
class MediaConstants {
  static const int imageMaxBytes = 5 * 1024 * 1024;
  static const int videoMaxBytes = 5 * 1024 * 1024;
  static const int voiceMaxBytes = 512 * 1024;
  static const int fileMaxBytes  = 5 * 1024 * 1024;
  static const int videoMaxSecs  = 15;
  static const int voiceMaxSecs  = 60;
  static const Set<String> allowedExtensions = {'pdf','doc','docx','xls','xlsx','txt'};
}
```

### 1.2 MinIO singleton güvenliği (S-5)
Module import sırasında client oluştur, lazy singleton kaldır.

### 1.3 Magic byte doğrulaması tamamlama (S-2)
DOC/DOCX/XLS/XLSX için magic byte map; ZIP sonrası `[Content_Types].xml` parse ile DOCX/XLSX ayırt.

### 1.4 Declined thread engeli
```python
if existing_thread and existing_thread.status == "declined":
    raise ForbiddenException(code="MESSAGING_FORBIDDEN")
```

### 1.5 Frontend validation
- Ses: `bytes.length > MediaConstants.voiceMaxBytes` → `TeqToast.error`
- Video: sıkıştırma sonrası `File.length()` → `TeqToast.error`
- Dosya: extension whitelist pre-check → `TeqToast.error`

### 1.6 Dosya indirme güvenliği (S-3)
Authorization header + `path.basename()` + karakter whitelist.

### 1.7 ffprobe startup kontrolü (S-4)
`lifespan` hook'unda `shutil.which("ffprobe")` zorunlu kontrol.

### 1.8 ARB — yeni lokalizasyon anahtarları

| Anahtar | TR | EN |
|---|---|---|
| `errVoiceTooLarge` | "Ses kaydı 512 KB sınırını aşıyor" | "Voice exceeds 512 KB limit" |
| `errVideoTooLargeAfterCompress` | "Video 5 MB sınırını aşıyor. Daha kısa bir klip deneyin." | "Video exceeds 5 MB. Try a shorter clip." |
| `errUnsupportedFile` | "Desteklenen: PDF, DOC, DOCX, XLS, XLSX, TXT" | "Supported: PDF, DOC, DOCX, XLS, XLSX, TXT" |
| `mediaCompressing` | "Sıkıştırılıyor..." | "Compressing..." |
| `mediaUploadFailed` | "Yükleme başarısız. Tekrar dene." | "Upload failed. Tap to retry." |

---

## Faz 2 — Clean Architecture Backend Refactor

> **Efor:** ~2 gün | **Risk:** Orta | **Öncelik:** Faz 1 sonrası

### 2.1 Media utils katmanı (A-1)
`backend/app/utils/media_processor.py` — router private fonksiyonları buraya taşınır. Use case ve router buradan import eder.

### 2.2 Strategy pattern — medya işleyiciler (A-4)
```python
class MediaProcessor(Protocol):
    async def process(self, data: bytes, ...) -> MediaProcessResult: ...

@dataclass
class MediaProcessResult:
    media_url: str
    thumbnail_url: str | None
    file_name: str
    duration_secs: int | None

# Her tür için: VoiceProcessor, ImageProcessor, VideoProcessor, FileProcessor
_PROCESSORS: dict[str, MediaProcessor] = { ... }
```

### 2.3 Orphan file koruması (C-5)
Upload başarılı → DB fail → MinIO'da orphan temizlenir. `MediaProcessResult` dataclass tuple'ı değiştirir.

### 2.4 CQRS düzeltme (A-2)
`GetMessagesQuery` sadece okur. `MarkMessagesReadCommand` ayrı çalışır.

### 2.5 Cursor pagination (API-3)
`before_id: int | None` parametresi — `id < before_id` filtresi. Mobile infinite scroll.

### 2.6 Literal tip kısıtlaması (API-4)
```python
content_type: Literal["text", "voice", "image", "video", "file"] = "text"
```

### 2.7 AbstractStorageService (D-2)
```python
class AbstractStorageService(Protocol):
    def upload_bytes(self, key, data, content_type) -> str: ...
    def upload_file(self, key, path, content_type) -> str: ...
    def delete_object(self, key) -> None: ...
    def presign_get(self, key, expires) -> str: ...  # Faz 4
```

---

## Faz 3 — Mesajlaşma Ekranı UI/UX Düzeltmeleri

> **Efor:** ~2 gün | **Risk:** Düşük | **Öncelik:** Faz 1 ile paralel başlatılabilir

### 3.1 Dark mode hataları (U-2, U-3, U-4, U-9)

**Attach sheet handle:**
```dart
// Önce (hata):
color: Colors.grey.shade300

// Sonra:
color: AppColors.border(context)
```

**`_RequestBanner` ve `_ContextBanner`:**
```dart
// Önce:
Color(0xFFF3F4F6)   // hardcode açık gri

// Sonra:
AppColors.surface(context)
AppColors.card(context)
```

**Voice mesaj baloncuğu:**
```dart
// Önce:
isMe ? Colors.white24 : Colors.grey.shade200

// Sonra:
isMe ? TeqColors.primary.withValues(alpha: 0.15)
     : AppColors.card(context)
```

**Kayıt iptal butonu:**
```dart
// Önce: Colors.red.shade50
// Sonra: TeqColors.error.withValues(alpha: 0.12)
```

### 3.2 Attach sheet TeqBottomSheet'e geçiş (U-1)

```dart
// Önce: showModalBottomSheet direkt
// Sonra:
TeqBottomSheet.show(
  context: context,
  child: _AttachSheetContent(onSelected: ...),
);
```

### 3.3 Ses süresi formatı (U-6)

```dart
String _formatDuration(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return m > 0
      ? '$m:${s.toString().padLeft(2, '0')}'
      : '0:${s.toString().padLeft(2, '0')}';
}
// "7s" → "0:07", "90s" → "1:30"
```

Her yerde tutarlı: kayıt bar, ses mesaj baloncuğu, sesli mesaj listesi.

### 3.4 Dosya boyutu formatı (U-7)

```dart
String _formatFileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
// "1024 KB" → "1.0 MB"
```

### 3.5 Voice progress bar responsive (U-5)

```dart
// Önce: SizedBox(width: 100, child: LinearProgressIndicator(...))
// Sonra:
Expanded(child: LinearProgressIndicator(...))
```
Bubble `maxWidth: ekran * 0.72` içinde her zaman dolacak.

### 3.6 Resim placeholder shimmer (U-8)

```dart
// Önce: CircularProgressIndicator placeholder
// Sonra (shimmer paketi kurulu, sadece kullanılmıyor):
placeholder: (context, url) => Shimmer.fromColors(
  baseColor: AppColors.card(context),
  highlightColor: AppColors.surface(context),
  child: Container(color: Colors.white),
),
```

### 3.7 Dosya tipi ikonları (U-14)

```dart
IconData _fileIcon(String? fileName) {
  final ext = fileName?.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf'  => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' => Icons.description_outlined,
    'xls' || 'xlsx' => Icons.table_chart_outlined,
    'txt'  => Icons.text_snippet_outlined,
    _      => Icons.attach_file_outlined,
  };
}
```

### 3.8 TeqSpacing / TeqTypography geçişi (U-12)

Mesajlaşma ekranında inline değerler token'larla değiştirilir:
- `EdgeInsets.symmetric(horizontal: 12)` → `EdgeInsets.symmetric(horizontal: TeqSpacing.s)`
- `EdgeInsets.symmetric(vertical: 8)` → `EdgeInsets.symmetric(vertical: TeqSpacing.xs)`
- `fontSize: 12` caption → `TeqTypography.bodySmall`
- `fontSize: 14, w600` → `TeqTypography.labelMedium`

### 3.9 Yeni mesaj liste animasyonu (U-10)

```dart
// ListView.builder yerine AnimatedList veya:
// Her yeni mesaj için AnimatedOpacity + SlideTransition
AnimatedOpacity(
  opacity: isNew ? 0 : 1,
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOutCubic,
  child: messageBubble,
)
```

### 3.10 Pending → sent durum geçiş animasyonu (U-11)

Mesaj pending durumundan confirmed'e geçerken:
- Saat ikonu `→` çift tik: `AnimatedSwitcher` + `FadeTransition` (200ms)
- Bubble kenarlığı: pending'de `0.5 opacity`, confirmed'de tam opacity

---

## Faz 4 — Upload State Machine & Optimistik UI

> **Efor:** ~3 gün | **Risk:** Orta | **Öncelik:** Faz 3 sonrası

### 4.1 Upload State Machine (U-15)

```dart
sealed class MediaUploadState { const MediaUploadState(); }
class UploadIdle     extends MediaUploadState { const UploadIdle(); }
class UploadPicking  extends MediaUploadState { const UploadPicking(); }
class UploadCompress extends MediaUploadState { const UploadCompress(); }
class UploadSending  extends MediaUploadState {
  final double progress;   // 0.0 – 1.0
  const UploadSending(this.progress);
}
class UploadDone    extends MediaUploadState { const UploadDone(); }
class UploadFailed  extends MediaUploadState {
  final String errorKey;
  final Object? retryPayload;
  const UploadFailed(this.errorKey, {this.retryPayload});
}
```

`MediaUploadNotifier` (AutoDispose Riverpod family) — upload mantığı ekrandan çıkar.

### 4.2 Optimistik medya baloncuğu

Upload başlar → geçici balon (tempId = negatif timestamp):

| Tür | Optimistik gösterim | Yükleniyor göstergesi |
|---|---|---|
| Resim | `MemoryImage(bytes)` 200×200 | LinearProgressIndicator alt kenar |
| Video | İlk frame thumbnail | LinearProgressIndicator + süre |
| Ses | Statik dalga formu + süre | Animasyonlu nokta |
| Dosya | Dosya adı + boyut | CircularProgressIndicator + `%` |

`UploadFailed`: kırmızı sol kenar stripe + "Tekrar dene" `TextButton`.

Durum bildirimi (compressing sırasında):
```dart
// UploadCompress state'inde input bar üstünde şerit:
Animate kompresyon: Text(loc.t('mediaCompressing'), style: TeqTypography.bodySmall)
```

### 4.3 God method parçalama (D-3, C-1)

`_buildMsgContent` → ayrı Stateless widget'lar:

```
lib/features/messaging/widgets/message_bubble/
  image_bubble.dart         ← CachedNetworkImage, shimmer, fullscreen
  video_bubble.dart         ← thumbnail + play overlay, fullscreen player
  voice_bubble.dart         ← play/pause, Expanded progress, formatDuration
  file_bubble.dart          ← tip ikonu, boyut, indirme + open
  pending_media_bubble.dart ← optimistik görünüm + retry
  text_bubble.dart          ← metin, link detection
```

### 4.4 Ses kaydı UI (U-13)

```dart
// Amplitude stream → CustomPainter waveform
record.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((amp) {
  _amplitudes.add(amp.current);
  setState(() {});
});

// Countdown bar
LinearProgressIndicator(
  value: _recordSecs / MediaConstants.voiceMaxSecs,
  color: _recordSecs > MediaConstants.voiceMaxSecs * 0.8
      ? TeqColors.error : TeqColors.primary,
)
```

---

## Faz 5 — Güvenlik: Private DM Bucket + Presigned URL

> **Efor:** ~2 gün | **Risk:** Orta-Yüksek | **Öncelik:** Faz 2 sonrası

### 5.1 Yeni private bucket
`teqlif-dm` MinIO bucket — private. Config'e `minio_dm_bucket` eklenir.

### 5.2 Presigned URL — mesaj payload'ına gömme

```python
# get_messages_query.py
async def _presign_if_dm(self, url: str | None) -> str | None:
    if not url or not url.startswith("/uploads/messages/"):
        return url
    key = url.removeprefix("/uploads/")
    cached = await redis.get(f"presign:{self.viewer_id}:{key}")
    if cached:
        return cached.decode()
    signed = storage_dm.presign_get(key, expires=timedelta(days=7))
    await redis.set(f"presign:{self.viewer_id}:{key}", signed, ex=6*24*3600)
    return signed
```

Mesaj payload'ında `media_url` ve `thumbnail_url` zaten presigned gelir. Frontend ekstra istek yapmaz.

### 5.3 TTL kararları

| | Değer | Gerekçe |
|---|---|---|
| MinIO presign TTL | 7 gün | Geçmiş ertesi gün açılınca geçerli |
| Redis cache TTL | 6 gün | 1 gün buffer — kullanıcı expired URL almaz |
| Block sonrası erişim | En fazla 6 gün | Kabul edilebilir trade-off (Signal/WhatsApp aynı) |

### 5.4 Erişim kontrolü
`sender_id == viewer_id` veya `receiver_id == viewer_id` presign üretimi sırasında doğrulanır.

---

## Faz 6 — Streaming Upload

> **Efor:** ~1 gün | **Risk:** Düşük | **Öncelik:** Faz 5 sonrası

### 6.1 Content-Length erken rejection
FastAPI middleware — `Content-Length > MAX_SIZE` ise 413 döner, dosya okunmaz.

### 6.2 Chunk-based streaming
```python
async for chunk in file.stream():
    total += len(chunk)
    if total > MAX_SIZE:
        raise BadRequestException(code="FILE_TOO_LARGE")
    tmp.write(chunk)
```
Bellek tüketimi: max 64 KB (chunk boyutu), dosya boyutundan bağımsız.

---

## Faz 7 — Clean Architecture Mobile Refactor

> **Efor:** ~1 hafta | **Risk:** Düşük | **Öncelik:** Kademeli, Faz 4 widget'larını absorbe eder

### Hedef yapı

```
mobile/lib/features/messaging/
  constants/
    media_constants.dart            ← Faz 1'den
  domain/
    models/
      media_message.dart
      upload_state.dart              ← Faz 4'ten
  repositories/
    message_repository.dart         ← HTTP, hata dönüşümü
  services/
    media_upload_service.dart       ← compress + upload + retry
    presigned_url_service.dart      ← Faz 5'ten (fallback)
    offline_upload_queue.dart       ← Hive + ConnectivityService
  viewmodels/
    media_upload_notifier.dart      ← Faz 4'ten
    messages_notifier.dart
  widgets/
    message_bubble/                 ← Faz 4'ten
    attach_sheet.dart
    voice_recorder_widget.dart
```

### Offline upload queue
Hive tabanlı. Bağlantı gelince `ConnectivityService` stream kuyruğu tüketir. Exponential backoff, max 3 deneme.

---

## Özet Tablo

| Faz | İçerik | Efor | Risk | Etki | Durum |
|---|---|---|---|---|---|
| **1** | Limitler, güvenlik bugları, declined guard, ARB | ~1 gün | Düşük | Yüksek | ⬜ |
| **2** | Strategy, CQRS, pagination, AbstractStorage | ~2 gün | Orta | Yüksek | ⬜ |
| **3** | Dark mode, TeqBottomSheet, format, shimmer, animasyon | ~2 gün | Düşük | Yüksek (görsel) | ⬜ |
| **4** | State machine, optimistik UI, waveform, widget parçalama | ~3 gün | Orta | Yüksek | ⬜ |
| **5** | Private DM bucket, presigned URL, Redis cache | ~2 gün | Orta-Yüksek | Çok Yüksek | ⬜ |
| **6** | Streaming upload | ~1 gün | Düşük | Orta | ⬜ |
| **7** | Clean arch refactor, offline queue | ~1 hafta | Düşük | Teknik borç | ⬜ |

## Bağımlılık Grafiği

```
Faz 1 ──► Faz 2 ──────────► Faz 5 ──► Faz 6
  │                               ▲
  ├──────► Faz 3                  │
  │                               │
  └──────► Faz 4 ─────────────────┘
                    Faz 7 (Faz 3+4 widget'larını absorbe eder)
```

- Faz 1, 2, 3 paralel başlatılabilir
- Faz 4 için Faz 3 dark mode düzeltmeleri tamamlanmış olmalı (widget'lar temiz zeminde yazılır)
- Faz 5 için Faz 2 (AbstractStorageService + presign_get) gerekli

---

## Kritik Kural Değişiklikleri (v1.0 → v1.2)

| # | v1.0 | v1.2 |
|---|---|---|
| 1 | Ayrı presign endpoint | URL mesaj payload'ına gömülür — N+1 yok |
| 2 | Tüm bucket private | `teqlif-dm` ayrı private bucket |
| 3 | Presign TTL 1 saat | TTL 7 gün, Redis 6 gün |
| 4 | — | Strategy pattern, CQRS, AbstractStorage |
| 5 | — | Streaming upload + Content-Length middleware |
| 6 | — | Orphan file koruması |
| 7 | — | Magic byte tüm dosya tiplerine |
| 8 | — | Dark mode bugları (U-1..U-9) Faz 3 olarak eklendi |
| 9 | — | Animasyonlar (U-10, U-11) Faz 3'e eklendi |
| 10 | — | Upload state machine + optimistik UI Faz 4 olarak ayrıldı |
| 11 | — | Ses kaydı waveform + countdown Faz 4'e eklendi |
| 12 | — | UI/UX sistem kuralları belgelendi (token, spacing, animasyon) |
