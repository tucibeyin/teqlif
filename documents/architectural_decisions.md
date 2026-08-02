# Architectural Decisions

Bu dosya, teqlif'teki büyük mimari kararları ve uygulama pattern'lerini tutar.  
**Yeni bir ekranı refactor ederken bu dosyaya bak — her karar burada, neden sorusuyla birlikte.**

**Pilot ekran:** `create_listing_screen.dart` (tüm pattern'lar burada uygulandı, referans al)  
**Son güncelleme:** Temmuz 2026 — TeqAsyncButton, async buton loading pattern'i eklendi

---

## İçindekiler

1. [OTA Localization](#1-ota-localization)
2. [Dinamik Field Konfigürasyonu](#2-dinamik-field-konfigürasyonu)
3. [ML / Analytics / ClickHouse](#3-ml--analytics--clickhouse)
4. [Merkezi Error Handling](#4-merkezi-error-handling)
5. [Async Buton Loading Pattern](#5-async-buton-loading-pattern)
6. [Deploy Pipeline](#6-deploy-pipeline)
7. [Ekran Migration Checklist](#7-ekran-migration-checklist)

---

## 1. OTA Localization

### Problem

Flutter'ın ARB/AppLocalizations sistemi çevirileri derleme zamanında uygulamaya gömer. Bir çeviriyi düzeltmek için App Store güncellemesi gerekiyordu.

### Karar

Çeviriler PostgreSQL'de tutulur, API'den serve edilir, client Hive'da cache'ler.  
Uygulama güncellemesi olmadan çeviriler anında değiştirilebilir.

ARB dosyaları **single source of truth** olmaya devam eder — DB'ye elle yazılmaz.  
Deploy pipeline ARB'ı okuyup DB'ye upsert eder.

### Mimari

```
ARB dosyaları (4 dil, git'te)
        │  [deploy: python3 scripts/sync_translations.py]
        ▼
translations(key, lang, value)   — PostgreSQL
        │  GET /api/i18n/{lang}  — Redis cache 1h
        ▼
LocalizationService              — Flutter, Hive cache 24h
        │  ref.watch(localizationProvider)
        ▼
loc.t('key') / loc.tOr('key', fallback)
```

---

### 1.1 Veritabanı

```sql
translations(key VARCHAR(200), lang VARCHAR(10), value TEXT, PRIMARY KEY (key, lang))
```

Key namespace'leri:

| Prefix | Örnek | Kaynak |
|--------|-------|--------|
| *(yok)* | `acceptRequest` | ARB kaynaklı |
| `subcat_` | `subcat_automobile` | Alt kategori isimleri |
| `opt_` | `opt_white`, `opt_gasoline` | Field option label'ları |
| `extraField_` | `extraField_brand` | Extra field label'ları |

---

### 1.2 Backend API

`GET /api/i18n/{lang}` → flat JSON  
`GET /api/i18n/{lang}/version` → MD5 hash (stale check için)

Desteklenen diller: `tr`, `en`, `ar`, `ru`  
Geçersiz lang → `BadRequestException(code="UNSUPPORTED_LANGUAGE")`

---

### 1.3 Flutter: LocalizationService

**Dosya:** `mobile/lib/services/localization_service.dart`

```dart
final localizationProvider =
    StateNotifierProvider<LocalizationService, TranslationPack>(...);
```

`TranslationPack` — iki metod:

```dart
loc.t('fieldCategory')                              // basit key
loc.t('tuciSpent', {'count': n.toString()})         // parametre interpolasyonu
loc.tOr('opt_bmw', 'BMW')                           // key yoksa fallback
```

Cache katmanları:
1. Hive `i18n_cache` box — açılışta anında yüklenir
2. 24h stale check — arka planda `/version` ile MD5 karşılaştırır, farklıysa yeniden çeker
3. Dil değişiminde otomatik yükleme

---

### 1.4 Widget Dönüşüm Pattern'i

```dart
// ÖNCE
class MyScreen extends StatefulWidget { ... }
class _MyScreenState extends State<MyScreen> { ... }

// SONRA
class MyScreen extends ConsumerStatefulWidget { ... }
class _MyScreenState extends ConsumerState<MyScreen> { ... }
```

```dart
// build() içinde — reaktif, dil değişince rebuild tetikler
final loc = ref.watch(localizationProvider);

// async metodlarda — sadece snapshot alır, rebuild tetiklemez
final loc = ref.read(localizationProvider);
```

```dart
// l.xxx  →  loc.t('xxx')
// l.xxx(param)  →  loc.t('xxx', {'param': value.toString()})
```

İç `StatelessWidget`'lar için iki seçenek:
- `ConsumerWidget`'a çevir ve `ref.watch(localizationProvider)` kullan
- Veya parent'tan `loc` parametresi olarak aşağı geçir (daha az değişiklik)

**Kaldırılacaklar:**
- `import '...app_localizations.dart'` — sil
- `import '...field_labels.dart'` — sil
- `final l = AppLocalizations.of(context)!;` — sil

---

### 1.5 Option / Subcategory / Field Label Pattern'leri

```dart
// Option label (dropdown, multiselect)
Text(loc.tOr('opt_${o.value}', o.label))   // opt_white → "White", yoksa o.label

// Subcategory label
loc.tOr('subcat_${s.$1}', s.$2)            // 47-case switch artık gerekmiyor

// Extra field label
loc.t(f.labelKey)                           // f.labelKey zaten "extraField_brand" formatında
```

---

### 1.6 ARB Codegen Tamamen Kaldırıldı — ARB Tek Kaynak

`flutter gen-l10n` pipeline'ı tamamen kaldırıldı. Flutter uygulaması artık hiçbir noktada `AppLocalizations` import etmez.

**Silinen dosyalar:**
- `mobile/l10n.yaml` — codegen config
- `mobile/lib/l10n/app_localizations*.dart` — tüm generated Dart dosyaları
- `mobile/lib/utils/field_labels.dart` — dead code (subcatLabel, AppLocalizations bağımlıydı)
- `pubspec.yaml`'dan `generate: true` kaldırıldı

**`main.dart` değişikliği:**
```dart
// Önce (AppLocalizations delegate):
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,

// Sonra (global delegates — RTL/AR desteği korundu):
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
supportedLocales: const [Locale('tr'), Locale('en'), Locale('ar'), Locale('ru')],
```

**Background isolate pattern** (`push_notification_service.dart`):  
BuildContext olmayan background isolate'lerde `lookupAppLocalizations` yerine:
```dart
await Hive.initFlutter();
await LocalizationService.initBox();
final pack = LocalizationService.readCacheSync(langCode);
pack.t('callVoiceCall');
```
`Hive.initFlutter()` + `initBox()` tekrar çağrısı güvenli — `_box ??=` guard'ı koruyor.

**ARB dosyalarının rolü:** Artık yalnızca `sync_translations.py → DB` zincirinin kaynağı. Uygulama ARB'yi hiç görmez.

> ⚠️ ARB dosyalarını silme — `sync_translations.py` onları okur ve DB'ye sync'ler.

---

### 1.7 OTA Çeviri Güncelleme Akışı

Çeviriyi değiştirmek için:
1. ARB dosyasında güncelle (TR, EN, AR, RU)
2. Commit + push
3. VPS'te deploy: `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`
4. Bitti — kullanıcılar bir sonraki uygulama açılışında yeni çeviriyi görür

> ⚠️ DB'ye direkt SQL yazmak **artık yasak** — her zaman ARB → deploy pipeline üzerinden git.

---

### 1.8 Dil Değiştirme UX Pattern'i

**Dosyalar:** `mobile/lib/services/localization_service.dart`, `mobile/lib/widgets/language_switch_overlay.dart`, `mobile/lib/screens/auth/login_screen.dart`, `mobile/lib/screens/profile_screen.dart`

**Sorun:** `localeProvider.setLocale()` anında state güncelliyor (toggle hareket ediyor), ama dil paketi henüz yüklenmemişse UI eski dilde kalıyor. Kullanıcı toggle'ın çalıştığını sanıyor, çalışmıyor.

**Karar:** Dil değiştirme UI'dan soyutlandı — `switchLanguage()` başarısız olursa toggle geri döner, `setLocale()` sadece başarı sonrası çağrılır.

```
Kullanıcı toggle'a basar
  → _displayedLang = newLang (optimistik)
  → _isSwitching = true → LanguageSwitchOverlay (blur + spinner)
  → await switchLanguage(newLang)
      ├── true  → setLocale(newLang) + success toast
      └── false → _displayedLang = prevLang (toggle geri) + error toast
```

**`LocalizationService.switchLanguage(lang) → Future<bool>`:**
- Cache'te varsa: anında pack yükle → `return true`
- Cache'te yoksa: `_fetchAndCache()` → başarıda `return true`, hata/timeout → `return false`
- Başarısızda `_currentLang` değişmez — caller UI'ı revert edebilir

**Ekran pattern'i:**
```dart
late String _displayedLang;   // initState: ref.read(localeProvider).languageCode
bool _isSwitching = false;

Future<void> _onLangChange(String newLang) async {
  if (_isSwitching || newLang == _displayedLang) return;
  final prevLang = _displayedLang;
  setState(() { _isSwitching = true; _displayedLang = newLang; });
  final ok = await ref.read(localizationProvider.notifier).switchLanguage(newLang);
  if (!mounted) return;
  if (ok) {
    await ref.read(localeProvider.notifier).setLocale(Locale(newLang));
    setState(() => _isSwitching = false);
    TeqToast.success(ref.read(localizationProvider).t('langSwitchSuccess'));
  } else {
    setState(() { _isSwitching = false; _displayedLang = prevLang; });
    TeqToast.error(ref.read(localizationProvider).t('langSwitchFailed'));
  }
}
```

**`LanguageSwitchOverlay`:** `BackdropFilter` blur + `CircularProgressIndicator`. Scaffold.body'yi sarar — `isVisible: _isSwitching` ile kontrol edilir.

**SegmentedButton:** `selected: {_displayedLang}` — `localeProvider`'a değil lokal state'e bağlı. `setLocale()` başarı sonrası çağrıldığında `localeProvider` listener'ı pack zaten yüklü olduğundan guard'a takılır (`_currentLang == lang && !state.isEmpty`) ve gereksiz reload yapmaz.

**Yeni ARB key'leri:** `langSwitching`, `langSwitchSuccess`, `langSwitchFailed` — 4 dilde.

---

### 1.9 Soğuk Başlatma — Sıfır Flash Garantisi

**Sorun:** `LocalizationService` ve `LocaleNotifier` senkron default değerlerle başlıyordu (boş pack, `'tr'` locale). Async Hive/SharedPreferences okuması bir tick sonra geliyordu — bu tek tick'te `loc.t('key')` → `'key'` dönüyordu.

**Karar:** `main()` içinde `runApp()` öncesi her ikisi de önyüklenir; provider override'larıyla geçilir.

```dart
// main() — initBox() ve prefs zaten hazır
final savedLang = prefs.getString('app_locale_language_code') ?? 'tr';
final initialPack = LocalizationService.readCacheSync(savedLang); // senkron, 0ms

runApp(ProviderScope(
  overrides: [
    localeProvider.overrideWith((ref) => LocaleNotifier(initial: Locale(savedLang))),
    localizationProvider.overrideWith((ref) => LocalizationService(ref, initialPack: initialPack)),
  ],
  child: const TeqlifApp(),
));
```

**`readCacheSync(lang)`:** Hive box `initBox()` sonrası bellekte — `box.get()` O(1) memory lookup, I/O yok, gerçek 0ms.

**`LocaleNotifier(initial:)`:** `initial` verilirse `_loadSavedLocale()` async çağrısı atlanır.

**`LocalizationService(initialPack:)`:** Pack dolu gelirse `load()` atlanır, sadece arka planda `_checkStale()` çalışır.

**İlk kurulum (Hive boş):** `initialPack.isEmpty` → constructor `_fetchAndCache()` başlatır. `SplashScreen` native splash'i pack hazır olmadan kaldırmaz:

```dart
// SplashScreen._boot()
await ProviderScope.containerOf(context, listen: false)
    .read(localizationProvider.notifier)
    .ready                                     // Completer — pack hazırsa anında
    .timeout(const Duration(seconds: 5), onTimeout: () {});
FlutterNativeSplash.remove();                  // Asla key gösterilmez
```

**`LocalizationService.ready`:** Pack ilk kez dolu hale gelince tamamlanan `Completer<void>`. Cache varsa constructor'da anında complete; yoksa `_fetchAndCache()` bitince complete.

---

### 1.10 Login Sonrası Locale Öncelik Kuralı

**Sorun:** Login ekranında kullanıcı dil değiştirdikten sonra login olduğunda, `AuthService.me()` server'dan eski locale'yi (`user.locale`) getirip `setLocaleLocally()` ile ezerek kullanıcının seçimini geri alıyordu.

**Karar:** Kullanıcının login ekranında bilinçli yaptığı seçim, server'da saklı eski değerden önceliklidir.

```dart
// login_screen.dart — _submit()
bool _userChangedLang = false;  // _onLangChange başarı olunca true

// login sonrası:
if (_userChangedLang) {
  // Kullanıcının tercihi kazanır + server'a PATCH ile sync
  ref.read(localeProvider.notifier).setLocale(Locale(_displayedLang)).ignore();
} else {
  // Bilinçli seçim yok — server tercihi geri yüklenir (multi-device sync)
  ref.read(localeProvider.notifier).setLocaleLocally(Locale(user.locale!));
}
```

**Kural:** `setLocale()` = state + SharedPreferences + backend PATCH. `setLocaleLocally()` = state + SharedPreferences, PATCH yok. Login ekranında kullanıcı değiştirmediyse `setLocaleLocally` ile sunucu tercihi uygulanır.

---

## 2. Dinamik Field Konfigürasyonu

### Problem

Form alanları (marka, yıl, renk, vb.) subkategoriye göre değişiyor. Eski yaklaşımda bunlar Flutter tarafında `kSubcategoryFields` Dart sabitleri olarak hardcode edilmişti — yeni alan eklemek için uygulama güncellemesi gerekiyordu, label çevirisi ARB'a bağlıydı.

### Karar

Alan tanımları ve seçenekleri PostgreSQL'de tutulur, API'den serve edilir.  
Label'lar OTA Localization ile çevrilir. Yeni alan = DB satırı + ARB key + deploy.

### Mimari

```
category_fields (key, label_key, type, required, position, depends_on, ...)
      │  1:N
field_options   (value, label, parent_option_value, position, ...)
      │
      ▼  GET /api/field-config/{subcategory}  [24h server cache]
      │
FieldConfigService.getFields(subcategory)  [in-memory cache]
      │
ExtraFieldDef(key, labelKey, type, options, dependsOn, ...)
      │
_buildExtraField(f, loc)
      │  loc.t(f.labelKey)                    → "Marka", "Yıl", ...
      │  loc.tOr('opt_${o.value}', o.label)  → "Beyaz", "BMW", ...
      ▼
Form widget (TextField / DropdownButton / MultiSelect)
```

---

### 2.1 Veritabanı Şeması

```
category_fields
  id, subcategory, key, label_key, type, required,
  position, unit, depends_on, is_active

field_options
  id, field_id, value, label, parent_option_value, position, is_active
```

**Alan tipleri:** `text` | `number` | `dropdown` | `multiselect`

**`depends_on`** — hangi alanın değerine bağlı olarak gösterileceği (`f.key`'e referans)  
**`parent_option_value`** — koşullu seçenekler için: `NULL` → her zaman göster; `'bmw'` → sadece parent `bmw` seçilince; `'__excl__'` → multiselect'te exclusive seçenek; `'grp:...'` → grup başlığı

---

### 2.2 Translation Key Convention

| Tablo kolonu | Translations key | Örnek |
|---|---|---|
| `category_fields.label_key` | `extraField_brand` | "Marka" / "Brand" |
| `field_options.value` | `opt_${value}` → `opt_white` | "Beyaz" / "White" |
| Subkategori isimleri | `subcat_${key}` → `subcat_automobile` | "Otomobil" |

Flutter tarafı:
```dart
loc.t(f.labelKey)                    // label_key direkt translation key'i
loc.tOr('opt_${o.value}', o.label)  // opt_ prefix; yoksa DB'deki label fallback
```

**`FieldOption.label`** (DB'deki) — OTA key yoksa kullanılan son fallback. Türkçe veya İngilizce olabilir; production'da her zaman OTA key'i tanımla.

---

### 2.3 FieldConfigService — Cache Katmanları

```
1. In-memory (_cache) — uygulama ömrü boyunca, subkategori başına bir kez çekilir
2. Sunucu cache (24h) — field schema değişmez, admin deploy'da invalidate
3. Offline fallback (_fallback) — kSubcategoryFields Dart sabitleri (listing_fields.dart)
```

> ⚠️ DB'ye eklenen yeni alan offline fallback'te görünmez — bu kabul edilmiş bir trade-off.

---

### 2.4 Yeni Field veya Subkategori Ekleme

1. `category_fields` tablosuna satır ekle (`key`, `label_key`, `type`, `required`, `position`, `subcategory`)
2. Varsa seçenekleri `field_options` tablosuna ekle (`value`, `label`, `field_id`)
3. ARB dosyalarına label_key'i ekle (TR, EN, AR, RU):
   ```
   "extraField_brand": "Marka"   // TR
   "opt_bmw": "BMW"              // tek format, tüm dillerde aynı value
   ```
4. Deploy: `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`
5. Uygulama güncellemesi **gerekmez** — Flutter `FieldConfigService.getFields()` ve `loc.t()` ile her şeyi dinamik alır

---

### 2.5 Flutter Render Flow

**Dosya:** `mobile/lib/utils/listing_fields.dart` (tipler) + `mobile/lib/services/field_config_service.dart`

```dart
// Subkategori seçilince
Future<void> _updateExtraFields(String subcategoryKey) async {
  final fields = await FieldConfigService.getFields(subcategoryKey);
  setState(() => _currentFields = fields);
}

// Her alan için widget
Widget _buildExtraField(ExtraFieldDef f, TranslationPack loc) {
  final label = loc.t(f.labelKey);               // OTA label

  if (f.dependsOn != null) {                     // koşullu alan
    final parentVal = _extraValues[f.dependsOn!];
    options = f.conditionalOptions?[parentVal] ?? [];
  }

  return switch (f.type) {
    ExtraFieldType.dropdown    => ...,            // loc.tOr('opt_${o.value}', o.label)
    ExtraFieldType.multiselect => ...,
    ExtraFieldType.number      => ...,
    ExtraFieldType.text        => ...,
  };
}
```

---

## 3. Merkezi Error Handling

### Problem

Uygulama genelinde üç farklı error entry point vardı:
- `showErrorSnackbar(context, e)` — context gerektiriyor, AppLocalizations kulllanıyor
- `ErrorDisplay.fromException(context, e)` — context gerektiriyor, sealed class type dispatch
- `handleError(e, loc)` — pilot ekranda OTA ile yazıldı

### Karar

Tek entry point: `handleError(error, TranslationPack loc)` — context yok, BuildContext yok.  
Tüm hata akışı buradan geçer.

### Mimari

```
catch (e) {
  handleError(e, ref.read(localizationProvider));   // her ekranda, her catch bloğunda
}
```

```
handleError(error, loc)
  ├── 401?  →  AuthService.authFailedStream.add(null)  →  return (toast yok)
  │             main_screen bunu dinler → logout + /login
  │
  ├── message = ErrorMapper.toMessage(error, loc)
  │             ├── NetworkException      → loc.t('errorNetworkMessage')
  │             ├── AppException.code     → switch (RATE_LIMIT_EXCEEDED, INSUFFICIENT_FUNDS, ...)
  │             ├── status >= 500         → loc.t('errorServerBusy')
  │             └── fallback              → loc.t('errorGenericRetry')
  │
  ├── TeqToast.error(message)    ← context yok, navigatorKey kullanır
  │
  └── shouldLog? → LoggerService.captureException(error)
                   shouldLog = true eğer statusCode == 0 veya >= 500
```

---

### 2.1 handleError — Dosya ve İmza

**Dosya:** `mobile/lib/utils/error_helper.dart`

```dart
void handleError(Object error, TranslationPack loc) { ... }
```

`TranslationPack loc` → `ref.read(localizationProvider)` ile alınır (async context'te `ref.read`, build'de `ref.watch`).

---

### 2.2 ErrorMapper — Bilinen Hata Kodları

**Dosya:** `mobile/lib/core/error_mapper.dart`

Yeni bir backend hata kodu geldiğinde buraya ekle:

```dart
case 'YENI_KOD': return loc.t('yeniLokKey');
```

Bilinen kodlar: `RATE_LIMIT_EXCEEDED`, `FORBIDDEN`, `CAPTCHA_FAILED`, `CONTENT_POLICY_VIOLATION`,
`PROVINCE_REQUIRED`, `INVALID_CONDITION`, `INVALID_PRICE`, `LISTING_TITLE_REQUIRED`,
`INSUFFICIENT_FUNDS_PRO`, `INSUFFICIENT_FUNDS_STD`, `AI_SERVICE_BUSY`, `AI_SERVICE_TIMEOUT`

---

### 2.3 TeqToast — Context-free Toast

**Dosya:** `mobile/lib/ui_library/components/overlays/teq_toast.dart`

```dart
TeqToast.error(message)    // kırmızı
TeqToast.success(message)  // yeşil
TeqToast.warning(message)  // sarı
TeqToast.info(message)     // mavi
```

- `main.dart`'ta `TeqToast.init(TeqlifApp.navigatorKey)` ile initialize edilmiş
- Yeni toast eskisini anında replace eder
- 3.5 saniye sonra otomatik kapanır
- Aşağı sürükleyince kapanır (swipe-to-dismiss)

---

### 2.4 Form Validasyonu vs API Hatası

**Kural: error location = kullanıcının hatayı nerede düzeltebileceği**

```
Form validator (Flutter FormField)
  → Field altında inline hata
  → handleError ÇAĞRILMAZ

API catch bloğu (network'e giden istek başarısız oldu)
  → handleError(e, loc) → Toast
  → Field altında hata GÖSTERİLMEZ
```

**Neden?** Pilot testte doğrulandı: boş başlık → field altında hata (form validator). AI fiyat butonu (API çağrısı) + boş başlık → Toast (backend LISTING_TITLE_REQUIRED döndü). İkisi çakışmaz, farklı katmanlar.

---

### 2.5 Auth Error Akışı (401)

`handleError` 401 aldığında:
1. `AuthService.authFailedStream.add(null)` — sinyal ver
2. `return` — toast gösterme
3. `main_screen._handleAuthFailed()` stream'i dinler → `AuthService.logout()` → `/login`

**Neden direkt navigate etmiyoruz?** `authFailedStream` zaten `api.dart`'ta refresh başarısız olunca da tetikleniyor. Eğer `handleError` da navigate etseydi çift navigation olurdu.

---

### 2.6 Kaldırılacaklar (Ekran migrate edildikçe)

| Ne | Ne Zaman |
|----|----------|
| `showErrorSnackbar(context, e)` → `handleError(e, loc)` | Her ekran migrate edildiğinde |
| `ErrorDisplay.fromException(context, e)` → `handleError(e, loc)` | Her ekran migrate edildiğinde |
| `ErrorDisplay` sınıfı (dosya) | Son ekran migrate edildikten sonra sil |
| `AppError` sealed class (dosya) | `ErrorDisplay` silindikten sonra sil |

> ⚠️ Bu iki dosyayı henüz silme — 5 ekran hâlâ `ErrorDisplay` kullanıyor (forgot_password, login, register, host_stream, swipe_live).

---

### 2.7 TeqSnackBar — TeqToast'ın Thin Wrapper'ı

`TeqSnackBar` doğrudan `TeqToast`'a delege eder — ayrı bir implementasyon değil.

```dart
// İkisi eşdeğerdir:
TeqSnackBar.show(message: loc.t('saveSuccess'), isSuccess: true);
TeqToast.success(loc.t('saveSuccess'));
```

**Ekranlarda ne kullanmalı?**

| Durum | Kullan |
|-------|--------|
| Hata göstermek | `handleError(e, loc)` — ErrorMapper üzerinden |
| Başarı mesajı | `TeqToast.success(msg)` veya `TeqSnackBar.show(isSuccess: true)` |
| Form validasyon hatası | Flutter `FormField` validator → inline, toast değil |

`TeqSnackBar.show()` context almaz, `loc.t()` kullanır — eski context'li SnackBar pattern değil.

**Kaldırılacak:** `showErrorSnackbar(context, e)` — artık gerekmiyor.  
**Kalacak:** `TeqSnackBar.show()` ve `TeqToast.*` — ikisi aynı şey.

---

### 2.8 Result<T> — Err Tipi Değişikliği

`core/result.dart`'taki `Err<T>` değiştirildi:

```dart
// ÖNCE
class Err<T> extends Result<T> {
  final AppError error;  // <-- UI katmanına sıkı bağlıydı
}

// SONRA
class Err<T> extends Result<T> {
  final Object error;    // herhangi bir exception wrapped edilebilir
}
```

`api.dart` de `AppError.from(e)` sarmalamayı bıraktı:

```dart
// ÖNCE: return Err(AppError.from(e));
// SONRA: return Err(e);           — ham exception Err içine girer
```

**Neden?** `handleError(error, loc)` zaten `Object error` kabul eder.  
`ErrorMapper` `AppException`, `DioException`, vs. type dispatch yapar.  
`AppError` ara katman gereksizleşti.

**Servis çağrısında kullanım:**

```dart
final result = await repo.doSomething();
result.when(
  ok: (data) { ... },
  err: (error) => handleError(error, loc),
);
```

---

### 2.9 Çifte Uyarı Orkestrasyonu (Network Errors)

**Kural: Reaktif state varken, Toast susturulur.**

Eğer kullanıcı cihazında internet kesikse, ana ekranlarda `ConnectivityService` üzerinden tetiklenen kalıcı bir `OfflineBanner` görünür (Reaktif State). Aynı esnada arka planda veya kullanıcının tetiklemesiyle fail olan API çağrıları `NetworkException` fırlatır.

Bu gibi durumlarda kullanıcının aynı anda hem kalıcı Banner'ı hem de geçici Toast pop-up'ını (Redundancy) görmemesi için `handleError` içerisine bir susturma (Supression) mekanizması eklenmiştir:

```dart
if (error is NetworkException && !ConnectivityService.isDeviceOnline) {
  // OfflineBanner zaten görünür olduğu için Toast basma
  return;
}
```

Bu sayede, kullanıcının UI üzerinden aynı anda çifte uyarı görmesi engellenmiş ve kullanıcı deneyimi (UX) pürüzsüz hale getirilmiştir. `OfflineBanner` sadece `main_screen.dart` gibi kök (root) yapıların içinde yer alır, sekme içeriklerine (örneğin `live_list_screen`) tekrar tekrar eklenmez.

---

## 3. ML / Analytics / ClickHouse

### 3.1 ClickHouse Schema Değişikliği: ALTER TABLE

**Karar: `ALTER TABLE ... ADD COLUMN` — yeni tablo açma**

ClickHouse MergeTree'de `ADD COLUMN` non-blocking'dir; mevcut satırlar otomatik olarak sütunun default değerini alır (boş string veya 0). Yeni INSERT'ler sütunu doldurur, eski satırlara backfill gerekmez. Geriye dönük uyumluluk korunur.

> Yeni bir ClickHouse sütunu eklemek için yeni tablo açmaya gerek yok. ALTER + default yeterli.

---

### 3.2 user_interests Subcategory Pattern

**Karar: Ayrı tablo değil, aynı tabloda `subcategory IS NULL` / `NOT NULL` ayrımı**

```sql
user_interests(user_id, category, subcategory, score)
-- subcategory IS NULL     → top-level kategori skoru ("arabalar")
-- subcategory IS NOT NULL → alt kategori skoru ("arabalar | sedan")
```

Feed scoring SQL her iki satır tipini birlikte kullanır — top-level affinity ve subcategory affinity ayrı sütunlardan okunur, backward compat korunur. Yeni subcategory sütunu için migration: `aac_user_interests_subcategory`.

---

### 3.3 ML Model Güncellemelerinde Veri Önce Prensibi

**Karar: ClickHouse'da subcategory verisi birikmeden ML modelleri güncellenmez**

ALS / BPR / K-Means'e subcategory feature enjekte etmek için önce 2-4 hafta gerçek kullanıcı sinyali birikmelidir (`user_events.subcategory`, `feed_analytics.listing_subcategory`). Veri olmadan yapılan model güncellemesi mock veriyle overfitting üretir.

**Eğitim frekansları:**
- BPR: haftada 3x (Pazartesi/Çarşamba/Cumartesi)
- K-Means: haftada 2x (Çarşamba/Pazar)
- Feed ALS + SwipeLive ALS: haftada 1x

---

### 3.4 Subcategory Sinyal Akışı

```
Mobile logInteraction(subcategory)
  → /api/analytics/user-events → user_events.subcategory (ClickHouse)
  → Redis flush (5 dk) → user_interests güncelleme

Mobile feed_telemetry(listingSubcategory)
  → /api/analytics/feed-events → feed_analytics.listing_subcategory

worker.py backfill_listing_embeddings
  → _listing_embed_text() = title + description + category + subcategory + extra_fields
  → listings.embedding (pgvector)

BPR / ALS eğitimi
  → subcategory hard-negative örnekleme
  → Redis: bpr:rec:{uid}, feed:als:user_vec:{uid}

feed_queries._score_and_rank()
  → subcat_affinity_expr CASE (top-8 subcategory, ağırlık 0.08)
  → greedy diversity: MAX_PER_SUBCAT=2
```

---

## 5. Async Buton Loading Pattern

### Problem

Bir butona basıldığında network çağrısı tetikleniyorsa (dialog açmadan önce API, form submit, vb.), API yanıtı gelmeden kullanıcı tekrar tıklayabiliyor. Her tıklama ayrı bir coroutine başlatıyor; birden fazla dialog açılıyor veya istek tekrarlıyor.

Manuel çözüm (`_loading` bool + `setState`) her ekranda yeniden yazılması gereken boilerplate üretiyor.

### Karar

İki katmanlı kural:

| Durum | Kullan |
|-------|--------|
| Yalnızca "çift tıklamayı önle" gerekiyor | `TeqAsyncButton` |
| Loading state başka widget'larda da görünüyorsa **veya** yaşam süresi tek build'i aşıyorsa (cooldown, timer) | `TeqButton` + provider state (`isLoading: notifier.isSending`) |

### TeqAsyncButton

**Dosya:** `mobile/lib/ui_library/components/buttons/teq_async_button.dart`

`onPressed` olarak `Future<void> Function()?` alır. Future süresince butonu otomatik spinner'a alır, çift tıklamayı önler. Future bitince butonu serbest bırakır. Ekranda `_loading` bool veya `setState` yazmaya gerek yok.

```dart
// ÖNCE — ekranda bool + setState
bool _submitLoading = false;

TeqButton(
  onPressed: _submitLoading ? null : () async {
    setState(() => _submitLoading = true);
    try { await _submit(); }
    finally { if (mounted) setState(() => _submitLoading = false); }
  },
  isLoading: _submitLoading,
  text: 'Gönder',
)

// SONRA — TeqAsyncButton
TeqAsyncButton(
  onPressed: _submit,
  text: 'Gönder',
)
```

Props `TeqButton` ile aynıdır (`text`, `type`, `size`, `customColor`, `icon`, `isDisabled`, `isExpanded`). `isLoading` dışarıdan geçilmez — buton kendi yönetir.

### Provider state ne zaman gerekli?

`isMassNotifSending` (Toplu Kitle Bildirimi) örneği:
- Cooldown sayacı başka bir widget'ta da gösteriliyor
- Sealed class state (`MassNotifAvailable`, `MassNotifCooldownActive`) provider'da tutuluyor
- Loading state bir timer ile güncelleniyor — widget build döngüsünü aşıyor

Bu durumlarda `TeqButton(isLoading: ref.watch(...).isSending, onPressed: isSending ? null : handler)` pattern'i korunur.

---

## 6. Deploy Pipeline

### Standart Deploy Komutu

(`/var/www/teqlif.com/backend/` dizininden)

```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

### Migration Varsa

```bash
git pull && alembic upgrade head && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

### sync_translations.py Ne Yapar?

- 4 ARB dosyasını okur
- `translations` tablosuna UPSERT eder (7100+ satır)
- Redis `i18n:*` cache'lerini temizler
- Kaç key sync'lendiğini rapor eder

### Backend Error Response Formatı

Tüm hatalar standart JSON formatında döner:

```json
{ "success": false, "error": { "code": "HATA_KODU", "message": "Lokalize mesaj" } }
```

- `AppException` subclass'ları → `app_exception_handler` → doğru `code` ile format
- Düz `HTTPException` → `http_exception_handler` → `code` = `HTTP_{status}` (kaçınılmalı)
- **Kural:** Yeni backend hataları için her zaman `AppException` subclass kullan, düz `HTTPException` yazma

---

## 7. Ekran Migration Checklist

Bir ekranı refactor ederken sırayla bu adımları uygula.

### 4.1 OTA Localization

- [ ] `class MyScreen extends ConsumerStatefulWidget`
- [ ] `class _MyState extends ConsumerState<MyScreen>`
- [ ] `build()` başına `final loc = ref.watch(localizationProvider);` ekle
- [ ] `async` metodlarda `final loc = ref.read(localizationProvider);` kullan
- [ ] `import '...app_localizations.dart'` sil
- [ ] `import '...field_labels.dart'` sil (varsa)
- [ ] `final l = AppLocalizations.of(context)!` sil
- [ ] `l.xxx` → `loc.t('xxx')` (tüm occurrences)
- [ ] `l.xxx(param)` → `loc.t('xxx', {'param': value.toString()})`
- [ ] Option label: `o.label` → `loc.tOr('opt_${o.value}', o.label)`
- [ ] Subcategory label: `subcatLabel(...)` → `loc.tOr('subcat_${s.$1}', s.$2)`
- [ ] Extra field label: `_extraFieldLabel(f.labelKey, l)` → `loc.t(f.labelKey)`
- [ ] İç widget'lar: `ConsumerWidget`'a çevir veya `loc` parametresi geç

### 4.2 Error Handling

- [ ] `showErrorSnackbar(context, e)` → `handleError(e, ref.read(localizationProvider))`
- [ ] `ErrorDisplay.fromException(context, e)` → `handleError(e, ref.read(localizationProvider))`
- [ ] `ErrorDisplay.show(context, appError)` → `handleError(e, ref.read(localizationProvider))`
- [ ] Ekran-spesifik `_mapError()` / `_extractMessage()` metodları → sil
- [ ] `import '...error_display.dart'` → sil
- [ ] `import '...app_error.dart'` → sil
- [ ] `import '...error_helper.dart'` ekle (handleError için)

### 4.3 Async Buton

- [ ] Network veya async iş tetikleyen butonlar `TeqAsyncButton` kullanıyor mu?
- [ ] Ekranda `_xxxLoading` bool + `setState(() => _xxxLoading = ...)` varsa → `TeqAsyncButton`'a migrate et
- [ ] Provider state'e bağlı loading (`isLoading: ref.watch(...).isSending`) gereken durumlarda `TeqButton` korunuyor

### 4.4 Son Kontroller

- [ ] `dart analyze` → 0 error, 0 warning
- [ ] Cihazda 4 dil test: TR / EN / AR / RU
- [ ] Error senaryosu test: network hatası veya API hatası → Toast görünmeli
- [ ] `Result<T>` kullanan servis çağrıları varsa: `Err(:final error)` → `handleError(error, loc)`

---

## Hızlı Başvuru

```dart
// Localization — build()
final loc = ref.watch(localizationProvider);

// Localization — async metod
final loc = ref.read(localizationProvider);

// Error handling — her catch bloğu
} catch (e) {
  handleError(e, ref.read(localizationProvider));
}

// Option label
loc.tOr('opt_${option.value}', option.label)

// Param ile key
loc.t('errorWithCount', {'count': n.toString()})
```

---

## 8. UI ve State Management Mimarisi (MVVM)

Flutter tarafında yeni geliştirilen veya refactor edilen karmaşık ekranlarda (iş mantığının UI ile iç içe geçtiği "Fat View" durumlarında) **MVVM (Model-View-ViewModel)** yaklaşımı uygulanacaktır.

- **Model:** API'den dönen veri yapıları (DTO, Entity) ve repository metodlarıdır.
- **ViewModel (Riverpod `AsyncNotifier` veya `Notifier`):** Sayfanın iş mantığını, API çağrılarını, veri manipülasyonunu ve state yönetimini üstlenir.
  - UI (Widget ağacı) veya `BuildContext` hakkında hiçbir şey bilmemelidir.
  - Sayfanın güncel durumunu (`loading`, `data`, `error` veya state class) kapsüller (encapsulate) ve dışarıya sunar.
- **View (Screen):** Sadece UI çizimi (render) yapar. 
  - `ref.watch(myViewModelProvider)` kullanarak ViewModel'deki duruma (state) göre ekranda ne gösterileceğine (loading spinner, list, error vs.) karar verir.
  - `setState` kullanımından olabildiğince kaçınılmalıdır. Tüm işlevler (butona basılması, pull-to-refresh vb.) doğrudan ViewModel üzerindeki metodlara yönlendirilir (Örn: `ref.read(myViewModelProvider.notifier).fetchData()`).

**Neden MVVM?**
`messages_screen.dart` ve `profile_screen.dart` gibi karmaşık sayfalardaki iş mantığı Widget'lardan soyutlandığında; kod temizleşir, sayfalar hafifler, test edilebilirlik artar ve aynı state başka widget'lar tarafından da kolaylıkla tüketilebilir hale gelir.
