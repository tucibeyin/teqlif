# Cache V1.3 — Mesaj Thread Cache: Analiz ve Tasarım

**Tarih:** Ekim 2026  
**Kapsam:** DM thread mesajları (metin + medya) ve mesaj isteği thread'leri  
**Önceki versiyon:** [V1.2](../V1.2/01_findings.md) — SWR geçişi + Repository katmanı

---

## §0 Bağlam

V1.2 sonrasında mesajlaşma sisteminin cache durumu:

| Veri | Cache | TTL | SWR |
|------|-------|-----|-----|
| Konuşma listesi (`cache_messages`) | ✅ Hive | 1s | ✅ |
| Mesaj istekleri listesi (`cache_message_requests`) | ✅ Hive | 1s | ✅ |
| **Thread içi mesajlar** (`chat_{userId}`) | ⚠️ Hive | **2 dakika** | ✅ |
| Thread durumu (`accepted/pending/declined`) | ❌ | — | — |
| Arşiv mesajları | ❌ | — | — |
| DM medya (resim/video thumb) | ⚠️ Disk | 2 gün (URL bazlı) | — |

**Mevcut uygulama noktası:** `messages_screen.dart:1302` — `_DirectChatScreenState._loadMessages()`  
`ApiService.get<T>()` SWR zaten var, `cacheKey: 'chat_${widget.otherUserId}'`, TTL=2dk.

---

## §1 Sorun Tespiti

### S1 — Sayfalama Eksikliği (Mobil Taraf)

`GET /messages/{otherUserId}` zaten `MSG_PAGE_SIZE = 50` ile sınırlıdır (`media_limits.py`).  
Backend her yanıtta en fazla 50 mesaj döndürür; 1000+ mesajlık thread için bu yanıt her seferinde son 50'yi verir.

**Eksik olan tek parça:** Mobil `before_id` parametresini hiç kullanmıyor.  
Kullanıcı yukarı scroll yaptığında eski mesajları çekecek mekanizma yok — thread geçmişine erişilemiyor.

**Sorun senaryosu:** 200 mesajlık bir thread'de kullanıcı yukarı kaydırırsa 150. mesajı göremez; API'den istenemiyor.

**Çözüm (Instagram/WhatsApp/Telegram modeli):**
- Son 50 mesaj Hive'a cache'lenir (anlık açılış)
- Yukarı scroll → `before_id={oldest_id}&limit=50` ile önceki sayfa çekilir, sadece RAM'de tutulur
- Eski sayfalar diske yazılmaz — oturumdan oturuma nadiren okunur, Hive'ı şişirmenin değeri yoktur

**Backend altyapısı hazır:** `get_messages_query.py:42` — `before_id: int | None = None`.  
**Mobil eksik:** `notification_service.dart:107` — `before_id` parametresi iletilmiyor.

---

### S2 — TTL Çok Kısa (2 Dakika)

`chat_{otherUserId}` TTL=2dk, conversation listesi TTL=1 saatken thread içi mesajlar için mantıksız kısa.

Mesajlar **append-only** veri: eklenir, nadiren silinir, içeriği değişmez. 2 dakikadan sonra ekrandan ayrılıp dönmek tam yeniden yükleme tetikliyor.

**Öneri:** TTL → 30 dakika (ratings, blocked_users ile aynı)

---

### S3 — Medya cacheKey Yok (Presigned URL Riski)

`messages_screen.dart:2117` ve `2155`:
```dart
CachedNetworkImage(
  imageUrl: ref.read(apiClientProvider).imgUrl(mediaUrl),
  cacheManager: TeqlifCacheManager(),  // cacheKey YOK
```

DM medyası `teqlif-dm` bucket'ında **private** — API her sorguda presigned URL üretiyor (`_PRESIGN_TTL = 7 gün`, Redis'te 6 gün cache'li).

**Risk analizi:**
- Şu an TTL=2dk → presign süresi dolmadan Hive yenileniyor → sorun yok
- TTL=30dk yapılırsa → 6 günlük Redis cache içinde aynı presigned URL dönüyor → hâlâ sorun yok
- TTL=7+ gün yapılırsa VEYA Redis cache'i expire olursa → yeni presigned URL → disk cache key değişir → miss

**Öneri (preemptive):** `cacheKey: 'dm_img_${msgId}'` ekle — URL rotation'dan bağımsız kararlı key.

---

### S4 — ADR §22 İhlali — ViewModel/Repository Yok

`_DirectChatScreenState` (`messages_screen.dart:1220`) doğrudan:
- `ref.read(apiServiceProvider).get()` çağırıyor → ViewModel'de HTTP çağrısı (ihlal)
- `ref.read(apiClientProvider)` kullanıyor → ViewModel'de config erişimi (ihlal)
- `ref.read(notificationServiceProvider)` kullanıyor → ViewModel'de servis çağrısı (ihlal)

Bu, V1.2'de `BlockedUsersViewModel`, `FollowListViewModel` vb.'de düzeltilen pattternin aynısı.

---

### S5 — WS Event'leri Hive'ı Güncellemıyor

`messages_screen.dart:1431` — `message_deleted` eventi:
```dart
setState(() => _messages.removeWhere((m) => m['id'] == id));
// Hive güncellenmez → uygulama yeniden başlatılırsa silinen mesaj görünür
```

`messages_screen.dart:1394` — `messages_read` eventi:
```dart
_messages = _messages.map((m) => {...m, 'is_read': true}).toList();
// Hive güncellenmez → restart sonrası okunmamış görünür
```

TTL=2dk iken bu sorun kısa süre içinde kendiliğinden düzeliyor. TTL uzatılınca bug süresi uzar.

---

### S6 — OfflineQueueService Repository Dışında Kaldı

`messages_screen.dart:1322` — `_loadMessages()` içinde `OfflineQueueService.getPendingForReceiver()` çağrısı:
```dart
final pending = OfflineQueueService.getPendingForReceiver(widget.otherUserId);
final merged = List<Map<String, dynamic>>.from(data);
// ... bekleyen mesajlar negatif ID ile merge edilir
```

Repository katmanına geçildiğinde bu merge mantığı ekranda bırakılırsa:
- `MessageRepository.getCachedThread()` yalnızca Hive verisi döner
- `ViewModel.build()` ekrandan sorumlu olmadığı için offline kuyruğu göremez
- Sonuç: internet yokken gönderilen ama henüz teslim edilmemiş mesajlar **UI'dan kaybolur**

**Düzeltme:** `getCachedThread()` ve `getThread()` her ikisi de `_mergePending()` ile OfflineQueue'yu birleştirir (bkz. Karar 5).

---

### S7 — Cache Key Sabiti Yok

`'chat_${widget.otherUserId}'` magic string olarak `messages_screen.dart:1313`'te inline yazılmış.  
`StorageService`'te sabiti yok — cache taxonomy'ye dahil değil, başka yerde çakışma riski var.

---

---

## §2 Tasarım Kararları

### Karar 1 — Sayfalama (Pagination)

**V1.3 kısa vade:** Tek sayfa, yalnızca son 50 mesaj cache'lenir.

```
GET /messages/{otherUserId}?limit=50
```

Cache'de: `cache_chat_{userId}` → son 50 mesaj (JSON list).

**Yukarı scroll (history):** `before_id` ile sayfalama, cache'siz:
```
GET /messages/{otherUserId}?before_id={oldest_id}&limit=50
```
Bu yanıtlar cache'lenmez — geçmiş sayfalar oturumdan oturuma nadiren okunur, Hive'ı şişirmenin değeri yoktur.

**Arşiv:** Mevcut gibi — cache yok, `getArchivedMessages` direkt API.

---

### Karar 2 — TTL

| Nesne | Mevcut | Yeni |
|-------|--------|------|
| Son 50 mesaj (`cache_chat_{userId}`) | 2 dakika | **30 dakika** |
| Konuşma listesi (`cache_messages`) | 1 saat | Değişmez |
| Medya disk cache | 2 gün | Değişmez |

---

### Karar 3 — Stabil Medya cacheKey

Presigned URL rotation'dan bağımsız, mesaj ID'ye dayalı key:

```dart
// Resim thumbnail / tam boyut
cacheKey: 'dm_img_${msgId}'

// Video thumbnail
cacheKey: 'dm_thumb_${msgId}'

// Ses / dosya: disk'e indirilir, TeqlifCacheManager kullanılmaz
```

---

### Karar 4 — StorageService Cache Key Sabitleri

```dart
static String cacheThreadKey(int userId) => 'cache_chat_$userId';
static String cacheDmImageKey(int msgId)  => 'dm_img_$msgId';
static String cacheDmThumbKey(int msgId)  => 'dm_thumb_$msgId';
```

`'cache_'` prefix zorunlu — taxonomy convention.

---

### Karar 5 — MessageRepository

ADR §22 uyumu için yeni repository:

```dart
class MessageRepository {
  final ApiClient _client;
  final ApiService _api;
  final CacheService _cache;

  // Synchronous cache read — ViewModel.build() için
  // Hive cache (Map) + OfflineQueue → DirectMessage listesi döner
  List<DirectMessage>? getCachedThread(int otherUserId, int myUserId) {
    final raw = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId))?.data;
    final cached = raw != null ? (raw as List).cast<Map<String, dynamic>>() : null;
    return _mergePending(cached, otherUserId, myUserId)
        ?.map(DirectMessage.fromJson)
        .toList();
  }

  // SWR stream — son 50 mesaj + offline pending mesajları birleşik döner
  // ApiService Map<> saklar (Hive JSON uyumu); stream çıkışında DirectMessage'a dönüştürülür
  Stream<List<DirectMessage>> getThread(int otherUserId, int myUserId) =>
      _api.get<List<Map<String, dynamic>>>(
        url: '${_client.config.baseUrl}/messages/$otherUserId?limit=50',
        cacheKey: StorageService.cacheThreadKey(otherUserId),
        fromJson: (raw) => (raw as List).cast<Map<String, dynamic>>(),
        cacheTtl: const Duration(minutes: 30),
      ).map((maps) =>
          (_mergePending(maps, otherUserId, myUserId) ?? maps)
              .map(DirectMessage.fromJson)
              .toList());

  // OfflineQueue'deki bekleyen mesajları ham Map listesine ekler.
  // Sunucu zaten teslim etmişse (içerik eşleşmesi) eklenmez.
  // Map seviyesinde çalışır — Hive serileştirme sınırı burada kalır.
  List<Map<String, dynamic>>? _mergePending(
    List<Map<String, dynamic>>? base,
    int otherUserId,
    int myUserId,
  ) {
    if (base == null) return null;
    final pending = OfflineQueueService.getPendingForReceiver(otherUserId);
    if (pending.isEmpty) return base;
    final merged = List<Map<String, dynamic>>.from(base);
    for (final p in pending) {
      final alreadyDelivered = base.any(
        (m) => m['content'] == p['content'] && (m['sender_id'] as int?) == myUserId,
      );
      if (!alreadyDelivered) {
        merged.add({
          'id': -(p['queued_at'] as int),
          'sender_id': myUserId,
          'receiver_id': otherUserId,
          'content': p['content'] as String,
          'is_read': false,
          'created_at': DateTime.fromMillisecondsSinceEpoch(p['queued_at'] as int)
              .toUtc().toIso8601String(),
          '_pending': true,
          '_local_id': p['local_id'] as String?,
        });
      }
    }
    return merged;
  }

  // Önceki sayfa — cache'siz, DirectMessage döner
  Future<List<DirectMessage>> getPage(int otherUserId, int beforeId) async {
    final body = await _client.callList(
      () async => http.get(
        Uri.parse('${_client.config.baseUrl}/messages/$otherUserId?before_id=$beforeId&limit=50'),
        headers: await _buildHeaders(),
      ),
    );
    return body
        .cast<Map<String, dynamic>>()
        .map(DirectMessage.fromJson)
        .toList();
  }

  // Mutation: mesaj sil → cache güncelle
  Future<bool> deleteMessage(int messageId, int otherUserId, {String scope = 'everyone'}) async {
    final ok = await _client.call(
      () async => http.delete(
        Uri.parse('${_client.config.baseUrl}/messages/$messageId?scope=$scope'),
        headers: await _buildHeaders(),
      ),
    );
    if (ok != null) {
      await _patchCache(otherUserId, (msgs) => msgs..removeWhere((m) => m['id'] == messageId));
    }
    return ok != null;
  }

  // WS event: is_read güncelle → cache'e yaz
  // messages_read eventi: karşı taraf BENIM mesajlarımı okudu → sender_id == myUserId olanlar okunmuş
  Future<void> markReadInCache(int otherUserId, int myUserId) async {
    await _patchCache(otherUserId, (msgs) =>
      msgs.map((m) => (m['sender_id'] as int?) == myUserId ? {...m, 'is_read': true} : m).toList()
    );
  }

  // WS event: yeni mesaj ekle → cache'e yaz (sliding window: max 50)
  Future<void> appendToCache(int otherUserId, Map<String, dynamic> msg) async {
    await _patchCache(otherUserId, (msgs) {
      final updated = [...msgs, msg];
      return updated.length > 50 ? updated.sublist(updated.length - 50) : updated;
    });
  }

  // WS event: mesaj sil → cache'ten kaldır
  Future<void> removeFromCache(int otherUserId, int messageId) async {
    await _patchCache(otherUserId, (msgs) => msgs..removeWhere((m) => m['id'] == messageId));
  }

  Future<void> _patchCache(
    int otherUserId,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) fn,
  ) async {
    final cached = getCachedThread(otherUserId);
    if (cached == null) return;
    await _cache.saveData(
      StorageService.cacheThreadKey(otherUserId),
      fn(List.from(cached)),
      ttl: const Duration(minutes: 30),
    );
  }
}
```

---

### Karar 6 — MessageThreadViewModel

`_DirectChatScreenState` (3740 satır) içindeki tüm ağ ve cache mantığını ayrı bir ViewModel'e taşı.  
`DirectChatScreen` yalnızca UI render ve kullanıcı aksiyonlarını ViewModel'e iletir.

**Tip:** `AutoDisposeFamilyAsyncNotifier<MessageThreadState, int>` — `arg = otherUserId`

```dart
class MessageThreadState {
  final List<DirectMessage> messages;
  final bool loading;
  final bool hasMore;       // Hâlâ yüklenecek önceki sayfa var mı
  final bool loadingMore;   // Yukarı scroll yüklemesi devam ediyor
  final bool hasError;

  const MessageThreadState({
    this.messages = const [],
    this.loading = true,
    this.hasMore = true,
    this.loadingMore = false,
    this.hasError = false,
  });

  MessageThreadState copyWith({...}) { ... }
}

class MessageThreadViewModel
    extends AutoDisposeFamilyAsyncNotifier<MessageThreadState, int> {
  StreamSubscription<List<DirectMessage>>? _sub;

  @override
  MessageThreadState build(int otherUserId) {
    final myId = StorageService.currentUserIdSync ?? 0;
    final repo = ref.read(messageRepositoryProvider);
    final cached = repo.getCachedThread(otherUserId, myId);

    ref.onDispose(() => _sub?.cancel());
    Future.microtask(() => _startStream(otherUserId, myId));

    return MessageThreadState(
      messages: cached ?? [],
      loading: cached == null,
    );
  }

  void _startStream(int otherUserId, int myId) {
    _sub?.cancel();
    _sub = ref.read(messageRepositoryProvider)
        .getThread(otherUserId, myId)
        .listen(
          (msgs) => state = AsyncValue.data(
            state.valueOrNull?.copyWith(messages: msgs, loading: false) ??
            MessageThreadState(messages: msgs, loading: false),
          ),
          onError: (_) => state = AsyncValue.data(
            state.valueOrNull?.copyWith(hasError: true, loading: false) ??
            const MessageThreadState(loading: false, hasError: true),
          ),
        );
  }

  // Yukarı scroll → önceki sayfa (cache'siz, listeye prepend)
  Future<void> loadPreviousPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final oldest = current.messages.first.id;
      final myId = StorageService.currentUserIdSync ?? 0;
      final page = await ref.read(messageRepositoryProvider)
          .getPage(arg, oldest);
      state = AsyncValue.data(current.copyWith(
        messages: [...page, ...current.messages],
        hasMore: page.length == 50,
        loadingMore: false,
      ));
    } catch (_) {
      state = AsyncValue.data(current.copyWith(loadingMore: false));
    }
  }

  // WS event dispatcher — DirectChatScreen buraya iletir
  Future<void> handleWsEvent(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    final repo = ref.read(messageRepositoryProvider);
    final myId = StorageService.currentUserIdSync ?? 0;
    switch (type) {
      case 'message':
        final msg = DirectMessage.fromJson(data);
        state = AsyncValue.data(state.value!.copyWith(
          messages: [...state.value!.messages, msg],
        ));
        await repo.appendToCache(arg, data);
      case 'message_deleted':
        final id = data['id'] as int;
        state = AsyncValue.data(state.value!.copyWith(
          messages: state.value!.messages.where((m) => m.id != id).toList(),
        ));
        await repo.removeFromCache(arg, id);
      case 'messages_read':
        state = AsyncValue.data(state.value!.copyWith(
          messages: state.value!.messages.map(
            (m) => m.senderId == myId ? m.copyWith(isRead: true) : m,
          ).toList(),
        ));
        await repo.markReadInCache(arg, myId);
    }
  }
}

final messageThreadProvider = AsyncNotifierProvider.autoDispose
    .family<MessageThreadViewModel, MessageThreadState, int>(
  MessageThreadViewModel.new,
);
```

---

### Karar 7 — DirectMessage Model

`Map<String, dynamic>` yerine strongly-typed model. Mesajlaşma alanı çok sayıda alan tipine sahiptir (metin, görsel, ses, dosya, reply, `_pending`, `_failed`) — runtime cast hatalarını ortadan kaldırır.

```dart
enum MessageContentType { text, image, video, voice, file }

class DirectMessage {
  final int id;                      // negatif → offline pending
  final int senderId;
  final int receiverId;
  final String? content;
  final MessageContentType contentType;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? fileName;
  final int? durationSecs;
  final bool isRead;
  final DateTime createdAt;
  final bool isPending;              // offline kuyrukta, henüz gönderilmedi
  final bool isFailed;               // gönderim başarısız
  final String? localId;             // OfflineQueue reconciliation için

  const DirectMessage({...});

  factory DirectMessage.fromJson(Map<String, dynamic> j) => DirectMessage(
    id: j['id'] as int,
    senderId: j['sender_id'] as int,
    receiverId: j['receiver_id'] as int,
    content: j['content'] as String?,
    contentType: MessageContentType.values.byName(
      j['content_type'] as String? ?? 'text',
    ),
    mediaUrl: j['media_url'] as String?,
    thumbnailUrl: j['thumbnail_url'] as String?,
    fileName: j['file_name'] as String?,
    durationSecs: j['duration_secs'] as int?,
    isRead: j['is_read'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
    isPending: j['_pending'] as bool? ?? false,
    isFailed: j['_failed'] as bool? ?? false,
    localId: j['_local_id'] as String?,
  );

  DirectMessage copyWith({bool? isRead, bool? isPending, bool? isFailed}) =>
      DirectMessage(
        id: id, senderId: senderId, receiverId: receiverId,
        content: content, contentType: contentType,
        mediaUrl: mediaUrl, thumbnailUrl: thumbnailUrl,
        fileName: fileName, durationSecs: durationSecs,
        createdAt: createdAt, localId: localId,
        isRead: isRead ?? this.isRead,
        isPending: isPending ?? this.isPending,
        isFailed: isFailed ?? this.isFailed,
      );
}
```

`MessageRepository` ve `MessageThreadViewModel` `DirectMessage` döner.  
`_patchCache` dahili olarak `Map` saklamaya devam eder (`Hive` JSON serileştirme uyumu); okurken `DirectMessage.fromJson()` çağrılır.

---

## §3 Cache Taxonomy ve TTL Hiyerarşisi

### Hive cache anahtarları (yeni satırlar **kalın**)

| Anahtar Deseni | Taksonomi | TTL | Format | Logout |
|----------------|-----------|-----|--------|--------|
| `cache_messages` | LIFECYCLE | 1s | `List` — konuşma listesi | `StorageService.clear()` |
| `cache_message_requests` | LIFECYCLE | 1s | `List` — istek listesi | `StorageService.clear()` |
| **`cache_chat_{userId}`** | **LIFECYCLE** | **30dk** | **`List<Map>` — son 50 mesaj** | **`StorageService.clear()`** |
| `cache_notifications` | EPHEMERAL | 1s | `List` — bildirim listesi | `StorageService.clear()` |
| `cache_profile` | LIFECYCLE | 30dk | `Map` — tam profil | `StorageService.clear()` |
| `cache_blocked_users` | LIFECYCLE | 30dk | `List` | `StorageService.clear()` |
| `cache_my_ratings_received` | LIFECYCLE | 30dk | `List` | `StorageService.clear()` |
| `cache_my_ratings_given` | LIFECYCLE | 30dk | `List` | `StorageService.clear()` |
| `cache_notification_settings` | LIFECYCLE | 1s | `Map` | `StorageService.clear()` |

**Medya disk cache (TeqlifCacheManager):**

| Anahtar Deseni | TTL | Açıklama |
|----------------|-----|----------|
| `dm_img_{msgId}` | 2 gün | DM resim |
| `dm_thumb_{msgId}` | 2 gün | DM video thumbnail |
| `user_{userId}_avatar` | 2 gün | Kullanıcı avatarı |

> **Güvenlik notu:** Tüm `cache_chat_*` ve `dm_*` anahtarları özel mesaj içeriği taşır.  
> Bunların özel yönetimi gerekmez — `StorageService.clear()` logout'ta **tüm** Hive box'ını siler.

---

### TTL Piramidi — Uçtan Uca Veri Yaşam Döngüsü

Backend'den mobil UI'a kadar her katman üstteki katmanın yaşam süresinin altında kalır; hiçbir alt katman hayalet (geçersiz) URL veya silinmiş veriye ulaşamaz.

| Katman | Konum | TTL | Açıklama |
|--------|-------|-----|----------|
| Fiziksel depo | MinIO `teqlif-dm` | **7 gün** | `cleanup_old_media_messages_task` (ARQ, her gün 06:30 UTC) — MinIO nesnesi + PostgreSQL kaydı hard-delete |
| Presigned URL Redis cache | node1 Redis | **6 gün** | `_CACHE_TTL_SECS` — aynı presigned URL 6 gün boyunca aynı key'den döner |
| Presigned URL imza geçerliliği | S3 imza başlığı | **7 gün** | `_PRESIGN_TTL` — istemcinin MinIO'dan doğrudan indirme penceresi |
| Mobil medya disk cache | TeqlifCacheManager | **2 gün** | `dm_img_{msgId}` ile URL rotasyonundan bağımsız disk hit |
| Mobil konuşma listesi | Hive `cache_messages` | **1 saat** | Sekme açılışında anında SWR render |
| Mobil thread mesajları | Hive `cache_chat_{id}` | **30 dakika** | Son 50 mesaj, sliding-window SWR |
| Mobil geçmiş sayfalar | RAM only | **Oturum boyu** | `before_id` ile çekilen eski sayfalar diske yazılmaz |

`7 gün ≥ 6 gün > 2 gün > 1 saat > 30 dakika` — mobil TTL'lerin tamamı backend medya imha süresi (7 gün) içinde kalır; istemci hiçbir zaman silinmiş medyaya 404 almaz.

---

## §4 Uygulama Sırası

1. `mobile/lib/models/direct_message.dart` — `DirectMessage` model sınıfı (Karar 7)
2. `mobile/lib/services/storage_service.dart` — `cacheThreadKey()`, `cacheDmImageKey()`, `cacheDmThumbKey()` ekle
3. `mobile/lib/repositories/message_repository.dart` — `MessageRepository` oluştur (Karar 5)
4. `mobile/lib/screens/viewmodels/message_thread_view_model.dart` — `MessageThreadViewModel` oluştur (Karar 6)
5. `mobile/lib/services/notification_service.dart` — `getMessages(otherUserId, {int? beforeId})` imzasını güncelle; `before_id` parametresini URL'e ilet (`?before_id=$beforeId&limit=50`). Backend `MSG_PAGE_SIZE=50` zaten uygular; mobilde ek `limit` parametresi gerekmez.
6. `mobile/lib/screens/messages_screen.dart` — `_loadMessages()` kaldır, `messageThreadProvider(otherUserId)` izle
7. `mobile/lib/screens/messages_screen.dart` — WS event'leri `viewmodel.handleWsEvent(data)` ile ilet
8. `mobile/lib/screens/messages_screen.dart` — scroll-up → `viewmodel.loadPreviousPage()` tetikle
9. `mobile/lib/screens/messages_screen.dart` — `CachedNetworkImage` çağrılarına `cacheKey: StorageService.cacheDmImageKey(msg.id)` ekle

### V1.3 sonrası mobil dizin yapısı

```
mobile/lib/
├── models/
│   └── direct_message.dart                  ← [YENİ] immutable domain model
├── repositories/
│   ├── home_repository.dart                 (V1.1)
│   ├── search_repository.dart               (V1.1)
│   ├── user_repository.dart                 (V1.2)
│   ├── ratings_repository.dart              (V1.2)
│   ├── notification_prefs_repository.dart   (V1.2)
│   └── message_repository.dart              ← [YENİ] Hive + API + OfflineQueue
├── screens/
│   ├── viewmodels/
│   │   ├── messages_view_model.dart         (V1.2 — konuşma listesi sekmeleri)
│   │   └── message_thread_view_model.dart   ← [YENİ] thread StateNotifier
│   └── messages_screen.dart                 (refactor: HTTP bağımlılıkları sökülür)
└── services/
    ├── storage_service.dart                 ← [GÜNCELLEME] 3 yeni cache key metodu
    ├── offline_queue_service.dart           (mevcut — getPendingForReceiver kullanılır)
    └── cache_service.dart                   (mevcut — Hive api_cache)
```

---

## §5 flutter analyze gereksinimleri

V1.3 uygulandıktan sonra kontrol:

```bash
# ADR §22 ihlal kontrolü — thread screen'de kalan http çağrısı olmamalı
grep -n "apiServiceProvider\|apiClientProvider\|http\.get\|http\.post\|http\.delete" \
  mobile/lib/screens/messages_screen.dart

# Medya cacheKey eksikliği kontrolü — 'dm' path'li CachedNetworkImage'da cacheKey zorunlu
grep -n "CachedNetworkImage" mobile/lib/screens/messages_screen.dart

# Cache key sabiti kontrolü — magic string 'chat_' olmamalı
grep -rn "'chat_" mobile/lib/screens/ mobile/lib/services/

# Repository bağımlılık kontrolü
grep -n "notificationServiceProvider\|cacheServiceProvider" \
  mobile/lib/screens/messages_screen.dart
```

Hedef: `messages_screen.dart`'ta `apiServiceProvider` ve `apiClientProvider` referansı sıfır.

---

## §6 Referans Bağlantıları

- `messages_screen.dart:1302` — `_loadMessages()` mevcut SWR uygulaması
- `messages_screen.dart:1313` — `cacheKey: 'chat_${widget.otherUserId}'` magic string
- `messages_screen.dart:2117` — image `CachedNetworkImage` (cacheKey eksik)
- `messages_screen.dart:2155` — video thumb `CachedNetworkImage` (cacheKey eksik)
- `backend/app/use_cases/messages/queries/get_messages_query.py:14` — `_PRESIGN_TTL = 7 gün`
- `backend/app/use_cases/messages/queries/get_messages_query.py:40` — `before_id` pagination
- `services/storage_service.dart:231` — `_clearHiveBoxes()` — logout'ta tüm Hive silinir
- `documents/teqlif_architectural_decisions.md` — ADR §22 (Repository katmanı)
