# Mobile Cache Sistem Analizi — V1.1 Bulgular & Uygulama Spesifikasyonu

**Tarih:** 2026-10-14
**Kapsam:** ADR, Clean Architecture, MVVM, OTA/ARB, Redis, PostgreSQL, backend servisleri ve V2.1 sistem mimarisine göre tam re-analiz
**Revizyon:** V1.1 — Mimari re-analiz tamamlandı, 13 bulgu, uygulama bekliyor

---

## 0. Uyum Gereksinimleri

V1.0 §0 kurallarının tamamı bu döküman için geçerlidir. Her uygulama adımında V1.0 §0 okunur.

Kısaca:
- ADR §13 workflow her commit için zorunlu
- ADR §8 MVVM katman sınırları ihlal edilemez
- ADR §9 cache taksonomisi her yeni anahtarda kontrol edilir
- `flutter analyze` sıfır hata/uyarı
- P0 ve P1 önce staging'de test edilir

---

## 1. ADR §9 — Tüm Cache Anahtarlarının Taksonomi Tablosu

Her cache anahtarı için ADR §9'daki beş taksonomiden biri atanmalıdır. Bu tablo V1.1 analizi sırasında oluşturulmuştur; eksik veya yanlış sınıflandırılan anahtarlar §12'deki bulgularla ilişkilendirilir.

| Cache Key | Taksonomi | Client TTL | Backend Redis TTL | Invalidasyon Tetikleyici | Durum |
|-----------|-----------|-----------|------------------|--------------------------|-------|
| `i18n_cache` (Hive) | SCHEMA_VERSIONED | 24h | 1h (`/api/i18n`) | `sync_translations.py` + `bump_schema_version()` | ✅ doğru |
| `field_config_*` (Hive) | SCHEMA_VERSIONED | in-memory | 24h | admin deploy | ✅ doğru |
| `catalog` / `cities` | SCHEMA_VERSIONED | — (backend) | 24h + schema_v | migration + `bump_schema_version()` | ✅ doğru |
| `home_feed_recent` (Hive box) | ALGORITHMIC | 30 min | **15 min** (Redis setex) | — (TTL) | ⚠️ TTL uyumsuz §12.10 |
| `explore_for_you` / `feed_personalized` | ALGORITHMIC | 10 min | 15 min (Redis setex) | — (TTL) | ✅ kabul edilebilir |
| `explore_personalized_feed` | ALGORITHMIC | 10 min | 15 min | — (TTL) | ✅ kabul edilebilir |
| `cache_streams` | **LIFECYCLE** | 3 min | — | ❌ stream sonu event temizlemiyor | 🔴 §12.9 |
| `cache_auctions` | **LIFECYCLE** | — | — | ❌ kullanılmıyor (dead code) | 🔴 §12.11 |
| `cache_stories` | LIFECYCLE | 5 min | — | story.expires_at → TTL ile örtüşüyor | ⚠️ kabul |
| `cache_profile` | LIFECYCLE | 15 min | — | ❌ profil güncellemede temizlenmiyor | ⚠️ kabul |
| `public_profile_*` | LIFECYCLE | 15 min | — | ❌ takip/engel event'inde temizlenmiyor | ⚠️ kabul |
| `public_listings_*` | LIFECYCLE | 10 min | — | — (TTL) | ✅ kabul |
| `public_ratings_*` | LIFECYCLE | 30 min | — | — (TTL) | ✅ kabul |
| `cache_messages` | EPHEMERAL | 5 min (**implicit**) | — | WS gerçek zamanlı | 🟡 §12.2 |
| `cache_notifications` | EPHEMERAL | 5 min (**implicit**) | — | push notification | 🟡 §12.2 |
| `cache_message_requests` | EPHEMERAL | 5 min (**implicit**) | — | WS event | 🟡 §12.2 |
| `cache_sales` | LIFECYCLE | 3 min | — | `clearData` satış tamamlandığında ✅ | ✅ doğru |
| `cache_my_ratings_*` | LIFECYCLE | 10 min | — | `clearData` manuel refresh ✅ | ✅ doğru |
| `cache_blocked_users` | LIFECYCLE | 10 min | — | `clearData` blokta ✅ | ✅ doğru |
| `cache_notification_settings` | SCHEMA_VERSIONED | 30 min | — | `clearData` ayar değişince ✅ | ✅ doğru |
| `cache_feed` | ALGORITHMIC | — | — | ❓ nerede kullanıldığı belirsiz | 🟡 gözlem |
| `user_wallet_data` | LIFECYCLE | default 5 min | — | `clearData` ödeme sonrası ✅ | ✅ doğru |
| `follow_list_*` | LIFECYCLE | 5 min | — | — (TTL) | ✅ kabul |

> **Kural (ADR §9):** LIFECYCLE anahtarlar için TTL yeterli değildir — olayın sonunda `clearData()` da çağrılmalıdır. TTL yalnızca event gözden kaçırıldığında ağ yeniden senkronizasyonunu garanti eder.

---

## 2. Özet Tablo

| § | Başlık | Öncelik | Etkilenen Sistem | Durum |
|---|--------|---------|-----------------|-------|
| §12.1 | `flutter_cache_manager` sürüm sabitleme | **P0** | Mobil | ⬜ bekliyor |
| §12.2 | messages/notifications açık TTL | **P1** | Mobil | ⬜ bekliyor |
| §12.3 | TeqlifCacheManager tüm CachedNetworkImage'lara yay | **P1** | Mobil | ⬜ bekliyor |
| §12.4 | memCacheWidth/Height feed kartlarına ekle | **P1** | Mobil | ⬜ bekliyor |
| §12.9 | LIFECYCLE cache → WS event invalidasyonu | **P1** | Mobil + WS | ⬜ bekliyor |
| §12.10 | Backend ↔ mobil TTL uyumsuzluğu (home feed) | **P1** | Mobil + Backend | ⬜ bekliyor |
| §12.11 | `home_view_model` / `search_view_model` — direct http.get (ADR §8 ihlali) | **P1** | Mobil MVVM | ⬜ bekliyor |
| §12.5 | Feed loadMore() sayfaları diske yaz | **P2** | Mobil | ⬜ bekliyor |
| §12.6 | api_cache box maksimum anahtar limiti | **P2** | Mobil | ⬜ bekliyor |
| §12.12 | cacheKey parametresi — presigned URL bağımlılığı | **P2** | Mobil | ⬜ bekliyor |
| §12.13 | Backend `Cache-Control` header eksikliği | **P2** | Backend + Cloudflare | ⬜ bekliyor |
| §12.7 | PublicProfile prefetch | **P3** | Mobil | ⬜ bekliyor |
| §12.8 | Entity normalization store | **P3** | Mobil | ⬜ bekliyor |

---

## 3. Bulgular

### §12.1 `flutter_cache_manager: any` — Sürüm Sabitleme

**Öncelik:** P0
**Etkilenen sistem:** Mobil → `mobile/pubspec.yaml:66`

`any` kısıtı, `flutter pub upgrade` veya CI ortamında farklı sürüm çözümü alınmasını sağlar. Bir sonraki breaking change'de sessizce bozulabilir. `cached_network_image: ^3.3.1` zaten bağımlı olduğundan `any` gereksiz.

**Çözüm:**
```yaml
flutter_cache_manager: ">=3.3.1 <4.0.0"
```
Mevcut prod sürümünü `flutter pub deps | grep flutter_cache_manager` ile doğrula, ardından sabitle.

**Test:** `flutter pub upgrade --dry-run` version conflict yok, `flutter analyze` temiz.

---

### §12.2 messages / notifications / message_requests — Açık TTL Eksikliği

**Öncelik:** P1
**Etkilenen sistem:** Mobil → `messages_view_model.dart:155,280,349`

Üç EPHEMERAL anahtar `saveData` çağrısında `ttl` parametresi geçmiyor. Şu an varsayılan 5 dakika kullanılıyor — bu değer doğru, ancak gelecekte `CacheService` varsayılanı değişirse sessizce kırılır. ADR §9 taksonomisi gereği TTL her zaman açık olmalıdır.

**Çözüm:**
```dart
await _cache.saveData(
  StorageService.cacheMessages, data,
  ttl: const Duration(minutes: 5), // EPHEMERAL: WS gerçek zamanlı günceller
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

---

### §12.3 TeqlifCacheManager — Tüm CachedNetworkImage Kapsamı

**Öncelik:** P1
**Etkilenen sistem:** Mobil → 60 CachedNetworkImage widget, 13'ü mevcut

47 widget `DefaultCacheManager` (7 gün TTL, 200 dosya) kullanıyor. `TeqlifCacheManager` (2 gün TTL, 300 dosya) ile tutarlı politika sağlanmalı.

**Öncelikli ekranlar (frekanslı):**
1. `messages_screen.dart` — 3 CachedNetworkImage + 2 CachedNetworkImageProvider
2. `recording_detail_screen.dart` — 4 + 4
3. `sales_screen.dart`, `purchase_detail_screen.dart` — 2'şer
4. `retargeting_screen.dart`, `direct_sale_detail_screen.dart` — kalan

**Çözüm:** Her `CachedNetworkImage(...)` çağrısına `cacheManager: TeqlifCacheManager()` ekle. `CachedNetworkImageProvider(url)` → `CachedNetworkImageProvider(url, cacheManager: TeqlifCacheManager())`.

---

### §12.4 memCacheWidth / memCacheHeight — Bellek Önbellek Optimizasyonu

**Öncelik:** P1
**Etkilenen sistem:** Mobil → tüm 60 CachedNetworkImage widget (0 memCache kullanımı)

`PaintingBinding.instance.imageCache` 25 MB ile sınırlı (V1.0). Ama 1080px görseller 80×80 avatar alanında decode ediliyor — bellek ~180× gereksiz harcanıyor.

**Çözüm:**
```dart
// Avatar (~60dp × 2x)
CachedNetworkImage(imageUrl: url, cacheManager: TeqlifCacheManager(),
  memCacheWidth: 120, memCacheHeight: 120, fit: BoxFit.cover)

// Feed kartı (ekran genişliği / 2 ~ 200dp × 2x)
CachedNetworkImage(imageUrl: url, cacheManager: TeqlifCacheManager(),
  memCacheWidth: 400, fit: BoxFit.cover)
```

Kural: `memCacheWidth = round(renderWidth * devicePixelRatio)`. Sabit olmayan layout için makul üst sınır: avatar=120, feed kart=400, tam ekran=800.

---

### §12.9 LIFECYCLE Cache — WS Event Invalidasyonu Eksikliği

**Öncelik:** P1
**Etkilenen sistem:** Mobil + WS altyapısı (ADR §10 StreamCommerceNotifier)

ADR §9: "LIFECYCLE: Olayın bitişiyle tetiklenir." Ancak mevcut durumda `cacheStreams` ve `cacheAuctions` yalnızca TTL ile evict ediliyor.

**Tespit:**

```dart
// auction_provider.dart:30 — auction_ended_by_buy_it_now
// direct_sale_provider.dart:64 — direct_sale_ended
// → clearData(cacheAuctions) veya clearData(cacheStreams) ÇAĞRILMIYOR
```

**Senaryo:** Kullanıcı açık artırma listesini görüyor (cache'de 3 dk TTL). Artırma anında sona eriyor (WS event alınıyor). Kullanıcı listele sayfasına geri dönüyor → 3 dakikaya kadar "aktif" olarak görebilir.

**Çözüm:**

ADR §10 kuralına göre WS altyapısına dokunulmaz; cache temizleme sadece `onCommerceEvent()` alt sınıf metoduna eklenir:

```dart
// auction_provider.dart — AuctionNotifier.onCommerceEvent()
case 'auction_ended':
case 'auction_ended_by_buy_it_now':
  // LIFECYCLE invalidasyon — cache stale kalmasın
  ref.read(cacheServiceProvider).clearData(StorageService.cacheAuctions);
  break;
```

```dart
// live_stream_provider.dart — FollowedStreamsNotifier (veya stream end observer)
// Stream durumu 'ended' olan kayıt home/search feed'de de olabilir
// → clearData(cacheStreams) stream.status == 'ended' WS event alındığında
```

**Not:** WS event olmaksızın stream sona erme (sunucu kapanması, ağ kopması) TTL ile çözülür. Bu düzeltme yalnızca uygulama açık ve WS bağlıyken geçerli event'lar içindir — ek karmaşıklık gerekmez.

---

### §12.10 Backend ↔ Mobil TTL Uyumsuzluğu

**Öncelik:** P1
**Etkilenen sistem:** Mobil HomeRepository + Backend feed.py

**Tespit:**

| Katman | TTL | Kaynak |
|--------|-----|--------|
| Backend Redis `feed:personalized:{uid}` | **15 dakika** | `feed.py:362` `setex(cache_key, 900, ...)` |
| Flutter `HomeRepository._kCacheTtlMs` | **30 dakika** | `home_repository.dart:27` |
| Flutter `search_view_model` for-you | **10 dakika** | `search_view_model.dart:330` |

`HomeRepository` 30 dakika geçerli sayarken backend aynı veriyi 15 dakika sonra yeniliyor. Kullanıcı uygulamayı 20 dakika sonra açtığında mobil 10 dakika daha taze veri gösterirken backend farklı (yenilenmiş) bir feed hesaplamış olabilir. Sosyal ticaret bağlamında yeni ilanlar, fiyat değişikliği ve "for-you" kişiselleştirme için bu fark önemli.

**Çözüm:**

```dart
// home_repository.dart
static const _kCacheTtlMs = 15 * 60 * 1000; // 30 → 15 dakika (backend TTL ile senkron)
```

`search_view_model.dart:330` zaten 10 dakika kullanıyor — for-you feed için bu daha iyi; değiştirilmez.

**Test:** Backend Redis'e doğrudan yazılmış bir test verisi 15 dakika sonra mobilde yenileniyor.

---

### §12.11 `home_view_model` / `search_view_model` — Direct http.get (ADR §8 İhlali)

**Öncelik:** P1
**Etkilenen sistem:** Mobil MVVM — Clean Architecture §0.4 ihlali

ADR §8: "ViewModel doğrudan `http.get()`, `Hive.openBox()`, `SharedPreferences.getInstance()` çağıramaz."

**Tespit:**

```
home_view_model.dart:117   final resp = await http.get(uri, headers: ...)
home_view_model.dart:149   final resp = await http.get(...)
home_view_model.dart:186   final resp = await http.get(...)
home_view_model.dart:255   final resp = await http.get(uri, headers: ...)   ← loadMore()
home_view_model.dart:310   await http.delete(...)

search_view_model.dart:235  final resp = await http.get(...)
search_view_model.dart:257  final resp = await http.get(...)
search_view_model.dart:476  final resp = await http.get(...)                ← loadMoreRecentListings()
search_view_model.dart:517  final resp = await http.get(...)                ← loadMoreForYou()
```

`StorageService.getToken()` static çağrısı da Data Layer → ViewModel ihlalidir. `ApiService` veya `ApiClient` bu token yönetimini zaten içeriyor.

**İlişki:** §12.5 (loadMore disk persistansı) bu bulguyla birleşiyor — her ikisi de `loadMore()` için `HomeRepository`'nin genişletilmesini gerektiriyor.

**Çözüm:**

`HomeRepository`'ye `loadMore(page, maxId)` metodu ekle:

```dart
// home_repository.dart
Future<HomeFeedPage> loadMore({required int page, int? maxId}) async {
  // ApiClient üzerinden çağrı yapar — token yönetimi ApiClient içinde
  final uri = maxId != null
      ? Uri.parse('${_client.config.baseUrl}/feed/recent?max_id=$maxId')
      : Uri.parse('${_client.config.baseUrl}/feed/recent?page=$page');
  final resp = await _client.get(uri);
  // parse + cache yazma buraya taşınır
}
```

`home_view_model.dart` `loadMore()` metodu `_repo.loadMore(...)` çağrısına indirgenir.

Aynı düzeltme `search_view_model.dart` için de gereklidir — ancak `SearchRepository` henüz yok; önce `HomeRepository` düzeltilir, ardından aynı pattern `SearchRepository` ile tekrarlanır.

**Etki:** Bu refactor `§12.5` (loadMore disk persistansı) ile aynı sprint'te yapılmalıdır; her ikisi de aynı metodun içini değiştiriyor.

---

### §12.5 Feed loadMore() Sayfaları — Disk Kalıcılığı

**Öncelik:** P2
**Etkilenen sistem:** Mobil — `HomeRepository` + `search_view_model`

> **Not:** Bu bulgu §12.11 ile birlikte ele alınmalıdır. `loadMore()` önce Repository'ye taşınmalı (§12.11), ardından Repository cache yazması eklenmeli.

**Tespit:**

`home_view_model.dart:235 loadMore()` ve `search_view_model.dart:445,503` — başarılı yanıtlar yalnızca state'e yazılıyor, cache'e değil. Uygulama arka plana alınıp geri dönüldüğünde yalnızca sayfa 0 görünür.

**Çözüm (§12.11 sonrası):**

`HomeRepository.loadMore()` içinde merged listeyi kaydeder:

```dart
const _kMaxCachedListings = 60; // 3 sayfa × 20 ilan
final merged = [...current, ...uniqueMore].take(_kMaxCachedListings).toList();
await saveFeed(jsonEncode(merged)); // var olan HomeRepository metodu
```

---

### §12.6 api_cache Box — Maksimum Anahtar Limiti (LRU Kırpma)

**Öncelik:** P2
**Etkilenen sistem:** Mobil — `CacheService`

`api_cache` box yalnızca TTL'e göre temizleniyor. Dinamik anahtarlar (`public_profile_<username>`, `public_listings_<username>`, `feed_personalized`) birikerek 500+ anahtara ulaşabilir (~1 MB).

**Çözüm:**

```dart
// cache_service.dart — clearExpired() sonuna ekle
const maxKeys = 200;
if (box.length > maxKeys) {
  final entries = box.keys.map((k) {
    final raw = box.get(k);
    if (raw == null) return MapEntry(k, 0);
    final w = jsonDecode(raw) as Map<String, dynamic>;
    return MapEntry(k, (w['_t'] as num).toInt());
  }).toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  await box.deleteAll(entries.take(box.length - maxKeys).map((e) => e.key));
}
```

**Limit:** 200 anahtar × ortalama 2 KB ≈ 400 KB Hive box boyutu.

---

### §12.12 cacheKey Parametresi — Presigned URL Bağımlılığı

**Öncelik:** P2
**Etkilenen sistem:** Mobil — tüm 60 CachedNetworkImage widget

`flutter_cache_manager`, URL'yi cache key olarak kullanır. MinIO presigned URL'leri rotasyon veya URL yapısı değişiminde bozulur — eski cache geçersiz hale gelir, tüm görseller yeniden indirilir.

**Tespit:**

```bash
# grep: 0 satır
grep -rn "cacheKey:" mobile/lib/
```

**Sorun:** `https://uploads.teqlif.com/teqlif/listings/42/photo_0.jpg?X-Amz-Expires=...` URL'sinin imza kısmı değişince cache miss oluşur. MinIO bucket adı değişikliği (staging → prod geçişi) de aynı sorunu yaratır.

**Çözüm:**

Entity ID tabanlı stabil cache key kullan:

```dart
CachedNetworkImage(
  imageUrl: listing.photoUrl,
  cacheKey: 'listing_${listing.id}_photo_0',   // URL değişse de key sabit
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 400,
)

// Avatar
CachedNetworkImage(
  imageUrl: user.avatarUrl,
  cacheKey: 'user_${user.id}_avatar',
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 120, memCacheHeight: 120,
)
```

Kural: `cacheKey = entityType_entityId_fieldName`. URL segment veya query string içermez.

---

### §12.13 Backend — `Cache-Control` Header Eksikliği

**Öncelik:** P2
**Etkilenen sistem:** Backend FastAPI + Cloudflare CDN katmanı

**Tespit:**

```bash
grep -rn "Cache-Control" backend/app/ → 0 sonuç
```

Backend hiçbir response'a `Cache-Control` header'ı eklemiyor. Cloudflare `teqlif.com` ve `api.teqlif.com` üzerinde Proxied modda çalışıyor (ADR §12). Cloudflare, standart `Cache-Control` header'ı olan JSON response'ları edge'de cache'leyebilir — bu özellikle ALGORITHMIC ve SCHEMA_VERSIONED endpoint'ler için önemli.

**ETag ile ilişki:** V1.0 §11.16'da ETag desteği eklendi (`If-None-Match`). `Cache-Control` ETag'ı tamamlar: müşteri önce `max-age` dolmadan sunucuya gitmez, dolunca `If-None-Match` ile gider.

**Çözüm (kademeli):**

```python
# backend/app/routers/feed.py — ALGORITHMIC endpoint'ler
from fastapi import Response

@router.get("/feed/recent")
async def get_recent_feed(..., response: Response):
    ...
    response.headers["Cache-Control"] = "private, max-age=300, stale-while-revalidate=900"
    return listings
```

| Endpoint tipi | Öneri |
|---------------|-------|
| `/api/catalog`, `/api/cities` (SCHEMA_VERSIONED) | `public, max-age=86400, stale-while-revalidate=3600` — Cloudflare edge cache |
| `/api/feed/recent`, `/api/feed/for-you` (ALGORITHMIC) | `private, max-age=300, stale-while-revalidate=900` — CDN cache değil, client hint |
| `/api/i18n/{lang}` (SCHEMA_VERSIONED) | `public, max-age=3600, stale-while-revalidate=86400` |
| Commerce / auction / stream (LIFECYCLE) | `no-cache` — WS gerçek zamanlı, CDN cache istenmiyor |
| Auth / payment (SECURITY_CRITICAL) | `no-store` |

**Kural:** `private` = yalnızca client cache, Cloudflare cache etmez. `public` = Cloudflare edge'de cache'lenebilir.

---

### §12.7 PublicProfile Prefetch — Gecikmeli Önbellek Isıtma

**Öncelik:** P3
**Etkilenen sistem:** Mobil

ADR §8 MVVM kuralı: prefetch View'dan ViewModel metodunu `didChangeDependencies` veya liste render sırasında çağırarak yapılabilir — ancak bu navigasyon zamanlamasını değiştirdiği için ADR kararı gerektirir. V1.2'ye bırakılır.

---

### §12.8 Entity Normalization Store

**Öncelik:** P3
**Etkilenen sistem:** Mobil

Bir `Listing` entity'si eş zamanlı 5-6 farklı cache anahtarında bulunabilir. Normalize store mimarisi V1.2'de ADR kararı ve bağımsız implementation sprint gerektirir.

---

## 4. ADR §17 Tutarsızlığı — Uptime Kuma Backend

**Bu dökümanın kapsamı dışında ama kritik not:**

ADR §17 (nodeMonitor) Uptime Kuma için "MariaDB backend" yazmaktadır. 2026-10-14 backup düzeltmesi sırasında doğrulama yapıldı — **gerçekte SQLite** kullanılıyor (`/opt/monitor/shared/uptime-kuma/db/kuma.db`). ADR §17 güncellenmeli.

---

## 5. Uygulama Sırası

```
P0 — flutter_cache_manager sürüm sabitleme          (§12.1)   ← bu sprint
P1 — messages/notifications açık TTL               (§12.2)   ← §12.1 ile birlikte (küçük değişiklik)
P1 — Backend TTL uyumu: home feed 30→15 dk          (§12.10)  ← §12.1 ile birlikte (tek satır)
P1 — TeqlifCacheManager tüm widget'lara             (§12.3)   ← ayrı PR (47 widget)
P1 — memCacheWidth/Height                           (§12.4)   ← §12.3 ile aynı PR
P1 — LIFECYCLE cache WS invalidasyon               (§12.9)   ← WS bağlamında ayrı PR
P1 — home/search ViewModel http.get kaldır          (§12.11)  ← HomeRepository refactor sprint
P2 — loadMore() Repository'den diske yaz            (§12.5)   ← §12.11 ile aynı sprint
P2 — api_cache box LRU kırpma                       (§12.6)   ← ayrı sprint
P2 — cacheKey parametresi                           (§12.12)  ← §12.3 ile aynı PR (her widget'a eklenebilir)
P2 — Backend Cache-Control header                   (§12.13)  ← backend-only ayrı PR
P3 — PublicProfile prefetch ADR kararı              (§12.7)   ← V1.2
P3 — Entity normalization tasarımı                  (§12.8)   ← V1.2
```

**Sprint Planı:**

| Sprint | Bulgular | Beklenen Etki |
|--------|----------|---------------|
| S1 (bu hafta) | §12.1 + §12.2 + §12.10 | Güvenli paket versiyonu, tutarlı TTL, tek satır fix |
| S2 | §12.3 + §12.4 + §12.12 | Tüm görseller 2 gün TTL + bellek optimizasyonu |
| S3 | §12.9 | LIFECYCLE anahtarlar gerçek zamanlı temizleniyor |
| S4 | §12.11 + §12.5 | Clean Architecture düzeldi, loadMore kalıcı |
| S5 | §12.6 + §12.13 | LRU kırpma + CDN cache hint |
| V1.2 | §12.7 + §12.8 | Prefetch + entity normalization |

---

## 6. Kapsam Dışı (V1.0'da Tamamlandı)

| Madde | Commit |
|-------|--------|
| SWR gerçek bayat-göster davranışı | `bc6998ff` |
| `CacheService` instance-based DIP | `bc6998ff` |
| `HomeRepository` izolasyon katmanı | `bc6998ff` |
| `StorageService.cacheData` → `CacheService` geçişi | `bc6998ff` |
| ETag / Conditional Request (`If-None-Match` + 304) | `20ab93a5` |
