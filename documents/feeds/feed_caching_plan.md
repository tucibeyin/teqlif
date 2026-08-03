# Feed Optimizasyonu Planı (Redis Cache & Delta Fetching)

> [!NOTE]
> **Tüm tasklar `feed_caching_task.md` içerisindedir.**

Bu doküman, uygulamanın farklı bölümlerindeki (Keşfet, İlanlar, Sana Özel vb.) Feed API'lerinin yüksek performanslı "Redis Fan-out + Delta Fetching" mimarisine geçişini analiz eder.

## User Review Required

> [!WARNING]
> Bu geçiş backend mimarisinde köklü bir "Read" mantığı değişikliğidir. Şu anda SQL sorguları anlık (on-the-fly) hesaplanıyor. Bu işlem sonrasında Feed algoritmaları, asenkron `Worker`'lar (Background Tasks) tarafından periyodik hesaplanacak. 
> Geliştirme süresi (Maliyeti) **Yüksektir** (Takribi 1-2 Hafta Backend + 1 Hafta Frontend entegrasyonu).
> Fakat sunucu donanım maliyetinizi (VPS) inanılmaz derecede **Düşürecektir**.

---

## 1. Nerelere Dokunacağız? (Etki Alanı)

Keşfetmediğimiz bir nokta yok, sistemdeki Feed yapısı oldukça parçalı (fragmented) ve farklı iş kurallarına sahip. Aşağıdaki API endpoint'leri ve mimari yapılar değişecek:

### Backend API'leri (`backend/app/routers/`)
1. **`GET /api/feed/recent`:** Karışık son ilanlar akışı (Misafirler için). 
2. **`GET /api/feed/for-you` (ve `personalized`):** Kullanıcı bütçesine, pgvector (yapay zeka) puanına ve `interest` (ilgi) tablosuna göre sıralanan ağır algoritmik feed.
3. **`GET /api/feed/hesitated`:** Sepette bırakılmış / tereddüt edilmiş ilanlar feed'i.
4. **`GET /api/search/explore`:** Keşfet sayfası. Giriş yapmış kullanıcılar için "ilgi alanına göre canlı yayınları", misafirler için "son ilanları" getirir.

### Backend İş Katmanı (`backend/app/use_cases/feed/queries/feed_queries.py`)
Mevcut kodda `/for-you` endpoint'i kısmen Redis kullanıyor (`feed:{user_id}:{seed}` caching) fakat Delta Fetching mekanizması yok. Tüm `FeedQueries` sınıfı "Önce SQL'den oku" yerine "Önce Redis'ten Oku (Yoksa MQ'ya tetik at)" mantığına geçirilecek.

### Mobile UI (`mobile/lib/screens/`)
Mobil tarafta Feed/Keşfet sayfalarındaki `RefreshIndicator` (Aşağı çekerek yenileme) işlemleri değişecek. API'ye `page=0` göndermek yerine `since_id=<ekrandaki_en_yeni_ilan_id>` gönderilip dönen verinin (sadece 1-2 yeni ilan) uygulamanın mevcut listesinin **en üstüne (prepend)** eklenmesi sağlanacak.

---

## 2. Maliyeti Ne Olacak? (Geliştirme ve Sistem Maliyeti)

### Geliştirme (Efor) Maliyeti: YÜKSEK
- **Worker/Cron Yazımı:** Redis feed listelerini arka planda dolduracak asenkron Python görevlerinin (arq/celery) yazılması gerekir.
- **Cache Invalidation:** Yeni bir ilan paylaşıldığında, bu ilanın kimin "for-you" (sana özel) feed'ine gireceğini hesaplayıp onların Redis listesine Push yapacak bir "Fan-out on write" (Yazmada Dağıtım) servisi kodlanmalıdır.
- **Frontend Refactoring:** State management (MobX/Provider) yapılarının baştan yazılan tüm listeyi silmek yerine delta (fark) ile merge edilmesi gerekir.

### Sistem (VPS) Maliyeti: NEGATİF (Büyük Tasarruf)
- **CPU (İşlemci) Kullanımı:** %80 oranında **düşecektir**. PGVector cosinus benzerlik hesaplamaları anlık değil, 15-30 dakikada bir arka planda sakin sakin hesaplanacak.
- **RAM (Bellek):** Burada endüstri standardı olan **"Normalize Edilmiş Cache (Akıllı Mimari)"** kullanılacaktır. İlanların tüm JSON verisi `Global Hash` olarak Redis'te tek bir kopyada tutulurken, kullanıcıların Feed'lerinde sadece 8 Byte'lık ilan ID'leri (Örn: `[1505, 9845]`) liste olarak tutulur. Bu sayede 10.000 aktif kullanıcı bile olsa maksimum **25-30 MB** gibi mikroskobik bir RAM tüketilir.
- **Veritabanı Yükü:** Saniyede yüzlerce çalışabilen `SELECT * FROM listings ORDER BY ...` SQL sorguları tamamen ortadan kalkar. Veritabanı sadece yeni veri yazıldığında çalışır.

---

## 3. Mimari Özet (Nasıl Çalışacak?)

> [!TIP]
> **Adım 1:** Kullanıcı uygulamayı açar, `GET /api/feed/for-you` atılır. Backend saniyenin binde biri hızda Redis'ten 20 adet ilanı (Hazır JSON) döner.
> **Adım 2:** Kullanıcı "Refresh" (aşağı çek) yapar. `GET /api/feed/for-you?since_id=9845` isteği atılır.
> **Adım 3:** Backend Redis'te `id > 9845` olan ilan var mı bakar. Yoksa `[]` döner. Varsa (Örn: 2 yeni ilan) sadece onları döner.
> **Adım 4:** Arka plandaki `FeedWorker` (cron), saat başı her kullanıcının zevklerini analiz edip Redis'teki o 500 ilanı sessizce günceller.

---

## 4. Sonsuz Kaydırma (Infinite Scroll) Durumu ve Trade-off'lar

Kullanıcı sadece sayfayı yenilemekle kalmaz, aynı zamanda aşağıya doğru kaydırarak (scroll) sayfa sayfa (Pagination) eski ilanları görmeye devam eder. Bu durum Redis mimarisinde nasıl çözülür?

**Sistem Nasıl Çalışır?**
1. **İlk 500 İlan (Redis Hızı):** Arka plandaki Worker, kullanıcı için örneğin en alakalı 500 ilanı Redis listesine dizer. Kullanıcı sayfa 1, sayfa 2, sayfa 10'a kadar kaydırdıkça API sadece Redis'ten okuma yapar (`LRANGE` komutu ile). Veritabanına hiç dokunulmaz.
2. **Kritik Eşik (Trade-off):** Kullanıcı 500. ilanı geçtiğinde (Örneğin 25. sayfaya geldiğinde) ne olacak? Redis listesinin sonuna gelinmiştir.
3. **Çözüm (Fallback to DB):** Kullanıcı 500. ilanı aştığı anda, API otomatik olarak Redis'i bırakır ve klasik SQL (PostgreSQL) veritabanı sorgusuna "Fallback" yapar (Yedek sisteme geçer).

**Neden Bu Yöntem Endüstri Standardıdır?**
Kullanıcıların %99'u bir oturuşta 500 ilanı (yaklaşık 25 sayfa kaydırma) geçmez. Çoğu kullanıcı ilk 2-3 sayfadan sonra uygulamadan çıkar veya yeni bir arama yapar. Biz sistemi o %99'luk dilim için Redis ile mükemmel optimize ediyoruz. %1'lik "derin kaydırıcı" kullanıcılar veritabanına ulaştığında, sunucu zaten çok rahatlamış olduğu için o azınlığın SQL yükünü çok rahat kaldırır.

### 4.1. Lazy Cache Refill & Watermark Pre-fetching (Bonus Optimizasyon)

Kullanıcı SQL veritabanına düşmek üzereyken (örneğin 25. sayfaya yaklaşırken), kullanıcının SQL sorgusu atmasını beklemeden **önbelleği tembel yolla doldurma (Lazy Cache Refill)** işlemi yapılabilir.

- **Watermark (Erken Uyarı):** API, kullanıcı Redis'teki 500 ilanın %80'ini (400. ilan / 20. sayfa) tükettiğinde bunu fark eder.
- **Background Trigger:** Kullanıcı 20. sayfanın verisini anında alırken, arka planda bir `Worker` tetiklenir: *"Git bu kullanıcı için 501. ile 1000. ilanları SQL'den hesapla ve Redis listesine ekle (Append)."*
- **Kusursuz Akış:** Kullanıcı kaydırmaya devam edip 25. sayfaya ulaştığında, veriler çoktan Redis'e yerleştirilmiş olur. Kullanıcı hiçbir "Yükleniyor (Loading)" gecikmesi veya veritabanı yavaşlığı hissetmez, sanki sonsuz bir Redis listesinde kaydırıyormuş gibi 50. sayfaya kadar ışık hızında devam eder.

---

## 5. Mimari Kurallara Uyum (`architectural_decisions.md`)

> [!IMPORTANT]
> **TEMEL KURAL (ŞERH):** Bu planın uygulanmasındaki tüm adımlar (Error/Exception handling, Backend loglama, DB bağlantı yaklaşımları, Mobile UI loading state'leri vb.) istisnasız olarak projenin ana anayasası olan `architectural_decisions.md` belgesine dayanmak zorundadır. Hiçbir task bu belgedeki pattern'ların dışına çıkamaz.

Bu caching mimarisi kurulurken, genel kuralların yanı sıra özellikle Feed ve ML tarafında şu kurallara kesinlikle sadık kalınacaktır:

1. **ML Veri Kaynakları:** `FeedWorker`, algoritmik sıralamayı oluştururken rastgele bir SQL sorgusu değil; arka planda BPR (haftada 3x) ve ALS (haftada 1x) tarafından hesaplanıp Redis'e basılmış olan `bpr:rec:{uid}` ve `feed:als:user_vec:{uid}` veri setlerini temel alacaktır.
2. **Greedy Diversity Kuralı:** İlanlar Redis feed listesine itilmeden (push) önce, `architectural_decisions.md`'de belirtilen `MAX_PER_SUBCAT=2` kuralı uygulanacak; böylece kullanıcının feed'i peş peşe aynı alt-kategoriden (örn: arka arkaya 10 tane sedan araba) ilanlarla dolmayacaktır.
3. **Gerçek Veri Önceliği:** Alt kategori (subcategory) ağırlıkları feed'e eklenirken, önce `user_events` tablosunda yeterli (2-4 hafta) gerçek kullanıcı sinyalinin birikmesi beklenecek, mock (sahte) verilerle ML modelleri kesinlikle manipüle edilmeyecektir.
