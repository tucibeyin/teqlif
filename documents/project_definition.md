# teqlif – PROJE SUNUMU

---

## 1. PROJE ADI

teqlif, Sosyal ve Canlı Yayın Odaklı E-Ticaret Pazar Yeri
---

## 2. PROJE ÖZETİ

teqlif, literatürde "Canlı Yayın Ticareti" (Livestream Commerce) ve "Sosyal Ticaret" (Social Commerce) olarak adlandırılan iş modellerini merkeze alan, topluluk odaklı bir elektronik pazar yeridir. Proje, spesifik ilgi alanlarına sahip kitleleri düşük gecikmeli canlı video yayınları üzerinden gerçek zamanlı açık artırmalarla bir araya getirir. Amaç, geleneksel, statik e-ticaret deneyimini "alışveriş + eğlence" (Shoppertainment) konseptiyle dinamik, etkileşimli ve rekabetçi bir sosyal etkinliğe dönüştürmektir.

---

## 3. PROBLEM TANIMI

Geleneksel yatay pazar yerleri (Horizontal Marketplaces) ve C2C ilan platformları, pazarların bazı yapısal sorunlarını çözmekte yetersiz kalmaktadır. Projenin çıkış noktasındaki temel problemler şunlardır:

Güven ve Orijinallik Açığı (Trust Deficit): Ürünlerin alım satımında, statik fotoğraflar ve metin açıklamaları ürünün kondisyonunu veya orijinalliğini kanıtlamak için yetersizdir. Bu durum, alıcılarda yüksek bir dolandırıcılık riski algısı yaratır.

Parçalanmış Satış Süreci (Friction in Transactions): Sosyal ağlarda (Instagram Live, Twitch vb.) topluluk kuran satıcılar, canlı yayın sırasında ürün satmak istediklerinde ödeme alma, teklif takibi yapma ve envanter yönetme işlemlerini manuel olarak ve platform dışında yapmak zorunda kalmaktadır. Bu durum ciddi operasyonel hantallık yaratır.

İzolasyon ve Etkileşim Eksikliği: Geleneksel e-ticaret siteleri "işlem" (transaction) odaklıdır. Hobidaşların fiziksel müzayedelerde veya fuarlarda yaşadığı sosyal aidiyet, anlık sohbet ve rekabet heyecanı dijital ortamda bulunmamaktadır.

---

## 4. ÇÖZÜM

teqlif, bu problemleri e-ticaret ve anlık iletişim altyapılarını tek bir çatı altında birleştirerek çözer. Literatürdeki karşılığıyla "Çok Taraflı Platform" (MSP) olarak sunduğu çözüm mimarisi şu şekildedir:

Entegre Canlı Yayın Altyapısı: Satıcıların ürünlerini 360 derece gösterebildiği, alıcıların sorularını anında yanıtlayabildiği düşük gecikmeli (low-latency) WebRTC tabanlı bir video akış mimarisi sunulur. Bu şeffaflık, güven problemini ortadan kaldırır.

Gerçek Zamanlı Teklif Motoru: Canlı yayın sırasında saniyeler içinde gerçekleşen anlık teklifleri (bidding) yönetebilmek için, eşzamanlılık (concurrency) sorunlarını çözen, yüksek performanslı arka plan iş kuyrukları (job queues) ve bellek içi veri yapıları kullanılır. Açık artırma bittiğinde ödeme eşzamanlı olarak provizyona alınır; böylece manuel ödeme takibi sorunu (friction) çözülür.

Oyunlaştırma ve FOMO Üretimi: 15-30 saniyelik "ani ölüm" (sudden death) açık artırmaları ve "gizemli kutu açılışları" gibi kurgularla alışveriş oyunlaştırılır. Alıcılar arasındaki rekabet, Fırsatı Kaçırma Korkusunu (FOMO) tetikleyerek dönüşüm oranlarını (conversion rate) dramatik ölçüde artırır.

Çapraz Platform (Cross-Platform) Mobil Deneyim: Video izleme, anlık sohbet (chat) ve ödeme altyapısı, kullanıcının uygulamadan çıkmasına gerek kalmadan, tek bir akış içinde pürüzsüz çalışacak şekilde tasarlanmıştır.

### Temel Özellik Kümeleri

**Satış Kanalları**

- İlan pazaryeri: ilan yayınlama, aktifleştirme, deaktifleştirme ve yeniden yayına alma
- Canlı yayın açık artırma motoru: başlatma, duraklatma, devam ettirme, sonlandırma, teklif verme, anlık satın alma (buy-it-now) ve kazanan teklifi kabul etme
- Canlı yayın üzerinden direkt satış: sabit fiyatlı, anlık sipariş oluşturma ve kuyruğa alma
- SwipeLive: kaydırma tabanlı kişiselleştirilmiş keşif akışı; canlı yayınların arasına kullanıcının ilgi alanına dayalı ilanlar dinamik olarak yerleştirilir. Kullanıcı tek akış üzerinden hem açık artırmaları, direkt satışları hem de kişiselleştirilmiş ilanları keşfeder

**İletişim**

- Canlı yayın içi gerçek zamanlı sohbet
- Bire bir mesajlaşma: metin, görsel, video ve dosya paylaşımı
- WebRTC tabanlı sesli ve görüntülü çağrı; çağrı geçmişi
- Hikayeler (Stories): beğeni, görüntülenme takibi ve 24 saatlik yaşam döngüsü

**Topluluk ve Güven**

- Kullanıcı ve işletme profili; takip/takipçi sistemi; özel hesap ve takip isteği yönetimi
- Satıcı güven skoru (Trust Score) ve etki sıralaması (Influence Rank): alıcıya sayısal satıcı güvenilirliği gösterimi
- Puanlama ve değerlendirme sistemi; satıcı yanıt hakkı
- Canlı yayın moderasyon araçları: susturma, yayından atma, moderatör atama

**Kişiselleştirilmiş İçerik ve Keşif**

- Kullanıcı ilgi haritası: kayıt sırasında seçilen kategorilerle başlayan, görüntüleme, teklif, satın alma ve tereddüt sinyalleriyle sürekli gelişen öneri motoru
- Sana Özel (For You) akışı: ilgi alanına dayalı ilan ve yayın önerileri
- Arama ve arama uyarıları: kayıtlı kriterlere yeni ilan girildiğinde otomatik bildirim

**Pro Araçlar — Hesap Tipinden Bağımsız, Herkese Eşit Erişim**

- Toplu bildirim gönderme (Blast): filtrelenmiş hedef kitleye kişiselleştirilmiş push bildirimi
- Yeniden Ulaşma (Retargeting): bir ilanla etkileşime geçmiş kullanıcılara otomatik bildirim kampanyası
- Sıcak Aday (Hot Lead) tespiti: 24 saat içinde aynı ilana yönelik yüksek teklif tereddütü davranışı gösteren kullanıcıların otomatik tespiti ve satıcı bildirimi
- Öne çıkarma ve sponsorlu ilan (Boost): tıklama ve görüntüleme bazlı reklam kampanyası yönetimi
- Fiyat Zekası (Price Intelligence): rakip fiyat verisi ve kategori bazlı karşılaştırma
- Rakip Radar: rakip satıcı aktivitesini izleme ve karşılaştırmalı analiz
- Dönüşüm hunisi analizi: görüntüleme → teklif tereddütü → satın alma hattı; KPI gösterge paneli
- Yapay zeka destekli fiyat tahmini: kategori ve platform verilerine dayalı dinamik fiyat öneri motoru

**Platform Altyapısı**

- Platform içi Tuci kredi sistemi: yapay zeka araçları, ilan öne çıkarma, blast kampanyaları ve canlı yayın hediye işlemleri
- Satın alma ve satış yönetimi; sipariş detay ve geçmiş
- Bildirim merkezi: gerçek zamanlı bildirimler
- OTA (Over-The-Air) yerelleştirme: Türkçe, İngilizce, Rusça, Arapça

---

## 5. TEKNOLOJİK YAKLAŞIM

- **Mobil istemci:** Flutter (iOS ve Android) – tek kod tabanıyla çift platform
- **Backend:** FastAPI (Python) + PostgreSQL + Redis
- **Gerçek zamanlı iletişim:** LiveKit WebRTC – canlı yayın ve P2P sesli/görüntülü çağrı için ortak altyapı
- **Gerçek zamanlı olay akışı:** WebSocket üzerinden anlık teklif, sohbet, bildirim ve sipariş yönetimi
- **Push bildirim:** iOS VoIP PushKit + APNs + Android FCM hibrit mimarisi
- **Davranışsal analitik:** ClickHouse tabanlı yüksek hacimli kullanıcı etkileşim ve reklam olay işleme
- **Öneri motoru:** ClickHouse üzerinde kullanıcı ilgi alanı hesaplama ve sinyal işleme
- **OTA yerelleştirme:** Uygulama güncellemesi gerektirmeden çok dilli içerik dağıtımı ve önbellekleme
- **Tuci kredi altyapısı:** Yapay zeka araçları, öne çıkarma, blast kampanyaları ve canlı yayın hediye işlemleri için platform içi kredi sistemi; ilerleyen aşamada gerçek para ile Tuci yükleme ve ödeme entegrasyonu planlanmaktadır

---

## 6. AR-GE YÖNLERİ

- **Gerçek zamanlı açık artırma motoru:** Canlı video akışıyla teklif olaylarının milisaniye düzeyinde eşzamanlı yönetimi; açık artırma süresince anlık satın alma akışının paralel çalışması ve durum senkronizasyonu
- **SwipeLive keşif algoritması:** Kullanıcı davranışına göre kişiselleştirilmiş kaydırma tabanlı canlı yayın sıralama ve öneri sistemi; canlı yayınlar arasına kullanıcının ilgi alanına dayalı ilanlar dinamik olarak yerleştirilir. İlanda video varsa video öncelikli gösterilir, video yoksa ilanın kapak fotoğrafı görüntülenerek kesintisiz karma içerik akışı oluşturulur
- **Kullanıcı ilgi alanı ve öneri motoru:** Kayıt sırasında beyan edilen kategorilerden başlayıp görüntüleme, teklif, satın alma ve tereddüt sinyalleriyle ClickHouse üzerinde sürekli güncellenen ilgi haritası; içerik kişiselleştirmenin temel motoru
- **Sıcak Aday (Hot Lead) tespiti:** Teklif tereddütü olaylarını gerçek zamanlı sayarak 24 saat içindeki eşik geçiminde otomatik satıcı bildirimi tetikleme
- **Hibrit anlık bildirim mimarisi:** iOS VoIP PushKit ve Android FCM kombinasyonuyla uygulama arka planda veya kapalıyken bile güvenilir ve düşük gecikmeli çağrı iletimi
- **Yeniden Ulaşma motoru:** Davranışsal segmentasyonla etkileşim geçmişine sahip kullanıcıları tespit edip otomatik bildirim kampanyası başlatma
- **Yapay zeka destekli fiyat tahmini:** Piyasa ve kategori verisine dayalı dinamik fiyat öneri motoru
- **Rakip Radar ve piyasa zekası:** Rakip satıcı aktivitesi, kategori talep trendleri ve zirve saati analizinin gerçek zamanlı işlenmesi
- **P2P ticaret iletişim entegrasyonu:** WebRTC tabanlı sesli/görüntülü çağrının ticaret akışına doğrudan entegrasyonu; iOS VoIP PushKit ile arka planda güvenilir çağrı alımı
- **OTA yerelleştirme sistemi:** Uygulama mağazası güncellemesi olmadan çok dilli çeviri paketlerinin cihazlara anlık dağıtımı ve sürüm yönetimi
- **ClickHouse tabanlı analitik altyapısı:** Yüksek hacimli tıklama, görüntüleme, etkileşim ve dönüşüm olaylarının gerçek zamanlı işlenmesi ve raporlanması

---

## 7. VERİ YÖNETİMİ VE YASAL UYUMLULUK

teqlif, kullanıcı verilerini Virginia, ABD'deki (US-EAST-VA) bulut altyapısı üzerinde işlemektedir. Bu yapı, 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) kapsamında yurt dışı veri aktarımı hükümlerine tabidir. Platform, bu yükümlülükleri aşağıdaki mimariyle karşılamaktadır:

**Yasal Dayanak ve Aydınlatma**

- Veri aktarımı, hizmetin ifası için zorunlu olduğundan KVKK Madde 9/6/b (sözleşmesel zorunluluk) kapsamında gerçekleştirilmektedir
- Kayıt sırasında kullanıcıya KVKK Madde 10 uyumlu aydınlatma metni sunulur; aktarımın Virginia, ABD'deki sunucularda gerçekleştiği açıkça belirtilir
- Onay tarihi, dil ve IP adresi veritabanında kayıt altına alınır; olası bir denetimde ispat kaydı olarak kullanılabilir
- Kullanıcı, Madde 11 hakları (bilgi, düzeltme, silme, itiraz) kapsamında hesabını silerek verilerinin kaldırılmasını talep edebilir

**Teknik Güvenlik**

- JWT tabanlı oturum yönetimi; token yenileme ve iptal mekanizması
- Güvenli depolama: mobil cihazda hassas veriler Flutter Secure Storage ile şifrelenir
- Rate limiting ve brute-force koruması kayıt, giriş ve doğrulama uç noktalarında aktiftir
- İçerik güvenliği: CSP politikası ve XSS koruması web arayüzünde uygulanmaktadır

**İdari Yol Haritası (Aşama 2)**

- Bulut sağlayıcı ile KVKK Kurulu'nun standart sözleşme şablonu imzalanması (Madde 9/4/c)
- İmza tarihinden itibaren 5 iş günü içinde KVKK Kurumu'na bildirim
- VERBİS kaydının yurt dışı aktarım bilgisiyle güncellenmesi

---

## 8. HEDEF PAZAR

**Satıcı Tarafı**

- Canlı yayın üzerinden açık artırmayla satış yapan bireysel satıcılar
- Koleksiyon, ikinci el, el yapımı ve niş ürün satıcıları
- Küçük ve orta ölçekli işletmeler; butikler, atölyeler, yerel markalar
- Instagram Live, TikTok veya Twitch gibi platformlarda topluluk kurmuş ancak entegre bir ödeme ve teklif altyapısından yoksun satıcılar
- Platforma yeni katılan ve büyümek isteyen her ölçekten satıcı

**Alıcı Tarafı**

- Niş ürün koleksiyoncuları: spor kartları, vintage elektronik, el yapımı takı, nadir kitap gibi spesifik ilgi alanlarına sahip kullanıcılar
- Shoppertainment izleyicileri: alışverişi sosyal ve eğlenceli bir etkinlik olarak deneyimleyen, canlı yayın atmosferinden FOMO ile karar veren alıcılar
- Güven odaklı alıcılar: ürünü satın almadan önce görüntülü veya sesli olarak satıcıyla iletişim kurmak isteyen kullanıcılar
- İkinci el ve fırsat avcıları: kişiselleştirilmiş keşif akışında beklenmedik ürünlerle karşılaşmayı tercih eden alıcılar

---

## 9. GELİR MODELİ

- İşlem başına komisyon: açık artırma, direkt satış ve ilan satışlarından
- Tuci kredisi satışı: ilan öne çıkarma, blast bildirimi kampanyaları ve yapay zeka araç kullanımı
- Canlı yayın hediye ekonomisi: izleyicilerin yayıncıya Tuci ile hediye göndermesi
- Sponsorlu ilan gelirleri: tıklama ve görüntüleme bazlı reklam kampanyaları
- Planlanan: gerçek para ile Tuci yükleme, platform içi ödeme entegrasyonu ve Pro araçlar için abonelik modeli

---

## 10. REKABET ANALİZİ

**Global rakipler:** Whatnot (canlı açık artırma), TikTok Shop, SHEIN Live, Amazon Live

**Yerel rakipler:** Trendyol Canlı, Hepsiburada Canlı

Mevcut platformların tamamında analitik ve pazarlama araçlarına erişim hesap tipine veya harcama düzeyine göre kademelenmekte; alıcı ile satıcı arasındaki güven açığı (Trust Deficit) ve iletişim sürtünmesi (Friction) çözümsüz kalmaktadır. teqlif bu yapısal boşlukları aşağıdaki rekabetçi avantajlarla kapatır:

**teqlif'in Rekabetçi Farklılaşması**

- **Entegre üç satış kanalı:** Açık artırma, direkt satış ve ilan pazaryeri aynı hesap altında paralel çalışır; rakip platformlarda bu kanallar ayrı ürünler olarak konumlandırılmaktadır
- **Platform içi P2P iletişim:** Sesli ve görüntülü alıcı-satıcı çağrısı doğrudan ticaret akışına entegre edilmiştir; incelenen global ve yerel rakiplerin hiçbirinde bu kanal mevcut değildir
- **SwipeLive keşif akışı:** Canlı yayınlar ile kişiselleştirilmiş ilanların tek akışta sunulması, kullanıcı başına oturum süresini ve dönüşüm fırsatını artırır
- **Araçlara demokratik erişim:** Yeniden ulaşma (Retargeting), Sıcak Aday (Hot Lead) tespiti, Rakip Radar ve Fiyat Zekası gibi kurumsal araçlar hesap tipinden bağımsız olarak tüm satıcılara açıktır
- **Şeffaf itibar sistemi:** Güven skoru ve etki sıralaması, alıcıya ilan sayfasında sayısal satıcı güvenilirliği sunar
- **Yerel yasal uyumluluk:** KVKK (6698 sayılı Kanun) gereklerini karşılayan veri işleme mimarisi; global rakiplerin Türkiye pazarında karşılamadığı yapısal bir avantajdır
- **OTA yerelleştirme:** Uygulama mağazası güncellemesi gerektirmeden Türkçe, İngilizce, Rusça ve Arapça içerik dağıtımı

---

## 11. PAZARA GİRİŞ STRATEJİSİ

İlk aşamada hedef segment:

- Canlı yayın ile açık artırma yapan bireysel satıcılar
- Koleksiyon ve niş ürün toplulukları
- Sosyal medya üzerinden satış yapan mikro işletmeler ve KOBİ'ler

Pilot kullanıcı grubuyla sistem test edilerek dönüşüm, sıcak aday tespiti ve hedefleme verileri ölçülecek; edinilen verilerle büyüme ve pazar genişlemesi planlanacaktır.

---

## 12. PROJE SONUCU

teqlif, geleneksel e-ticaretin "işlem" (transaction) odaklı yapısını, canlı video ve topluluk dinamikleriyle "deneyim" (experience) odaklı bir sosyal ticaret ekosistemine dönüştürme iddiasıyla tasarlanmıştır.

Platform bu iddiayı somut bir mimariyle desteklemektedir:

- Açık artırma, direkt satış ve ilan pazaryerini tek altyapıda ve aynı hesap altında entegre eder; satıcı üç kanalı paralel yönetir
- WebRTC tabanlı sesli/görüntülü iletişimle alıcı-satıcı güven açığını (Trust Deficit) platform içinde kapatır; iletişim platform dışına taşmaz
- SwipeLive ile kişiselleştirilmiş karma içerik akışı ve FOMO mekanizmasıyla dönüşüm oranını (Conversion Rate) artırır
- Retargeting, Hot Lead tespiti, Rakip Radar ve Fiyat Zekası gibi kurumsal araçları hesap sınıflaması olmaksızın tüm satıcılara açar
- KVKK uyumlu veri işleme mimarisiyle yasal riski minimize eder; kullanıcı onay kaydı denetlenebilir düzeyde tutulur
- Tuci kredi sistemi ve komisyon geliriyle çok katmanlı bir gelir yapısı oluşturur; ilerleyen aşamada platform içi ödeme altyapısı ve abonelik modeli planlanmaktadır

Sonuç olarak teqlif; ölçeklenebilir, denetlenebilir, yasal uyumlu ve çok gelir akışlı bir "Livestream Commerce" platformu olarak konumlanmaktadır.
