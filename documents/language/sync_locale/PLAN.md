# Uçtan Uca Dil Senkronizasyonu (Sync Locale) Mimari Planı

Bu döküman, Teqlif uygulamasında kullanıcının dil tercihinin (Arapça, İngilizce, Türkçe, Rusça vb.) **Mobil İstemci (State & SharedPreferences)**, **Ağ Katmanı (HTTP Headers & API)**, **Arka Uç Veritabanı (PostgreSQL)** ve **Önbellek (Redis)** üzerinde %100 tutarlı ve kesintisiz şekilde senkronize edilmesini sağlayacak mimari analizi ve iyileştirme planını içerir.

---

## 🎯 Kök Neden Analizi: Neden Dil Tercihi Kayboluyor veya Eziyor?

Kullanıcının Ayarlar menüsünden Arapçadan İngilizceye geçtikten hemen sonra uygulamayı kapatıp açtığında arayüzün İngilizce yerine tekrar Arapça açılması sorunu, sistemin mevcut mimarisindeki 4 temel senkronizasyon zaafiyetinden kaynaklanmaktadır:

### 1. Ateşle ve Unut (Fire-and-Forget) Ağ İsteği Kesintisi
Mobil uygulamada `LocaleNotifier.setLocale(Locale('en'))` çağrıldığında, yeni dil kodu yerel bellek (`SharedPreferences`) üzerine anında yazılmaktadır. Ancak veritabanını güncellemek için arka uca gönderilen `PATCH /auth/me` (`{"locale": "en"}`) isteği **`.ignore()`** olarak işaretlenmiştir.
- Kullanıcı dili değiştirdikten hemen sonra uygulamayı kapattığında, ağ katmanındaki HTTP isteği işletim sistemi tarafından iptal edilir veya sunucuya ulaşamadan kesilir.
- Sonuç olarak cihazın yerel belleğinde `'en'` (İngilizce) kalırken, arka uç PostgreSQL veritabanında bir önceki başarılı istek olan `'ar'` (Arapça) kalır.

### 2. Başlangıçta (Startup) Tek Yönlü Koşulsuz Ezme (Override)
Uygulama yeniden açıldığında (`main.dart`), önce `SharedPreferences` okur ve arayüzü İngilizce başlatır. Ancak saniyeler içinde `SplashScreen` (`splash_screen.dart`) devreye girerek sunucudan profil bilgisini (`GET /auth/me`) çeker.
- Sunucu, veritabanında kalan (kesintiye uğrayan) eski değeri yani `locale: 'ar'` yanıtını döner.
- `SplashScreen` içindeki mantık, sunucudan gelen bu değeri koşulsuz şartsız doğru kabul ederek `setLocaleLocally(Locale('ar'))` çağrısı yapar. Bu çağrı hem Riverpod reaktif state'ini hem de cihazın `SharedPreferences` belleğini eski veritabanı değeriyle **ezer** ve arayüz aniden Arapçaya döner.

### 3. Eksik `Accept-Language` Başlıkları ve API Yan Etkileri
- **Başlık Eksikliği:** Projede `config/api.dart` içerisinde `buildApiHeaders()` metodu `'Accept-Language'` başlığını otomatik eklese de, mobil projedeki neredeyse tüm servis sınıfları (`AuthService._headers`, `AuctionService._headers`, `ListingService._headers`, `NotificationService._headers` vb.) kendi özel `_headers()` metodlarını tanımlamakta ve hiçbirinde `Accept-Language` başlığını göndermemektedir.
- **Tehlikeli Yan Etki (`POST /auth/device-tokens`):** Arka uçta bildirim ve arama token'larını kaydeden `/device-tokens` uç noktası, her çalıştığında `lang = get_locale(request=request)` çağrısı yapıp `if current_user.locale != lang:` koşuluyla veritabanındaki kullanıcı dilini ezmektedir. Mobil servisler bu isteğe `Accept-Language` eklemediği için, arka uç varsayılan dil olan `"tr"` (Türkçe) değerini değerlendirir ve sıradan bir token yenileme isteği kullanıcının veritabanındaki dilini sessizce değiştirebilir.

### 4. Redis Önbellek İnvalidasyon Eksikliği
- Arka uçta `get_current_user` her API isteğinde doğrudan PostgreSQL veritabanını sorgulamaktadır; kullanıcı oturumu için hızlı bir Redis cache katmanı bulunmamaktadır.
- Bununla birlikte, analitik, pazar trendleri ve öneri motoru gibi yoğun hesaplama gerektiren servislerde Redis önbellek anahtarları dile bağlı oluşturulmaktadır (Örn: `cache:market_trends_global_{locale}`, `cache:pro_insights:{uid}:{_locale}:...`). Kullanıcının dili PostgreSQL'de güncellense bile bu önbellekler temizlenmediği (invalidate edilmediği) için, kullanıcı dil değiştirdiğinde TTL süresi dolana kadar eski dildeki cache verilerini görmeye devam edebilir.

---

## 🏗️ Hedef Mimari ve Çözüm Yaklaşımı (To-Be Architecture)

Bu sorunları kalıcı olarak çözmek ve uçtan uca senkronizasyonu garanti altına almak için **Zaman Damgalı Akıllı Çift Yönlü Senkronizasyon (Timestamped Two-Way Sync)** mimarisine geçilecektir:

```mermaid
flowchart TD
    subdiagram [Mobil İstemci - Dil Değişimi]
    UI[Kullanıcı Dil Seçer: 'en'] --> NOTIF[LocaleNotifier.setLocale]
    NOTIF --> LOCAL_MEM[SharedPreferences:<br/>locale='en', updated_at=T1]
    NOTIF --> QUEUE[Güvenilir Ağ Kuyruğu / Retry]
    QUEUE -->|PATCH /auth/me| API[Backend API]
    
    subdiagram_backend [Backend & Redis Senkronizasyonu]
    API -->|if T1 > db.updated_at| DB[(PostgreSQL: users tablosu)]
    DB --> EVT[LanguageChangedEvent Tetiklenir]
    EVT --> CLR_REDIS[Redis Cache Invalidation:<br/>cache:*:{uid}:{old_locale}]
    EVT --> SET_SESSION[Redis Session Cache:<br/>user:{uid}:locale = 'en']
    
    subdiagram_startup [Uygulama Açılışı - Akıllı Senkronizasyon]
    START[SplashScreen GET /auth/me] --> RESP[Sunucu Döner:<br/>db_locale='ar', db_updated_at=T0]
    RESP --> CMP{Cihaz T1 > Sunucu T0 ?}
    CMP -->|Evet Cihaz Daha Yeni| PUSH[Sunucuyu Güncelle:<br/>PATCH /auth/me locale='en']
    CMP -->|Hayır Sunucu Daha Yeni| OVERRIDE[Cihazı Güncelle:<br/>setLocaleLocally 'ar']
```

### 1. Zaman Damgalı Çift Yönlü Senkronizasyon (Timestamped Sync)
- Hem mobilde (`SharedPreferences` altında `app_locale_updated_at`) hem de veritabanında (`users.locale_updated_at` sütunu) dil değişikliğinin yapıldığı zaman damgası (UTC timestamp) tutulacaktır.
- Uygulama ilk açıldığında (`SplashScreen`), sunucudan gelen değer yerel tercihi ezmeden önce zaman damgaları karşılaştırılacaktır:
  - **Eğer Cihazdaki Zaman Damgası > Sunucudaki Zaman Damgası ise:** Kullanıcı çevrimdışıyken veya uygulama kapanmadan önce dil değiştirmiştir ancak sunucuya ulaşamamıştır. Cihaz yerel dili **ezmez**; aksine arka planda sunucuyu yeni dille günceller.
  - **Eğer Sunucudaki Zaman Damgası > Cihazdaki Zaman Damgası ise:** Kullanıcı başka bir cihazdan (örneğin Web veya başka bir telefon) dilini değiştirmiştir. Cihaz yerel dilini sunucudan gelen yeni dille günceller.

### 2. Güvenilir Ağ İsteği ve Yan Etkilerin Temizlenmesi
- `LocaleNotifier.setLocale` içindeki `.ignore()` (fire-and-forget) yapısı kaldırılarak hata durumunda tekrar deneyecek (retry backoff) veya projede mevcut olan `OfflineQueueService` üzerinden gönderilecek güvenilir bir yapı kurulacaktır.
- Arka uçtaki `/auth/device-tokens` gibi dil değiştirme amacı taşımayan tüm yardımcı uç noktalardan `current_user.locale` alanını değiştiren/ezen yan etkili kodlar tamamen temizlenecektir.

### 3. Evrensel `Accept-Language` Başlık Standardizasyonu
- Mobil projedeki tüm servis sınıfları (`AuthService`, `AuctionService`, `ListingService` vb.) özel ad-hoc `_headers()` metodlarından arındırılacak ve merkezi `buildApiHeaders()` metodunu kullanacak şekilde standartlaştırılacaktır.
- Böylece uygulamanın attığı her API isteğinde `Accept-Language: <current_lang>` başlığı istisnasız yer alacaktır.

### 4. Redis Önbellek İnvalidasyon (Cache Invalidation) Stratejisi
- Kullanıcının dil tercihi PostgreSQL'de güncellendiği anda bir arka uç olayı (`LanguageChangedEvent`) tetiklenecektir.
- Bu olay, o kullanıcıya ait dile bağlı tüm Redis önbelleklerini (analitik raporları, pazar trendleri özetleri, yapay zeka tavsiyeleri vb.) pattern matching (`cache:*:{uid}:{old_locale}*` veya özel anahtar setleri) ile anında temizleyecektir.
- Ayrıca kullanıcı profili için Redis'te hafif bir oturum önbelleği (`user_session:{uid}:locale`) tutularak her istekte PostgreSQL'e gereksiz sorgu atılmasının önüne geçilecektir.
