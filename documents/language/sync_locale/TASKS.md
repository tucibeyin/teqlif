# Uçtan Uca Dil Senkronizasyonu (Sync Locale) Görev Takip Listesi

Bu döküman, Teqlif uygulamasındaki dil tercihinin Mobil (State/SharedPreferences), Ağ (API Headers), Veritabanı (PostgreSQL) ve Önbellek (Redis) katmanlarında %100 senkronize çalışmasını sağlayacak iyileştirmelerin canlı görev takip listesidir.

---

## 📱 Faz 1: Mobil İstemci ve Durum Yönetimi (Mobile Client & State)

- [x] **1.1. `LocaleNotifier.setLocale` Güvenilir Ağ İsteği Altyapısı**
  - `mobile/lib/providers/locale_provider.dart` içerisindeki `http.patch` isteğinden `.ignore()` (fire-and-forget) ifadesi kaldırılacak.
  - Ağ hatası veya çevrimdışı olma durumunda isteğin kaybolmaması için projede mevcut olan `OfflineQueueService` veya üstel geri çekilme (exponential backoff) mekanizmasına entegre edilecek.
  - Dil değiştiği anda UTC zaman damgası (`DateTime.now().toUtc().toIso8601String()`) oluşturularak `SharedPreferences` altında `app_locale_updated_at` anahtarıyla saklanacak.

- [x] **1.2. `SplashScreen` Akıllı Senkronizasyon (Zaman Damgası Karşılaştırması)**
  - `mobile/lib/screens/splash_screen.dart` dosyasında `AuthService.me()` yanıtından gelen `user.locale` değerinin koşulsuz olarak `setLocaleLocally` ile yerel tercihi ezmesi (`override`) engellenecek.
  - Sunucudan gelen `user.locale_updated_at` ile cihazdaki `app_locale_updated_at` zaman damgaları karşılaştırılacak:
    - **Cihaz Daha Yeni ise (`Cihaz T > Sunucu T`):** Arka planda sunucuyu yeni dille güncelleyecek (`PATCH /auth/me`) senkronizasyon tetiklenecek.
    - **Sunucu Daha Yeni ise (`Sunucu T > Cihaz T`):** Cihazın arayüz dili ve yerel belleği sunucudan gelen yeni dille güncellenecek (`setLocaleLocally`).

---

## 🌐 Faz 2: API Başlıklarının Standardizasyonu (Network & Headers)

- [x] **2.1. Merkezi `buildApiHeaders()` Entegrasyonu**
  - Mobil projedeki servis sınıflarında tanımlanmış olan ad-hoc (özel) `_headers()` metodları temizlenerek `mobile/lib/config/api.dart` içerisindeki merkezi `buildApiHeaders()` kullanımına geçilecek:
    - `mobile/lib/services/auth_service.dart` (`_headers` -> `buildApiHeaders`)
    - `mobile/lib/services/auction_service.dart` (`_headers` -> `buildApiHeaders`)
    - `mobile/lib/services/listing_service.dart` (`_headers` -> `buildApiHeaders`)
    - `mobile/lib/services/notification_service.dart` (`_headers` -> `buildApiHeaders`)
    - `mobile/lib/services/stream_service.dart`, `story_service.dart`, `moderation_service.dart`
- [x] **2.2. Evrensel `Accept-Language` Doğrulaması**
  - Yapılan refactor sonrası, uygulamadan giden tüm yetkilendirilmiş ve yetkilendirilmemiş HTTP isteklerinde `Accept-Language: <current_lang>` başlığının otomatik olarak yer aldığı doğrulanacak.

---

## ⚙️ Faz 3: Arka Uç API ve Veritabanı Düzenlemeleri (Backend & DB)

- [x] **3.1. Yardımcı Uç Noktalardan Yan Etkilerin (Side-Effects) Temizlenmesi**
  - `backend/app/routers/auth.py` dosyasındaki `@router.post("/device-tokens")` uç noktasında yer alan ve gelen HTTP başlığına göre veritabanındaki dili ezen `if current_user.locale != lang: values["locale"] = lang` bloğu kaldırılacak.
  - Dil değişimi yalnızca explicit (açıkça dil değiştirme amacı taşıyan) API uç noktaları (`PATCH /auth/me` veya `PATCH /users/locale`) üzerinden yapılacak.

- [x] **3.2. Veritabanı Şeması ve SQLAlchemy Modeli Güncellemesi**
  - `backend/app/models/user.py` içindeki `User` modeline `locale_updated_at = Column(DateTime(timezone=True), nullable=True)` sütunu eklenecek.
  - Alembic migration dosyası oluşturularak PostgreSQL `users` tablosuna ilgili alan eklenecek.
  - `backend/app/schemas/user.py` içindeki `UserOut` ve `UserUpdate` Pydantic şemalarına `locale_updated_at` alanı dâhil edilecek.

- [x] **3.3. `PATCH /auth/me` Çift Yönlü Zaman Damgası Kontrolü**
  - `update_me` metodu, mobil istemciden gelen `locale` ve `locale_updated_at` verilerini karşılaştıracak.
  - Eğer gelen zaman damgası veritabanındaki mevcut `locale_updated_at` değerinden daha eskiyse değişim yoksayılacak (stale request koruması); daha yeniyse veritabanı güncellenecek.

---

## ⚡ Faz 4: Redis Önbellek Senkronizasyonu ve İnvalidasyon (Redis Cache Layer)

- [x] **4.1. Kullanıcı Oturumu (User Session) Önbelleklemesi**
  - `backend/app/utils/auth.py` içindeki `get_current_user` fonksiyonu, her istekte PostgreSQL'e sorgu atmak yerine Redis üzerinde 15 dakika TTL süreli `session:user:{uid}` önbelleğini kullanacak şekilde optimize edilecek.

- [x] **4.2. Dile Bağımlı Önbelleklerin Temizlenmesi (Cache Invalidation Event)**
  - Veritabanında kullanıcının dili değiştiğinde tetiklenecek bir `invalidate_user_i18n_caches(user_id, old_locale)` yardımcı fonksiyonu yazılacak.
  - Bu fonksiyon, kullanıcının eski dile ait önbelleklerini anında Redis'ten temizleyecek (`DEL` / `UNLINK`):
    - Pazar trendleri ve istatistikler (`cache:market_trends_*`, `cache:pro_insights:{uid}:*`)
    - Dile özel feed ve öneri önbellekleri (`interests:{uid}`, `feed:foryou:{uid}`)
    - Oturum önbelleği (`session:user:{uid}`) yenilenerek yeni dil derhal aktif edilecek.

---

## 🧪 Faz 5: Test ve Doğrulama (Testing & Verification)

- [x] **5.1. Çevrimdışı ve Yarış Koşulu (Race Condition) Entegrasyon Testleri**
  - Uygulama çevrimdışıyken dil değiştirilip kapatıldığında, yeniden açıldığında yerel tercihin korunduğu ve bağlantı geldiğinde sunucunun güncellendiği test edilecek.
  - Arka uca arka arkaya farklı dil değişim istekleri gönderildiğinde (eski zaman damgalı isteğin geç ulaşması senaryosu), sadece en yeni zaman damgalı dilin aktif kaldığı doğrulanacak.

- [x] **5.2. Yan Etki (Side-Effect) İzolasyon Testleri**
  - Farklı `Accept-Language` başlığıyla `/auth/device-tokens` veya bildirim uç noktalarına istek atıldığında veritabanındaki `users.locale` değerinin değişmediği bir Pytest test kurgusuyla doğrulanacak.
