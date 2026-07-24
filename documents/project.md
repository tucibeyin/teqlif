📝 Teqlif Proje Dokümantasyonu (AI & Geliştirici Rehberi)
Bu belge, Teqlif platformunun güncel dizin yapısını, teknoloji yığınını, mimari kararlarını ve kodlama standartlarını tanımlar. Yeni bir özellik eklerken, hata çözerken veya refactor yaparken bu belgedeki kurallara kesinlikle uyulmalıdır.

1. 🎯 Proje Özeti
Teqlif; canlı yayın destekli, gerçek zamanlı açık artırma ve ilan platformudur. Sistem, asenkron çalışan bir Python backend'i, Vanilla JS ile yazılmış hafif bir web önyüzü ve Flutter ile geliştirilmiş çok platformlu bir mobil uygulamadan oluşmaktadır.

2. 📁 Dizin Yapısı ve Modüller
Proje temel olarak 4 ana bileşene ayrılmıştır:

/backend/ (FastAPI): Projenin kalbi. API uç noktaları, veri tabanı modelleri, güvenlik katmanları ve WebSocket / PubSub yönetimini içerir.

/mobile/ (Flutter): iOS ve Android uygulaması. LiveKit ile WebRTC canlı yayın, WebSocket ile gerçek zamanlı açık artırma ve sohbet içerir.

/frontend/ (Vanilla JS/HTML): Tarayıcı üzerinden erişilen hafif web arayüzü. Backend tarafından statik olarak sunulur.

/deploy/ & Scriptler: Nginx konfigürasyonları, Systemd servis dosyaları ve deployment/güvenlik scriptleri (deploy.sh, setup_security.sh).

3. 🛠 Teknoloji Yığını ve Kullanılan Paketler
Backend Katmanı (/backend)
Framework: FastAPI (async tabanlı).

Veri Tabanı: PostgreSQL & SQLAlchemy (AsyncSession kullanılarak).

Migration: Alembic (/alembic dizini altında).

Gerçek Zamanlı İletişim: Redis (Pub/Sub ve Cache) & WebSockets.

Medya Sunucusu: LiveKit API (Canlı yayın yönetimi için).

Güvenlik: JWT (python-jose), Bcrypt (passlib), Input Sanitization (bleach), Rate Limiting (slowapi).

Hata İzleme ve Push: Sentry SDK, Firebase Admin SDK.

Mobil Katman (/mobile)
Framework: Flutter (Material Design).

Canlı Yayın: livekit_client.

Gerçek Zamanlı Veri: web_socket_channel.

Bildirimler: firebase_messaging & app_badge_plus.

Güvenlik: local_auth (Biyometrik doğrulama).

Dağıtım: Fastlane (Android için yapılandırılmış).

4. 🏗 Mimari Kurallar ve Veri Akışı
4.1. Güvenlik ve Doğrulama (Backend)
Backend tarafında /app/security/ klasörü altında çok katmanlı bir güvenlik yapısı vardır.

Route Koruması: Kimlik doğrulama gerektiren route'larda SecurityMiddleware ve JWT token doğrulama mantığı kullanılır.

Girdi Temizleme (Sanitization): Kullanıcıdan gelen tüm metin girdileri, XSS saldırılarına karşı app/security/sanitizer.py kullanılarak temizlenmelidir.

Rate Limiting: Kritik endpoint'lerde (Örn: /api/auction/{id}/bid) aşırı isteği önlemek için limiter kullanılmalıdır.

4.2. Gerçek Zamanlı Açık Artırma ve Sohbet
Sistem, doğrudan veri tabanına yazmak yerine Redis üzerinden haberleşir:

Teklif/Mesaj Gelir: API endpoint'ine HTTP POST veya doğrudan WebSocket üzerinden veri gelir.

Redis İşleme: Gelen teklif, app/utils/redis_client.py veya Lua scriptleri ile atomik olarak doğrulanır.

Pub/Sub Yayını: Geçerli veri, Redis Pub/Sub kanalına (auction_broadcast veya chat_broadcast) gönderilir.

WebSocket Dağıtımı: main.py içinde asenkron olarak çalışan pubsub_listener ve chat_pubsub_listener task'ları bu mesajları yakalar ve bağlı tüm WebSocket istemcilerine (Mobil/Web) iletir.

4.3. Veri Tabanı ve Alembic Kullanımı
Modeller /app/models/ dizini altındadır (User, Listing, Stream, Auction, Chat, Follow, Favorite vb.).

Kural: Veri tabanı şemasında (model dosyalarında) herhangi bir değişiklik yapıldığında mutlaka yeni bir Alembic migration dosyası oluşturulmalıdır: alembic revision --autogenerate -m "degisiklik_aciklamasi"

Kural: Yeni bir model oluşturulduğunda, app/database.py veya main.py içerisine import edilerek Base'e tanıtılmalıdır. main.py'deki lifespan event'i, tabloları ve temel SQL ALTER sorgularını başlatırken kullanılır.

5. 🤖 AI Ajanları ve Geliştiriciler İçin Sıkı Kurallar
Yeni özellik eklerken aşağıdaki kuralları ihlal etmeyin:

Tam Asenkronluk: Backend kodunda hiçbir senkron I/O (bloklayıcı) işlem yapılmamalıdır. Veri tabanı sorguları await db.execute(select(...)) şeklinde yazılmalıdır.

Dosya Yüklemeleri: Yüklenen görseller /app/routers/upload.py üzerinden yönetilir. Dosya isimleri güvenli hale getirilmeli ve uploads/ dizinine yazılmalıdır.

Mobil Servis Mimarisi: Flutter tarafında her yeni özellik için UI (ekran) ve İş Mantığı (servis) ayrı tutulmalıdır. API istekleri /lib/services/ altındaki ilgili sınıflar üzerinden (Örn: auction_service.dart, stream_service.dart) yapılmalıdır.

Modüler Route Yapısı: main.py dosyasını şişirmeyin. Yeni bir domain mantığı ekleniyorsa, /app/routers/ altında yeni bir router oluşturun ve main.py içinde app.include_router(...) ile dahil edin.

Ortam Değişkenleri (ENV): settings nesnesi /app/config.py (Pydantic Settings) üzerinden yönetilir. Yeni bir gizli anahtar (API key vb.) eklendiğinde .env.example dosyasına da boş bir referans ekleyin.

Hata Yönetimi (Sentry): Beklenmeyen hatalar loglanmalı ve backend'de yapılandırılmış olan Sentry entegrasyonu (sentry_sdk) üzerinden takip edilebilir olmalıdır.

🎨 UI/UX ve Frontend Geliştirme Standartları
Bu proje hem mobil (Flutter) hem de web (Vanilla JS/HTML) platformlarında hizmet vermektedir. Kullanıcı arayüzü geliştirilirken kod tekrarından kaçınılmalı ve "Gerçek Zamanlı Açık Artırma" dinamiklerine uygun, düşük gecikmeli (low-latency) bir hissiyat sağlanmalıdır.

1. Genel Tasarım Dili ve Tema
Ana Renk (Primary): Projenin imza rengi Cyan'dır (#06B6D4). Tüm vurgular, ana butonlar ve aktif durumlar bu renk etrafında şekillenmelidir.

Karanlık Mod (Dark Mode): Mobil uygulamada theme_provider.dart üzerinden dinamik tema yönetimi yapılmaktadır. Yazılacak her yeni ekran ve UI bileşeni (widget/HTML elementi) hem aydınlık hem de karanlık temaya tam uyumlu olmalıdır. Renkleri "hard-code" yazmak yasaktır (Örn: color: Colors.white yerine Theme.of(context).colorScheme.surface kullanılmalıdır).

2. Mobil (Flutter) UI Kuralları
Klasör Yapısı: Ekranlar /lib/screens/ altında, tekrar kullanılabilir UI parçaları ise /lib/widgets/ altında (Örn: auction_panel.dart, chat_panel.dart) bulunmalıdır. Bir ekran dosyası 300 satırı geçiyorsa, UI parçaları mecburi olarak alt widget'lara bölünmelidir.

Gerçek Zamanlı Güncellemeler: Açık artırma teklifleri ve sohbet mesajları WebSocket üzerinden anlık akar. Sayfayı tamamen yenileyen (setState ile tüm ekranı çizen) pahalı işlemlerden kaçınılmalı; sadece ilgili UI bileşenini güncelleyen StreamBuilder veya localized stateler kullanılmalıdır.

Klavye Yönetimi: Sohbet ve teklif girişlerinde klavye açıldığında ekranın bozulmaması için global_keyboard_accessory.dart veya SafeArea & resizeToAvoidBottomInset yapılarına dikkat edilmelidir.

3. Web (Vanilla JS & HTML/CSS) UI Kuralları
Framework Yok: Projenin web tarafı Vanilla JS, saf HTML ve CSS (/frontend/static/css/main.css) ile yürütülmektedir. React, Vue veya Tailwind gibi ağır bağımlılıklar eklemek yasaktır.

DOM Manipülasyonu: Gelen WebSocket mesajlarında DOM'u tamamen temizleyip yeniden yaratmak yerine, document.createElement veya mevcut elementlerin text/class değerlerini güncelleyerek (Örn: .classList.add('new-bid-animation')) performanslı güncellemeler yapılmalıdır.

Responsive Tasarım: CSS tarafında mobil öncelikli (mobile-first) yaklaşım kullanılmalı; grid ve flexbox yapılarıyla tarayıcı ekran boyutlarına göre kırılımlar (media queries) ayarlanmalıdır.

4. Animasyon ve Gecikme (Latency) Hissiyatı
İyimser UI (Optimistic UI): Kullanıcı bir teklif (bid) verdiğinde, backend'den onay beklemeden UI'da teklifin iletildiğine dair bir "yükleniyor/işleniyor" animasyonu anında gösterilmelidir.

Görsel Geri Bildirim: Yeni bir teklif geldiğinde, fiyat metninin rengi kısa süreliğine parlamalı (highlight flash) veya fiyat kutusu ufak bir "pop" animasyonu yapmalıdır. Bu, açık artırma heyecanını artırır.

5. WebSocket Bağlantısı ve Mesaj Yönetimi
Bağlantı Durumu: WebSocket bağlantısı kesildiğinde, kullanıcıya bir "bağlantı kesildi" uyarısı gösterilmeli ve otomatik olarak yeniden bağlanma denemesi yapılmalıdır.

Mesaj İşleme: Gelen mesajlar (teklifler, sohbet mesajları) bir kuyruk (queue) ile işlenmeli ve sırayla işlenmelidir. Bu, mesajların kaybolmasını veya yanlış sıralanmasını önler.