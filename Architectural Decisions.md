# Architectural Decisions

Bu dosya, codebase'deki büyük mimari kararları ve "neden" sorusunun cevaplarını tutar.
Yeni bir ekranı migrate ederken veya pattern'in nasıl çalıştığını hatırlamak istediğinde buraya bak.

---

## OTA Localization (Over-The-Air Çeviri Sistemi)

**Pilot ekran:** İlan Ver (`create_listing_screen.dart`)  
**Tamamlandı:** Temmuz 2026

### Problem

Flutter'ın yerleşik ARB/AppLocalizations sistemi, çevirileri **derleme zamanında** uygulamaya gömer.
Bir çeviriyi düzeltmek için yeni bir App Store güncellemesi yayınlamak gerekiyordu.

### Karar

Çevirileri DB'de tut, API'den serve et, client'lar kendi cache'lerinde saklasın.
Uygulama güncellemesi olmadan çeviriler anında değiştirilebilir.

---

### Mimari (Katman Katman)

```
DB: translations(key, lang, value)
           ↓
GET /api/i18n/{lang}          — Backend, Redis cache (1h TTL)
           ↓
LocalizationService            — Flutter, Hive cache (24h stale check)
           ↓
TranslationPack.t('key')       — Widget rebuild tetikler
```

---

### 1. Veritabanı: `translations` Tablosu

```sql
CREATE TABLE translations (
    key  VARCHAR(200) NOT NULL,
    lang VARCHAR(10)  NOT NULL,
    value TEXT        NOT NULL,
    PRIMARY KEY (key, lang)
);
CREATE INDEX ix_translations_lang ON translations (lang);
```

**Neden bu şema?**
- `PRIMARY KEY (key, lang)` — aynı key'in birden fazla dile girişini engeller, upsert yapmayı kolaylaştırır.
- `lang` index'i — `WHERE lang = 'tr'` sorgusu tüm paketi tek geçişte çeker.

**Seed kaynağı:**
- Mevcut 4 ARB dosyasından ~1775 key × 4 dil = 7096 satır migration'a Python dict olarak gömüldü.
- `opt_*` key'leri (renkler, yakıt, vites, hasar vb.) ARB'de olmadığından ayrıca `_OPT_DATA` olarak eklendi.

**Key namespace'leri:**

| Prefix | Örnek | Kullanım |
|--------|-------|----------|
| *(prefix yok)* | `acceptRequest` | ARB'den gelen orijinal key'ler |
| `subcat_` | `subcat_automobile` | Alt kategori isimleri |
| `opt_` | `opt_white`, `opt_gasoline` | Field option label'ları |
| `extraField_` | `extraField_brand` | Extra field label'ları |

---

### 2. Backend API

**Dosya:** `backend/app/routers/i18n.py`

```
GET /api/i18n/{lang}          → { "acceptRequest": "Onayla", ... }
GET /api/i18n/{lang}/version  → { "version": "md5hash" }
```

- Geçersiz `lang` → HTTP 400.
- Desteklenen diller: `tr`, `en`, `ar`, `ru`.
- Redis cache: `i18n:{lang}` — TTL 3600s. Çeviri güncellenince `redis-cli DEL i18n:{lang} i18n:{lang}:version` yeterli.

---

### 3. Flutter: `LocalizationService`

**Dosya:** `mobile/lib/services/localization_service.dart`

```dart
// Provider — her yerde ref.watch(localizationProvider) ile erişilir
final localizationProvider =
    StateNotifierProvider<LocalizationService, TranslationPack>(...);
```

**`TranslationPack` — iki metod, hepsi bu:**

```dart
// Basit string
loc.t('fieldCategory')

// Parametre interpolasyonu  {param} → değer
loc.t('tuciSpent', {'count': n.toString()})

// Key yoksa fallback döner (brand/model isimleri için)
loc.tOr('opt_bmw', 'BMW')
```

**Cache katmanları:**
1. Hive `i18n_cache` box'ı — açılışta anında yüklenir.
2. 24h stale check — arka planda `/version` endpoint'i ile MD5 karşılaştırır, farklıysa yeniden çeker.
3. Dil değişiminde otomatik yükleme — `ref.listen(localeProvider, ...)` tetikler.

**Init:** `main.dart`'ta `CacheService.init()` hemen ardından:
```dart
await LocalizationService.initBox();
```

---

### 4. Widget Dönüşümü (Pattern)

Bir ekranı OTA'ya migrate etmek için yapılacaklar:

**a) Sınıf dönüşümü:**
```dart
// Önce
class MyScreen extends StatefulWidget { ... }
class _MyScreenState extends State<MyScreen> { ... }

// Sonra
class MyScreen extends ConsumerStatefulWidget { ... }
class _MyScreenState extends ConsumerState<MyScreen> { ... }
```

**b) `build()` içinde `loc`'u al:**
```dart
final loc = ref.watch(localizationProvider); // reaktif — dil değişince rebuild
```

**c) Async metodlarda:**
```dart
final loc = ref.read(localizationProvider); // snapshot — rebuild tetiklemez
```

**d) İç `StatelessWidget`'lar için:**
```dart
class _MyInnerWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    ...
  }
}
```

**e) Kaldırılacaklar:**
- `import '...app_localizations.dart'` — sil
- `import '...field_labels.dart'` — sil (subcatLabel helper artık gerek yok)
- `final l = AppLocalizations.of(context)!;` — sil
- `l.keyName` → `loc.t('keyName')`
- `l.keyName(param)` → `loc.t('keyName', {'param': value.toString()})`

---

### 5. Option Label Pattern (`tOr`)

Dropdown ve multiselect'lerde option label'ları için:

```dart
// Önce: DB'den gelen Türkçe label (hardcoded, çevrilmiyor)
Text(o.label)

// Sonra: DB'deki opt_* key'i varsa çevrilmiş, yoksa orijinal label
Text(loc.tOr('opt_${o.value}', o.label))
```

**Neden `tOr`?** Renk/yakıt/vites gibi kategorik değerler `translations` tablosunda `opt_*` key'i olarak var.
Ama araç markası (`opt_bmw`) gibi değerler tabloda yok — fallback olarak `o.label` (`'BMW'`) döner.

---

### 6. Subcategory Label Pattern

```dart
// Önce: field_labels.dart'taki switch ile
subcatLabel(s.$1, l, fallback: s.$2)

// Sonra: doğrudan
loc.tOr('subcat_${s.$1}', s.$2)
```

`field_labels.dart`'taki `subcatLabel` fonksiyonu artık gerekmiyor — import'u kaldır.

---

### 7. Extra Field Label Pattern

```dart
// Önce: 47-case switch (_extraFieldLabel metodu)
final label = _extraFieldLabel(f.labelKey, l);

// Sonra: tek satır
final label = loc.t(f.labelKey);
```

`extraField_*` key'leri zaten `translations` tablosunda olduğundan switch'e gerek kalmadı.

---

### Sonraki Ekranı Migrate Ederken Kontrol Listesi

- [ ] `ConsumerStatefulWidget` / `ConsumerState` dönüşümü
- [ ] `import app_localizations.dart` kaldırıldı
- [ ] `final l = AppLocalizations.of(context)!` kaldırıldı
- [ ] Tüm `l.xxx` → `loc.t('xxx')` (parametreli olanlar manuel)
- [ ] Option label'lar `loc.tOr('opt_${o.value}', o.label)` pattern'ine geçirildi
- [ ] İç StatelessWidget'lar `ConsumerWidget`'a dönüştürüldü
- [ ] `dart analyze` → sıfır hata
- [ ] 4 dil test (TR / EN / AR / RU)

---

### OTA Güncelleme Akışı (Operasyonel)

Bir çeviriyi değiştirmek için:

```bash
# 1. DB'yi güncelle
psql "postgresql://teqlif:***@127.0.0.1:5432/teqlif" \
  -c "UPDATE translations SET value='Yeni Değer' WHERE key='someKey' AND lang='tr';"

# 2. Redis cache'i temizle
redis-cli DEL i18n:tr i18n:tr:version

# 3. Bitti — kullanıcılar bir sonraki uygulama açılışında yeni çeviriyi görür
```
