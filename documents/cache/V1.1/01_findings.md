# Mobile Cache Sistem Analizi — V1.1 Bulgular & Uygulama Spesifikasyonu

**Tarih:** 2026-10-14
**Kapsam:** V1.0 sonrası açık kalan cache iyileştirme fırsatları; görüntü cache birleşimi, sayfalama kalıcılığı, bellek yönetimi
**Revizyon:** V1.0 — Analiz tamamlandı, uygulama bekliyor

---

## 0. Uyum Gereksinimleri

V1.0 §0 kurallarının tamamı bu döküman için de geçerlidir. Tekrarlanmamıştır; her uygulama adımında V1.0 §0 okunur.

Kısaca:
- ADR §13 workflow her commit için zorunlu (local → push → git pull → test → docs → cleanup)
- ADR §8 MVVM katman sınırları ihlal edilemez
- `flutter analyze` sıfır hata/uyarı
- P0 ve P1 önce staging'de test edilir

---

## 1. Özet Tablo

| § | Başlık | Öncelik | Durum | Commit |
|---|--------|---------|-------|--------|
| §12.1 | `flutter_cache_manager` sürüm sabitleme | **P0** | ⬜ bekliyor | — |
| §12.2 | messages/notifications açık TTL | **P1** | ⬜ bekliyor | — |
| §12.3 | TeqlifCacheManager tüm CachedNetworkImage'lara yay | **P1** | ⬜ bekliyor | — |
| §12.4 | memCacheWidth/Height feed kartlarına ekle | **P1** | ⬜ bekliyor | — |
| §12.5 | Feed loadMore() sayfaları diske yaz | **P2** | ⬜ bekliyor | — |
| §12.6 | api_cache box maksimum anahtar limiti | **P2** | ⬜ bekliyor | — |
| §12.7 | PublicProfile prefetch (gecikmeli önbellek ısıtma) | **P3** | ⬜ bekliyor | — |
| §12.8 | Entity normalization store | **P3** | ⬜ bekliyor | — |

---

## 2. Bulgular

### §12.1 `flutter_cache_manager: any` — Sürüm Sabitleme

**Öncelik:** P0
**Etki:** Bir sonraki `flutter pub upgrade` ile kırılma riski — breaking change olduğunda herhangi bir build'de sessizce bozulabilir.

**Tespit:**

```
mobile/pubspec.yaml:66:  flutter_cache_manager: any
```

`any` kısıtı, pub.dev'de yeni sürüm yayınlandığında CI/build ortamında farklı sürüm çözümü alınmasına neden olur. `cached_network_image: ^3.3.1` zaten `flutter_cache_manager`'a bağımlıdır; `any` bırakmak gereksiz.

**Çözüm:**

```yaml
# pubspec.yaml
flutter_cache_manager: ">=3.3.1 <4.0.0"
```

Mevcut prod sürümünü doğrula: `flutter pub deps | grep flutter_cache_manager`, ardından `^` ile sabitle.

**Test:** `flutter pub upgrade --dry-run` çıktısında version conflict yok, `flutter analyze` temiz.

---

### §12.2 messages / notifications / message_requests — Açık TTL Eksikliği

**Öncelik:** P1
**Etki:** ADR §9 taksonomisi `EPHEMERAL` olarak sınıflandırılmış bu anahtarlar, `saveData` çağrısında `ttl` parametresi geçmediği için varsayılan 5 dakika kullanıyor. Bu değer şu an doğru tesadüfen — ama gelecekte `CacheService` varsayılanı değişirse sessizce kırılır.

**Tespit:**

```
messages_view_model.dart:155   await _cache.saveData(StorageService.cacheMessages, data);
messages_view_model.dart:280   await _cache.saveData(StorageService.cacheNotifications, data);
messages_view_model.dart:349   await _cache.saveData(StorageService.cacheMessageRequests, data);
```

Her üçü de `ttl` parametresi geçmiyor. Kasıtlı değer değil, unutulmuş.

**Çözüm:**

```dart
// messages_view_model.dart — üç satır
await _cache.saveData(
  StorageService.cacheMessages,
  data,
  ttl: const Duration(minutes: 5), // EPHEMERAL: mesaj listesi hızla bayatlar
);
await _cache.saveData(
  StorageService.cacheNotifications,
  data,
  ttl: const Duration(minutes: 5),
);
await _cache.saveData(
  StorageService.cacheMessageRequests,
  data,
  ttl: const Duration(minutes: 5),
);
```

TTL değeri bilinçli olarak seçilmeli: backend mesaj/bildirim event gönderiyorsa WS bağlantısında zaten anlık güncellenir; 5 dakika offline kapsam için yeterli.

**Test:** Messages ekranı offline açılınca cached data gösterir; 5 dakika sonra açılınca network fetch tetikler.

---

### §12.3 TeqlifCacheManager — Tüm CachedNetworkImage Kapsamı

**Öncelik:** P1
**Etki:** 60 `CachedNetworkImage` widget'ından yalnızca 13'ü `TeqlifCacheManager` kullanıyor. Geri kalan 47'si `DefaultCacheManager` ile calışıyor: **7 günlük TTL, 200 dosya limiti** — uygulamamızın 2 gün / 300 dosya konfigürasyonu yerine.

**Tespit:**

```
TeqlifCacheManager kullanan widget'lar (13):
  search_screen.dart         : 3 widget
  home_screen.dart           : 2 widget
  profile_screen.dart        : 4 widget
  listing_detail_screen.dart : 3 widget  (eklendi)
  (diğer ekranlar)           : 1 widget

DefaultCacheManager ile kalan ekranlar (örnekler):
  direct_sale_detail_screen.dart
  retargeting_screen.dart       (2 widget)
  sales_screen.dart             (2 widget)
  purchase_detail_screen.dart   (2 widget)
  recording_detail_screen.dart  (4 widget)
  messages_screen.dart          (3 widget + 2 Provider)
  follow_requests_screen.dart
  call_history_screen.dart
  blocked_users_screen.dart
```

`CachedNetworkImageProvider` kullanan 10 konum da `TeqlifCacheManager` almıyor — ancak `CachedNetworkImageProvider` CircleAvatar içinde background image olarak kullanıldığında `cacheManager` parametresi destekleniyor.

**Çözüm:**

Her `CachedNetworkImage(...)` çağrısına `cacheManager: TeqlifCacheManager()` ekle. `CachedNetworkImageProvider(url)` → `CachedNetworkImageProvider(url, cacheManager: TeqlifCacheManager())`.

Uygulama sırası (etki büyüklüğüne göre):
1. `messages_screen.dart` — 3 CachedNetworkImage + 2 Provider (yüksek frekanslı ekran)
2. `recording_detail_screen.dart` — 4 CachedNetworkImage + 4 Provider
3. `sales_screen.dart`, `purchase_detail_screen.dart` — 2'şer widget
4. `retargeting_screen.dart`, `direct_sale_detail_screen.dart` — kalan ekranlar

**Test:** `flutter_cache_manager` disk cache dizininde `teqlifImgCache/` klasörü büyürken `flutter_cache/` küçülüyor.

---

### §12.4 memCacheWidth / memCacheHeight — Bellek Önbellek Optimizasyonu

**Öncelik:** P1
**Etki:** `PaintingBinding.instance.imageCache` 25 MB olarak sınırlandırılmış (V1.0'da uygulandı). Ancak hiçbir `CachedNetworkImage` widget'ı `memCacheWidth` veya `memCacheHeight` kullanmıyor. Feed kartları 1080px tam boyutlu görselleri 80×80 avatar olarak decode ediyor — bellek 180× gereksiz harcanıyor.

**Tespit:**

```bash
# grep sonucu: 0 satır
grep -rn "memCacheWidth\|memCacheHeight" mobile/lib/
```

**Çözüm — öncelikli lokasyonlar:**

Feed kartları ve avatar'lar en kritik; bunlar yüksek tekrar eden widget'lar:

```dart
// Avatar (genellikle 40-60dp → 2x = 80-120px mantıklı)
CachedNetworkImage(
  imageUrl: avatarUrl,
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 120,   // dp * devicePixelRatio ≈ 60 * 2
  memCacheHeight: 120,
  fit: BoxFit.cover,
)

// Feed kartı ana görseli (genellikle ekran genişliği / 2 grid veya full width)
CachedNetworkImage(
  imageUrl: photoUrl,
  cacheManager: TeqlifCacheManager(),
  memCacheWidth: 400,  // grid kart genişliği * 2x
  fit: BoxFit.cover,
)
```

Kural: `memCacheWidth = round(renderWidth * devicePixelRatio)`. Layout sabit değilse hesaplamak yerine makul bir üst sınır belirle (avatar=120, feed kart=400, full-screen=800).

**Not:** `memCacheWidth` yalnızca bellek decoder cache'ini etkiler — disk'teki dosya değişmez. `§12.3` ile aynı anda uygulanabilir.

**Test:** `flutter --profile` ile memory profiler'da image cache bellek kullanımı azalıyor.

---

### §12.5 Feed loadMore() Sayfaları — Disk Kalıcılığı

**Öncelik:** P2
**Etki:** Kullanıcı feed'i 3 sayfa kaydırır, uygulama arka plana alınır. Geri döndüğünde yalnızca sayfa 0 görünür — kaydırma pozisyonu ve görülen ilan listesi kaybolur. Instagram / TikTok bu durumu "sayfa önbelleğe alınmış" veriyle çözer.

**Tespit:**

`home_view_model.dart:235 loadMore()` — yalnızca state'e yazar, `CacheService.saveData()` çağırmaz.
`search_view_model.dart:445 loadMoreRecentListings()` ve `loadMoreForYou()` — aynı durum.

**Çözüm:**

Feed state'ini tek bir merged blob olarak sakla — her `loadMore()` sonrasında tüm birikmiş listeyi güncelle:

```dart
// home_view_model.dart — loadMore() başarı bloğu sonuna ekle
await ref.read(cacheServiceProvider).saveData(
  StorageService.cacheHomeFeedRecent,
  [...current.recentListings, ...uniqueMore],
  ttl: const Duration(minutes: 15), // ALGORITHMIC taksonomi
);
```

Maksimum sayfa limiti belirle — disk'e sonsuz liste yazmamak için:

```dart
const _kMaxCachedListings = 60; // 3 sayfa × 20 ilan
if (mergedList.length > _kMaxCachedListings) {
  mergedList = mergedList.take(_kMaxCachedListings).toList();
}
```

`StorageService` sabitlerini kontrol et: `cacheHomeFeedRecent` zaten var mı, yoksa ekle.

**Kapsam:** `home_view_model.dart` + `search_view_model.dart` (iki feed türü).

**Test:** 3 sayfa kaydır → arka plana al → geri dön → liste korunmuş.

---

### §12.6 api_cache Box — Maksimum Anahtar Limiti

**Öncelik:** P2
**Etki:** `CacheService` altındaki `api_cache` Hive box'ı sadece `clearExpired()` ile TTL dolmuş kayıtları temizliyor. Dinamik anahtarlar (örn: `public_profile_<username>`, `public_listings_<username>`) kullanıcı davranışına bağlı olarak birikir; aktif kullanıcıda 500+ anahtar mümkün.

**Tespit:**

```dart
// cache_service.dart — clearExpired() tek temizleme noktası
Future<void> clearExpired() async {
  // sadece TTL dolmuş kayıtları siler
}
// maksimum box boyutu kontrolü yok
```

**Çözüm:**

`clearExpired()` çalıştıktan sonra box boyutu hâlâ limitin üzerindeyse en eski kayıtları sil:

```dart
Future<void> clearExpired() async {
  final box = Hive.box<String>(_boxName);
  final now = DateTime.now().millisecondsSinceEpoch;

  // 1. TTL dolmuş kayıtları sil (mevcut mantık)
  final expiredKeys = <dynamic>[];
  for (final key in box.keys) {
    final raw = box.get(key);
    if (raw == null) continue;
    final wrapper = jsonDecode(raw) as Map<String, dynamic>;
    final savedAt = (wrapper['_t'] as num).toInt();
    final ttlMs   = (wrapper['_x'] as num).toInt();
    if (now - savedAt > ttlMs) expiredKeys.add(key);
  }
  await box.deleteAll(expiredKeys);

  // 2. Aşırı büyümüş box'ı LRU benzeri kırp
  const maxKeys = 200;
  if (box.length > maxKeys) {
    final entries = <MapEntry<dynamic, int>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      entries.add(MapEntry(key, (wrapper['_t'] as num).toInt()));
    }
    entries.sort((a, b) => a.value.compareTo(b.value)); // en eski önce
    final toDelete = entries.take(box.length - maxKeys).map((e) => e.key).toList();
    await box.deleteAll(toDelete);
  }
}
```

**Limit önerisi:** 200 anahtar. Her kayıt ortalama 2KB → toplam ~400KB; Hive için uygun.

**Test:** 300 farklı anahtar yaz → `clearExpired()` çağır → box.length ≤ 200.

---

### §12.7 PublicProfile Prefetch — Gecikmeli Önbellek Isıtma

**Öncelik:** P3
**Etki:** Kullanıcı ilan kartına tıklamadan önce profil verisini önceden yüklemek mümkün, ancak uygulamanın mevcut navigasyon deseninde tap anında veri yükleniyor. Profil verisi küçük (~2KB) ve yüksek hit-rate bir önbellek adayı.

**Tespit:**

`public_profile_view_model.dart` profil verisini `build()` sırasında `_fetchProfile()` ile yüklüyor. Herhangi bir "ön ısıtma" mekanizması yok.

**Çözüm:**

Feed kart widget'larında `onHover` (tablet/desktop) veya ilan detayına geçiş sırasında `PublicProfileViewModel`'in prefetch metodunu tetikle. Ancak bu değişiklik View → ViewModel çağrısının zamanlamasını değiştirdiği için ADR §8 incelemesi gerektirir.

**Öneri:** Bu madde bağımsız bir ADR kararı gerektirir; mevcut döngüde uygulanmaz.

---

### §12.8 Entity Normalization Store

**Öncelik:** P3
**Etki:** Bir `Listing` entity'si aynı anda 5-6 farklı cache anahtarında bulunabilir:
- `home_feed_recent` (page 0)
- `explore_for_you`
- `explore_personalized_feed`
- `public_listings_<username>`
- `user_favorites`
- ilan detayı cache'i (varsa)

Birinde ilan kapandığında veya fiyat değiştiğinde diğerleri bayat kalır. Instagram / Facebook bu sorunu normalize entity store ile çözer — her entity tek yerde tutulur, diğerleri ID'ye referans verir.

**Çözüm (mimari):**

1. `ListingEntity` ID → JSON normalize cache: `entity_listing_<id>`
2. Feed cache'leri yalnızca ID listesi tutar: `[42, 17, 98, ...]`
3. Feed widget'ları ID'ye göre `EntityStore`'dan resolve eder

**Neden P3:** Bu refactor tüm feed / search / profile akışlarını etkiler; bağımsız bir ADR maddesi ve ayrı implementation sprint gerektirir. V1.1 döngüsünde analiz belgesi oluşturulur, uygulama V1.2'ye bırakılır.

---

## 3. Uygulama Sırası

```
P0 — flutter_cache_manager sürüm sabitleme          (§12.1)  ← hemen
P1 — messages TTL açık hale getir                   (§12.2)  ← §12.1 ile birlikte
P1 — TeqlifCacheManager tüm widget'lara             (§12.3)  ← en yüksek etki
P1 — memCacheWidth/Height feed kartları             (§12.4)  ← §12.3 ile aynı PR
P2 — loadMore() sayfaları diske yaz                 (§12.5)  ← ayrı sprint
P2 — api_cache box LRU kırpma                       (§12.6)  ← ayrı sprint
P3 — PublicProfile prefetch ADR kararı              (§12.7)  ← V1.2
P3 — Entity normalization ADR + tasarım             (§12.8)  ← V1.2
```

**Tahmini etki:** §12.1–§12.4 tamamlandığında görüntü cache tutarsızlığı ortadan kalkar; kullanıcı her ekranda 2 günlük staleness politikasından yararlanır (şu an rastgele 7 gün vs 2 gün karışımı var). Bellek kullanımı özellikle mesajlar ve kayıtlar ekranında ölçülebilir şekilde düşer.

---

## 4. Kapsam Dışı

Aşağıdakiler V1.0 döngüsünde tamamlandı; V1.1'de yeniden ele alınmaz:

| Madde | Commit |
|-------|--------|
| SWR gerçek bayat-göster davranışı | `bc6998ff` |
| `CacheService` instance-based DIP | `bc6998ff` |
| `HomeRepository` izolasyon katmanı | `bc6998ff` |
| `StorageService.cacheData` → `CacheService` geçişi | `bc6998ff` |
| ETag / Conditional Request (`If-None-Match` + 304) | `20ab93a5` |
