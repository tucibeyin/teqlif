# Merkezi Hata Yönetimi — Task Listesi

**Plan:** `PLAN.md`  
**Pilot ekran:** `create_listing_screen.dart` ✅ tamamlandı

---

## FAZ 1 — Backend: ARB → DB Deploy Pipeline

- [ ] **T01** — `backend/scripts/sync_translations.py` yaz
  - 4 ARB dosyasını (`app_tr`, `en`, `ar`, `ru`) okur
  - @-annotasyon satırlarını atlar
  - `translations` tablosuna `UPSERT` eder (key, lang, value)
  - Çalıştırıldığında kaç key sync'lendi yazar

- [ ] **T02** — VPS deploy komutunu güncelle
  - Eski: `git pull && sudo systemctl restart teqlif`
  - Yeni: `git pull && python3 backend/scripts/sync_translations.py && sudo systemctl restart teqlif`
  - `project_vps_deploy.md` memory'sini güncelle

- [ ] **T03** — VPS'te pipeline testi
  - ARB'a geçici test key ekle
  - Deploy et, `GET /api/i18n/tr` den key'in geldiğini doğrula
  - Test key'i geri al

---

## FAZ 2 — Flutter Core: handleError Tamamlama

- [ ] **T04** — `handleError` a 401/auth routing ekle (`lib/utils/error_helper.dart`)
  - `error is AppException && error.statusCode == 401` → `AuthService.logout()` + `TeqlifApp.navigatorKey` ile `/login`
  - Toast gösterme (yönlendirme mesaj yeterli)

- [ ] **T05** — `Result<T>` error type değiştir (`lib/core/result.dart` + `lib/config/api.dart`)
  - `Err<T>` içindeki `final AppError error` → `final Object error`
  - `api.dart` deki `AppError.from(e)` çağrıları → doğrudan `e`

- [ ] **T06** — `ErrorDisplay` sınıfını sil (`lib/core/error_display.dart`)
  - Dosyayı sil
  - İmport eden dosyaları bul ve import'u kaldır

- [ ] **T07** — `AppError` sealed class sil (`lib/core/app_error.dart`)
  - Dosyayı sil
  - Import eden dosyaları bul ve kaldır

- [ ] **T08** — `dart analyze` — sıfır hata (core refactor sonrası kontrol)

---

## FAZ 3 — Pilot Ekran Doğrulaması

- [ ] **T09** — `create_listing_screen.dart` review
  - `AppLocalizations`, `showErrorSnackbar`, `ErrorDisplay` kalmış mı kontrol et
  - `handleError` doğru şekilde kullanılıyor mu doğrula

---

## FAZ 4 — Ekran Migrasyonu: Error Handling

`showErrorSnackbar` ve `ErrorDisplay` kullanan ekranlar — OTA'ya geçmese bile error handling düzeltilir.

- [ ] **T10** — `screens/auth/forgot_password_screen.dart` — `ErrorDisplay` → `handleError`
- [ ] **T11** — `screens/auth/login_screen.dart` — `ErrorDisplay` → `handleError`
- [ ] **T12** — `screens/auth/register_screen.dart` — `ErrorDisplay` → `handleError`
- [ ] **T13** — `screens/auth/reset_password_screen.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T14** — `screens/auth/verify_screen.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T15** — `screens/follow_requests_screen.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T16** — `screens/my_ratings_screen.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T17** — `screens/profile_screen.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T18** — `utils/start_stream_helper.dart` — `showErrorSnackbar` → `handleError`
- [ ] **T19** — `screens/live/host_stream_screen.dart` — `ErrorDisplay` → `handleError`
- [ ] **T20** — `screens/live/swipe_live_screen.dart` — `ErrorDisplay` → `handleError`

- [ ] **T21** — `showErrorSnackbar` fonksiyonunu `error_helper.dart` dan sil

---

## FAZ 5 — Ekran Migrasyonu: OTA Localization

`AppLocalizations.of(context)` → `ref.watch(localizationProvider)` + `loc.t('key')`  
Her ekran: `StatefulWidget` → `ConsumerStatefulWidget`, `l.xxx` → `loc.t('xxx')`

### Auth ekranları
- [ ] **T22** — `screens/auth/login_screen.dart`
- [ ] **T23** — `screens/auth/register_screen.dart`
- [ ] **T24** — `screens/auth/forgot_password_screen.dart`
- [ ] **T25** — `screens/auth/reset_password_screen.dart`
- [ ] **T26** — `screens/auth/verify_screen.dart`
- [ ] **T27** — `screens/auth/category_onboarding_screen.dart`

### Ana ekranlar
- [ ] **T28** — `screens/home_screen.dart`
- [ ] **T29** — `screens/search_screen.dart`
- [ ] **T30** — `screens/main_screen.dart`

### İlan ekranları
- [ ] **T31** — `screens/edit_listing_screen.dart` ← create_listing ile aynı pattern
- [ ] **T32** — `screens/listing_detail_screen.dart` (49 kullanım — büyük ekran)
- [ ] **T33** — `screens/listing_analytics_screen.dart`

### Profil ekranları
- [ ] **T34** — `screens/profile_screen.dart` (87 kullanım — en büyük)
- [ ] **T35** — `screens/public_profile_screen.dart`
- [ ] **T36** — `screens/account_info_screen.dart`

### Live ekranları
- [ ] **T37** — `screens/live/host_stream_screen.dart` (49 kullanım)
- [ ] **T38** — `screens/live/swipe_live_screen.dart` (29 kullanım)
- [ ] **T39** — `screens/live/live_list_screen.dart`
- [ ] **T40** — `screens/live/seller_report_screen.dart`

### Mesajlaşma & sosyal
- [ ] **T41** — `screens/messages_screen.dart` (30 kullanım)
- [ ] **T42** — `screens/follow_requests_screen.dart`
- [ ] **T43** — `screens/follow_list_screen.dart`

### Ticaret & ödeme
- [ ] **T44** — `screens/sales_screen.dart`
- [ ] **T45** — `screens/sale_detail_screen.dart`
- [ ] **T46** — `screens/purchases_screen.dart`
- [ ] **T47** — `screens/purchase_detail_screen.dart`

### Analytics & Pro
- [ ] **T48** — `screens/competitor_radar_screen.dart` (34 kullanım)
- [ ] **T49** — `screens/demand_trends_screen.dart`
- [ ] **T50** — `screens/market_intelligence_screen.dart`
- [ ] **T51** — `screens/pro_hub_screen.dart`
- [ ] **T52** — `screens/pro_insights_screen.dart`
- [ ] **T53** — `screens/retargeting_screen.dart`
- [ ] **T54** — `screens/listing_analytics_screen.dart`
- [ ] **T55** — `screens/live_stream_analytics_screen.dart`
- [ ] **T56** — `screens/live_stream_history_screen.dart`
- [ ] **T57** — `screens/pro_stream_analytics_screen.dart`

### Diğer ekranlar
- [ ] **T58** — `screens/ad_report_screen.dart`
- [ ] **T59** — `screens/blocked_users_screen.dart`
- [ ] **T60** — `screens/call_screen.dart`
- [ ] **T61** — `screens/call_history_screen.dart`
- [ ] **T62** — `screens/faq_screen.dart`
- [ ] **T63** — `screens/force_update_screen.dart`
- [ ] **T64** — `screens/incoming_call_screen.dart`
- [ ] **T65** — `screens/my_ratings_screen.dart`
- [ ] **T66** — `screens/notification_settings_screen.dart`
- [ ] **T67** — `screens/story/story_viewer_screen.dart`

### Widget'lar
- [ ] **T68** — `widgets/auction_panel.dart` (32 kullanım)
- [ ] **T69** — `widgets/chat_panel.dart`
- [ ] **T70** — `widgets/live/story_tray.dart` (22 kullanım)
- [ ] **T71** — `widgets/live/host_top_bar.dart`
- [ ] **T72** — `widgets/live/viewer_top_bar.dart`
- [ ] **T73** — `widgets/live/gift_hud.dart`
- [ ] **T74** — `widgets/live/cohost_mod_sheet.dart`
- [ ] **T75** — `widgets/live/live_video_player.dart`
- [ ] **T76** — `widgets/live/pip_video_widget.dart`
- [ ] **T77** — `widgets/global_call_overlay.dart`
- [ ] **T78** — `widgets/global_keyboard_accessory.dart`
- [ ] **T79** — `widgets/incoming_call_overlay.dart`
- [ ] **T80** — `widgets/network_error_widget.dart`
- [ ] **T81** — `widgets/offline_banner.dart`
- [ ] **T82** — `widgets/phone_input_field.dart`
- [ ] **T83** — `widgets/soft_update_dialog.dart`
- [ ] **T84** — `widgets/stale_data_banner.dart`
- [ ] **T85** — `widgets/streamer_avatar_card.dart`
- [ ] **T86** — `widgets/swipe_to_bid_button.dart`

---

## FAZ 6 — Temizlik

- [ ] **T87** — `utils/snackbar_helper.dart` context parametrelerini kaldır
  - `showSuccessSnackbar(context, message)` → `showSuccessSnackbar(String message)` veya direkt `TeqToast.success(message)` kullan
- [ ] **T88** — `services/share_service.dart` AppLocalizations kullanımını gözden geçir
- [ ] **T89** — `dart analyze` — sıfır hata, tüm ekranlar migrate sonrası

---

## FAZ 7 — Son Test & Deploy

- [ ] **T90** — 4 dilde manuel test (TR / EN / AR / RU) — create_listing_screen, login, profile, listing_detail
- [ ] **T91** — Error senaryoları test: network hatası (uçak modu), 401 (oturumu kapat), 500 server hatası, validasyon hatası
- [ ] **T92** — Swipe-to-dismiss test
- [ ] **T93** — OTA doğrulama: DB'de bir çeviriyi güncelle, uygulama yeniden açılınca değişikliği gör
- [ ] **T94** — Commit + push + VPS deploy (sync_translations dahil)

---

## Notlar

- **Ekran önceliği:** Auth ekranları (T22–T27) → Ana ekranlar → Karmaşık ekranlar
- **Her ekrandan sonra** `dart analyze` çalıştır, biriken hata biriktirme
- **Widget migration:** Parent'tan `loc` parametresi almak da kabul edilebilir; her widget'ı `ConsumerWidget` yapmak zorunda değiliz
- **ARB dosyaları silinmez** — MaterialApp delegates için codegen çalışmaya devam eder
