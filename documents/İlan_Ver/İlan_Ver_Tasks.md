# İlan Ver — Görev Listesi

**Plan:** `İlan_Ver_Plan.md`  
**Ekran:** `mobile/lib/screens/create_listing_screen.dart`  
**Global migration taskları:** `documents/central_error_handling/TASK.md`

---

## FAZ 1 — Backend Altyapısı

- [x] **T01** — `scripts/sync_translations.py` yaz ✅
  - 4 ARB dosyasını okur, `translations` tablosuna UPSERT eder
  - Redis `i18n:*` cache'ini invalidate eder
  - VPS: 7104 satır sync, `errorServerBusy` doğrulandı

- [x] **T02** — VPS deploy komutunu güncelle ✅
  - `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`

- [x] **T03** — Backend error format düzelt ✅
  - `field_config.py`: `HTTPException(404)` → `NotFoundException(SUBCATEGORY_NOT_FOUND)`
  - `i18n.py` (2 yer): `HTTPException(400)` → `BadRequestException(UNSUPPORTED_LANGUAGE)`

- [x] **T04** — Error loc key'leri ekle ✅
  - `errorServerBusy` ve `errorSessionExpired` → 4 ARB dosyası + Alembic migration
  - `down_revision` düzeltmesi: `aad_translations_table` (multiple head hatası çözüldü)

---

## FAZ 2 — Flutter Core

- [x] **T05** — `handleError`'a 401 auth routing ekle ✅
  - 401 → `AuthService.authFailedStream.add(null)` → `return` (toast gösterme)
  - `main_screen._handleAuthFailed()` stream'i dinler → logout + /login

- [x] **T06** — `Result<T>` error type değiştir ✅
  - `Err<T>.error`: `final AppError error` → `final Object error`
  - `api.dart`: `return Err(AppError.from(e))` → `return Err(e)`

---

## FAZ 3 — OTA Localization Migrasyonu

- [x] **T07** — `ConsumerStatefulWidget` / `ConsumerState` dönüşümü ✅
  - `StatefulWidget` → `ConsumerStatefulWidget`
  - `State<CreateListingScreen>` → `ConsumerState<CreateListingScreen>`

- [x] **T08** — Localization bağlantısı ✅
  - `build()`: `final loc = ref.watch(localizationProvider)`
  - `async` metodlar: `final loc = ref.read(localizationProvider)`
  - `AppLocalizations.of(context)!` ve `field_labels.dart` importları kaldırıldı

- [x] **T09** — `l.xxx` → `loc.t('xxx')` toplu dönüşüm ✅
  - Parametreli key'ler: `loc.t('xxx', {'param': value.toString()})`

- [x] **T10** — Subcategory label dönüşümü ✅
  - `subcatLabel(s.$1, l, fallback: s.$2)` → `loc.tOr('subcat_${s.$1}', s.$2)`
  - 47-case switch silindi

- [x] **T11** — Option label dönüşümü ✅
  - `o.label` → `loc.tOr('opt_${o.value}', o.label)`
  - Dropdown, conditional dropdown, multiselect

- [x] **T12** — Extra field label dönüşümü ✅
  - `_extraFieldLabel(f.labelKey, l)` switch (47-case) → `loc.t(f.labelKey)`

- [x] **T13** — İç widget'ları dönüştür ✅
  - `_AiPriceButton`, `_AiDescButton`: `StatelessWidget` → `ConsumerWidget`

- [x] **T14** — 4 dil manuel test ✅
  - TR / EN / AR / RU — tüm label'lar doğru çevrildi

- [x] **T15** — OTA doğrulama ✅
  - `opt_white` TR: "Beyaz" → "Bembeyaz" → Redis cache temizlendi → Flutter'da "Bembeyaz" göründü ✅
  - Değer geri alındı

---

## FAZ 4 — Merkezi Error Handling Migrasyonu

- [x] **T16** — `_mapError()` metodunu sil, `handleError` ile değiştir ✅
- [x] **T17** — `_uploadError()` metodunu sil ✅
- [x] **T18** — `TeqSnackBar.show(context, ...)` → context kaldır ✅
- [x] **T19** — `showErrorSnackbar(context, e)` → `handleError(e, loc)` ✅
- [x] **T20** — `dart analyze` — 0 error, 0 warning ✅ (46 info, önceden vardı)

---

## FAZ 5 — Pilot Doğrulama

- [x] **T21** — Ekran review ✅
  - `AppLocalizations` kalmadı ✅
  - `showErrorSnackbar` kalmadı ✅
  - `ErrorDisplay` kalmadı ✅
  - Tüm catch blokları `handleError` kullanıyor ✅
  - `TeqSnackBar.show()` çağrıları geçerli (`loc.t()` kullanıyor, context yok) ✅

- [x] **T22** — Form vs API hata testi ✅
  - Boş açıklama + fiyat → inline field hataları (form validator) ✅
  - AI fiyat butonu + boş başlık → Toast (LISTING_TITLE_REQUIRED backend'den) ✅

---

## FAZ 6 — Kalan İşler

- [x] **T23** — Kapsamlı hata senaryosu testi ✅
  - [x] Uçak modunda submit → `errorNetworkMessage` toast görünüyor mu?
  - [x] Rate limit → `errorTooFast` toast görünüyor mu?
  - [x] Server hatası (500) → `errorServerBusy` toast görünüyor mu?
  - [x] Swipe-to-dismiss çalışıyor mu?
  - [x] 401 → uygulama logout yapıyor mu? (çift navigation yok mu?)

- [x] **T24** — ARB key temizliği ✅
  - AppLocalizations tamamen kaldırıldı — `start_stream_helper.dart`, `push_notification_service.dart` OTA'ya geçirildi
  - `app_localizations*.dart` generated dosyaları silindi, `generate: true` pubspec'ten kaldırıldı
  - `field_labels.dart` silindi (dead code — hiçbir çağıranı yoktu)
  - ARB dosyaları artık yalnızca `sync_translations.py` → DB pipeline'ının kaynağı

- [x] **T25** — `kSubcategoryFields` offline fallback gözden geçir ✅
  - DB ve Flutter kSubcategoryFields karşılaştırıldı: eksik subcategory yok
  - `tablet`, `tv_monitor` SUBCATEGORY_MAP'te görünmüyor çünkü slug değişmedi — DB'de mevcut
