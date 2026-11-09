# teqlif Platformu — Uçtan Uca (Client · Backend · DB) Cache Mimarisi Raporu (V1.4)

**Tarih:** 9 Kasım 2026  
**Kapsam:** 
- **Client Katmanı:** `mobile/lib/services/` (`cache_service.dart`, `api_service.dart`, `storage_service.dart`, `image_cache_manager.dart`, `offline_queue_service.dart`), `mobile/lib/repositories/`, `mobile/lib/screens/viewmodels/`
- **Backend Katmanı:** `backend/app/core/read_cache.py`, `backend/app/security/etag_middleware.py`, `backend/app/services/feed/listing_cache_service.py`, `backend/app/utils/schema_cache.py`, `backend/app/utils/auth.py`, `backend/app/routers/`
- **Veritabanı & Depolama Katmanı:** PostgreSQL 17 + `shared_buffers`, PgBouncer Transaction Pooling (`prepared_statement_cache`), ClickHouse `MergeTree` + Redis Write-Behind Buffering (`database_clickhouse.py`), MinIO S3 Presigned URL Önbelleklemesi  
**Amaç:** teqlif ekosisteminin tüm katmanlarını (İstemci, API/Uygulama Sunucusu, Dağıtık Önbellek, Veritabanı ve Analitik Depolama) **Clean Code**, **Clean Architecture**, **MVVM**, **ADR §9 (Cache Taksonomisi)**, **OWASP Mobile Security (M2/M9)** ve **RFC 7232/9111 HTTP Caching** standartları doğrultusunda uçtan uca analiz ederek; mimari tutarsızlıkları, yarış koşullarını, veri sızıntılarını ve performans darboğazlarını somut çözüm reçeteleriyle belgelemek.

---

## 🏗️ 1. Katman Bazlı Mimari ve Endüstriyel Değerlendirme

```
┌────────────────────────────────────────────────────────────────────────┐
│                        1. CLIENT KATMANI (Flutter)                     │
│  - Presentation (Widgets / Views)                                      │
│  - ViewModel (Riverpod AsyncNotifier / Notifier)                       │
│  - Data (CacheService [Hive], StorageService, TeqlifCacheManager)      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTP / ETag (If-None-Match) / WS
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        2. BACKEND KATMANI (FastAPI)                    │
│  - Middlewares: ETagMiddleware (MD5 Hashing), GZip, CORS               │
│  - Application Services & Use Cases (CQRS Read Cache, Auth Session)    │
│  - Distributed Cache: Redis Cluster (Sessions, ZSET Feeds, Schemas)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ SQL (asyncpg) / PgBouncer / ClickHouse Driver
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 3. VERİTABANI & DEPOLAMA KATMANI (DB / Storage)        │
│  - PostgreSQL 17: Shared Buffers, OS Page Cache, PgBouncer Prep Stmt   │
│  - ClickHouse: Redis Write-Behind Flush Loop (30s batch)               │
│  - MinIO: S3 Object Storage, Presigned URL Lifecycle                   │
└────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Katman 1: Client (Mobil / Flutter)
* **MVVM Değerlendirmesi:**  
  - *İhlal:* Ekran (View) sınıfları (`listing_detail_screen.dart`, `swipe_live_screen.dart`), ViewModel veya Repository katmanını baypas ederek doğrudan `ref.read(cacheServiceProvider).clearData('user_wallet_data')` çağırmaktadır (ADR §8 ihlali). View katmanı veri katmanının önbellek anahtarlarından tamamen habersiz olmalıdır.
  - *İhlal:* `profile_screen.dart` içinde doğrudan HTTP PATCH isteği atılmakta ve `StorageService.saveUserInfo` çalıştırılmaktadır.
* **Clean Architecture Değerlendirmesi:**  
  - *İhlal:* Bağımlılık yönü bozulmuştur. Presentation katmanı doğrudan Data katmanındaki somut sınıflara (`CacheService`, `StorageService`) erişmektedir.
  - *İhlal:* `HomeRepository` kendi özel Hive kutusunu (`homeCache`) yönetmekte; merkezi `CacheService` ve `ApiService`'i baypas etmektedir.
* **Clean Code Değerlendirmesi:**  
  - Sihirli dizgeler (Magic Strings) kontrolsüzce yayılmıştır (`'user_wallet_data'`, `'feed_personalized'`, `'cache_feed'`). `StorageService.cacheFeed` sabiti tanımlanmış fakat projede hiçbir yerde kullanılmamaktadır.
  - `CacheService.clearExpired()` metodu adında "LRU" iddiası taşımasına karşın, sıralamayı `_t` (oluşturulma zamanı) alanına göre yaparak fiilen **FIFO (First In First Out)** işletmektedir.
* **Endüstriyel Pratikler & Güvenlik:**  
  - **OWASP M2/M9 İhlali:** Hive kutusu (`api_cache`) donanım destekli şifreleme anahtarı (`HiveAesCipher`) olmadan açılmakta; cüzdan bakiyeleri, özel DM sohbetleri ve kimlik bilgileri cihaz diskinde düz metin (plaintext) durmaktadır.
  - **Multi-Tenant / Account İzolasyon Yokluğu:** Cache anahtarları kullanıcı ID'si barındırmadığı için, hesap değişiminde Kullanıcı B ilk frame'de Kullanıcı A'nın cüzdan bakiyesini görmektedir.
  - **Stale Avatar Bug:** `CachedNetworkImageProvider` için statik `cacheKey: 'user_${id}_avatar'` kullanıldığından, kullanıcı profil resmini değiştirse bile CDN URL'i yok sayılarak 48 saat boyunca eski avatar diskten basılmaktadır.

---

### 1.2 Katman 2: Backend (FastAPI, Redis, Middlewares)
* **Clean Architecture & CQRS Değerlendirmesi:**  
  - *İhlal:* CQRS önbellek mekanizması (`read_cache.py`), Infrastructure katmanı yerine `app/core/` altında konumlandırılmıştır.
  - *İhlal:* Router katmanı (`routers/chat.py`, `routers/notifications.py`, `routers/onboarding.py`) doğrudan `get_redis()` ile `session:user:{id}` anahtarına ham okuma/yazma yapmakta; soyut bir `UserSessionRepository` port/adapter yapısı bulunmamaktadır.
  - *İhlal:* `auth.py` içinde Redis'ten deserialize edilen dict, `db.merge(user, load=False)` ile SQLAlchemy oturumuna zorla eklenmektedir. Bu durum, ilişkili alanlar okunduğunda asenkron ortamda `DetachedInstanceError` veya gizli DB sorgusu riskine yol açmaktadır.
* **Clean Code Değerlendirmesi:**  
  - Backend genelinde 4 farklı ve birbiriyle konuşmayan önbellekleme paradigması vardır:
    1. `FastAPICache` decorator'ı (`@cache`, sadece statik şemalar için),
    2. `read_cache.py` (MD5 parametre hash'li CQRS okuma modeli),
    3. `listing_cache_service.py` (ZSET + String tabanlı ilan önbelleği),
    4. `auth.py` (özel JSON tabanlı 15 dakikalık oturum önbelleği).
  - Bu parçalanmış yapı, tek bir varlık güncellendiğinde (örneğin kullanıcı bilgisi veya ilan durumu) hangi cache'in nasıl invalidate edileceği konusunda kör noktalara yol açmaktadır.
* **Endüstriyel Pratikler & Eşzamanlılık (Concurrency):**  
  - **Weak ETag Normalizasyon Eksikliği (RFC 7232):** `ETagMiddleware`, `If-None-Match` doğrulaması yaparken `W/` zayıf ETag önekini ayıklamamaktadır. Nginx veya Cloudflare devreye girdiğinde zayıf ETag üretildiği için eşitlik (`==`) asla sağlanamaz ve 304 Not Modified yanıtı tamamen çalışmaz hale gelir.
  - **Post-Computation ETag Maliyeti:** ETag hesaplaması tüm veritabanı sorguları, ORM serileştirmeleri ve API iş mantığı bittikten sonra en dış middleware'de yapılmaktadır. Bu durum ağ çıkış (egress) trafiğini optimize etse de, arka uç CPU ve veritabanı yükünü %0 oranında düşürür.
  - **Thundering Herd / Cache Stampede Korumasızlığı:** `read_cache.py` içinde bir anahtarın TTL'i dolduğunda veya silindiğinde, aynı anda gelen yüzlerce istek DB'ye aynı anda hücum eder (Single-Flight veya Distributed Lock/Mutex yoktur).
  - **O(N) `redis.scan_iter` Tehlikesi:** `invalidate_cache(namespace)` fonksiyonu Redis üzerinde `scan_iter("cqrs:namespace:*")` çalıştırmaktadır. On binlerce anahtarın olduğu üretim ortamında bu işlem Redis ağ trafiğini ve CPU'sunu kilitler.

---

### 1.3 Katman 3: Veritabanı & Kalıcı Depolama (PostgreSQL, ClickHouse, PgBouncer)
* **PostgreSQL & PgBouncer Prepared Statement Cache:**  
  - `backend/app/database.py` dosyasında `use_pgbouncer=True` olduğunda:
    `prepared_statement_cache_size: 0` ve `statement_cache_size: 0` olarak set edilmiştir.
  - *Mimari Etki:* PgBouncer transaction pooling modunda çalıştığı için prepared statement çakışmalarını önlemek adına bu ayar zorunludur; ancak veritabanı motorunun her gelen SQL ifadesini baştan ayrıştırmasına (parsing) ve planlamasına (planning) neden olarak DB CPU maliyetini artırmaktadır.
* **ClickHouse Redis Write-Behind Buffering (`database_clickhouse.py`):**  
  - Telemetri ve analitik olayları doğrudan ClickHouse'a yazılmak yerine Redis `ch_buf:{table}` listelerine atılmakta ve arka planda 30 saniyede bir toplu (batch) flush edilmektedir.
  - *Endüstriyel Değerlendirme:* MergeTree part sayısını azaltmak ve disk I/O'sunu korumak için mükemmel bir desendir. Ancak **Read-Your-Own-Writes** tutarlılığı yoktur; bir kullanıcı ilan tıkladıktan veya dwell time ürettikten sonraki 30 saniye boyunca ClickHouse analitik sorguları bu veriyi göremez (30 saniyelik körlük penceresi).
* **MinIO Presigned URL Önbelleklemesi:**  
  - DM medyası için üretilen presigned URL'ler Redis'te 6 gün önbelleklenmektedir (`_PRESIGN_TTL = 7 gün`). İstemci tarafında `cacheKey` URL'in kendisine bağlandığında, 6. gün sonunda presigned URL değiştiği an istemci diski yeni dosya indirerek önbellek ısrafına yol açmaktadır.

---

### 1.4 Katman 4: Çapraz Katman Senkronizasyonu & Tutarlılık (Cross-Layer Coherency)
Sistemdeki en büyük mimari zaaf, katmanlar arasındaki önbellek yaşam döngülerinin birbirini tetiklememesidir (Loose Coupling Desync):
1. Veritabanında bir ilanın fiyatı veya durumu değiştiğinde (`status = PASSIVE`), PostgreSQL güncellenir.
2. `listing_cache_service.py` Redis'teki kaydı siler.
3. Ancak mobil istemcinin yerel Hive diskinde saklanan `cache_feed` veya `entity_listing_{id}` kaydı 15 dakika ile 2 saat arasında yaşamaya devam eder.
4. İstemciye bir **WebSocket Cache Invalidation Event** gönderilmediği için mobil kullanıcı pasif ilana tıklayıp checkout hatası alana kadar verinin güncelliğinden haberdar olamaz.

---

## 📌 2. Uçtan Uca Önceliklendirme ve Özet Tablosu

| ID | Seviye | Katman | Bileşen / Dosya | Zaaf / Hata Türü | Etki Alanı | Durum |
| :---: | :---: | :---: | :--- | :--- | :--- | :---: |
| **CACHE-01** | 🔴 **P0** | **Client** | `cache_service.dart` | Şifrelemesiz (Plaintext) Disk Depolaması & Finansal/PII Açığı | Cüzdan, bakiye, DM ve profil verisinin sızması | ✅ `47c4db17` · 2026-11-09 |
| **CACHE-02** | 🔴 **P0** | **Client** | `storage_service.dart` & `api_service.dart` | Kullanıcı İzolasyonu Yokluğu (User-Scoped Key Eksikliği) | Hesap değişiminde Kullanıcı B'nin Kullanıcı A bakiyesini görmesi | ⏳ Açık |
| **CACHE-03** | 🔴 **P0** | **Client** | `storage_service.dart` & `offline_queue_service.dart` | Eksik Logout Temizliği & Offline Mesajın Başkası Adına Gitmesi | `searchCache`, `_likeCache` ve offline mesaj sızıntısı | ⏳ Açık |
| **CACHE-04** | 🔴 **P0** | **Client** | `TeqlifCacheManager` & UI Ekranları | Statik `cacheKey: 'user_${id}_avatar'` Nedeniyle Avatar Kilitlenmesi | Profil resmi değişmesine rağmen 48 saat eski resmin görünmesi | ⏳ Açık |
| **CACHE-05** | 🟠 **P1** | **Backend** | `etag_middleware.py` | ETag Doğrulamasında `strip('W/')` Eksikliği (Weak ETag Incompatibility) | Reverse proxy (Nginx/Cloudflare) arkasında 304'ün çalışmaması | ⏳ Açık |
| **CACHE-06** | 🟠 **P1** | **Client** | `api_service.dart` | Yanlış SWR Mantığı (`if (!cached.isStale) return`) | Arka plan yenilemenin engellenmesi, bayat veri kalıcılığı | ⏳ Açık |
| **CACHE-07** | 🟠 **P1** | **Client** | `api_service.dart` | Cache Yayını Sonrası 401/403/404 Hatalarının Yutulması | Banlanan veya silinen hesabın/ilanın cache'te asılı kalması | ⏳ Açık |
| **CACHE-08** | 🟠 **P1** | **Client** | `message_repository.dart` | `_patchCache` İçinde Kilitsiz Read-Modify-Write Yarış Durumu | Eşzamanlı gelen WebSocket mesajlarının birbirini ezmesi | ⏳ Açık |
| **CACHE-09** | 🟠 **P1** | **Client** | `home_repository.dart` vs `api_service.dart` | Çift Başlı Cache Mimarisi (`homeCache` vs `api_cache`) & ETag Baypası | Veri duplikasyonu, merkezi SWR ve ETag mekanizmasının çiğnenmesi | ⏳ Açık |
| **CACHE-10** | 🟡 **P2** | **Client** | `listing_detail_screen.dart` & `swipe_live_screen.dart` | View Katmanından Doğrudan `clearData()` Çağrısı (ADR §8 İhlali) | UI'ın önbellek anahtarlarını ve veri katmanını bilmesi | ⏳ Açık |
| **CACHE-11** | 🟡 **P2** | **Client** | `cache_service.dart` | Yanıltıcı LRU (Aslında FIFO) ve Çalışma Zamanında Sınırsız Büyüme | Aktif kayıtların erken silinmesi, uzun oturumlarda bellek şişmesi | ⏳ Açık |
| **CACHE-12** | 🟡 **P2** | **Client** | `cache_service.dart` | Ana UI İş Parçacığında (UI Isolate) Senkron `jsonDecode` Blokajı | Feed ve mesaj listeleri yüklenirken frame düşmesi (UI Jank) | ⏳ Açık |
| **CACHE-13** | 🟡 **P2** | **Client** | `api_service.dart` | HTTP 304 Durumunda Tüm Body'nin Yeniden Serialize Edilmesi | Gereksiz disk yazma I/O'su ve ETag kaybı | ⏳ Açık |
| **CACHE-14** | 🟡 **P2** | **Client** | `api_service.dart` | Sunucu `Cache-Control` (`no-store`, `no-cache`) Direktiflerinin Yoksayılması | Sunucunun saklama dediği verinin istemcide zorla diske yazılması | ⏳ Açık |
| **CACHE-15** | 🟢 **P3** | **Client** | `api_service.dart` | Uçuşan İsteklerin Birleştirilmemesi (In-flight Request Coalescing Yokluğu) | Aynı anda açılan bileşenlerde paralel mükerrer HTTP GET çağrıları | ⏳ Açık |
| **CACHE-16** | 🟠 **P1** | **Backend** | `read_cache.py` & `routers/` | Dağıtık Cache Parçalanması ve Merkezi Cache Manager Eksikliği | Tutarsız TTL'ler, dağınık Redis erişimi ve mimari kirlilik | ⏳ Açık |
| **CACHE-17** | 🟠 **P1** | **Backend** | `read_cache.py` | CQRS Read Cache'te Cache Stampede / Thundering Herd Açığı | Cache süresi dolduğunda binlerce isteğin aynı anda DB'yi vurması | ⏳ Açık |
| **CACHE-18** | 🟠 **P1** | **Backend** | `read_cache.py` | `invalidate_cache` İçinde O(N) `redis.scan_iter` ile Redis Blokajı | Yüksek anahtar hacminde Redis CPU'sunun kilitlenmesi | ⏳ Açık |
| **CACHE-19** | 🟠 **P1** | **Backend** | `auth.py` | Redis Session Cache Deserializasyonunda `db.merge(load=False)` Riskleri | DetachedInstanceError ve ilişkili alanlarda asenkron crash | ⏳ Açık |
| **CACHE-20** | 🟡 **P2** | **Backend** | `etag_middleware.py` | Post-Computation ETag Nedeniyle DB ve CPU Tasarrufu Sağlanamaması | Her istekte DB sorgusu ve ORM çalışması, 0 CPU tasarrufu | ⏳ Açık |
| **CACHE-21** | 🟡 **P2** | **DB** | `database_clickhouse.py` | Write-Behind Tamponlamada 30 Saniyelik Körlük (Read Lag) | Canlı analitik ve son 30 saniyelik tıklamaların okunamaması | ⏳ Açık |
| **CACHE-22** | 🟡 **P2** | **DB** | `database.py` & PgBouncer | `prepared_statement_cache_size: 0` Nedeniyle SQL Parse Yükü | Her sorgunun DB CPU'sunda tekrar tekrar planlanması | ⏳ Açık |
| **CACHE-23** | 🟠 **P1** | **Cross** | Client ↔ Backend ↔ DB | Event-Driven Cache Invalidation (WebSocket Push) Yokluğu | DB'de değişen ilanın mobilde 30 dk bayat kalması (Desync) | ⏳ Açık |

---

## 🔍 3. Detaylı Bulgular ve Somut Çözüm Reçeteleri

---

### CACHE-01 · 🔴 P0 (Kritik) · Şifrelemesiz (Unencrypted Plaintext) Disk Depolaması & Finansal/PII Açığı

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/cache_service.dart` (Satır 26–30)
* **İlgili Standart:** OWASP Mobile Top 10 (M2: Inadequate Data Protection, M9: Insecure Data Storage)

#### Kök Neden ve Problem Analizi
`CacheService.init()` metodu, `api_cache` Hive kutusunu herhangi bir şifreleme anahtarı (`HiveAesCipher`) sağlamadan açmaktadır. Cüzdan bakiyesi ve transfer dökümleri (`user_wallet_data`), özel kullanıcı mesajları (`cache_messages`, `cache_chat_*`), kimlik bilgileri (`cache_profile`) ve bekleyen giden mesajlar (`offline_messages_queue`) cihaz diskinde **düz metin JSON** olarak saklanır. Rootlu Android, jailbreak'li iOS veya cihaz yedeklerinde (adb/backup) bu veriler doğrudan okunabilir.

#### Çözüm Reçetesi
`FlutterSecureStorage` (Android Keystore / iOS Keychain) içinde rastgele üretilen 256-bit bir şifreleme anahtarı saklanmalı ve `Hive.openBox` bu anahtarla açılmalıdır:

```dart
// mobile/lib/services/cache_service.dart
static const _kEncryptionKeyName = 'teqlif_hive_encryption_key';

static Future<void> init() async {
  await Hive.initFlutter();
  final keyBytes = await _getOrCreateEncryptionKey();
  _box = await Hive.openBox<String>(
    _boxName,
    encryptionCipher: HiveAesCipher(keyBytes),
  );
  await _migrate();
}

static Future<List<int>> _getOrCreateEncryptionKey() async {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final existing = await secureStorage.read(key: _kEncryptionKeyName);
  if (existing != null) return base64Decode(existing);
  final key = Hive.generateSecureKey();
  await secureStorage.write(key: _kEncryptionKeyName, value: base64Encode(key));
  return key;
}
```

---

### CACHE-02 · 🔴 P0 (Kritik) · Kullanıcı İzolasyonu Yokluğu (User-Scoped Cache Key Eksikliği)

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosyalar:** `mobile/lib/services/storage_service.dart`, `mobile/lib/services/wallet_service.dart`, `mobile/lib/repositories/message_repository.dart`

#### Kök Neden ve Problem Analizi
Kullanıcıya özel olan veriler (`user_wallet_data`, `cache_messages`, `cache_profile`, `cache_chat_${otherUserId}`), anahtarlarında aktif kullanıcı kimliği (`currentUserId`) barındırmayan genel stringlerle saklanmaktadır. Kullanıcı A oturumu kapatıp aynı cihazda Kullanıcı B oturum açtığında, SWR ilk frame'de Kullanıcı A'nın cüzdan bakiyesini ve DM konuşmalarını Kullanıcı B'nin ekranına basmaktadır.

#### Çözüm Reçetesi
Tüm kullanıcı bağımlı önbellek anahtarları aktif kullanıcının ID'si ile namespace'lenmelidir:

```dart
// mobile/lib/services/storage_service.dart
static String userScopedKey(String baseKey) {
  final uid = currentUserIdSync ?? 'anon';
  return 'u_${uid}_$baseKey';
}

static String cacheThreadKey(int otherUserId) {
  final uid = currentUserIdSync ?? 'anon';
  return 'u_${uid}_chat_$otherUserId';
}
```

---

### CACHE-03 · 🔴 P0 (Kritik) · Eksik Logout Temizliği & Offline Mesajın Başkası Adına Gitmesi

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosyalar:** `mobile/lib/services/storage_service.dart`, `mobile/lib/services/offline_queue_service.dart`

#### Kök Neden ve Problem Analizi
`StorageService.clear()` oturum kapatıldığında sadece `homeCache` ve `api_cache` kutularını silmektedir. `offline_messages_queue`, `searchCache`, `ListingService._likeCache` ve `_cachedAvatarUrl` silinmez. Kullanıcı A çevrimdışıyken mesaj gönderip oturumu kapattığında, Kullanıcı B oturum açıp internet geldiğinde Kullanıcı A'nın mesajı **Kullanıcı B'nin oturum token'ı ile** alıcıya iletilmektedir.

#### Çözüm Reçetesi
`StorageService.clear()` tüm yerel kutuları ve bellek içi durumları temizlemelidir:

```dart
static Future<void> clear() async {
  _cachedToken = null;
  _cachedRefreshToken = null;
  _cachedAvatarUrl = null;
  ListingService.clearLikeCache();
  
  await Future.wait([
    _secureStorage.deleteAll(),
    SharedPreferences.getInstance().then((p) => p.clear()),
    _clearAllLocalBoxes(),
  ]);
}

static Future<void> _clearAllLocalBoxes() async {
  try {
    final boxesToClear = ['homeCache', 'api_cache', 'searchCache', 'offline_messages_queue'];
    for (final name in boxesToClear) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).clear();
      } else {
        final b = await Hive.openBox(name);
        await b.clear();
      }
    }
  } catch (_) {}
}
```

---

### CACHE-04 · 🔴 P0 (Kritik) · Statik CacheKey Nedeniyle Avatar Kilitlenmesi (Stale Avatar Bug)

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosyalar:** `image_cache_manager.dart` ve 40+ UI ekranı
* **İlgili Satırlar:** `image_cache_manager.dart:15`, `follow_list_screen.dart:81`

#### Kök Neden ve Problem Analizi
Uygulama genelinde avatarlar `cacheKey: 'user_${userId}_avatar'` ile `TeqlifCacheManager` üzerinden yüklenmektedir. Yöneticinin disk saklama süresi **2 gündür**. Kullanıcı profil fotoğrafını değiştirdiğinde URL değişse dahi, diskteki anahtar değişmediği için `CachedNetworkImage` diskteki eski resmi 48 saat boyunca ekranda tutar.

#### Çözüm Reçetesi
Statik anahtar kaldırılmalı ve önbellek URL hash'ine bağlanmalıdır:

```dart
String avatarCacheKey(int userId, String? url) {
  if (url == null || url.isEmpty) return 'user_${userId}_avatar_empty';
  return 'user_${userId}_avatar_${url.hashCode}';
}
```

---

### CACHE-05 · 🟠 P1 (Yüksek) · ETag Doğrulamasında `strip('W/')` Eksikliği (Weak ETag Incompatibility)

* **Katman:** Backend (FastAPI / Middleware)
* **Etkilenen Dosya:** `backend/app/security/etag_middleware.py` (Satır 28–31)
* **İlgili Standart:** RFC 7232 Section 2.3 & 3.2

#### Kök Neden ve Problem Analizi
Middleware `If-None-Match` eşleşmesini katı string eşitliğiyle yapmaktadır:
```python
etag = f'"{hashlib.md5(body, usedforsecurity=False).hexdigest()}"'
if request.headers.get("if-none-match") == etag:
    return Response(status_code=304, headers={"etag": etag})
```
Nginx, Cloudflare veya Starlette GZip devreye girdiğinde ETag'in başına `W/` eklenir (`W/"hash"`). Python'daki string kontrolü `W/` önekini temizlemediği için eşleşme hiçbir zaman sağlanamaz ve istemciye sürekli `200 OK` dönerek tüm bant genişliği tasarrufu çöker.

#### Çözüm Reçetesi
RFC 7232 standardı gereği zayıf ETag önekini normalize eden karşılaştırma yapılmalıdır:

```python
# backend/app/security/etag_middleware.py
def _normalize_etag(tag: str | None) -> str:
    if not tag:
        return ""
    tag = tag.strip()
    if tag.startswith("W/"):
        tag = tag[2:]
    return tag.strip('"')

client_etag = request.headers.get("if-none-match")
if _normalize_etag(client_etag) == _normalize_etag(etag):
    return Response(status_code=304, headers={"etag": etag})
```

---

### CACHE-06 · 🟠 P1 (Yüksek) · Yanlış SWR Mantığı (`if (!cached.isStale) return`)

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/api_service.dart` (Satır 71–82)
* **İlgili Standart:** RFC 5861

#### Kök Neden ve Problem Analizi
`ApiService.get` içinde önbellek taze ise (`!cached.isStale`) fonksiyondan `return` edilerek çıkılmaktadır. Bu davranış gerçek bir **SWR** değil, **TTL Cache-First** yaklaşımıdır. Veri taze ise arka plan revalidation çağrısı hiç yapılmaz; kullanıcı 14 dakika önceki bayat veriyi görmeye devam eder.

#### Çözüm Reçetesi
Erken dönüş (`return`) kaldırılmalı; önbellek anında emit edildikten sonra ağ çağrısı arka planda her zaman sessizce çalışıp ETag ile sunucudan teyit almalıdır.

---

### CACHE-07 · 🟠 P1 (Yüksek) · Cache Yayını Sonrası 401/403/404 Hatalarının Sessizce Yutulması

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/api_service.dart` (Satır 124–149)

#### Kök Neden ve Problem Analizi
Önbellek ekrana verildikten sonra (`cacheYielded == true`), arkadan gelen ağ isteğinde `401 Unauthorized` (oturum düşmesi), `403 Forbidden` (kullanıcı banlanması) veya `404 Not Found` (ilanın silinmesi) alınırsa bu hatalar yutulmaktadır. UI kullanıcının banlandığını veya ilanın silindiğini anlayamaz; kullanıcı bayat cache içinde asılı kalır.

#### Çözüm Reçetesi
Ağ kesintisi hataları yutulmalı, ancak HTTP 4xx durumları kesinlikle fırlatılmalı ve geçersiz cache temizlenmelidir:

```dart
if (resp.statusCode == 401) {
  await StorageService.clear();
  throw const UnauthorizedException();
} else if (resp.statusCode == 404 && cacheKey != null) {
  await _cache.clearData(cacheKey);
  throw const NotFoundException();
} else if (!cacheYielded) {
  throw AppException(...);
}
```

---

### CACHE-08 · 🟠 P1 (Yüksek) · `_patchCache` İçinde Kilitsiz Read-Modify-Write Yarış Durumu

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/repositories/message_repository.dart` (Satır 157–169)

#### Kök Neden ve Problem Analizi
WebSocket üzerinden art arda iki mesaj geldiğinde, iki asenkron işlem aynı anda Hive'dan mesaj listesini okur, yeni mesajı ekler ve yazar. Eşzamanlı iki yazma birbirini ezerek sessizce mesaj kaybına yol açar.

#### Çözüm Reçetesi
Thread bazında sıralı çalışan bir `AsyncLock` veya `SerialQueue` eklenmelidir:

```dart
static final Map<int, Future<void>> _threadLocks = {};

Future<void> _patchCache(int otherUserId, ...) async {
  final prevLock = _threadLocks[otherUserId] ?? Future.value();
  final completer = Completer<void>();
  _threadLocks[otherUserId] = completer.future;

  try {
    await prevLock;
    // Oku -> Değiştir -> Yaz
    final raw = _cache.getWithStaleness(StorageService.cacheThreadKey(otherUserId))?.data;
    if (raw == null) return;
    final current = (raw as List).cast<Map<String, dynamic>>();
    await _cache.saveData(
      StorageService.cacheThreadKey(otherUserId),
      fn(List.from(current)),
      ttl: const Duration(minutes: 30),
    );
  } finally {
    completer.complete();
  }
}
```

---

### CACHE-09 · 🟠 P1 (Yüksek) · Çift Başlı Cache Mimarisi (`homeCache` vs `api_cache`) & ETag Baypası

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/repositories/home_repository.dart` (Satır 36–105)

#### Kök Neden ve Problem Analizi
`HomeRepository` bağımsız bir `homeCache` kutusu açmakta, ham `http.get` ile doğrudan ağ çağrısı yapmakta ve merkezi `ApiService`'in ETag (304), timeout ve hata yönetimi mekanizmalarını baypas etmektedir.

#### Çözüm Reçetesi
`HomeRepository` ham `http.get` yerine `ApiService.get` kullanacak şekilde refactor edilmeli ve `homeCache` kutusu merkezi `api_cache` varlık deposu ile birleştirilmelidir.

---

### CACHE-10 · 🟡 P2 (Orta) · View Katmanından Doğrudan `clearData()` Çağrısı (ADR §8 İhlali)

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosyalar:** `mobile/lib/screens/listing_detail_screen.dart`, `mobile/lib/screens/live/swipe_live_screen.dart`

#### Kök Neden ve Problem Analizi
UI widget sınıfları doğrudan `ref.read(cacheServiceProvider).clearData('user_wallet_data')` çağırmaktadır. Bu durum Clean Architecture ve ADR §8 (MVVM) prensiplerini ihlal eder; UI katmanı veri katmanının anahtar adlarını ve cache mekanizmalarını bilmemelidir.

#### Çözüm Reçetesi
Önbellek iptali ilgili ViewModel veya Repository metodunun (örneğin `WalletRepository.invalidateBalance()`) içine kapsüllenmelidir.

---

### CACHE-11 · 🟡 P2 (Orta) · Yanıltıcı LRU (Aslında FIFO) ve Çalışma Zamanında Sınırsız Büyüme

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/cache_service.dart` (Satır 168–189)

#### Kök Neden ve Problem Analizi
`clearExpired()` 200 anahtar sınırını aşınca `_t` (kayıt oluşturulma zamanı) alanına göre sıralama yapıp siler. Bu bir **LRU değil, FIFO** politikasıdır; sık okunan eski kayıtlar silinirken az okunan yeni kayıtlar tutulur. Ayrıca tahliye sadece uygulama açılışında bir kez çalışır; uygulama saatlerce açık kaldığında `saveData` sınır kontrolü yapmadığı için Hive bellekte kontrolsüz büyüyebilir.

#### Çözüm Reçetesi
Kayıt zarfına son erişim zamanı (`_last_read`) eklenmeli ve her 20 yazma işleminde bir arka planda debounced temizlik tetiklenmelidir.

---

### CACHE-12 · 🟡 P2 (Orta) · Ana UI İş Parçacığında (UI Isolate) Senkron `jsonDecode` Blokajı

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/cache_service.dart` (Satır 46–64)

#### Kök Neden ve Problem Analizi
Hive kutusu `Box<String>` olarak kullanıldığından, her `getData()` çağrısında `jsonDecode(raw)` işlemi ana iş parçacığında senkron çalıştırılır. Yüzlerce kilobaytlık feed veya mesaj JSON'ları widget `build()` anında ana iş parçacığını bloke ederek ekranda takılmalara (UI jank) yol açar.

#### Çözüm Reçetesi
Büyük JSON yükleri arka plan isolate'ine (`compute(jsonDecode, ...)`) taşınmalı veya Hive binary TypeAdapter serileştirmesine geçilmelidir.

---

### CACHE-13 · 🟡 P2 (Orta) · HTTP 304 Durumunda Tüm Body'nin Yeniden Serialize Edilmesi

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/api_service.dart` (Satır 99–111)

#### Kök Neden ve Problem Analizi
Sunucu `304 Not Modified` döndüğünde `_cache.saveData` çağrılarak tüm JSON nesnesi baştan sona tekrar serialize edilip diske yazılmaktadır. Ayrıca sunucudan gelen yeni ETag (`resp.headers['etag']`) yerine eski ETag saklanmaktadır.

#### Çözüm Reçetesi
Veri gövdesini tekrar diske yazmak yerine sadece timestamp (`_t`) ve varsa yeni ETag güncellenmelidir.

---

### CACHE-14 · 🟡 P2 (Orta) · Sunucu `Cache-Control` Direktiflerinin Yoksayılması

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/api_service.dart` (Satır 113–123)

#### Kök Neden ve Problem Analizi
`ApiService.get`, sunucunun döndürdüğü `Cache-Control: no-store` veya `no-cache` başlıklarını dikkate almaz; istemci kodunda `cacheKey` geçilmişse veriyi zorla diske yazar.

#### Çözüm Reçetesi
Yanıt başlığında `no-store` varsa `cache.saveData` adımı atlanmalıdır.

---

### CACHE-15 · 🟢 P3 (Düşük) · Uçuşan İsteklerin Birleştirilmemesi (In-flight Request Coalescing Yokluğu)

* **Katman:** Client (Mobile Flutter)
* **Etkilenen Dosya:** `mobile/lib/services/api_service.dart`

#### Kök Neden ve Problem Analizi
Aynı ekranda iki ayrı bileşen aynı `cacheKey` ve URL için SWR başlattığında iki paralel HTTP GET isteği fırlatılır (Cache Stampede). Uçuşan istekleri tek bir `Future` altında birleştiren deduplication mekanizması eksiktir.

---

### CACHE-16 · 🟠 P1 (Yüksek) · Dağıtık Cache Parçalanması ve Merkezi Cache Manager Eksikliği

* **Katman:** Backend (FastAPI / Architecture)
* **Etkilenen Dosyalar:** `backend/app/core/read_cache.py`, `backend/app/utils/schema_cache.py`, `backend/app/services/feed/listing_cache_service.py`, `backend/app/utils/auth.py`

#### Kök Neden ve Problem Analizi
Backend üzerinde 4 farklı ve birbirinden izole caching deseni çalışmaktadır:
1. `FastAPICache` (`@cache` decorator'ı ile Redis üzerinde `teqlif:cache:*`),
2. `read_cache.py` (CQRS okuma modelleri için `cqrs:*`),
3. `listing_cache_service.py` (İlanlar için `listing:*` ve `feed:recent`),
4. `auth.py` (Kullanıcı oturumları için `session:user:*`).
Merkezi bir `CacheManager` veya `CachePort` arayüzü bulunmadığından; TTL'ler, serialization formatları, hata yönetimi ve invalidation politikaları parçalanmış durumdadır.

#### Çözüm Reçetesi
Backend'de Clean Architecture standartlarına uygun tekil bir `CacheService` / `CachePort` soyutlaması oluşturulmalı ve tüm servisler bu port üzerinden Redis'e erişmelidir.

---

### CACHE-17 · 🟠 P1 (Yüksek) · CQRS Read Cache'te Cache Stampede / Thundering Herd Açığı

* **Katman:** Backend (FastAPI / Redis)
* **Etkilenen Dosya:** `backend/app/core/read_cache.py` (Satır 44–69)

#### Kök Neden ve Problem Analizi
`cache_get` fonksiyonu cache miss durumunda `None` döner. Yüksek trafikli bir endpoint'te (örneğin ana sayfa arama veya popüler ilanlar) cache süresi dolduğu an, aynı milisaniyede gelen 500 eşzamanlı istek aynı anda `cache_get(...) == None` alır ve tamamı veritabanına aynı SQL sorgusunu fırlatır (Thundering Herd / Cache Stampede).

#### Çözüm Reçetesi
Distributed Mutex / Single-Flight deseni uygulanmalıdır. Anahtar süresi dolduğunda sadece tek bir worker DB'ye gitmeli, diğer eşzamanlı istekler bu sonucu beklemelidir:

```python
# backend/app/core/read_cache.py
import asyncio

async def cache_get_or_compute(namespace: str, params: dict, compute_fn, ttl: int = 30):
    cached = await cache_get(namespace, params)
    if cached is not None:
        return cached

    redis = await get_redis()
    lock_key = f"lock:{namespace}:{_make_params_hash(params)}"
    # 5 saniyelik atomik kilit edin
    acquired = await redis.set(lock_key, "1", nx=True, ex=5)
    
    if acquired:
        try:
            result = await compute_fn()
            await cache_set(namespace, params, result, ttl=ttl)
            return result
        finally:
            await redis.delete(lock_key)
    else:
        # Kilit başka bir worker'da; kısa bekle ve tekrar cache'ten oku
        await asyncio.sleep(0.05)
        return await cache_get(namespace, params) or await compute_fn()
```

---

### CACHE-18 · 🟠 P1 (Yüksek) · `invalidate_cache` İçinde O(N) `redis.scan_iter` ile Redis Blokajı

* **Katman:** Backend (FastAPI / Redis)
* **Etkilenen Dosya:** `backend/app/core/read_cache.py` (Satır 71–86)

#### Kök Neden ve Problem Analizi
İlan güncellendiğinde çağrılan `invalidate_cache`:
```python
pattern = f"{_PREFIX}:{namespace}:*"
keys = [k async for k in redis.scan_iter(pattern)]
if keys:
    await redis.delete(*keys)
```
Üretim ortamında milyonlarca arama ve filtreleme varyasyonu Redis'e yazıldığında, `scan_iter` işlemi yüzlerce ağ gidiş-dönüşü (round-trip) yapar ve tek iş parçacıklı Redis sunucusunda I/O tıkanıklığı yaratır.

#### Çözüm Reçetesi
Pattern tabanlı O(N) arama yerine, **Tag/Namespace Versioning** deseni uygulanmalıdır:
Her namespace için Redis'te bir versiyon anahtarı tutulur (`ns_ver:{namespace}`). Cache anahtarı üretilirken bu versiyon kullanılır (`cqrs:{namespace}:v{version}:{hash}`). Invalidate etmek için tek bir `redis.incr("ns_ver:" + namespace)` çağrısı yeterlidir; O(1) maliyetle tüm eski anahtarlar yetim kalır ve TTL'leri dolunca otomatik silinir.

---

### CACHE-19 · 🟠 P1 (Yüksek) · `auth.py` Session Cache Deserializasyonunda `db.merge(load=False)` Riskleri

* **Katman:** Backend (FastAPI / SQLAlchemy)
* **Etkilenen Dosya:** `backend/app/utils/auth.py` (Satır 145–175)

#### Kök Neden ve Problem Analizi
`auth.py` içinde kullanıcı session cache'ten çekildiğinde:
```python
user = User(**data)
return await db.merge(user, load=False)
```
yapılmaktadır.
1. `load=False` kullanıldığı için kullanıcının ilişkili modelleri (örneğin roller, mağaza bilgisi, ayarlar) SQLAlchemy oturumuna yüklenmez.
2. İş akışı içinde bir servis bu ilişkiye eriştiğinde asenkron ortamda `DetachedInstanceError` fırlatılır.
3. Ayrıca `User` tablosundaki bir alan (örneğin bakiye veya telefon onayı) güncellendiğinde `invalidate_user_session_cache` unutulursa, kullanıcı 15 dakika boyunca bayat oturum bilgisiyle işlem yapar (SRE-146 kök nedeni).

#### Çözüm Reçetesi
Kullanıcı kimlik doğrulama oturumu tam bir SQLAlchemy ORM nesnesi olarak merge edilmek yerine, hafif bir Pydantic Value Object (`CurrentUserDTO`) olarak dönmeli; veritabanı mutasyonları gerektiğinde taze ORM nesnesi çekilmelidir.

---

### CACHE-20 · 🟡 P2 (Orta) · Post-Computation ETag Nedeniyle DB ve CPU Tasarrufu Sağlanamaması

* **Katman:** Backend (FastAPI / Architecture)
* **Etkilenen Dosya:** `backend/app/security/etag_middleware.py`

#### Kök Neden ve Problem Analizi
`ETagMiddleware`, yanıt gövdesini oluşturulduktan sonra yakalar ve MD5 hash'ini hesaplar. İstemci `If-None-Match` başlığı gönderip 304 alsa dahi; FastAPI tüm DB sorgularını yapmış, ORM modellerini çalıştırmış ve JSON üretmiştir. Bu durum sadece bant genişliğini korur; sunucu CPU ve DB yükünü azaltmaz.

#### Çözüm Reçetesi
Kritik ve yüksek trafikli GET sorguları (örneğin katalog veya kullanıcı profili) için, DB'ye gitmeden önce bir versiyon veya `updated_at` kontrolü yapılarak erken 304 dönülmelidir.

---

### CACHE-21 · 🟡 P2 (Orta) · ClickHouse Write-Behind Tamponlamada 30 Saniyelik Körlük (Read Lag)

* **Katman:** Database & Analytics (ClickHouse / Redis)
* **Etkilenen Dosya:** `backend/app/database_clickhouse.py` (Satır 33–42)

#### Kök Neden ve Problem Analizi
Kullanıcı tıklama ve dwell time olayları Redis `ch_buf:*` listelerine yazılmakta ve `_flush_loop` ile 30 saniyede bir ClickHouse'a aktarılmaktadır. Ancak gerçek zamanlı analitik ekranları doğrudan ClickHouse'a `SELECT` attığı için son 30 saniyedeki veriler raporda görünmemektedir (Eventual Consistency penceresi).

#### Çözüm Reçetesi
Gerçek zamanlı görünürlük gerektiren kritik metrikler için (örneğin canlı yayın anlık izleyici veya açık artırma teklifleri), sorgu anında Redis buffer'ındaki eleman sayısı `LLEN` ile okunup ClickHouse sonucuna eklenmelidir.

---

### CACHE-22 · 🟡 P2 (Orta) · `prepared_statement_cache_size: 0` Nedeniyle SQL Parse Yükü

* **Katman:** Database (PostgreSQL / PgBouncer)
* **Etkilenen Dosya:** `backend/app/database.py` (Satır 9–18)

#### Kök Neden ve Problem Analizi
PgBouncer transaction pooling modunda prepared statement çakışmalarını engellemek için asyncpg tarafında statement cache kapatılmıştır. Bu zorunlu bir güvenlik önlemidir ancak PostgreSQL'in her sorguyu tekrar derlemesine yol açar.

#### Çözüm Reçetesi
PgBouncer 1.21+ sürümünün sunduğu yerel prepared statement desteği (`max_prepared_statements`) devreye alınmalı veya PostgreSQL sunucusunda sık kullanılan şablonlar için plan önbelleklemesi optimize edilmelidir.

---

### CACHE-23 · 🟠 P1 (Yüksek) · Event-Driven Cache Invalidation (WebSocket Push) Yokluğu

* **Katman:** Cross-Layer (Client ↔ Backend ↔ DB)

#### Kök Neden ve Problem Analizi
Veritabanında bir ilanın fiyatı değiştiğinde veya ilan satıldığında, backend Redis'i temizler. Ancak mobil istemcinin Hive diskindeki kopya (15 dk – 2 saat TTL) yaşamaya devam eder. İstemci ile sunucu arasında önbellek geçersiz kılma olaylarını taşıyan bir haberleşme kanalı yoktur.

#### Çözüm Reçetesi
İlan durumu değiştiğinde backend mevcut WebSocket altyapısı üzerinden bir `cache_invalidate` eventi yayınlamalıdır:
```json
{
  "type": "cache_invalidate",
  "scope": "listing",
  "id": 12345
}
```
Mobil istemci bu eventi aldığında `CacheService.clearData('entity_listing_12345')` çağırarak anında önbelleği düşürmelidir.

---

## 📊 4. Güncellenmiş Uçtan Uca Cache Taksonomisi ve Topolojisi

```mermaid
flowchart TD
    subgraph Client ["Mobil İstemci (Flutter)"]
        UI["UI Widget Tree"]
        SWR["ApiService (SWR + ETag)"]
        SecureStore["FlutterSecureStorage (Encrypted)"]
        HiveBox["Hive api_cache (AES-256)"]
        ImgCache["TeqlifCacheManager (URL Hash Disk)"]
    end

    subgraph Backend ["Arka Uç (FastAPI Cluster)"]
        ETagMW["ETagMiddleware (Weak ETag Norm)"]
        AuthSvc["AuthService (Session Cache)"]
        CQRS["CQRS CacheService (Tag Versioning)"]
        Redis[("Redis Cluster")]
    end

    subgraph DB ["Veritabanı & Kalıcı Depolama"]
        PG[("PostgreSQL 17 (Shared Buffers)")]
        PgB["PgBouncer (Tx Pooling)"]
        CH[("ClickHouse (MergeTree)")]
        MinIO[("MinIO S3 (Presigned TTL)")]
    end

    UI -->|1. Oku| HiveBox
    UI -->|Görsel İsteği| ImgCache
    SWR -->|2. Arka Plan Revalidate| ETagMW
    ETagMW -->|304 / 200| SWR
    ETagMW --> AuthSvc
    AuthSvc -->|Session Oku/Yaz| Redis
    AuthSvc --> CQRS
    CQRS -->|Cache Miss / Tag Version| Redis
    CQRS --> PgB
    PgB --> PG
    Backend -->|Write-Behind Buffer (30s)| Redis
    Redis -->|Batch Flush| CH
    MinIO -.->|Presigned URL| ImgCache
```

### Uçtan Uca Veri Yaşam Döngüsü Tablosu (ADR §9)

| Veri Türü | Client Katmanı (Hive / Memory) | Backend Katmanı (Redis) | DB Katmanı (Postgres / ClickHouse) | İptal (Invalidation) Mekanizması |
| :--- | :--- | :--- | :--- | :--- |
| **Cüzdan & Bakiye** | `u_{uid}_wallet` (2 dk, Şifreli) | `session:user:{id}` (15 dk) | `users.teqlik_balance` | Para transferi, bakiye mutasyonu → DB commit + Redis del + Mobilde SWR revalidate |
| **Kullanıcı Profili** | `u_{uid}_profile` (15 dk, Şifreli)| `cqrs:user_profile:{username}` | `users` tablosu | Profil düzenleme → Redis del + ETag miss |
| **İlan Feed'i** | `entity_listing_{id}` (2 saat) | `listing:{id}` + `feed:recent` | `listings` tablosu | İlan güncelleme/silme → Redis zrem/del + WS invalidation push |
| **Canlı Yayınlar** | `cache_streams` (1–3 dk) | `live:viewer_set` + Stream state | `live_streams` tablosu | Yayın sonlanma WS eventi |
| **DM Sohbetleri** | `u_{uid}_chat_{otherId}` (30 dk) | `ch_buf:messages` (Buffer) | `direct_messages` tablosu | WS `message_received` → AsyncLock ile _patchCache |
| **Analitik & Tıklama**| Bellekte tutulmaz (anlık post)| `ch_buf:user_events` (30s buffer) | ClickHouse `user_events` | 30 saniyelik loop ile batch insert |
| **Katalog & Şemalar**| `api_cache` (24 saat) | `teqlif:cache:schema:v{ver}` | `categories` tablosu | Migration → `schema:static_version` bump |

---

## 🚀 5. Bütünsel Uygulama ve İyileştirme Yol Haritası

### Faz 1: P0 Güvenlik ve Veri Sızıntısı İyileştirmeleri (Acil)
1. **[CACHE-01]** `mobile/lib/services/cache_service.dart` içine `HiveAesCipher` şifrelemesinin entegre edilmesi.
2. **[CACHE-02]** Mobil cache anahtarlarının kullanıcı kimliği ile namespace'lenmesi (`u_{uid}_*`).
3. **[CACHE-03]** `StorageService.clear()` içine `offline_messages_queue`, `searchCache` ve bellek içi değişkenlerin temizliğinin eklenmesi.
4. **[CACHE-04]** `CachedNetworkImageProvider` çağrılarından statik `cacheKey`'in kaldırılarak URL hash'ine bağlanması (stale avatar hatası çözümü).

### Faz 2: P1 Mimari ve Protokol Düzeltmeleri
1. **[CACHE-05]** `backend/app/security/etag_middleware.py` içine zayıf ETag (`W/`) normalizasyonunun eklenmesi.
2. **[CACHE-06 & CACHE-07]** `mobile/lib/services/api_service.dart` içindeki `!isStale` early-return'ünün kaldırılması ve 401/403/404 HTTP hatalarının yutulmasının engellenmesi.
3. **[CACHE-08]** `mobile/lib/repositories/message_repository.dart` içine `_threadLocks` (AsyncLock) eklenerek mesaj ezilme yarış durumunun çözülmesi.
4. **[CACHE-17 & CACHE-18]** `backend/app/core/read_cache.py` içindeki `scan_iter`'ın Tag Versioning ile O(1)'e indirilmesi ve single-flight mutex eklenmesi.
5. **[CACHE-23]** WebSocket üzerinden `cache_invalidate` push mekanizmasının kurulması.

### Faz 3: P2/P3 Clean Architecture ve Performans İyileştirmeleri
1. **[CACHE-09 & CACHE-10]** UI'dan doğrudan yapılan `clearData()` çağrılarının Repository'lere taşınması; `HomeRepository`'nin merkezi `ApiService` ile birleştirilmesi (ADR §8 uyumu).
2. **[CACHE-11]** `CacheService.clearExpired()` algoritmasının FIFO'dan gerçek LRU'ya dönüştürülmesi.
3. **[CACHE-13]** 304 Not Modified durumunda tüm JSON'ın tekrar serialize edilmesinin önlenmesi.
4. **[CACHE-19]** `auth.py` içindeki `db.merge(load=False)` yapısının hafif Value Object modeline evrilmesi.
