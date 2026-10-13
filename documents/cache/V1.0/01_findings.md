# Mobile Cache Sistem Analizi — Bulgular & Uygulama Spesifikasyonu

**Tarih:** 2026-10-13
**Kapsam:** Flutter mobile uygulaması client-side cache stratejisi, TTL yönetimi, veri yaşam döngüsü
**Revizyon:** V1.7 — V1.1 analizi tamamlandı; bkz. `documents/cache/V1.1/01_findings.md`

---

## 0. Uyum Gereksinimleri

Bu döküman kapsamındaki **her değişiklik**, aşağıdaki kurallara tam uyumlu olmak zorundadır. Kural sırası öncelik sırasıdır: bir çelişki durumunda üstteki kural kazanır.

---

### 0.1 `teqlif_architectural_decisions.md` Önce Okunur

`documents/teqlif_architectural_decisions.md` — ADR §13 gereği her kod değişikliğinden önce okunur. Bu dökümanın herhangi bir maddesi uygulanmadan önce ADR kontrol edilir; bir karar zaten ADR'de varsa yeni bir karar oluşturulmaz, var olan karar uygulanır.

---

### 0.2 ADR §9 — Cache Taksonomisi (her cache değişikliği)

Her yeni cache anahtarı veya TTL değişikliği için §5 tablosundaki **ADR §9 Taksonomisi** sütunu doldurulmalıdır:

| Taksonomi | Nasıl Tanınır | Uygulama Kuralı |
|---|---|---|
| **SCHEMA_VERSIONED** | Katalog, şehirler, kategori — şema değişince geçersiz | Sürüm çarpması + migration zorunlu |
| **ALGORITHMIC** | Personalized feed, trending — hesaplaması pahalı | Kendi TTL'i + backend cron ile senkron |
| **LIFECYCLE** | Profil, ilan, stream — yaşam döngüsüne bağlı | Olay bitişinde `clearData()` ile invalidasyon |
| **SECURITY_CRITICAL** | Token, rate limit, presigned URL | TTL dışında müdahale yasak |
| **EPHEMERAL** | Bakiye, mesaj listesi — hızla bayat | Kısa TTL yeterli, event-driven güncelleme |

Cache anahtarının taksonomisi hatalı sınıflandırılırsa invalidasyon stratejisi yanlış seçilir. **§5 tablosuna bakılmadan yeni cache eklenmez.**

---

### 0.3 ADR §8 — MVVM (her ViewModel değişikliği)

| Katman | Yapabilir | Yapamaz |
|---|---|---|
| **Model** | API DTO, entity, domain nesnesi | UI import, `BuildContext`, Riverpod widget ref |
| **ViewModel** (`AsyncNotifier`/`Notifier`) | İş mantığı, API çağrısı, state yönetimi, cache okuma/yazma | `flutter/material.dart`, `BuildContext`, widget ağacı bilgisi |
| **View (Screen)** | `ref.watch()` ile state göster, ViewModel metodlarını çağır | İş mantığı, `http.get()`, Hive erişimi, cache işlemi |

Kontrol listesi (her ViewModel değişikliğinde):
- [ ] ViewModel `flutter/material.dart` veya `flutter/widgets.dart` import etmiyor
- [ ] ViewModel `BuildContext` parametresi almıyor
- [ ] View'da `http.get()` / `CacheService` / `Hive.openBox()` çağrısı yok
- [ ] Navigasyon gerektiren durumlar callback pattern ile çözülüyor (ADR §8, commit `bc6998ff`)
- [ ] `setState` kullanımı yoksa gereksiz `StatefulWidget` dönüştürülüyor

---

### 0.4 Clean Architecture — Katman Sınırları

```
Presentation  →  Domain  →  Data
  (View)          (UseCase/       (Repository/
  (ViewModel)      ViewModel)      Service/Cache)
```

Kurallar:
- **Presentation → Data doğrudan erişim yasak.** `HomeViewModel`'deki `Hive.openBox('homeCache')` bu ihlale örnektir (§9.1). Bu döküman kapsamındaki yeni kodlar bu hatayı tekrarlamamalıdır.
- **Bağımlılık oku içeri doğru akar.** Data layer, Domain'i bilmez; Domain, Presentation'ı bilmez.
- **Cache bir Data Layer detayıdır.** ViewModel cache'in nerede tutulduğunu (Hive mi, SharedPreferences mi, memory mi) bilmemelidir. Cache erişimi `CacheService` veya `Repository` üzerinden yapılır.
- **Yeni ekranlar için:** ViewModel doğrudan `ApiService.get()` kullanabilir (mevcut pattern); ancak `Hive.openBox()`, `SharedPreferences.getInstance()`, `http.get()` doğrudan ViewModel içinde çağrılamaz.

---

### 0.5 Clean Code Kuralları

Bu döküman kapsamındaki tüm Flutter kodu için:

**İsimlendirme:**
- Cache key sabitleri `StorageService` içinde `static const` olarak tanımlanır; magic string yasak.
- TTL sabitleri `const Duration(minutes: X)` ile tanımlanır; magic number yasak.
- Yeni cache key: `snake_case`, scope_entity formatı (örn: `public_profile_42`, `my_ratings_received`).

**Fonksiyon büyüklüğü:**
- `build()` metodu maksimum tek sorumluluğa sahip olmalıdır: state başlatma + subscription kurma. İş mantığı ayrı private metodlara taşınır.
- Cache okuma (`_loadFromCache`) ve API çağrısı (`_fetchData`) ayrı metodlar olarak kalır; birleştirilmez.

**Yorum politikası:**
- Yorum yalnızca "neden" açıklamak için yazılır; "ne yaptığını" açıklayan yorumlar eklenmez.
- TTL değişikliğinin nedeni: satır başı kısa yorum kabul edilir (örn: `// sosyal ticaret standardı: 15 dk`).

**Hata yönetimi:**
- `recordStoryView` gibi fire-and-forget çağrılar `catchError` ile sessizce ignore edilir.
- Cache miss asla hata değildir; `null` döndürmek beklenen davranıştır.
- Cache okuma/yazma hatası asla ekranı çökertmemeli; loglama yeterli.

---

### 0.6 ADR §13 — Development Workflow (her commit)

Her §11 maddesinin uygulanması aşağıdaki adımları izler:

```
1. Local    Mac'te kod yazılır, `flutter analyze` temiz geçmeli
2. push     git push — GitHub'a gönderilir
3. pull     İlgili node'da git pull (sudo'suz)
4. config   .env veya config değişikliği varsa düzenlenir
5. log      sudo journalctl -u teqlif -f ile canlı log izlenir
6. onay     Değişiklik mobil/staging üzerinden test edilir
7. docs     Bu döküman veya ADR güncellenir, commit numarası eklenir
8. izleme   Node hataları kısa süre gözlemlenir
9. cleanup  Geçici dosya, debug kodu temizlenir
```

Flutter-spesifik ek kurallar:
- Her değişiklik sonrası `flutter analyze` sıfır hata/uyarı vermeli.
- P0 ve P1 değişiklikleri staging'de (`dart_defines/staging.json`) test edildikten sonra prod'a taşınır.
- Cache key değişikliği veya eklenmesinde `StorageService` sabit listesi güncellenir; PR açıklamasına hangi key'lerin eklendiği/değiştirildiği yazılır.
- Mobil tarafta backend şemasına dokunulmaz; migration gerektiren durum oluşursa ADR §9 kuralı işletilir (backend koordinasyonu şart).

---

## 1. Cache Altyapısı

### 1.1 Kullanılan Paketler

| Paket | Versiyon | Kullanım |
|---|---|---|
| `hive` + `hive_flutter` | ^2.2.3 / ^1.1.0 | Kalıcı anahtar-değer cache |
| `shared_preferences` | ^2.3.0 | Mesaj/bildirim cache |
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
- **Mimari sorun:** Statik metodlar (`CacheService.getData()`, `CacheService.saveData()`) — DIP ihlali, unit testlerde mock'lanamaz. Bkz. §11.13.

#### B. Hive — `homeCache` Box (`HomeViewModel`)
- **Dosya:** `lib/screens/viewmodels/home_view_model.dart`
- Ham `resp.body` JSON string'i saklanır. **TTL sarmalayıcı kullanılmaz.**
- Tek invalidasyon mekanizması: `_kCacheVersion = 2` eşleşmesi.
- Versiyon değişmediği sürece cache **süresiz geçerli** kabul edilir.
- **Katman ihlali:** ViewModel `Hive.openBox('homeCache')` doğrudan açıyor. Bkz. §11.14.

#### C. SharedPreferences (`StorageService`)
- **Dosya:** `lib/services/storage_service.dart`
- `cacheData(key, data, ttl)` / `getCachedData(key)` — `CacheService` ile **aynı `{_d, _t, _x}` TTL sarmalayıcı mantığını** SharedPreferences üzerinde tekrarlıyor.
- Kullanım alanı: mesajlar, bildirimler, mesaj istekleri. Varsayılan 5 dakika TTL.
- **DRY ihlali:** İki bağımsız TTL implementasyonu — tek doğruluk kaynağı yok. Bkz. §11.15.

#### D. In-Memory Cache'ler

| Konum | Amaç | TTL |
|---|---|---|
| `ListingService._likeCache` (`static Map<int, bool>`) | Beğeni durumu | Yok — process ömrü |
| `CategoryService._cache` (`static Map<String, List<...>>`) | Kategori listesi | Yok — process ömrü |
| `StorageService._cachedToken` vb. | Token/avatar geçici kopy | Yok — null koruması için |
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
**ETag, Cache-Control, If-None-Match, If-Modified-Since header'larının hiçbiri okunmuyor veya gönderilmiyor.** Her API çağrısı tam yanıt alır; sunucu tarafında değişmemiş olsa bile bant genişliği harcanır. Bkz. §11.16.

### 2.3 SWR Akışı (`ApiService.get<T>`) — ve Kritik Kusuru

- **Dosya:** `lib/services/api_service.dart`
- `Stream<T>` döner, iki kez emit eder:
  1. **Anlık (sync):** Hive `api_cache` box'tan cache okunur, TTL geçerliyse hemen emit edilir.
  2. **Arka planda (async):** HTTP isteği atılır; başarılı yanıt cache'e yazılır ve emit edilir.

**Kırık SWR** — `CacheService.getData()` satır 41:
```dart
if (age > ttlMs) return null;   // TTL dolunca null → ekran boşalır
```
TTL süresi dolmuş kayıt için `null` dönülüyor. Gerçek SWR standardında (RFC 5861) bayat veri de ekranda gösterilmeli, arka planda yenileme yapılmalıdır. Şu an TTL geçince kullanıcı veriyi kaybediyor — bu **Cache-or-Network** davranışıdır, SWR değil. Düzeltme spesifikasyonu: §11.3.

---

## 3. State Management

- **Riverpod** (`flutter_riverpod ^2.4.9`) — eski `StateNotifier` ve yeni `AsyncNotifier`/`Notifier` karışımı.
- Tüm ana ekran provider'ları `autoDispose` — widget tree'den çıkıldığında state silinir.
- `autoDispose` + Hive cache → her ekran ziyaretinde disk serialize/deserialize maliyeti var. `ref.cacheFor()` ile bu maliyet sıfırlanabilir. Bkz. §11.10.

### Provider — API Çağrısı Tetiklenme Tablosu

| Provider | Mevcut Cache | Hedef (bkz. §11) |
|---|---|---|
| `homeViewModelProvider` (autoDispose) | Hive `homeCache` TTL'siz + race condition | TTL 30 dk + race fix |
| `searchViewModelProvider` (autoDispose) | Hive SWR 5-15 dk | Explore 10 dk; personalized 15 dk |
| `profileViewModelProvider` (autoDispose) | SWR profile 10 dk, listings 5 dk | Profile 15 dk, listings 10 dk |
| `publicProfileProvider` (autoDispose.family) | **YOK** — 3 HTTP istek | profile 15 dk, listings 10 dk, ratings 30 dk |
| `salesProvider` (autoDispose) | **YOK** — tam fetch | `ref.cacheFor(3 dk)` |
| `myRatingsProvider` (autoDispose) | **YOK** — 2 concurrent HTTP | Hive SWR 10 dk |
| `followListProvider` (autoDispose.family) | **YOK** — HTTP her seferinde | Hive SWR 5 dk |
| `accountInfoProvider` (autoDispose) | **YOK** + resume debounce yok | 30 sn debounce |
| `notificationSettingsProvider` (autoDispose) | **YOK** | Hive SWR 30 dk |
| `blockedUsersProvider` (autoDispose) | **YOK** | Hive SWR 10 dk |
| `mainViewModelProvider` (autoDispose) | Yok (badge sayaçları) | 30s timer — değişmez |
| `messagesTabViewModel` (autoDispose) | SharedPreferences SWR 5 dk | Değişmez |
| `storyGroupsProvider` (autoDispose) | Hive SWR 2 dk | 5 dk |
| `myStoriesProvider` (autoDispose) | Hive SWR 2 dk | 5 dk |
| `liveStreamProvider` (autoDispose) | Hive SWR 3 dk | Değişmez |

---

## 4. Pagination Bellekte Tutulma Durumu

| ViewModel | Davranış |
|---|---|
| `HomeViewModel.loadMore()` | Cursor tabanlı; önceki sayfalar bellekte korunur |
| `SearchViewModel` (giriş yapmış) | 100 öğelik buffer tek seferde çekilir; her scroll'da 12 öğelik memory windowing |
| `SearchViewModel` (misafir) | Her sayfa ayrı API çağrısıyla getirilir, belleğe eklenir |
| `SearchViewModel.loadMoreForYou()` | Her sayfa API çağrısıyla getirilir, deduplication ile belleğe eklenir |
| `SwipeFeedManager` | In-memory listing pool; video indirmeleri viewport eviction ile iptal edilir ama listing verisi bellekte kalır |

---

## 5. TTL Referans Tablosu — Mevcut ve Hedef

ADR §9 taksonomisi: **SCHEMA_VERSIONED** · **ALGORITHMIC** · **LIFECYCLE** · **SECURITY_CRITICAL** · **EPHEMERAL**

Değişen satırlar **kalın** olarak işaretlenmiştir.

| Cache Key / Endpoint | Dosya | Mevcut TTL | Hedef TTL | Depolama | ADR §9 | §11 Ref |
|---|---|---|---|---|---|---|
| `homeCache` (ana feed) | `viewmodels/home_view_model.dart` | **TTL YOK** ⚠️ | **30 dk** | Hive homeCache | ALGORITHMIC | §11.2 |
| `user_wallet_data` | `api_service.dart` + clearData çağrıları | 2 dk | **5 dk** | Hive api_cache | EPHEMERAL | §11.9 |
| `active_streams` | `live_stream_provider.dart` | 1 dk | 2 dk | Hive api_cache | EPHEMERAL | §11.9 |
| `cache_streams` | `live_stream_provider.dart` | 3 dk | 3 dk ✓ | Hive api_cache | LIFECYCLE | — |
| `feed_personalized` | `listing_service.dart:52` | 10 dk | **15 dk** | Hive api_cache | ALGORITHMIC | §11.9 |
| `cache_profile` | `profile_view_model.dart:175` | 10 dk | **15 dk** | Hive api_cache | LIFECYCLE | §11.9 |
| `cache_user_listings` | `profile_view_model.dart:218` | 5 dk | **10 dk** | Hive api_cache | LIFECYCLE | §11.9 |
| `explore_personalized_feed` | `search_view_model.dart:383` | 15 dk | 15 dk ✓ | Hive api_cache | ALGORITHMIC | — |
| `explore_for_you` | `search_view_model.dart:330` | 5 dk | **10 dk** | Hive api_cache | ALGORITHMIC | §11.9 |
| `explore_listings` | `search_view_model.dart:384` | 5 dk | **10 dk** | Hive api_cache | ALGORITHMIC | §11.9 |
| `pro_insights_*` | `analytics_service.dart:212` | 10 dk | 10 dk ✓ | Hive api_cache | ALGORITHMIC | — |
| `pro_metrics` | `analytics_service.dart:224` | 10 dk | 10 dk ✓ | Hive api_cache | ALGORITHMIC | — |
| `cache_stories` | `story_provider.dart:37` | 2 dk | **5 dk** | Hive api_cache | LIFECYCLE | §11.9 |
| `cache_my_stories` | `story_provider.dart:93` | 2 dk | **5 dk** | Hive api_cache | LIFECYCLE | §11.9 |
| `chat_${userId}` | `messages_screen.dart:1305` | 2 dk | 2 dk ✓ | Hive api_cache | EPHEMERAL | — |
| `cache_messages` | `messages_view_model.dart:153` | 5 dk | 5 dk ✓ | SharedPreferences | EPHEMERAL | — |
| `cache_notifications` | `messages_view_model.dart:276` | 5 dk | 5 dk ✓ | SharedPreferences | EPHEMERAL | — |
| `cache_message_requests` | `messages_view_model.dart:343` | 5 dk | 5 dk ✓ | SharedPreferences | EPHEMERAL | — |
| `CategoryService._cache` | `services/category_service.dart` | **TTL YOK** | Foregrounding refresh | In-memory | SCHEMA_VERSIONED | §11.11 |
| `_kCacheVersion = 2` | `home_view_model.dart` | Hardcoded | 30 dk TTL + korunur | Hive box | SCHEMA_VERSIONED | §11.2 |
| **`public_profile_${userId}`** | `public_profile_view_model.dart` | **YOK** | **15 dk** | Hive api_cache | LIFECYCLE | §11.5 |
| **`public_listings_${userId}`** | `public_profile_view_model.dart` | **YOK** | **10 dk** | Hive api_cache | LIFECYCLE | §11.5 |
| **`public_ratings_${userId}`** | `public_profile_view_model.dart` | **YOK** | **30 dk** | Hive api_cache | LIFECYCLE | §11.5 |
| **`sales_data`** | `sales_screen.dart` (veya viewmodel) | **YOK** | **3 dk** | ref.cacheFor | LIFECYCLE | §11.6 |
| **`my_ratings_received`** | `my_ratings_view_model.dart` | **YOK** | **10 dk** | Hive api_cache | LIFECYCLE | §11.7 |
| **`my_ratings_given`** | `my_ratings_view_model.dart` | **YOK** | **10 dk** | Hive api_cache | LIFECYCLE | §11.7 |
| **`follow_list_${userId}_followers`** | `follow_list_view_model.dart` | **YOK** | **5 dk** | Hive api_cache | LIFECYCLE | §11.8 |
| **`follow_list_${userId}_following`** | `follow_list_view_model.dart` | **YOK** | **5 dk** | Hive api_cache | LIFECYCLE | §11.8 |
| **`notification_settings`** | `notification_settings_view_model.dart` | **YOK** | **30 dk** | Hive api_cache | LIFECYCLE | §11.8 |
| **`blocked_users`** | `blocked_users_view_model.dart` | **YOK** | **10 dk** | Hive api_cache | LIFECYCLE | §11.8 |
| Kayıt URL (presigned) | `recordings_cache_service.dart:10` | 55 dk | 55 dk ✓ | Hive api_cache | SECURITY_CRITICAL | — |
| Kayıt özeti | `recordings_cache_service.dart:11` | 10 dk | 10 dk ✓ | Hive api_cache | LIFECYCLE | — |
| Resimler (`TeqlifCacheManager`) | `image_cache_manager.dart:15` | 2 gün, 300 dosya | 2 gün ✓ | Disk | EPHEMERAL | — |
| Resimler (`DefaultCacheManager`) | — | 7 gün, 200 dosya | 7 gün ✓ | Disk | EPHEMERAL | — |

### Cache Temizleme Mekanizmaları
- `CacheService.clearExpired()`: Startup'ta Hive `api_cache` süresi dolmuş kayıtları siler.
- `TeqlifCacheManager` / `DefaultCacheManager`: `flutter_cache_manager` kendi TTL'ini yönetir.
- `StorageService.clear()`: Logout'ta hem SecureStorage hem SharedPreferences hem `homeCache` hem `api_cache` box'larını siler.

---

## 6. Endüstri Standardı Karşılaştırması

### 6.1 Benchmark — Sosyal Ticaret Uygulamaları

| Platform | Feed | Profil | Canlı | Mesajlar | Finansal |
|---|---|---|---|---|---|
| **Instagram** | 30 dk SWR | 15 dk | 30-60 sn | Push-driven | — |
| **TikTok** | 1-2 saat SWR | 30 dk | 30 sn | Push-driven | — |
| **Pinterest** | 20-30 dk SWR | 1 saat | — | — | — |
| **Shopify Mobile** | 30 dk | 15 dk | — | — | 1-5 dk |
| **Teqlif (mevcut)** | TTL'siz ⚠️ | 10 dk | 3 dk | 5 dk | 2 dk |
| **Teqlif (hedef)** | 30 dk SWR | 15 dk | 3 dk | 5 dk | 5 dk |

### 6.2 SWR — Kırık Olmadan Ne Kadar Değer Yaratır

Aynı TTL değeriyle bile kırık SWR vs. düzgün SWR arasındaki fark çarpıcıdır:

```
TTL = 5 dk, kırık SWR (şu an):
  t=0:00  Kullanıcı ekrana girer → cache hit → anlık
  t=5:01  Kullanıcı ekrana geri döner → null → yüklenme → API bekleme

TTL = 5 dk, düzgün SWR (hedef):
  t=0:00  Kullanıcı ekrana girer → cache hit → anlık
  t=5:01  Kullanıcı ekrana geri döner → bayat veri gösterilir → arka planda yenileme
  t=5:02  Yeni veri gelir, sessiz güncelleme

TTL = 30 dk, düzgün SWR (hedef):
  t=0:00  Kullanıcı ekrana girer → cache hit → anlık
  t=30:01 Kullanıcı ekrana geri döner → bayat veri gösterilir → arka planda yenileme
  Kullanıcı boş ekran görme oranı: neredeyse sıfır
```

**Düzgün SWR + uzun TTL = sunucuya daha az istek + daha iyi UX. Kırık SWR + kısa TTL = her ikisinden de mahrum.**

### 6.3 Veri Değişkenlik Sınıflaması — Sosyal Ticaret Bağlamı

| Veri Tipi | Değişim Sıklığı | Endüstri TTL Aralığı | Teqlif Hedef |
|---|---|---|---|
| Canlı yayın listesi | Dakikalar | 30-120 sn | 3 dk |
| Story listesi | Dakikalar | 5-10 dk | 5 dk |
| Mesajlar | Anlık (push ile) | Cache sadece ilk render | 5 dk |
| Bildirimler | Anlık (push ile) | Cache sadece ilk render | 5 dk |
| Cüzdan bakiyesi | İşlem bazlı | 1-5 dk (optimistic update ile) | 5 dk |
| Ana feed | Saatler | 20-60 dk SWR | 30 dk |
| Kişisel feed | Saatler | 15-30 dk | 15 dk |
| Keşfet feed | Saatler | 15-30 dk | 15 dk |
| Kendi profil | Saatler | 10-20 dk | 15 dk |
| Satıcı/public profil | Günler | 10-30 dk | 15 dk |
| Kendi ilanları | Saatler | 5-15 dk | 10 dk |
| Satıcı ilanları | Günler | 10-20 dk | 10 dk |
| Satış/satın alma | İşlem bazlı | 2-5 dk | 3 dk |
| Puanlar | Günler-haftalar | 20-60 dk | 30 dk |
| Kategori listesi | Haftalar | process ömrü + foregrounding refresh | Foregrounding |
| Bildirim ayarları | Nadiren | 15-60 dk | 30 dk |
| Engellenen kullanıcılar | Nadiren | 10-30 dk | 10 dk |

---

## 7. Cloudflare Edge Cache Analizi

### 7.1 Mevcut Cloudflare Topolojisi

```
teqlif.com/staging  → Proxied (Cloudflare)  ← API istekleri buradan geçiyor
uploads.*           → DNS Only              ← Cloudflare bypass
live.*              → DNS Only              ← Cloudflare bypass
minio.*             → DNS Only              ← Cloudflare bypass
```

### 7.2 Cloudflare API Yanıtlarını Cache'lemiyor

Authenticated endpoint'lerde Cloudflare cache çalışmıyor. Nedenleri:

1. **Authorization header:** `Bearer` token içeren istekler Cloudflare'ın varsayılan davranışıyla cache'lenmez (`Vary: Authorization` kuralı).
2. **Cache-Control:** Backend büyük olasılıkla `Cache-Control: no-cache` veya `private` döndürüyor — Cloudflare bunu görünce cache'lemiyor.
3. **ETag yokluğu:** Client If-None-Match göndermediği için 304 cevabından yararlanılamıyor.

### 7.3 Cloudflare Ne Zaman Yardım Ediyor

| İstek Tipi | Cloudflare Etkisi |
|---|---|
| API (`/api/*`, authenticated) | **Sıfır** — her istek backend'e ulaşıyor |
| Static assets (JS, CSS, resimler) | **Aktif** — CDN cache devrede |
| Resim upload'ları (MinIO/uploads) | **Yok** — DNS Only, Cloudflare bypass |

### 7.4 Sonuç

Cloudflare şu an API yükünü azaltmıyor. Client-side cache'in düzgün çalışması, sunucu yükünü azaltmanın tek gerçek mekanizmasıdır. ETag desteği eklenmesi (§11.16) uzun vadede bant genişliği tasarrufu sağlar ama Cloudflare cache açmaz.

---

## 8. Risk Değerlendirmesi

| Sorun | Alan | Risk | Gerekçe |
|---|---|---|---|
| Race condition: `_loadFromCache()` await edilmemiş | `HomeViewModel.build()` | **KRİTİK** | Ağ hızlıysa API yanıtı sonrası eski cache state'i ezebilir |
| `homeCache` TTL yok | `HomeViewModel` | **KRİTİK** | Uygulama restart'ları arasında günlerce eski içerik gösterilebilir |
| Kırık SWR: TTL dolunca `null` dönülüyor | `CacheService.getData()` | **YÜKSEK** | Cache expire = ekran boşalır; tüm cache yatırımının geri dönüşünü düşürüyor |
| `PublicProfileViewModel` cache yok | Profil ekranı | **YÜKSEK** | Sosyal ticarette en sık yapılan işlem: her satıcı ziyaretinde 3 HTTP isteği |
| `SalesViewModel` cache yok | Satışlar sekmesi | **ORTA** | Her tab geçişinde full fetch |
| `MyRatingsViewModel` cache yok | Puanlarım ekranı | **ORTA** | Her açılışta 2 concurrent HTTP GET |
| `FollowListViewModel` cache yok | Takipçi/Takip listesi | **ORTA** | Her açılışta HTTP GET |
| Bildirim ayarları / engellenenler cache yok | Ayarlar ekranları | **DÜŞÜK-ORTA** | Nadiren değişen veri için gereksiz istek |
| 83/95 `CachedNetworkImage` özel manager yok | Resim cache | **ORTA** | Tutarsız TTL ve dosya limitleri |
| `AccountInfo` resume debounce yok | Hesap bilgisi ekranı | **ORTA** | Her app resume'da `GET /auth/me` tetikleniyor |
| `CategoryService` SCHEMA_VERSIONED ama invalidasyon yok | In-memory | **ORTA** | Admin panel kategori değişikliği app restart'a kadar yansımaz |
| `story.dart`'ta `isViewed` alanı yok | Story tray | **ORTA** | İzlenen story ile izlenmeyenin görsel ayrımı yapılamıyor |
| ETag / conditional request yok | Tüm API katmanı | **DÜŞÜK** | Değişmemiş içerik için tam bandwidth harcanıyor |
| İki paralel TTL-cache sistemi (DRY ihlali) | Hive + SharedPreferences | **DÜŞÜK** | Aynı `{_d, _t, _x}` mantığı iki yerde; bakım yükü |

---

## 9. Mimari Sorunlar

### 9.1 Katman İhlali — ViewModel Storage Biliyor (Clean Architecture)

`HomeViewModel` doğrudan `Hive.openBox('homeCache')` çağırıyor. Clean Architecture'da cache bir **Data Layer** detayıdır; Presentation katmanındaki ViewModel verinin nereden geldiğini bilmemeli.

```dart
// Mevcut — HomeViewModel (Presentation) → Hive (Data), katman atlıyor
final cacheBox = await Hive.openBox('homeCache');

// Hedef
HomeViewModel → ListingRepository.getHomeFeed() → (Hive | API)
```

### 9.2 Kırık SWR Standardı

`CacheService.getData()` TTL süresi dolmuşsa `null` döner. Ekran açıldığında cache expire olmuşsa kullanıcı yüklenme göster → API cevabını bekler.

RFC 5861 standardı: bayat veri de UI'a verilmeli (`stale-while-revalidate`), arka planda sessizce yenilenmeli.

### 9.3 Race Condition — `HomeViewModel.build()`

```dart
// home_view_model.dart satır 76-78
_loadFromCache();       // AWAIT EDİLMEMİŞ — fire-and-forget
await _fetchInitial();  // ağ hızlıysa önce bu biter, sonra cache eski veriyle ezebilir
```

### 9.4 DIP İhlali — `CacheService` Static

`CacheService.getData()` / `CacheService.saveData()` statik metodlar. Riverpod provider olarak enjekte edilemiyor, unit testlerde mock'lanamıyor.

### 9.5 DRY İhlali — İki TTL Sistemi

`{_d, _t, _x}` TTL sarmalayıcı mantığı hem `CacheService` (Hive) hem `StorageService` (SharedPreferences) içinde ayrı implementasyonlarda bulunuyor.

---

## 10. Story Cache Detay Analizi

### 10.1 Cache Durumu

| Provider | Cache Key | Mevcut TTL | Hedef TTL | Tetiklenme |
|---|---|---|---|---|
| `storyGroupsProvider` (autoDispose) | `cache_stories` | 2 dk | **5 dk** | Her `build()` → SWR; `refresh()` → `bypassCache: true` |
| `myStoriesProvider` (autoDispose) | `cache_my_stories` | 2 dk | **5 dk** | Her `build()` → SWR |

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

`recordStoryView(storyId)` sadece backend'e POST atar (`/stories/{id}/view`); local state'de hiçbir iz bırakmaz. Kullanıcı bir story izleyip geri döndüğünde client izlendi-izlenmedi ayrımını bilmiyor; story tray'de görsel fark (gri halka) yok.

### 10.3 autoDispose Etkisi

Her iki provider `AutoDisposeAsyncNotifier`. Story ekranından çıkılınca provider dispose olur:
- TTL dolmamışsa → anlık cache, arka plan yenileme (iyi)
- TTL dolmuşsa → yüklenme göstergesi, API bekleme (kırık SWR ile)

---

## 11. İyileştirme Spesifikasyonu

Tüm değişiklikler yalnızca `mobile/lib/` kapsamında; backend şemasına, API'ye, routing'e dokunmuyor.

---

### P0 — Hemen (Hatalı Davranış)

---

#### §11.1 Race Condition Düzelt — `HomeViewModel.build()`

**Dosya:** `mobile/lib/screens/viewmodels/home_view_model.dart`

```dart
// ÖNCE (satır ~76-78)
_loadFromCache();       // fire-and-forget
await _fetchInitial();

// SONRA
await _loadFromCache(); // await ile sıra garantilendi
await _fetchInitial();
```

`_loadFromCache()` state'i cache'ten doldurur, `_fetchInitial()` API'den taze veriyle günceller. Sıra korunduğunda taze veri her zaman kazanır.

---

#### §11.2 `homeCache` TTL Ekle

**Dosya:** `mobile/lib/screens/viewmodels/home_view_model.dart`

`homeCache` box'a kayıt yazılırken `_kCacheTimestampKey` adında ek bir anahtar saklanmalı; okunurken yaş hesaplanmalı.

```dart
// Sabitler bloğuna ekle
static const _kCacheKeyTimestamp = 'feed_saved_at';
static const _kCacheTtlMs = 30 * 60 * 1000; // 30 dakika

// _fetchInitial() içinde cacheBox.put çağrılarının yanına ekle
await cacheBox.put(_kCacheKeyTimestamp, DateTime.now().millisecondsSinceEpoch);

// _loadFromCache() içinde version kontrolünden sonra, feed okumasından önce
final savedAt = cacheBox.get(_kCacheKeyTimestamp) as int?;
if (savedAt != null) {
  final age = DateTime.now().millisecondsSinceEpoch - savedAt;
  if (age > _kCacheTtlMs) {
    // Süresi dolmuş — cache'i temizle, API'yi bekle
    await cacheBox.clear();
    return;
  }
}
```

`_kCacheVersion` hardcoded versiyonu ek güvence olarak **korunur**; TTL ona ek bir katman oluşturur.

---

### P1 — Güvenilirlik / Gereksiz İstek Azaltma

---

#### §11.3 Gerçek SWR Uygula — `CacheService` + `ApiService`

**Dosya 1:** `mobile/lib/services/cache_service.dart`

Mevcut `getData()` metodunu değiştirme; `getWithStaleness()` adında yeni metod ekle:

```dart
/// Kayıt varsa veri ve bayatlık bilgisini birlikte döner.
/// TTL dolmuşsa data hâlâ dönülür, isStale: true işareti taşır.
/// Kayıt hiç yoksa null döner.
static ({dynamic data, bool isStale})? getWithStaleness(String key) {
  final box = _box;
  if (box == null) return null;
  final raw = box.get(key);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    if (!decoded.containsKey('_t') || !decoded.containsKey('_d')) return null;
    final savedAt = (decoded['_t'] as num).toInt();
    final ttlMs = (decoded['_x'] as num? ?? 300000).toInt();
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    return (data: decoded['_d'], isStale: age > ttlMs);
  } catch (_) {
    return null;
  }
}
```

**Dosya 2:** `mobile/lib/services/api_service.dart`

`get<T>()` metodunda `CacheService.getData()` çağrısını `getWithStaleness()` ile değiştir:

```dart
// ÖNCE
final cached = CacheService.getData(cacheKey);
if (cached != null) {
  yield fromJson(cached);
}
// ... HTTP call her durumda devam ediyor

// SONRA
if (!bypassCache) {
  final cached = CacheService.getWithStaleness(cacheKey);
  if (cached != null) {
    yield fromJson(cached.data);          // bayat olsa da hemen göster
    if (!cached.isStale) return;          // taze ise HTTP çağrısına gerek yok
    // isStale: true → aşağıdaki HTTP çağrısına devam et
  }
}
// ... HTTP call (cache miss veya stale durumda)
yield fromJson(data);
await CacheService.saveData(cacheKey, data, ttl: cacheTtl);
```

**Etki:** TTL dolmuş her endpoint artık boş ekran yerine anlık bayat veri gösterir; arka planda sessiz güncelleme yapar. Diğer `getData()` çağrıları (homeCache dışı doğrudan erişimler) etkilenmez.

---

#### §11.4 `StorageService.getCachedData()` — Aynı SWR Mantığı

**Dosya:** `mobile/lib/services/storage_service.dart`

`getCachedData()` SharedPreferences versiyonu da aynı `null` dönme sorununu taşıyor. `getWithStaleness()` benzeri eklenebilir ama mesajlar/bildirimler push-driven olduğundan öncelik düşük. `messages_view_model.dart` SWR akışına taşınmadığı sürece bu değişiklik ertelenebilir.

**Karar:** P1 kapsamı dışında bırak; WS push zaten mesajları güncel tutuyor.

---

#### §11.5 Public Profil Cache Ekle

**Dosya:** `mobile/lib/screens/viewmodels/public_profile_view_model.dart`

Mevcut durum: üç ayrı `http.get()` çağrısı, cache yok.

```dart
// Profil verisi — 15 dk
_profileSub = ref.read(apiServiceProvider).get<Map<String, dynamic>>(
  url: '${baseUrl}/users/${arg.userId}',
  cacheKey: 'public_profile_${arg.userId}',
  cacheTtl: const Duration(minutes: 15),
  fromJson: (raw) => raw as Map<String, dynamic>,
).listen((data) {
  if (!_disposed) state = state.copyWith(profile: PublicProfile.fromJson(data));
});

// İlanlar — 10 dk
_listingsSub = ref.read(apiServiceProvider).get<List<dynamic>>(
  url: '${baseUrl}/users/${arg.userId}/listings',
  cacheKey: 'public_listings_${arg.userId}',
  cacheTtl: const Duration(minutes: 10),
  fromJson: (raw) => raw as List<dynamic>,
).listen((data) {
  if (!_disposed) state = state.copyWith(listings: data.map(Listing.fromJson).toList());
});

// Puanlar — 30 dk (çok nadiren değişir)
_ratingsSub = ref.read(apiServiceProvider).get<Map<String, dynamic>>(
  url: '${baseUrl}/ratings/${arg.userId}',
  cacheKey: 'public_ratings_${arg.userId}',
  cacheTtl: const Duration(minutes: 30),
  fromJson: (raw) => raw as Map<String, dynamic>,
).listen((data) {
  if (!_disposed) state = state.copyWith(ratings: RatingsSummary.fromJson(data));
});
```

`onDispose`'ta üç subscription iptal edilmeli:
```dart
ref.onDispose(() {
  _disposed = true;
  _profileSub?.cancel();
  _listingsSub?.cancel();
  _ratingsSub?.cancel();
});
```

**Etki:** Popüler satıcı sayfası artık 3 HTTP isteği yerine 0 istek (cache geçerliyse), 3 istek (ilk ziyaret veya TTL dolmuşsa arka planda).

---

#### §11.6 Sales Cache Ekle

**Dosya:** `mobile/lib/screens/sales_screen.dart` (veya ayrı ViewModel varsa)

Mevcut: `build()` her çağrıldığında full fetch.

```dart
@override
FutureOr<SalesState> build() {
  ref.cacheFor(const Duration(minutes: 3)); // Hive'a gitme; in-memory tut
  return _fetchSales();
}
```

Pull-to-refresh: mevcut `invalidate()` / `refresh()` mekanizması olduğu gibi çalışır — `ref.cacheFor()` sadece otomatik dispose'u geciktirir.

---

#### §11.7 MyRatings Cache Ekle

**Dosya:** `mobile/lib/screens/viewmodels/my_ratings_view_model.dart`

Mevcut: iki concurrent `http.get()`, cache yok.

```dart
// received — 10 dk
_receivedSub = ref.read(apiServiceProvider).get<List<dynamic>>(
  url: '${baseUrl}/ratings/me/received',
  cacheKey: 'my_ratings_received',
  cacheTtl: const Duration(minutes: 10),
  fromJson: (raw) => raw as List<dynamic>,
).listen((data) { ... });

// given — 10 dk
_givenSub = ref.read(apiServiceProvider).get<List<dynamic>>(
  url: '${baseUrl}/ratings/me/given',
  cacheKey: 'my_ratings_given',
  cacheTtl: const Duration(minutes: 10),
  fromJson: (raw) => raw as List<dynamic>,
).listen((data) { ... });
```

---

#### §11.8 Düşük Öncelikli Cache Eklemeleri

Aşağıdaki endpoint'ler nadiren ziyaret edilen ekranlara aittir. Hepsi için `ApiService.get()` SWR entegrasyonu aynı pattern ile yapılır.

| Dosya | Cache Key | TTL |
|---|---|---|
| `follow_list_view_model.dart` | `follow_list_${userId}_followers` | 5 dk |
| `follow_list_view_model.dart` | `follow_list_${userId}_following` | 5 dk |
| `notification_settings_view_model.dart` | `notification_settings` | 30 dk |
| `blocked_users_view_model.dart` | `blocked_users` | 10 dk |

---

### P2 — TTL Değerleri Güncelle

SWR düzeltmesi (§11.3) uygulandıktan sonra yapılmalıdır; aksi halde uzun TTL + kırık SWR = uzun süreli boş ekran.

#### §11.9 TTL Güncellemeleri

| Dosya | Mevcut | Hedef | Satır |
|---|---|---|---|
| `story_provider.dart` | `Duration(minutes: 2)` | `Duration(minutes: 5)` | 37, 52, 93, 108 (4 yer) |
| `listing_service.dart` | `Duration(minutes: 10)` | `Duration(minutes: 15)` | 52 |
| `profile_view_model.dart` | `Duration(minutes: 10)` | `Duration(minutes: 15)` | 175 |
| `profile_view_model.dart` | `Duration(minutes: 5)` | `Duration(minutes: 10)` | 218 |
| `search_view_model.dart` | `Duration(minutes: 5)` → explore_for_you | `Duration(minutes: 10)` | 330 |
| `search_view_model.dart` | `Duration(minutes: 5)` → explore_listings | `Duration(minutes: 10)` | 384 |
| `api_service.dart` varsayılan TTL | `Duration(minutes: 5)` | **Değiştirme** — bazı yerler 5 dk'yı bilinçli kullanıyor |

`user_wallet_data` için: TTL'yi 5 dk'ya çıkarmak düşük risk çünkü `CacheService.clearData('user_wallet_data')` çağrısı zaten işlem anında invalidasyon yapıyor. Etkili yerler: `listing_detail_screen.dart:793`, `listing_detail_screen.dart:892`, `live/host_stream_screen.dart:284`, `live/swipe_live_screen.dart:1798`, `ai_desc_provider.dart:64`. Hepsi clearData sonrası yeni veri çekiyor — TTL değişikliği güvenli.

---

#### §11.10 `ref.cacheFor()` — Sık Ziyaret Edilen Ekranlar

`autoDispose` + Hive kombinasyonu her tab geçişinde disk serialize/deserialize maliyeti yaratıyor. Aşağıdaki provider'lar için in-memory retention yeterli; Hive'a gitmesi gerekmiyor.

```dart
// storyGroupsProvider — StoryGroupsNotifier.build() içine ekle
ref.cacheFor(const Duration(minutes: 5));

// myStoriesProvider — MyStoriesNotifier.build() içine ekle
ref.cacheFor(const Duration(minutes: 5));

// liveStreamProvider — LiveStreamNotifier.build() içine ekle
ref.cacheFor(const Duration(minutes: 3));
```

Hive SWR ile `ref.cacheFor()` birlikte çalışır — Hive ilk yükleme için (app restart sonrası); `ref.cacheFor()` aynı oturum içindeki tekrar ziyaretler için.

---

#### §11.11 `CategoryService` Foregrounding Refresh

**Dosya:** `mobile/lib/services/category_service.dart`

Mevcut: process ömrü boyunca in-memory, invalidasyon yok.

```dart
// CategoryService'e son yenileme zamanı ekle
static DateTime? _lastFetch;
static const _refreshInterval = Duration(minutes: 30);

static Future<List<Category>> getCategories(ApiClient api) async {
  final now = DateTime.now();
  if (_cache != null && _lastFetch != null &&
      now.difference(_lastFetch!) < _refreshInterval) {
    return _cache!;
  }
  // API call...
  _cache = result;
  _lastFetch = now;
  return result;
}
```

`AppLifecycleState.resumed` dinleyicisine: `CategoryService.invalidate()` çağrısı ekle (sadece `_lastFetch = null` ataması).

---

#### §11.12 `AccountInfo` Resume Debounce

**Dosya:** `mobile/lib/screens/viewmodels/account_info_view_model.dart` (veya `accountInfoProvider`'ın bulunduğu dosya)

```dart
DateTime? _lastResume;
static const _resumeDebounce = Duration(seconds: 30);

void onAppResumed() {
  final now = DateTime.now();
  if (_lastResume != null && now.difference(_lastResume!) < _resumeDebounce) return;
  _lastResume = now;
  _fetchAccountInfo();
}
```

---

### P3 — Uzun Vadeli / Mimari

---

#### §11.13 `CacheService` DIP

Statik metodları Riverpod `Provider<CacheService>` ile enjekte et. `CacheService._()` private constructor kaldırılır; singleton yerine Riverpod tarafından yönetilen instance kullanılır.

```dart
final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());
```

Mevcut statik çağrılar: `ref.read(cacheServiceProvider).getData(...)` haline gelir. Unit testlerde `ProviderContainer` ile mock `CacheService` enjekte edilebilir.

---

#### §11.14 Repository Katmanı — `homeCache`

`homeCache` Hive erişimi `ListingRepository` / `HomeRepository`'ye taşınır. `HomeViewModel` yalnızca `repository.getHomeFeed()` akışını dinler; `Hive.openBox` çağrısı Presentation katmanından çıkar.

---

#### §11.15 DRY — SharedPreferences TTL Kaldır

`StorageService.cacheData()` / `getCachedData()` metodları kaldırılır; yerine `CacheService` (Hive) kullanılır. Mesajlar, bildirimler, mesaj istekleri de Hive `api_cache` box'a taşınır. Tek `{_d, _t, _x}` implementasyonu kalır.

---

#### §11.16 ETag / Conditional Request (Bant Genişliği)

**Dosya:** `mobile/lib/core/network/api_client.dart`

```dart
// GET isteğine If-None-Match header ekle
final etag = await CacheService.getEtag(cacheKey);
if (etag != null) headers['If-None-Match'] = etag;

// Yanıtta ETag varsa sakla
final responseEtag = response.headers['etag'];
if (responseEtag != null) await CacheService.saveEtag(cacheKey, responseEtag);

// HTTP 304 → mevcut cache'i döndür
if (response.statusCode == 304) {
  return CacheService.getData(cacheKey);
}
```

Etkin olması için backend'in GET endpoint'lerinde `ETag` header dönmesi gerekir. Client-backend koordinasyonu gerektirdiğinden P3.

---

### Özet — Uygulama Sırası

```
P0  §11.1  race condition          home_view_model.dart          ✅ f371c67b
P0  §11.2  homeCache TTL           home_view_model.dart          ✅ f371c67b

P1  §11.3  SWR düzelt              cache_service.dart            ✅ f371c67b
           SWR düzelt              api_service.dart              ✅ f371c67b
P1  §11.5  public profil cache     public_profile_view_model.dart ✅ f371c67b
P1  §11.6  sales cache             sales_view_model.dart          ✅ f371c67b
P1  §11.7  ratings cache           my_ratings_view_model.dart     ✅ f371c67b
P1  §11.8  düşük öncelikli cache   4 dosya                        ✅ f371c67b

P2  §11.9  TTL güncellemeleri      6 dosya                        ✅ f371c67b
P2  §11.10 ref.keepAlive+Timer     story + live stream provider   ✅ f371c67b
P2  §11.11 CategoryService refresh main_screen.dart               ✅ f371c67b
P2  §11.12 resume debounce         account_info_screen.dart       ✅ f371c67b

P3  §11.13 CacheService DIP        20 dosya                           ✅ 2a5dc9cd
P3  §11.14 Repository pattern      home_repository.dart (yeni)         ✅ ccbcf109
P3  §11.15 DRY                     storage_service + messages VM       ✅ ccbcf109
P3  §11.16 ETag                    etag_middleware.py + cache_service + api_service  ✅ 20ab93a5
```
