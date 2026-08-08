# Aktivite Paneli (TEKLİFLER → AKTİVİTE) — Mimari Plan

Son güncelleme: 2026-08-08

---

## Motivasyon

Host ekranında mevcut "TEKLİFLER" paneli sadece auction tekliflerini göstermektedir.
Direct Sale satın alımları bu panelde yer almaz; yalnızca chat duyurusu olarak geçer.

**Hedef:** Paneli generikleştirip host'un başlattığı tüm ticaret aktivitelerini
(auction teklifi, DS satın alımı) tek bir, MVVM uyumlu, UI library'e taşınmış
bileşen üzerinden göstermek.

---

## Mevcut Durum

### Sorunlar

| # | Katman | Sorun |
|---|---|---|
| 1 | View | `_bidGroups`, `_bidsVisible`, `_bidsPanelTop`, `_onBidAdded`, `_loadBidHistory` hepsi `_HostStreamScreenState` içinde — MVVM ihlali |
| 2 | View | `_BidGroup`, `_BidsOverlay`, `_BidsToggleTab` aynı dosyada private class olarak gömülü — UI library'e taşınmamış |
| 3 | Model | `_BidGroup.bids` → `List<({String bidder, double amount})>` — auction'a sabit, DS bilgisini tutamaz |
| 4 | Callback | DS `DIRECT_SALE_PURCHASED` WS eventi `DirectSalePanel` içinde kalır; host screen görmez |
| 5 | Backend | `GET /auction/{id}/bids` yalnızca auction — stream bazlı DS orders endpoint'i yok |
| 6 | i18n | `lblBidsUpper` ve `auctionBidsHeader` duplicate; her ikisi de "TEKLİFLER" (auction-spesifik) |

---

## Hedef Mimari

### Katman Diyagramı

```
host_stream_screen.dart (View)
    │ ref.watch(commerceActivityProvider)
    │ onBidAdded  ──────────────────────────────────┐
    │ onPurchaseAdded ──────────────────────────────┐│
    ▼                                               ││
CommerceActivityNotifier (ViewModel/StateNotifier)  ││
    │  addBidEvent()      ◄──────────────────────────┘│
    │  addPurchaseEvent() ◄───────────────────────────┘
    │  loadHistory(streamId) → StreamService
    │  state: List<CommerceEventGroup>
    ▼
StreamService.fetchCommerceActivity(streamId)
    │
    ▼
GET /api/streams/{stream_id}/commerce-activity (Backend)
    │
    ▼
GetCommerceActivityQuery
    │  SELECT bid UNION ALL SELECT ds_order WHERE stream_id
    │  ORDER BY created_at DESC
    ▼
DB: bids JOIN users  +  direct_sale_orders JOIN direct_sales JOIN users
```

---

## Backend

### Yeni Endpoint

```
GET /api/streams/{stream_id}/commerce-activity
Auth: current_user (host)
```

**SQL (UNION):**
```sql
SELECT
    'bid'           AS event_type,
    u.username      AS actor,
    b.amount        AS value,
    1               AS quantity,
    NULL            AS group_title,
    b.created_at
FROM bids b
JOIN users u ON u.id = b.bidder_id
WHERE b.stream_id = :stream_id

UNION ALL

SELECT
    'ds_purchase'   AS event_type,
    u.username      AS actor,
    o.unit_price    AS value,
    o.quantity,
    ds.title        AS group_title,
    o.created_at
FROM direct_sale_orders o
JOIN direct_sales ds ON ds.id = o.sale_id
JOIN users u ON u.id = o.buyer_id
WHERE ds.stream_id = :stream_id

ORDER BY created_at DESC
LIMIT 100
```

**Response Schema:**
```python
class CommerceActivityItem(BaseModel):
    event_type: Literal["bid", "ds_purchase"]
    actor: str          # bidder_username / buyer_username
    value: float        # bid amount / unit_price
    quantity: int = 1   # auction her zaman 1, DS actual qty
    group_title: str | None  # ürün adı (auction item / DS title)
    created_at: datetime
```

**Mevcut endpoint korunur** — geriye dönük uyumluluk:
```
GET /api/auction/{stream_id}/bids  →  değişmez
```

---

## Flutter — Model

**Dosya:** `mobile/lib/models/commerce_activity.dart` *(yeni)*

```dart
sealed class CommerceEvent {
  const CommerceEvent();
  String get actor;
  DateTime get createdAt;
}

class AuctionBidEvent extends CommerceEvent {
  final String actor;
  final double amount;
  final DateTime createdAt;
  const AuctionBidEvent({required this.actor, required this.amount, required this.createdAt});
}

class DsPurchaseEvent extends CommerceEvent {
  final String actor;
  final double unitPrice;
  final int quantity;
  final DateTime createdAt;
  const DsPurchaseEvent({required this.actor, required this.unitPrice, required this.quantity, required this.createdAt});
}

class CommerceEventGroup {
  final String? title;          // ürün adı / DS başlığı
  final String groupType;       // "auction" | "ds"
  final List<CommerceEvent> events;
  CommerceEventGroup({this.title, required this.groupType}) : events = [];
}
```

---

## Flutter — StateNotifier (ViewModel)

**Dosya:** `mobile/lib/providers/commerce_activity_provider.dart` *(yeni)*

```dart
class CommerceActivityNotifier
    extends StateNotifier<List<CommerceEventGroup>> {

  CommerceActivityNotifier() : super([]);

  // WS'ten gelen anlık auction teklifi
  void addBidEvent(String bidder, double amount, String? itemName) {
    final groups = List<CommerceEventGroup>.from(state);
    if (groups.isEmpty || groups.last.groupType != 'auction' ||
        groups.last.title != itemName) {
      groups.add(CommerceEventGroup(title: itemName, groupType: 'auction'));
    }
    groups.last.events.insert(0, AuctionBidEvent(
      actor: bidder, amount: amount, createdAt: DateTime.now(),
    ));
    state = groups;
  }

  // WS'ten gelen anlık DS satın alımı
  void addPurchaseEvent(String buyer, double price, int qty, String? title) {
    final groups = List<CommerceEventGroup>.from(state);
    if (groups.isEmpty || groups.last.groupType != 'ds' ||
        groups.last.title != title) {
      groups.add(CommerceEventGroup(title: title, groupType: 'ds'));
    }
    groups.last.events.insert(0, DsPurchaseEvent(
      actor: buyer, unitPrice: price, quantity: qty, createdAt: DateTime.now(),
    ));
    state = groups;
  }

  void resetGroups() => state = [];

  Future<void> loadHistory(int streamId) async {
    final items = await StreamService.fetchCommerceActivity(streamId);
    state = _buildGroups(items);
  }

  List<CommerceEventGroup> _buildGroups(List<Map<String, dynamic>> items) { ... }
}

final commerceActivityProvider = StateNotifierProvider
    .autoDispose<CommerceActivityNotifier, List<CommerceEventGroup>>(
  (ref) => CommerceActivityNotifier(),
);
```

---

## Flutter — Widget (UI Library)

**Yeni dosyalar:**
```
mobile/lib/ui_library/components/live/
  commerce_activity_overlay.dart    ← _BidsOverlay yerine
  commerce_activity_toggle.dart     ← _BidsToggleTab yerine
```

`CommerceActivityOverlay`, event tipine göre farklı satır render eder:

```dart
switch (event) {
  AuctionBidEvent bid => _BidRow(bid),
  // #N | @bidder | 1.200 ₺  (altın #1, mavi diğerleri)

  DsPurchaseEvent ds => _DsPurchaseRow(ds),
  // 🛍 | @buyer 2× | 450 ₺  (yeşil, adet rozeti)
}
```

Grup başlıkları:
```dart
groupType == 'auction'
  ? loc.t('lblCommerceGroupAuction')  // "AÇIK ARTIRMA"
  : loc.t('lblCommerceGroupDs')       // "DİREKT SATIŞ"
```

---

## Flutter — Callback Zinciri

```
AuctionPanel.onBidAdded(bidder, amount, itemName)
    → CommercePanelWrapper
    → host_stream_screen._onBidAdded()
    → commerceActivityProvider.notifier.addBidEvent()

DirectSalePanel  [YENİ CALLBACK]
  onPurchaseAdded(buyer, price, qty, title)
    → CommercePanelWrapper
    → host_stream_screen._onPurchaseAdded()   [YENİ]
    → commerceActivityProvider.notifier.addPurchaseEvent()
```

`DirectSalePanel`'de `DIRECT_SALE_PURCHASED` WS eventi zaten işleniyor.
Bu noktaya `onPurchaseAdded?.call(...)` eklemek yeterli.

---

## i18n

| Key | TR | EN | RU | AR |
|---|---|---|---|---|
| `lblCommerceActivity` | `AKTİVİTE` | `ACTIVITY` | `АКТИВНОСТЬ` | `النشاط` |
| `lblCommerceGroupAuction` | `AÇIK ARTIRMA` | `AUCTION` | `АУКЦИОН` | `المزاد` |
| `lblCommerceGroupDs` | `DİREKT SATIŞ` | `DIRECT SALE` | `ПРЯМАЯ ПРОДАЖА` | `بيع مباشر` |

`lblBidsUpper` → `lblCommerceActivity` olarak rename (veya değer güncellenir, key kalır).

---

## Uygulama Sırası

1. **Backend** — `GetCommerceActivityQuery` + `GET /streams/{id}/commerce-activity`
2. **Flutter Model** — `commerce_activity.dart` sealed class'lar
3. **Flutter Service** — `StreamService.fetchCommerceActivity()`
4. **Flutter Provider** — `CommerceActivityNotifier` StateNotifier
5. **Flutter Widget** — `CommerceActivityOverlay` + `CommerceActivityToggle` (ui_library)
6. **Flutter Panel** — `DirectSalePanel.onPurchaseAdded` callback ekle
7. **Flutter Panel** — `CommercePanelWrapper` callback zinciri
8. **Flutter Screen** — `host_stream_screen.dart` state temizliği + provider entegrasyonu
9. **i18n** — 3 yeni key × 4 dil

---

## Kararlar (2026-08-08)

| # | Soru | Karar |
|---|---|---|
| 1 | Panel etiketi | **AKTİVİTE** — hem auction hem DS'i kapsayan nötr terim |
| 2 | DS satır stili | **🛍 ikonu + @buyer + fiyat** — sıra no yok; adet > 1 ise `2×` rozeti |
| 3 | Grup başlıkları | **Tip + ürün adı** — `"AÇIK ARTIRMA · iPhone 15"` / `"DİREKT SATIŞ · Çanta"` |
| 4 | Geçmiş yükleme | **Evet, auction + DS birlikte** — yeni unified endpoint kullanılır |
| 5 | Panel açılma | **Her iki tipte** — ilk auction teklifi veya ilk DS satın alımı paneli açar |
| 6 | i18n key stratejisi | **Yeni key ekle, eski silinmez** — `lblCommerceActivity` eklenir, `lblBidsUpper` değeri güncellenir |
