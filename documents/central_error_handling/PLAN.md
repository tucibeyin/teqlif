# Merkezi Hata Yönetimi ve OTA Localization — Mimari Plan

**Tarih:** 2026-07-24  
**Pilot ekran:** `create_listing_screen.dart` (tamamlandı — referans implementasyon)  
**Kapsam:** Tüm Flutter ekranları + backend deploy pipeline

---

## 1. Mevcut Durum (Problem)

### Localization — İki paralel sistem çalışıyor

| Sistem | Nerede | Avantaj | Problem |
|--------|--------|---------|---------|
| `AppLocalizations` (ARB) | 50+ ekran/widget | Flutter codegen, compile-time safe | Dil değişimi için app restart, OTA güncellenemez |
| `LocalizationService` (OTA) | create_listing_screen | Runtime güncelleme, DB'den gelir | Pilot aşamada, diğer ekranlar migrate edilmedi |

### Error Handling — Üç ayrı entry point

```
catch (e) {
  showErrorSnackbar(context, e);     // 6 ekran + start_stream_helper
  ErrorDisplay.fromException(ctx, e); // 5 ekran
  handleError(e, loc);               // create_listing_screen (pilot)
}
```

Her biri farklı davranır, farklı mesaj formatlar, farklı loglama yapar.

### `BuildContext` bağımlılığı

`showErrorSnackbar` ve `ErrorDisplay` context alıyor çünkü `AppLocalizations.of(context)` ile mesaj lokalize ediyorlar. OTA'ya geçildiğinde bu bağımlılık ortadan kalkar.

---

## 2. Hedef Mimari

### Localization

```
ARB dosyaları (4 dil)
    │
    │  [deploy pipeline]
    ▼
translations tablosu (PostgreSQL)
    │
    │  GET /api/i18n/{lang}  (Redis cache 1h)
    ▼
LocalizationService (Hive cache 24h)
    │
    │  ref.watch(localizationProvider)
    ▼
Her ekranda:  loc.t('key')  /  loc.tOr('key', 'fallback')
```

**Kural:** ARB = single source of truth. DB'ye hiçbir zaman elle yazılmaz.  
Deploy pipeline'ı ARB'ı okuyup DB'ye upsert eder. Yeni çeviri eklemek = ARB'a yaz + deploy.

### Error Handling

```
catch (e) {
  handleError(e, loc);   // TEK entry point — tüm ekranlarda aynı
}
```

`handleError` içindeki akış:

```
handleError(error, TranslationPack loc)
  │
  ├── message = ErrorMapper.toMessage(error, loc)
  │
  ├── 401 / AuthError?
  │     └── AuthService.logout()
  │         + navigatorKey.pushNamedAndRemoveUntil('/login')
  │         (return — toast gösterme)
  │
  ├── TeqToast.error(message)   ← context yok, navigatorKey kullanır
  │
  └── shouldLog? → LoggerService.captureException(error)
```

### Result<T> — Domain katmanı

`api.dart` teki `Result<T>` pattern korunur, ama `AppError` çıkar:

```dart
// ÖNCE
final class Err<T> extends Result<T> { final AppError error; }

// SONRA
final class Err<T> extends Result<T> { final Object error; }
```

UI katmanında:
```dart
case Err(:final error): handleError(error, loc);
```

`AppError` sealed class UI-layer type dispatch için kullanılıyordu. Bu görevi `ErrorMapper` üstlendi.

### Silinecekler

| Dosya | Sebep |
|-------|-------|
| `core/error_display.dart` | `handleError` aynı işi yapıyor |
| `core/app_error.dart` | `ErrorMapper` type dispatch'i üstlendi |
| `showErrorSnackbar` (error_helper.dart) | Compat shim, artık gerek yok |
| `snackbar_helper.dart` context parametreleri | Context zaten kullanılmıyordu |

---

## 3. Mimari Kararlar

### Karar 1: ARB dosyaları kalır, DB'ye direkt yazılmaz

**Gerekçe:** ARB'ı kaldırırsak Flutter'ın `localizationsDelegates` altyapısı bozulur (Material/Cupertino widget'ları bunu gerektirir). Daha önemlisi, ARB code-review sürecine dahil: değişiklik PR'da görünür, diff okunabilir. DB'ye direkt yazılan key'ler görünmez.

**Uygulama:** `sync_translations.py` deploy adımına eklenir. ARB değişince otomatik sync olur.

### Karar 2: `Result<T>` pattern korunur

**Gerekçe:** Service katmanında try/catch yerine `Result<Ok, Err>` dönmek, çağıran kodun hatayı handle etmesini zorunlu kılar (derleme zamanı garantisi). Sadece error type `AppError` → `Object` olarak genişletilir.

### Karar 3: Auth error routing `handleError` içinde

**Gerekçe:** 401 tepkisi global bir davranış — her ekranın bunu ayrı handle etmesi gerekmiyor. `handleError` navigatorKey ile `/login`'e yönlendirir, context gerektirmez.

### Karar 4: `AppLocalizations` codegen kalır, import edilmez

**Gerekçe:** `MaterialApp` için `localizationsDelegates` ve `supportedLocales` ARB codegen'den geliyor. Bu boilerplate'i elle tutmak yerine codegen çalıştırmaya devam ederiz, sadece uygulama kodunda `AppLocalizations.of(context)` kullanmayız.

---

## 4. Ekran Migration Pattern (create_listing_screen referans)

Her ekran için 3 değişiklik:

```dart
// 1. Widget tip değişimi
class MyScreen extends ConsumerStatefulWidget { ... }
class _MyScreenState extends ConsumerState<MyScreen> { ... }

// 2. Build metodunda localization
@override
Widget build(BuildContext context) {
  final loc = ref.watch(localizationProvider);  // ARB yerine OTA
  // l.xxx  →  loc.t('xxx')
}

// 3. Async metodlarda error handling
} catch (e) {
  handleError(e, ref.read(localizationProvider));  // context yok
}
```

**StatelessWidget durumu:** Eğer ekran zaten `ConsumerWidget` ise sadece `ref.watch(localizationProvider)` eklenir.

**Widget durumu:** Widget'lar `ConsumerWidget` olur veya `loc` parametresi parent'tan aşağı geçirilir.

---

## 5. Bağımlılık Grafiği

Hangi task hangi task'a bağlı:

```
T01 (sync_translations.py)
  └── T02 (deploy pipeline)
        └── T03 (VPS test)

T04 (handleError auth routing)
  └── T05 (Result<T> type değişimi)
        └── T06 (ErrorDisplay sil)
              └── T07 (AppError sil)

T08–T18 (ekran migrasyonu)  ← T04 tamamlanınca başlanabilir
  └── T19 (showErrorSnackbar sil)
        └── T20 (snackbar_helper context parametreleri sil)
              └── T21 (AppLocalizations import temizliği)
                    └── T22 (dart analyze sıfır hata)
```

---

## 6. Scope Özeti

| Kategori | Adet | Durum |
|----------|------|-------|
| `showErrorSnackbar` kullanan ekran | 6 + helper | Migrate edilecek |
| `ErrorDisplay` kullanan ekran | 5 | Migrate edilecek |
| `AppLocalizations` kullanan ekran | ~45 | Migrate edilecek |
| `AppLocalizations` kullanan widget | ~15 | Migrate edilecek |
| Backend sync script | 1 | Yazılacak |
| Silinecek Flutter dosyası | 2 (`error_display`, `app_error`) | Silinecek |

**Pilot (tamamlandı):** `create_listing_screen.dart` — tüm pattern'lar burada uygulandı.
