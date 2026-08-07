# Commerce Altyapısı — Görev Listesi

> **Kaynak:** `documents/commerce/PLAN.md`  
> **Kapsam:** Backend · Flutter (ViewModel katmanı)  
> **Durum:** `[ ]` Bekliyor · `[/]` Devam ediyor · `[x]` Tamamlandı  
> **Deploy:** Backend değişikliği her fazın sonunda `git pull && sudo systemctl restart teqlif` gerektirir.

---

## Faz 1 — Backend

### T-01: `get_stream_commerce_snapshot` use-case oluştur

**Dosya:** `backend/app/use_cases/stream/commerce_snapshot.py` (yeni)

- [x] `backend/app/use_cases/stream/` dizini oluştur
- [x] `commerce_snapshot.py` dosyasını yaz
  - [x] `GetAuctionStateQuery().execute(stream_id)` çağrısı
  - [x] `ds_redis.get_state(stream_id)` çağrısı
  - [x] `_DS_INACTIVE = frozenset({"ended", "cancelled"})` sabiti
  - [x] `{"auction": ..., "direct_sale": ...}` dict döner
- [x] `backend/app/use_cases/stream/__init__.py` ekle (boş veya re-export)

---

### T-02: Auction router'daki domain import'unu temizle

**Dosya:** `backend/app/routers/auction.py`

- [x] `from app.use_cases.direct_sales import direct_sale_redis as ds_redis` satırını kaldır (L198 inline import)
- [x] `from app.use_cases.stream.commerce_snapshot import get_stream_commerce_snapshot` ekle (modül seviyesi)
- [x] `auction_ws` endpoint'inde snapshot çağrısını güncelle:
  - [x] `GetAuctionStateQuery().execute(stream_id)` → `snapshot["auction"]`
  - [x] DS inline if/send bloğu → `if snapshot["direct_sale"]: await websocket.send_json(...)`
- [ ] Davranış doğrula: bağlanan istemci hâlâ auction + aktif DS state'ini alıyor

**Deploy:** Backend restart gerekli.

---

### T-03: Outbox'ı direct sale event'lerine genişlet

**Dosya:** `backend/app/core/commerce_outbox.py` (yeni) veya `auction_outbox.py` genişletme

- [x] DS outbox için Redis key şeması belirle: `ds:events:{stream_id}` Redis Stream (auction_outbox ile aynı mekanizma)
- [x] `ds_outbox_push(stream_id, event_dict)` async fonksiyonu yaz (`backend/app/core/commerce_outbox.py`)
  - [x] XADD ile Redis Stream'e yaz, maxlen=100
  - [x] Key TTL: 24h (LIFECYCLE)
- [x] `ds_outbox_replay(stream_id, count=10)` async fonksiyonu yaz
  - [x] XREVRANGE ile son N event'i çek, max_age_seconds=30
  - [x] JSON parse edip list döner
- [x] `direct_sale_commands.py` içinde event yayınlarına `ds_outbox_push` ekle:
  - [x] `direct_sale_purchased` sonrası
  - [x] `direct_sale_paused` sonrası
  - [x] `direct_sale_resumed` sonrası
  - [x] `direct_sale_sold_out` sonrası
  - [x] `direct_sale_ended` sonrası
  - [x] `direct_sale_cancelled` sonrası
- [x] `auction.py` WS endpoint'ine `ds_outbox_replay` çağrısı ekle (auction outbox replay'in hemen ardından)
- [ ] Test: satın alım sırasında bağlantı kesip yeniden bağlanan viewer'ın doğru stok sayısını aldığını kontrol et

**Deploy:** Backend restart gerekli.

---

## Faz 2 — Flutter

### T-04: `StreamCommerceNotifier<S>` base class oluştur

**Dosya:** `mobile/lib/providers/stream_commerce_notifier.dart` (yeni)

- [x] Dosyayı oluştur: `mobile/lib/providers/stream_commerce_notifier.dart`
- [x] `StreamCommerceNotifier<S> extends StateNotifier<S>` abstract class
  - [x] `streamId` field
  - [x] `_channel`, `_sub`, `_heartbeat`, `_reconnecting`, `_reconnectAttempt` field'ları
  - [x] `_wsBase` getter
  - [x] `abstract void onCommerceEvent(String type, Map<String, dynamic> json)` metodu
  - [x] `_connect()` — token auth + heartbeat
  - [x] `_onRaw()` — JSON parse + `onCommerceEvent` dispatch
  - [x] `_scheduleReconnect()` — exponential backoff
  - [x] `_wsLog()` helper
  - [x] `dispose()` override
- [x] `DirectSaleViewerNotifier` bu class'ı extend etmez — class docstring'de belirtildi
- [x] `flutter analyze` — 0 hata

---

### T-05: `AuctionNotifier`'ı base class'a migrate et

**Dosya:** Auction notifier dosyası (auction_provider.dart veya mevcut konum)

- [x] `extends StateNotifier<AuctionState>` → `extends StreamCommerceNotifier<AuctionState>` değiştirildi
- [x] Import'a `stream_commerce_notifier.dart` eklendi
- [x] Constructor güncellendi: `super(streamId, AuctionState.idle())`
- [x] `onCommerceEvent` implement edildi — `state`, `auction_ended_by_buy_it_now` işleniyor; diğerleri görmezden geliniyor
- [x] WS altyapısı kaldırıldı (base class'a taşındı)
- [x] `flutter analyze` — hata yok
- [ ] Manuel test: auction başlat, teklif ver, duraklat, devam et, bitir

---

### T-06: `DirectSaleHostNotifier`'ı base class'a migrate et

**Dosya:** `mobile/lib/providers/direct_sale_provider.dart`

- [x] `extends StateNotifier<DirectSaleState>` → `extends StreamCommerceNotifier<DirectSaleState>` değiştirildi
- [x] Import'a `stream_commerce_notifier.dart` eklendi; `dart:async`, `dart:convert`, `dart:math`, `web_socket_channel`, `config/api`, `storage_service` kaldırıldı
- [x] Constructor güncellendi: `super(streamId, DirectSaleState.idle())`
- [x] `onCommerceEvent` implement edildi — `direct_sale_*` filtreliyor, `_applyWsEvent` çağırıyor
- [x] WS altyapısı kaldırıldı (`_connect`, `_scheduleReconnect`, `dispose`, tüm WS field'ları)
- [x] `flutter analyze` — hata yok
- [ ] Manuel test: DS başlat, duraklat, devam et, bitir, satın al

---

## Faz 3 — Dokümantasyon

### T-07: `architectural_decisions.md` §10 ekle

**Dosya:** `documents/architectural_decisions.md`

- [x] §10 "Commerce WS Altyapısı — `StreamCommerceNotifier<S>`" bölümü eklendi
- [x] Header "Son güncelleme" satırı güncellendi
- [x] `DirectSaleViewerNotifier` extend etmez kuralı eklendi
- [x] 3. commerce tipi ekleme adımları listelendi

---

## Tamamlanma Kriterleri

- [x] `flutter analyze` — 0 hata, 0 yeni uyarı
- [x] `AuctionNotifier` ve `DirectSaleHostNotifier` WS kodu içermiyor
- [x] Router'da `direct_sale_redis` import'u yok
- [ ] Bağlantı kesip yeniden bağlanan viewer doğru stok sayısını görüyor (T-03 — deploy sonrası test)
- [x] ADR güncellendi
