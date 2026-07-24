# OTA Localization — Büyük Plan

**Hedef:** Tüm çeviriler tek kaynakta (DB) yaşar. Backend dil paketi serve eder. Her client (Flutter, Web) paketi çeker, kendi cache'inde saklar, kullanır. Uygulama güncellemesi olmadan çeviriler güncellenebilir.

**Pilot:** Flutter — İlan Ver Ekranı  
**Kapsam:** Pattern bu ekranda kanıtlanır, diğer ekranlar aynı pattern ile ilerler.

---

## Mimari Özeti

```
DB: translations(key, lang, value)
           ↓
GET /api/i18n/{lang}  →  { "ui_save": "Save", "subcat_automobile": "Automobile", ... }
           ↓
LocalizationService (Hive cache, ChangeNotifier)
           ↓
t('ui_save')  →  "Save"
```

**Çeviri Key Namespace'leri:**

| Prefix | Örnek | Açıklama |
|--------|-------|----------|
| `ui_` | `ui_save`, `ui_cancel` | Statik UI chrome (butonlar, başlıklar, hata mesajları) |
| `subcat_` | `subcat_automobile` | Alt kategori isimleri |
| `opt_` | `opt_white`, `opt_gasoline` | Field option label'ları |
| `field_` | `field_brand`, `field_color` | Field label'ları (extraField_ prefix yerine) |
| `cat_` | `cat_vehicles`, `cat_electronics` | Ana kategori isimleri |

**Diller:** `tr` · `en` · `ar` · `ru`

---

## FAZ 1 — DB: Translations Tablosu

**Amaç:** Tüm çevirilerin yaşayacağı merkezi tabloyu oluştur ve seed et.

---

- [x] **T01** — Alembic migration: `translations(key, lang, value)` tablosunu oluştur ✅
  - `PRIMARY KEY (key, lang)`
  - Index: `lang` üzerinde (dil paketi çekimini hızlandırır)
  - Dosya: `backend/alembic/versions/aad_translations_table.py`

- [x] **T02** — ARB → DB migration: Mevcut 4 ARB dosyasının tüm key-value'larını translations tablosuna import et ✅
  - 4 dil × ~1775 key = 7096 satır — T01 migration dosyasına gömüldü

- [x] **T03** — Field label'larını 4 dilde translations tablosuna ekle ✅
  - `extraField_brand`, `extraField_year` vb. — ARB'den otomatik geldi (T02 içinde)

- [x] **T04** — Option label'larını 4 dilde translations tablosuna ekle ✅
  - 36 `opt_*` key × 4 dil = 144 satır — migration'a `_OPT_DATA` dict olarak gömüldü
  - Renkler, yakıt, vites, kasa tipi, hasar durumları + `opt_other`

- [x] **T05** — Subcategory label'larını 4 dilde translations tablosuna ekle ✅
  - `subcat_automobile` vb. 59 key — ARB'den otomatik geldi (T02 içinde)

- [x] **T06** — VPS'te migration çalıştır ve verify et ✅
  - `alembic upgrade head` → başarılı
  - Verify: `SELECT lang, COUNT(*) FROM translations GROUP BY lang;`
  - `redis-cli FLUSHALL` (sonraki fazda cache'i temiz başlat)

---

## FAZ 2 — Backend API: Dil Paketi Endpoint'i

**Amaç:** Client'ların dil paketini çekebileceği temiz bir API yaz.

---

- [x] **T07** — `GET /api/i18n/{lang}` endpoint yaz ✅
  - DB'den `WHERE lang = :lang` ile tüm key-value'ları çek
  - Flat JSON döndür: `{ "acceptRequest": "Onayla", "subcat_automobile": "Otomobil", ... }`
  - Geçersiz lang → 400 Bad Request
  - Dosya: `backend/app/routers/i18n.py`

- [x] **T08** — Redis cache ekle ✅
  - Cache key: `i18n:{lang}` (örn. `i18n:en`), TTL: 3600s
  - Version cache: `i18n:{lang}:version`, TTL: 3600s

- [x] **T09** — `GET /api/i18n/{lang}/version` endpoint yaz ✅
  - MD5 hash of sorted key-value JSON
  - `{ "version": "a3f8c2..." }` döndürür

- [x] **T10** — `main.py`'a i18n router kaydını ekle ✅

- [x] **T11** — Deploy + 4 dil için API test ✅
  - `curl /api/i18n/tr` → TR paketi geldi mi?
  - `curl /api/i18n/en` → EN paketi geldi mi?
  - `curl /api/i18n/ar` → AR paketi geldi mi?
  - `curl /api/i18n/ru` → RU paketi geldi mi?
  - `curl /api/i18n/xx` → 400 döndü mü?

---

## FAZ 3 — Flutter: LocalizationService

**Amaç:** Flutter'ın kendi i18n sistemini (AppLocalizations/ARB) bypass eden, DB kaynaklı dil paketini kullanan servis yaz.

---

- [x] **T12** — Hive box tanımla ve `main.dart`'a init ekle ✅
  - Box adı: `i18n_cache`, `LocalizationService.initBox()` → `main.dart`'ta `CacheService.init()` sonrası

- [x] **T13** — `LocalizationService` sınıfı yaz ✅
  - `StateNotifier<TranslationPack>` (Riverpod ile uyumlu)
  - `TranslationPack.t(key, params?)` — immutable, widget rebuild tetikler
  - `load()`, `clearCache()`, `_fetchAndCache()` implementasyonları
  - Dosya: `mobile/lib/services/localization_service.dart`

- [x] **T14** — `t()` fonksiyonuna param interpolation ekle ✅
  - `t('key', {'name': 'Ahmet'})` → `"Merhaba Ahmet"` (`{name}` replace)

- [x] **T15** — Stale check mekanizması yaz ✅
  - 24h TTL: `cached_at_{lang}` Hive key'i
  - Background: version hash karşılaştırması → farklıysa re-fetch

- [x] **T16** — Riverpod `StateNotifierProvider` ile provide et ✅
  - `localizationProvider` → `ProviderScope` altında otomatik available
  - Widgets: `ref.watch(localizationProvider).t('key')`

- [x] **T17** — `localeProvider` değişiminde otomatik dil paketi yükleme ✅
  - `ref.listen<Locale>(localeProvider, ...)` → `load()` otomatik tetiklenir
  - RTL layout `localeProvider` üzerinden zaten çalışıyor (main.dart)

---

## FAZ 4 — Dil Seçimi Entegrasyonu

**Amaç:** Kullanıcı dil seçtiğinde veya değiştirdiğinde akış doğru çalışsın.

---

- [x] **T18** — Uygulama açılışı akışı ✅
  - `LocalizationService` constructor'ı `localeProvider`'dan mevcut dili okuyup `load()` çağırıyor
  - Hive'da cache varsa anında yüklenir, yoksa API'den çeker

- [x] **T19** — Login ekranı — dil seçimi entegrasyonu ✅
  - `login_screen.dart`: `localeProvider.notifier.setLocale(Locale(x))` → `ref.listen` tetiklenir → `load()` otomatik
  - Ayrıca değişiklik gerekmedi

- [x] **T20** — Settings ekranı — dil değişimi entegrasyonu ✅
  - `profile_screen.dart`: `localeProvider.notifier.setLocale(Locale(x))` → aynı mekanizma
  - Ayrıca değişiklik gerekmedi

---

## FAZ 5 — Pilot Ekran: İlan Ver

**Amaç:** `create_listing_screen.dart`'taki tüm `AppLocalizations` bağımlılığını `LocalizationService`'e taşı. Pattern kanıtlandı.

---

- [ ] **T21** — `AppLocalizations` import ve `l` değişkenini kaldır
  - `final l = AppLocalizations.of(context)!;` satırını sil
  - Yerine: `final loc = context.watch<LocalizationService>();`
  - Ya da global `t()` helper kullanımı (tercih edilirse)

- [ ] **T22** — Tüm `l.xxx` → `t('xxx')` dönüşümü
  - `l.fieldSubcategory` → `t('ui_fieldSubcategory')`
  - `l.validRequiredSubcategory` → `t('ui_validRequiredSubcategory')`
  - `l.fieldCategory` → `t('ui_fieldCategory')`
  - vb. — ekrandaki tüm `l.` referansları

- [ ] **T23** — `subcatLabel()` fonksiyonunu `t()` kullanacak şekilde güncelle
  - `field_labels.dart`'taki `subcatLabel(key, l)` → `subcatLabel(key)` (AppLocalizations parametresi düşer)
  - İçeride `t('subcat_$key')` kullanır

- [ ] **T24** — Option label pattern uygula
  - `o.label` (DB'den gelen Türkçe) yerine `t('opt_${o.value}')`
  - Tüm dropdown ve multiselect render'larında uygulanır

- [ ] **T25** — Field label pattern uygula
  - `t(field.labelKey)` — field_config API'sinin döndürdüğü `label_key` direkt translation key olarak kullanılır

- [ ] **T26** — 4 dilde manuel test
  - TR: Tüm label'lar Türkçe mi?
  - EN: Tüm label'lar İngilizce mi?
  - AR: Tüm label'lar Arapça mı? RTL doğru mu?
  - RU: Tüm label'lar Rusça mı?

---

## FAZ 6 — Temizlik ve OTA Doğrulama

**Amaç:** Pattern kanıtlandı, temizlik yapılır ve OTA çalıştığı doğrulanır.

---

- [ ] **T27** — `dart analyze` — sıfır hata/warning

- [ ] **T28** — OTA doğrulama testi
  - DB'de bir çeviriyi elle değiştir (örn. `opt_white` TR: "Beyaz" → "Bembeyaz")
  - Redis cache temizle: `redis-cli DEL i18n:tr`
  - Flutter'da dili TR'ye geç (veya force refresh)
  - "Bembeyaz" göründü mü? → OTA çalışıyor ✅

- [ ] **T29** — Commit + push + VPS deploy

- [ ] **T30** — `create_listing_screen.dart` için kullanılmayan ARB key'lerini tespit et
  - Bu ekrana ait key'ler artık sadece DB'de yaşıyor
  - ARB'den silmek için liste hazırla (diğer ekranlar hâlâ ARB kullanıyor, dikkatli ol)

---

## Notlar

- **ARB dosyaları** FAZ 5 sonrası `create_listing_screen` için dead code olur ama silinmez — diğer ekranlar henüz migrate olmadı.
- **Web frontend** aynı `GET /api/i18n/{lang}` API'sini kullanır, aynı pattern uygulanır (ayrı plan).
- **Admin panel** ilerleyen aşamada `translations` tablosunu yönetmek için eklenebilir — API değişmez.
- **Yeni dil eklemek:** `translations` tablosuna yeni `lang` değerleri insert et, API otomatik destekler.
