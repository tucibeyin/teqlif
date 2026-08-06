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
- [x] 2026-08-06 — 1.4 Pydantic şemaları: `DirectSaleStartIn`, `DirectSalePurchaseIn`, `DirectSaleCancelIn`, `DirectSaleStateOut`, `DirectSaleSummaryOut`, `DirectSaleOrderOut` — `schemas/direct_sale.py`

---

## Faz 2 — Backend Core (State Machine + Host API)

> **Referans:** `direct_sale_plan.md §1, §3, §5, §6`
>
> **Bağımlılık:** Faz 1 ✅

- [x] 2026-08-06 — 2.1 `AppException` subclass'ları: `DirectSaleNotFound`, `DirectSaleNotActive`, `DirectSaleSoldOut`, `DirectSaleInsufficientStock`, `DirectSaleAlreadyActive` — `exceptions.py`'e eklendi
- [x] 2026-08-06 — 2.2 `DirectSaleRedisManager`: `start()`, `pause()`, `resume()`, `end()`, `cancel()`, `decrement_stock()` (Lua), `get_state()`, `publish_direct_sale()` — `direct_sale_redis.py`
- [x] 2026-08-06 — 2.3 `POST /direct-sales/{stream_id}/start` — DB kaydı + Redis LIFECYCLE + `direct_sale_started` WS broadcast — `direct_sale_commands.py` + `direct_sale.py` router
- [x] 2026-08-06 — 2.4 `POST /direct-sales/{id}/pause` + `/resume` — WS broadcast ile birlikte
- [x] 2026-08-06 — 2.5 `POST /direct-sales/{id}/end` — Redis temizle, `direct_sale_ended` WS broadcast
- [x] 2026-08-06 — 2.6 `POST /direct-sales/{id}/cancel` — `orders_voided` logic (order status güncelle), `direct_sale_cancelled` WS broadcast
- [x] 2026-08-06 — 2.7 `GET /direct-sales/{stream_id}/state` — Redis hash'ten direkt oku, `idle` fallback

---

## Faz 3 — Purchase Flow (Satın Alma)

> **Referans:** `direct_sale_plan.md §3.3, §5.3, §9`
>
> **Bağımlılık:** Faz 2 ✅

- [x] 2026-08-06 — 3.1 `POST /direct-sales/{id}/purchase` — Lua atomik stok, order kaydı, `direct_sale_purchased` WS broadcast; rate limit 10/min
- [x] 2026-08-06 — 3.2 `sold_out` otomatik geçiş — stok=0 → `set_sold_out()` Redis + DB, `direct_sale_sold_out` broadcast; `scheduled_end_at` DB yazımı → `direct_sale_scheduler` (10s poll, FOR UPDATE SKIP LOCKED, durable)
- [x] 2026-08-06 — 3.3 Satın alma DM — aynı commit'te `DirectMessage(host→buyer)`, WS broadcast `dm:{buyer}` + `dm:{host}`, `push_notification`, deep link formatı
- [x] 2026-08-06 — 3.4 `GET /direct-sales/{id}/summary` — rol bazlı (seller: toplam gelir/adet/order sayısı; buyer: kendi siparişleri özeti)
- [x] 2026-08-06 — 3.5 `GET /direct-sales/{id}/orders` — sadece host, buyer JOIN, `DirectSaleOrderOut` listesi

---

## Faz 4 — Flutter UI

> **Referans:** `direct_sale_plan.md §2, §2.B, §2.C, §10, §11, §12, §13, §14`
>
> **Bağımlılık:** Faz 3 ✅

- [x] 2026-08-06 — 4.1 ARB key'leri eklendi — 63 key, 14 grup, TR/EN/RU/AR (AR şimdilik EN fallback) → `[VPS]` `git pull && python sync_translations.py` tamamlandı
- [x] 2026-08-06 — 4.2 Dart modelleri: `DirectSaleState`, `DirectSaleOrder`, `DirectSaleSummary`, `CommercePurchase`, `CommerceSale`, `CommerceType` — `mobile/lib/models/direct_sale.dart`
- [x] 2026-08-06 — 4.3 `DirectSaleService` — start/pause/resume/end/cancel/purchase/getState/getSummary/getOrders — `mobile/lib/services/direct_sale_service.dart`
- [x] 2026-08-06 — 4.4 `DirectSaleHostNotifier` (`StateNotifier`) — WS bağlantısı + host state machine — `mobile/lib/providers/direct_sale_provider.dart`
- [x] 2026-08-06 — 4.5 `DirectSaleViewerNotifier` + `DirectSaleViewerState` (`StateNotifier`) — viewer purchase flow + stok sayacı — `mobile/lib/providers/direct_sale_provider.dart`
- [x] 2026-08-06 — 4.6 `CommercePanelWrapper` — `_CommerceMode` local state + force bayrakları, idle host chip (açık artırma / direkt satış), viewer hint — `mobile/lib/widgets/commerce_panel_wrapper.dart`
- [x] 2026-08-06 — 4.7+4.8 `DirectSalePanel` — host: başlat formu (listing seç / manuel + proof dialog), aktif kontroller (duraklat/devam/bitir/iptal dialoglı); viewer: ürün kartı, adet seçici, satın alma bottom sheet — `mobile/lib/widgets/direct_sale_panel.dart`
- [x] 2026-08-06 — 4.9 `/me/commerce/purchases` + `/me/commerce/sales` ekranları — `PurchasesScreen` ve `SalesScreen` unified model ile güncelle, badge mantığı + Alıcılar bottom sheet (→ §10.1, §10.2, §10.5)
- [x] 2026-08-06 — 4.10 `DirectSaleDetailScreen` — `teqlif://direct-sale/{id}` deep link, rol bazlı görünüm (buyer/seller), "Alıcılar" bottom sheet (→ §14.2, §10.4)

---

## Faz 5 — ClickHouse Tracking

> **Referans:** `direct_sale_plan.md §7`
>
> **Bağımlılık:** Faz 4 ✅

- [x] 2026-08-06 — 5.1 Backend dual-write — `sale_started`, `purchase_completed`, `sale_ended`, `sale_cancelled` event'leri `direct_sale_events`'e `fire_and_forget` yaz (→ §7.4)
- [x] 2026-08-06 — 5.2 Backend `user_events` dual-write — `purchase_completed` → `user_events` ML sinyali + `update_user_preference_embedding` kuyruğu (→ §7.2)
- [x] 2026-08-06 — 5.3 Flutter client-side events — `sale_impression` (panel görününce) + `purchase_intent` (bottom sheet açılınca) → mevcut `POST /api/analytics/user-events` (→ §7.4)

---

## Faz 6 — ML / AI

> **Referans:** `direct_sale_plan.md §7.5, §8`
>
> **Bağımlılık:** Faz 5 ✅ + minimum 2-4 hafta gerçek satış verisi (ADR §3.3)

- [x] 6.1 Fiyat önerisi modeli — geçmiş `unit_price` + dönüşüm oranı bazlı — 2026-08-07
- [x] 6.2 Talep tahmini — geçmiş `viewer_count` + satılan adet bazlı — 2026-08-07

---

## Teknik Borç (Daha Sonra Yapılacaklar)

> Her faz sonunda tespit edilen bağımlılıklar ve refactor ihtiyaçları buraya eklenir.
> Kritiklik: 🔴 Yayına çıkmadan önce | 🟡 Faz tamamlanmadan önce | 🟢 Fırsatta

| # | Konu | Neden | Kritiklik | Tespit Fazı |
|---|------|-------|-----------|-------------|
| T-1 | ~~`auction_utils.publish_auction()` → `broadcast_to_stream_viewers()` olarak yeniden adlandırılmalı~~ | ✅ 2026-08-07 | 🟢 | Faz 2 |
| T-2 | ~~Flutter `CommercePanelWrapper` WS event routing'i — `DirectSaleViewerNotifier` üçüncü duplicate WS bağlantısı açıyordu~~ | ✅ 2026-08-07 — viewer notifier'dan WS kaldırıldı; `purchaseStatus` tek kaynak | 🔴 | Faz 2 |
| T-3 | ~~**[SİSTEM GENELİ]** Tüm codebase'de `asyncio.create_task + sleep → state değişikliği` pattern'ini audit et~~ | ✅ 2026-08-07 — ihlal yok; `webhooks.py` dev-only fallback olarak belgelenmiş | 🟡 | Faz 3 |

---

## Açık Kalan Kararlar (Faz Başında Kapatılacak)

> **Referans:** `direct_sale_plan.md §15.4`

| Soru | Faz |
|---|---|
| `purchase_intent` ve `sale_impression` Flutter client'ten mi, backend'den mi? | Faz 3 |
| `GET /me/commerce/*` EPHEMERAL cache key formatı | Faz 2 |
| AR (Arapça) ARB key çevirileri | Faz 4 |
| `DirectSaleViewModel` state class tasarımı (sealed class mı?) | Faz 4 |
