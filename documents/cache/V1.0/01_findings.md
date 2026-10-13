# Mobile Cache Sistem Analizi — Bulgular

**Tarih:** 2026-10-13
**Kapsam:** Flutter mobile uygulaması client-side cache stratejisi, TTL yönetimi, veri yaşam döngüsü
**Revizyon:** Statik kod analizi — mimari eleştiri sonrası güncellendi (ADR §9 uyumu dahil)

---

## 1. Cache Altyapısı

### 1.1 Kullanılan Paketler

| Paket | Versiyon | Kullanım |
|---|---|---|
| `hive` + `hive_flutter` | ^2.2.3 / ^1.1.0 | Kalıcı anahtar-değer cache |
| `shared_preferences` | ^2.3.0 | Kullanıcı tercihleri + mesaj/bildirim cache |
| `flutter_secure_storage` | ^9.2.4 | Auth token'ları (cache değil; güvenli depo) |
| `cached_network_image` | ^3.3.1 | Resim disk cache |
| `flutter_cache_manager` | any | `cached_network_image` disk backend'i |

### 1.2 Cache Katmanları

#### A. Hive — `api_cache` Box (`CacheService`)
- **Dosya:** `lib/services/cache_service.dart`
- Merkezi SWR cache katmanı. Box uygulama başlangıcında belleğe yüklendiği için okuma disk I/O beklemez.
- TTL sarmalayıcı: `{"_d": data, "_t": savedAtMs, "_x": ttlMs}` JSON string olarak saklanır.
- Varsayılan TTL: **5 dakika**.
- `clearExpired()` startup'ta fire-and-forget çağrılır (`main.dart:101`).
- **Mimari sorun:** Statik metodlar (`CacheService.getData()`, `CacheService.saveData()`) — DIP ihlali, unit testlerde mock'lanamaz. Bkz. §8.2.

#### B. Hive — `homeCache` Box (`HomeViewModel`)
- **Dosya:** `lib/screens/viewmodels/home_view_model.dart`
- Ham `resp.body` JSON string'i saklanır. **TTL sarmalayıcı kullanılmaz.**
- Tek invalidasyon mekanizması: `_kCacheVersion = 2` eşleşmesi.
- Versiyon değişmediği sürece cache **süresiz geçerli** kabul edilir.
- **Katman ihlali:** ViewModel `Hive.openBox('homeCache')` doğrudan açıyor. Bkz. §8.1.

#### C. SharedPreferences (`StorageService`)
- **Dosya:** `lib/services/storage_service.dart`
- `cacheData(key, data, ttl)` / `getCachedData(key)` — `CacheService` ile **aynı `{_d, _t, _x}` TTL sarmalayıcı mantığını** SharedPreferences üzerinde tekrarlıyor.
- Kullanım alanı: mesajlar, bildirimler, mesaj istekleri. Varsayılan 5 dakika TTL.
- **DRY ihlali:** İki bağımsız TTL implementasyonu — tek doğruluk kaynağı yok. Bkz. §8.2.

#### D. In-Memory Cache'ler

| Konum | Amaç | TTL |
|---|---|---|
| `ListingService._likeCache` (`static Map<int, bool>`) | Beğeni durumu | Yok — process ömrü |
| `CategoryService._cache` (`static Map<String, List<...>>`) | Kategori listesi | Yok — process ömrü |
| `StorageService._cachedToken` vb. | Token/avatar geçici copy | Yok — null koruması için |
| `VideoCacheManager._cachedFiles` (`Map<int, String>`) | Video ID → temp dosya | Viewport-based eviction |

#### E. Resim/Medya Cache

- `TeqlifCacheManager` özel config: **2 günlük TTL, max 300 dosya**.
- `DefaultCacheManager` (flutter_cache_manager varsayılanı): **7 günlük TTL, max 200 dosya**.
- `PaintingBinding.instance.imageCache.maximumSizeBytes` = 25 MB (default 100 MB'den düşürülmüş).
- Video: `VideoCacheManager` temp dizine indirir; aynı anda max 2 indirme; viewport dışına çıkan indirmeler iptal edilir.

---

## 2. HTTP / API Katmanı

### 2.1 Client
- **`http` paketi** kullanılıyor (Dio, dio_cache_interceptor, retrofit yok).
- `ApiClient.call()` içinde dahili retry mantığı:
  - HTTP 429 → `Retry-After` header'a göre bekle, bir kez yeniden dene.
  - HTTP 500-5xx → 500ms bekle, bir kez yeniden dene.
  - HTTP 401 → `authService.tryRefresh()`, başarılıysa bir kez yeniden dene.
- Interceptor pattern yok.

### 2.2 Cache Header Desteği
**ETag, Cache-Control, If-None-Match, If-Modified-Since header'larının hiçbiri okunmuyor veya gönderilmiyor.** Her API çağrısı tam yanıt alır; sunucu tarafında değişmemiş olsa bile bant genişliği harcanır.

### 2.3 SWR Akışı (`ApiService.get<T>`) — ve Kritik Kusuru

- **Dosya:** `lib/services/api_service.dart`
- `Stream<T>` döner, iki kez emit eder:
  1. **Anlık (sync):** Hive `api_cache` box'tan cache okunur, TTL geçerliyse hemen emit edilir.
  2. **Arka planda (async):** HTTP isteği atılır; başarılı yanıt cache'e yazılır ve emit edilir.

**Kırık SWR:** `CacheService.getData()` satır 41:
```dart
if (age > ttlMs) return null;   // TTL dolunca null → ekran boşalır
```
TTL süresi dolmuş kayıt için `null` dönülüyor. Gerçek SWR standardında (RFC 5861) bayat veri de ekranda gösterilmeli, arka planda yenileme yapılmalıdır. Şu an TTL geçince kullanıcı veriyi kaybediyor — bu **Cache-or-Network** davranışıdır, SWR değil. Bkz. §7.2 ve §9.2.

---

## 3. State Management

- **Riverpod** (`flutter_riverpod ^2.4.9`) — eski `StateNotifier` ve yeni `AsyncNotifier`/`Notifier` karışımı.
- Tüm ana ekran provider'ları `autoDispose` — widget tree'den çıkıldığında state silinir.
- `autoDispose` + Hive cache → her ekran ziyaretinde disk serialize/deserialize maliyeti var. `ref.keepAlive()` / `ref.cacheFor()` ile bu maliyet sıfırlanabilir. Bkz. §8.3.

### Provider — API Çağrısı Tetiklenme Tablosu

| Provider | Cache | Tetiklenme |
|---|---|---|
| `homeViewModelProvider` (autoDispose) | Hive `homeCache` (TTL'siz) + SWR | Her `build()`: önce Hive, sonra API |
| `searchViewModelProvider` (autoDispose) | Hive SWR (5-15 dk TTL) | Her `build()` → microtask; ayrıca 30s stream poll |
| `profileViewModelProvider` (autoDispose) | SWR profile 10 dk, listings 5 dk | Her `build()` → microtask SWR load |
| `publicProfileProvider` (autoDispose.family) | **YOK** | Her `build()`: 3 ayrı HTTP isteği |
| `salesProvider` (autoDispose) | **YOK** | Her `build()`: tam fetch |
| `accountInfoProvider` (autoDispose) | **YOK** | Her `build()` + `AppLifecycleState.resumed` |
| `mainViewModelProvider` (autoDispose) | Yok (badge sayaçları) | Her `build()` + 30s timer |
| `messagesTabViewModel` (autoDispose) | SharedPreferences SWR 5 dk | Her `build()` + WS mesajı + FCM push |
| `listingDetailProvider` (autoDispose.family) | Yok | `refreshStatus()` manuel çağrıyla |

---

## 4. Pagination Bellekte Tutulma Durumu

| ViewModel | Davranış |
|---|---|
| `HomeViewModel.loadMore()` | Cursor tabanlı; önceki sayfalar bellekte korunur |
| `SearchViewModel` (giriş yapmış) | 100 öğelik buffer tek seferde çekilir; her scroll'da 12 öğelik memory windowing |
| `SearchViewModel` (misafir) | Her sayfa ayrı API çağrısıyla getirilir, belleğe eklenir |
| `SearchViewModel.loadMoreForYou()` | Her sayfa API çağrısıyla getirilir, deduplication ile belleğe eklenir |
| `SwipeFeedManager` | In-memory listing pool; video indirileri viewport eviction ile iptal edilir ama listing verisi bellekte kalır |

---

## 5. TTL Referans Tablosu — ADR §9 Taksonomisiyle Etiketlenmiş

ADR §9, sistemdeki tüm cache'leri 5 kategoriye ayırır: **SCHEMA_VERSIONED** · **ALGORITHMIC** · **LIFECYCLE** · **SECURITY_CRITICAL** · **EPHEMERAL**

| Cache Key / Endpoint | Depolama | TTL | ADR §9 Taksonomisi |
|---|---|---|---|
| `homeCache` (ana feed) | Hive `homeCache` box | **TTL YOK** ⚠️ | ALGORITHMIC |
| `user_wallet_data` | Hive `api_cache` | 2 dakika | EPHEMERAL |
| `active_streams` | Hive `api_cache` | 1 dakika | EPHEMERAL |
| `feed_personalized` | Hive `api_cache` | 10 dakika | ALGORITHMIC |
| `cache_profile` | Hive `api_cache` | 10 dakika | LIFECYCLE |
| `explore_personalized_feed` | Hive `api_cache` | 15 dakika | ALGORITHMIC (Backend Redis cron ile senkron) |
| `explore_for_you` | Hive `api_cache` | 5 dakika | ALGORITHMIC |
| `explore_listings` | Hive `api_cache` | 5 dakika | ALGORITHMIC |
| `pro_insights_*` | Hive `api_cache` | 10 dakika | ALGORITHMIC |
| `cache_streams` | Hive `api_cache` | 5 dakika (varsayılan) | LIFECYCLE |
| `cache_stories` / `cache_my_stories` | Hive `api_cache` | **2 dakika** | LIFECYCLE |
| `cache_messages` | SharedPreferences | 5 dakika | EPHEMERAL |
| `cache_notifications` | SharedPreferences | 5 dakika | EPHEMERAL |
| `cache_message_requests` | SharedPreferences | 5 dakika | EPHEMERAL |
| `CategoryService._cache` | In-memory Map | **TTL YOK** | **SCHEMA_VERSIONED** ⚠️ (ADR §9: migration tetiklemeli) |
| `HomeViewModel._kCacheVersion = 2` | Hive box versiyonu | Hardcoded | SCHEMA_VERSIONED (ADR `schema:static_version` ile uyumsuz) |
| Public profil verisi | **YOK** | — | LIFECYCLE |
| Satışlar verisi | **YOK** | — | LIFECYCLE |
| Resimler (`TeqlifCacheManager`) | Disk | 2 gün, max 300 dosya | EPHEMERAL |
| Resimler (`DefaultCacheManager`) | Disk | 7 gün, max 200 dosya | EPHEMERAL |

### Cache Temizleme Mekanizmaları
- `CacheService.clearExpired()`: Startup'ta Hive `api_cache` süresi dolmuş kayıtları siler.
- `TeqlifCacheManager` / `DefaultCacheManager`: `flutter_cache_manager` kendi TTL'ini yönetir.
- `StorageService.clear()`: Logout'ta hem SecureStorage hem SharedPreferences hem `homeCache` hem `api_cache` box'larını siler.

---

## 6. Risk Değerlendirmesi

| Sorun | Alan | Risk | Gerekçe |
|---|---|---|---|
| Race condition: `_loadFromCache()` await edilmemiş | `HomeViewModel.build()` | **KRİTİK** | Ağ hızlıysa API yanıtı sonrası eski cache state'i ezebilir |
| `homeCache` TTL yok | `HomeViewModel` | **KRİTİK** | Uygulama restart'ları arasında günlerce eski içerik gösterilebilir |
| Kırık SWR: TTL dolunca `null` dönülüyor | `CacheService.getData()` | **YÜKSEK** | Cache expire = ekran boşalır; gerçek SWR değil |
| `PublicProfileViewModel` cache yok | Profil ekranı | **YÜKSEK** | Her ziyarette 3 HTTP isteği |
| `SalesViewModel` cache yok | Satışlar sekmesi | **ORTA** | Her tab geçişinde tam fetch |
| 83/95 `CachedNetworkImage` özel manager yok | Resim cache | **ORTA** | Tutarsız TTL ve dosya limitleri |
| `AccountInfo` resume debounce yok | Hesap bilgisi ekranı | **ORTA** | Her app resume'da `GET /auth/me` tetikleniyor |
| `CategoryService` SCHEMA_VERSIONED ama TTL/invalidasyon yok | In-memory | **ORTA** | Admin panel kategori değişikliği app restart'a kadar yansımaz |
| ETag / conditional request yok | Tüm API katmanı | **DÜŞÜK** | Değişmemiş içerik için tam bandwidth harcanıyor |
| İki paralel TTL-cache sistemi (DRY ihlali) | Hive + SharedPreferences | **DÜŞÜK** | Aynı `{_d, _t, _x}` mantığı iki yerde; bakım yükü |

---

## 7. Mimari Sorunlar

### 7.1 Katman İhlali — ViewModel Storage Biliyor (Clean Architecture)

`HomeViewModel` doğrudan `Hive.openBox('homeCache')` çağırıyor. Clean Architecture'da cache bir **Data Layer** detayıdır; Presentation katmanındaki ViewModel verinin nereden geldiğini bilmemeli.

Mevcut durum:
```dart
// HomeViewModel (Presentation) → Hive (Data) — katman atlıyor
final cacheBox = await Hive.openBox('homeCache');
```

Olması gereken:
```
HomeViewModel → ListingRepository.getHomeFeed() → (Hive | API)
```

### 7.2 Kırık SWR Standardı

`CacheService.getData()` TTL süresi dolmuşsa `null` döner. Ekran açıldığında cache expire olmuşsa kullanıcı yüklenme göster → API cevabını bekler. Gerçek SWR (RFC 5861): bayat veri de UI'a verilmeli, arka planda sessizce yenilenmeli.

Düzeltme — `getData()` iki mod desteklemeli:
```dart
// Tazelik TTL: verinin "güncel" sayıldığı süre
// Bayatlık TTL: verinin "hâlâ gösterilebilir" sayıldığı süre
static ({dynamic data, bool isStale}) getDataWithStaleness(String key) { ... }
```

### 7.3 Race Condition — `HomeViewModel.build()`

`home_view_model.dart` (satır 76-78):
```dart
_loadFromCache();       // ← AWAIT EDİLMEMİŞ — fire-and-forget
await _fetchInitial();  // ← ağ hızlıysa önce bu biter
```

Ağ hızlıysa `_fetchInitial()` tamamlandıktan sonra `_loadFromCache()` devam edip `state`'i eski veriyle ezebilir.

---

## 8. İyileştirme Fırsatları (Mimari)

### 8.1 Repository Pattern (Uzun Vadeli)
`homeCache` box çağrıları ViewModel'dan alınıp `ListingRepository` / `HomeRepository` katmanına indirilmelidir. ViewModel yalnızca `repository.getHomeFeed()` akışını dinler.

### 8.2 DIP + DRY
- `CacheService` statik metod yerine Riverpod `Provider<CacheService>` olarak enjekte edilmeli.
- `StorageService` cache metotları uzun vadede `CacheService`'e taşınmalı (tek `{_d, _t, _x}` implementasyonu).

### 8.3 Riverpod `ref.keepAlive()` / `ref.cacheFor()`
`autoDispose` + Hive kombinasyonu her tab geçişinde disk serialize/deserialize maliyeti yaratıyor. Riverpod 2.x'in `ref.cacheFor(Duration(minutes: 5))` ile belirli bir süre in-memory state korunabilir; diske gitme maliyeti sıfırlanır.

```dart
// Örnek: SalesViewModel'de Hive yerine Riverpod memory cache
@override
FutureOr<SalesState> build() {
  ref.cacheFor(const Duration(minutes: 5));
  return _fetchSales();
}
```

### 8.4 `CategoryService` SCHEMA_VERSIONED Uyumu
ADR §9'a göre kategori verisi `SCHEMA_VERSIONED` kategorisindedir: TTL yerine backend `schema:static_version` değişince invalidate edilmeli. Şu an static `Map` ile process ömrüne bağlı; mobil tarafta da sürüm bazlı invalidasyon uygulanmalı.

### 8.5 `_kCacheVersion = 2` Hardcoded Değer
ADR §9'daki `schema:static_version` Redis anahtarıyla uyumsuz. İdealde startup'ta backend'ten versiyon çekilip karşılaştırılmalı.

---

## 10. Story Cache Detay Analizi

### 10.1 Cache Durumu

Story verileri `ApiService.get()` SWR akışı üzerinden Hive `api_cache` box'a yazılır.

| Provider | Cache Key | TTL | Tetiklenme |
|---|---|---|---|
| `storyGroupsProvider` (autoDispose) | `cache_stories` | **2 dakika** | Her `build()` → SWR; `refresh()` → `bypassCache: true` |
| `myStoriesProvider` (autoDispose) | `cache_my_stories` | **2 dakika** | Her `build()` → SWR |

- 2 dakika içinde ekrana dönülürse: cache-first (anlık), sessiz arka plan yenileme.
- 2 dakika sonra: **kırık SWR** devreye girer — `getData()` `null` döner, ekran doğrudan API bekler (§2.3).

### 10.2 Viewed (İzlenmiş) Durum Takibi

**`StoryItem` modelinde `isViewed` alanı yoktur.** `UserStoryGroup` modelinde de `allViewed` alanı yoktur.

```dart
// story.dart — StoryItem alanları
final int id;
final String storyType;
final String? videoUrl;
final String? thumbnailUrl;
final DateTime? expiresAt;
final int likesCount;
final bool isLiked;
// ← isViewed / hasBeenWatched YOK
```

`recordStoryView(storyId)` sadece backend'e POST atar (`/stories/{id}/view`); local state'de hiçbir iz bırakmaz.

**Sonuç:** Kullanıcı bir story izleyip geri döndüğünde, client izlendi-izlenmedi ayrımını bilmiyor. Story tray'de görsel fark (gri halka) yok; backend'in döndürdüğü veriye de bu bilgi yansımıyor. Her story listesi yenilemesinde kullanıcı tüm içerikleri "yeni gibi" görür.

### 10.3 autoDispose Etkisi

Her iki provider `AutoDisposeAsyncNotifier`. Story ekranından çıkılınca provider dispose olur. Geri gelindiğinde `build()` tekrar çalışır:
- TTL dolmamışsa → anlık cache, arka plan yenileme
- TTL dolmuşsa → yüklenme göstergesi, API bekleme

### 10.4 Risk Özeti

| Sorun | Risk |
|---|---|
| `isViewed` alanı yok → kullanıcı izlediği story'yi tekrar izleyebilir | **ORTA** (UX sorunu; kota değil) |
| 2 dk TTL kısa; kırık SWR ile TTL sonrası boş ekran | **DÜŞÜK-ORTA** |
| autoDispose + 2 dk TTL → kısa aralıklı tekrar ziyarette gereksiz API çağrısı yok (cache yeterli) | ✓ |

---

## 9. Uygulama Kararı

Uygulama yapılabilir. Değişiklikler yalnızca mobile `lib/` kapsamında; backend şemasına, API'ye, routing'e dokunmuyor.

### Öncelik Sıralaması

**P0 — Hemen (hatalı davranış / veri bütünlüğü):**

1. **Race condition düzelt:** `HomeViewModel.build()` içinde `_loadFromCache()` `await` edilmeli ya da senkron hale getirilmeli.
2. **`homeCache` TTL ekle:** `CacheService.saveData(ttl: Duration(minutes: 30))` kullan; `_kCacheVersion` hardcoded versiyonu ek güvence olarak bırakılabilir.

**P1 — Güvenilirlik / gereksiz istek azaltma:**

3. **Gerçek SWR uygula:** `CacheService.getData()` expire olmuş veriyi silmek yerine `isStale: true` flagıyla döndürmeli. `ApiService.get()` bayat veriyi de emit etmeli.
4. **`PublicProfileViewModel` cache:** `ApiService.get()` SWR entegrasyonu (`"public_profile_$username"`, TTL 5 dk). Listings ve ratings için de aynı şekilde.
5. **`SalesViewModel` cache:** `ApiService.get()` SWR entegrasyonu ya da `ref.cacheFor(5 dk)`.

**P2 — Tutarlılık:**

6. **`TeqCachedImage` wrapper:** Tüm 95 `CachedNetworkImage` kullanımını tek wrapper üzerinden çalıştır; cache manager tek noktada yönetilir.
7. **`AccountInfo` resume debounce:** Son reload zamanını tut; 30 saniye geçmemişse `resumed` tetiklemesini atla.
8. **`CategoryService` invalidasyon:** Startup'ta backend versiyon kontrolü veya foregrounding'de yenileme.

**P3 — Uzun vadeli / mimari:**

9. **ETag / `If-None-Match` desteği:** `ApiClient`'a conditional request ekle; sunucu 304 dönerse cache'i koru.
10. **Repository katmanı:** `homeCache` Hive erişimini `ListingRepository`'ye taşı; ViewModel veri kaynağını bilmesin.
11. **`CacheService` DIP:** Statik metotları kaldır, Riverpod `Provider` ile enjekte et; böylece mock'lanabilir.
12. **DRY:** SharedPreferences cache metotlarını `CacheService`'e taşı (tek `{_d, _t, _x}` implementasyonu).
