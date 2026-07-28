# Swipe Live Algorithms & Subcategory Task List

- `[x]` **Backend: Schema & Endpoint Update**
  - `backend/app/schemas/stream.py` içerisinde `subcategory` alanının kontrol edilmesi (Zaten var!).
  - `backend/app/routers/leads.py` içerisindeki `BlastRequest` şemasına `subcategory: str = Field(default="")` eklenmesi.
  - `backend/app/routers/leads.py` içerisindeki `audience_size` endpoint'ine `subcategory: str = Query(default="")` eklenmesi.
  - `backend/app/routers/leads.py` içerisindeki `send_blast` endpoint'inde Firebase Push Notification metninin `[{body.subcategory}] {body.title}` formatında özelleştirilmesi.

- `[x]` **Frontend: Stream Start Dialog**
  - `mobile/lib/utils/start_stream_helper.dart` içerisinde `selectedSubcategory` state değişkeni eklenmesi.
  - `CategoryService` yerine (veya ek olarak) `CatalogService` üzerinden ana kategoriye ait alt kategorilerin fetch edilip dropdown listesinin doldurulması.
  - İkinci bir `DropdownButtonFormField` eklenerek UI'ın tasarlanması (İkonlu DropdownMenuItem yapısı).
  - Sadece Alt Kategori de seçildiğinde (eğer o kategorinin alt kategorisi varsa) Blast hedef kitle (audience) hesabının tetiklenmesi.
  - Alt kategori yoksa (Örn: Sohbet) 2. Dropdown gizlenip doğrudan Blast hesabının yapılması.
  - API isteklerine (`StreamService.startStream` ve `AnalyticsService.getAudienceSize/sendLeadBlast`) `subcategory` parametresinin dahil edilmesi.

- `[x]` **Frontend: Live List Cascading Chips UI**
  - `mobile/lib/screens/live/live_list_screen.dart` içerisinde seçilen ana kategoriye (`_selectedCategory`) bağlı olarak `_selectedSubcategory` state'i eklenmesi.
  - Kategorilerin altında, o kategoriye ait aktif yayınların alt kategorilerini toplayan dinamik bir çip (chip) listesinin (Örn: Tümü, Yüz Yüze, Maskeli) render edilmesi.
  - Yayın filtreleme fonksiyonunun (`_filtered` ve `_filteredRecommended`) hem kategori hem alt kategoriye göre çalışacak şekilde güncellenmesi.

- `[x]` **Tracking, ML ve ARB Tercümeleri (YENİ)**
  - `mobile/lib/screens/live/swipe_live_screen.dart` içerisindeki ML Tracking Dwell Time eşiklerinin revize edilmesi:
    - `Canlı Yayınlar (Stream)` için:
      - `<3sn` → Skip (Data gönderilmez veya izlendi sayılmaz)
      - `3-10sn` → Glance (Göz attı)
      - `>10sn` → Dwell (İzledi)
    - `İlanlar (Listing)` için (eğer swipe ekranında ilan geçiliyorsa):
      - `<1.5sn` → Skip
      - `1.5-4sn` → Glance
      - `>4sn` → Dwell
  - Yeni eklenecek alt kategoriler için `cat_...` (Örn: `cat_bilgisayar`) key'lerinin `intl_tr.arb` ve `intl_en.arb` dosyalarına işlenmesi.

- `[x]` **Test ve Doğrulama**
  - Yayın oluştururken alt kategorinin DB'ye doğru kaydedildiğinin doğrulanması.
  - Kitle hesabının (Blast estimate) alt kategoriye göre spesifik daraldığının (daha az sayı çıkardığının) teyit edilmesi.
  - Push bildiriminin köşeli parantez içinde alt kategori etiketiyle (Örn: `[MOBİLYA] Kampanya!`) atıldığının teyidi.
  - Tracking 3-Tier Dwell Algoritmasının 12 saniyelik bir beklemede "dwell" gönderdiğinin teyidi.
