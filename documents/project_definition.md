# teqlif – TEKNOPARK PROJE SUNUMU

---

## 1. PROJE ADI

teqlif – Sosyal Ticaret Platformu

---

## 2. PROJE ÖZETİ

teqlif; ilan pazaryeri, canlı yayın açık artırması, canlı yayın üzerinden direkt satış, gerçek zamanlı mesajlaşma, sesli/görüntülü iletişim, kişiselleştirilmiş içerik akışı ve platform içi ticari veri ve pazarlama araçlarını tek bir dijital çatı altında birleştiren mobil tabanlı sosyal ticaret platformudur.

Platformun temel felsefesi kullanıcı sınıflandırması yapmamaktır. Bireysel bir satıcı da, küçük bir işletme de, orta ölçekli bir KOBİ de teqlif'e üye olduğu andan itibaren tüm uygulama özelliklerine eşit biçimde erişir. Harcama düzeyi veya hesap tipi, bu özelliklere erişimi kısıtlamaz.

iOS ve Android üzerinde çalışan platform; her ölçekten satıcıya birden fazla satış kanalını paralel olarak yönetme, davranışsal veri ile doğrudan hedef kitleye ulaşma ve ilan ile satış verisi odaklı karar alma imkânı sunar. Alıcılara ise canlı yayınlar arasına kullanıcının ilgi alanına (afinite profili) göre yerleştirilmiş kişiselleştirilmiş ilanlar (video varsa video, yoksa kapak fotoğrafı), güvenli ticaret ortamı ve platform içi doğrudan iletişim sağlar.

---

## 3. PROBLEM TANIMI

Mevcut sosyal ticaret platformlarında araçlara ve verilere erişim kullanıcı tipine, harcama düzeyine veya abonelik kademesine göre farklılaşmaktadır. Bu yapı aşağıdaki sorunları doğurmaktadır:

- Yeniden ulaşma, rakip analizi, fiyat zekası ve sıcak aday tespiti gibi veri odaklı araçlar ücretli planların veya yüksek harcama eşiklerinin arkasında tutulmaktadır; platforma yeni katılan veya küçük ölçekte çalışan satıcılar bu araçlara erişememektedir
- Canlı yayın açık artırması, direkt satış ve ilan yayınlama aynı hesap altında entegre ve paralel biçimde yönetilememektedir
- Alıcı ile satıcı arasında platform içi doğrudan sesli veya görüntülü iletişim kanalı bulunmamaktadır; iletişim platform dışına taşmakta, güven ve takip sorunu doğurmaktadır
- Canlı yayın keşfi ile ilan içeriği ayrı platformlarda yer almakta; kullanıcıya bütünleşik ve kişiselleştirilmiş bir alışveriş akışı sunulamamaktadır
- Satıcı itibarını sayısal olarak ölçen ve alıcıya şeffaf biçimde sunan standart bir güven sistemi mevcut değildir

---

## 4. ÇÖZÜM

teqlif, bu boşlukları aşağıdaki entegre modüllerle kapatır:

### Satış Kanalları

- İlan pazaryeri: ilan yayınlama, aktifleştirme, deaktifleştirme ve yeniden yayına alma
- Canlı yayın açık artırma motoru: başlatma, duraklatma, devam ettirme, sonlandırma, teklif verme, anlık satın alma (buy-it-now) ve kazanan teklifi kabul etme
- Canlı yayın üzerinden direkt satış: sabit fiyatlı, anlık sipariş oluşturma ve kuyruğa alma
- SwipeLive: kaydırma tabanlı kişiselleştirilmiş canlı yayın keşif akışı; canlı yayınların arasına kullanıcının ilgi alanına göre belirlenen ilanlar yerleştirilir. İlanda video varsa video öncelikli olarak gösterilir, video yoksa ilanın kapak fotoğrafı görüntülenir. Kullanıcı tek bir akış üzerinden hem canlı açık artırmaları ve direkt satışları hem de kişiselleştirilmiş ilanları keşfeder.

### İletişim

- Canlı yayın içi gerçek zamanlı sohbet
- Bire bir mesajlaşma: metin, görsel, video ve dosya paylaşımı
- WebRTC tabanlı sesli ve görüntülü çağrı; çağrı geçmişi
- Hikayeler (Stories): beğeni, görüntülenme takibi ve 24 saatlik yaşam döngüsü

### Topluluk ve Güven Sistemi

- Kullanıcı ve işletme profili; takip/takipçi sistemi; özel hesap ve takip isteği yönetimi
- Kullanıcı engelleme
- Satıcı güven skoru (Trust Score) ve etki sıralaması (Influence Rank): ilan detay sayfasında alıcıya sayısal satıcı güvenilirliği gösterimi
- Puanlama ve değerlendirme sistemi; satıcı yanıt hakkı ve puan güncelleme geçmişi
- Canlı yayın moderasyon araçları: seyirciyi susturma, yayından atma, moderatör atama ve görevden alma

### Kişiselleştirilmiş İçerik ve Keşif

- Kullanıcı ilgi alanı: kayıt sırasında seçilen kategorilerle başlayan ve görüntüleme, teklif, satın alma, tereddüt gibi kullanım sinyalleriyle sürekli gelişen ilgi haritası; tüm içerik önerilerinin temel kaynağı
- Sana Özel (For You) akışı: kullanıcının ilgi alanına dayalı ilan ve yayın önerileri
- Kullanıcı geri bildirim sinyalleri: "İlgilenmiyorum" ve tereddüt edilen ilanlar; öneri motorunu gerçek zamanlı besler
- Arama ve arama uyarıları: kayıtlı arama kriterlerine yeni ilan girildiğinde otomatik bildirim

### Pro Araçlar — Tüm Kullanıcılara Eşit Erişim

teqlif'te Pro araçlar hesap tipine veya harcama düzeyine göre kademelendirilmez. Platforma üye olan her satıcı aşağıdaki araçların tamamına eşit biçimde erişir:

- Toplu bildirim gönderme (Blast): filtrelenmiş hedef kitleye kişiselleştirilmiş push bildirimi; Tuci kredi tabanlı erişim
- Yeniden Ulaşma: bir ilanla etkileşime geçmiş kullanıcılara otomatik bildirim kampanyası; hedef kitle büyüklüğü ön gösterimi
- Sıcak Aday (Hot Lead) tespiti: 24 saat içinde aynı ilana yönelik yüksek teklif tereddütü davranışı gösteren kullanıcılar tespit edilip satıcıya otomatik bildirim gönderilir
- Öne çıkarma ve sponsorlu ilan (Boost): ilan ve yayın görünürlüğünü artırma; tıklama ve görüntüleme bazlı reklam kampanyası yönetimi
- Canlı yayın analitiği ve satıcı raporu
- İlan bazlı analitik; ilan karşılaştırma ve segment analizi
- Dönüşüm hunisi analizi: görüntüleme, teklif tereddütü ve satın alma dönüşüm hattı; KPI gösterge paneli
- Fiyat Zekası (Price Intelligence): rakip fiyat verisi ve kategori bazlı fiyat karşılaştırma
- Rakip Radar: rakip satıcı aktivitesini izleme ve karşılaştırmalı analiz
- Talep Trendleri: piyasa talep analizi ve kategori bazlı yükselen ilgi tespiti
- Piyasa Zekası: arama trendleri, zirve saatleri, kategori hacim verileri
- Pro Insights: dönüşüm dağılımı, en iyi yayın saati önerileri, pro metrikler
- Yapay zeka destekli fiyat tahmini: kategori ve platform içi verileri referans alan dinamik fiyat öneri motoru

### Platform Altyapısı

- Platform içi Tuci kredi sistemi: yapay zeka destekli ilan açıklaması ve fiyatlama, ilan öne çıkarma, toplu bildirim gönderme ve canlı yayın sırasında izleyiciden yayıncıya hediye gönderme işlemleri için kullanılır
- Satın alma ve satış yönetimi; sipariş detay ve geçmiş
- Bildirim merkezi: gerçek zamanlı bildirimler ve ileti entegrasyonu
- Raporlama ve içerik moderasyonu
- Favori ilan yönetimi
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

## 7. GÜVENLİ VE DİJİTAL TİCARET ALTYAPISI

teqlif, kullanıcı sınıflandırması yapmayan ve tüm özellikleri herkese eşit biçimde açan yapısıyla:

- Güven skoru ve etki sıralamasıyla şeffaf satıcı itibar sistemi
- Otomatik açık artırma ve sipariş motoru
- Platform içi alıcı-satıcı sesli/görüntülü iletişim kanalı
- Canlı yayın moderasyon araçları ve topluluk yönetimi
- Tüm özelliklere üye olan herkesin eşit erişimi
- Merkezi işlem yönetimi ve denetlenebilir arşivleme

ile güvenli, ölçeklenebilir ve denetlenebilir bir dijital ticaret altyapısı sunar.

---

## 8. HEDEF PAZAR

- Canlı yayın üzerinden açık artırmayla satış yapan bireysel satıcılar
- Koleksiyon, ikinci el, el yapımı ve niş ürün satıcıları
- Küçük ve orta ölçekli işletmeler; butikler, atölyeler, yerel markalar
- Sosyal medya tabanlı satış yapan mikro işletmeler ve girişimciler
- Platforma yeni katılan ve büyümek isteyen her ölçekten satıcı

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

Mevcut platformların tamamında araçlara ve verilere erişim hesap tipine, harcama düzeyine veya abonelik kademesine göre farklılaşmaktadır. teqlif bu kademelendirmeyi kaldırır.

**teqlif'in farkı:**

- Üç satış kanalı tek platformda ve aynı hesap altında entegre: açık artırma, direkt satış, ilan pazaryeri
- SwipeLive ile canlı yayın ve kişiselleştirilmiş ilanlar tek akışta; ilanda video varsa video, yoksa kapak fotoğrafı gösterilir; kullanıcının ilgi alanına dayalı karma içerik deneyimi
- Platform içi sesli/görüntülü alıcı-satıcı iletişimi; hiçbir rakipte bulunmayan doğrudan iletişim kanalı
- Tüm özellikler — yeniden ulaşma, sıcak aday tespiti, rakip radar, fiyat zekası — hesap tipinden bağımsız olarak her kullanıcıya açık
- Güven skoru ve etki sıralamasıyla şeffaf satıcı itibar sistemi
- ClickHouse tabanlı gerçek zamanlı davranışsal analitik
- Uygulama güncellemesi gerektirmeyen çok dilli OTA altyapısı

---

## 11. PAZARA GİRİŞ STRATEJİSİ

İlk aşamada hedef segment:

- Canlı yayın ile açık artırma yapan bireysel satıcılar
- Koleksiyon ve niş ürün toplulukları
- Sosyal medya üzerinden satış yapan mikro işletmeler ve KOBİ'ler

Pilot kullanıcı grubuyla sistem test edilerek dönüşüm, sıcak aday tespiti ve hedefleme verileri ölçülecek; edinilen verilerle büyüme ve pazar genişlemesi planlanacaktır.

---

## 12. PROJE SONUCU

teqlif, tüm özelliklerine eşit erişim sağlayan yapısıyla:

- Açık artırma, direkt satış ve ilan pazaryeri süreçlerini tek altyapıda ve aynı hesap altında entegre biçimde sunar
- Veri ve pazarlama araçlarının tamamını platforma üye olan herkese eşit biçimde açar
- Kullanıcının ilgi alanına göre kişiselleştirilmiş içerik akışı ve sıcak aday tespiti sağlar
- Alıcı-satıcı iletişimini platform içi sesli/görüntülü kanalla doğrudan ve güvenli hale getirir
- Güven skoru sistemiyle platformda şeffaf bir itibar ekonomisi oluşturur
- Tuci kredi sistemiyle öne çıkarma, hedefleme ve canlı yayın hediye ekonomisini destekleyen; ilerleyen aşamada platform içi ödeme altyapısı ve abonelik modeline dönüşmesi planlanan çok katmanlı bir gelir yapısı oluşturur
- Ölçeklenebilir, denetlenebilir ve çok gelir akışlı bir sosyal ticaret ekosistemi kurar
