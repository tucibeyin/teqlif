# Direct Sale — Task Listesi

> **Referans:** Tüm kararlar ve detaylar `direct_sale_plan.md`'de. Bu dosya yalnızca uygulama sırası ve ilerlemesi içindir.

> **Şerh:** Her task tamamlandığında:
> 1. İlgili kod commit edilir
> 2. Task `[x]` olarak işaretlenir
> 3. Tamamlanma tarihi ve saati eklenir: `[x] 2026-08-06 14:30`
>
> `[VPS]` etiketli tasklar SQL çalıştırma gerektirir — Claude SQL üretir, kullanıcı VPS'te çalıştırır, çıktı paylaşılır, task işaretlenir.

---

## Faz 0 — Kontrat

- [x] 2026-08-06 — `direct_sale_plan.md` tamamlandı (15 bölüm, tüm mimari kararlar)

---

## Faz 1 — Veritabanı Temeli

> **Referans:** `direct_sale_plan.md §4`
>
> **Bağımlılık:** Faz 0 ✅

- [x] 2026-08-06 — 1.1+1.2 `[VPS]` `direct_sales` + `direct_sale_orders` tabloları — migration: `zzzzf_add_direct_sales.py`, model: `direct_sale.py`
- [x] 2026-08-06 — 1.3 ClickHouse `direct_sale_events` DDL — `database_clickhouse.py`'e eklendi, servis restart'ında `CREATE TABLE IF NOT EXISTS` otomatik çalışır `[VPS deploy gerekir]`
- [ ] 1.4 Pydantic şemaları: `StartSaleRequest`, `PurchaseRequest`, `DirectSaleStateResponse`, `DirectSaleSummaryResponse`, `DirectSaleOrderResponse`

---

## Faz 2 — Backend Core (State Machine + Host API)

> **Referans:** `direct_sale_plan.md §1, §3, §5, §6`
>
> **Bağımlılık:** Faz 1 ✅

- [ ] 2.1 `AppException` subclass'ları: `DirectSaleNotFound`, `DirectSaleNotActive`, `DirectSaleSoldOut`, `DirectSaleInsufficientStock`, `DirectSaleAlreadyActive` — `ErrorMapper`'a ekle (→ §15.1)
- [ ] 2.2 `DirectSaleRedisManager`: `start()`, `pause()`, `resume()`, `end()` state geçişleri + Lua stok script'i (→ §5.3)
- [ ] 2.3 `POST /direct-sales/start` endpoint — satış başlat, Redis LIFECYCLE key yükle, `direct_sale_started` WS broadcast (→ §3.2, §6.2)
- [ ] 2.4 `POST /direct-sales/{id}/pause` + `POST /direct-sales/{id}/resume` endpoint'leri — WS broadcast (→ §3.1, §6.2)
- [ ] 2.5 `POST /direct-sales/{id}/end` endpoint — LIFECYCLE cache temizle, `direct_sale_ended` WS broadcast (→ §3.1, §6.2)
- [ ] 2.6 `POST /direct-sales/{id}/cancel` endpoint — `orders_voided` logic, sipariş status güncelle, `direct_sale_cancelled` WS broadcast (→ §1.2, §6.2)
- [ ] 2.7 `GET /direct-sales/{stream_id}/state` endpoint — Redis hash'ten direkt oku, cache yok (→ §3.4, §5.4)

---

## Faz 3 — Purchase Flow (Satın Alma)

> **Referans:** `direct_sale_plan.md §3.3, §5.3, §9`
>
> **Bağımlılık:** Faz 2 ✅

- [ ] 3.1 `POST /direct-sales/{id}/purchase` endpoint — Lua atomik stok azalt, `direct_sale_orders` kaydı oluştur, `direct_sale_purchased` WS broadcast (→ §3.3, §5.3); rate limit: 10/min per user
- [ ] 3.2 `sold_out` otomatik geçiş — `remaining_stock == 0` sonrası `direct_sale_sold_out` broadcast, 5 sn timer → `direct_sale_ended` (end_reason: `sold_out`) (→ §1.2)
- [ ] 3.3 Satın alma DirectMessage — buyer + host'a DM, WS broadcast her iki kanala, deep link formatı (→ §9.2, §9.4)
- [ ] 3.4 `GET /direct-sales/{id}/summary` endpoint — rol bazlı (buyer/seller) response (→ §14.2)
- [ ] 3.5 `GET /direct-sales/{id}/orders` endpoint — sadece host yetkisi (→ §10.4)

---

## Faz 4 — Flutter UI

> **Referans:** `direct_sale_plan.md §2, §2.B, §2.C, §10, §11, §12, §13, §14`
>
> **Bağımlılık:** Faz 3 ✅

- [ ] 4.1 ARB key'leri ekle — TR/EN/RU (~60 key, 13 grup) → `sync_translations.py` çalıştır (→ §13); `[VPS]`
- [ ] 4.2 Dart modelleri: `DirectSale`, `DirectSaleOrder`, `CommercePurchase`, `CommerceSale` (→ §10.3)
- [ ] 4.3 `DirectSaleService` — tüm endpoint çağrıları (start, pause, resume, end, cancel, purchase, state, summary, orders)
- [ ] 4.4 `DirectSaleViewModel` (`AsyncNotifier`) — host state machine: form, proof dialog, kontrol butonları (→ §12; MVVM ADR §8)
- [ ] 4.5 `DirectSaleViewerViewModel` (`AsyncNotifier`) — viewer state machine: lokal purchase state, stok sayacı (→ §2.B.4)
- [ ] 4.6 `CommercePanelWrapper` — `_CommerceMode` lokal state, WS event yönlendirme, idle chip (→ §12.2, §12.3, §12.6)
- [ ] 4.7 `DirectSalePanel` host view — başlat formu (listing seç / manuel), proof dialog, aktif satış kontrolleri (duraklat/devam/bitir/iptal), özet kart (→ §2, §11)
- [ ] 4.8 `DirectSalePanel` viewer view — tıklanabilir ürün kartı, satın alma bottom sheet (stepper + fiyat + badge), state bazlı animasyonlar (→ §2.B, §2.C)
- [ ] 4.9 `/me/commerce/purchases` + `/me/commerce/sales` ekranları — `PurchasesScreen` ve `SalesScreen` unified model ile güncelle, badge mantığı (→ §10.1, §10.2, §10.5)
- [ ] 4.10 `DirectSaleDetailScreen` — `teqlif://direct-sale/{id}` deep link, rol bazlı görünüm (buyer/seller), "Alıcılar" bottom sheet (→ §14.2, §10.4)

---

## Faz 5 — ClickHouse Tracking

> **Referans:** `direct_sale_plan.md §7`
>
> **Bağımlılık:** Faz 4 ✅

- [ ] 5.1 Backend dual-write — `sale_started`, `purchase_completed`, `sale_ended`, `sale_cancelled` event'leri `direct_sale_events`'e `fire_and_forget` yaz (→ §7.4)
- [ ] 5.2 Backend `user_events` dual-write — `purchase_completed` → `user_events` ML sinyali + `update_user_preference_embedding` kuyruğu (→ §7.2)
- [ ] 5.3 Flutter client-side events — `sale_impression` (panel görününce) + `purchase_intent` (bottom sheet açılınca) → mevcut `POST /api/analytics/user-events` (→ §7.4)

---

## Faz 6 — ML / AI

> **Referans:** `direct_sale_plan.md §7.5, §8`
>
> **Bağımlılık:** Faz 5 ✅ + minimum 2-4 hafta gerçek satış verisi (ADR §3.3)

- [ ] 6.1 Fiyat önerisi modeli — geçmiş `unit_price` + dönüşüm oranı bazlı
- [ ] 6.2 Talep tahmini — geçmiş `viewer_count` + satılan adet bazlı

---

## Açık Kalan Kararlar (Faz Başında Kapatılacak)

> **Referans:** `direct_sale_plan.md §15.4`

| Soru | Faz |
|---|---|
| `purchase_intent` ve `sale_impression` Flutter client'ten mi, backend'den mi? | Faz 3 |
| `GET /me/commerce/*` EPHEMERAL cache key formatı | Faz 2 |
| AR (Arapça) ARB key çevirileri | Faz 4 |
| `DirectSaleViewModel` state class tasarımı (sealed class mı?) | Faz 4 |
