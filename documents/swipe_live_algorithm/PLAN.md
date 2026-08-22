# Hedef: Canlı Yayınlara Uçtan Uca Alt Kategori (Subcategory) Entegrasyonu

Canlı yayınlara (Live Streams) alt kategori desteğinin eklenmesi için yapılan uçtan uca sistem mimarisi analizi sonucunda plan güncellenmiştir. Sistemde API'ler, DB, ML veri akışı, Blast algoritmaları ve ARB tercümelerinin tamamı bu değişime adapte edilecektir.

## Uçtan Uca Sistem Analizi & Kararlar

1. **Veritabanı (DB):** `live_streams` tablosunda `subcategory` kolonu ve `subcategories` tablosu halihazırda var. DB yapısı değişmeden kullanılabilecek (Migration gerekmiyor).
2. **Blast FCM Push Bildirimleri (Özelleştirme):** `POST /api/leads/send-blast` endpoint'i `subcategory` alacak. Push bildirimi atılırken bildirim metni (Notification Body) `[Alt Kategori] Yayın Başlığı` formatında özelleştirilecek. Bu sayede Tıklama Oranı (CTR) ciddi şekilde artacak. *(Kullanıcı tarafından onaylandı)*
3. **Tracking & ML (Yapay Zeka):** `swipe_live_screen.dart` içerisinde tracking payload'ı incelendi, halihazırda `stream_subcategory` parametresi gönderiliyor. Yani yayınlara alt kategori eklendiği an, ClickHouse logları ve ML (vektör/embedding) eşleşmeleri **kod değişikliği olmadan** otomatik olarak çok daha spesifik hale gelecek!
4. **ARB Tercümeleri:** UI'da alt kategoriler gösterilirken `loc.t('cat_$subKey')` yapısı kullanılacak. ARB dosyalarına (Örn: `cat_bilgisayar`, `cat_telefon`) bu anahtarlar eklenecek.
5. **Alt Kategori Yoksa Davranış:** Seçilen ana kategorinin altında hiçbir alt kategori yoksa (Örn: Chat/Sohbet), Alt Kategori menüsü gizlenecek ve sistem sanki doğrudan seçilmiş gibi Blast hesabını başlatacaktır. *(Kullanıcı tarafından onaylandı)*
6. **Alt Kategori İkonları:** Alt kategori menüsünde ve çiplerde sadece metin değil, sistem ikon havuzundan alt kategoriye uygun Material/Cupertino ikonları dinamik olarak (veya statik haritalamayla) eşleştirilip gösterilecektir. *(Kullanıcı tarafından eklendi)*

## Yeni Eklenti: Tracking ve "Dwell Time" (İzleme Süresi) Algoritması
Mobil koddaki (`swipe_live_screen.dart`) mevcut durumu analiz ettim: Şu anda kullanıcı bir yayında 2 saniyeden fazla kalırsa ML'e **"dwell" (ilgilendi)** olarak gidiyor. Ancak canlı yayın bağlantı süresi + buffer hesaba katıldığında 2 saniye ML (yapay zeka) verisini **kirleten (false positive)** bir eşiktir. 

Yapay zeka verisinin tutarlılığını sağlamak için veri toplama mimarisini şu **3 aşamalı (Tier)** eşik yapısına geçireceğiz:

- **Canlı Yayın Eşikleri:**
  - `0 - 3 saniye`: **skip** (Hızlı geçiş / İlgilenmedi. ML bu veriyi yok sayar)
  - `3 - 10 saniye`: **glance** (Göz attı. Zayıf pozitif sinyal)
  - `10+ saniye`: **dwell** (Kaldı ve izledi. Güçlü pozitif sinyal)
- **İlan (Listing) Eşikleri:** (İlanlar daha hızlı tüketildiği için eşikler farklıdır)
  - `0 - 1.5 saniye`: **skip**
  - `1.5 - 4 saniye`: **glance**
  - `4+ saniye`: **dwell**

*(Bu sayede yapay zekayı eğiten verilerde "Hızlıca kaydırırken yanlışlıkla 2 sn bekledi" gibi hatalı ilgi alanı eşleşmelerinin önüne tamamen geçilecektir.)*

## Önerilen Değişiklikler

### 1. Backend (Python/FastAPI)

#### [MODIFY] [backend/app/routers/leads.py](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/leads.py)
- `BlastRequest` şemasına `subcategory: str = Field(default="")` eklenecek.
- `audience_size` endpoint'ine `subcategory: str = Query(default="")` eklenecek ve DB sorgusunda `listing_q.where(Listing.subcategory == subcategory)` filtresi uygulanacak.
- `send_blast` endpoint'inde, Firebase'e giden `notif_body` formatı `f"[{body.subcategory.upper()}] {body.title}"` şeklinde özelleştirilecek.

---

### 2. Frontend (Mobil Uygulama)

#### [MODIFY] [mobile/lib/utils/start_stream_helper.dart](file:///Users/tucibeyin/Desktop/teqlif/mobile/lib/utils/start_stream_helper.dart)
- `CategoryService` yerine (veya ek olarak) `CatalogService` kullanılarak seçilen ana kategoriye ait alt kategoriler dinamik olarak fetch edilecek.
- Arayüze "Alt Kategori" için ikinci bir `DropdownButtonFormField` eklenecek ve içerisindeki `DropdownMenuItem`'lar ikon barındıracak.
- Alt kategori listesi boş gelirse, bu menü `SizedBox.shrink()` ile gizlenip `audience_size` hemen çalıştırılacak.
- API'ye (StreamService ve AnalyticsService) `subcategory` datası gönderilecek.

#### [MODIFY] [mobile/lib/screens/live/swipe_live_screen.dart](file:///Users/tucibeyin/Desktop/teqlif/mobile/lib/screens/live/swipe_live_screen.dart)
- `dwellMs` hesabı güncellenecek ve ML'e giden eventler yukarıda belirlenen `skip`, `glance`, `dwell` threshold'larına göre ayrıştırılacak.

#### [MODIFY] [mobile/lib/services/analytics_service.dart](file:///Users/tucibeyin/Desktop/teqlif/mobile/lib/services/analytics_service.dart)
- `sendLeadBlast` metoduna `String? subcategory` parametresi eklenecek ve `leads/send-blast` API payload'una geçirilecek.

#### [MODIFY] [mobile/lib/screens/live/live_list_screen.dart](file:///Users/tucibeyin/Desktop/teqlif/mobile/lib/screens/live/live_list_screen.dart)
- "Cascading Chips" UI entegre edilecek. Eğer seçili kategorinin alt kategorileri varsa, animasyonlu bir biçimde ikonlu çipleri barındıran ikinci satır (Alt Kategori Çipleri) görünecek.
- `_filtered` getter'ları bu yeni çipe göre veriyi süzecek.

#### [MODIFY] [ARBs] (intl_tr.arb / intl_en.arb vb.)
- Yeni eklenecek alt kategoriler için `cat_...` key'leri (örn: `cat_computers_tablets`) ilgili ARB dosyalarına işlenecek.

## Doğrulama Planı

### Test Adımları
1. Dialog açıldığında ana kategori seçilince, alt kategori yoksa doğrudan Blast hesaplanacak; varsa Alt Kategori menüsü **ikonlarıyla birlikte** görünecek ve seçimden sonra Blast hesaplanacak.
2. Yayıncı "Başlat" ve "Push Gönder" dediğinde, gönderilen Push Notification başlığının (Terminal loglarında) `[ALT_KATEGORI] Başlık` formatında olduğu doğrulanacak.
3. Tracking testinde yayın 3 saniyeden az izlenirse ML verisine `skip`, 12 saniye izlenirse `dwell` düştüğü Terminalden teyit edilecek.
4. İzleyici tarafında Cascading Chips'in ikonlu alt kırılımlarla geldiği ve filtrelemenin çalıştığı test edilecek.
