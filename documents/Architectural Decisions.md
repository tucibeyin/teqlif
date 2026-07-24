# Architectural Decisions

Bu dosya, teqlif'teki büyük mimari kararları ve uygulama pattern'lerini tutar.  
**Yeni bir ekranı refactor ederken bu dosyaya bak — her karar burada, neden sorusuyla birlikte.**

**Pilot ekran:** `create_listing_screen.dart` (tüm pattern'lar burada uygulandı, referans al)  
**Son güncelleme:** Temmuz 2026

---

## İçindekiler

1. [OTA Localization](#1-ota-localization)
2. [Merkezi Error Handling](#2-merkezi-error-handling)
3. [Deploy Pipeline](#3-deploy-pipeline)
4. [Ekran Migration Checklist](#4-ekran-migration-checklist)

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

### 1.6 OTA Çeviri Güncelleme Akışı

Çeviriyi değiştirmek için:
1. ARB dosyasında güncelle (TR, EN, AR, RU)
2. Commit + push
3. VPS'te deploy: `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`
4. Bitti — kullanıcılar bir sonraki uygulama açılışında yeni çeviriyi görür

> ⚠️ DB'ye direkt SQL yazmak **artık yasak** — her zaman ARB → deploy pipeline üzerinden git.

---

## 2. Merkezi Error Handling

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

## 3. Deploy Pipeline

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

## 4. Ekran Migration Checklist

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

### 4.3 Son Kontroller

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
