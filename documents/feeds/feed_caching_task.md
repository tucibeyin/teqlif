# Feed Caching ve Optimizasyon Görevleri (Tasks)

> [!IMPORTANT]
> **BAĞIMLILIK ZİNCİRİ VE İŞ AKIŞI (ŞERH):** Bu görev (task) listesinde yer alan her bir madde uygulanırken;
> 1. Doğrudan `documents/feeds/feed_caching_plan.md` belgesindeki mimari yönlendirmelere harfiyen uyulacaktır.
> 2. `feed_caching_plan.md` ise uygulamanın ana anayasası olan `documents/architectural_decisions.md` belgesine tabiidir (Error handling, UI state vb.).
> 3. **WORKFLOW KURALI:** Her bir görev (task) adımı bittiğinde anında Git commit'i atılacak, bu belgedeki ilgili görevin yanına tarih ve commit hash bilgisi eklenecek, ve KULLANICIDAN (User) ONAY BEKLENMEDEN asla bir sonraki göreve geçilmeyecektir.
> 
> Yalnızca bu zincire ve akışa (Architectural Decisions -> Plan -> Task -> Commit -> Onay) uygun olan kod parçaları sisteme entegre edilebilir.

Bu belge, yukarıdaki bağımlılık zinciri uyarınca backend ve mobil tarafta yapılacak işlerin adım adım takibini sağlamak amacıyla oluşturulmuştur.

## 1. Veri Yapısı ve Temel Redis Kurulumu
- [x] **Global Listing Hash Kurulumu:** İlan oluşturulduğunda veya güncellendiğinde, ilanın JSON detayının Redis üzerinde `listing:{id}` olarak (Global Hash) saklanmasını sağlayan servisin yazılması. *(04.08.2026 - efa77b0c)*
- [x] **Cache Invalidation:** İlan silindiğinde veya pasife alındığında `listing:{id}` verisinin Redis'ten temizlenmesi. *(04.08.2026 - efa77b0c)*
- [x] **Redis Feed Lists:** Her kullanıcı için Redis üzerinde `feed:{user_id}:recent`, `feed:{user_id}:foryou` şeklinde `List` (veya `Sorted Set`) yapıları oluşturmak için yardımcı (helper) sınıfların yazılması. *(04.08.2026 - efa77b0c)*

## 2. Arka Plan Görevleri (Workers / Fan-out)
- [x] **Recent Feed Worker:** Sisteme yeni bir ilan eklendiğinde (Fan-out on write), misafirlerin ve genel kullanıcıların "Son İlanlar" (Recent) listesine bu ID'nin `LPUSH` edilmesi. Limit 500 ile sınırlandırılmalı (`LTRIM`). *(04.08.2026 - efa77b0c)*
- [x] **For-You Feed Worker (Cron):** Her aktif kullanıcının ilgi alanlarını (interests) ve pgvector puanlarını değerlendirip saatte/günde bir "Sana Özel" (For You) Redis listesini (min 500 ID) baştan dolduran arq/celery görevinin yazılması. *(04.08.2026 - a4e431e6)*
- [x] **Lazy Cache Refill (Watermark):** Feed üzerinden okuma yapılırken liste sonuna yaklaşıldığında (örneğin %80'i bittiğinde), sıradaki 500 ilanı asenkron olarak liste ucuna ekleyen trigger (tetikleyici) yapısının kurulması. *(04.08.2026 - efa77b0c)*

## 3. Backend API Güncellemeleri (Delta Fetching & Fallback)
- [x] **`since_id` Desteği:** `routers/feed.py` ve `routers/search.py` altındaki endpoint'lerin query parametresi olarak `since_id` kabul edecek şekilde güncellenmesi. *(04.08.2026 - efa77b0c)*
- [x] **Redis'ten Okuma Entegrasyonu:** `FeedQueries` metodlarının (`get_mixed_recent_feed`, `get_foryou_feed` vb.) SQL yerine doğrudan Redis'ten (Örn: `LRANGE feed:{user_id}:recent 0 19`) veriyi çekecek şekilde refactor edilmesi. *(04.08.2026 - efa77b0c)*
- [x] **DB Fallback Mekanizması & Error Handling:** İstenen sayfa/offset Redis limitini aştığında veya Redis anlık çöktüğünde (Timeout), sistemin `architectural_decisions.md`'deki standart exception kurallarını uygulayarak yumuşak bir şekilde (graceful) `PostgreSQL` sorgularına dönmesini sağlayan kontrol bloklarının yazılması. *(04.08.2026 - efa77b0c)*
- [x] **Data Merging:** Redis'ten alınan ID'lerin, Global Hash üzerinden JSON nesnelerine çevrilip client'a liste olarak dönülmesi. *(04.08.2026 - efa77b0c)*
- [x] **Telemetri (ClickHouse) Koruması:** Redis'ten veri dönülse dahi, `architectural_decisions.md`'de belirtilen `feed_telemetry` loglarının (kullanıcıların hangi alt-kategorileri gördüğü) kaybolmaması için ClickHouse sinyal akışının korunması. *(04.08.2026 - efa77b0c)*

## 4. Mobile (Frontend) Entegrasyonu
- [x] **Pull-to-Refresh Güncellemesi:** Keşfet ve İlanlar sayfalarındaki "Aşağı çekerek yenileme" aksiyonunun tüm listeyi sıfırlamak yerine `since_id=<ekrandaki_en_yeni_ilan_id>` parametresiyle API isteği atması. *(04.08.2026 - 4d69568e)*
- [x] **Delta Merging (State Management):** API'den sadece yeni ilanlar geldiğinde, MobX/Provider/BLoC state yöneticisinin bu yeni ilanları mevcut listenin en üstüne (prepend) sorunsuzca eklemesi. *(04.08.2026 - 4d69568e)*
- [x] **Infinite Scroll Uyumu:** Liste sonuna gelindiğinde standart pagination (sayfa + 1) isteğinin atılmaya devam etmesi ve State listesinin sonuna (append) yeni sayfaların eklenmesi. *(04.08.2026 - 4d69568e)*
- [x] **UI Loading State Uyumu:** Refresh veya Scroll sırasında ekranda gösterilecek "Yükleniyor" durumlarının, `architectural_decisions.md` "5. Async Buton Loading Pattern" bölümündeki kurallara sadık kalarak, manuel `_loading = true` (setState) yerine standart Provider State (`isLoading: notifier.isSending`) ile yönetilmesi. *(04.08.2026 - 4d69568e)*
