# Teqlif MVVM Refactor Kılavuzu

Bu döküman, Teqlif uygulamasının mevcut "Fat View" (StatefulWidget merkezli) yapısından, **Riverpod tabanlı temiz MVVM (Model-View-ViewModel)** mimarisine geçişini koordine etmek için hazırlanmıştır.

## 🎯 Vizyon ve Strateji
Tüm ekranlara aynı anda müdahale etmek yerine, önce bir **Pilot Ekran** (Örn: `login_screen.dart`) seçilerek MVVM dönüşümü yapılacaktır. 
Bu pilot dönüşüm sırasında elde edilen tüm deneyimler, Riverpod state-management kurguları ve karşılaşılan zorlukların çözümleri bu dökümanın "Öğrenilenler ve Standartlar" bölümüne işlenecektir. Ardından bir **Refactor Döngüsü** başlatılarak aşağıdaki listede bulunan tüm ekranlar teker teker bu standarda yükseltilecektir.

## 🛠 Refactor Döngüsü (Cycle)
Her bir ekran için şu adımlar izlenmelidir:
1. Ekranın mevcut State mantığı (API çağrıları, form validation, error handling) incelenir.
2. İlgili feature klasörü altında (örn: `lib/screens/auth/viewmodels/`) `EkranAdiViewModel` adında bir `AsyncNotifier` veya `Notifier` oluşturulur.
3. UI (View) tarafındaki tüm `setState` ve API çağrıları silinir, Widget `ConsumerWidget`'a çevrilerek ViewModel'e bağlanır (`ref.watch`).
4. Test edilir ve aşağıdaki listeye `[x]` atılır.

## 💡 Öğrenilenler ve MVVM Standartları (Pilot Ekrandan Sonra Doldurulacak)
- *Pilot ekran (Login Screen) refactor edildikten sonra, Riverpod kullanımı, form yönetimi ve hata yakalama standartlarımız buraya madde madde eklenecektir.*

---

## 📱 Ekranlar ve Refactor Durumu

### Auth (Kimlik Doğrulama)
- [ ] `mobile/lib/screens/auth/category_onboarding_screen.dart`
- [ ] `mobile/lib/screens/auth/forgot_password_screen.dart`
- [ ] `mobile/lib/screens/auth/login_screen.dart` (Pilot Ekran)
- [ ] `mobile/lib/screens/auth/register_screen.dart`
- [ ] `mobile/lib/screens/auth/reset_password_screen.dart`
- [ ] `mobile/lib/screens/auth/verify_screen.dart`

### Ana Ekranlar ve Gezinme
- [ ] `mobile/lib/screens/splash_screen.dart`
- [ ] `mobile/lib/screens/main_screen.dart`
- [ ] `mobile/lib/screens/home_screen.dart`
- [ ] `mobile/lib/screens/search_screen.dart`
- [ ] `mobile/lib/screens/messages_screen.dart`
- [ ] `mobile/lib/screens/profile_screen.dart`

### İlanlar (Listings)
- [ ] `mobile/lib/screens/create_listing_screen.dart`
- [ ] `mobile/lib/screens/edit_listing_screen.dart`
- [ ] `mobile/lib/screens/listing_detail_screen.dart`

### Canlı Yayın (Live & Story)
- [ ] `mobile/lib/screens/live/host_stream_screen.dart`
- [ ] `mobile/lib/screens/live/live_list_screen.dart`
- [ ] `mobile/lib/screens/live/seller_report_screen.dart`
- [ ] `mobile/lib/screens/live/swipe_live_screen.dart`
- [ ] `mobile/lib/screens/story/story_viewer_screen.dart`

### Arama & İletişim (Call)
- [ ] `mobile/lib/screens/call_history_screen.dart`
- [ ] `mobile/lib/screens/call_screen.dart`
- [ ] `mobile/lib/screens/incoming_call_screen.dart`

### Profil, Ayarlar & Sosyal
- [ ] `mobile/lib/screens/account_info_screen.dart`
- [ ] `mobile/lib/screens/blocked_users_screen.dart`
- [ ] `mobile/lib/screens/faq_screen.dart`
- [ ] `mobile/lib/screens/follow_list_screen.dart`
- [ ] `mobile/lib/screens/follow_requests_screen.dart`
- [ ] `mobile/lib/screens/force_update_screen.dart`
- [ ] `mobile/lib/screens/notification_settings_screen.dart`
- [ ] `mobile/lib/screens/public_profile_screen.dart`

### Analitik & Pro Araçları
- [ ] `mobile/lib/screens/competitor_radar_screen.dart`
- [ ] `mobile/lib/screens/demand_trends_screen.dart`
- [ ] `mobile/lib/screens/listing_analytics_screen.dart`
- [ ] `mobile/lib/screens/live_stream_analytics_screen.dart`
- [ ] `mobile/lib/screens/live_stream_history_screen.dart`
- [ ] `mobile/lib/screens/market_intelligence_screen.dart`
- [ ] `mobile/lib/screens/pro_hub_screen.dart`
- [ ] `mobile/lib/screens/pro_insights_screen.dart`
- [ ] `mobile/lib/screens/pro_stream_analytics_screen.dart`
- [ ] `mobile/lib/screens/retargeting_screen.dart`

### İşlemler (Ticaret)
- [ ] `mobile/lib/screens/ad_report_screen.dart`
- [ ] `mobile/lib/screens/my_ratings_screen.dart`
- [ ] `mobile/lib/screens/purchase_detail_screen.dart`
- [ ] `mobile/lib/screens/purchases_screen.dart`
- [ ] `mobile/lib/screens/sale_detail_screen.dart`
- [ ] `mobile/lib/screens/sales_screen.dart`

### Test
- [ ] `mobile/lib/screens/teq_test_screen.dart`
