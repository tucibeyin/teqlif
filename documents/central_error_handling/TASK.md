# Merkezi Hata Yönetimi — Task Listesi

**Plan:** `PLAN.md`  
**Pilot ekran:** `create_listing_screen.dart` ✅ tamamlandı

---

## FAZ 1 — Backend: ARB → DB Deploy Pipeline

- [x] **T01** — `backend/scripts/sync_translations.py` yaz ✅
  - 4 ARB dosyasını (`app_tr`, `en`, `ar`, `ru`) okur
  - @-annotasyon satırlarını atlar
  - `translations` tablosuna `UPSERT` eder (key, lang, value)
  - Çalıştırıldığında kaç key sync'lendi yazar

- [x] **T02** — VPS deploy komutunu güncelle ✅
  - Yeni: `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`
  - Migration varsa: `alembic upgrade head` öncesine eklenir
  - `project_vps_deploy.md` memory güncellendi

- [x] **T03** — VPS'te pipeline testi ✅
  - 7104 satır upsert edildi (tr:1775, en:1776, ar:1776, ru:1777)
  - `GET /api/i18n/tr` → `errorServerBusy` key'i doğrulandı

---

## FAZ 2 — Flutter Core: handleError Tamamlama

- [x] **T04** — `handleError` a 401/auth routing ekle (`lib/utils/error_helper.dart`) ✅
  - 401 geldiğinde `AuthService.authFailedStream.add(null)` sinyali verilir, `return` edilir
  - Toast gösterilmez — `main_screen._handleAuthFailed()` zaten logout + /login yapar
  - Çift navigation önlendi (ErrorDisplay'in eski yaklaşımı çift navigate ediyordu)

- [x] **T05** — `Result<T>` error type değiştir (`lib/core/result.dart` + `lib/config/api.dart`) ✅
  - `Err<T>` içindeki `final AppError error` → `final Object error`
  - `api.dart` deki `AppError.from(e)` → `e`, `app_error.dart` import'u kaldırıldı

- [x] **T06** — `ErrorDisplay` sınıfını sil (`lib/core/error_display.dart`) ✅
  - FAZ 4 tamamlandıktan sonra yapıldı

- [ ] **T07** — `AppError` sealed class sil (`lib/core/app_error.dart`)
  - ⚠️ Hâlâ bazı ekranlarda referans var — FAZ 5 OTA migrasyonlarından sonra silinecek

- [x] **T08** — `dart analyze` — sıfır hata ✅ (46 info, tümü önceden vardı)

---

## FAZ 3 — Pilot Ekran Doğrulaması

- [x] **T09** — `create_listing_screen.dart` review ✅ (pilot tamam, tüm pattern'lar uygulandı)
  - `AppLocalizations`, `showErrorSnackbar`, `ErrorDisplay` kalmış mı kontrol et
  - `handleError` doğru şekilde kullanılıyor mu doğrula

---

## FAZ 4 — Ekran Migrasyonu: Error Handling

`showErrorSnackbar` ve `ErrorDisplay` kullanan ekranlar — OTA'ya geçmese bile error handling düzeltilir.

- [x] **T10** — `screens/auth/forgot_password_screen.dart` — `ErrorDisplay` → `handleError` ✅
- [x] **T11** — `screens/auth/login_screen.dart` — `ErrorDisplay` → `handleError` ✅
- [x] **T12** — `screens/auth/register_screen.dart` — `ErrorDisplay` → `handleError` ✅
- [x] **T13** — `screens/auth/reset_password_screen.dart` — `showErrorSnackbar` → `handleError` ✅
- [x] **T14** — `screens/auth/verify_screen.dart` — `showErrorSnackbar` → `handleError` ✅
- [x] **T15** — `screens/follow_requests_screen.dart` — `showErrorSnackbar` → `handleError` ✅
- [x] **T16** — `screens/my_ratings_screen.dart` — `showErrorSnackbar` → `handleError` ✅
- [x] **T17** — `screens/profile_screen.dart` — `showErrorSnackbar` → `handleError` ✅
- [x] **T18** — `utils/start_stream_helper.dart` — `showErrorSnackbar` → `TeqToast.error` ✅
- [x] **T19** — `screens/live/host_stream_screen.dart` — `ErrorDisplay` → `handleError` ✅
- [x] **T20** — `screens/live/swipe_live_screen.dart` — `ErrorDisplay` → `handleError` ✅

- [x] **T21** — `showErrorSnackbar` fonksiyonunu `error_helper.dart` dan sil ✅

---

## FAZ 5 — Ekran Migrasyonu: OTA Localization

`AppLocalizations.of(context)` → `ref.watch(localizationProvider)` + `loc.t('key')`  
Her ekran: `StatefulWidget` → `ConsumerStatefulWidget`, `l.xxx` → `loc.t('xxx')`

### Auth ekranları ✅ Tümü tamamlandı
- [x] **T22** — `screens/auth/login_screen.dart` ✅
- [x] **T23** — `screens/auth/register_screen.dart` ✅
- [x] **T24** — `screens/auth/forgot_password_screen.dart` ✅
- [x] **T25** — `screens/auth/reset_password_screen.dart` ✅
- [x] **T26** — `screens/auth/verify_screen.dart` ✅
- [x] **T27** — `screens/auth/category_onboarding_screen.dart` ✅

### Ana ekranlar ✅ Tümü tamamlandı
- [x] **T28** — `screens/home_screen.dart` ✅
- [x] **T29** — `screens/search_screen.dart` ✅
- [x] **T30** — `screens/main_screen.dart` ✅

### İlan ekranları ✅ Tümü tamamlandı
- [x] **T31** — `screens/edit_listing_screen.dart` ✅
- [x] **T32** — `screens/listing_detail_screen.dart` ✅
- [x] **T33** — `screens/listing_analytics_screen.dart` ✅

### Profil ekranları ✅ Tümü tamamlandı
- [x] **T34** — `screens/profile_screen.dart` ✅
- [x] **T35** — `screens/public_profile_screen.dart` ✅
- [x] **T36** — `screens/account_info_screen.dart` ✅

### Live ekranları
- [x] **T37** — `screens/live/host_stream_screen.dart` ✅
- [x] **T38** — `screens/live/swipe_live_screen.dart` ✅
- [x] **T39** — `screens/live/live_list_screen.dart` ✅
- [x] **T40** — `screens/live/seller_report_screen.dart` ✅

### Mesajlaşma & sosyal ✅ Tümü tamamlandı
- [x] **T41** — `screens/messages_screen.dart` ✅
- [x] **T42** — `screens/follow_requests_screen.dart` ✅
- [x] **T43** — `screens/follow_list_screen.dart` ✅

### Ticaret & ödeme ✅ Tümü tamamlandı
- [x] **T44** — `screens/sales_screen.dart` ✅
- [x] **T45** — `screens/sale_detail_screen.dart` ✅
- [x] **T46** — `screens/purchases_screen.dart` ✅
- [x] **T47** — `screens/purchase_detail_screen.dart` ✅

### Analytics & Pro ✅ Tümü tamamlandı
- [x] **T48** — `screens/competitor_radar_screen.dart` ✅
- [x] **T49** — `screens/demand_trends_screen.dart` ✅
- [x] **T50** — `screens/market_intelligence_screen.dart` ✅
- [x] **T51** — `screens/pro_hub_screen.dart` ✅
- [x] **T52** — `screens/pro_insights_screen.dart` ✅
- [x] **T53** — `screens/retargeting_screen.dart` ✅
- [x] **T54** — `screens/listing_analytics_screen.dart` ✅ (T33 ile aynı ekran)
- [x] **T55** — `screens/live_stream_analytics_screen.dart` ✅
- [x] **T56** — `screens/live_stream_history_screen.dart` ✅

### Diğer ekranlar ✅ Tümü tamamlandı
- [x] **T57** — `screens/pro_stream_analytics_screen.dart` ✅
- [x] **T58** — `screens/ad_report_screen.dart` ✅
- [x] **T59** — `screens/blocked_users_screen.dart` ✅
- [x] **T60** — `screens/call_screen.dart` ✅
- [x] **T61** — `screens/call_history_screen.dart` ✅
- [x] **T62** — `screens/faq_screen.dart` ✅
- [x] **T63** — `screens/force_update_screen.dart` ✅
- [x] **T64** — `screens/incoming_call_screen.dart` ✅
- [x] **T65** — `screens/my_ratings_screen.dart` ✅
- [x] **T66** — `screens/notification_settings_screen.dart` ✅
- [x] **T67** — `screens/story/story_viewer_screen.dart` ✅

### Widget'lar ✅ Tümü tamamlandı
- [x] **T68** — `widgets/auction_panel.dart` ✅
- [x] **T69** — `widgets/chat_panel.dart` ✅
- [x] **T70** — `widgets/live/story_tray.dart` ✅
- [x] **T71** — `widgets/live/host_top_bar.dart` ✅
- [x] **T72** — `widgets/live/viewer_top_bar.dart` ✅
- [x] **T73** — `widgets/live/gift_hud.dart` ✅
- [x] **T74** — `widgets/live/cohost_mod_sheet.dart` ✅
- [x] **T75** — `widgets/live/live_video_player.dart` ✅
- [x] **T76** — `widgets/live/pip_video_widget.dart` ✅
- [x] **T77** — `widgets/global_call_overlay.dart` ✅
- [x] **T78** — `widgets/global_keyboard_accessory.dart` ✅
- [x] **T79** — `widgets/incoming_call_overlay.dart` ✅
- [x] **T80** — `widgets/network_error_widget.dart` ✅
- [x] **T81** — `widgets/offline_banner.dart` ✅
- [x] **T82** — `widgets/phone_input_field.dart` ✅
- [x] **T83** — `widgets/soft_update_dialog.dart` ✅
- [x] **T84** — `widgets/stale_data_banner.dart` ✅
- [x] **T85** — `widgets/streamer_avatar_card.dart` ✅
- [x] **T86** — `widgets/swipe_to_bid_button.dart` ✅

---

## FAZ 6 — Temizlik ✅ Tümü tamamlandı

- [x] **T87** — `utils/snackbar_helper.dart` context parametrelerini kaldır ✅
  - `showSuccessSnackbar(context, message)` → `showSuccessSnackbar(String message)` — context artık kullanılmıyor
- [x] **T88** — `services/share_service.dart` AppLocalizations kullanımını gözden geçir ✅
  - `_ShareSheet` → ConsumerWidget, tüm `AppLocalizations.of(context)!.xxx` → `loc.t("xxx")`
  - `copyLink()` → `copiedLabel` string parametresi alıyor, AppLocalizations bağımlılığı kaldırıldı
- [x] **T89** — `dart analyze` — 0 error, 2 warning + 34 info (tümü önceden vardı) ✅

---

## FAZ 7 — Son Test & Deploy

- [ ] **T90** — 4 dilde manuel test (TR / EN / AR / RU) — create_listing_screen, login, profile, listing_detail ⬅️ Manuel
- [ ] **T91** — Error senaryoları test: network hatası (uçak modu), 401 (oturumu kapat), 500 server hatası, validasyon hatası ⬅️ Manuel
- [ ] **T92** — Swipe-to-dismiss test ⬅️ Manuel
- [ ] **T93** — OTA doğrulama: DB'de bir çeviriyi güncelle, uygulama yeniden açılınca değişikliği gör ⬅️ Manuel
- [x] **T94** — Commit + push + VPS deploy ✅
  - Commit: `e3d0d554` — feat: complete OTA localization migration (FAZ 5 + FAZ 6)
  - 81 dosya, 3193 ekleme, 3791 silme
  - VPS deploy: `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`

---

## Notlar

- **Ekran önceliği:** Auth ekranları (T22–T27) → Ana ekranlar → Karmaşık ekranlar
- **Her ekrandan sonra** `dart analyze` çalıştır, biriken hata biriktirme
- **Widget migration:** Parent'tan `loc` parametresi almak da kabul edilebilir; her widget'ı `ConsumerWidget` yapmak zorunda değiliz
- **ARB dosyaları silinmez** — MaterialApp delegates için codegen çalışmaya devam eder
- **Mevcut durum:** FAZ 1–6 tamamen tamamlandı. FAZ 7'de T90–T93 manuel test gerektiriyor. `dart analyze` → 0 error.
