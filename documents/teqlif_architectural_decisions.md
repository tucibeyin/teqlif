# Architectural Decisions

Bu dosya, teqlif'teki büyük mimari kararları ve uygulama pattern'lerini tutar.  
**Yeni bir ekranı refactor ederken bu dosyaya bak — her karar burada, neden sorusuyla birlikte.**

**Pilot ekran:** `create_listing_screen.dart` (tüm pattern'lar burada uygulandı, referans al)  
**Son güncelleme:** Ekim 2026 — §33 ClickHouse DB yeniden adlandırma: teqlif_analytics → teqlif_prod_analytics

---

## İçindekiler

1. [OTA Localization](#1-ota-localization)
2. [Dinamik Field Konfigürasyonu](#2-dinamik-field-konfigürasyonu)
3. [ML / Analytics / ClickHouse](#3-ml--analytics--clickhouse)
4. [Merkezi Error Handling](#4-merkezi-error-handling)
5. [Async Buton Loading Pattern](#5-async-buton-loading-pattern)
6. [Deploy Pipeline](#6-deploy-pipeline)
7. [Ekran Migration Checklist](#7-ekran-migration-checklist)
8. [Kategori `is_listable` Flag](#8-kategori-is_listable-flag)
9. [Cache Taksonomisi ve Schema-Versioned İnvalidasyon](#9-cache-taksonomisi-ve-schema-versioned-i̇nvalidasyon)
13. [Bir İş Nasıl Yapılır (Development Workflow)](#13-bir-i̇ş-nasıl-yapılır-development-workflow)
18. [AI Proxy Mimarisi — Redis Keşfi](#18-ai-proxy-mimarisi--redis-keşfi)
19. [Stream Recording — aiortc Gizli Abone](#19-stream-recording--aiortc-gizli-abone)
20. [HostStream MVVM Refactor + ICE Retry](#20-hoststream-mvvm-refactor--ice-retry)
22. [Cache V1.1 — Feed Entity Store ve ID-List Mimarisi](#22-cache-v11--feed-entity-store-ve-id-list-mimarisi)
23. [Cache V1.2 — SWR Geçişi ve Repository ADR §22 Uyumu](#23-cache-v12--swr-geçişi-ve-repository-adr-22-uyumu)
24. [feed:recent ZSET Tutarlılık Kuralları](#24-feedrecent-zset-tutarlılık-kuralları)
25. [Chat Dump Güvenilirliği — Kayıp Önleme](#25-chat-dump-güvenilirliği--kayıp-önleme)
26. [Recording Detail V1.5 — Analitik Sekme Dashboard](#26-recording-detail-v15--analitik-sekme-dashboard-commit-c1e66024-d2b17e5e-65101e02)
27. [teqlif-agent Bug Düzeltmeleri — Healer + Watchdog](#27-teqlif-agent-bug-düzeltmeleri--healer--watchdog-commit-afeaf889)
28. [Healer Polkit + Redis Failover + node2 Monitoring Temizliği](#28-healer-polkit--redis-failover--node2-monitoring-temizliği-commit-62c29222)
29. [Stream Recording V1.6 — Dinamik Encode Parallelism](#29-stream-recording-v16--dinamik-encode-parallelism-commit-14e8bd1b-847d991a)
30. [teqlif-agent İzleme Düzeltmeleri — Redis/Backup/Cleaner/PG Replikasyon](#30-teqlif-agent-i̇zleme-düzeltmeleri--redisbackupcleaner-pg-replikasyon-commit-daa72d2b-dd206266-28836f45-9c6ecf18-ef2dcadc)
31. [MinIO ILM Acil Freni + Off-site Sync Altyapısı](#31-minio-ilm-acil-freni--off-site-sync-altyapısı)

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

## 2. Dinamik Field Konfigürasyonu (Declarative)

### Problem

Form alanları (marka, yıl, renk, vb.) subkategoriye göre değişiyor. Eskiden bu alanları ve seçeneklerini (options) veritabanına eklemek veya sıralarını (position) değiştirmek için her defasında özel Python "seeder" scriptleri (örn: `seed_emlak_listing_types.py`) yazıp DB'ye manuel kayıt atmak zorundaydık. Bu hem hata yapmaya açık hem de takip edilmesi zor bir yöntemdi.

### Karar

**Declarative (Bildirimsel) JSON Mimarisini** benimsedik.  
Tıpkı OTA çevirilerinde (ARB dosyaları) olduğu gibi, **kategori alanlarının (extra fields) Tek Gerçek Kaynağı (Source of Truth) artık repodaki `documents/categorization/*.json` dosyalarıdır.** Veritabanı manuel olarak düzenlenmez; deploy sırasında bir sync scripti JSON'dan okuyup DB'ye yansıtır.

### Mimari

```
documents/categorization/*.json (Tüm alanlar ve seçenekler, git'te)
      │  [deploy: python3 scripts/sync_category_fields.py]
      ▼
category_fields & field_options (PostgreSQL — Upsert & Soft Delete)
      │
      ▼  GET /api/field-config/{subcategory}  [24h server cache, otomatik silinir]
      │
FieldConfigService.getFields(subcategory)  [Flutter, Hive cache]
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

**`ChangeNotifier` + Navigation Callback Pattern (bc6998ff):**  
`BuildContext` tutamayan ViewModel'lerin navigasyon tetiklemesi gerektiğinde:
1. ViewModel'de `VoidCallback? onNavigateHome` gibi opsiyonel callback field'ları tanımlanır.
2. View `initState`'te bu callback'leri set eder (`_vm.onNavigateToReport = (id, title) { ... }`).
3. ViewModel callback'leri `null` guard ile çağırır; View navigate eder.
4. `ChangeNotifierProvider.autoDispose` ile ViewModel, ekran pop edilince otomatik dispose olur.

**Neden MVVM?**
`messages_screen.dart` ve `profile_screen.dart` gibi karmaşık sayfalardaki iş mantığı Widget'lardan soyutlandığında; kod temizleşir, sayfalar hafifler, test edilebilirlik artar ve aynı state başka widget'lar tarafından da kolaylıkla tüketilebilir hale gelir.

---

## 8. Kategori `is_listable` Flag

### Problem

`chat` gibi bazı ana kategoriler yalnızca canlı yayın / stream sistemi içinde anlam taşır; hiçbir ilan bu kategoriye bağlanamaz. Eski yaklaşımda bu kategori filtre ekranında görünüyor ve kullanıcının seçmesi halinde anlamsız boş sonuçlar üretiyordu.

### Alternatifler Değerlendirildi

| Yaklaşım | Avantaj | Dezavantaj |
|---|---|---|
| Flutter'da sabit slug filtresi (`where key != 'chat'`) | Tek satır, anlık | Yeni sistem kategorisi geldiğinde koda dokunmak şart |
| DB'de `is_listable` flag | Kod değişikliği gerekmez, server-driven | Küçük bir migration gerektirir |

### Karar

`categories` tablosuna `is_listable BOOLEAN NOT NULL DEFAULT TRUE` sütunu eklendi. Yalnızca ilan bağlanamayacak sistem kategorileri `FALSE` yapılır; bu sayede Flutter tarafında hiçbir slug sabit kodlanmaz.

### Uygulama

- **Migration:** `zzzze_add_is_listable_to_categories.py` — sütunu ekler, `chat` kategorisini `FALSE` yapar.
- **Backend:** `category.py` modeli + `/api/catalog` response'u `is_listable` alanını içerir.
- **Flutter:** `CatalogCategory.isListable` alanı; `TeqFilterSheet` dropdown'u `where((c) => c.isListable)` ile filtreler.

### Kural

Gelecekte ilan bağlanamayan yeni bir sistem kategorisi eklendiğinde **kod değişikliği gerekmez.** Yalnızca DB'de `UPDATE categories SET is_listable = FALSE WHERE key = 'yeni_kategori'` çalıştırmak yeterlidir.

---

## 9. Cache Taksonomisi ve Schema-Versioned İnvalidasyon

### Problem

Sistemde çok sayıda farklı doğaya sahip veri cacheleniyordu (fastapi-cache, manuel redis set/zadd, arq vb.). "Servis yeniden başlatıldığında hangi cache silinmeli?" sorusu sürekli karışıklık yaratıyor, yanlışlıkla silinen pahalı cache'ler veya silinmediği için eski kalan statik veriler (`/api/catalog`, `/api/cities` gibi) hatalara yol açıyordu.

### Karar

"Restart'ta ne silinsin?" sorusunun yanlış olduğu, doğru sorunun "Bu veriyi ne tetiklemeli?" olduğuna karar verildi. Sistemdeki tüm cache'ler 5 kategoriye ayrıldı:

1. **SCHEMA_VERSIONED:** Verinin şeması değiştiğinde geçerliliğini yitiren statik veriler. (Catalog, Cities, Fields). Migration ile tetiklenir.
2. **ALGORITHMIC:** Üretilmesi pahalı, periyodik veya olay bazlı güncellenen veriler. Kendi TTL'i ve cron'u vardır. (Trending, Feed).
3. **LIFECYCLE:** Stream veya Auction gibi bir olayın yaşam döngüsüne bağlı veriler. Olayın bitişiyle tetiklenir.
4. **SECURITY_CRITICAL:** Oturum, rate limit gibi güvenlikle veya maddi süreçlerle (Ad Campaign) ilgili veriler. Asla müdahale edilmez.
5. **EPHEMERAL:** Kısa TTL'li geçici veriler.

### Uygulama (Schema-Versioned)

- Redis'te `schema:static_version` adında bir anahtar tutulur.
- FastAPI uygulaması ayağa kalktığında (`init_schema_version()`) bu değeri okur.
- Statik verileri dönen endpoint'ler (`/api/catalog`, `/api/cities`, vs.) `fastapi-cache` key'ini üretirken bu versiyonu namespace olarak ekler (örn: `teqlif:cache:schema:v2:/api/catalog`).
- Veritabanında (Alembic migration) bu verileri değiştiren bir şema güncellemesi yapıldığında `bump_schema_version()` çağrılır. Versiyon 3 olur.
- Yeni gelen API istekleri "v3" aradığı için cache miss olur ve taze veriyi çeker. Eski "v2" verileri TTL (86400) süresince eriyip kaybolur. Manuel hiçbir cache temizleme (örn: `redis-cli DEL`) komutuna gerek kalmaz.

### Kural

Veritabanı şemasını (özellikle `catalog`, `cities` veya `field_config` etkileyen) değiştiren bir migration yazıldığında, mutlaka `upgrade()` ve `downgrade()` metodlarının en sonuna `bump_schema_version()` eklenmelidir.

---

## 10. Commerce WS Altyapısı — `StreamCommerceNotifier<S>`

### Problem

Auction ve Direct Sale sistemlerinin her ikisi de aynı WS kanalını (`/auction/{id}/ws`) kullanıyor; ancak WS bağlantısı, heartbeat ve exponential backoff reconnect mantığı iki ayrı notifier'da (~80 satır) neredeyse birebir kopyalanmış durumda. Her bug veya iyileştirme iki yerde ayrı ayrı düzeltilmek zorunda.

Ek olarak, `auction.py` router doğrudan `direct_sale_redis` domain'ini import ediyordu — Router → Domain Use Case bağımlılığı, Dependency Rule ihlali.

### Karar

**`StreamCommerceNotifier<S>`** abstract base class oluşturuldu. Tüm commerce ViewModel'leri bu class'ı extend eder.

```
StreamCommerceNotifier<S>          ← WS bağlantısı, heartbeat, reconnect, dispose
    ├── AuctionNotifier             ← auction domain logic + onCommerceEvent()
    └── DirectSaleHostNotifier     ← direct sale domain logic + onCommerceEvent()
```

### Kural

**WS altyapısı:** `_channel`, `_sub`, `_heartbeat`, `_connect()`, `_scheduleReconnect()`, `dispose()` yalnızca base class'ta bulunur. Notifier'larda bu kod bloklarına yer yoktur.

**Domain ayrımı:** Alt sınıf `onCommerceEvent(type, json)` metodunu implement eder. Kendi domain'iyle ilgili olmayan event tiplerini `return` ile atar.

**Viewer notifier istisnası:** `DirectSaleViewerNotifier` bu class'ı extend etmez. Viewer tarafı WS bağlantısı açmaz; state'i `DirectSaleHostNotifier`'dan (veya auction notifier üzerinden gelen event'lerden) okur. İkinci bir WS bağlantısı açılması veri tutarsızlığına ve gereksiz kaynak kullanımına yol açar.

**Router temizliği:** WS bağlantısında başlangıç state snapshot'ı `get_stream_commerce_snapshot(stream_id)` use-case fonksiyonu üzerinden alınır. Router hiçbir domain katmanına doğrudan bağımlı değildir.

### 3. Commerce Tipi Eklemek

Flash Sale veya benzeri yeni bir commerce tipi eklemek şu adımlara indirgenir:

**Backend:**
1. `flash_sale_redis.py` — state yönetimi
2. `flash_sale_commands.py` — iş mantığı
3. `commerce_snapshot.py` — flash sale state'ini snapshot'a ekle
4. `commerce_outbox.py` — flash sale event'lerini outbox'a kaydet

**Flutter:**
1. `FlashSaleState` model
2. `FlashSaleNotifier extends StreamCommerceNotifier<FlashSaleState>` — sadece `onCommerceEvent` implement edilir
3. `FlashSalePanel` widget — pure view
4. `CommercePanelWrapper._CommerceMode` enum'una `flashSale` değeri ekle
5. `_resolveMode()` ve `_forceFlashSale` bayrağı ekle

WS altyapısına, router'a veya outbox'ın temel mekanizmasına dokunulmaz.

**Referans:** `documents/commerce/PLAN.md`

---

## 11. Media Pipeline — MediaCompressor

**Referans:** `documents/medium/V2.0/plan.md`  
**Paket:** `ffmpeg_kit_flutter_min` — `video_compress` ve `flutter_image_compress` tamamen kaldırıldı.

### Temel kural

Tüm medya (ses, video, fotoğraf) upload öncesi `MediaCompressor.compress()` üzerinden geçer. İstisnalar yalnızca in-memory capture'lar (`RepaintBoundary.toImage()`).

### Flutter tarafı

**`MediaCompressor`** — `mobile/lib/services/media_compressor.dart`
- Statik class, DI yok.
- `compress(inputPath, MediaCompressType, {onProgress?})` → `CompressedMedia` (bytes + meta)
- Hata: `throw` — caller `handleError(e, loc)` ile yakalar. İptal: `MediaCompressCancelledException` → sessiz return (toast yok).
- `static cancel()` → `_currentSession?.cancel()`. Aynı anda tek session çalışır.
- Output temp dosyasını kendisi siler; caller bytes alır, path almaz.

**Progress state** — `compressionProgressProvider` (`StateProvider<double?>`)
- `null` = sıkıştırma yok, `0.0–1.0` = devam ediyor.
- ViewModel veya Fat View `onProgress` callback'te bu provider'ı günceller.
- `finally` bloğu her zaman `null`'a döndürür.

**`MediaCompressType`** enum: `voice | dmVideo | dmPhoto | listingPhoto | listingVideo | storyPhoto | storyVideo`

### Backend tarafı

**MIME validation** — `media_processor.py` → `VoiceProcessor._ALLOWED_CT`  
Opus `OggS` magic bytes ile otomatik yakalanır; `audio/opus` MIME fallback için `_ALLOWED_CT`'de tutulur.

**İlan videosu upload** — `upload.py` → `_process_listing_video`  
Client CRF23 1080p sıkıştırdığı için backend sadece remux + faststart yapar (`-c:v copy`). Re-encode yok.

**Limitler** (`media_limits.py`):

| Sabit | Değer |
|-------|-------|
| `VOICE_MAX_SECS` | 600 sn |
| `VOICE_MAX_BYTES` | 2 MB |
| `VIDEO_MAX_SECS` | 90 sn |
| `VIDEO_MAX_BYTES` | 30 MB |
| `LISTING_VIDEO_MAX_SECS` | 60 sn |
| `LISTING_VIDEO_MAX_BYTES` | 50 MB |

---

## 12. DNS ve Cloudflare Yapılandırması (V2.1)

### Trafik Akışı

V2.1'de gateway kaldırıldı. Her domain doğrudan hedef node'a işaret eder.

```
Kullanıcı → Cloudflare Edge → node1 (prod) veya node5 (staging)
```

### Cloudflare DNS Kayıtları

| Subdomain | Tip | IP / Hedef | CF Proxy | Node |
|-----------|-----|-----------|----------|------|
| `teqlif.com` | A | 193.70.46.74 | Proxied | node1 |
| `www.teqlif.com` | CNAME | teqlif.com | Proxied | node1 |
| `api.teqlif.com` | A | 193.70.46.74 | Proxied | node1 |
| `uploads.teqlif.com` | A | 193.70.46.74 | DNS only | node1 (MinIO) |
| `staging.teqlif.com` | A | 45.146.252.165 | Proxied | node5 |
| `api-staging.teqlif.com` | A | 45.146.252.165 | Proxied | node5 |
| `staging.uploads.teqlif.com` | A | 45.146.252.165 | DNS only | node5 (MinIO staging) |
| `live-staging.teqlif.com` | A | 45.146.252.165 | DNS only | node5 (LiveKit) |
| `live1.teqlif.com` | A | 135.125.175.223 | DNS only | node4 (LiveKit) |
| `live2.teqlif.com` | A | 51.75.74.124 | DNS only | node3 (LiveKit) |
| `stream3.teqlif.com` | A | 51.75.74.124 | DNS only | node3 (TURN/STUN) |
| `stream4.teqlif.com` | A | 135.125.175.223 | DNS only | node4 (TURN/STUN) |

### Proxy Kararı

- **Proxied:** Web (HTTP/HTTPS) trafiği — Cloudflare WAF, DDoS koruması ve SSL termination sağlar. Origin HTTP alır (port 80).
- **DNS only:** LiveKit, MinIO ve TURN/STUN — UDP/WebRTC/WebSocket trafiği doğrudan IP'ye gider; Cloudflare proxy bu protokollerle uyumlu değil.

### nginx Yapılandırması (V2.1)

**node1** (`deploy/scale/V2.1/node1/resources/nginx/`):
- `cloudflare-real-ip.conf` — CF edge IP bloklarından gerçek istemci IP'sini çeker
- `teqlif.com.conf` — `teqlif.com`, `www.teqlif.com`, `api.teqlif.com` → `127.0.0.1:8000` (prod FastAPI)

**node5** (`deploy/scale/V2.1/node5/resources/nginx/`):
- `cloudflare-real-ip.conf` — aynı CF IP blokları
- `staging.teqlif.com.conf` — `staging.teqlif.com`, `api-staging.teqlif.com` → `10.10.0.5:8000` (staging FastAPI, WireGuard IP)

### Kural

- `api.teqlif.com/` → `302 https://teqlif.com` (API root web'e yönlenir)
- `api-staging.teqlif.com/` → `302 https://staging.teqlif.com`
- `uploads.*` subdomain'leri nginx'e gelmez — MinIO presigned URL pattern ile direkt erişilir
- Her nginx server block `include /etc/nginx/cloudflare-real-ip.conf;` içermeli — aksi hâlde `$remote_addr` CF edge IP olur

---

## 13. Bir İş Nasıl Yapılır (Development Workflow)

**Temel ilkeler:** Clean architecture, clean code, bu dosyadaki kararlara uyum.  
Her değişiklik öncesinde `teqlif_architectural_decisions.md` okunur.

### Adımlar

1. **Local geliştirme** — Mac'te clean code, clean architecture ve bu dosyadaki kararlara uygun kod yazılır
2. **`git push`** — Mac'ten GitHub'a push edilir
3. **`git pull` (node'da)** — İlgili node'da `git pull` çalıştırılır (git kullanıcısı zaten tanımlı, `sudo` gerekmez)
4. **Config ayarı** — Gerekirse node'da `.env` veya sistem konfigürasyonu düzenlenir (`ssh nodex` ile direkt)
5. **Canlı log izleme** — `sudo journalctl -u <servis> -f` ile loglar izlenir; hata varsa adım 1'e dön
6. **Test onayı** — Kullanıcıdan test onayı alınır
7. **Dokümantasyon** — Yapılan değişiklik bu dosyaya veya ilgili `documents/` dosyasına commit numarasıyla kaydedilir
8. **Node izleme** — Bir süre node hataları gözlemlenir; hata varsa adım 1'e dön
9. **Sistem Mimarisi Güncellemesi** — `teqlif/deploy/scale/` dizini altında yapılanlar ile ilgili güncelleme yapılır
10. **Cleanup** — Geçici dosyalar, test verileri temizlenir; iş tamamlandı

### Servis restart

```bash
sudo teqlif-restart          # node'u otomatik algılar, git pull + pip sync + restart
sudo teqlif-restart --livekit  # node3/node4: LiveKit'i de yeniden başlatır
```

`teqlif-restart` sırası: git pull (tucibeyin kullanıcısıyla) → requirements değişmişse pip install → alembic upgrade head (ExecStartPre) → sync_main.py (ExecStartPre) → servis restart → son loglar.

### Staging vs Prod

| | Prod (node1) | Staging (node5) |
|---|---|---|
| Servis | `teqlif.service` | `teqlif-staging.service` |
| URL | `https://api.teqlif.com` | `https://api-staging.teqlif.com` |
| DB | `teqlif` | `teqlif_staging` |
| MinIO bucket | `teqlif` | `teqlif-staging` |
| Uploads | `https://uploads.teqlif.com` | `https://staging.uploads.teqlif.com` |
| Flutter define | `dart_defines/release.json` | `dart_defines/staging.json` |

### Kurallar

- `git pull` asla `sudo` ile çalıştırılmaz — tucibeyin kullanıcısının SSH key'i var, root'un yok
- Her restart'ta `sync_main.py` otomatik çalışır (kategori, lokasyon, çeviri sync)
- **Servis restart için her zaman `sudo teqlif-restart` kullanılır** — direkt `systemctl restart` asla kullanılmaz; script requirements.txt farkına göre pip sync yapar, direkt restart bunu atlar
- Staging DB'yi sıfırlamak için: `TRUNCATE TABLE users CASCADE;` (ilişkili tüm tablolar temizlenir)
- Staging admin yapmak için: `UPDATE users SET is_admin = true WHERE email = '...';`

---

## 14. Mail Server (Stalwart)

### Problem

Birden fazla domain için (`teqlif.com` vb.) kişisel/kurumsal mail adresleri (`info@`, `support@` vb.) gerekiyor. Ücretli servis kullanılmak istenmiyor; gizlilik ve tam kontrol öncelikli.

### Karar

**Stalwart Mail Server** node2'de self-host edildi.

**Modoboa ve diğer alternatiflere göre avantajları:**
- Tek Rust binary — Postfix + Dovecot + Django + MySQL gibi hareketli parça yok
- `stalwart-cli` ile tam CLI yönetimi, web UI zorunlu değil
- Dahili spam filtresi, ACME, rate limiting — ayrıca servis kurulmuyor
- node2 HDD RAID üzerinde çalışır, mail için yeterli I/O
- 50–100 MB RAM kullanımı (Modoboa ~500 MB)

### Mimari Özeti

```
Stalwart (node2:135.125.223.43)
  ├── SMTP    :25   (MTA-to-MTA)
  ├── Sub     :587  (istemci, STARTTLS)
  ├── Sub     :465  (istemci, TLS)
  ├── IMAP    :993  (istemci okuma, TLS)
  └── Admin   :8080 (WireGuard 10.10.0.2 only)

Depolama: RocksDB + filesystem blobs
TLS: Let's Encrypt ACME (tls-alpn-01)
```

### Yönetim Komutları

```bash
export STALWART_URL=http://10.10.0.2:8080
export STALWART_CREDENTIALS="admin:<SIFRE>"

stalwart-cli domain create yenidomain.com
stalwart-cli dkim generate rsa yenidomain.com mail
stalwart-cli account create info@yenidomain.com --name "Info"
stalwart-cli alias create destek@yenidomain.com info@yenidomain.com
stalwart-cli account list
```

### Config Yönetimi

- Şablon: `deploy/scale/V2.1/node2/resources/stalwart/config.toml` (repoda)
- Çalışan config: `/project/teqlif/config/stalwart/config.toml` (sunucuda)
- Secrets: `/project/teqlif/config/.env.mail` (sunucuda, repoya girmez)
- DKIM anahtarları: `/project/teqlif/config/stalwart/dkim/` (repoya girmez)

### Güvenlik Kuralları

- Admin HTTP portu (8080) dışarıya asla açılmaz — sadece WireGuard
- DKIM anahtarları ve `.env.mail` repoya commit edilmez
- Her yeni domain için SPF + DKIM + DMARC DNS kayıtları zorunlu
- OVH panelinden PTR kaydı `mail.teqlif.com`'a işaret etmeli
- IP reputation monitoring: `mxtoolbox.com/blacklists` ile periyodik kontrol

### Kurulum

```bash
sudo bash /var/www/teqlif.com/deploy/scale/V2.1/node2/resources/stalwart/setup.sh
```

Detaylı kurulum adımları: `deploy/scale/V2.1/documents/01_architecture.md §10`

---

## 15. Webmail (Snappymail)

### Problem

Stalwart Mail Server'ın webadmin arayüzü 443'te çalışıyor; `webmail.teqlif.com` aynı porta yönlendirilirse Stalwart webadmin'i açılır.

### Karar

Snappymail v2.38.2 — PHP-FPM + nginx port 80 üzerinden Cloudflare Flexible SSL ile sunulur.

### Trafik Akışı

```
Kullanıcı → Cloudflare (Proxied, HTTPS)
  → [Configuration Rule: SSL=Flexible]
  → [Origin Rule: port=80]
  → node2: nginx :80 → PHP-FPM → Snappymail
  → Snappymail → Stalwart IMAP :993 (127.0.0.1 via /etc/hosts)
```

### Cloudflare Kuralları (manuel)

| Kural | Tip | Koşul | Değer |
|-------|-----|-------|-------|
| webmail-ssl | Configuration Rule | Hostname = webmail.teqlif.com | SSL: Flexible |
| webmail-port | Origin Rule | Hostname = webmail.teqlif.com | Dest. Port: 80 |

### Kritik: Domain Config `type` Alanı

Snappymail `ConnectionSecurityType`: `SSL=1`, `STARTTLS=2`. Port 993 (IMAPS) ve 465 (SMTPS) implicit TLS olduğundan **`type=1`** kullanılır. `type=2` (STARTTLS) bu portlarda TLS el sıkışması başlamadan plaintext bekler — 60s timeout ile sonuçlanır.

### Hairpin NAT Önlemi

`/etc/hosts` üzerinde `127.0.0.1 mail.teqlif.com` tanımlanır; Snappymail→Stalwart bağlantısı public IP'ye çıkmadan loopback üzerinden gider. PHP-FPM'nin DNS cache'ini temizlemek için `hosts` değişikliğinin ardından `systemctl restart php8.4-fpm` gerekir.

### Kurulum

```bash
sudo bash /var/www/teqlif.com/deploy/scale/V2.1/node2/resources/webmail/setup.sh
```

### Kural

- Snappymail domain config dosyası: `/var/www/webmail/data/_data_/_default_/domains/teqlif.com.json`
- `type` değeri **asla 2 (STARTTLS) yapılmaz**; 993/465 için her zaman `1` (SSL)
- `/etc/hosts` değişikliğinden sonra mutlaka `systemctl restart php8.4-fpm`

---

## 16. SwipeLive UX — Geçiş Animasyonları

### Problem

- Canlı yayına geçişte sadece spinner gösteriliyordu; içerik hakkında bilgi yoktu.
- İlan sayfalarında video yüklenene kadar beyaz flash / ani geçiş oluşuyordu.

### Karar

**Canlı yayın bekleme ekranı (`_buildStreamLoadingScreen`):**
Bağlantı kurulmadan önce `BackdropFilter + ImageFilter.blur` ile bulanık thumbnail arka plan; üstünde host avatar, `@username`, yayın başlığı, kategori rozeti (CategoryService), izleyici sayısı, `liveBadgeLabel` (OTA lokalize) ve ince spinner.

**Fade geçişleri (`AnimatedSwitcher`):**
- Canlı yayın arka planı (`_buildLiveBackground`): `ValueKey` ile keyed widget, 700ms fade — thumbnail → video akışı geçişi
- İlan video/thumbnail (`_buildListingBackground`): 500ms fade — thumbnail varken spinner gizlenir, video hazır olunca fade ile geçer

### Kurallar

- Tüm OTA string'ler `loc.t(key)` ile çekilir; hardcode `'LIVE'` gibi sabit string yasaktır
- Renk sabitleri `withValues(alpha:)` kullanır (`withOpacity` Flutter 3.27+'da deprecated)
- `AnimatedSwitcher` içindeki widget'lar farklı `ValueKey` taşımalı; aksi halde Flutter aynı widget tipi olduğunda geçiş animasyonu tetiklemez
- Kategori label için **`CategoryService.localizedLabelFor(loc, key)`** kullanılır — `labelFor(key, locale:)` API cache'e bağımlıdır, cache dolmamışsa ham key döner ve OTA uyumsuz olur

---

## 17. nodeMonitor — Merkezi İzleme Altyapısı

### Problem

- node2 HDD RAID-1 (~70 MB/s, ~440 IOPS) Prometheus TSDB için kritik yavaştı; write amplification sorunu.
- Monitoring stack node2'de çalışıyorken node2 donanımsal bir sorun yaşarsa hem backup hem izleme aynı anda devre dışı kalıyordu.
- node2 OVH kaynaklı; tek sağlayıcı bağımlılığı azaltmak gerekiyordu.

### Karar

**Ayrı, bağımsız bir VPS** (nodeMonitor — Netcup Karlsruhe DE) üzerinde tüm monitoring stack çalıştırılır:
- Farklı sağlayıcı → provider-level failure izolasyonu
- SSD disk → Prometheus TSDB için yeterli IOPS
- Küçük, ucuz VPS (2GB RAM, 60GB SSD) — monitoring workload için yeterli

### nodeMonitor Teknik Özellikleri

| Özellik | Değer |
|---------|-------|
| WireGuard IP | 10.10.0.99 |
| Public IP | 94.16.105.135 |
| Sağlayıcı | Netcup Karlsruhe DE |
| RAM | 2GB |
| Disk | 60GB SSD |
| OS | Debian 12 Bookworm |
| SSH | 2FA (key + Google Authenticator) |

### Stack Bileşenleri

| Bileşen | Port | Veri Dizini | Config |
|---------|------|-------------|--------|
| Prometheus 2.x | 10.10.0.99:9090 | `/opt/monitor/teqlif/prometheus/data/` | `deploy/.../nodeMonitor/config/teqlif/prometheus.yml` |
| Loki 3.x | 10.10.0.99:3100 | `/opt/monitor/teqlif/loki/data/` | `deploy/.../nodeMonitor/config/teqlif/loki.yml` |
| Alertmanager 0.x | 127.0.0.1:9093 | `/opt/monitor/teqlif/alertmanager/data/` | `/project/teqlif/config/alertmanager.yml` (Telegram token — repoya girmez) |
| Grafana 11.x | 10.10.0.99:3000 | `/opt/monitor/shared/grafana/data/` | `/project/shared/config/grafana.ini` |
| Uptime Kuma | 10.10.0.99:3001 | `/opt/monitor/shared/uptime-kuma/data/` | `/project/shared/config/uptime-kuma.env` |
| MariaDB | 127.0.0.1:3306 | sistem default | Uptime Kuma backend DB |

### node-exporter (Tüm Node'larda)

Her node'da `teqlif-node-exporter.service` (`deploy/scale/V2.1/common/systemd/node-exporter.service`) çalışır:

```ini
ExecStart=/bin/bash -c 'exec /usr/local/bin/node_exporter \
  --web.listen-address=$(ip -4 addr show wg0 | grep -oP "(?<=inet )[\d.]+" | head -1):9100'
```

- WireGuard IP'yi **dinamik** tespit eder — aynı servis dosyası tüm node'larda çalışır
- `wg-quick@wg0.service` gerektir — WG hazır olmadan başlamaz
- UFW: `allow proto tcp from 10.10.0.0/24 to any port 9100` (tüm node'lar)
- node1/node2: `Anywhere on wg0 ALLOW 10.10.0.0/24` stili kural yeterliydi; node3–6 için port 9100'ü explicit açmak gerekti

### Grafana Kritik Notlar

**override.conf zorunlu alanlar:**
```ini
EnvironmentFile=/etc/default/grafana-server        # GF_* env'leri için
cfg:default.paths.bundled_plugins=/usr/share/grafana/plugins-bundled  # Prometheus plugin kaydı
```

`bundled_plugins` path verilmezse Prometheus datasource `Plugin not registered` hatası verir.

**`/etc/grafana/` izin sorunu:** Grafana `grafana` user'ına ait kurulur, `User=tucibeyin` ile çalışınca:
```bash
chmod o+rx /etc/grafana
chmod -R o+rX /etc/grafana/
```

**Grafana provisioning:** Datasource'lar repodaki YAML'dan otomatik yüklenir:
- `deploy/scale/V2.1/nodeMonitor/config/shared/grafana-provisioning/datasources/datasources.yml`
- `grafana.ini` → `provisioning =` bu dizine işaret eder

### Loki Kritik Not

`retention_enabled: true` ise `compactor.delete_request_store: filesystem` **zorunlu** — yoksa Loki başlamaz.

### Alertmanager Konfigürasyonu

`/project/teqlif/config/alertmanager.yml` repoya girmez (Telegram Bot Token içerir). Template:
`deploy/scale/V2.1/nodeMonitor/config/teqlif/alertmanager.yml.template`

### Uptime Kuma — MariaDB Backend

SQLite yerine MariaDB seçildi (gelecekteki multi-project expansion için).

```
DATABASE=mariadb
DB_HOSTNAME=127.0.0.1
DB_PORT=3306
DB_USERNAME=uptime_kuma
DB_NAME=uptime_kuma
DB_PASSWORD=<secret>  → /project/shared/config/uptime-kuma.env
```

**13 Monitör:**

| Grup | Monitor | Tip |
|------|---------|-----|
| Production API | api.teqlif.com/health | HTTP |
| Production API | api.teqlif.com WebSocket | TCP |
| Storage | uploads.teqlif.com/minio/health/live | HTTP |
| Streaming | node3 nginx :443 | TCP |
| Streaming | node4 nginx :443 | TCP |
| Staging | api-staging.teqlif.com/health | HTTP |
| AI Proxy | node6 AI Proxy :8001 | TCP |
| AI Proxy | node5 AI Proxy :8001 | TCP |
| Mail | mail.teqlif.com SMTP :25 | TCP |
| Mail | mail.teqlif.com IMAP :993 | TCP |
| Internal | node1 nginx :80 | TCP |
| Internal | node5 nginx :80 | TCP |
| Internal | nodeMonitor Prometheus :9090 | TCP |

**Not:** node1/node5'te nginx 80→443 redirect yaptığından ve HTTPS sertifikası public IP'ye değil domain'e ait olduğundan, bu node'lar için HTTP yerine TCP Port check kullanılır.

### Kurallar

- Alertmanager config (`alertmanager.yml`) asla repoya commit edilmez — Telegram credentials içerir
- `uptime-kuma.env` ve `grafana.ini` içindeki `admin_password` placeholder kaldığında repoya girmesi sorun olmaz; production değerleri `/project/shared/config/` altında 600 perm ile saklanır
- Monitoring portları (3000, 3001, 3100, 9090, 9093) dışarıya **asla** açılmaz — WireGuard erişim yeterli
- Grafana Node Exporter Full dashboard'u **template variable'ları** (job, instance) ilk açılışta manuel seçilmeli; Grafana 11 URL state'i sonraki açılışlarda korur
- Yeni node eklendiğinde: `prometheus.yml`'a scrape target ekle, node'a `node-exporter.service` kur, `ufw allow port 9100` ver


---

## 18. AI Proxy Mimarisi — Redis Keşfi

### Karar: Statik URL yerine Redis tabanlı servis keşfi

**Durum:** node6 AI Proxy birincil, node5 ikincil olarak `ai_proxy_url` / `ai_proxy_fallback_url` config alanlarıyla tanımlanıyordu. node6'dan AI işleri node5'e taşındı; gelecekte yeni AI node'ları eklenebilir.

**Karar:** `ai_proxy_client.py` Core Redis'teki `edge:metrics:*` anahtarlarını okuyarak sağlıklı AI proxy node'larını keşfeder. Statik config alanları kaldırıldı.

### Keşif Mantığı

```
Core Redis (node1:6379)
  edge:metrics:node5  → { ai_proxy_url, ai_proxy_priority: 10, services.ai_proxy.healthy: true }
  edge:metrics:nodeX  → { ai_proxy_url, ai_proxy_priority: 20, services.ai_proxy.healthy: true }

ai_proxy_client._discover_ai_proxy_urls()
  → healthy node'ları filtrele (services.ai_proxy.healthy == true)
  → ai_proxy_priority ile sırala (küçük = önce)
  → 30 saniyelik in-process cache (Redis yükü minimumda)

generate_via_proxy()
  → her sağlıklı node sırayla denenir
  → tümü erişilemezse lokal llm_service.py'e fallback
```

### Yeni Node Ekleme (Plug & Play)

1. Node'da `teqlif-ai-proxy` ve `teqlif-metrics-agent` servislerini kur
2. `.env.metrics-agent` içinde `NODE_SERVICES=ai_proxy`, `EDGE_AI_PROXY_URL=http://<ip>:8001`, `EDGE_AI_PROXY_PRIORITY=<öncelik>` set et (küçük değer = önce denenir)
3. Servis sağlıklı hale gelince Core Redis'e yazar; `ai_proxy_client` sonraki 30 saniye içinde onu keşfeder
4. `config.py` veya `.env.production` değişikliği gerekmez

### Config Değişiklikleri

- **Kaldırıldı:** `ai_proxy_url`, `ai_proxy_fallback_url` (`config.py`)
- **Korundu:** `ai_proxy_internal_token` (shared bearer token — tüm proxy node'larında aynı değer)
- **Eklendi:** `EDGE_AI_PROXY_PRIORITY` env var (`edge_metrics_agent.py`, varsayılan: 100)

### Staging'de AI Proxy Keşfi

Staging backend `CORE_REDIS_URL=redis://…@127.0.0.1:6379/0` (staging Redis) okur.  
Ana `teqlif-metrics-agent` ise `10.10.0.1:6379` (prod Redis) yazar → staging backend'de keşif yoktu.

**Çözüm (51df667e):** node5'te ayrı `teqlif-metrics-agent-staging.service` eklendi.  
Config: `deploy/scale/V2.1/node5/resources/.env.metrics-agent-staging.template`  
`CORE_REDIS_URL` olarak staging Redis URL'i kullanır; servis `PartOf=teqlif-staging.service`.

### Mevcut Durum (2026-10-12)

| Node | Rol | Öncelik | Durum |
|------|-----|---------|-------|
| node6 | AI Proxy Primary | 10 | Aktif (Virginia US, Gemini kısıtsız + Groq) |
| node5 | AI Proxy Secondary | 20 | Aktif (EU, Groq + Gemini limitli) |

---

## 19. Stream Recording — livekit-rtc Gizli Abone

**Commit:** `51df667e` (ilk tasarım) → `c92afc02` (livekit-rtc migration, Ekim 2026)

### Problem

FFmpeg'in `whep://` demuxer'ı Debian paketinde yok; LiveKit `/rooms/{room}/whep` endpoint'i de mevcut değil.  
livekit-egress Docker tabanlı — kabul edilmedi.  
LiveKit DTLS/SRTP şifreli WebRTC kullandığından ağ tapı mümkün değil; yalnızca odaya WebRTC katılımcısı olarak girmek kayıt için çalışır.

**livekit-rtc migration (Ekim 2026):** aiortc, yayın süresiyle doğrusal büyüyen bellek sızıntısı sergiledi (~167 MB/dak). Resmi LiveKit Python SDK (`livekit` paketi, Rust tabanlı) ile değiştirildi: RSS ~98 MB sabit, sızıntı yok.

### Karar: livekit-rtc ile gizli WebRTC abone

Her canlı yayın başladığında `teqlif-agent`, `livekit_subscriber.py`'yi subprocess olarak başlatır.  
Script resmi `livekit.rtc` SDK'sı ile odaya `hidden=True, recorder=True` JWT'siyle girer, VP8 + Opus MKV dosyasına kaydeder.

### Tetikleme: Event-Driven + Fallback Poll

```
ConfirmLiveCommand.execute()               (yayın canlıya alınınca — anında)
  → stream.status = LIVE → commit
  → background: redis.publish("teqlif:recording:stream_started",
                               {stream_id, room_name, host_id})

RecordingManager._pubsub_loop()            (arka planda sürekli çalışır)
  → Redis SUBSCRIBE teqlif:recording:stream_started
  → mesaj gelince → _event_queue.put(data)

RecordingManager.run() — her 60s cycle
  → _drain_event_queue()                   (pub/sub eventi varsa anında işle)
      → DB'de kayıt yok mu? → _start_recording()
  → _sync_recordings()                     (fallback poll — event kaçırma güvencesi)
      → live_streams.status = 'live' AND stream_recordings yok
      → asyncio.create_subprocess_exec(livekit_subscriber.py ...)
  → _reap_finished()
      → returncode == 0 → status='encoding' + db.mark_ok("recorder.<node_id>")
      → returncode != 0 → status='failed'  + db.mark_fail("recorder.<node_id>")

livekit_subscriber.py
  → rtc.Room.connect(ws_url, token)
  → on_track_subscribed: publication.set_video_quality(HIGH)   ← dynacast HIGH layer iste
  → _open_when_ready(): çözünürlük 500ms sabit kalınca container aç (max 3s timeout)
  → _record_video: VideoStream(BGRA) → numpy → av.VideoFrame → VP8 encode → MKV
  → _record_audio: AudioStream → av.AudioFrame → Opus encode → MKV
  → stop_evt (room disconnect | SIGTERM) → tüm task'ler cancel → vs.aclose()/ast.aclose()
  → writer.close() → room.disconnect() → çıkış kodu 0

EncoderManager
  → MKV → MP4 (FFmpeg encode) → MinIO transfer
```

### Simulcast ve Kayıt Kalitesi

Yayıncı telefon `dynacast: true` ile yayın yapar — SFU yalnızca aktif izlenen katmanları iletir.  
Recorder bağlandığında `set_video_quality(HIGH)` ile HIGH katmanı talep eder (~500ms–2s içinde gelir).  
`_open_when_ready()` ilk frame'den itibaren çözünürlüğün 500ms sabit kalmasını bekler; bu sayede  
container LOW (~360p) yerine doğru kalitede (yayıncı desteklediği max) açılır.

Yayın sırasında izleyici katılımıyla çözünürlük yükselebilir (dynacast); bu durumda  
frame encoder boyutuna `reformat()` ile ölçeklenir — container yeniden açılmaz.

### Sağlık İzleme

`RecordingManager._reap_finished()`, her kayıt bitişinde `AgentDB.mark_ok` / `mark_fail` çağırır:

| Durum | Çağrı | Etki |
|-------|-------|------|
| Başarılı (exit 0) | `mark_ok("recorder.<node_id>", expected_every_m=10080)` | fail_count sıfırlanır |
| Hatalı (exit ≠ 0) | `mark_fail("recorder.<node_id>", expected_every_m=10080)` | fail_count artar |

`job_health` tablosu gossip ile tüm node'lara replike olur; Grafana'dan sorgulanabilir.  
`expected_every_m=10080` (1 hafta) — kayıtsız dönemlerde false stale alert engellenmiş olur.

### Redis Topolojisi

**Prod (node3/4):** Backend (node1) → Core Redis (`127.0.0.1:6379`) `PUBLISH`.  
Agent (node3/4) → Core Redis (`10.10.0.1:6379`) `SUBSCRIBE`. Aynı instance — sorunsuz.

**Staging (node5):** Staging backend → Staging Redis (`127.0.0.1:6379`) `PUBLISH`.  
Agent → Staging Redis (`127.0.0.1:6379`) `SUBSCRIBE` — `redis_url_env: STAGING_REDIS_URL`.

`cluster.yaml`'daki `redis_url_env` pattern'i `pg_dsn_env` ile aynı: `/etc/teqlif-agent/env` dosyasına  
`STAGING_REDIS_URL=redis://:<pass>@127.0.0.1:6379/0` eklenir. `setup_node.sh` bu değeri otomatik tarar.

### Bant Genişliği

Subscriber `ws://127.0.0.1:7880` (loopback) üzerinden bağlanır.  
ICE de loopback adayları tercih eder — dış trafik sıfır.  
Yüzlerce viewer'dan bağımsız: recorder tek sabit subscriber.

### Python Paket Gereksinimleri

```
livekit==1.1.20     # rtc SDK (Rust tabanlı, livekit.rtc modülü)
livekit-api>=1.2.0  # JWT token üretimi
av>=17.0.0          # VP8/Opus encode (PyAV)
numpy>=2.0          # BGRA frame buffer işleme
```

Kurulum: `sudo bash deploy/scale/V2.1/node5/setup/setup_recorder.sh`  
(Script tüm recording node'ları için geçerlidir: node3, node4, node5)

### Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py` | livekit-rtc kayıt script (VP8+Opus MKV) |
| `deploy/scale/V2.1/teqlif-agent/modules/recorder.py` | Subprocess yönetimi, DB tracking, job_health |
| `deploy/scale/V2.1/cluster.yaml` | `livekit_ws_url`, MinIO staging port düzeltmesi (9000→9100) |
| `backend/alembic/versions/zzzzzn_recording_egress.py` | `egress_id TEXT` kolonu (ileride kullanım için) |
| `deploy/scale/V2.1/node5/setup/setup_recorder.sh` | livekit + numpy + av kurulum scripti (tüm node'lar) |

### Çalıştığı Node'lar

`cluster.yaml`'da `recording.services` altında tanımlı servis adı ile çalışan agent node'ları:

| Servis | Node | WS URL |
|--------|------|--------|
| `teqlif-livekit` | node3, node4 | `ws://127.0.0.1:7880` |
| `teqlif-livekit-staging` | node5 | `ws://127.0.0.1:7890` |

### Video PTS Kaynağı — Server-Side Monotonic Clock

**Commit:** `<sonraki commit>`  
**Sorun:** Video PTS, `event.timestamp_us` (gönderenin RTP saatinden türetilen telefon tarafı timestamp) ile hesaplanıyordu. Telefon RTP saati 90 kHz'de çalışır; microsaniyeye dönüştürme sırasında sender clock drift'i veya livekit-rtc'nin sistematik sapması PTS değerlerini sıkıştırarak kaydın gerçek zamandan daha kısa sürede oynatılmasına neden oluyordu.

**Karar:** PTS her zaman `time.monotonic()` (server-side duvar saati, microsaniye) ile hesaplanır.

```python
# livekit_subscriber.py — _record_video
ts_us = int(time.monotonic() * 1_000_000)
```

`event.timestamp_us` artık kullanılmaz. Server monotonic clock, network burst veya kısa kesinti ardından toplu gelen frame'lerde küçük PTS sıkışması yaratabilir; ancak kayıt doğruluğu (gerçek zamana yakın süre) için sender clock bağımsızlığı daha kritiktir.

---

## 20. HostStream MVVM Refactor + ICE Retry

**Commit:** `bc6998ff` — Ekim 2026

### Problem

`host_stream_screen.dart` "Fat View" anti-pattern'ına düşmüştü:  
- 12+ field (`Room`, `LocalVideoTrack`, `ConnectionQuality`, hata state'i, mic/kamera durumu) doğrudan View'da tutuluyordu.  
- Tek bir transient ICE timeout (örn. stream 417), `cancelStream()` → `delete_livekit_room` → "Yayına bağlanılamadı" zincirini tetikliyordu.  
- `_connect()`, `_reconnect()`, `_scheduleReconnect()`, `_handleHostBackground()` gibi iş mantığı metodları View'da yaşıyordu.

### Karar

`HostStreamViewModel extends ChangeNotifier` oluşturuldu (`ChangeNotifierProvider.autoDispose`).  
View'da yalnızca gerçek UI state kaldı: `_wasBackgrounded`, thumbnail timer, zoom.

**Navigation callback pattern:** ViewModel `BuildContext` tutmaz; View `initState`'te  
`_vm.onNavigateToReport` / `_vm.onNavigateHome` set eder (bkz. §8).

**3-retry ICE connect:** `connect()` içinde `_kMaxInitialConnectAttempts = 3` döngüsü;  
- Attempt 1: anında  
- Attempt 2: 1s gecikme  
- Attempt 3: 2s gecikme  
- `_ConfirmLiveFailure` sentinel: `confirmLive()` başarısızlığını ICE hatasından ayırır, retry yapılmaz.  
- Tüm denemeler başarısızsa → `cancelStream()` + `loc.tOr('streamConnectFailed', ...)` error state.

**Exponential backoff reconnect:** 2,4,8,16,30,30,30s (~120s toplam), tamamen ViewModel'de.

### Kural

- Yeni canlı yayın özellikleri `HostStreamViewModel`'e eklenir; View sadece `ref.watch` ile tüketir.  
- `_attemptConnect()` her başarısızlıkta Room'u temizler (disconnect) ve tekrar throw eder — bağlantı state'i tutarsız kalmaz.  
- `ChangeNotifierProvider.autoDispose` sayesinde ekran pop edilince Room ve listener otomatik dispose olur.

### Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `mobile/lib/screens/live/host_stream_screen.dart` | 12 field → ViewModel; `_connect`, `_reconnect`, `_scheduleReconnect`, `_waitForTrack` silindi |
| `mobile/lib/screens/live/viewmodels/host_stream_view_model.dart` | `ChangeNotifier` tam yeniden yazım; 3-retry + exponential backoff |
| `mobile/lib/widgets/direct_sale_panel.dart` | 2-adım satın alma onayı ("Onayla" dialog) + analytics event |

---

## 21. Backup Sistemi Sertleştirmesi (P0/P1/P2)

**Commit:** `3e6fff2d` (P0), `69d558db` (P1/P2)  
**Tarih:** 2026-10-13  
**Analiz:** `documents/backup/V1.0/01_findings.md`

### Sorunlar ve Düzeltmeler

| Öncelik | Bileşen | Sorun | Düzeltme |
|---|---|---|---|
| P0 | `mail_backup.sh` | `trap` yok — `tar` başarısız olunca mail servisi kapalı kalır | `trap 'sudo systemctl start stalwart-mail' EXIT` |
| P0 | `clickhouse_backup.sh` | `cmd \|\| cmd \|\| subshell` zinciri her durumda exit 0 — watchdog yanlış pozitif | `if/elif/else` yapısı; fallback `exit 2` ile çıkar, HSET önceden yazılır |
| P0 | Tüm 9 backup servisi | `OnFailure=` yok — hata ~25 saate kadar sessiz kalır | `teqlif-backup-failed@.service` template + Telegram notification |
| P0 | `teqlif-clickhouse-backup.*` | `resources/systemd/` altında (yanlış dizin), `WantedBy=multi-user.target` | `node2/systemd/` taşındı, `WantedBy=timers.target` |
| P1 | `pg_dump.sh` | Dump doğrudan `$DEST`'e — yarım dump geçerli backup gibi görünür | `${DEST}.tmp` → `pg_restore --list` → `mv` |
| P1 | `minio_backup.sh` | Retry yok — WireGuard kopukluğu job'ı öldürür | 3x retry, 120s backoff |
| P1 | `health.py` | `clickhouse_backup` ve `pg_basebackup` Katman B'de izlenmiyor | `_BACKUP_MAX_MIN` + `_backup_ages` + `blabel` güncellendi |
| P2 | `redis_backup.sh` | `sleep 5` — yoğun I/O'da eski RDB kopyalanabilir | `rdb_bgsave_in_progress` polling (maks 60s) |
| P2 | `schedule.yaml` | `mail_backup` 03:45, `minio_backup` 04:00 — timer gerçeğiyle uyuşmuyor | 06:15 ve 05:30 olarak güncellendi |
| P2 | `teqlif-pg-basebackup.timer` | Description "02:00 UTC" kalıntısı | "08:30 UTC" düzeltildi |

### Bildirim Mimarisi

`teqlif-backup-failed@.service`: systemd `OnFailure=` tetiklenince `notify_backup_failed.sh` çalışır. Script `.env.backup`'tan `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` okur, journalctl son 5 satırıyla Telegram mesajı gönderir. Watchdog (Katman A) + filesystem yaşı (Katman B) + anlık OnFailure bildirim (Katman C) — 3 bağımsız izleme katmanı.

---

## 22. Cache V1.1 — Feed Entity Store ve ID-List Mimarisi

**Commit:** `2e974c21` (S7), `d3bf5728` (S2), `fb711758` (S4), `aeb12557` (S6)  
**Tarih:** 2026-10-14  
**Analiz:** `documents/cache/V1.1/01_findings.md`

### Feed Cache Mimarisi

Feed cache'ler artık tam JSON değil, yalnızca ID listesi saklar. Listing verisi `entity_listing_{id}` anahtarıyla `api_cache` Hive box'unda tek kayıtta tutulur.

```
api_cache (Hive)
  entity_listing_42  → { id, title, price, status, ... }   ← tek kaynak
  entity_listing_17  → { ... }

  homeCache (ayrı box)
  home_feed_recent   → [42, 17, 98, ...]                    ← yalnızca ID listesi
```

**Kurallar:**
- `HomeRepository.saveFeed(List)` → her listing'i `CacheService.saveEntity('listing', id, data)` ile yazar, homeCache'e ID listesi saklar
- `HomeRepository.loadCache()` → ID listesini okur, her ID için `CacheService.getEntity('listing', id)` çağırır
- `SearchRepository._appendCache()` → aynı entity store'a yazar
- `entityProvider` Riverpod family → widget'lar entity'yi reaktif okur: `ref.watch(entityProvider(('listing', id)))`
- Bir entity güncellendiğinde tüm feed görünümleri (home, explore, public profile) otomatik tutarlı kalır

### Migration

`CacheService.init()` içinde `_kApiCacheVersion = 2` kontrolü bulunur. Uygulama güncellenince eski tam-JSON `api_cache` içeriği otomatik silinir; `homeCache._kCacheVersion = 3` ile eski ID-list-öncesi homeCache de sıfırlanır. İlk açılışta network fetch tetiklenir, entity store dolar.

### Image Cache (S2)

Tüm `CachedNetworkImage` / `CachedNetworkImageProvider` widget'larında:
- `cacheManager: TeqlifCacheManager()` — 2 günlük disk TTL, maks 300 dosya
- `cacheKey: 'listing_{id}_photo_{i}'` / `'user_{id}_avatar'` / `'stream_{id}_thumb'` — presigned URL rotasyonunda disk hit korunur
- `memCacheWidth` — decode-time boyut ipucu; avatar 88–240px, listing card 144–400px, full screen 800px

### Repository Katmanı (S4 — ADR §8)

ViewModel `http.get()` ve `StorageService.getToken()` çağıramaz. Tüm API çağrıları `HomeRepository` / `SearchRepository` üzerinden geçer. `loadMore()` başarılı yanıtı disk cache'e merge eder (maks 60 ilan).

### Prefetch (S6 — ADR §8)

`PublicProfileViewModel.warmup(username)` fire-and-forget; `_warming` Set guard eş zamanlı in-flight'ı engeller. Feed kartı long-press anında seller profili ön-ısıtılır.

---

## 23. Cache V1.2 — SWR Geçişi ve Repository ADR §22 Uyumu

**Commit:** `b2486884`  
**Tarih:** 2026-10-14  
**Analiz:** `documents/cache/V1.2/01_findings.md`

### SWR (Stale-While-Revalidate) Geçişi

Uygulama genelinde `CacheService.getData()` → `getWithStaleness()` geçişi yapıldı.

| Davranış | getData() (eski) | getWithStaleness() (yeni) |
|----------|-----------------|--------------------------|
| TTL dolmuşsa | `null` → spinner | stale data → hemen göster |
| Arka plan refresh | sadece boş gelince | her zaman |
| Spinner | her TTL dolmasında | ilk açılışta (cache yoksa) |

Etkilenen sayfalar: Mesajlar, Bildirimler, İstekler, Engellenen kullanıcılar, Takip listesi, Bildirim tercihleri, Puanlar, Herkese açık profil, Ana sayfa, Profil, Pro Araçları (Rakip Radar + Talep Trendleri).

### async build() Race Condition Düzeltmesi

`MessagesTabViewModel`, `RequestsTabViewModel` — `async build()` + `Future.microtask(() => load())` kombinasyonu race condition'a yol açıyordu: Riverpod state `AsyncLoading` kalır, microtask `state.hasValue == false` iken ateşlenir, `load()` early-return yapar. **Düzeltme:** `build()` senkron; `StorageService.currentUserIdSync` getter eklendi (JWT sync parse, `_cachedToken`'dan).

### Repository Katmanı — ADR §22 Tam Uyum

V1.1'de yalnızca `HomeRepository` / `SearchRepository` vardı. V1.2'de 5 ViewModel'deki doğrudan `http.get()` + `StorageService.getToken()` çağrıları temizlendi:

| Repository | Kapsam |
|-----------|--------|
| `UserRepository` | Engellenen kullanıcılar, takip listesi, follow toggle |
| `RatingsRepository` | Alınan/verilen puanlar, yanıt, puan gönderme |
| `NotificationPrefsRepository` | Bildirim tercihleri okuma/yazma |
| `ListingService` (genişletildi) | `getMyActiveListings()` — Competitor Radar için |

**Kural (ADR §8 eki):**
- Query: `ApiService.get<T>()` SWR stream — cache → network, ETag/304 destekli
- Mutation: `ApiClient.call()` — token refresh, 429 rate-limit, 5xx retry korumalı
- ViewModel `CacheService`'e doğrudan erişmez; Repository `getCached()` senkron metodu expose eder
- Her mutation başarı durumunda `clearData(key)` ile cache'i invalidate eder

### StreamSubscription Pattern

`build()` senkron kalır; `ApiService.get()` stream'i `StreamSubscription` ile tüketilir. `ref.onDispose(() => _sub?.cancel())` ile disposed notifier hatası ve bellek sızıntısı önlenir. `await for` kullanılmaz — `build()` async yapardı.

### Pro Tools Cache

Competitor Radar (`cache_competitor_radar_listings`, `cache_radar_{id}`, `cache_velocity_{id}`) ve Talep Trendleri (`cache_demand_trends_{cat}_{subcat}`) 30dk TTL ile cache'lenir. Filtre değişiminde ilgili anahtar türetilir; `build()` içinde static `_keyFor()` helper kullanılır (state'e erişim yoktur).

---

## 24. feed:recent ZSET Tutarlılık Kuralları

**Commit:** `41fe789e` (kısmi fallback), `042f38bf` (leak fix), `3654b949` (post-filter supplement — geçici), temiz mimari: bu commit  
**Tarih:** 2026-10-15 → 2026-10-16

### Problem

`feed:recent` Redis ZSET yalnızca `create_listing` / `update_listing` use case'lerinden besleniyordu. `toggle_listing`, `auction_commands` (BIN + accept_bid) ve doğrudan SQL ile eklenen ilanlar ZSET'i güncellemiyordu. Sonuç: ZSET'te `active` olmayan stale entry'ler birikti; `get_mixed_recent_feed` page=0'da sadece 4–6 ilan döndürdü. Kök neden: servis başlangıcında ZSET hiç doldurulmuyordu.

### Karar — Üç Katmanlı Sorumluluk

**1. Startup Warm-up (`sync_feed_cache.py` + `sync_main.py`)** — _yetkili kaynak_  
`ExecStartPre` adımında `sync_main.py` çalışır; bu script `warm_feed_cache()` çağırır. Her seferinde `DEL feed:recent` + `zadd` ile DB'deki tüm `status='active'` ilan ID'lerini (max 2000, score=id) yeniden inşa eder. Stale entry kalmaz, eksik entry oluşmaz.

**2. Real-time Güncellemeler (tüm status-change path'leri)** — _güncel tutar_  
Her status değişimi ZSET'i anında günceller:

| Durum | Çağrılacak |
|-------|-----------|
| `create_listing` → active | `push_to_recent_feed_cache(listing)` |
| `update_listing` → active | `push_to_recent_feed_cache(listing)` |
| `update_listing` → passive/deleted | `remove_from_recent_feed_cache(id)` |
| `toggle_listing` → active (reactivate) | `cache_listing(listing)` + `push_to_recent_feed_cache(listing)` |
| `toggle_listing` → passive | `cleanup_listing_redis(id)` (içinde `remove_from_recent_feed_cache`) |
| `auction BIN / accept_bid` → passive | `remove_from_recent_feed_cache(id)` |
| `delete_listing` | `invalidate_listing(id)` (içinde `remove_from_recent_feed_cache`) |

**Toggle düzeltmesi:** Daha önce reactivating'de `cleanup_listing_redis` çağrılıyordu — bu ZSET'ten çıkarıyordu. Düzeltme: `cache_listing` + `push_to_recent_feed_cache`.

**3. Query Katmanı (`feed_queries.py`)** — _güvenlik ağı_  
`get_mixed_recent_feed` tam `_RECENT_PAGE_SIZE` (20) ID çeker. ZSET boş veya yetersizse DB fallback devreye girer. Buffer veya post-filter supplement **yoktur** — bunlar startup warm-up'ın görevidir.

### Lazy Cache Refill

DB fallback tetiklendiğinde (`feed:recent` eksikse veya yetersizse) bulunan active ID'ler `zadd "feed:recent"` ile ZSET'e eklenir. Startup warm-up'tan sonra bu yol nadiren tetiklenir.

---

## 25. Chat Dump Güvenilirliği — Kayıp Önleme

**Commit:** `14219db0`  
**Tarih:** 2026-10-16  
**Analiz:** `documents/backup/V1.1/01_findings.md`

### Problem

`finalize_stream` içinde `_dump_chat_to_db` hata durumunda `None` dönüyor, `finalize_stream` sonucu kontrol etmiyordu. Step 6'da chat key her koşulda siliniyordu. DB bağlantı hatası veya asyncpg zaman aşımında mesajlar kalıcı olarak kayboluyordu.

### Karar

**1. `dump_chat_to_db(stream_id, db) -> bool`**  
`_` prefix kaldırıldı — worker da çağırıyor. `bool` döner: `True` başarı, `False` hata. Hata durumunda `db.rollback()` + `capture_exception`. Boş chat başarı sayılır.

**2. İdempotency: DELETE + INSERT**  
`stream_chat_messages` tablosunda `id BIGSERIAL` dışında unique constraint yok — `on_conflict_do_nothing` etkisiz. Aynı transaction'da önce `sa_delete`, ardından `pg_insert`. Retry her zaman temiz bir slate'e yazar. Migration gerekmez.

**3. `finalize_stream` step 6 koşullu**  
`dump_ok = await dump_chat_to_db(stream.id, db)`. Chat key yalnızca `dump_ok is True` iken silinir; diğer 8 Redis key etkilenmez. Başarısız dump 24 saatlik TTL boyunca Redis'te kalır.

**4. `retry_failed_chat_dumps_task` (ARQ default worker, her 30 dk)**  
Son 2 saat içinde biten stream'leri DB'den sorgular, Redis'te `chat_key()` varlığını kontrol eder, mevcutsa `dump_chat_to_db` çağırır. 2 saatlik pencere = maksimum 4 retry. `chat_key()` import'u string literal değil — format coupling yok.

**5. Watchdog**  
`_CONTINUOUS_REGISTRY["retry_failed_chat_dumps_task"] = 30`

### Kural

- `dump_chat_to_db` tek sorumluluk: sadece dump yapar, Redis key silmez, stream state değiştirmez.
- Worker Redis key formatına değil `chat_utils.chat_key()` fonksiyonuna bağımlı.

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `backend/app/use_cases/streams/stream_finalizer.py` | `dump_chat_to_db` rename + bool return + DELETE+INSERT + rollback + `capture_exception` |
| `backend/app/worker.py` | `retry_failed_chat_dumps_task` + `WorkerSettings.functions` + cron (30 dk) |
| `deploy/scale/V2.1/teqlif-agent/modules/watchdog.py` | `_CONTINUOUS_REGISTRY` kaydı |

---

## 26. Recording Detail V1.5 — Analitik Sekme Dashboard (commit `c1e66024`, `d2b17e5e`, `65101e02`)

### Problem

`recording_detail_screen.dart` mevcut haliyle (1730 satır, monolitik) yalnızca video oynatıcı ve temel yayın özetini gösteriyordu. Müzayede, satış, hediye ve katılımcı verisi `GET /api/streams/{id}/recording-summary` endpoint'inden zaten geliyordu; ancak UI'da gösterilmiyordu.

### Karar

Backend değişikliği yapılmadan Flutter katmanında 4 sekmeli analitik dashboard oluşturuldu. Monolitik dosya SRP'ye uygun 15+ widget dosyasına bölündü.

### Sekme Yapısı

```
[Özet] [Müzayedeler] [Satış & Hediye] [Katılımcılar]
                                              ↓
                          [Genel] [Teklif] [Alışveriş] [Hediye] [Chat]
```

Dış `TabBarView`: `NeverScrollableScrollPhysics` — iç swipe ile çakışmayı önler.  
İç `TabBarView` (Katılımcılar): `ClampingScrollPhysics` — yatay swipe ile 5 alt sekme arasında geçiş.

### Scrollable Tab Bar + Yanıp Sönen Ok

Her iki tab bar da `isScrollable: true, tabAlignment: TabAlignment.start` ile yapılandırılır. Tab isimleri tam görünür; kesilme olmaz.

Görünür alanın dışında sekme varken sağ kenarda `FadeTransition` + gradient + `Icons.chevron_right_rounded` yanıp söner. Son sekme seçilince kaybolur.

```dart
AnimationController _tabHintPulse = AnimationController(
  vsync: this, duration: const Duration(milliseconds: 700))
  ..repeat(reverse: true);

bool get _hasMoreRight => controller.index < tabs.length - 1;
```

### Fiyat ve Teqliq Formatlama Kuralları

**`rd_formatters.dart`** (`mobile/lib/screens/recording_detail/widgets/`) tüm recording detail bileşenlerinde kullanılan helper dosyasıdır:

```dart
String rdPrice(num amount, String lang)   // → '₺1.234,56'  (locale-aware)
String rdTeqliq(num amount, String lang)  // → '1.234 teqliq'
```

- `toStringAsFixed()` bu ekranda kullanılmaz; her fiyat `rdPrice()`, her teqliq değeri `rdTeqliq()` üzerinden geçer.
- Yazım kuralı: her zaman `teqliq` (küçük harf). `Teqlik`, `TQL`, `Teqliq` kullanılmaz.
- `TeqNumberFormatter.format(amount, locale: rdLocale(lang))` binlik ayraç ve virgül/nokta tercihini locale'ye göre otomatik ayarlar.

### Katılımcı Aggregation (ViewModel Katmanı)

`_buildParticipants(RecordingDetail)` → `List<RecordingParticipantActivity>` ViewModel'da (`recording_detail_view_model.dart`) çalışır. View salt okuma yapar.

Aggregation mantığı: `auctions[].bids`, `directSales[].orders`, `gifts.events`, `chatMessages` → userId bazında haritada biriktirilir → `monetaryTotal` azalana göre sıralanır → `RecordingDetailState.participants` olarak state'e yazılır.

`RecordingParticipantActivity.timeline`: `late final` ile bir kez hesaplanır; her build'de yeniden sıralanmaz (jank önlemi).

### Dosya Yapısı

```
mobile/lib/screens/recording_detail/
  overview_tab.dart
  auctions_tab.dart
  sales_gifts_tab.dart
  participants_tab.dart
  participants/
    overall_sub_tab.dart
    bids_sub_tab.dart
    shopping_sub_tab.dart
    gifts_sub_tab.dart
    chat_sub_tab.dart
  widgets/
    rd_formatters.dart        ← rdPrice / rdTeqliq / rdLocale
    metric_grid.dart
    activity_timeline.dart
    price_curve_painter.dart
    gift_bars_painter.dart
    podium_widget.dart
    stacked_avatars.dart
    participant_card.dart
    modal_sheet.dart
```

### Arama Kutusu (commit `65101e02`)

`AuctionsTab` ve `ParticipantsTab`'a `TeqSearchField` eklendi.

- `AuctionsTab`: ürün adına göre filtreler (`a.itemName.toLowerCase().contains(q)`); sort + search birleşik `_filtered` getter'da.
- `ParticipantsTab`: kullanıcı adına göre filtreler; filtrelenmiş `p` listesi 5 alt tab'ın tamamına (`OverallSubTab`, `BidsSubTab`, `ShoppingSubTab`, `GiftsSubTab`, `ChatSubTab`) geçirilir.
- ARB: `recordingSearchAuctions`, `recordingSearchParticipants` (5 dil).

### Kural

- `rd_formatters.dart` sadece bu ekrana özeldir; global util'e taşınmaz.
- Yeni tab ya da widget eklenirken `loc` (veya `loc.lang`) parametre olarak geçirilir; `context` üzerinden `InheritedWidget` ile çekilmez.
- `GiftBarsChart`, `ParticipantCard` gibi widget'lar `lang` parametresi alır; daha üst seviyede `loc.lang` olarak beslenir.
- Tam plan ve tüm implementasyon detayları: `documents/stream/V1.5/01_findings.md`

---

## 27. teqlif-agent Bug Düzeltmeleri — Healer + Watchdog (commit `afeaf889`)

### Bug A — Healer: Hatalı Servis Adları + `systemctl show` Davranışı

**Problem:**  
`_SERVICES_TO_WATCH` listesinde 6 hatalı unit adı vardı (`teqlif-app`, `teqlif-livekit-sfu`, `redis`, `postgres` vb.).  
`_get_active_state` yalnızca `ActiveState` property'sini okuyordu; ancak `systemctl show` kurulu olmayan servisler için `ActiveState=inactive` döndürür — "not-found" **asla** `ActiveState`'de görünmez.  
Bu nedenle healer tüm bilinmeyen servisleri "bu node'da kurulu değil" sanarak sessizce atlıyordu.

**Düzeltme (`healer.py`):**
- `_SERVICES_TO_WATCH` gerçek systemd unit adlarıyla güncellendi.
- `_get_active_state` artık `--property=LoadState,ActiveState` ile her iki property'yi okur; `LoadState=not-found` kontrolüyle kurulu olmayan servisler atlanır, `ActiveState=inactive` false-negative vermez.

### Bug B — Watchdog: Redis Timestamp Göz Ardı Ediliyordu

**Problem:**  
`_sync_from_redis` Redis'ten `hgetall("teqlif:agent:job_ok")` ile `{job_name: iso_timestamp}` çekiyordu; ancak `mark_ok(job_name, expected_every_m=expected)` çağrısında `ts` iletilmiyordu. `AgentDB.mark_ok` içinde `_now()` kullanıldığından `last_ok_at` her zaman agent'ın okuma anına yazılıyordu; gerçek iş bitim zamanı kayboluyordu.

**Düzeltme (`watchdog.py` + `db.py`):**
- `mark_ok` çağrısına `last_ok_at=ts` eklendi.
- `AgentDB.mark_ok` imzasına `last_ok_at: str | None = None` parametresi eklendi; `ok_time = last_ok_at or now` mantığıyla Redis'ten gelen gerçek zaman kullanılıyor.

### Kural

- `systemctl show` ile servis varlığı sorgularken mutlaka `--property=LoadState,ActiveState` çift çekilmeli; `LoadState=not-found` kontrolü yapılmalıdır.
- ARQ worker'ların yazdığı `HSET teqlif:agent:job_ok <name> <ts>` değerindeki timestamp, agent'a iletilmeli; `_now()` fallback olarak kalır (Redis boş ise).

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/teqlif-agent/modules/healer.py` | `_SERVICES_TO_WATCH` düzeltildi, `_get_active_state` LoadState kontrolü eklendi |
| `deploy/scale/V2.1/teqlif-agent/modules/watchdog.py` | `mark_ok` çağrısına `last_ok_at=ts` eklendi |
| `deploy/scale/V2.1/teqlif-agent/db.py` | `mark_ok` imzasına `last_ok_at: str | None = None` parametresi eklendi |

---

## 28. Healer Polkit + Redis Failover + node2 Monitoring Temizliği (commit `62c29222`)

### Healer Yetki — Polkit Kuralı

**Problem:**
`healer.py` bare `systemctl start/reset-failed` çağırıyor ancak `teqlif-agent` kullanıcısı yetkisiz. Servis dosyasında `NoNewPrivileges=true` olduğundan `sudo` da çalışmıyor. Sudoers kuralı yazılmıştı ama kod hiç `sudo` çağırmıyordu — kural kullanılmıyordu. Ayrıca `postgresql@17-main`, `clickhouse-server`, `haproxy`, `stalwart-mail` sudoers kapsamı dışındaydı.

**Karar:**
`sudo` yerine Polkit kuralı. `systemctl` D-Bus üzerinden polkit'e başvurur; `NoNewPrivileges=true` bunu engellemez. Kod değişmeden (bare `systemctl`) çalışır.

`setup_node.sh` artık `/etc/polkit-1/rules.d/50-teqlif-agent.rules` oluşturuyor:
- Kapsam: `teqlif-*`, `postgresql@17-main.service`, `clickhouse-server.service`, `haproxy.service`, `stalwart-mail.service`, `livekit-*`
- Eylemler: `manage-units`, `reload-or-restart-unit`

### Redis Failover

**Problem:** Dokümantasyonda "redis-failover.timer her 10s çalışır" yazıyordu ama dosya hiç yoktu.

**Implementasyon (`node2/resources/scripts/redis_failover.sh`):**
- Her 10s `10.10.0.1:6379`'a PING atar
- 3 ardışık başarısızlık → `REPLICAOF NO ONE` (promote)
- `promoted_flag` dosyası çift-promote'u önler
- Telegram bildirimi gönderir
- Failback: `REPLICAOF 10.10.0.1 6379` + flag sil

**Timer:** `OnActiveSec=30`, `OnUnitActiveSec=10s`, `AccuracySec=1s`

### node2 Monitoring Temizliği

`bootstrap_node2.sh`'dan Prometheus/Grafana/Loki/Alertmanager kurulumu kaldırıldı.
Canonical monitoring host: **nodeMonitor (10.10.0.99)**. node2'de sadece Promtail + node_exporter kalır (veri gönderici rol).

### Kural

- `teqlif-agent` kullanıcısına systemd yetkisi her zaman polkit ile verilir, sudoers ile değil.
- `NoNewPrivileges=true` servislerde `sudo` çalışmaz; polkit ve D-Bus çalışır.
- Her node'da monitoring stack çalıştırılmaz — sadece Promtail + node_exporter (veri toplama).

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/teqlif-agent/setup/setup_node.sh` | Sudoers → polkit kuralı |
| `deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh` | Yeni — failover scripti |
| `deploy/scale/V2.1/node2/systemd/teqlif-redis-failover.service` | Yeni |
| `deploy/scale/V2.1/node2/systemd/teqlif-redis-failover.timer` | Yeni — 10s interval |
| `deploy/scale/V2.1/scripts/bootstrap_node2.sh` | Monitoring stack kaldırıldı, redis_failover eklendi |

---

## 29. Stream Recording V1.6 — Dinamik Encode Parallelism (commit `14e8bd1b`, `847d991a`)

### Sorun

`EncoderManager._MAX_PARALLEL = 1` sabitti. Bakım penceresinde sıra birikiyordu; aktif yayın olmadığında CPU boşta bekletiliyordu. Ayrıca aktif kayıt durumu her 60 saniyede PostgreSQL'e TCP sorgusu atılarak öğreniliyordu.

### Karar

**`_resolve_max_parallel(rec_cfg, svc_cfg)`** metodu eklendi (`847d991a`: `encoded_dir` `svc_cfg`'den alınır — cluster.yaml'de servis konfigürasyonu altında tanımlı):

| Durum | N |
|-------|---|
| Aktif kayıt var (`len(recording_procs) > 0`) | 1 |
| Disk acil (`< disk_emergency_gb`) | 4 |
| Bakım penceresi (`transfer_window_start_utc` – `transfer_window_end_utc`) | 4 |
| Normal atıl | 2 |

**PostgreSQL anti-pattern kaldırıldı:** `RecordingManager._procs` sözlüğünün referansı `agent.py`'de dependency injection ile `EncoderManager`'a geçirildi. Aktif kayıt sayısı `len(self._recording_procs)` ile sıfır ağ gecikmesiyle okunuyor.

**`nice -n 19`:** FFmpeg komutu `["nice", "-n", "19", "ffmpeg", ...]` biçimine getirildi. N=1 senaryosunda Linux scheduler encoding'i LiveKit SFU'nun arkasına iterek CPU rekabetini engeller.

### Disk Emergency Önceliği

Aktif kayıt kontrolü disk emergency kontrolünden önce gelir. Aktif yayın varken disk acilse N=1 korunur — N=4 VP8 subscriber'ın CPU'sunu çalar ve kaydı bozar. Yayın bittikten sonra bir sonraki döngüde N=4 tetiklenir.

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/teqlif-agent/modules/encoder.py` | `_MAX_PARALLEL` kaldırıldı, `_resolve_max_parallel` + `nice -n 19` eklendi |
| `deploy/scale/V2.1/teqlif-agent/agent.py` | `recording_procs=rec_mgr._procs` dependency injection |
| `documents/stream/V1.6/01_findings.md` | Mimari analiz belgesi oluşturuldu |

---

## 30. teqlif-agent İzleme Düzeltmeleri — Redis/Backup/Cleaner/PG Replikasyon (commit `daa72d2b`, `dd206266`, `28836f45`, `9c6ecf18`, `ef2dcadc`)

### 1. Redis Servis Adı Yanlışlığı — `health.py` (`daa72d2b`)

**Problem:** `_ALL_SERVICES` listesinde `"redis-server"` ve `"livekit"` vardı. Ubuntu paketi `/lib/systemd/system/redis-server.service` dosyası tüm node'larda mevcut (inactive/disabled) olduğundan health check her node'da "Redis çöktü" false alarmı üretiyordu.

**Karar:** Doğru servis adları rol bazında ayrıştırıldı:
- `"teqlif-redis-core"` → node1
- `"teqlif-redis-replica"` → node2
- `"teqlif-redis-staging"` → node5
- `"teqlif-livekit"` → node3/node4

**Kural:** Systemd servis adı her zaman `/etc/systemd/system/<ad>.service` dosyasının base adıdır; Ubuntu paket kurulumunun `/lib/systemd/system/` altında bıraktığı dosya adı değil.

### 2. ScheduledCleaner "permission denied" — `zzzzzt_agent_select_grant` (`dd206266`)

**Problem:** `DELETE FROM table WHERE col = val` sorgusu `SELECT` yetkisi olmadan çalışmaz. PostgreSQL, `WHERE` koşulundaki kolon değerlerine erişmek için `SELECT` ister (docs: "SELECT privilege is also needed to reference existing column values in UPDATE, DELETE, or MERGE"). 10 tablo için `DELETE` grant'ı vardı, `SELECT` yoktu.

**Karar:** `zzzzzt_agent_select_grant` migration: `GRANT SELECT ON {10 tablo} TO teqlif_agent`.

**Kural:** `teqlif_agent`'a `DELETE` grant verirken aynı tablo için `SELECT` da verilmelidir.

### 3. `pg:replication` False Alarm — `certs.py` (`28836f45`)

**Problem:** `pg_stat_replication` view'ı `teqlif_agent` kullanıcısı için (pg_monitor üyesi olsa da) doğrudan bağlantıda boş dönüyor. Replication çalışmasına rağmen "aktif replica yok" alarmı 6 saatte bir tetikleniyordu.

**Karar:** `pg_stat_replication` boş dönünce çapraz doğrulama: `pg_stat_activity WHERE backend_type = 'walsender'` > 0 ise alarm verilmez.

**Kural:** PostgreSQL 17'de `pg_stat_replication` bazı bağlantı rollerinde boş dönebilir; WAL sender varlığını `pg_stat_activity` ile doğrula.

### 4. Backup Yaşı False Alarmları — Sentinel Dosyaları (`9c6ecf18`)

**Problem:** `rsync -a` kaynak dosya mtime'ını korur. Boş MinIO bucket'ta `mc mirror` hiç dosya yazmaz. Health check dizindeki en yeni dosyanın mtime'ını ölçüyordu — her ikisinde de gerçek backup zamanını yansıtmıyordu.

**Karar:** Her backup script başarı sonrası `touch "${BACKUP_DIR}/.last_backup_ok"` çalıştırır. Health check bu sentinel dosyanın mtime'ını okur — dizin taraması yerine.

**Etkilenen scriptler:** `minio_backup.sh`, `uptime_kuma_backup.sh`, `nodemonitor_config_backup.sh`  
**health.py:** `minio_backup` `backup_dirs`'tan `sentinel_dirs`'e taşındı; `elif p.is_dir()` bloğu kaldırıldı.

**Kural:** Backup sağlığı her zaman sentinel dosya mtime'ı ile ölçülür; rsync/mirror çalıştıktan sonra `touch .last_backup_ok` zorunludur.

### 5. `teqlif-restart` Agent Sync — Git Hash Bazlı (`ef2dcadc`)

**Problem:** `rsync --checksum` (rsync 3.5.0) double-pull korumasında (`BEFORE==AFTER` senaryosu) farklı dosyaları tespit edemiyordu — agent kodu değişse bile sync atlandı.

**Karar:** Deploy sonrası `echo "$AFTER" > "$agent_dst/.git_hash"` yazılır. Double-pull protection `rsync --checksum` yerine bu hash'i HEAD ile karşılaştırır.

**Kural:** rsync version'a bağımlı checksum yerine git hash dosyası güvenilir deploy marker'dır.

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/teqlif-agent/modules/health.py` | Redis servis adları düzeltildi; minio_backup sentinel'e taşındı; `elif p.is_dir()` bloğu kaldırıldı |
| `deploy/scale/V2.1/teqlif-agent/modules/certs.py` | pg:replication WAL sender çapraz doğrulama |
| `deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh` | `touch .last_backup_ok` eklendi |
| `deploy/scale/V2.1/node2/resources/scripts/uptime_kuma_backup.sh` | `touch .last_backup_ok` eklendi |
| `deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh` | `touch .last_backup_ok` eklendi |
| `deploy/scale/V2.1/scripts/teqlif-restart.sh` | Double-pull protection git hash bazlı; self-update bloğu eklendi |
| `backend/alembic/versions/zzzzzt_agent_select_grant.py` | GRANT SELECT ON 10 tablo TO teqlif_agent |

---

## 31. MinIO ILM Acil Freni + Off-site Sync Altyapısı

### Sorun

Mimari analizi 3 kritik risk ortaya çıkardı:
1. MinIO ILM (2 gün) ile minio_backup 3×retry arasındaki race condition: 2 ardışık başarısız backup → veri kalıcı kayıp
2. Off-site backup yok: tüm veriler tek fiziksel lokasyon (node2, Saarbrücken)
3. Pazar ML bloku + pg_basebackup çakışma riski (>50K kullanıcı eşiğinde)

### Karar

**MinIO ILM retention 2→4 gün:** `mc ilm edit --id db3tiuskndq8as06c0e0 --expiry-days 4 node1minio/teqlif`. 4 günlük buffer; 3×retry günlük → ardışık 3 başarısız gün bile ILM'in önünde kalır.

**ILM acil freni (`minio_backup.sh`):** Bucket mirror başarısız → `mc ilm edit --expiry-days 7` (acil, 7 gün). Başarılı → `mc ilm edit --expiry-days 4` (normal). `set -euo pipefail` yerine bucket başarıları ayrı izleniyor (`teqlif_ok`, `teqlif_dm_ok`).

**Off-site sync altyapısı hazırlandı:** `offsite_sync.sh` artık gerçek bir rclone template içeriyor. Aktif etmek için `.env.backup`'a `RCLONE_REMOTE` ve `RCLONE_BUCKET` eklemek ve timer'ı enable etmek yeterli. Timer hâlâ disabled — hedef belirlenince enable edilmeli. Önerilen: Hetzner Storage Box veya Backblaze B2, rclone crypt remote ile şifreli.

**Pazar ML süre riski belgelendi:** `schedule.yaml`'a uyarı eklendi. Şu anki `watchdog_m` yalnızca "hiç çalışmadı mı?" sorusunu yanıtlar; süre aşımını yakalamaz. >50K kullanıcıda `max_duration_m` alanı + Redis task_start/end key'leri ile agent alarm verebilmeli.

### Kural

- MinIO ILM ID değişirse `minio_backup.sh`'daki `MINIO_ILM_ID` ve node1'deki ILM kuralı senkron tutulmalıdır.
- Off-site sync için her zaman rclone crypt remote kullanılır — şifresiz bulut transferi yapılmaz.
- `teqlif-offsite-sync.timer` enable edilmeden önce `rclone lsd <REMOTE>:<BUCKET>` ile erişim doğrulanmalıdır.

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh` | ILM acil freni: başarısızlıkta 7g, başarıda 4g; bucket başarı ayrı izleniyor |
| `deploy/scale/V2.1/node2/resources/scripts/offsite_sync.sh` | Boş stub → rclone template; RCLONE_REMOTE/BUCKET env desteği |
| `deploy/scale/V2.1/schedule.yaml` | Pazar ML ölçek riski notu eklendi |
| MinIO node1 (canlı) | `teqlif/recordings/` ILM retention 2→4 gün (`db3tiuskndq8as06c0e0`) |

### Açık Görevler

- [ ] Off-site hedef seç (Hetzner/B2) ve `RCLONE_REMOTE`, `RCLONE_BUCKET` `.env.backup`'a ekle
- [ ] `teqlif-offsite-sync.timer`'ı enable et
- [ ] >50K kullanıcıda ML task süre izleme: `max_duration_m` + Redis key'ler

---

## §32 — Çapraz Denetim Düzeltmeleri: Yedekleme, İzleme ve Servis Konfigürasyonu

**Commit:** `f3c82ca5` | **Tarih:** Ekim 2026

### Problem

Çapraz denetim taraması 9 kritik hata/tutarsızlık tespit etti; büyük çoğunluğu sessiz çöküş üretiyor ve sıfır alarm veriyor.

### Yapılan Değişiklikler

**`mail_backup.sh` — sentinel yol hatası:**
`touch "${BACKUP_DIR}/../.last_mail_backup_ok"` → `touch "${BACKUP_DIR}/.last_mail_backup_ok"`.
Fazladan `/../` bir üst dizine yazıyordu; health.py `stalwart/` altındaki dosyayı arıyordu → yalancı alarm.

**`clickhouse_backup.sh` — veritabanı adı uyuşmazlığı:**
Script `teqlif_analytics` adını kullanıyordu; gerçek DB `teqlif_prod_analytics`. Tüm üç yerde (`--tables`, `BACKUP DATABASE`, `FROM`) düzeltildi. Bu hata etkin olduğu süre boyunca ClickHouse yedekleri sıfır tablo ile sessizce başarısız sayılıyordu.

**`uptime_kuma_backup.sh` — SQLite → MariaDB dump:**
Uptime Kuma `kuma.db` (SQLite) değil, MariaDB kullanıyor (`DATABASE=mariadb`). Script `rsync kuma.db` yerine `MYSQL_PWD` env ile SSH üzerinden `mysqldump` çalıştıracak şekilde yeniden yazıldı. `UPTIME_KUMA_DB_PASS` `.env.backup`'a eklenmeli (bkz. `secrets.env.template`). Arşiv uzantısı `.db.gz` → `.sql.gz`.

**`certs.py` — LiveKit domain tutarsızlığı:**
İzleme `live1/live2.teqlif.com` kontrol ediyordu; gerçek prod domainler `stream3/stream4.teqlif.com`. stream3/stream4 sertifikası expire olsa alarm gelmiyordu.

**`livekit-staging.yaml` — yanlış Redis şifresi:**
`<core_redis_pass>` → `<staging_redis_pass>`. Node5 staging Redis kendi `staging_redis_pass` ile korumalı; core pass ile WRONGPASS hatası alırdı.

**`teqlif-staging.service` — WireGuard boot race condition:**
`After=network.target` → `After=network.target wg-quick@wg0.service`. Uvicorn `10.10.0.5` (WireGuard IP) dinliyor; tünel hazır olmadan uvicorn "Cannot assign requested address" ile çökebilir.

**`clickhouse/users.d/teqlif.xml` — grant DB adı:**
Bootstrap kılavuzundaki SQL şablonu `teqlif_analytics.*` grant içeriyordu; `teqlif_prod_analytics.*` olarak güncellendi. Eski şablon ile kurulumda Access Denied alınırdı.

**`nodemonitor_config_backup.sh` — Prometheus/Loki data hariç tutma:**
`/opt/monitor/teqlif/` tüm ağacı rsync ediliyordu. Prometheus TSDB (`prometheus/data/`, 30 günlük) ve Loki chunk/compactor dizinleri (`loki/data/`) `--exclude` ile kapsam dışına alındı. Config dosyaları (`.yml`, `.ini`) zaten git repo'sunda sürüm kontrolünde.

**`backend/app/config.py` — MinIO endpoint varsayılanı:**
`http://10.10.0.8:9000` (V2.0 mirası) → `http://10.10.0.1:9000` (V2.1 node1). `.env.production` override ederdi ama varsayılan doğru değil, yeni kurulumda hata kaynağı olabilirdi.

### Kural

- Backup script'lerinde `touch sentinel` her zaman backup dosyasının yazıldığı dizinde yapılır; `/../` veya başka göreli sıçramalar kullanılmaz.
- ClickHouse DB adı `teqlif_prod_analytics` — backup script, grant şablonu ve backend config senkron tutulmalıdır.
- MariaDB/MySQL backup'ı şifreyi komut satırına değil `MYSQL_PWD` ortam değişkenine koyar (ps gizleme).
- Systemd servis `--host <WireGuard-IP>` dinliyorsa mutlaka `After=wg-quick@wg0.service` içermelidir.
- `nodemonitor_config_backup.sh` kapsam kuralı: runtime secrets ve Grafana state → evet; Prometheus TSDB / Loki chunks → hayır (loki_backup ile yönetilmeli).

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/node2/resources/scripts/mail_backup.sh` | Sentinel yol: `/../` kaldırıldı |
| `deploy/scale/V2.1/node2/resources/scripts/clickhouse_backup.sh` | DB adı `teqlif_analytics` → `teqlif_prod_analytics` (3 yerde) |
| `deploy/scale/V2.1/node2/resources/scripts/uptime_kuma_backup.sh` | SQLite rsync → mysqldump (MariaDB) |
| `deploy/scale/V2.1/node2/resources/scripts/nodemonitor_config_backup.sh` | `--exclude prometheus/data/ loki/data/` eklendi |
| `deploy/scale/V2.1/node2/resources/clickhouse/users.d/teqlif.xml` | Grant DB adı düzeltildi |
| `deploy/scale/V2.1/teqlif-agent/modules/certs.py` | LiveKit domain: live1/live2 → stream3/stream4 |
| `deploy/scale/V2.1/node5/resources/livekit/livekit-staging.yaml` | Redis password: core → staging |
| `deploy/scale/V2.1/node5/systemd/teqlif-staging.service` | `After=wg-quick@wg0.service` eklendi |
| `deploy/scale/V2.1/secrets.env.template` | `uptime_kuma_db_pass` değişkeni eklendi |
| `backend/app/config.py` | MinIO default endpoint 10.10.0.8 → 10.10.0.1 |

### Açık Görevler

- [x] nodeMonitor'da `UPTIME_KUMA_DB_PASS` değerini al ve node2 `.env.backup`'a ekle ✅
- [ ] node5'te `teqlif-staging-livekit.service` varsa `apply_secrets` ile `livekit-staging.yaml` yeniden uygula

---

## §33 — ClickHouse Veritabanı Yeniden Adlandırma

**Tarih:** Ekim 2026

### Problem

`teqlif_analytics` adı prod/staging ayrımını yansıtmıyordu; `teqlif_analytics_staging` ile simetri eksikti. `config.py` varsayılanı `teqlif_prod_analytics` yazıyordu ama gerçek DB `teqlif_analytics`'ti — isim tutarsızlığı.

### Yapılan Değişiklikler

ClickHouse'da `RENAME DATABASE` komutu olmadığından tablo bazlı atomik migration uygulandı:

```sql
-- Prod
CREATE DATABASE IF NOT EXISTS teqlif_prod_analytics;
RENAME TABLE teqlif_analytics.* TO teqlif_prod_analytics.*;  -- 5 tablo, atomik
DROP DATABASE teqlif_analytics;

-- Staging
CREATE DATABASE IF NOT EXISTS teqlif_prod_analytics_staging;
RENAME TABLE teqlif_analytics_staging.* TO teqlif_prod_analytics_staging.*;
DROP DATABASE teqlif_analytics_staging;
```

Migration sırasında prod ve staging servisleri kısa süre durduruldu (aktif kullanıcı yok).

Env dosyaları yerinde güncellendi:
- node1: `CLICKHOUSE_DB=teqlif_prod_analytics`
- node5: `CLICKHOUSE_DB=teqlif_prod_analytics_staging`

### Kural

- ClickHouse DB adlandırma: `teqlif_prod_analytics` (prod) / `teqlif_prod_analytics_staging` (staging)
- `RENAME TABLE` yöntemi tercih edilir (atomik, veri kopyası gerektirmez)
- Yeni tablo migration'larında her iki DB'ye aynı anda uygulanmalı

### Etkilenen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `deploy/scale/V2.1/node2/resources/scripts/clickhouse_backup.sh` | `teqlif_prod_analytics` (§32'de yapılmıştı, şimdi doğru DB'ye karşılık geliyor) |
| `deploy/scale/V2.1/node2/resources/clickhouse/users.d/teqlif.xml` | Grant şablonu `teqlif_prod_analytics.*` |
| `backend/app/config.py` | `clickhouse_db` varsayılanı `teqlif_prod_analytics` |
| node1 `.env.production` (git dışı) | `CLICKHOUSE_DB=teqlif_prod_analytics` |
| node5 `.env.staging` (git dışı) | `CLICKHOUSE_DB=teqlif_prod_analytics_staging` |

