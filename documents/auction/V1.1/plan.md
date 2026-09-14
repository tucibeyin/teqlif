# Auction V1.1 - Mimari Refactor ve Mute Bug Çözüm Planı

Bu belge, Teqlif'in Auction V1.1 sürümündeki müzayede (bid) sisteminin performansını artırmak, sahte banlanmaları (Mute Bug) engellemek ve Clean Architecture (ADR) standartlarına uygun hale getirmek amacıyla uygulanacak adımları içerir. **Pre-Authorization (Ön-Provizyon) özelliği daha sonraki versiyonlara (V1.2+) ertelenmiştir.**

## 1. Mute Bug (False-Positive) Çözümü
Sorun: Mobil operatörlerin (CGNAT) veya Cloudflare'in tüm IP'leri aynı göstermesi sebebiyle `FraudDetectionService`'in yeni kullanıcıları anında banlaması.

**Aksiyonlar:**
*   **Gateway (Nginx) Düzeltmesi:**
    *   Dosya: `deploy/scale/V1.3/gateway/nginx/teqlif.conf`
    *   Tüm resmi Cloudflare IPv4 ve IPv6 aralıkları `set_real_ip_from` direktifi ile Nginx konfigürasyonuna eklenecek.
    *   `real_ip_header CF-Connecting-IP;` aktif edilecek. Bu sayede Nginx `$remote_addr` değişkenine Cloudflare'in değil, **gerçek kullanıcının** IP'sini yerleştirecek ve Backend `request.client.host` üzerinden doğru IP'yi okumaya başlayacak.
*   **Fraud Skor Güncellemesi:**
    *   Dosya: `app/services/fraud_detection_service.py`
    *   IP doğruluğu sağlansa dahi CGNAT'tan (mobil veriden) kaynaklı çakışmaları tolere edebilmek için `_SHILL_SCORE_IP_MATCH` sabiti **30'dan 15'e düşürülecek**.

## 2. Clean Architecture Refactor (Troll Teklif Doğrulama)
Sorun: `place_bid` fonksiyonu, doğrudan içerisinde karmaşık matematiksel doğrulamalar (çarpanlar ve telefon onay kısıtları) barındırıyor. Bu "Business Logic Leakage" (İş Mantığı Sızıntısı) yaratmaktadır.

**Aksiyonlar:**
*   **Servis Ayrıştırması (BidValidationService):**
    *   Dosya: `app/services/bid_validation_service.py` (YENİ DOSYA)
    *   Troll teklif (10.000 TL, 7x/10x zıplama kısıtlamaları) mantığı bu servise taşınacak.
    *   `validate_troll_bid(user, amount, current_bid)` adında bir asenkron metod oluşturulacak.
*   **AuctionCommands Temizliği:**
    *   Dosya: `app/use_cases/auctions/commands/auction_commands.py`
    *   Buradaki uzun doğrulama blokları (30+ satır) silinecek ve yerine `await BidValidationService().validate_troll_bid(...)` çağrısı eklenecek.
    *   Bu sayede `place_bid` sadece "Orkestrasyon" rolünü (Clean Architecture'ın Command Pattern hedefi) üstlenecek.

## 3. Redis Bağlantılarının (Dependency Injection) İyileştirilmesi
Sorun: `await get_redis()` komutları `auction_commands.py` içerisinde satır aralarına hardcode edilmiştir. ADR dokümanına göre DI üzerinden geçmelidir.

**Aksiyonlar:**
*   **Redis Repository:**
    *   Dosya: `app/repositories/auction_redis_repo.py` (YENİ DOSYA)
    *   Redis ile olan Mute listesi, Auction State okuma/yazma ve Lua Script (`_VALIDATE_BID_SCRIPT`) işlemleri bir sınıfa toplanacak.
    *   `AuctionCommands` bu servisi constructor üzerinden veya metod içinde izole bir sınıftan çağırarak Redis katmanını soyutlayacak.

---

> Bu plan uygulanıp kodlar pushlandıktan sonra `task.md` ve `final.md` üzerinden tüm raporlama tamamlanacaktır.
