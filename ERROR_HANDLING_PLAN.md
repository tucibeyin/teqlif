# Hata ve Uyarı Standardizasyonu Planı

**Hedef:** Uygulamanın her katmanından gelen hata ve uyarıları tek bir pipeline üzerinden yönet.
Kullanıcıya ne gösterileceği, neyin loglanacağı ve nasıl görüntüleneceği tek bir yerden kontrol edilsin.

**Pilot ekran:** İlan Ver (`create_listing_screen.dart`)

---

## Mevcut Durum Analizi

### Neler İyi
- `AppException(code, message, statusCode, shouldCapture)` — sağlam bir hata modeli zaten var
- `NetworkException` — ayrı bir tip olarak tanımlı
- `TeqToast` — overlay tabanlı, replace davranışı var, animasyonlu
- `LoggerService` — Sentry entegrasyonu hazır

### Neler Eksik / Kırık
| Sorun | Nerede |
|-------|--------|
| `TeqToast.show()` context zorunlu | `teq_toast.dart` |
| Swipe-to-dismiss yok | `teq_toast.dart` |
| `error_helper.dart` hâlâ AppLocalizations kullanıyor | `error_helper.dart` |
| Her ekran kendi `_mapError` / `_uploadError` yazıyor | `create_listing_screen.dart` vb. |
| Hata kodu → loc key eşleştirmesi 3 farklı yerde | `error_helper.dart`, `create_listing_screen.dart`, ... |

---

## Show vs Log Politikası

| Hata Durumu | Kullanıcıya Göster | Logla (Sentry) |
|---|---|---|
| Network yok / timeout | ✅ `errorNetworkMessage` | ❌ |
| HTTP 400 — validation | ✅ API mesajı veya loc key | ❌ |
| HTTP 401 — unauthorized | ✅ `errorSessionExpired` | ❌ |
| HTTP 403 — forbidden / captcha | ✅ `errorCaptchaFailed` | ❌ |
| HTTP 429 — rate limit | ✅ `errorTooFast` | ❌ |
| HTTP 4xx — business logic (içerik ihlali vb.) | ✅ koda göre loc key | ❌ |
| HTTP 5xx — sunucu hatası | ✅ `errorServerBusy` (generic) | ✅ |
| Upload hatası (413, 502, 503) | ✅ `uploadErrorTooLarge` vb. | ❌ |
| Beklenmedik exception | ✅ `errorGenericRetry` | ✅ |
| Form validator | ✅ inline (field altında) — Toast değil | ❌ |

`shouldCapture` bu politikanın kodu — `AppException`'da zaten var (statusCode == 0 veya >= 500).

---

## Hedef Mimari

```
[API yanıtı / Exception atılır]
            ↓
     AppException
  (code, statusCode, message, shouldCapture)
            ↓
      ErrorMapper
  .toMessage(error, loc) → localize edilmiş String
  .shouldLog(error)      → bool
            ↓
    ┌───────┴────────┐
    ▼                ▼
TeqToast          LoggerService
.error(msg)     .captureException(e)
```

### Çağrı şekli (pilot sonrası standart)

```dart
// Ekranda:
try {
  await _submit();
} catch (e) {
  handleError(e, ref.read(localizationProvider));
}

// handleError — tek satır, her yerden çağrılabilir
void handleError(Object error, TranslationPack loc) {
  final msg = ErrorMapper.toMessage(error, loc);
  TeqToast.error(msg);
  if (ErrorMapper.shouldLog(error)) LoggerService.instance.captureException(error);
}
```

---

## FAZ 1 — TeqToast Yükseltme

**Amaç:** Render katmanını context bağımlılığından kurtar, swipe-to-dismiss ekle.

---

- [ ] **T01** — `TeqToast`'tan `BuildContext` parametresini kaldır
  - `navigatorKey.currentState?.overlay` ile root overlay'e eriş
  - `TeqlifApp.navigatorKey` zaten `main.dart`'ta mevcut
  - Dosya: `mobile/lib/ui_library/components/overlays/teq_toast.dart`

- [ ] **T02** — Swipe-to-dismiss ekle
  - `GestureDetector` + `onVerticalDragEnd` — aşağı sürükleyince `_dismiss()`
  - Sürükleme threshold: `velocity.primaryVelocity > 300` veya `offset.dy > 40`
  - Dosya: `mobile/lib/ui_library/components/overlays/teq_toast.dart`

- [ ] **T03** — `TeqSnackBar` wrapper'ını güncelle
  - `show(context, ...)` → `show(...)` — context parametresi kaldır
  - Dosya: `mobile/lib/ui_library/components/overlays/teq_snackbar.dart`

---

## FAZ 2 — ErrorMapper (Merkezi Hata Eşleştirici)

**Amaç:** "Hangi hata → hangi mesaj" ve "logla mı" kararını tek yerde topla.

---

- [ ] **T04** — `ErrorMapper` yaz
  - Konum: `mobile/lib/core/error_mapper.dart`
  - `static String toMessage(Object error, TranslationPack loc)`:
    - `NetworkException` → `loc.t('errorNetworkMessage')`
    - `AppException.code == 'RATE_LIMIT_EXCEEDED'` → `loc.t('errorTooFast')`
    - `AppException.code == 'FORBIDDEN'` → `loc.t('errorCaptchaFailed')`
    - `AppException.code == 'CONTENT_POLICY_VIOLATION'` → `loc.t('errorContentPolicy')`
    - `AppException.code == 'PROVINCE_REQUIRED'` → `loc.t('errProvinceRequired')`
    - `AppException.code == 'INVALID_CONDITION'` → `loc.t('errInvalidCondition')`
    - `AppException.code == 'INVALID_PRICE'` → `loc.t('errInvalidPrice')`
    - `AppException.code == 'LISTING_TITLE_REQUIRED'` → `loc.t('fieldListingTitleHint')`
    - `AppException.statusCode >= 500` → `loc.t('errorServerBusy')`
    - Upload hataları (HTTP 413, 502, 503, 401) → ilgili loc key'ler
    - Fallback: `loc.t('errorGenericRetry')`
  - `static bool shouldLog(Object error)`:
    - `error is AppException` → `error.shouldCapture` (zaten var)
    - Diğer → `true`

- [ ] **T05** — `handleError` global fonksiyonu yaz
  - Konum: `mobile/lib/utils/error_helper.dart` (mevcut dosyayı refactor et)
  - `void handleError(Object error, TranslationPack loc)`
  - İçeride: `ErrorMapper.toMessage` + `TeqToast.error` + `LoggerService` (shouldLog ise)
  - Eski `showErrorSnackbar` → deprecated wrapper olarak bırak (yeni kod `handleError` kullanır)

---

## FAZ 3 — error_helper.dart Refactor

**Amaç:** `AppLocalizations` bağımlılığını ve `context` zorunluluğunu kaldır.

---

- [ ] **T06** — `_extractMessage` fonksiyonunu sil, yerine `ErrorMapper.toMessage` kullan

- [ ] **T07** — `showErrorSnackbar(context, error)` imzasını `showErrorSnackbar(error, loc)` yap
  - İçini `handleError(error, loc)` çağrısına dönüştür
  - `import app_localizations.dart` kaldır

---

## FAZ 4 — Pilot: İlan Ver Ekranı

**Amaç:** Ekrandaki dağınık hata yönetimini standardize edilmiş `handleError` çağrılarına dönüştür.

---

- [ ] **T08** — `_mapError(AppException)` metodunu sil
  - `TeqSnackBar.show(context, message: _mapError(e), ...)` → `handleError(e, loc)`

- [ ] **T09** — `_uploadError(Object)` metodunu sil
  - `TeqSnackBar.show(context, message: _uploadError(e), ...)` → `handleError(e, loc)`
  - Upload error mantığı `ErrorMapper`'a taşındığı için burada gerek kalmaz

- [ ] **T10** — Kalan `TeqSnackBar.show(context, ...)` çağrılarından `context` kaldır
  - Success ve warning mesajları (bunlar `handleError` değil, doğrudan toast)
  - Pattern: `TeqSnackBar.show(message: loc.t('key'), type: ...)` — context yok

- [ ] **T11** — `showErrorSnackbar(context, ...)` çağrısını `handleError(e, loc)` ile değiştir

- [ ] **T12** — `dart analyze` — sıfır hata/warning

- [ ] **T13** — Manuel test: 4 hata senaryosu
  - Network kapalıyken submit → `errorNetworkMessage` görünüyor mu?
  - Geçersiz fiyat ile submit → `errInvalidPrice` görünüyor mu?
  - Rate limit simülasyonu → `errorTooFast` görünüyor mu?
  - Swipe-to-dismiss çalışıyor mu?

---

## FAZ 5 — Backend Error Format Review

**Amaç:** Tüm API endpoint'lerinin aynı error formatını döndürdüğünü doğrula.

---

- [ ] **T14** — Backend `error` response formatını kontrol et
  - Beklenen: `{"success": false, "error": {"code": "...", "message": "..."}}`
  - Tüm router'larda tutarlı mı? Eksik olan var mı?
  - Dosya: `backend/app/routers/`

- [ ] **T15** — Eksik error code'lar için `translations` tablosuna key ekle
  - `errorServerBusy`, `errorSessionExpired`, `errorGenericRetry` DB'de var mı?
  - Yoksa migration ile ekle

---

## Notlar

- **Form validator'lar bu plana dahil değil** — inline field hataları ayrı bir sistem, dokunulmayacak.
- **Warning ve success toast'lar `handleError` kullanmaz** — sadece hatalar için. Success/warning ekranlar doğrudan `TeqToast.success(loc.t('key'))` çağırır.
- **Diğer ekranlar** — pilot sonrası aynı pattern `handleError(e, loc)` ile uygulanır, her ekranda 1-2 satır değişiklik.
- **`shouldCapture` flag'i** — `AppException`'da zaten doğru implement edilmiş, dokunulmayacak.
