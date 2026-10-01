# Teqlif — Fiyat Önerisi Mimarisi

Son güncelleme: 2026-08-08

---

## Vizyon

Teqlif içindeki tüm fiyat önerileri, **platformun kendi organik satış verisinden** beslenir.
Dış kaynak (Trendyol, Sahibinden vb.) kullanılmaz — teqlif'in birikimi piyasanın kendisidir.

Yeterli veri yoksa öneri gösterilmez. Yanıltıcı öneri, öneri yoktan kötüdür.

---

## Mevcut Durum (Sorunlar)

| Yüzey | Endpoint | Veri kaynağı | Sorun |
|---|---|---|---|
| İlan Ver | `POST /analytics/price-estimate` | `listings.last_sold_price` (sadece auction) | DS satışları havuza girmiyor |
| DS Start | `GET /direct-sales/suggestions` | ClickHouse `direct_sale_events` (host geneli) | Yanlış kapsam, zayıf veri |
| Auction Start | `GET /analytics/competitor-radar/{id}` | Aktif ilanlar (rakip karşılaştırması) | Farklı soru soruyor, fiyat önerisi değil |

Ek sorun: `listings.last_sold_price` sadece auction bitişinde güncelleniyor
(`auction_commands.py:411`). DS satışı tamamlandığında bu alan hiç güncellenmiyor.

---

## Hedef Mimari

### Tek Veri Havuzu

Her iki satış mekanizmasının (auction + DS) tamamlanan satışları
`listings.last_sold_price` üzerinden ortak havuza giriyor:

```
auctions.final_price      ──┐
                             ├──► listings.last_sold_price  ──► pgvector AI havuzu
direct_sale_orders.unit_price──┘

listings.embedding (384d)  ──► HNSW index  ──► benzerlik araması
listings.subcategory / brand / model_name / condition  ──► sinyal ağırlıklandırma
```

### Fiyat Sinyallerinin Niteliği

- **Auction final fiyatı** = rekabet tarafından keşfedilmiş piyasa değeri → **tavan sinyali**
- **DS satış fiyatı** = hostin belirlediği, alıcının kabul ettiği fiyat → **satış sinyali**

İkisi aynı havuzda ama ayrı sinyaller olarak etiketlenir; düz ortalama alınmaz.

### Embedding Stratejisi

| Bağlam | Embedding kaynağı | Maliyet |
|---|---|---|
| İlan Ver (yeni ilan) | ARQ worker üretir, Redis'e cache | TUCi |
| DS/Auction Start (listing seçildi) | `listings.embedding` doğrudan okunur | Ücretsiz |

Listing oluşturulduğunda embedding zaten var → DS/Auction start'ta yeniden üretilmez.

---

## Yüzey Bazlı Davranış

### 1. İlan Ver — `POST /analytics/price-estimate`

**Değişiklik:** Mevcut AI korunur, sadece DS satışları da havuza eklenir.

- Mevcut: `listings.last_sold_price` (sadece auction)
- Hedef: `listings.last_sold_price` (auction + DS — her ikisi günceller)
- Çıktı değişmez: `suggested_start_price`, `estimated_close_price`, güven bantları
- Maliyet: TUCi (değişmez)

### 2. DS Start — Yeni Hafif Endpoint

**Değişiklik:** ClickHouse sorgusu kaldırılır; listing'in mevcut embedding'i kullanılır.

- Yalnızca `listingId` varsa çalışır (manuel modda chip gösterilmez)
- `listings.embedding` → pgvector benzerlik araması → en yakın satılan ilanlar
- Sinyal ağırlıklandırma: DS satışları %70, auction satışları %30
- Çıktı: `suggested_price`, `sample_count`, `confidence`
- Kaldırılan çıktılar: `avg_demand`, `avg_conversion_rate`, `recommended_stock`
- Eşikler: aynı listing ≥2 satış, aynı özellik grubu ≥5 satış → yoksa sessiz
- Maliyet: Ücretsiz

### 3. Auction Start

**Değişiklik:** Aynı hafif endpoint, farklı ağırlık ve çıktı yorumu.

- Sinyal ağırlıklandırma: Auction final fiyatları %80, DS fiyatları %20
- Çıktı yorumu: "Benzer müzayedeler X'te kapandı → başlangıç için Y–Z aralığı"
- (Başlangıç fiyatı genellikle kapanış fiyatının %65–75'i)

### 4. Competitor Radar — Değişmez

`GET /analytics/competitor-radar/{id}` — farklı bir soru soruyor:
"Şu anki aktif ilanlar arasında benim fiyatım nerede duruyor?"
Bu analiz aynı kalır; fiyat önerisi sistemiyle entegre edilmez.

---

## Fallback Hiyerarşisi

```
1. Aynı listing_id (≥2 satış)            → En güçlü sinyal
2. subcategory + brand + model + condition (≥5 satış)  → Neredeyse aynı ürün
3. subcategory + brand + model (≥5 satış) → Kondisyon fark etmez
4. subcategory + brand (≥10 satış)        → Aynı marka grubu
5. Sessizlik                              → Yeterli veri yok, chip gösterilmez
```

Host-wide fallback kaldırıldı — farklı ürün fiyatlarının ortalaması anlamsız.

---

## Veri Akışı (Hedef)

```
Auction biter (accept_bid / end_auction, winner_accepted=true)
    └──► listings.last_sold_price = final_price   [mevcut ✅]
    └──► listings.last_start_price = start_price  [mevcut ✅]

DS satışı tamamlanır (purchase_completed, tüm stok bitince veya host bitirir)
    └──► listings.last_sold_price = avg(unit_price)  [eksik ❌ → eklenecek]
```

---

## Neyin Değişmediği

- İlan Ver AI algoritması (pgvector + KDE + IQR + TUCi) korunur
- Competitor radar korunur
- Listing oluşturma embedding üretimi değişmez
- ClickHouse `direct_sale_events` tablosu değişmez (analytics için kullanılmaya devam eder)
