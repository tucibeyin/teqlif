# Mobile Cache & Mimari Analizi — V1.2 Bulgular & Uygulama Spesifikasyonu

**Tarih:** 2026-10-14  
**Kapsam:** V1.1 üzerine SWR iyileştirmeleri, teknik borç tespiti, ADR §22 ihlal analizi ve repository refactor planı  
**Revizyon:** V1.2 — Kısmen uygulandı (SWR), devam ediyor (Repository refactor)  
**İlgili commit'ler:** `99a1a3b5`, `a0dac216`, `a567e645`, `5bbd8f6b`, `0f2931bc`

---

## 0. Uyum Gereksinimleri

V1.1'deki §0.1–§0.5 maddeleri aynen geçerlidir. Bu doküman V1.1'e ek olarak okunur, onun yerine geçmez.

Hatırlatıcı:
- **ADR §22:** ViewModel `http.get()` ve `StorageService.getToken()` çağıramaz. API çağrıları Repository veya Service katmanından geçer.
- **ADR §8:** MVVM katman sınırları — ViewModel sadece iş mantığı + state; HTTP, Hive, token Data katmanına aittir.
- **ADR §13:** Her commit öncesi `flutter analyze` sıfır hata; staging testi; docs güncelleme.

---

## 1. V1.2'de Yapılanlar (Özet)

### 1.1 SWR Geçişi — Tüm Sayfalar

**Problem:** Uygulama genelinde `getData()` kullanılıyordu. TTL dolunca cache `null` döner → ViewModel spinner gösterirdi. Kullanıcı sekmeyi her açtığında sunucudan yükleniyordu.

**Çözüm:** `getData()` → `getWithStaleness()` geçişi. TTL dolmuş olsa bile disk cache'teki veri anında gösterilir; arka planda sessizce güncellenir (SWR davranışı).

**`async build()` race condition düzeltmesi:**  
`NotificationsTabViewModel`, `MessagesTabViewModel`, `RequestsTabViewModel` — `async build()` + `Future.microtask(() => load())` kombinasyonu race condition'a yol açıyordu:
- Dart, async fonksiyon dönüşünü `Future` olarak sarar → Riverpod state `AsyncLoading` kalır.
- Microtask, `state.hasValue == false` iken ateşlenir → `load()` early-return yapar → HTTP isteği atılmaz.
- **Düzeltme:** `async` kaldırıldı; `build()` senkron hale getirildi; `currentUserIdSync` getter eklendi.

**Etkilenen dosyalar ve değişiklikler:**

| Dosya | Değişiklik |
|-------|-----------|
| `mobile/lib/services/storage_service.dart` | `currentUserIdSync` getter eklendi (JWT sync parse) |
| `messages_view_model.dart` — MessagesTab | `async` kaldırıldı, `getWithStaleness`, TTL 5dk→1sa |
| `messages_view_model.dart` — NotificationsTab | `getWithStaleness`, TTL 5dk→1sa |
| `messages_view_model.dart` — RequestsTab | `async` kaldırıldı, `getWithStaleness`, TTL 5dk→1sa |
| `blocked_users_view_model.dart` | `getData` → `getWithStaleness` |
| `follow_list_view_model.dart` | `getData` → `getWithStaleness` |
| `notification_settings_view_model.dart` | `getData` → `getWithStaleness` |
| `my_ratings_view_model.dart` | `getData` → `getWithStaleness` |
| `public_profile_view_model.dart` | `getData` → `getWithStaleness` (profil + ilanlar + puanlar) |
| `home_view_model.dart` | Cache varken `isLoading/isHesitatedLoading: true` set edilmez |
| `profile_view_model.dart` | `localInfo` varsa `loading: false` döner |
| `competitor_radar_view_model.dart` | SWR cache eklendi — ilanlar (30dk) + radar/velocity per ilan |
| `demand_trends_view_model.dart` | SWR cache eklendi — filtre bazlı key, 30dk TTL |

### 1.2 Bug Düzeltmeleri (0f2931bc)

**Bug 1 — Magic key kırılganlığı (`demand_trends_view_model.dart`):**  
`build()` içinde `'cache_demand_trends__'` hardcode edilmişti. `_cacheKey()` metodu `state.filter`'a eriştiği için `build()` içinde çağrılamazdı. Yarın `ListingFilterState`'e varsayılan kategori atanırsa key sessizce uyumsuz hale gelirdi.  
**Düzeltme:** `static String _keyFor(ListingFilterState filter)` metodu eklendi. `build()`, `load()`, `updateFilter()` hepsi bu metodu kullanıyor.

**Bug 2 — `currentUserIdSync` null soğuk açılış (`messages_view_model.dart`):**  
`StorageService._cachedToken`, `getToken()` ilk çağrıldığında dolar. Soğuk açılışta token henüz bellekte yoksa `currentUserIdSync` `null` döner ve `myUserId` kalıcı `null` kalır. WebSocket'ten gelen mesajlar `_updateConversationInMemory()` içinde işlenemez.  
**Düzeltme:** `load()` tamamlandığında `myUserId: state.value!.myUserId ?? StorageService.currentUserIdSync` ile boşluk doldurulur.

---

## 2. Teknik Borç Tespiti

### 2.1 Clean Code Sorunları (Mevcut)

**DRY ihlali:** Aynı SWR boilerplate 8'den fazla ViewModel'de tekrarlanıyor:
```dart
final result = _cache.getWithStaleness(key);
final cached = result?.data;
Future.microtask(() => load(silent: true));
return XState(data: cached, loading: cached == null);
```
Çözüm: `build()` + `_load()` pattern'ını standartlaştırmak için Repository + StreamSubscription pattern'ı (bkz. §4).

**`isStale` flag kullanılmıyor:** `getWithStaleness()` `{dynamic data, bool isStale}` döndürür. Neredeyse hiçbir ViewModel `isStale`'i okumaz; sadece `.data` alınır. Gelecekte "son güncelleme: X dakika önce" UI'ı eklenirse bu bayrak hazır; aksi halde dead metadata.

**Tip güvensizliği:** `cached as List`, `Map<String, dynamic>.from(cached as Map)`, `(raw as List).cast<Map<String, dynamic>>()` — şema uyuşmazlığında runtime `TypeError`. Repository katmanına geçince `fromJson` callable içinde kontrol altına alınacak.

### 2.2 ADR §22 İhlalleri (Devam Eden — §4'te ele alınıyor)

ViewModel içinde doğrudan `http.get()` + `StorageService.getToken()` çağıran 5 dosya:

| ViewModel | İhlal Tipi | Hedef Repository |
|-----------|-----------|-----------------|
| `blocked_users_view_model.dart` | `http.get`, `http.delete` | `UserRepository` |
| `follow_list_view_model.dart` | `http.get`, `http.post/delete` | `UserRepository` |
| `my_ratings_view_model.dart` | `http.get` (×2 parallel) | `RatingsRepository` |
| `notification_settings_view_model.dart` | `http.get`, `http.patch` | `NotificationPrefsRepository` |
| `competitor_radar_view_model.dart` | `http.get` (listings fetch) | `ListingService` (metot ekleme) |

**Not:** Bu ihlaller V1.2 değişikliklerinden önce de mevcuttu; V1.2 bu dosyalarda sadece `getData` → `getWithStaleness` yaptı, ADR ihlalini ne ekledi ne kötüleştirdi.

---

## 3. V1.2 Sonrası Cache Taksonomisi (Yeni Anahtarlar)

V1.1 tablosuna ek:

| Cache Key | Taksonomi | Client TTL | Invalidasyon Tetikleyici | Durum |
|-----------|-----------|-----------|--------------------------|-------|
| `cache_messages` | EPHEMERAL | 1 sa | WS event (`message` type) | ✅ V1.2 |
| `cache_notifications` | EPHEMERAL | 1 sa | push notification stream | ✅ V1.2 |
| `cache_message_requests` | EPHEMERAL | 1 sa | WS event | ✅ V1.2 |
| `cache_competitor_radar_listings` | LIFECYCLE | 30 dk | filtre değişimi → `loadListings()` | ✅ V1.2 |
| `cache_radar_{id}` | LIFECYCLE | 30 dk | listing seçim değişimi | ✅ V1.2 |
| `cache_velocity_{id}` | LIFECYCLE | 30 dk | listing seçim değişimi | ✅ V1.2 |
| `cache_demand_trends_{cat}_{subcat}` | ALGORITHMIC | 30 dk | filtre değişimi → `updateFilter()` | ✅ V1.2 |

**ADR §9 notu:** `cache_radar_{id}` ve `cache_velocity_{id}` anahtarları ilan ID'sine göre şişer. İlan silindiğinde bu anahtarlar `clearData()` ile temizlenmez — yalnızca TTL ile silinir. Kabul edilebilir (30dk) ancak ileri versiyonda listing silinme event'ine bağlanabilir.

---

## 4. Repository Refactor Planı (Bekleyen İş)

### 4.1 Amaç

5 ViewModel'deki ADR §22 ihlalini gidermek:
- HTTP + token yönetimi Data katmanına taşınır.
- ViewModel yalnızca stream'i dinler ve UI state'ini yönetir.
- Cache anahtarları, TTL süreleri ve endpoint URL'leri ViewModel'den çıkar.

### 4.2 Temel Teknik Kararlar

**Karar 1 — `await for` değil `StreamSubscription`:**  
`build()` senkron kalmalıdır (spinner problemi geri döner). `ApiService.get()` bir `Stream<T>` döndürür; bunu `async build()` içinde `await for` ile tüketmek imkânsız/yanlıştır. Doğru pattern:

```dart
StreamSubscription? _sub;

@override
FutureOr<XState> build() {
  final cachedRaw = _cache.getWithStaleness(XRepository.cacheKey)?.data;
  // initial state anında gösterilir

  _sub?.cancel();
  _sub = ref.read(xRepositoryProvider).getX().listen(
    (data) {
      if (state.hasValue) state = AsyncValue.data(state.value!.copyWith(items: data, loading: false));
    },
    onError: (e) {
      if (!state.hasValue) state = AsyncValue.error(e, StackTrace.current);
    },
  );
  ref.onDispose(() => _sub?.cancel());

  return XState(
    items: cachedRaw != null ? (cachedRaw as List) : const [],
    loading: cachedRaw == null,
  );
}
```

`ref.onDispose()` ile abonelik iptal edilir → dispose edilmiş notifier'a yazma (`Bad state`) hatası önlenir. Filtre değişiminde `_sub?.cancel()` ardından yeni abonelik açılır → race condition önlenir.

**Karar 2 — Mutation'lar için `ApiClient.call()`:**  
`ApiService` yalnızca `get<T>()` içerir. DELETE / POST / PATCH işlemleri için `ApiClient.call()` veya `ApiClient.callList()` kullanılır. Bu sayede:
- Otomatik token refresh (401 → tryRefresh)
- 429 rate-limit bekleme (Retry-After)
- Merkezi hata yakalama (`AppException`)

```dart
// Repository içinde mutation örneği
Future<void> unblockUser(String username) async {
  final token = await StorageService.getToken();
  final headers = await _client.buildApiHeaders(token);
  await _client.call(
    () => http.delete(
      Uri.parse('${_client.config.baseUrl}/users/${Uri.encodeComponent(username)}/block'),
      headers: headers,
    ),
  );
}
```

**Karar 4 — ViewModel `CacheService`'e hiç dokunmaz; Repository `getCached()` expose eder:**  
`build()` içindeki `_cache.getWithStaleness(XRepository.cacheKey)?.data` çağrısı ViewModel'i `CacheService` + cache key'e bağlar — tam kaçmak istediğimiz bağımlılık. Her Repository, senkron ilk okuma için bir `getCached()` metodu expose eder; ViewModel yalnızca Repository'yi bilir.

```dart
// Repository içinde:
dynamic getCachedBlockedUsers() =>
    _cache.getWithStaleness(StorageService.cacheBlockedUsers)?.data;

// ViewModel build() içinde (DOĞRU):
final cachedRaw = ref.read(userRepositoryProvider).getCachedBlockedUsers();
// _cache.getWithStaleness(...) asla ViewModel'de çağrılmaz
```

`getCached()` saf bir Hive okumadır — async değil, senkron. Repository bunu expose edene kadar `_cache` ViewModel'den dışarı çıkmaz.

**Karar 3 — `ListingsRepository` yok; `ListingService`'e metot eklenir:**  
`mobile/lib/services/listing_service.dart` zaten mevcut. Yeni `listings_repository.dart` açmak mimari kafa karışıklığı yaratır. `CompetitorRadarViewModel`'deki `/listings/my?...` çağrısı `ListingService.getMyActiveListings()` olarak eklenir.

```dart
// listing_service.dart'a ekleme
Stream<List<Map<String, dynamic>>> getMyActiveListings({
  String? query,
  String? category,
  String? subcategory,
}) {
  final params = StringBuffer('?limit=50&offset=0&active=true');
  if (query != null && query.isNotEmpty) params.write('&q=${Uri.encodeComponent(query)}');
  if (category != null && category.isNotEmpty) params.write('&category=${Uri.encodeComponent(category)}');
  if (subcategory != null && subcategory.isNotEmpty) params.write('&subcategory=${Uri.encodeComponent(subcategory)}');

  return _apiService.get<List<Map<String, dynamic>>>(
    url: '${_api.config.baseUrl}/listings/my$params',
    cacheKey: 'cache_my_active_listings_${query ?? ''}_${category ?? ''}_${subcategory ?? ''}',
    fromJson: (raw) => (raw as List).cast<Map<String, dynamic>>(),
    cacheTtl: const Duration(minutes: 30),
  );
}
```

### 4.3 Yeni Dosyalar

#### `mobile/lib/repositories/user_repository.dart`

**Kapsam:** Engellenen kullanıcılar + takipçi/takip listesi + follow toggle

```
UserRepository
  ├── dynamic getCachedBlockedUsers()                  → _cache.getWithStaleness(cacheBlockedUsers)?.data (senkron)
  ├── dynamic getCachedFollowList(int userId, FollowListType type) → senkron
  ├── Stream<List<dynamic>> getBlockedUsers()          → ApiService.get, TTL 30dk
  ├── Future<void> unblockUser(String username)        → ApiClient.call, http.delete
  │     + clearData(StorageService.cacheBlockedUsers)  ← cache invalidation zorunlu
  ├── Stream<List<dynamic>> getFollowList(int userId, FollowListType type)
  │     cacheKey: 'follow_list_{userId}_{type}', TTL 15dk
  └── Future<bool> toggleFollow(int userId, {required bool isFollowing})
        → ApiClient.call, http.post/delete
        + clearData('follow_list_{userId}_*')          ← cache invalidation zorunlu

final userRepositoryProvider = Provider<UserRepository>((ref) =>
  UserRepository(ref.watch(apiClientProvider), ref.watch(cacheServiceProvider)));
```

**Mutation → Cache Invalidation kuralı:** Her Repository mutation'ı, başarı durumunda ilgili cache anahtarını `clearData()` ile temizler. TTL dolmadan eski veri geri dönmesin. Bu kural `NotificationPrefsRepository.patchPrefs()`'te yazılıydı; `UserRepository` ve `RatingsRepository` için de geçerlidir.

#### `mobile/lib/repositories/ratings_repository.dart`

**Kapsam:** Alınan/verilen puanlar + yanıt + puan gönderme

```
RatingsRepository
  ├── Stream<List<dynamic>> getReceivedRatings()   → ApiService.get, TTL 30dk
  ├── Stream<List<dynamic>> getGivenRatings()      → ApiService.get, TTL 30dk
  ├── Future<void> markAsRead()                    → ApiClient.call, http.patch
  ├── Future<bool> submitReply(int ratingId, String text)  → ApiClient.call, http.post
  └── Future<bool> saveRating(int userId, int score, String? comment) → ApiClient.call, http.post

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) =>
  RatingsRepository(ref.watch(apiClientProvider), ref.watch(cacheServiceProvider)));
```

#### `mobile/lib/repositories/notification_prefs_repository.dart`

**Kapsam:** Bildirim tercihleri okuma/yazma

```
NotificationPrefsRepository
  ├── Stream<Map<String, dynamic>> getPrefs()  → ApiService.get, TTL 1sa
  └── Future<void> patchPrefs(Map<String, dynamic> payload)  → ApiClient.call, http.patch
        + cache invalidation: clearData(StorageService.cacheNotificationSettings)

final notificationPrefsRepositoryProvider = Provider<NotificationPrefsRepository>((ref) =>
  NotificationPrefsRepository(ref.watch(apiClientProvider), ref.watch(cacheServiceProvider)));
```

### 4.4 Güncellenecek Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `mobile/lib/services/listing_service.dart` | `getMyActiveListings()` metodu eklenir |
| `blocked_users_view_model.dart` | `UserRepository` kullanır; `http` import'u kaldırılır |
| `follow_list_view_model.dart` | `UserRepository` kullanır; `http` import'u kaldırılır |
| `my_ratings_view_model.dart` | `RatingsRepository` kullanır; `http` import'u kaldırılır |
| `notification_settings_view_model.dart` | `NotificationPrefsRepository` kullanır; `http` import'u kaldırılır |
| `competitor_radar_view_model.dart` | `ListingService` kullanır; `http` import'u ve `_fetchListingsPage()` kaldırılır |

### 4.5 ViewModel Refactor Pattern (Her Dosya İçin)

**Mevcut (ADR §22 ihlali):**
```dart
FutureOr<XState> build() async {
  final cached = _cache.getData(key);
  if (cached != null) state = AsyncValue.data(XState(items: cached));
  final token = await StorageService.getToken();
  final resp = await http.get(url, headers: {'Authorization': 'Bearer $token'});
  if (resp.statusCode == 200) {
    final data = jsonDecode(resp.body);
    await _cache.saveData(key, data, ttl: ...);
    return XState(items: data);
  }
  if (cached != null) return state.value!;
  throw Exception('...');
}
```

**Hedef (ADR §22 uyumlu + leaky abstraction kapatıldı):**
```dart
StreamSubscription? _sub;

@override
FutureOr<XState> build() {
  // Repository getCached() — ViewModel CacheService'i hiç bilmez
  final cachedRaw = ref.read(xRepositoryProvider).getCached();

  _sub?.cancel();
  _sub = ref.read(xRepositoryProvider).getX().listen(
    (items) {
      if (state.hasValue) {
        state = AsyncValue.data(state.value!.copyWith(items: items, loading: false));
      }
    },
    onError: (_) {
      if (state.hasValue) state = AsyncValue.data(state.value!.copyWith(loading: false));
    },
  );
  ref.onDispose(() => _sub?.cancel());

  return XState(
    items: cachedRaw != null ? (cachedRaw as List) : const [],
    loading: cachedRaw == null,
  );
}
```

**Mutation pattern (optimistic update + cache invalidation):**
```dart
Future<void> removeItem(int id) async {
  // Optimistic update
  final current = state.value!;
  final updated = current.items.where((i) => i['id'] != id).toList();
  state = AsyncValue.data(current.copyWith(items: updated));

  try {
    await ref.read(xRepositoryProvider).deleteItem(id);
    // Repository.deleteItem() içinde clearData(key) çağrılır.
    // TTL dolmadan eski veri geri gelmesin.
  } catch (_) {
    // Rollback
    state = AsyncValue.data(current);
  }
}
```

**Kural:** ViewModel mutation başarısında cache temizlemez — bu Repository'nin sorumluluğudur. ViewModel yalnızca UI state'ini günceller / rollback yapar.

### 4.6 Uygulama Sırası

```
1. user_repository.dart oluştur
2. ratings_repository.dart oluştur
3. notification_prefs_repository.dart oluştur
4. listing_service.dart — getMyActiveListings() ekle
   ↓ (her biri bağımsız commit)
5. blocked_users_view_model.dart refactor
6. follow_list_view_model.dart refactor
7. my_ratings_view_model.dart refactor
8. notification_settings_view_model.dart refactor
9. competitor_radar_view_model.dart refactor
```

Her adım sonrası `flutter analyze` sıfır hata; staging testi.

### 4.7 Kapsam Dışı (Bu Faz)

- **Tip güvenliği / Model sınıfları** — `List<Map<String, dynamic>>` → `List<BlockedUser>` dönüşümü. Repository refactor'dan bağımsız, ayrı sprint.
- **`NotificationService` ve `AnalyticsService` refactor'ı** — Bu servisler ADR §22'ye zaten uygun; bu fazda dokunulmaz.
- **`isStale` flag UI kullanımı** — "Son güncelleme" ibaresi. Repository refactor'dan sonra eklenebilir.

---

## 5. flutter analyze Gereksinimleri

Bu dokümanın kapsadığı her commit için:

```bash
cd mobile && flutter analyze
```

Sıfır hata + sıfır uyarı zorunludur. Özellikle dikkat:
- Repository dosyalarına `http` paketi import'u sonrası `unused_import` yok.
- ViewModel'lerden kaldırılan `http`, `dart:convert`, `StorageService.getToken` import'larının temizlenmesi.
- `StreamSubscription` için `dart:async` import'u eklenmesi.

---

## 6. İzleme ve Doğrulama

Repository refactor tamamlandıktan sonra:

1. `grep -r "http.get\|http.post\|http.delete\|http.patch" mobile/lib/screens/` → sıfır sonuç olmalı.
2. `grep -r "StorageService.getToken" mobile/lib/screens/` → sıfır sonuç olmalı.
3. Staging'de her refactor edilen sayfa açılış testi: cache varken spinner görülmemeli, yokken spinner görülmeli.
4. Pull-to-refresh (varsa) yeni istek atmalı, eski subscription iptal edilmeli.
