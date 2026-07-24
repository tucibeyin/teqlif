# Hata ve Uyarı Standardizasyonu — Task Listesi

**Plan:** `ERROR_HANDLING_PLAN.md`  
**Pilot ekran:** `create_listing_screen.dart`

---

## FAZ 1 — TeqToast Yükseltme

- [x] **T01** — TeqToast'tan BuildContext kaldır, navigatorKey ile overlay bul ✅
- [x] **T02** — Swipe-to-dismiss ekle (aşağı sürükleyince kapanır) ✅
- [x] **T03** — TeqSnackBar wrapper'dan context parametresini kaldır ✅
  - `main.dart`'a `TeqToast.init(TeqlifApp.navigatorKey)` eklendi
  - 25 dosyada bulk context kaldırması yapıldı

## FAZ 2 — Merkezi Hata Katmanı

- [x] **T04** — `ErrorMapper` yaz (`lib/core/error_mapper.dart`) ✅
  - Tüm bilinen error code'lar → loc key eşleştirmesi
  - Upload hata string'leri → loc key eşleştirmesi
  - `shouldLog` → AppException.shouldCapture'a delege eder
- [x] **T05** — `handleError(error, loc)` global fonksiyonu yaz (`lib/utils/error_helper.dart`) ✅
  - ErrorMapper + TeqToast + LoggerService zinciri

## FAZ 3 — error_helper Refactor

- [x] **T06** — `_extractMessage` silindi, `ErrorMapper.toMessage` kullanılıyor ✅
- [x] **T07** — `showErrorSnackbar` compat shim olarak bırakıldı (context alır ama TeqToast context-free çağırır) ✅

## FAZ 4 — Pilot: İlan Ver Ekranı

- [x] **T08** — `_mapError` metodunu sil, `handleError` ile değiştir ✅
- [x] **T09** — `_uploadError` metodunu sil, `ErrorMapper` karşılar ✅
- [x] **T10** — Kalan `TeqSnackBar.show(context, ...)` çağrılarından context kaldırıldı ✅
- [x] **T11** — `showErrorSnackbar(context, ...)` → `handleError(e, loc)` ile değiştirildi ✅
- [x] **T12** — `dart analyze` sıfır hata ✅
- [ ] **T13** — Manuel test: network hatası, validasyon hatası, swipe-to-dismiss

## FAZ 5 — Backend Format Review

- [x] **T14** — Backend error response formatını kontrol et, tutarsız endpoint var mı? ✅
  - `field_config.py`: `HTTPException(404)` → `NotFoundException(code="SUBCATEGORY_NOT_FOUND")`
  - `i18n.py` (2 yer): `HTTPException(400)` → `BadRequestException(code="UNSUPPORTED_LANGUAGE")`
  - `wallet.py`: zaten `AppException` subclass'ları kullanıyor; tek kalan `HTTPException` `topup_manual`'da (503, kasıtlı devre dışı endpoint)
- [x] **T15** — Eksik error loc key'lerini translations tablosuna ekle ✅
  - `errorServerBusy` ve `errorSessionExpired` 4 dilde ARB dosyalarına eklendi
  - `alembic/versions/aaa_error_loc_keys.py` migration'ı oluşturuldu (VPS'te çalıştırılacak)
