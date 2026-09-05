# Mesajlaşma Medya Sistemi — Uygulama Planı

**Versiyon:** 1.1  
**Tarih:** 2026-09-05  
**Kapsam:** Teqlif DM ekranlarında medya gönderme/alma sisteminin endüstri standardına taşınması  
**Güncelleme notu:** v1.0'dan farklar — presign mimarisi düzeltildi (N+1 kaldırıldı), bucket stratejisi netleştirildi, TTL 7 güne çıkarıldı, kod analizi bulguları entegre edildi.

---

## Mevcut Durum — Tespit Edilen Sorunlar

### Güvenlik (Security)

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| S-1 | `upload.py`, `messages.py` | 150, 125 | `await file.read()` tüm dosyayı belleğe alıyor — streaming upload yok |
| S-2 | `send_media_message_command.py` | 340–350 | DOC/DOCX/XLS için magic byte doğrulaması yok, sadece PDF kontrol ediliyor |
| S-3 | `messages_screen.dart` | 1769–1783 | Dosya indirmede auth token yok; `fileName` server'dan gelip sanitize edilmeden path'e yazılıyor (path traversal riski) |
| S-4 | `upload.py` | 79–94 | `ffprobe` yoksa video süre limiti sessizce devre dışı kalıyor |
| S-5 | `storage_service.py` | 19–31 | MinIO singleton thread-safe değil; eşzamanlı coroutine'ler multiple client yaratabilir |
| S-6 | MinIO | — | Bucket public-read; URL bilen herkes medyaya erişiyor, imzalı/geçici URL yok |

### Clean Architecture (Katman İhlalleri)

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| A-1 | `send_media_message_command.py` | 19–25 | Use case, router'ın private `_` fonksiyonlarını import ediyor — ters bağımlılık |
| A-2 | `get_messages_query.py` | 61–76 | Query sınıfı write yapıyor (is_read update) ve WS broadcast fırlatıyor — CQRS ihlali |
| A-3 | `messages.py` router | 187–214 | `update_call_permission` UoW yerine raw `db: AsyncSession` kullanıyor — router içinde iki farklı DB paradigması |
| A-4 | `send_media_message_command.py` | 257–352 | `_process_media` 95 satır, 4 medya tipini tek method'da işliyor — Strategy pattern eksikliği |

### Design Patterns

| ID | Dosya | Sorun |
|---|---|---|
| D-1 | `send_media_message_command.py` | `_msg_out()` ve `_media_payload()` neredeyse aynı — DRY ihlali |
| D-2 | `storage_service.py` | Interface/abstract class yok — test edilemez, mock'lanamaz |
| D-3 | `messages_screen.dart` | `_uploadMedia` ~65 satır God method: HTTP, hata parse, state, UI iç içe |

### API Design

| ID | Dosya | Sorun |
|---|---|---|
| API-1 | `messages.py` | `/messages/upload` non-REST; kaynak odaklı URL olmalı |
| API-2 | `upload.py` + `send_media_message_command.py` | Limit değerleri dağınık ve tutarsız (resim: 10 MB vs 5 MB) |
| API-3 | `get_messages_query.py:57` | `limit(100)` hardcoded, cursor-based pagination yok |
| API-4 | `schemas/message.py` | `content_type: str = "text"` — `Literal` tip kısıtlaması yok |

### Clean Code

| ID | Dosya | Satır | Sorun |
|---|---|---|---|
| C-1 | `messages_screen.dart` | 1787–1989 | `_buildMsgContent` 202 satır, 5 tip switch — parçalanmalı |
| C-2 | Birden fazla | — | Magic number'lar dağınık (5 MB, 512 KB, 15s, 100 limit...) |
| C-3 | `messages_screen.dart` | 1694 | Ses kaydı client 10s, backend 60s — senkronize değil |
| C-4 | `send_media_message_command.py` | 303–338 | Video işleme bloğunda 4 seviye iç içe nesting |
| C-5 | `send_media_message_command.py` | 257 | Upload başarılı → DB hata → MinIO'da orphan dosya kalıyor; tuple return anlaşılmaz |

---

## Hedef Mimari

### Presigned URL — Doğru Desen

**Kaldırılan (N+1 anti-pattern):**
```
Mobile → GET /api/media/presign?key=x  (her resim için ayrı istek)
```

**Endüstri standardı (Telegram / Signal / WhatsApp modeli):**
```
Mobile → GET /api/messages/{other_id}
Backend → mesajları çek → batch presign (Redis 7 gün cache) → URL'ler payload'a gömülü
Mobile → CachedNetworkImage(presigned_url)   ← ekstra istek yok
```

### Bucket Stratejisi

Tek bucket'ı tamamen private yapmak profil fotoğrafı, ilan görseli, story'yi kırar. Doğru yaklaşım:

```
teqlif bucket (mevcut, public-read)
  profiles/*     → public  ✓
  listings/*     → public  ✓
  stories/*      → public  ✓
  streams/*      → public  ✓

teqlif-dm bucket (YENİ, private)
  messages/*     → presigned URL (7 gün TTL)
```

Nginx `/uploads/` proxy'si yalnızca `teqlif` bucket'ını sergilemeye devam eder. `teqlif-dm` bucket'ı doğrudan client'a expose edilmez, presigned URL üzerinden erişilir.

### Limit Merkezi — Tek Kaynak

```
backend: app/config/media_limits.py
mobile:  lib/constants/media_constants.dart
```

Her iki taraf aynı değerleri kullanır; limit değiştiğinde tek yerde güncellenir.

---

## Faz 1 — Kritik Güvenlik & Doğruluk

> **Efor:** ~1 gün | **Risk:** Düşük | **Öncelik:** İlk

### 1.1 Merkezi limit tanımı (C-2, API-2)

**Backend — `backend/app/config/media_limits.py` (yeni dosya):**
```python
IMAGE_MAX_BYTES  = 5 * 1024 * 1024   # 5 MB
VIDEO_MAX_BYTES  = 5 * 1024 * 1024   # 5 MB
VOICE_MAX_BYTES  = 512 * 1024         # 512 KB
FILE_MAX_BYTES   = 5 * 1024 * 1024   # 5 MB
VIDEO_MAX_SECS   = 15
VOICE_MAX_SECS   = 60
MSG_PAGE_SIZE    = 50
```

`upload.py` ve `send_media_message_command.py` bu sabitlerden import eder. Magic number'lar kaldırılır.

**Mobile — `lib/constants/media_constants.dart` (yeni dosya):**
```dart
class MediaConstants {
  static const int imageMaxBytes  = 5 * 1024 * 1024;
  static const int videoMaxBytes  = 5 * 1024 * 1024;
  static const int voiceMaxBytes  = 512 * 1024;
  static const int fileMaxBytes   = 5 * 1024 * 1024;
  static const int videoMaxSecs   = 15;
  static const int voiceMaxSecs   = 60;   // backend ile senkron
  static const Set<String> allowedFileExtensions = {'pdf','doc','docx','xls','xlsx','txt'};
}
```

### 1.2 MinIO singleton güvenliği (S-5)

`storage_service.py`: module import sırasında client oluştur, lazy singleton kaldır.

```python
_client = Minio(
    settings.minio_endpoint,
    access_key=settings.minio_access_key,
    secret_key=settings.minio_secret_key,
    secure=settings.minio_secure,
)
```

### 1.3 Dosya magic byte doğrulaması tamamlama (S-2)

`send_media_message_command.py`'de DOC/DOCX/XLS/XLSX için magic byte map ekle:

```python
_FILE_MAGIC: dict[bytes, str] = {
    b"%PDF":                             "application/pdf",
    b"\xD0\xCF\x11\xE0":               "application/msword",         # DOC, XLS (OLE2)
    b"PK\x03\x04":                      "application/zip",            # DOCX, XLSX (ZIP)
}
```

ZIP magic sonrası içerik `[Content_Types].xml` parse edilerek DOCX/XLSX ayırt edilir.

### 1.4 Declined thread engeli (işlevsel)

`send_media_message_command.py` ve `send_direct_message.py`'de thread okunurken:

```python
if existing_thread and existing_thread.status == "declined":
    raise ForbiddenException(code="MESSAGING_FORBIDDEN")
```

### 1.5 Frontend — ses boyutu + video sonrası boyut + dosya pre-check

```dart
// Ses kayıt bitti:
if (bytes.length > MediaConstants.voiceMaxBytes) {
  TeqToast.error(loc.t('errVoiceTooLarge'));
  return;
}

// Video sıkıştırma sonrası:
final compressedSize = await File(info.path!).length();
if (compressedSize > MediaConstants.videoMaxBytes) {
  TeqToast.error(loc.t('errVideoTooLargeAfterCompress'));
  return;
}

// Dosya seçimi:
if (!MediaConstants.allowedFileExtensions.contains(ext)) {
  TeqToast.error(loc.t('errUnsupportedFile'));
  return;
}
```

### 1.6 Dosya indirme güvenliği (S-3)

`_downloadAndOpen`'da:
- Authorization header ekle
- `fileName` için `path.basename()` + alfanumerik+nokta+tire+alt çizgi whitelist

```dart
final safeName = path.basename(rawName).replaceAll(RegExp(r'[^\w\-.]'), '_');
final file = File('${dir.path}/$safeName');
```

### 1.7 ffprobe zorunlu bağımlılık (S-4)

`upload.py` startup validation'ında (ya da `lifespan` hook'unda):
```python
if not shutil.which("ffprobe"):
    raise RuntimeError("ffprobe bulunamadı — video yükleme çalışmaz")
```

### 1.8 ARB — yeni lokalizasyon anahtarları

| Anahtar | TR | EN |
|---|---|---|
| `errVoiceTooLarge` | "Ses kaydı 512 KB sınırını aşıyor" | "Voice message exceeds 512 KB limit" |
| `errVideoTooLargeAfterCompress` | "Video sıkıştırma sonrası 5 MB sınırını aşıyor. Daha kısa bir klip deneyin." | "Video exceeds 5 MB after compression. Try a shorter clip." |
| `errUnsupportedFile` | "Desteklenen formatlar: PDF, DOC, DOCX, XLS, XLSX, TXT" | "Supported: PDF, DOC, DOCX, XLS, XLSX, TXT" |
| `mediaCompressing` | "Sıkıştırılıyor..." | "Compressing..." |
| `mediaUploadFailed` | "Yükleme başarısız. Tekrar dene." | "Upload failed. Tap to retry." |

**Workflow:** ARB → `sync_translations.py` → DB → Redis → mobile Hive cache.

---

## Faz 2 — Clean Architecture Backend Refactor

> **Efor:** ~2 gün | **Risk:** Orta | **Öncelik:** Faz 1 sonrası

### 2.1 Media utils katmanı — ters bağımlılığı kır (A-1)

**Yeni dosya:** `backend/app/utils/media_processor.py`

Router'ın private fonksiyonları (`_detect_image_type`, `_detect_video_type`, `_make_thumbnail`, `_get_video_duration`) buraya taşınır. Hem `upload.py` hem `send_media_message_command.py` buradan import eder. Ters bağımlılık ortadan kalkar.

### 2.2 Strategy pattern — medya tipine göre işleyici (A-4)

`send_media_message_command.py` içindeki 95 satırlık `_process_media` metodu:

```python
class MediaProcessor(Protocol):
    async def process(self, data: bytes, ...) -> MediaProcessResult: ...

@dataclass
class MediaProcessResult:
    media_url: str
    thumbnail_url: str | None
    file_name: str
    duration_secs: int | None

class VoiceProcessor(MediaProcessor): ...
class ImageProcessor(MediaProcessor): ...
class VideoProcessor(MediaProcessor): ...
class FileProcessor(MediaProcessor): ...

_PROCESSORS: dict[str, MediaProcessor] = {
    "voice": VoiceProcessor(),
    "image": ImageProcessor(),
    "video": VideoProcessor(),
    "file":  FileProcessor(),
}
```

`SendMediaMessageCommand.execute()` yalnızca `processor = _PROCESSORS[content_type_field]` çağırır. Her processor kendi cleanup'ını da yönetir (orphan file koruması — C-5).

### 2.3 Orphan file koruması (C-5)

```python
media_url = None
try:
    result = await processor.process(data, ...)
    media_url = result.media_url
    # DB write
    async with self.uow:
        ...
except Exception:
    if media_url:
        storage.delete_object(storage.url_to_key(media_url))
    raise
```

### 2.4 CQRS düzeltme — query'den write çıkar (A-2)

`GetMessagesQuery.execute()` artık sadece okuma yapar. `is_read` güncelleme ve WS broadcast ayrı bir `MarkMessagesReadCommand`'a taşınır. GET endpoint'i her iki komutu sıralı çağırır:

```python
@router.get("/{other_user_id}/messages")
async def get_messages(other_user_id: int, ...):
    messages = await GetMessagesQuery(uow).execute(uid, other_user_id)
    asyncio.create_task(MarkMessagesReadCommand(uow).execute(uid, other_user_id))
    return messages
```

### 2.5 Cursor tabanlı pagination (API-3)

`GetMessagesQuery` imzası:
```python
async def execute(self, uid: int, other_id: int, before_id: int | None = None, limit: int = MSG_PAGE_SIZE) -> list[MessageOut]:
```

`before_id` verilmişse `DirectMessage.id < before_id` filtresi eklenir. Mobile infinite scroll bu `before_id` ile çalışır.

### 2.6 `content_type` Literal tip kısıtlaması (API-4)

```python
# schemas/message.py
from typing import Literal
content_type: Literal["text", "voice", "image", "video", "file"] = "text"
```

### 2.7 AbstractStorageService — test edilebilirlik (D-2)

```python
class AbstractStorageService(Protocol):
    def upload_bytes(self, key: str, data: bytes, content_type: str) -> str: ...
    def upload_file(self, key: str, path: str, content_type: str) -> str: ...
    def delete_object(self, key: str) -> None: ...
    def presign_get(self, key: str, expires: timedelta) -> str: ...  # Faz 3 için

class MinioStorageService(AbstractStorageService): ...  # mevcut impl
```

Use case'ler `AbstractStorageService` tipini alır; production'da `MinioStorageService`, testlerde `FakeStorageService` inject edilir.

---

## Faz 3 — UX & Upload State Machine (Mobile)

> **Efor:** ~2-3 gün | **Risk:** Orta | **Öncelik:** Faz 2 ile paralel başlatılabilir

### 3.1 Upload State Machine

**Yeni:** `mobile/lib/features/messaging/domain/models/upload_state.dart`

```dart
sealed class MediaUploadState { const MediaUploadState(); }
class UploadIdle     extends MediaUploadState { const UploadIdle(); }
class UploadPicking  extends MediaUploadState { const UploadPicking(); }
class UploadCompress extends MediaUploadState { const UploadCompress(); }
class UploadSending  extends MediaUploadState {
  final double progress;
  const UploadSending(this.progress);
}
class UploadDone    extends MediaUploadState { const UploadDone(); }
class UploadFailed  extends MediaUploadState {
  final String errorKey;
  final Object? retryPayload;
  const UploadFailed(this.errorKey, {this.retryPayload});
}
```

**Yeni:** `MediaUploadNotifier` (AutoDispose Riverpod family, key = otherUserId)  
Upload mantığı `messages_screen.dart`'tan tamamen çıkar.

### 3.2 Optimistik medya baloncuğu

Upload başlar başlamaz geçici balonc (tempId = negatif timestamp) eklenir:

| Tür | Optimistik gösterim |
|---|---|
| Resim | `MemoryImage(bytes)` 200×200 |
| Video | Sıkıştırma çıktısından ilk frame thumbnail |
| Ses | Statik dalga formu + süre etiketi |
| Dosya | Dosya adı + boyut + CircularProgressIndicator |

`UploadFailed` durumunda: kırmızı kenar + "Tekrar dene" butonu. API 200 dönünce tempId swap edilir.

### 3.3 God method parçalama (D-3, C-1)

`_uploadMedia` → `MessageRepository.uploadMedia()` (HTTP katmanı)  
`_buildMsgContent` → ayrı widget'lar:

```
mobile/lib/features/messaging/widgets/message_bubble/
  image_bubble.dart
  video_bubble.dart
  voice_bubble.dart
  file_bubble.dart
  pending_media_bubble.dart
```

### 3.4 Ses kaydı UI iyileştirmesi

- `record` paketi amplitude stream'inden gerçek zamanlı dalga formu (CustomPainter)
- Kalan süre countdown bar (LinearProgressIndicator)
- Ses kaydı süresi backend ile senkron: `MediaConstants.voiceMaxSecs` (60s)
- Swipe-to-cancel `GestureDetector` + `AnimatedContainer`

---

## Faz 4 — Güvenlik: Private DM Bucket + Presigned URL

> **Efor:** ~2 gün | **Risk:** Orta-Yüksek | **Öncelik:** Faz 2 sonrası

### 4.1 Yeni private bucket — `teqlif-dm`

MinIO'da ayrı bucket oluştur:
- `teqlif` (mevcut) → public-read, nginx proxy devam eder
- `teqlif-dm` (yeni) → private, nginx proxy yok

Config'e `minio_dm_bucket: str = "teqlif-dm"` eklenir.  
`SendMediaMessageCommand` DM medyasını `teqlif-dm` bucket'ına yazar.

**Mevcut mesajlar için geçiş:**  
DB'de `/uploads/messages/` prefix'li URL'ler `PresignedUrlService` tarafından tanınır, otomatik presign edilir.

### 4.2 Presigned URL — mesaj payload'ına gömme (N+1 kaldırıldı)

**Endüstri standardı:** Ayrı presign endpoint yok.  
`GetMessagesQuery` mesajları çekerken medya URL'lerini batch presign eder.

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
    await redis.set(f"presign:{self.viewer_id}:{key}", signed, ex=6*24*3600)  # 6 gün
    return signed

# Her mesaj için:
msg.media_url = await self._presign_if_dm(msg.media_url)
msg.thumbnail_url = await self._presign_if_dm(msg.thumbnail_url)
```

**`SendMediaMessageCommand`** da dönüş payload'ında aynı şekilde presign eder.

### 4.3 Presign TTL kararları

| | Değer | Gerekçe |
|---|---|---|
| MinIO presign TTL | 7 gün | Mesaj geçmişi ertesi gün açılınca hâlâ geçerli |
| Redis cache TTL | 6 gün | MinIO'dan 1 gün önce expire → kullanıcı expired URL almaz |
| Mobile cache | Hive + expiresAt | Redis hit olduğu sürece mobile ayrıca fetch yapmaz |

### 4.4 Mobile — PresignedUrlService (sadece fallback için)

Hive cache → expired kontrolü → zaten mesaj listesinde presigned URL geliyor, bu servis yalnızca retry/deep-link senaryoları için:

```dart
class PresignedUrlService {
  // Çağrılır sadece URL expired ise (nadiren)
  // messages GET endpoint'i zaten fresh URL gönderir
  Future<String> refresh(String key) async { ... }
}
```

### 4.5 Erişim kontrolü

Presign üretimi sırasında (backend):
- `sender_id == viewer_id` veya `receiver_id == viewer_id` doğrulanır
- Blok durumunda presign üretilmez → 403
- URL geçerliyken block oluşursa: en fazla 6 gün erişim (kabul edilebilir trade-off — Signal/WhatsApp aynı yaklaşımı kullanır)

---

## Faz 5 — Streaming Upload (Büyük Dosya Güvenliği)

> **Efor:** ~1 gün | **Risk:** Düşük | **Öncelik:** Faz 4 sonrası

### 5.1 Content-Length erken rejection (S-1)

FastAPI middleware ile:
```python
@app.middleware("http")
async def reject_oversized(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > 10 * 1024 * 1024:
        return JSONResponse(status_code=413, content={"success": False, "error": {"code": "FILE_TOO_LARGE"}})
    return await call_next(request)
```

### 5.2 Geçici diske yazarak streaming (S-1)

`upload.py`'de tüm dosya belleğe alınmak yerine temp file'a stream edilir:

```python
with tempfile.NamedTemporaryFile(delete=False) as tmp:
    chunk_size = 64 * 1024  # 64 KB
    total = 0
    async for chunk in file.stream():
        total += len(chunk)
        if total > MAX_SIZE:
            raise BadRequestException(code="FILE_TOO_LARGE")
        tmp.write(chunk)
    tmp_path = tmp.name
# İşleme tmp_path üzerinden devam eder
```

---

## Faz 6 — Clean Architecture Mobile Refactor

> **Efor:** ~1 hafta | **Risk:** Düşük | **Öncelik:** En son, kademeli

### Hedef klasör yapısı

```
mobile/lib/features/messaging/
  constants/
    media_constants.dart          ← Faz 1'den
  domain/
    models/
      media_message.dart          ← tip güvenli entity
      upload_state.dart            ← Faz 3'ten
  repositories/
    message_repository.dart       ← HTTP + hata dönüşümü
  services/
    media_upload_service.dart     ← compress + upload + retry
    presigned_url_service.dart    ← Faz 4'ten
    offline_upload_queue.dart     ← Hive tabanlı offline retry
  viewmodels/
    media_upload_notifier.dart    ← Faz 3'ten
    messages_notifier.dart        ← liste yönetimi
  widgets/
    message_bubble/
      image_bubble.dart
      video_bubble.dart
      voice_bubble.dart
      file_bubble.dart
      pending_media_bubble.dart
    attach_sheet.dart
    voice_recorder_widget.dart
```

### Offline upload queue

`ConnectivityService` stream bağlantı geldiğinde Hive kuyruğunu tüketir. Retry: exponential backoff, max 3 deneme.

---

## Özet Tablo

| Faz | İçerik | Efor | Risk | Etki | Durum |
|---|---|---|---|---|---|
| **1** | Limitler merkezi, güvenlik bugları, declined guard, ARB | ~1 gün | Düşük | Yüksek | ⬜ |
| **2** | Strategy pattern, CQRS, pagination, AbstractStorage | ~2 gün | Orta | Yüksek | ⬜ |
| **3** | State machine, optimistik UI, god method parçalama | ~3 gün | Orta | Yüksek | ⬜ |
| **4** | Private DM bucket, presigned URL (payload gömme, Redis 6 gün) | ~2 gün | Orta-Yüksek | Çok Yüksek | ⬜ |
| **5** | Streaming upload, Content-Length middleware | ~1 gün | Düşük | Orta | ⬜ |
| **6** | Clean arch refactor, offline queue | ~1 hafta | Düşük | Teknik borç | ⬜ |

## Bağımlılık Grafiği

```
Faz 1 ──► Faz 2 ──► Faz 4 ──► Faz 5
  │                               ▲
  └──────► Faz 3 ─────────────────┘
                    Faz 6 (Faz 3 widget'larını içerir, paralel başlatılabilir)
```

- Faz 1 → Faz 2 ve Faz 3 paralel başlatılabilir
- Faz 4 için Faz 2 (AbstractStorageService + presign method) tamamlanmış olmalı
- Faz 6 bağımsız, Faz 3 çıktılarını absorbe eder

---

## Kritik Kural Değişiklikleri (v1.0 → v1.1)

| # | v1.0 | v1.1 |
|---|---|---|
| 1 | Ayrı `GET /api/media/presign` endpoint | Presigned URL mesaj payload'ına gömülür — N+1 yok |
| 2 | Tüm bucket private, nginx kapatılır | Ayrı `teqlif-dm` private bucket — public içerikler etkilenmez |
| 3 | Presign TTL 1 saat | Presign TTL 7 gün, Redis cache 6 gün |
| 4 | — | Strategy pattern ile `_process_media` parçalanması eklendi |
| 5 | — | CQRS ihlali (query içinde write) düzeltmesi eklendi |
| 6 | — | Streaming upload + Content-Length middleware (Faz 5) eklendi |
| 7 | — | Orphan file koruması eklendi |
| 8 | — | Magic byte doğrulaması tüm dosya tiplerine genişletildi |
