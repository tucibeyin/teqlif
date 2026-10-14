# Mobile Cache Sistem Analizi — V1.1 Bulgular & Uygulama Spesifikasyonu

**Tarih:** 2026-10-14
**Kapsam:** ADR, Clean Architecture, MVVM, OTA/ARB, Redis, PostgreSQL, backend servisleri ve V2.1 sistem mimarisine göre tam re-analiz
**Revizyon:** V1.1 — 13 bulgu, uygulama bekliyor

---

## 0. Uyum Gereksinimleri

Bu döküman kapsamındaki **her değişiklik**, aşağıdaki kurallara tam uyumlu olmak zorundadır.

### 0.1 `teqlif_architectural_decisions.md` Önce Okunur

`documents/teqlif_architectural_decisions.md` — ADR §13 gereği her kod değişikliğinden önce okunur. Bu dökümanın herhangi bir maddesi uygulanmadan önce ADR kontrol edilir; bir karar zaten ADR'de varsa yeni bir karar oluşturulmaz, var olan karar uygulanır.

### 0.2 ADR §9 — Cache Taksonomisi (her cache değişikliği)

| Taksonomi | Nasıl Tanınır | Uygulama Kuralı |
|---|---|---|
| **SCHEMA_VERSIONED** | Katalog, şehirler, kategori — şema değişince geçersiz | Sürüm çarpması + migration zorunlu |
| **ALGORITHMIC** | Personalized feed, trending — hesaplaması pahalı | Kendi TTL'i + backend cron ile senkron |
| **LIFECYCLE** | Profil, ilan, stream — yaşam döngüsüne bağlı | Olay bitişinde `clearData()` ile invalidasyon |
| **SECURITY_CRITICAL** | Token, rate limit, presigned URL | TTL dışında müdahale yasak |
| **EPHEMERAL** | Bakiye, mesaj listesi — hızla bayat | Kısa TTL + event-driven güncelleme |

Cache anahtarının taksonomisi hatalı sınıflandırılırsa invalidasyon stratejisi yanlış seçilir. **§1 tablosuna bakılmadan yeni cache eklenmez.**

### 0.3 ADR §8 — MVVM (her ViewModel değişikliği)

| Katman | Yapabilir | Yapamaz |
|---|---|---|
| **Model** | API DTO, entity, domain nesnesi | UI import, `BuildContext`, Riverpod widget ref |
| **ViewModel** | İş mantığı, API çağrısı, state yönetimi, Repository üzerinden cache erişimi | `flutter/material.dart`, `BuildContext`, `http.get()`, `Hive.openBox()`, `StorageService.getToken()` |
| **View (Screen)** | `ref.watch()` ile state göster, ViewModel metodlarını çağır | İş mantığı, `http.get()`, Hive erişimi, cache işlemi |

### 0.4 Clean Architecture — Katman Sınırları

```
Presentation  →  Domain  →  Data
  (View)          (ViewModel)   (Repository / Service / Cache)
```

- Presentation → Data doğrudan erişim yasak.
- Bağımlılık oku içeri doğru akar.
- Cache bir Data Layer detayıdır — ViewModel `HomeRepository` veya `CacheService` üzerinden erişir.
- `http.get()`, `Hive.openBox()`, `StorageService.getToken()` ViewModel içinde çağrılamaz.

### 0.5 ADR §13 — Development Workflow (her commit)

```
1. Local    Mac'te kod yazılır, flutter analyze temiz geçmeli
2. push     git push — GitHub'a gönderilir
3. pull     İlgili node'da git pull (sudo'suz)
4. config   .env veya config değişikliği varsa düzenlenir
5. log      sudo journalctl -u teqlif -f ile canlı log izlenir
6. onay     Değişiklik mobil/staging üzerinden test edilir
7. docs     Bu döküman güncellenir, commit numarası eklenir
8. izleme   Node hataları kısa süre gözlemlenir
9. cleanup  Geçici dosyalar temizlenir
```

Flutter-spesifik:
- Her değişiklik sonrası `flutter analyze` sıfır hata/uyarı.
- P0 ve P1 değişiklikleri staging'de (`dart_defines/staging.json`) test edildikten sonra prod'a taşınır.
- Cache key değişikliği veya eklenmesinde `StorageService` sabit listesi güncellenir.

---

## 1. ADR §9 — Tüm Cache Anahtarlarının Taksonomi Tablosu

| Cache Key | Taksonomi | Client TTL | Backend Redis TTL | Invalidasyon Tetikleyici | Durum |
|-----------|-----------|-----------|------------------|--------------------------|-------|
| `i18n_cache` (Hive) | SCHEMA_VERSIONED | 24h | 1h (`/api/i18n`) | `sync_translations.py` + `bump_schema_version()` | ✅ |
| `field_config_*` (Hive) | SCHEMA_VERSIONED | in-memory | 24h | admin deploy | ✅ |
| `catalog` / `cities` | SCHEMA_VERSIONED | — (backend) | 24h + schema_v | migration + `bump_schema_version()` | ✅ |
| `home_feed_recent` (Hive box) | ALGORITHMIC | 30 min | **15 min** | — (TTL) | ⚠️ §12.10 |
| `explore_for_you` / `feed_personalized` | ALGORITHMIC | 10 min | 15 min | — (TTL) | ✅ |
| `explore_personalized_feed` | ALGORITHMIC | 10 min | 15 min | — (TTL) | ✅ |
| `cache_streams` | LIFECYCLE | 3 min | — | ❌ stream sonu event yok | 🔴 §12.9 |
| `cache_auctions` | LIFECYCLE | — | — | ❌ kullanılmıyor | 🔴 §12.9 |
| `cache_stories` | LIFECYCLE | 5 min | — | story.expires_at TTL örtüşüyor | ✅ |
| `cache_profile` | LIFECYCLE | 15 min | — | TTL | ✅ kabul |
| `public_profile_*` | LIFECYCLE | 15 min | — | TTL | ✅ kabul |
| `public_listings_*` | LIFECYCLE | 10 min | — | TTL | ✅ |
| `public_ratings_*` | LIFECYCLE | 30 min | — | TTL | ✅ |
| `cache_messages` | EPHEMERAL | 5 min (implicit) | — | WS gerçek zamanlı | 🟡 §12.2 |
| `cache_notifications` | EPHEMERAL | 5 min (implicit) | — | push notification | 🟡 §12.2 |
| `cache_message_requests` | EPHEMERAL | 5 min (implicit) | — | WS event | 🟡 §12.2 |
| `cache_sales` | LIFECYCLE | 3 min | — | `clearData` satış tamamlandığında | ✅ |
| `cache_my_ratings_*` | LIFECYCLE | 10 min | — | `clearData` refresh'te | ✅ |
| `cache_blocked_users` | LIFECYCLE | 10 min | — | `clearData` blokta | ✅ |
| `cache_notification_settings` | SCHEMA_VERSIONED | 30 min | — | `clearData` ayar değişince | ✅ |
| `cache_feed` | — | — | — | `StorageService`'te tanımlı, hiçbir ViewModel yazamıyor — dead code; §12.9 temizliği kapsamında kaldırılır | 🔴 §12.9 |
| `user_wallet_data` | LIFECYCLE | default 5 min | — | `clearData` ödeme sonrası | ✅ |
| `follow_list_*` | LIFECYCLE | 5 min | — | TTL | ✅ |

**Kural (ADR §9):** LIFECYCLE anahtarlar için TTL tek başına yetmez — olayın sonunda `clearData()` da çağrılmalıdır. TTL yalnızca event kaçırıldığında ağ yeniden senkronizasyonunu garanti eder.

---

## 2. Özet Tablo

| § | Başlık | Öncelik | Etkilenen Sistem |
|---|--------|---------|-----------------|
| §12.1 | `flutter_cache_manager` sürüm sabitleme | **P0** | Mobil |
| §12.2 | messages/notifications açık TTL | **P1** | Mobil |
| §12.3 | TeqlifCacheManager tüm CachedNetworkImage'lara yay | **P1** | Mobil |
| §12.4 | memCacheWidth/Height feed kartlarına ekle | **P1** | Mobil |
| §12.9 | LIFECYCLE cache → WS event invalidasyonu | **P1** | Mobil + WS |
| §12.10 | Backend ↔ mobil TTL uyumsuzluğu (home feed) | **P1** | Mobil + Backend |
| §12.11 | HomeViewModel / SearchViewModel — direct http.get (ADR §8 ihlali) | **P1** | Mobil MVVM |
| §12.5 | Feed loadMore() sayfaları diske yaz | **P2** | Mobil |
| §12.6 | api_cache box maksimum anahtar limiti | **P2** | Mobil |
| §12.12 | cacheKey parametresi — presigned URL bağımlılığı | **P2** | Mobil |
| §12.13 | Backend `Cache-Control` header eksikliği | **P2** | Backend + Cloudflare |
| §12.7 | PublicProfile prefetch | **P3** | Mobil |
| §12.8 | Entity normalization store | **P3** | Mobil |

---

## 3. Bulgular

### §12.1 `flutter_cache_manager: any` — Sürüm Sabitleme

**Öncelik:** P0
**Dosya:** `mobile/pubspec.yaml:66`

`any` kısıtı, `flutter pub upgrade` veya CI ortamında farklı sürüm çözümü alınmasını sağlar. `cached_network_image: ^3.3.1` zaten `flutter_cache_manager`'a bağımlıdır; `any` bırakmak gereksiz ve bir sonraki breaking change'de sessizce bozulma riskidir.

**Uygulama:**

```yaml
# mobile/pubspec.yaml
flutter_cache_manager: ">=3.3.1 <4.0.0"
```

Mevcut prod sürümünü doğrula: `flutter pub deps | grep flutter_cache_manager`. Ardından sabitle.

**Doğrulama:** `flutter pub upgrade --dry-run` çıktısında version conflict yok; `flutter analyze` sıfır hata.

---

### §12.2 messages / notifications / message_requests — Açık TTL Eksikliği

**Öncelik:** P1
**Dosya:** `mobile/lib/screens/viewmodels/messages_view_model.dart:155,280,349`

Üç EPHEMERAL anahtar `saveData` çağrısında `ttl` parametresi geçmiyor. Şu an `CacheService` varsayılanı olan 5 dakika uygulanıyor — bu değer doğru, ancak ADR §9 taksonomisi gereği TTL her zaman açık bildirilmelidir. `CacheService` varsayılanı ileride değişirse sessizce hatalı TTL uygulanır.

**Uygulama:**

```dart
// messages_view_model.dart — _fetchMessages(), _fetchNotifications(), _fetchMessageRequests()
await _cache.saveData(
  StorageService.cacheMessages, data,
  ttl: const Duration(minutes: 5), // EPHEMERAL — WS gerçek zamanlı günceller
);
await _cache.saveData(
  StorageService.cacheNotifications, data,
  ttl: const Duration(minutes: 5),
);
await _cache.saveData(
  StorageService.cacheMessageRequests, data,
  ttl: const Duration(minutes: 5),
);
```

**Doğrulama:** `flutter analyze` sıfır hata. Mesajlar ekranı offline açılınca cached data gösterir; 5 dakika sonra network fetch tetikler.

---

### §12.3 TeqlifCacheManager — Tüm CachedNetworkImage Kapsamı

**Öncelik:** P1
**Dosya:** 47 widget, ekran listesi aşağıda

60 `CachedNetworkImage` widget'ından 13'ü `TeqlifCacheManager` (2 gün TTL, 300 dosya) kullanıyor. Geri kalan 47'si `DefaultCacheManager` (7 gün TTL, 200 dosya) ile çalışıyor. Uygulama genelinde tutarsız cache politikası oluşuyor.

**Kapsam (frekanslıdan başlayarak):**

| Ekran | Widget sayısı |
|-------|--------------|
| `messages_screen.dart` | 3 CachedNetworkImage + 2 CachedNetworkImageProvider |
| `recording_detail_screen.dart` | 4 CachedNetworkImage + 4 CachedNetworkImageProvider |
| `sales_screen.dart` | 2 |
| `purchase_detail_screen.dart` | 2 |
| `retargeting_screen.dart` | 2 |
| `direct_sale_detail_screen.dart` | 1 |
| `follow_requests_screen.dart` | 1 CachedNetworkImageProvider |
| `call_history_screen.dart` | 1 CachedNetworkImageProvider |
| `blocked_users_screen.dart` | 1 CachedNetworkImageProvider |

**Uygulama:**

```dart
// Her CachedNetworkImage(...) çağrısına ekle:
cacheManager: TeqlifCacheManager(),

// CachedNetworkImageProvider(url) → 
CachedNetworkImageProvider(url, cacheManager: TeqlifCacheManager())
```

**Doğrulama:** `TeqlifCacheManager` disk cache dizininde (`teqlifImgCache/`) büyürken `flutter_cache/` küçülüyor.

---

### §12.4 memCacheWidth / memCacheHeight — Bellek Önbellek Optimizasyonu

**Öncelik:** P1
**Dosya:** Tüm 60 CachedNetworkImage widget (0 `memCacheWidth` kullanımı)

`PaintingBinding.instance.imageCache` 25 MB ile sınırlı (V1.0). 1080px tam boyutlu görseller 80×80 avatar alanında decode ediliyor — bellek ~180× gereksiz harcanıyor. `memCacheWidth` / `memCacheHeight` sağlandığında Flutter, decode sırasında boyutu küçültür; bellek önbellekteki boyut düşer.

**Uygulama:**

```dart
// Avatar (~60 dp ekranda, 2× density)
CachedNetworkImage(
  imageUrl: avatarUrl,
  cacheKey: 'user_${userId}_avatar',       // §12.12 ile birlikte
  cacheManager: TeqlifCacheManager(),      // §12.3 ile birlikte
  memCacheWidth: 120,
  memCacheHeight: 120,
  fit: BoxFit.cover,
)

// Feed kartı ana görseli (~200 dp ekranda, 2× density)
CachedNetworkImage(
  imageUrl: photoUrl,
  cacheKey: 'listing_${listingId}_photo_0',
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 400,
  fit: BoxFit.cover,
)

// Tam ekran görsel (ilan detay, kayıt)
CachedNetworkImage(
  imageUrl: photoUrl,
  cacheKey: 'listing_${listingId}_photo_${index}',
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 800,
  fit: BoxFit.contain,
)
```

Kural: `memCacheWidth = round(renderWidth_dp × devicePixelRatio)`. Layout sabit değilse üst sınır: avatar=120, feed kart=400, tam ekran=800.

**Doğrulama:** Flutter Profile mode memory profiler'da image cache bellek kullanımı azalıyor.

---

### §12.5 Feed loadMore() Sayfaları — Disk Kalıcılığı

**Öncelik:** P2
**Dosya:** `mobile/lib/repositories/home_repository.dart`, `mobile/lib/screens/viewmodels/home_view_model.dart:235`, `mobile/lib/screens/viewmodels/search_view_model.dart:445,503`

`loadMore()` API çağrısı §12.11 kapsamında `HomeRepository`'ye taşındıktan sonra disk kalıcılığı aynı Repository metoduna eklenir; §12.11 ve §12.5 tek PR'da birleşir (S4).

`loadMore()` başarılı yanıtları yalnızca state'e yazıyor, Hive cache'e değil. Uygulama arka plana alınıp geri dönüldüğünde yalnızca sayfa 0 görünür; kullanıcının kaydırdığı ilan listesi kaybolur.

**Uygulama:**

`HomeRepository.loadMore()` içinde (§12.11 sonrası oluşturulacak metod) merged listeyi diske yazar:

```dart
// home_repository.dart — loadMore() metodu
Future<HomeFeedPage> loadMore({required int page, int? maxId}) async {
  final uri = maxId != null
      ? Uri.parse('${_client.config.baseUrl}/feed/recent?max_id=$maxId')
      : Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page');
  final resp = await _client.get(uri);
  if (resp.statusCode != 200) throw HttpException(resp.statusCode);

  final parsed = jsonDecode(resp.body);
  final more = (parsed is List ? parsed : (parsed['listings'] ?? [])) as List<dynamic>;

  // Biriktirilen listeyi limitle ve diske yaz
  const kMaxCachedListings = 60; // 3 sayfa × 20 ilan
  final current = (await loadCache())?.recentListings ?? <dynamic>[];
  final merged = [...current, ...more]
      .fold<List<dynamic>>([], (acc, e) =>
          acc.any((x) => x['id'] == e['id']) ? acc : [...acc, e])
      .take(kMaxCachedListings)
      .toList();
  await saveFeed(jsonEncode(merged));

  return HomeFeedPage(listings: more, totalPages: parsed['pagination']?['total_pages'] ?? page);
}
```

`home_view_model.dart` `loadMore()` → `_repo.loadMore(page: nextPage, maxId: current.lastMaxId)` çağrısına indirgenir.

**Pull-to-refresh sıfırlama:** `onRefresh` (sayfa 0 yenileme) `fetchRecent(page: 0)` → `saveFeed(jsonEncode(page.listings))` çağırır; bu çağrı `api_cache` box'taki `home_feed_recent` anahtarını biriktirilmiş listeyle birlikte **eze**r. `loadMore()` ise her zaman önce `loadCache()` ile mevcut listeyi okur, merge eder, tekrar yazar. İki kod yolu birbirinden ayrı tutulur; refresh'te `loadMore()` çağrılmaz.

Aynı pattern `SearchRepository.loadMoreRecent()` ve `SearchRepository.loadMoreForYou()` olarak oluşturulur.

**Doğrulama:** 3 sayfa kaydır → arka plana al → geri dön → liste korunmuş; sayfa 0'dan fazlası görünüyor.

---

### §12.6 api_cache Box — Maksimum Anahtar Limiti (LRU Kırpma)

**Öncelik:** P2
**Dosya:** `mobile/lib/services/cache_service.dart`

`api_cache` Hive box yalnızca TTL'e göre temizleniyor. Dinamik anahtarlar (`public_profile_<username>`, `public_listings_<username>`, `feed_personalized`) kullanıcı davranışına göre birikir; aktif kullanıcıda 500+ anahtar oluşabilir (~1 MB Hive box boyutu).

**Uygulama:**

```dart
// cache_service.dart — clearExpired() metoduna TTL temizlemesinin ardından ekle
Future<void> clearExpired() async {
  final box = Hive.box<String>(_boxName);
  final now = DateTime.now().millisecondsSinceEpoch;

  // 1. TTL dolmuş kayıtları sil
  final expiredKeys = <dynamic>[];
  for (final key in box.keys) {
    final raw = box.get(key);
    if (raw == null) { expiredKeys.add(key); continue; }
    final wrapper = jsonDecode(raw) as Map<String, dynamic>;
    final savedAt = (wrapper['_t'] as num).toInt();
    final ttlMs   = (wrapper['_x'] as num).toInt();
    if (now - savedAt > ttlMs) expiredKeys.add(key);
  }
  await box.deleteAll(expiredKeys);

  // 2. Limit aşımında en eski kayıtları kırp
  const maxKeys = 200;
  if (box.length > maxKeys) {
    final entries = <MapEntry<dynamic, int>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      entries.add(MapEntry(key, (wrapper['_t'] as num).toInt()));
    }
    entries.sort((a, b) => a.value.compareTo(b.value));
    final toDelete = entries.take(box.length - maxKeys).map((e) => e.key).toList();
    await box.deleteAll(toDelete);
  }
}
```

**Doğrulama:** 300 farklı anahtar yaz → `clearExpired()` çağır → `box.length ≤ 200`.

---

### §12.7 PublicProfile Prefetch — Gecikmeli Önbellek Isıtma

**Öncelik:** P3
**Dosya:** `mobile/lib/screens/viewmodels/public_profile_view_model.dart`, feed kart widget'ları

Kullanıcı feed kartına dokunmadan önce hedef profilin önbelleğe alınması, `PublicProfileScreen` açılışındaki yükleme gecikmesini ortadan kaldırır.

**Mimari:**

ADR §8 gereği prefetch ViewModel metodunu View'dan tetikler; ancak View, ViewModel'in hangi ekranda olduğunu bilmeden `ref.read(publicProfileViewModelProvider(arg).notifier).warmup(username)` çağrısını `onLongPress` veya `onHover` anında yapabilir.

**Uygulama:**

```dart
// PublicProfileViewModel — alan ve yeni metod
final _warming = <String>{}; // eş zamanlı warmup fetch'lerini izler

Future<void> warmup(String username) async {
  if (_warming.contains(username)) return; // zaten in-flight
  final cached = ref.read(cacheServiceProvider).getData(_profileKey(username));
  if (cached != null) return; // zaten cache'te güncel veri var
  _warming.add(username);
  try {
    await _fetchProfile(PublicProfileArg(username: username));
  } catch (_) {
    // warmup başarısız olursa ekran normal flow ile yükler
  } finally {
    _warming.remove(username);
  }
}
```

```dart
// Feed kart widget'ı — onLongPress veya onHover
onLongPress: () {
  ref.read(publicProfileViewModelProvider(
    PublicProfileArg(username: item.sellerUsername),
  ).notifier).warmup(item.sellerUsername);
},
```

`warmup()` fire-and-forget çağrıdır; View state'i beklemez. Kullanıcı karta dokunduğunda `PublicProfileScreen` build olur, `CacheService` sıcak veriyi anında döner.

**Kısıt:** `warmup()` aynı kullanıcı için birden fazla kez tetiklenmeyecek şekilde `_warming` Set guard ile korunur. Feed'de 20 kart render olduğunda eş zamanlı 20 prefetch isteği açılmaz; yalnızca kullanıcının dokunduğu veya uzun bastığı kart tetikler.

**Doğrulama:** Feed kartına uzun bas → hemen tap → PublicProfileScreen yükleme göstergesi görünmez, veri anında gelir.

---

### §12.8 Entity Normalization Store

**Öncelik:** P3
**Dosya:** `mobile/lib/services/cache_service.dart`, tüm feed ve profil cache anahtarları

Aynı `Listing` entity'si eş zamanlı 5-6 farklı cache anahtarında bulunabilir (`home_feed_recent`, `explore_for_you`, `public_listings_<username>`, `user_favorites` vb.). Bir ilan kapandığında veya fiyat güncellendiğinde yalnızca doğrudan tetiklenen anahtar temizlenir; diğerleri TTL dolana kadar bayat kalır.

**Hedef Mimari:**

```
api_cache (Hive)
  entity_listing_42  → { id, title, price, status, ... }   ← tek kaynak
  entity_listing_17  → { ... }
  entity_user_99     → { id, username, avatar, ... }

  home_feed_recent   → [42, 17, 98, ...]                    ← yalnızca ID listesi
  explore_for_you    → [17, 42, 301, ...]
  public_listings_ayse → [42, 301, ...]
```

**Uygulama:**

1. `CacheService`'e `EntityStore` katmanı ekle:
   ```dart
   Future<void> saveEntity(String type, int id, Map<String, dynamic> data, {Duration? ttl}) async {
     await saveData('entity_${type}_$id', data, ttl: ttl);
   }
   Map<String, dynamic>? getEntity(String type, int id) =>
       getData('entity_${type}_$id') as Map<String, dynamic>?;
   ```

2. Feed cache'leri JSON yerine ID listesi saklar:
   ```dart
   await _cache.saveData(StorageService.cacheHomeFeed, listings.map((e) => e['id']).toList(), ...);
   ```

3. Feed widget'ları ID'ye göre `EntityStore`'dan resolve eder:
   ```dart
   // entity_store.dart — Riverpod provider tanımı
   final entityProvider = Provider.family<Map<String, dynamic>?, (String, int)>(
     (ref, args) => ref.watch(cacheServiceProvider).getEntity(args.$1, args.$2),
   );

   // Feed widget'ı
   final listing = ref.watch(entityProvider(('listing', item.id)));
   ```

**Kısıt — Migration:** S7 deploy öncesinde `CacheService.clearAll()` çağrısı ile `api_cache` box temizlenir. Mevcut `home_feed_recent` vb. full-JSON cache'leri ID-list formatıyla uyumsuz olduğundan ilk açılışta network fetch tetikler; box boş gelir, entity store'a yazılır.

**ADR §22 (S7 tamamlandığında eklenir):** Feed cache'ler ID listesi saklar; entity verisi `entity_<type>_<id>` anahtarında tek kayıtta tutulur. Tek entity güncellendiğinde tüm feed görünümleri tutarlı kalır.

**Doğrulama:** Bir ilan fiyatı değişince tüm feed ve profil listelerinde aynı anda güncelleniyor; hiçbir görünümde bayat fiyat kalmıyor.

---

### §12.9 LIFECYCLE Cache — WS Event Invalidasyonu Eksikliği

**Öncelik:** P1
**Dosya:** `mobile/lib/providers/auction_provider.dart`, `mobile/lib/providers/direct_sale_provider.dart`, `mobile/lib/providers/live_stream_provider.dart`

ADR §9: "LIFECYCLE: Olayın bitişiyle tetiklenir." `cacheStreams` ve `cacheAuctions` yalnızca TTL ile evict ediliyor; WS üzerinden gelen bitiş event'i geldiğinde cache temizlenmiyor.

Senaryo: Kullanıcı açık artırma listesini görüyor. Artırma anında sona eriyor (WS event alınıyor). Kullanıcı listeye geri dönüyor → 3 dakikaya kadar "aktif" olarak görebilir.

`cacheAuctions` anahtarı `StorageService`'te tanımlı ancak hiçbir ViewModel tarafından kullanılmıyor. Açık artırma listesi `cacheAuctions`'a yazılmalı ya da dead code temizlenmeli.

**Uygulama:**

ADR §10 gereği WS altyapısına dokunulmaz; cache temizleme yalnızca `onCommerceEvent()` alt sınıf metoduna eklenir:

```dart
// auction_provider.dart — AuctionNotifier.onCommerceEvent()
case 'auction_ended':
case 'auction_ended_by_buy_it_now':
  ref.read(cacheServiceProvider).clearData(StorageService.cacheAuctions);
  // Artık aktif olmayan açık artırmayı listeleme cache'inden de temizle
  ref.read(cacheServiceProvider).clearData(StorageService.cacheStreams);
  break;
```

```dart
// direct_sale_provider.dart — DirectSaleHostNotifier.onCommerceEvent()
case 'direct_sale_ended':
  ref.read(cacheServiceProvider).clearData(StorageService.cacheStreams);
  break;
```

WS bağlantısı yokken sona eren stream/auction TTL ile evict edilir — bu beklenen davranış, ek mekanizma gerekmez.

**Doğrulama:** Aktif bir yayın, WS üzerinden `auction_ended` aldıktan hemen sonra listeye dönüldüğünde görünmüyor.

---

### §12.10 Backend ↔ Mobil TTL Uyumsuzluğu

**Öncelik:** P1
**Dosya:** `mobile/lib/repositories/home_repository.dart:27`, `backend/app/routers/feed.py:362`

| Katman | TTL | Kaynak |
|--------|-----|--------|
| Backend Redis `feed:personalized:{uid}` | 15 dakika | `feed.py:362 → setex(cache_key, 900, ...)` |
| Flutter `HomeRepository._kCacheTtlMs` | **30 dakika** | `home_repository.dart:27` |
| Flutter `search_view_model` for-you | 10 dakika | `search_view_model.dart:330` |

`HomeRepository` 30 dakika geçerli sayarken backend aynı veriyi 15 dakikada yeniliyor. Kullanıcı uygulamayı 20 dakika sonra açtığında mobil 10 dakika daha eski önbelleği dönerken backend kişiselleştirme modelini yenilemiş olabilir. Sosyal ticaret bağlamında yeni ilanlar, fiyat değişikliği ve kişiselleştirme güncelliği kritiktir.

**Uygulama:**

```dart
// mobile/lib/repositories/home_repository.dart
static const _kCacheTtlMs = 15 * 60 * 1000; // 30 → 15 dk (backend Redis TTL ile senkron)
```

`search_view_model.dart:330` zaten 10 dakika kullanıyor; for-you feed için daha kısa TTL daha iyi — değiştirilmez.

**Doğrulama:** `HomeRepository` 16 dakika sonra cache miss verir; ağ isteği atılır.

---

### §12.11 HomeViewModel / SearchViewModel — Direct http.get (ADR §8 İhlali)

**Öncelik:** P1
**Dosya:** `mobile/lib/screens/viewmodels/home_view_model.dart`, `mobile/lib/screens/viewmodels/search_view_model.dart`

ADR §8: "ViewModel doğrudan `http.get()`, `Hive.openBox()`, `SharedPreferences.getInstance()` çağıramaz."

`home_view_model.dart` içindeki `_fetchInitial()`, `_fetchForYou()`, `loadMore()`, `notInterested()` ve `search_view_model.dart` içindeki `_loadForYou()`, `_loadRecentListings()`, `loadMoreRecentListings()`, `loadMoreForYou()` metodları doğrudan `http.get()` ve `StorageService.getToken()` çağırıyor. `HomeRepository` sınıfı var olmasına rağmen yalnızca cache okuma/yazma için kullanılıyor; API çağrıları Repository dışında kalıyor.

**Uygulama:**

`HomeRepository`'ye tüm API metodlarını taşı; ViewModel yalnızca Repository metodlarını çağırır:

```dart
// home_repository.dart — eklenecek metodlar
Future<HomeFeedPage> fetchRecent({int page = 0, int? maxId}) async {
  final uri = maxId != null
      ? Uri.parse('${_client.config.baseUrl}/feed/recent?max_id=$maxId')
      : Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page');
  final resp = await _client.get(uri); // ApiClient token yönetimini içeriyor
  if (resp.statusCode != 200) throw HttpException(resp.statusCode);
  return HomeFeedPage.fromJson(jsonDecode(resp.body));
}

Future<HomeFeedPage> fetchForYou({int page = 0}) async {
  final resp = await _client.get(
    Uri.parse('${_client.config.baseUrl}/feed/for-you?page=$page'));
  if (resp.statusCode != 200) throw HttpException(resp.statusCode);
  return HomeFeedPage.fromJson(jsonDecode(resp.body));
}

Future<void> markNotInterested(int listingId) async {
  await _client.post(
    Uri.parse('${_client.config.baseUrl}/feed/not-interested/$listingId'));
}
```

```dart
// home_view_model.dart — _fetchInitial() sonrası
final page = await _repo.fetchRecent();
state = AsyncValue.data(HomeState.fromPage(page));
await _repo.saveFeed(jsonEncode(page.listings));
```

`SearchRepository` henüz yok; önce `HomeRepository` refactor edilir, ardından aynı pattern `SearchRepository` ile tekrarlanır.

**Doğrulama:** `home_view_model.dart` dosyasında `import 'package:http/http.dart'` ve `StorageService.getToken` bulunmuyor; `flutter analyze` sıfır hata.

---

### §12.12 cacheKey Parametresi — Presigned URL Bağımlılığı

**Öncelik:** P2
**Dosya:** Tüm 60 CachedNetworkImage widget

`flutter_cache_manager`, URL'yi cache key olarak kullanır. MinIO presigned URL sorgu parametreleri (`X-Amz-Expires`, `X-Amz-Signature`) değişince cache miss oluşur; tüm görseller yeniden indirilir. Staging → prod geçişi veya bucket yapısı değişikliğinde aynı sorun yaşanır.

`grep -rn "cacheKey:" mobile/lib/` → 0 sonuç.

**Uygulama:**

Entity ID tabanlı stabil cache key kullan:

```dart
// İlan görseli
CachedNetworkImage(
  imageUrl: listing.photoUrl,
  cacheKey: 'listing_${listing.id}_photo_${photoIndex}',
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 400,
)

// Kullanıcı avatarı
CachedNetworkImage(
  imageUrl: user.avatarUrl,
  cacheKey: 'user_${user.id}_avatar',
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 120,
  memCacheHeight: 120,
)

// CachedNetworkImageProvider
CachedNetworkImageProvider(
  user.avatarUrl,
  cacheKey: 'user_${user.id}_avatar',
  cacheManager: TeqlifCacheManager(),
)
```

Kural: `cacheKey = entityType_entityId_fieldName`. URL segment, query string veya imza içermez.

**Doğrulama:** MinIO bucket adı değiştirilip presigned URL yenilendiğinde mevcut görseller önbellekten servise devam ediyor; yeniden indirme yaşanmıyor.

---

### §12.13 Backend — `Cache-Control` Header Eksikliği

**Öncelik:** P2
**Dosya:** `backend/app/routers/feed.py`, `backend/app/routers/catalog.py`, `backend/app/routers/i18n.py`

Backend hiçbir response'a `Cache-Control` header'ı eklemiyor. Cloudflare, `teqlif.com` ve `api.teqlif.com` üzerinde Proxied modda çalışıyor (ADR §12). Standart `Cache-Control` header'ı olan JSON response'lar Cloudflare edge'de cache'lenebilir; bu özellikle SCHEMA_VERSIONED ve ALGORITHMIC endpoint'ler için bant genişliği ve gecikme kazancı sağlar.

V1.0 §11.16'da ETag desteği eklendi (`If-None-Match`). `Cache-Control` ETag'ı tamamlar: `max-age` dolmadan istemci sunucuya gitmiyor, dolunca `If-None-Match` ile gidiyor.

**Uygulama:**

```python
# backend/app/routers/feed.py
from fastapi import Response

@router.get("/feed/recent")
async def get_recent_feed(..., response: Response):
    response.headers["Cache-Control"] = "private, max-age=300, stale-while-revalidate=900"
    ...
    return listings

@router.get("/feed/for-you")
async def get_for_you_feed(..., response: Response):
    response.headers["Cache-Control"] = "private, max-age=300, stale-while-revalidate=900"
    ...
    return listings
```

| Endpoint tipi | `Cache-Control` değeri |
|---------------|----------------------|
| `/api/catalog`, `/api/cities` (SCHEMA_VERSIONED) | `public, max-age=86400, stale-while-revalidate=3600` |
| `/api/feed/recent`, `/api/feed/for-you` (ALGORITHMIC) | `private, max-age=300, stale-while-revalidate=900` |
| `/api/i18n/{lang}` (SCHEMA_VERSIONED) | `public, max-age=3600, stale-while-revalidate=86400` |
| Commerce / auction / stream (LIFECYCLE) | `no-cache` |
| Auth / payment (SECURITY_CRITICAL) | `no-store` |

`private` = yalnızca istemci cache'ler, Cloudflare edge'e geçmez. `public` = Cloudflare edge cache'leyebilir.

**Cloudflare — Authorization Header Kısıtı:**

Cloudflare, `Authorization` header'ı içeren request'leri varsayılan olarak cache'lemez. `public` direktifi tek başına yetmez; `/api/catalog` ve `/api/cities` endpoint'leri için aşağıdakilerden biri uygulanmalıdır:

- **Seçenek A (Tercih):** Mobil `ApiClient`'ta bu iki endpoint için `Authorization` header'ı çıkarılır. Bu endpoint'ler public veri döner, kimlik doğrulama gerektirmez.
- **Seçenek B:** Cloudflare dashboard'da Cache Rules → "Bypass cache on cookie/header" için `catalog` ve `cities` path'lerinde `Authorization` header'ı yoksayılır.

Seçenek A, backend değişikliği gerektirmeyen ve güvenlik açısından daha temiz yaklaşımdır; seçeneğin ADR'ye (`§23 Cloudflare Cache Rules`) kaydedilmesi gerekir.

**Doğrulama:** `curl -I https://api.teqlif.com/feed/recent` response header'ında `Cache-Control: private, max-age=300` görünüyor. `/api/catalog` için Cloudflare dashboard'da cache HIT oranı artıyor.

---

## 4. ADR §17 Tutarsızlığı — Uptime Kuma Veritabanı

ADR §17 (nodeMonitor bölümü) Uptime Kuma için "MariaDB backend" yazıyor ve MariaDB bağlantı konfigürasyonu içeriyor. 2026-10-14 backup servislerinin düzeltilmesi sırasında (`adafbfad`) doğrulandı: Uptime Kuma gerçekte SQLite kullanıyor (`/opt/monitor/shared/uptime-kuma/db/kuma.db`). ADR §17'deki MariaDB referansı ve bağlantı tablosu SQLite ile güncellenmelidir.

---

## 5. Uygulama Sırası

| Sprint | Bulgular | Öncelik |
|--------|----------|---------|
| S1 | §12.1 + §12.2 + §12.10 | P0 + P1 |
| S2 | §12.3 + §12.4 + §12.12 | P1 + P2 |
| S3 | §12.9 | P1 |
| S4 | §12.11 + §12.5 | P1 + P2 |
| S5 | §12.6 + §12.13 | P2 |
| S6 | §12.7 | P3 |
| S7 | §12.8 | P3 |

S1 → S7 ardışık uygulanır. S4 (§12.11 + §12.5) aynı sprint: `HomeRepository` refactor ile loadMore disk kalıcılığı aynı PR'da birleşir. S7 deploy öncesinde `CacheService.clearAll()` çağrısı ile `api_cache` box temizlenir (§12.8 Migration kısıtı).

---

## 6. Kapsam Dışı — V1.0'da Tamamlandı

| Madde | Commit |
|-------|--------|
| SWR gerçek bayat-göster davranışı | `bc6998ff` |
| `CacheService` instance-based DIP | `bc6998ff` |
| `HomeRepository` izolasyon katmanı | `bc6998ff` |
| `StorageService.cacheData` → `CacheService` geçişi | `bc6998ff` |
| ETag / Conditional Request (`If-None-Match` + 304) | `20ab93a5` |
