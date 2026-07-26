# İlan Filtreleme — Analiz ve Tasarım

## 1. Mevcut Durum: Hangi Ekranlarda Filtreleme Var?

### 1.1 API-Driven Filtreleme (sunucu sorgusu tetikler)

#### `home_screen.dart` — Ana İlanlar Sayfası
**Mevcut filtre state'i:**
- `String? _selectedCategory` — seçili kategori slug'ı
- `String? _selectedCity` — seçili şehir adı
- `String _searchQuery` — arama metni

**Mevcut UI:**
```
[AppBar: "İlanlar"                         ] [+ İlan Ver]
[İkon kategoriler — yatay scroll, 90px]
[Şehir chip▼] [Aktif kategori chip ✕] [Aktif şehir chip ✕] [Temizle]
[🔍 Ara... TextField                            ✕]
─── İlan listesi ───────────────────────────────────────
```

**Nasıl çalışır:** Kategori/şehir değişince `_load()` → API çağrısı.  
**Eksikler:** Subcategory yok, extra fields yok, kondisyon yok, fiyat aralığı yok, sıralama yok.

---

### 1.2 Client-Side Filtreleme (yerel liste filtrelenir)

#### `profile_screen.dart` → `_MyListingsScreen` — Kendi İlanlarım
**Mevcut filtre state'i:**
- `String? _selectedCategory`
- `String _searchQuery`
- `_searchCtrl: TextEditingController`

**Mevcut UI:** `ListingFilter` widget (profile_screen.dart:937 — accordion "Filtrele" başlığı altında arama + yatay kategori chip'leri)

**Nasıl çalışır:** `_filteredListings` getter — `_selectedCategory` ve `_searchQuery` ile yerel liste filtrelenir. API çağrısı yok.

---

#### `public_profile_screen.dart` — Herkese Açık Profil
**Mevcut filtre state'i:** Aynı `_MyListingsScreen` ile özdeş.  
**Mevcut UI:** Aynı `ListingFilter` widget'ı kullanıyor.

---

#### `sales_screen.dart` — Satışlarım
**Mevcut filtre state'i:**
- `String _categoryFilter` (boş string = tümü)
- `String _searchQuery`

**Mevcut UI:** Satır içi search TextField + yatay kategori chip'leri. `ListingFilter` widget'ı kullanmıyor, inline yazılmış.

---

### 1.3 Filtreleme **Olmayan** Ekranlar (Yanıltıcı çıktılar)
- `search_screen.dart` — Arama ekranı, kendi başına bir feature. Filtre modal'a gerek yok.
- `pro_insights_screen.dart` — Analitik filtreler (tarih, kategori): farklı amaç, buna dokunmuyoruz.
- `sales_screen.dart`'ın Pro araç kısmı — analytics filter, kapsam dışı.

---

## 2. Ne Kaldırılacak, Ne Eklenecek

### home_screen.dart
| Kaldırılacak | Eklenecek |
|---|---|
| 90px yüksekliğinde kategori ikonu scroll bar'ı | Üstte yalnızca arama TextField |
| Şehir chip + aktif filtre chip'leri satırı | "Filtrele" butonu + aktifse "Temizle" butonu |
| İlan listesinin üstündeki `showModalBottomSheet` şehir seçici | → Filter modal'a taşınır |

### profile_screen.dart + public_profile_screen.dart
| Kaldırılacak | Eklenecek |
|---|---|
| `ListingFilter` accordion widget (profile_screen:937–1054) | Yeni `ListingFilterBar` widget'ı |

### sales_screen.dart
| Kaldırılacak | Eklenecek |
|---|---|
| Inline search + kategori chip'leri | Yeni `ListingFilterBar` widget'ı |

---

## 3. Yeni Component Mimarisi

### 3.1 `ListingFilterState` — Veri Modeli
**Dosya:** `mobile/lib/models/listing_filter_state.dart`

```dart
class ListingFilterState {
  final String? category;       // slug: 'vasita', 'elektronik'
  final String? subcategory;    // slug: 'otomobil', 'cep-telefonu'
  final String? city;           // şehir adı
  final String? condition;      // 'new', 'used', 'damaged'
  final String? sortBy;         // 'newest', 'price_asc', 'price_desc'
  final double? minPrice;
  final double? maxPrice;
  final Map<String, dynamic> extraFields; // year, km, fuel_type, ...

  const ListingFilterState({...});

  bool get isEmpty => category == null && subcategory == null
      && city == null && condition == null && sortBy == null
      && minPrice == null && maxPrice == null && extraFields.isEmpty;

  int get activeCount => [
    category, subcategory, city, condition, sortBy,
    if (minPrice != null || maxPrice != null) 'price',
    ...extraFields.keys,
  ].whereType<String>().length;
}
```

> `searchQuery` bu modele **girmez** — arama çubuğu her zaman görünür, filtre modal'ın dışındadır.

---

### 3.2 `ListingFilterBar` — Tetikleyici Satır
**Dosya:** `mobile/lib/widgets/listing_filter_bar.dart`

```
[🔍 Ara... TextField                            ✕]
[🎛 Filtrele (3) ▼]   [✕ Temizle]
```

**Davranış:**
- Search TextField her zaman en üstte, filtre butonundan bağımsız
- "Filtrele" butonu → `ListingFilterSheet.show()` açar
- Aktif filtre sayısı badge olarak butonda gösterilir: `Filtrele (3)`
- "Temizle" butonu yalnızca `!filter.isEmpty` durumunda görünür
- Kullanıcı modal dışına basarsa filtreler **uygulanmaz** (pending state korunur, applied state değişmez)
- Yalnızca "Filtreyi Uygula" basılırsa `onFilterApplied` callback tetiklenir

**Parametre arayüzü:**
```dart
ListingFilterBar({
  required TextEditingController searchCtrl,
  required ListingFilterState appliedFilter,
  required ValueChanged<String> onSearchChanged,
  required ValueChanged<ListingFilterState> onFilterApplied,
  required VoidCallback onSearchCleared,
  VoidCallback? onFilterCleared,
  // Hangi alanların gösterileceğini kontrol eder:
  bool showCategory = true,
  bool showSubcategory = true,
  bool showExtraFields = true,
  bool showCity = true,
  bool showCondition = true,
  bool showSort = false,       // home_screen'de true
  bool showPriceRange = false, // home_screen'de true
})
```

---

### 3.3 `ListingFilterSheet` — Bottom Sheet Modal
**Dosya:** `mobile/lib/widgets/listing_filter_sheet.dart`

**Layout:**
```
┌────────────────────────────────────────────┐
│ ○ ── (drag handle)                         │
│ Filtrele                         ✕ Kapat   │
├────────────────────────────────────────────┤
│                                            │ ↑
│  Kategori                                  │
│  [Vasıta] [Elektronik] [Ev & Yaşam] ...    │
│                                            │
│  Alt Kategori  (kategori seçilince açılır) │
│  [Otomobil] [Motosiklet] [Kamyon] ...      │
│                                            │
│  Extra Alanlar (subcategory seçilince)     │
│  Yıl: [____]  Km: [____]  Yakıt: [▼]      │
│                                            │
│  Şehir                                     │
│  [🔽 Şehir seç]                           │
│                                            │
│  Durum                                     │
│  [Tümü] [Sıfır] [İkinci El] [Hasarlı]     │
│                                            │
│  Fiyat Aralığı  (home_screen için)         │
│  Min [____] TL   Max [____] TL             │
│                                            │
│  Sıralama  (home_screen için)              │
│  [En Yeni] [Ucuzdan Pahalıya] [Pahalıdan] │
│                                            │ ↓
├────────────────────────────────────────────┤  ← sticky
│  [Filtreyi Temizle]                        │
│  [         Filtreyi Uygula (3)           ] │
└────────────────────────────────────────────┘
```

**Davranış kuralları:**
1. Modal açıldığında `appliedFilter`'ı kopyalayarak **pending state** başlatır
2. Kullanıcı scroll yaparken "Filtreyi Uygula" ve "Filtreyi Temizle" **her zaman görünür** (sticky footer)
3. Dışarı tıklanırsa → modal kapanır, pending state atılır, applied state değişmez
4. "Filtreyi Temizle" → pending state temizlenir, modal açık kalır
5. "Filtreyi Uygula" → `onApplied(pendingFilter)` callback, modal kapanır
6. Kategori seçildiğinde subcategory alanı `AnimatedSize` ile kayarak açılır
7. Subcategory seçildiğinde extra fields `FieldConfigService.getFields()` ile yüklenir
8. Şehir seçimi — aynı `showModalBottomSheet` city picker (home_screen'den taşınır)

**`show()` static helper:**
```dart
static Future<ListingFilterState?> show(
  BuildContext context, {
  required ListingFilterState current,
  bool showSort = false,
  bool showPriceRange = false,
}) async { ... }
```

---

## 4. Ekran Bazlı Uygulama Planı

### Sıra 1 — Component Oluştur
- `mobile/lib/models/listing_filter_state.dart`
- `mobile/lib/widgets/listing_filter_sheet.dart`
- `mobile/lib/widgets/listing_filter_bar.dart`

### Sıra 2 — `home_screen.dart` Migration

**State değişimi:**
```dart
// ÖNCE
String? _selectedCategory;
String? _selectedCity;
String _searchQuery = '';
TextEditingController _searchController;

// SONRA
ListingFilterState _appliedFilter = const ListingFilterState();
String _searchQuery = '';
TextEditingController _searchController;
```

**Build değişimi:**
```dart
// Kaldırılacak bloğun başladığı satır: 441 (SizedBox, kategori ikonları)
// Kaldırılacak bloğun bittiği satır: ~650 (city chip satırı + search TextField)

// Yerine:
ListingFilterBar(
  searchCtrl: _searchController,
  appliedFilter: _appliedFilter,
  onSearchChanged: _onSearchChanged,
  onSearchCleared: _clearSearch,
  onFilterApplied: (f) { setState(() => _appliedFilter = f); _load(); },
  onFilterCleared: () { setState(() => _appliedFilter = const ListingFilterState()); _load(); },
  showSort: true,
  showPriceRange: true,
),
```

**`_load()` güncelleme:**
```dart
// ÖNCE
if (_selectedCategory != null) params['category'] = _selectedCategory!;
if (_selectedCity != null) params['location'] = _selectedCity!;

// SONRA
if (_appliedFilter.category != null) params['category'] = _appliedFilter.category!;
if (_appliedFilter.subcategory != null) params['subcategory'] = _appliedFilter.subcategory!;
if (_appliedFilter.city != null) params['location'] = _appliedFilter.city!;
if (_appliedFilter.condition != null) params['condition'] = _appliedFilter.condition!;
if (_appliedFilter.sortBy != null) params['sort'] = _appliedFilter.sortBy!;
// ... minPrice, maxPrice, extraFields
```

---

### Sıra 3 — `profile_screen.dart` + `public_profile_screen.dart` Migration

**State değişimi:**
```dart
// ÖNCE
String _searchQuery = '';
String? _selectedCategory;
TextEditingController _searchCtrl;

// SONRA
ListingFilterState _appliedFilter = const ListingFilterState();
String _searchQuery = '';
TextEditingController _searchCtrl;
```

**`_filteredListings` güncelleme:**
```dart
List<dynamic> get _filteredListings {
  var r = List<dynamic>.from(_listings);
  if (_appliedFilter.category != null)
    r = r.where((l) => l['category'] == _appliedFilter.category).toList();
  if (_searchQuery.isNotEmpty) {
    final q = _searchQuery.toLowerCase();
    r = r.where((l) => (l['title'] as String? ?? '').toLowerCase().contains(q)
                     || (l['description'] as String? ?? '').toLowerCase().contains(q)).toList();
  }
  return r;
}
```

**Build:** `ListingFilter` widget → `ListingFilterBar` widget  
**Silinecek:** `ListingFilter`, `_ListingFilterState`, `_CategoryChip` class'ları (profile_screen:937–1054)

---

### Sıra 4 — `sales_screen.dart` Migration

Inline search + kategori chip'leri → `ListingFilterBar`.  
`showCategory: true`, subcategory/extraField/city/condition: `false` (satış listesi basit tutulur).

---

## 5. Kapsam Dışı Bırakılanlar

| Ekran | Neden |
|---|---|
| `search_screen.dart` | Arama kendi başına bir feature, filtre modal'ı uygun değil |
| `pro_insights_screen.dart` | Analitik filtreler, farklı domain |
| `sales_screen.dart` (Pro araç kısmı) | Satış analitikleri, ayrı filter chip'leri kalacak |

---

## 6. Yeni Dosyalar

```
mobile/lib/
  models/
    listing_filter_state.dart        ← yeni
  widgets/
    listing_filter_bar.dart          ← yeni
    listing_filter_sheet.dart        ← yeni
```

## 7. Silinen / Değiştirilen Kod

| Dosya | Satır | Ne Olacak |
|---|---|---|
| `home_screen.dart` | 441–670 | Kategori ikonu + şehir chip + filtre chip satırı kaldırılır |
| `home_screen.dart` | ~297–385 | `_showCityPicker()` metodu kaldırılır (sheet'e taşınır) |
| `profile_screen.dart` | 937–1054 | `ListingFilter` + `_CategoryChip` class'ları kaldırılır |
| `public_profile_screen.dart` | ~770 | `ListingFilter` çağrısı → `ListingFilterBar` |
| `sales_screen.dart` | ~126–170 | Inline filter → `ListingFilterBar` |
