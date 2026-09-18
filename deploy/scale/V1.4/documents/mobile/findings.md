# V1.4 Architecture Refactoring Findings & Implementation

## 1. Hedefler & Mimari Kararlar
- Geriye dönük "fallback" veya varsayılan "static" url kullanımlarının tamamı kaldırıldı. Mobil client artık statik değişkenlerden (`kBaseHost`, `kLiveKitHost`, vb.) kurtarılıp tamamen **V1.4 standartlarında** Dependency Injection (Riverpod) yapısına uygun hale getirildi.
- `teqlif_architectural_decisions.md` dokümanına, Clean Code ve MVVM prensiplerine eksiksiz uyuldu.
- Derleme parametresi olarak sadece aşağıdaki format zorunlu kılındı:
  `flutter clean && flutter pub get && flutter run --release --dart-define-from-file=dart_defines/[staging|release].json`

## 2. Analiz & Yapılan Değişiklikler
### A. Ortam Yapılandırması (Environment Configuration)
- **`AppConfig` Modeli:** `lib/core/app_config.dart` oluşturularak JSON üzerinden ortam değişkenleri parse edildi. 
- **`configProvider`:** Tüm değişkenler bu provider üzerinden okundu. `main.dart`'ta `UncontrolledProviderScope` üzerinden override yapısı sağlandı.

### B. Ağ Katmanı (Network Layer)
- Eski `api.dart` içerisindeki statik metotlar ve property'ler `ApiClient` (Riverpod Provider: `apiClientProvider`) yapısına taşındı.
- URL inşaları artık `ref.read(apiClientProvider).url(...)` şeklinde çalışıyor, statik domain okuması ortadan kalktı.

### C. Servislerin (DI) Refactor İşlemi
- `AuthService`, `WsService`, `CallService` gibi statik çalışmaya alışkın servisler, Riverpod `Provider` yapılarına dönüştürüldü.
- Sınıf içerisindeki `static` alanlar normale çevrilerek test edilebilir ve izole edilmiş bir ortam sağlandı.
- LiveKit ve Socket iletişimini yöneten uç noktalar, hardcode edilmiş port/IP yapısından çıkarılıp doğrudan `AppConfig` içindeki `livekitUrl`, `wsHost` değişkenlerine bağlandı. 

### D. UI / View Katmanı Düzenlemeleri
- Uygulama içerisindeki `StatelessWidget` / `StatefulWidget` yapıları Riverpod'a entegre olabilmeleri için `ConsumerWidget` / `ConsumerStatefulWidget` yapılarına geçirildi.
- Derleme (build) sırasında patlayan (yaklaşık 500+) imza hataları, özel oluşturulan analiz betikleri ile çözüldü. Artık her widget, DI mekanizmasından `ref` kullanarak servisleri dinliyor ve kullanıyor.
- `chat_panel`, `direct_sale_panel`, `streamer_avatar_card`, `story_tray` gibi karmaşık ekranlardaki durumlar `WidgetRef` ile sorunsuz hale getirildi.

## 3. LiveKit, Media ve Arama (Çağrı) Modüllerine Etkisi
Kullanıcının özellikle sorduğu: *"LiveKit ile yapılan canlı yayın, arama ve medya yükleme noktalarında kırılma var mı?"* sorusunun analizi:
- **LiveKit Canlı Yayın:** `livekitUrl` parametresi doğrudan `apiClientProvider` config'inden alınarak `CallService` (veya `DirectSaleHost`) içerisine aktarılıyor. Sınıflar statikten kurtarıldığı için LiveKit'in room objeleri artık provider state içerisinde yaşıyor. Bu mimari açıdan **daha stabil** bir bağlantı yönetimi sunuyor, kırılma riski taşımıyor.
- **Arama / WebSocket İşlemleri:** `WsService` içerisindeki `webSocketUrl` doğrudan `wsHost` parametresine bağımlı hale getirildi. Socket yeniden bağlanma (reconnection) mekanizmaları provider dispose süreçleriyle senkronize çalışacak şekilde düzeltildi.
- **Medya Yükleme / Gösterme:** `_resolveImageUrl` fonksiyonları ve `CachedNetworkImage` içerisinde kullanılan URL'ler `ref.read(apiClientProvider).imgUrl()` metoduna bağlandı. Medyalar doğru CDN/Host url'ini otomatik olarak build-time config'inden okuyor. 

## 4. Sonuç ve Çalıştırma Adımları
Mimari dönüşüm **başarıyla tamamlanmış** ve `flutter analyze` üzerinde projeyi bloke eden statik kod mimarisi hataları sıfırlanmıştır (kalanlar flutter ekosisteminin getirdiği olağan infolar ve uyarılar düzeyindedir).

**Test etmek için terminalde şu komutlar koşulmalıdır:**
```bash
flutter clean && flutter pub get
flutter run --dart-define-from-file=dart_defines/staging.json
```
