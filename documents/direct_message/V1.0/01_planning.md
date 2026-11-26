# DM Offline-First: SQLite Kalıcı Depolama

**Tarih:** 26 Kasım 2026  
**Durum:** Planlandı  
**Öncelik:** Yüksek  

---

## İçindekiler

1. [Problem](#1-problem)
2. [Mevcut Mimari Analizi](#2-mevcut-mimari-analizi)
3. [Karar](#3-karar)
4. [Değerlendirilen Alternatifler](#4-değerlendirilen-alternatifler)
5. [Hedef Mimari](#5-hedef-mimari)
6. [Şema](#6-şema)
7. [Bileşen Tasarımı](#7-bileşen-tasarımı)
8. [Değişecek Dosyalar](#8-değişecek-dosyalar)
9. [Uygulama Planı](#9-uygulama-planı)
10. [Migration Stratejisi](#10-migration-stratejisi)
11. [Riskler ve Önlemler](#11-riskler-ve-önlemler)
12. [Kabul Kriterleri](#12-kabul-kriterleri)

---

## 1. Problem

### 1.1 Kullanıcı Deneyimi Sorunu

Kullanıcı "Mesajlarım" ekranında konuşma listesini offline görebiliyor (Hive cache, 1 saat TTL) ancak herhangi bir konuşmaya girdiğinde **"İnternet bağlantısı yok."** hatası alıyor.

### 1.2 Teknik Kök Neden

```
Conversation listesi cache (cacheMessages)   TTL: 1 saat  → offline görünür
Thread içeriği cache (cacheThreadKey)         TTL: 30 dk   → hızla boşalır
```

WS olayları (`appendToCache`, `removeFromCache`, `markReadInCache`) cache'i yalnızca **uygulama açıkken** güncel tutar. Uygulama kapatılınca Hive TTL sayacı tıklamaya devam eder. Kullanıcı 30 dakika sonra tekrar açtığında thread cache'leri boştur; `MessageThreadViewModel.build()` `loading: true` ile başlar, network yoksa `hasError: true, messages.isEmpty` → `NetworkErrorWidget`.

### 1.3 Ara Çözümün Sınırları

Thread TTL 30 dk → 7 gün'e uzatıldı ve `preWarmThread()` ile top-5 konuşma proaktif ısıtıldı. Ancak bu **hâlâ TTL tabanlı**:

- Kullanıcı 7+ gün app'i açmazsa cache boşalır
- Yeni cihaza geçişte Hive verisi taşınmaz; sıfırdan başlanır
- Hiç açılmamış konuşmalar (top-5 dışı) offline erişilemiyor kalır

---

## 2. Mevcut Mimari Analizi

### 2.1 Veri Akışı

```
Server
  │  REST GET /messages/{userId}
  ▼
ApiService.get() — SWR (Stale-While-Revalidate)
  │  1. Hive cache varsa → anında emit
  │  2. Network fetch → Hive'a yaz → emit
  ▼
MessageRepository.getThread()
  │  _mergePending: OfflineQueue bekleyenleri ekle
  ▼
MessageThreadViewModel._startStream()
  │  Stream<List<DirectMessage>>
  ▼
DirectChatScreen
```

### 2.2 Cache Güncelleme Yolları (mevcut)

| Olay | Güncelleme | Yol |
|------|-----------|-----|
| WS `message` | `appendToCache` → Hive patch | ✅ Anında |
| WS `message_deleted` | `removeFromCache` → Hive patch | ✅ Anında |
| WS `messages_read` | `markReadInCache` → Hive patch | ✅ Anında |
| Thread açıldı | `getThread()` → SWR → Hive yaz | ✅ Anında |
| `getPage()` scroll | Sadece RAM (Hive'a yazılmıyor) | ❌ Kaybolur |
| App kapalı > TTL | Cache silinir | ❌ Veri yok |
| Yeni cihaz | Hive boş | ❌ Veri yok |

### 2.3 `OfflineQueueService` (ayrı sorumluluk)

Hive'da `offline_messages_queue` box'ı: gönderilemeyen mesajları tutar, bağlantı gelince `drain()` ile sırayla gönderir. Bu **DM offline storage ile ayrı bir sorumluluktur** ve bu migrasyondan etkilenmez.

---

## 3. Karar

**DM thread içerikleri için Hive TTL cache yerine SQLite kalıcı depolama kullanılır.**

### 3.1 Gerekçe

| Kriter | Hive TTL | SQLite |
|--------|----------|--------|
| Offline erişim | TTL dolunca yok | Kalıcı |
| Yeni cihaz | Yok | Yok (server'dan çekilir) |
| WS ile güncelleme | read-modify-write | Direct upsert |
| Pagination geçmişi | Kaybolur | Kalıcı birikir |
| Sliding window sınırı | 50 mesaj | Sınırsız |
| Storage büyümesi | Otomatik TTL ile temizlenir | Manuel silme |
| Mimari karmaşıklık | Düşük | Orta |

WhatsApp, Telegram ve Signal mesaj geçmişini lokal SQLite veritabanında kalıcı olarak saklar. Sunucu yalnızca **henüz alınmamış yeni mesajlar** için kullanılır; lokal DB görüntüleme için kaynak gerçekliği (source of truth) olur.

### 3.2 Kapsam

Bu ADR **yalnızca DM thread içeriklerini** kapsar. Şunlar kapsam dışıdır:
- `OfflineQueueService` (pending send queue) → Hive'da kalır
- Conversation listesi (`cacheMessages`) → Hive'da kalır (liste küçük, TTL yeterli)
- Medya dosyaları (DM görselleri) → MinIO + `CacheService` kalır

---

## 4. Değerlendirilen Alternatifler

### A. TTL'yi Daha da Uzatmak (Reddedildi)

7 gün → 30 gün veya 1 yıl. Hive'da kalınır.

**Reddedilme gerekçesi:** Hive TTL tabanlı cache mimarisi sorunun kökünü çözmez. Yalnızca pencereyi genişletir. Yeni cihaza geçişte veri hâlâ sıfırlanır. Pagination scroll ile yüklenen eski mesajlar hâlâ kalıcı saklanmaz.

### B. Drift (ORM, Kod Üretimi)

Type-safe şema, ilişkisel sorgular, migration yönetimi.

**Reddedilme gerekçesi:** Tek tablo, basit CRUD, ilişki yok. Drift'in sağladığı avantajlar bu kullanım senaryosuna orantısız karmaşıklık katar (kod üretimi, build_runner bağımlılığı).

### C. Seçilen: `sqflite` (Kabul Edildi)

Düşük seviye SQLite wrapper. Kod üretimi yok, battle-tested, pub.dev'de Flutter'ın en yaygın SQLite kütüphanesi. Tek tablo için ideal.

---

## 5. Hedef Mimari

### 5.1 Yeni Veri Akışı

```
Server
  │  REST GET /messages/{userId}
  ▼
ApiService.get() — cacheKey: null (Hive bypass)
  │  Network response → DmDatabase.upsertMessages()
  ▼
MessageRepository.getThread()
  │  1. DmDatabase.getThread() → anında emit (SQLite, <1ms)
  │  2. Network fetch → upsert → emit
  │  _mergePending: OfflineQueue bekleyenleri ekle
  ▼
MessageThreadViewModel._startStream()
  │  Stream<List<DirectMessage>>  (arayüz değişmez)
  ▼
DirectChatScreen  (değişmez)
```

### 5.2 Cache Güncelleme Yolları (hedef)

| Olay | Güncelleme | Yol |
|------|-----------|-----|
| WS `message` | `DmDatabase.appendMessage()` | ✅ Anında, kalıcı |
| WS `message_deleted` | `DmDatabase.deleteMessage()` | ✅ Anında, kalıcı |
| WS `messages_read` | `DmDatabase.markReadByThread()` | ✅ Anında, kalıcı |
| Thread açıldı | `getThread()` → upsert | ✅ Anında, kalıcı |
| `getPage()` scroll | `DmDatabase.upsertMessages()` | ✅ Anında, kalıcı |
| App kapalı > N gün | — | ✅ Hâlâ erişilebilir |
| Yeni cihaz | SQLite boş → SWR doldurur | ✅ Thread açılınca |

### 5.3 Katman Sorumlulukları

```
DirectChatScreen          → UI, WS olaylarını ViewModel'e iletir
MessageThreadViewModel    → State yönetimi, build() async olur
MessageRepository         → Veri kaynağı koordinasyonu (DB + network)
DmDatabase                → SQLite erişim katmanı (yeni)
ApiService                → Network SWR (cacheKey: null ile çağrılır)
OfflineQueueService       → Pending send queue (değişmez)
```

---

## 6. Şema

### 6.1 Tablo Tanımı

```sql
CREATE TABLE IF NOT EXISTS dm_messages (
  id              INTEGER PRIMARY KEY,
  thread_id       INTEGER NOT NULL,
  sender_id       INTEGER NOT NULL,
  receiver_id     INTEGER NOT NULL,
  content         TEXT,
  content_type    TEXT NOT NULL DEFAULT 'text',
  media_url       TEXT,
  thumbnail_url   TEXT,
  file_name       TEXT,
  file_size_bytes INTEGER,
  duration_secs   INTEGER,
  is_read         INTEGER NOT NULL DEFAULT 0,
  created_at      TEXT NOT NULL,
  is_pending      INTEGER NOT NULL DEFAULT 0,
  is_failed       INTEGER NOT NULL DEFAULT 0,
  local_id        TEXT
);

CREATE INDEX IF NOT EXISTS idx_dm_thread_time
  ON dm_messages(thread_id, created_at ASC);
```

### 6.2 Alan Açıklamaları

| Alan | Kaynak | Not |
|------|--------|-----|
| `id` | Server ID | Pending mesajlarda negatif (`-(queued_at)`) |
| `thread_id` | `other_user_id` | `StorageService.cacheThreadKey` ile paralel |
| `content_type` | `MessageContentType` enum | `'text'` \| `'image'` \| `'video'` \| `'voice'` \| `'file'` |
| `is_read` | boolean → 0/1 | SQLite boolean yok |
| `is_pending` | `DirectMessage.isPending` | OfflineQueue drain'den önce |
| `is_failed` | `DirectMessage.isFailed` | Gönderim başarısız |
| `local_id` | OfflineQueue referansı | Deduplication için |

### 6.3 `thread_id` Tanımı

`thread_id = other_user_id`. Her kullanıcı çifti için tek bir thread. Mesaj yönü (gönderen/alan) `sender_id` ve `receiver_id` ile belirlenir.

### 6.4 Veritabanı Dosya Konumu

```
iOS:  <Documents>/dm_messages.db
Android: <data/data/{package}>/databases/dm_messages.db
```

Kullanıcıya özel namespace yoktur — `thread_id` ve `sender_id`/`receiver_id` ile hangi kullanıcıya ait olduğu belirlenir. Logout'ta tüm tablo temizlenir.

### 6.5 Migration Yönetimi

`sqflite`'ın `onUpgrade` callback'i kullanılır. İlk versiyon: 1.

```dart
static const _kDbVersion = 1;

Future<void> _onCreate(Database db, int version) async {
  await db.execute(_kCreateTable);
  await db.execute(_kCreateIndex);
}

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  // v2'de yeni kolon eklenirse: ALTER TABLE ...
}
```

---

## 7. Bileşen Tasarımı

### 7.1 `DmDatabase` (Yeni — `services/dm_database.dart`)

Tek sorumluluk: SQLite erişim katmanı. ViewModel veya iş mantığı içermez.

```dart
class DmDatabase {
  static Database? _db;

  /// Uygulama başlangıcında main.dart'ta çağrılır.
  static Future<void> init() async { ... }

  /// thread_id'ye ait mesajları created_at ASC sıralamasıyla döner.
  Future<List<Map<String, dynamic>>> getThread(int threadId) async { ... }

  /// Mesaj listesini INSERT OR REPLACE ile yazar.
  Future<void> upsertMessages(int threadId, List<Map<String, dynamic>> msgs) async { ... }

  /// Tek mesaj ekler (WS yeni mesaj olayı).
  Future<void> appendMessage(int threadId, Map<String, dynamic> msg) async { ... }

  /// Mesajı ID ile siler (WS silme olayı veya kullanıcı silme).
  Future<void> deleteMessage(int messageId) async { ... }

  /// thread_id içinde myId'nin gönderdiği mesajları okundu işaretler.
  Future<void> markReadByThread(int threadId, int myId) async { ... }

  /// Konuşmanın tüm mesajlarını siler (konuşma silme).
  Future<void> deleteThread(int threadId) async { ... }

  /// Logout'ta tüm mesajları temizler.
  Future<void> clearAll() async { ... }
}

final dmDatabaseProvider = Provider<DmDatabase>((_) => DmDatabase());
```

**Neden singleton değil Provider?** Riverpod test isolation için — test ortamında mock `DmDatabase` enjekte edilebilir.

### 7.2 `MessageRepository` Değişiklikleri

```dart
// ÖNCE (Hive)
List<DirectMessage>? getCachedThread(int otherUserId, int myUserId) {
  final raw = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId))?.data;
  ...
}

// SONRA (SQLite — async)
Future<List<DirectMessage>?> getCachedThread(int otherUserId, int myUserId) async {
  final rows = await _db.getThread(otherUserId);
  if (rows.isEmpty) return null;
  return _mergePending(rows, otherUserId, myUserId)
      ?.map(DirectMessage.fromJson)
      .toList();
}
```

```dart
// ÖNCE
Stream<List<DirectMessage>> getThread(int otherUserId, int myUserId) =>
    _api.get<...>(cacheKey: StorageService.cacheThreadKey(otherUserId), cacheTtl: ...).map(...)

// SONRA — SQLite emit + network upsert
Stream<List<DirectMessage>> getThread(int otherUserId, int myUserId) async* {
  final dbRows = await _db.getThread(otherUserId);
  yield _buildList(dbRows, otherUserId, myUserId);  // DB'den anında

  try {
    await for (final maps in _api.get<List<Map<String, dynamic>>>(
      url: '...', cacheKey: null, fromJson: ...)) {
      await _db.upsertMessages(otherUserId, maps);  // DB'ye yaz
      yield _buildList(maps, otherUserId, myUserId); // taze veri
    }
  } catch (_) {
    if (dbRows.isEmpty) rethrow;
    // DB zaten emit edildi — ağ hatası sessizce geçer
  }
}
```

```dart
// ÖNCE — getPage sadece RAM'de
Future<List<DirectMessage>> getPage(int otherUserId, int beforeId) async {
  final body = await _client.callList(...);
  return body.cast<Map<String, dynamic>>().map(DirectMessage.fromJson).toList();
}

// SONRA — eski sayfalar da DB'ye yazılır
Future<List<DirectMessage>> getPage(int otherUserId, int beforeId) async {
  final body = await _client.callList(...);
  final maps = body.cast<Map<String, dynamic>>();
  await _db.upsertMessages(otherUserId, maps);  // ← yeni
  return maps.map(DirectMessage.fromJson).toList();
}
```

WS patch metodları:

```dart
// appendToCache   → _db.appendMessage(otherUserId, msg)
// removeFromCache → _db.deleteMessage(messageId)
// markReadInCache → _db.markReadByThread(otherUserId, myUserId)
// _patchCache     → kaldırılır (artık gerekli değil)
```

### 7.3 `MessageThreadViewModel` Değişikliği

```dart
// ÖNCE — sync build
@override
MessageThreadState build(int otherUserId) {
  final cached = ref.read(messageRepositoryProvider).getCachedThread(otherUserId, _myId);
  ...
  return MessageThreadState(messages: cached ?? [], loading: cached == null);
}

// SONRA — async build (SQLite okuma <1ms)
@override
Future<MessageThreadState> build(int otherUserId) async {
  final cached = await ref.read(messageRepositoryProvider).getCachedThread(otherUserId, _myId);
  ref.onDispose(() => _sub?.cancel());
  Future.microtask(() => _startStream(otherUserId));
  return MessageThreadState(messages: cached ?? [], loading: cached == null);
}
```

Ekran `vmAsync.valueOrNull ?? const MessageThreadState()` kullandığı için `AsyncLoading` döneminde boş state düşer (spinner), SQLite okuma biter biter mesajlar görünür. Gecikme algılanamaz düzeyde.

### 7.4 `preWarmThread` Güncellemesi

```dart
// ÖNCE — Hive kontrolü
Future<void> preWarmThread(int otherUserId, int myUserId) async {
  final existing = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId));
  if (existing != null) return;
  ...
}

// SONRA — SQLite kontrolü
Future<void> preWarmThread(int otherUserId, int myUserId) async {
  final existing = await _db.getThread(otherUserId);
  if (existing.isNotEmpty) return;  // zaten DB'de → 0 ağ isteği
  try {
    await getThread(otherUserId, myUserId).drain<void>();
  } catch (_) {}
}
```

---

## 8. Değişecek Dosyalar

| Dosya | Değişim Türü | Özet |
|-------|-------------|------|
| `mobile/pubspec.yaml` | Güncelleme | `sqflite`, `path` bağımlılıkları |
| **`mobile/lib/services/dm_database.dart`** | **Yeni** | SQLite erişim katmanı |
| `mobile/lib/repositories/message_repository.dart` | Refactor | Hive → SQLite; `getPage` DB'ye yazar |
| `mobile/lib/screens/viewmodels/message_thread_view_model.dart` | Küçük | `build()` → `async` |
| `mobile/lib/main.dart` | Küçük | `DmDatabase.init()` eklenir |

**Değişmeyen dosyalar:**
- `DirectChatScreen` — WS handling, UI
- `MessagesTabViewModel` — conversation listesi (Hive'da kalır)
- `OfflineQueueService` — pending send queue (Hive'da kalır)
- `DirectMessage` model — toJson/fromJson değişmez
- `MessageThreadState` — hiç değişmez
- Backend — sıfır değişiklik

---

## 9. Uygulama Planı

### Faz 1: Altyapı

1. `pubspec.yaml`: `sqflite` ve `path` ekle, `flutter pub get`
2. `dm_database.dart` oluştur: `init`, `getThread`, `upsertMessages`, `appendMessage`, `deleteMessage`, `markReadByThread`, `deleteThread`, `clearAll`
3. `main.dart`: `DmDatabase.init()` app başlangıcına ekle

### Faz 2: Repository Migrasyonu

4. `message_repository.dart`:
   - `DmDatabase` bağımlılığını constructor'a ekle
   - `getCachedThread()` → async, SQLite'tan oku
   - `getThread()` → async*, DB emit + network upsert
   - `getPage()` → upsertMessages ekle
   - `appendToCache()` → `_db.appendMessage()`
   - `removeFromCache()` → `_db.deleteMessage()`
   - `markReadInCache()` → `_db.markReadByThread()`
   - `_patchCache()` → kaldır
   - `preWarmThread()` → SQLite kontrolü
   - `messageRepositoryProvider` → `DmDatabase` inject et

### Faz 3: ViewModel

5. `message_thread_view_model.dart`: `build()` → `async`

### Faz 4: Test

6. Staging'de manuel test:
   - Thread aç → kapat → uçak modu → tekrar aç → mesajlar görünmeli
   - Yeni mesaj gönder → uçak modunda gönder → online ol → deliver olmalı
   - Scroll up (pagination) → uçak moduna geç → eski mesajlar hâlâ görünmeli
   - Çok eski thread (hiç açılmamış, pre-warm ile ısıtılmış) → offline erişim

### Faz 5: Deploy

7. `git commit` + `git push` + `sudo teqlif-restart` (node1, node5)

---

## 10. Migration Stratejisi

**Sıfır migration.** SQLite başlangıçta boş açılır.

- Mevcut kullanıcılar: Hive cache'leri kullanılmaz hale gelir; uygulama güncellendiğinde SQLite boş başlar. Kullanıcı her konuşmayı açtığında SQLite dolar.
- `preWarmThread`: En son 5 konuşma background'da otomatik ısıtılır — kullanıcı hiç dokunmasa bile offline erişilebilir olur.
- Hive thread cache'leri (`u_{uid}_chat_{otherId}`): artık okunmaz/yazılmaz; mevcut TTL'leriyle kendi kendine eriyip gider.

---

## 11. Riskler ve Önlemler

| Risk | Olasılık | Etki | Önlem |
|------|---------|------|-------|
| SQLite init hatası (disk dolu, izin yok) | Düşük | Yüksek | `init()` hatası → app açılmasın, Sentry'e logla |
| `upsertMessages` performansı (büyük batch) | Orta | Orta | Transaction kullan: `db.transaction((txn) async { ... })` |
| Farklı kullanıcılar aynı cihazda | Düşük | Yüksek | Logout'ta `clearAll()` çağrılmalı |
| `getThread()` stream'i subscribe edilmeden önce DB hatası | Düşük | Orta | `getCachedThread` null döner → `loading: true` → screen graceful |
| Çok büyük thread (binlerce mesaj) | Düşük | Orta | `getThread` LIMIT 200, `getPage` scroll ile gerisi |
| async `build()` → kısa AsyncLoading | Yüksek | Düşük | SQLite <1ms; `valueOrNull ?? MessageThreadState()` ile guard |

---

## 12. Kabul Kriterleri

- [ ] Uçak modunda, daha önce açılmış bir thread'in son 50 mesajı görünür
- [ ] Uçak modunda, pre-warm ile ısıtılmış (hiç açılmamış) top-5 thread görünür
- [ ] Uçak modunda scroll up → daha önce yüklenmiş eski sayfalar görünür
- [ ] WS ile gelen yeni mesaj SQLite'a yazılır ve offline'da da görünür
- [ ] WS ile silinen mesaj SQLite'tan silinir
- [ ] Logout'ta tüm mesajlar SQLite'tan temizlenir
- [ ] Başka kullanıcıyla login → eski kullanıcının mesajları görünmez
- [ ] `NetworkErrorWidget` thread'in hiç açılmadığı (DB boş + offline) durumda gösterilir
- [ ] `StaleDataBanner` DB dolu + online fetch başarısız durumunda gösterilir
