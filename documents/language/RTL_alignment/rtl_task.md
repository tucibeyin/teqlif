# RTL Alignment Task List

## Şerh 1: Plan Referansı
Bu dosyadaki görevler, `documents/language/RTL_alignment/rtl_alignment.plan.md` planının uygulama adımlarıdır.

## Şerh 2: İşlem Kaydı
Her bir görev adımı tamamlandığında, yapılan değişiklikler Git'e commit edilecek, göreve onay işareti (tick) konulacak ve tamamlandığı commit numarası, tarih/saat eklenecektir.

---

## 🎯 Vizyon ve Strateji: Ne Yapıyoruz ve Neden?

Flutter'ın native olarak mükemmel bir **RTL (Sağdan Sola)** desteği vardır. Uygulamamızın `main.dart` dosyasında Arapça (`Locale('ar')`) ve tüm lokalizasyon delegateleri aktif durumdadır. Yani ekstra bir kütüphaneye veya teknolojiye ihtiyacımız yoktur.

Ancak şu an Arapça seçildiğinde arayüzün (UI) bozuk veya kafa karıştırıcı görünmesinin temel sebebi şudur: **Geliştirme sırasında ekranlar kodlanırken sabit (hardcoded) yön belirten komutların kullanılmış olması.**

### Hatalı Düşünce: Sadece Metinleri Hizalamak
Metinlerin nerede gösterildiğini `loc.t` ile kolayca bulabileceğimiz fikri doğru olsa da, **RTL desteği sadece metnin hizalanması demek değildir.** 

RTL'i tüm ekranın **ayna görüntüsü (mirroring)** olarak düşünmeliyiz. Mesela bir ilanın kartında solda resim, ortada isim, sağda fiyat varsa; Arapça'da sağda resim, ortada isim, solda fiyat olması gerekir. Sadece ismin nerede durduğunu bilmek yetmez, o ilanın içindeki resimle isim arasındaki 10 piksellik boşluğun da aynalanması gerekir. Aksi halde metin Arapça olur ama 10 piksellik boşluk solda kaldığı için resme yapışık, çirkin bir görüntü oluşur.

Bu yüzden stratejimiz metin (Text) odaklı değil, **Layout (Düzen) odaklı** olmalıdır.

### Dönüşüm Kuralları
Kod içerisindeki sabit `left` ve `right` tanımlarını, `start` ve `end` mantığıyla çalışan **Directional** karşılıklarıyla değiştirmeliyiz:

**Yanlış (LTR'ye sabitlenmiş) Kullanımlar:**
- `padding: EdgeInsets.only(left: 16)` *(Arapça'da da soldan boşluk bırakır, düzeni bozar)*
- `alignment: Alignment.topLeft` *(Arapça'da da yazıyı sola yaslar)*
- `Positioned(left: 10, ...)` *(İkonu her zaman sola çiviler)*

**Doğru (RTL Uyumlu) Kullanımlar:**
- `padding: EdgeInsetsDirectional.only(start: 16)` *(İngilizcede soldan, Arapçada sağdan boşluk bırakır)*
- `alignment: AlignmentDirectional.topStart` *(Dile göre otomatik yer değiştirir)*
- `Positioned.directional(textDirection: Directionality.of(context), start: 10, ...)`

---

## 📱 Ekranlar ve RTL Dönüşüm Durumu

### Auth (Kimlik Doğrulama)
- [x] `mobile/lib/screens/auth/login_screen.dart` (Pilot Ekran) - *Tamamlandı: 2026-08-04*
- [x] `mobile/lib/screens/auth/category_onboarding_screen.dart` - *Tamamlandı: 2026-08-04*
- [x] `mobile/lib/screens/auth/forgot_password_screen.dart` - *Tamamlandı: 2026-08-04*
- [x] `mobile/lib/screens/auth/register_screen.dart` - *Tamamlandı: 2026-08-04*
- [x] `mobile/lib/screens/auth/reset_password_screen.dart` - *Tamamlandı: 2026-08-04*
- [x] `mobile/lib/screens/auth/verify_screen.dart` - *Tamamlandı: 2026-08-04*

### 2. Ana Ekranlar ve Gezinme (Batch 2)
- [x] `mobile/lib/screens/splash_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/main_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/home_screen.dart` - *Tamamlandı [853eb887]: 2026-08-04*
- [x] `mobile/lib/screens/search_screen.dart` - *Tamamlandı [853eb887]: 2026-08-04*
- [x] `mobile/lib/screens/messages_screen.dart` - *Tamamlandı [853eb887]: 2026-08-04*
- [x] `mobile/lib/screens/profile_screen.dart` - *Tamamlandı [853eb887]: 2026-08-04*

### Canlı Yayın (Live & Story)
- [x] `mobile/lib/screens/live/host_stream_screen.dart` - *Tamamlandı [8247cd26]: 2026-08-04*
- [x] `mobile/lib/screens/live/live_list_screen.dart` - *Tamamlandı [8247cd26]: 2026-08-04*
- [x] `mobile/lib/screens/live/seller_report_screen.dart` - *Tamamlandı [8247cd26]: 2026-08-04*
- [x] `mobile/lib/screens/live/swipe_live_screen.dart` - *Tamamlandı [8247cd26]: 2026-08-04*
- [x] `mobile/lib/screens/story/story_viewer_screen.dart` - *Tamamlandı [8247cd26]: 2026-08-04*

### Arama & İletişim (Call)
- [x] `mobile/lib/screens/call_history_screen.dart` - *Tamamlandı [f97f0fbb]: 2026-08-04*
- [x] `mobile/lib/screens/call_screen.dart` - *Tamamlandı [f97f0fbb]: 2026-08-04*
- [x] `mobile/lib/screens/incoming_call_screen.dart` - *Tamamlandı [f97f0fbb]: 2026-08-04*

### Profil, Ayarlar & Sosyal
- [x] `mobile/lib/screens/account_info_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/blocked_users_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/faq_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/follow_list_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/follow_requests_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/force_update_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/notification_settings_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*
- [x] `mobile/lib/screens/public_profile_screen.dart` - *Tamamlandı [f1990c2a]: 2026-08-04*

### Analitik & Pro Araçları
- [x] `mobile/lib/screens/competitor_radar_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/demand_trends_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/listing_analytics_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/live_stream_analytics_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/live_stream_history_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/market_intelligence_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/pro_hub_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/pro_insights_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/pro_stream_analytics_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*
- [x] `mobile/lib/screens/retargeting_screen.dart` - *Tamamlandı [1c18b94a]: 2026-08-04*

### İşlemler (Ticaret)
- [x] `mobile/lib/screens/ad_report_screen.dart` - *Tamamlandı [4368dbb2]: 2026-08-04*
- [x] `mobile/lib/screens/my_ratings_screen.dart` - *Tamamlandı [4368dbb2]: 2026-08-04*
- [x] `mobile/lib/screens/purchase_detail_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/purchases_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/sale_detail_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*
- [x] `mobile/lib/screens/sales_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*

### Test
- [x] `mobile/lib/screens/teq_test_screen.dart` - *Tamamlandı (Değişiklik Gerekmedi): 2026-08-04*

### Bileşenler (Widgets & UI Library)
- [x] `mobile/lib/widgets/...` (Tüm alt klasörler tarandı) - *Tamamlandı [c4adde94]: 2026-08-04*
- [x] `mobile/lib/ui_library/...` (Tüm alt klasörler tarandı) - *Tamamlandı [c4adde94]: 2026-08-04*
