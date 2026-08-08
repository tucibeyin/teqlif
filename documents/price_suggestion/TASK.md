# Fiyat Önerisi — Görev Listesi

Son güncelleme: 2026-08-08

Mimari için bkz. [PLAN.md](./PLAN.md)

---

## Faz 1 — Veri Havuzunu Tamamla

> Önkoşul: DS satışları `last_sold_price`'a yazılmadan hiçbir öneri sistemi DS verisini göremez.

- [x] **F1-1** `direct_sale_commands.py` — DS satışı bittiğinde (tüm stok tükendi veya host `end_sale` çağırdı) `listings.last_sold_price`'ı güncelle.
  - Kullanılacak değer: o satıştaki `unit_price` (tek fiyat, DS'de değişmiyor)
  - Koşul: `sale.listing_id IS NOT NULL`
  - Dosya: `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py`

- [x] **F1-2** `direct_sale_commands.py` — Aynı yerde `listings.last_start_price`'ı da güncelle (DS başlangıç fiyatı → auction ile simetrik).

---

## Faz 2 — Hafif Fiyat Sinyali Endpoint'i

> Mevcut `GET /direct-sales/suggestions` → kaldırılır veya yönlendirilir.

- [ ] **F2-1** `backend/app/database_clickhouse.py` — `get_direct_sale_suggestions()` fonksiyonunu kaldır (artık kullanılmayacak). *(Şimdilik bırakıldı — ClickHouse analytics için ileride referans alınabilir)*

- [x] **F2-2** Yeni endpoint: `GET /listings/{listing_id}/price-signal`
  - Auth: `current_user` (host)
  - Sorgu: auctions + direct_sale_orders JOIN listings — attribute fallback hiyerarşisi
  - Sinyal ayrımı: DS vs auction ayrı avg, ağırlıklı `suggested_price` (DS %70, auction %30)
  - Fallback hiyerarşisi: PLAN.md §Fallback Hiyerarşisi'ne göre
  - Dosya: `backend/app/routers/listings.py`

- [x] **F2-3** `backend/app/schemas/` — `ListingPriceSignalOut` Pydantic modeli listings router'a inline eklendi.

---

## Faz 3 — DS Öneri Panelini Güncelle

- [x] **F3-1** `mobile/lib/widgets/direct_sale_panel.dart`
  - Chip sadece `_fromListing` modunda gösteriliyor, `listingId` pass ediliyor
  - `_SuggestionChip`: `stockCtrl` kaldırıldı, `listingId` eklendi, `listingPriceSignalProvider` kullanıyor

- [x] **F3-2** `mobile/lib/models/direct_sale.dart`
  - `DirectSaleSuggestion` → `ListingPriceSignal` olarak yeniden yazıldı
  - Kaldırıldı: `avg_demand`, `avg_conversion_rate`, `recommended_stock`
  - Eklendi: `ds_avg`, `auction_avg`

- [x] **F3-3** `mobile/lib/services/listing_service.dart`
  - `getPriceSignal(listingId)` metodu eklendi → `GET /listings/{id}/price-signal`
  - `mobile/lib/services/direct_sale_service.dart`: `getSuggestions()` kaldırıldı

- [x] **F3-4** `backend/app/routers/direct_sale.py`
  - `GET /direct-sales/suggestions` endpoint'i kaldırıldı

- [ ] **F3-5** `backend/app/schemas/direct_sale.py`
  - `DirectSaleSuggestionsOut` schema'sını kaldır *(ileride temizlenecek)*

---

## Faz 4 — İlan Ver AI'ını DS Verisiyle Besle

> Bu faz Faz 1 tamamlandıktan sonra otomatik olarak çalışır (listings.last_sold_price artık DS de içeriyor).
> Kod değişikliği gerekmeyebilir — sadece doğrulama gerekli.

- [x] **F4-1** `backend/app/routers/analytics.py` — `price-estimate` endpoint'inin `last_sold_price`'ı hem auction hem DS için doğru çekip çekmediği doğrulandı.
  - `listings.last_sold_price IS NOT NULL AND > 0` filtresi kullanıyor — kaynak agnostik.
  - F1 sonrası DS satışları da bu alanı dolduracağı için otomatik çalışır. Kod değişikliği gerekmedi.

- [ ] **F4-2** Opsiyonel: öneri çıktısında DS ve auction sinyallerini ayrı göster:
  - `ds_avg`: DS satışları ortalaması
  - `auction_avg`: Auction kapanış ortalaması
  - Mevcut `estimated_close_price` hesabı buna göre ağırlıklandırılır.

---

## Faz 5 — Auction Start Önerisini Güncelle

> Auction başlatma panelinde listing seçildiğinde DS gibi `price-signal` endpoint'i kullanılır.

- [ ] **F5-1** Flutter auction panelinde listing seçilince `GET /listings/{listingId}/price-signal` çağır.
- [ ] **F5-2** Çıktıyı auction bağlamında yorumla:
  - `suggested_price` → başlangıç fiyatı önerisi olarak göster (auction'da bu genellikle `auction_avg * 0.65–0.75`)
  - "Benzer müzayedeler X'te kapandı" mesajı ekle.

---

## Notlar

- Faz sırası önemli: F1 → F2 → F3 → F4 → F5
- F1 ve F2 backend değişikliği; deploy gerektirir
- F3 mobile değişikliği; app güncellemesi gerektirir
- F4 kod değişikliği gerekmeyebilir (sadece doğrulama)
- F5 hem backend hem mobile dokunuşu gerektirir
