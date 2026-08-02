# Teqlif MVVM Refactor Kılavuzu

Bu döküman, Teqlif uygulamasının mevcut "Fat View" (StatefulWidget merkezli) yapısından, **Riverpod tabanlı temiz MVVM (Model-View-ViewModel)** mimarisine geçişini koordine etmek için hazırlanmıştır.

## 🎯 Vizyon ve Strateji
Tüm ekranlara aynı anda müdahale etmek yerine, önce bir **Pilot Ekran** (Örn: `login_screen.dart`) seçilerek MVVM dönüşümü yapılacaktır. 
Bu pilot dönüşüm sırasında elde edilen tüm deneyimler, Riverpod state-management kurguları ve karşılaşılan zorlukların çözümleri bu dökümanın "Öğrenilenler ve Standartlar" bölümüne işlenecektir. Ardından bir **Refactor Döngüsü** başlatılarak aşağıdaki listede bulunan tüm ekranlar teker teker bu standarda yükseltilecektir.

## 🛑 Kritik Zorunluluk: Mimari Kararlar (Architectural Decisions)
Bu döküman üzerinden yapılacak her türlü refactor işlemi (Pilot ekran dahil), projede daha önce alınmış olan resmi mimari kararlara sıkı sıkıya bağlı kalmak **zorundadır.**
Tüm geliştirme (veya AI refactor) süreçlerinde **`documents/architectural_decisions.md`** dosyası mutlak referans olarak kabul edilmelidir. Error Handling (Toast/Banner), State Management (ViewModel kuralları) ve Localization standartları hiçbir ekranda esnetilemez.

## 🛠 Refactor Döngüsü (Cycle)
Her bir ekran için şu adımlar izlenmelidir:
1. Ekranın mevcut State mantığı (API çağrıları, form validation, error handling) incelenir.
2. İlgili feature klasörü altında (örn: `lib/screens/auth/viewmodels/`) `EkranAdiViewModel` adında bir `AsyncNotifier` veya `Notifier` oluşturulur.
3. UI (View) tarafındaki tüm `setState` ve API çağrıları silinir, Widget `ConsumerWidget`'a çevrilerek ViewModel'e bağlanır (`ref.watch`).
4. Test edilir ve aşağıdaki listeye `[x]` atılır.

## 💡 Öğrenilenler ve MVVM Standartları (Pilot Ekrandan Sonra Doldurulacak)
- **State Yönetimi:** ViewModel (`AsyncNotifier`), `build()` metodundan bir şey döndürmez (`void`). Yüklenme durumu (loading) asenkron metodun başında `state = const AsyncValue.loading()` ve bittiğinde `state = const AsyncValue.data(null)` yapılarak otomatik sağlanır. UI tarafında `ref.watch(viewModelProvider).isLoading` kullanılır.
- **UI Yönlendirmeleri (Routing):** ViewModel asla `BuildContext` almaz. Metodlar bir Enum (örn: `LoginResult`) döner. UI katmanındaki butonun `onPressed` fonksiyonu bu Enum'a göre sayfaları yönlendirir (`Navigator.push...`).
- **Hata Yönetimi (Error Handling):** Hatalar (API hataları vs.) UI'a fırlatılmadan önce ViewModel içinde `handleError(e, loc)` ile yakalanır (Bu kural `architectural_decisions.md`'den gelir). ViewModel hata durumunda `state = AsyncValue.error(e, st)` yapar ve geriye `LoginResult.error` döner.
- **UI Durumları (Pure UI State):** `TextEditingController`, `FocusNode` ve sadece görsel bir özelliği değiştiren `isObscure` gibi durumlar UI sınıfı (ConsumerStatefulWidget) içinde kalır. ViewModel'e taşınmaz.

---

## 📱 Ekranlar ve Refactor Durumu

### Auth (Kimlik Doğrulama)
- [x] `mobile/lib/screens/auth/category_onboarding_screen.dart`
- [x] `mobile/lib/screens/auth/forgot_password_screen.dart`
- [x] `mobile/lib/screens/auth/login_screen.dart` (Pilot Ekran)
- [x] `mobile/lib/screens/auth/register_screen.dart`
- [x] `mobile/lib/screens/auth/reset_password_screen.dart`
- [x] `mobile/lib/screens/auth/verify_screen.dart`

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
