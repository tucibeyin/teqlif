# Canlı Yayın (Auction) Teklif Verme (Bid) Algoritmaları - Kapsamlı Analiz

İzleyicilerin canlı yayında teklif vermesini engelleyen (veya filtreleyen) tüm güvenlik, iş mantığı ve anti-fraud katmanları baştan sona analiz edilmiştir. Bir kullanıcının `place_bid` isteği attığında geçtiği 6 temel bariyer aşağıda listelenmiştir.

---

## 1. Bot ve Spam Koruması (Rate Limiting)
Kullanıcıların sürekli butona basmasını (spam) veya bot ağlarının müzayedeyi manipüle etmesini engellemek için hız sınırı uygulanır.
- **Kural:** Her kullanıcı **3 saniyede en fazla 1 teklif** verebilir.
- **Engel:** Bu limiti aşan isteklere anında `BID_RATE_LIMIT` (Too Many Requests) hatası dönülür ve işlem reddedilir.

## 2. Yayıncı (Host) Kısıtlaması
Bir kullanıcının kendi yayınındaki ürünün fiyatını yapay olarak artırmasını engellemek için temel bir kimlik kontrolü yapılır.
- **Kural:** Teklif veren kişinin ID'si, yayının `host_id`'si ile aynı olamaz.
- **Engel:** Aynıysa `HOST_CANNOT_BID` hatası fırlatılır.

## 3. Aktif Susturma (Mute) Kontrolü
Yayın moderatörleri veya sistem tarafından anlık olarak cezalandırılmış kullanıcıların teklif vermesi engellenir.
- **Kural:** Kullanıcının ID'si o yayına ait Redis Mute listesinde (Set) bulunmamalıdır.
- **Engel:** Listede varsa `BID_BLOCKED_MUTE` hatası ile reddedilir.

## 4. Shill Bidding & Fraud Detection (False-Positive Bug'ın Kaynağı)
Uygulamadaki en agresif ve şu an hatalı (false-positive) çalışan algoritmadır. Fiyat şişirme (shill bidding) amacıyla açılmış yan hesapları tespit etmeyi amaçlar.
- **Skorlama:**
  - Yayıncı ile Teklif Veren IP eşleşmesi: **+30 Puan**
  - Doğrulanmamış hesap: **+35 Puan**
  - Yeni hesap (7 günden genç): **+25 Puan**
- **Kural:** Toplam risk skoru **80**'e ulaşırsa kullanıcı **otomatik Mute** (Susturma) yer.
- **Bug Durumu (Önceki Analiz):** Cloudflare'in IP maskelemesi (Nginx `real_ip` eksikliği) veya mobil ağlardaki CGNAT (ortak IPv4 havuzu) nedeniyle yeni/doğrulanmamış kullanıcılar doğrudan 90 puan (30+35+25) alarak ilk tekliflerinde haksız yere banlanmaktadır.

## 5. Troll Teklif Koruması (Yüksek Fiyat & Zıplama Sınırları)
Açık artırmayı sabote etmek isteyen (ödeme niyeti olmayan) kullanıcıların astronomik teklifler verip müzayedeyi kitlemesini önler. Limitler hesap türüne göre değişir:
- **Doğrulanmamış Hesaplar:** Teklif **5.000 TL**'yi aşamaz veya mevcut fiyatın **7 katından** fazla zıplayamaz.
- **Doğrulanmış Hesaplar:** Teklif **10.000 TL**'yi aşamaz veya mevcut fiyatın **10 katından** fazla zıplayamaz.
- **Kural:** Eğer kullanıcı bu astronomik barajları geçmek istiyorsa sistem **Telefon Doğrulaması** (SMS) talep eder.
- **Engel:** Telefon onaylı değilse `BID_BLOCKED_NO_PHONE` veya `BID_BLOCKED_PHONE_UNVERIFIED` hatası döner.
> *Not: Sistemde teklif verme aşamasında cüzdan bakiyesi (Wallet Balance) veya Kredi Kartı (CC) kontrolü **yapılmamaktadır**. Teklifler tamamen ücretsiz ve taahhütsüzdür, ödeme zorunluluğu müzayede bitiminde kazanan belli olunca başlar.*

## 6. Eş Zamanlılık (Concurrency) ve Mantıksal Kontroller (Redis Lua)
Yukarıdaki tüm aşamaları geçen teklif, mikrosaniye seviyesindeki yarışları (Race Condition) önlemek için atomik bir Lua scriptine girer.
- **Kural A:** Açık artırma "Aktif" olmalıdır (`AUCTION_NOT_ACTIVE` hatası).
- **Kural B:** Verilen teklif, anlık fiyattan ve başlangıç fiyatından kesinlikle büyük olmalıdır (`BID_TOO_LOW` hatası).
- **Kural C (Race Condition):** Eğer iki kullanıcı aynı milisaniyede teklif atarsa ve veritabanı kayıt sırası Redis ile çelişirse, geride kalan kullanıcıya `CONCURRENT_BID_OUTBID` hatası dönülür ve ekranı anında güncellenir.

---

## 7. Mimari ve Endüstri Standartları Değerlendirmesi
`teqlif_architectural_decisions.md` belgesindeki (ADR) kararlara ve modern pazar yeri standartlarına göre `auction_commands.py` (place_bid) değerlendirmesi:

### Artılar (ADR ve Clean Architecture ile Uyumlu Noktalar)
1. **Event-Driven Asenkron Mimari:** Bildirimler (Push Notifications), ARQ Workers (`notify_outbid_task`) aracılığıyla `fire_and_forget` mantığıyla fırlatılıyor. Bu sayede teklif atan kullanıcının HTTP isteği bildirim kuyruğunu beklemiyor. Modern e-ticaret (Whatnot, vb.) standartlarına tam uygun.
2. **Merkezi Hata Yönetimi (Centralized Error Handling):** `ForbiddenException`, `BadRequestException` gibi özel exception'lar fırlatılarak kontrol sağlanıyor. ADR'de belirtilen projenin standart JSON hata çıktılarıyla (error handler) tam senkronize.
3. **Concurrency (Race Condition) Çözümü:** İki kullanıcının aynı mikrosaniyede teklif atmasını engellemek için PostgreSQL veritabanı lock'ları (Pessimistic Lock) yerine **Redis Lua Scripting** kullanılmış. Bu, büyük ölçekte inanılmaz bir performans artışı sağlayan birinci sınıf bir mühendislik kararıdır.

### Eksiler ve İyileştirilebilecek Noktalar (Code Smell)
1. **İş Mantığı Sızıntısı (Business Logic Leakage):** `auction_commands.py` içerisinde Troll Teklif hesaplamaları (çarpanlar, 5.000 TL vs.) doğrudan `place_bid` fonksiyonunun ortasına hardcode (spaghetti) yazılmış. Clean Architecture gereği bu hesaplamalar `BidValidationService` isimli ayrı bir domain servise taşınmalı, `AuctionCommands` sadece süreci orkestre etmelidir.
2. **Dependency Injection Eksikliği:** PostgreSQL (`self.uow.session`) temiz bir şekilde içeri (inject) edilmiş ancak `await get_redis()` doğrudan fonksiyon ortasında çağrılıyor. Redis işlemlerinin `RedisRepository` (veya `CacheService`) arkasına soyutlanması mock testleri yazılabilmesi için şarttır.
3. **Endüstri Standardı Eksikliği (Pre-Authorization):** Dünyadaki canlı müzayede sistemlerinin (Whatnot, eBay vb.) tamamında, yüksek bir teklif vermeden önce kredi kartından küçük bir **Provizyon (Pre-auth)** veya Cüzdan (Wallet) blokesi alınır. Teqlif'te teklif atmanın 10.000 TL'ye kadar sıfır taahhütlü (ücretsiz) olması dolandırıcılar ve troller için devasa bir zafiyettir.

---

## Değerlendirme & Yorum
Teqlif'in mevcut canlı yayın teklif mimarisi, büyük ölçekli ve yüksek trafikli bir sisteme (Redis Lua, ARQ Workers) son derece uygun tasarlanmış. Ancak 4 numaralı (Shill Bidding) kuralın IP'ye aşırı güvenmesi ve cüzdan bakiyesi sorulmadan (5 numara) çok yüksek baremlere (10.000 TL) teklif verilebilmesi risk teşkil ediyor.

**Öneriler:**
1. Mute Bug'ı (Shill Bidding) çözülecek (IP Skoru 15'e düşecek + Cloudflare Nginx düzeltilecek).
2. Troll teklif limitleri (5.000 TL) cüzdanda para olmadan atılabildiği için `place_bid` içerisine Cüzdan bakiye blokesi eklenebilir.
3. `place_bid` içerisindeki karmaşık matematiksel doğrulamalar kendi servislerine (`BidValidationService`) taşınarak Clean Code refactor'ü yapılabilir.
