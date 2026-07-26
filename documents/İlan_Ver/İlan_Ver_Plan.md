# İlan Ver — Yapay Zeka Açıklama İyileştirme Planı

**Ekran:** `mobile/lib/screens/create_listing_screen.dart`  
**Backend:** `backend/app/routers/listings.py`, `backend/app/services/ml/llm_service.py`  
**Mimari referans:** `documents/Architectural Decisions.md`

---

## Kapsam

Üç bağımsız iyileştirme:

1. **Buton etiketi güncelleme** — "AI ile Açıklama Yaz" → "Yapay Zeka ile Açıklama Yaz"
2. **Buton davranışı hizalama** — Açıklama butonunun disable yerine uyarı vermesi
3. **Zengin AI açıklama** — Subcategory + extra field verisiyle LLM'e daha fazla bağlam

---

## 1. Buton Etiketi Güncelleme

### Mevcut durum

```
aiDescButton    → "AI ile Açıklama Yaz"         ← tutarsız
aiPriceButton   → "Yapay Zeka ile Fiyat Belirle" ← doğru format
aiDescUnavailable → "AI açıklama servisi..."      ← tutarsız
```

### Değişiklikler

**4 ARB dosyasında:**

| Key | Önce | Sonra |
|-----|------|-------|
| `aiDescButton` | "AI ile Açıklama Yaz" | "Yapay Zeka ile Açıklama Yaz" |
| `aiDescUnavailable` | "AI açıklama servisi şu an aktif değil." | "Yapay Zeka açıklama servisi şu an aktif değil." |

Diğer 3 dil (EN, AR, RU) için de aynı key'lerin karşılığı güncellenir.

VPS'te `sync_translations.py` çalıştırılmalı.

---

## 2. Buton Davranışı Hizalama

### Mevcut asimetri

| | AI Fiyat Butonu | AI Açıklama Butonu |
|---|---|---|
| Görsel durum | Her zaman aktif | `_aiReady` false iken disabled (gri) |
| Tıklandığında | `_fetchAiPriceEstimate` → `!_aiReady` ise warning toast | `onTap: null` — hiçbir şey olmaz |
| Kullanıcı geri bildirimi | "Tüm alanları doldurun" tostu | Yok — kullanıcı neyin eksik olduğunu bilmez |

### Analiz

`_fetchAiDescription` fonksiyonu zaten doğru guard'a sahip:
```dart
if (!_aiReady) {
  TeqSnackBar.show(message: loc.t('createNeedAllFieldsNew'), type: TeqSnackBarType.warning);
  return;
}
```

Sorun: `_AiDescButton` widget'ına `enabled: _aiReady` geçiliyor ve bu `false` olduğunda `onTap: null` yapılıyor — guard'a hiç ulaşılmıyor.

### Çözüm

`_AiDescButton` widget'ından `enabled` parametresi kaldırılır. Button her zaman aktif görünür ve tıklanabilir; guard `_fetchAiDescription` içinde kalır.

**AD §3 (Merkezi Error Handling) uyumu:**
- Form validasyonu → inline field error (kırmızı metin altında)
- AI hazır değil uyarısı → `TeqSnackBar` warning (tutarlı, toast)
- API hataları → `TeqSnackBar` error veya `handleError`
- Ekranda hiçbir `showErrorSnackbar(context, ...)` veya `ErrorDisplay` kalmamalı

### `_aiReady` scope kontrolü

`_aiReady` şu an: başlık + kategori + şehir + durum. Açıklama butonu için subcategory gerekmez (opsiyonel veri olarak kullanılır). Fiyat butonu için de aynı kural — `_aiReady` değişmez.

---

## 3. Zengin AI Açıklama — Extra Field Entegrasyonu

### Mevcut prompt'a giden veri

```python
# Flutter → Backend request body
{
  'title': 'Ford Focus',
  'category': 'vehicles',
  'condition': 'used',
  'price': 450000,       # opsiyonel
  'location': 'İstanbul' # opsiyonel
}

# _build_prompt kullandığı değişkenler
title, category, condition  # price ve location prompt'a girmiyor!
```

`price` ve `location` `_build_prompt`'a geçilmiyor — `_sentence_stream`'e geçiliyor ama orada post-processing yapılıyor (fiyat/konum bilgisi açıklama içine ekleniyor).

### Kaybedilen zengin veri

Ekranda elimizde olan ama LLM'e gitmeyen:

```dart
_selectedSubcategory  // "automobile"
_extraValues          // {marka: Ford, model: Focus, yil: 2019, km: 85000}
_extraMultiValues     // {renk: {white}, kasa_tipi: {sedan}, yakit: {gasoline}}
_selectedDistrict     // "Kadıköy"
```

### Potansiyel çıktı farkı

**Şimdi:** "2019 model otomobil, kullanıldı, İstanbul'da satılık..."  
**Sonra:** "2019 Ford Focus, 85.000 km'de, benzinli, manuel, sedan kasa, beyaz, Kadıköy'den satılık..."

### Mimari karar: Extra field'ları nasıl geçeceğiz?

**Flutter → API:** `extra_fields: {marka: Ford, model: Focus, yil: "2019", km: "85000", yakit: gasoline}`

Multiselect değerleri string'e join edilir: `{renk: "beyaz, siyah"}`.

**Backend `GenerateDescriptionRequest` genişlemesi:**
```python
class GenerateDescriptionRequest(BaseModel):
    title: str
    category: str
    subcategory: Optional[str] = None       # yeni
    condition: Optional[str] = None
    price: Optional[float] = None
    location: Optional[str] = None
    district: Optional[str] = None          # yeni
    extra_fields: Optional[dict] = None     # yeni
```

**`_build_prompt` genişlemesi:**

Extra field'lar `user_prompt`'a eklenir:
```
Ek özellikler:
- Marka: Ford
- Model: Focus
- Yıl: 2019
- Kilometre: 85.000 km
- Yakıt: Benzin
- Vites: Manuel
- Kasa: Sedan
- Renk: Beyaz
```

LLM bunları hem doğal dile çevirmeli hem de mevcut `combo_hint` ile sentezlemelidir.

### Kategori bazlı etki büyüklüğü

| Kategori | Extra field zenginliği | Açıklama kalite artışı |
|---|---|---|
| Otomobil / Motorsiklet | Yüksek (10+ field) | Çok yüksek |
| Elektronik (telefon, laptop) | Orta (5-7 field) | Yüksek |
| Gayrimenkul (daire, ev) | Orta (ısıtma, kat, m²) | Yüksek |
| Moda, Kitap | Düşük (1-2 field) | Orta |
| Diğer | Yok | Değişmez |

### Boş extra_field güvencesi

Extra field yoksa (subcategory seçilmemişse veya field doldurmamışsa) backend sessizce yok sayar — mevcut davranış korunur. Hiçbir hata tetiklenmez.

---

## Özet Karar Tablosu

| Görev | Değişen Yer | Risk |
|---|---|---|
| Buton etiketi | 4 ARB + sync | Sıfır |
| Buton davranışı | Flutter: `_AiDescButton` widget | Düşük |
| Zengin AI | Flutter request body + Backend request model + `_build_prompt` | Orta |
