# Commerce Altyapısı — Refactor Planı

> **Versiyon:** 1.0  
> **Tarih:** Ağustos 2026  
> **Kaynak:** Direct Sale post-launch mimari analizi + auction sistemi karşılaştırması  
> **Kapsam:** Backend · Flutter (ViewModel katmanı)  
> **Görev Takibi:** `documents/commerce/TASK.md`  
> **ADR:** `documents/architectural_decisions.md` §10 — Commerce WS Altyapısı

---

## İçindekiler

1. [Problem Analizi](#1-problem-analizi)
2. [Hedef Mimari](#2-hedef-mimari)
3. [Backend — Faz 1](#3-backend--faz-1)
   - [3.1 `get_stream_commerce_snapshot` use-case](#31-get_stream_commerce_snapshot-use-case)
   - [3.2 Outbox'ı Direct Sale Event'lerine Genişlet](#32-outboxı-direct-sale-eventlerine-genişlet)
4. [Flutter — Faz 2](#4-flutter--faz-2)
   - [4.1 `StreamCommerceNotifier<S>` Base Class](#41-streamcommercenotifiers-base-class)
   - [4.2 `AuctionNotifier` Migration](#42-auctionnotifier-migration)
   - [4.3 `DirectSaleHostNotifier` Migration](#43-directsalehostnotifier-migration)
5. [Dokümantasyon — Faz 3](#5-dokümantasyon--faz-3)
6. [Değişmeyen Parçalar](#6-değişmeyen-parçalar)
7. [3. Commerce Tipi Eklemek](#7-3-commerce-tipi-eklemek)

---

## 1. Problem Analizi

Direct Sale sistemi Auction sistemiyle aynı WS kanalını paylaşıyor; ancak altyapı ayrı ayrı implement edilmiş durumda. Dört somut sorun var:

### 1.1 WS Altyapısı Kopyalanmış (~80 satır tekrar)

`AuctionNotifier` ve `DirectSaleHostNotifier` içinde neredeyse birebir aynı kod:

| Kod bloğu | Her iki notifier'da var mı? |
|---|---|
| `_channel`, `_sub`, `_heartbeat`, `_reconnecting`, `_reconnectAttempt` field'ları | ✅ |
| `_wsBase` getter (kBaseUrl http→ws dönüşümü) | ✅ |
| `_connect()` — WebSocket bağlantısı + token auth + heartbeat | ✅ |
| `_scheduleReconnect()` — exponential backoff (1.5^n, 1s–60s clamp) | ✅ |
| `dispose()` — heartbeat/sub/channel temizleme | ✅ |

**Risk:** Bir bug veya iyileştirme iki yerde ayrı ayrı düzeltilmek zorunda. Geçmişte ya bir yerden kaçtı ya da kaçacak.

### 1.2 Auction Router'da Domain İçe Aktarımı

```python
# backend/app/routers/auction.py — L198
from app.use_cases.direct_sales import direct_sale_redis as ds_redis
```

Router, başka bir domain'in use-case katmanına doğrudan bağımlı. Bu Dependency Rule ihlali: Router → Domain Use Case bağımlılığı olmamalı, Router → Use Case → Domain olmalı.

### 1.3 Outbox Yalnızca Auction Event'lerini Kapsamıyor

`auction_outbox.py` sadece auction event'lerini saklar. WS bağlantısı sırasında gerçekleşen `direct_sale_purchased`, `direct_sale_paused` gibi event'ler bağlantı sonrası gelen izleyiciye iletilemiyor.

**Etki:** Viewer, satın alım gerçekleşirken bağlantı kesip geri gelirse eski stok sayısını görür. Host kısa bir ping sonucu kaybederse state tutarsızlaşabilir.

### 1.4 Viewer Notifier Scope'u Doğru Ama Belgelenmemiş

`DirectSaleViewerNotifier` kasıtlı olarak WS bağlantısı açmıyor — `DirectSaleHostNotifier` tek WS kaynağı ve tüm state değişikliklerini yayıyor. Bu doğru karar, ancak ileride `DirectSaleViewerNotifier` içinde biri WS açmaya kalkışırsa ikili bağlantı hatası çıkar. Dokümante edilmeli.

---

## 2. Hedef Mimari

```
┌─────────────────────────────────────────────────────────────┐
│                     CommercePanelWrapper                    │
│  _resolveMode() → hangi panel gösterileceğine karar verir  │
│  _forceAuction / _forceDirectSale  (UI intent bayrakları)  │
└──────────────┬──────────────────────────┬───────────────────┘
               │                          │
      ┌────────▼────────┐       ┌─────────▼────────┐
      │  AuctionPanel   │       │ DirectSalePanel   │
      │  (View — pure)  │       │  (View — pure)    │
      └────────┬────────┘       └─────────┬─────────┘
               │                          │
      ┌────────▼────────┐       ┌─────────▼─────────────┐
      │ AuctionNotifier │       │ DirectSaleHostNotifier │
      │  (ViewModel)    │       │  (ViewModel)           │
      └────────┬────────┘       └─────────┬──────────────┘
               │                          │
               └──────────┬───────────────┘
                           │ extends
                  ┌────────▼──────────────┐
                  │ StreamCommerceNotifier │  ← YENİ
                  │      <S>              │
                  │  WS + reconnect +     │
                  │  heartbeat + dispose  │
                  └───────────────────────┘
                           │
                    WS /auction/{id}/ws
                           │
                  ┌────────▼───────────────┐
                  │   Backend WS Endpoint  │
                  │  auction + direct_sale │
                  │  events aynı kanaldan  │
                  └────────┬───────────────┘
                           │
            ┌──────────────▼──────────────────┐
            │  get_stream_commerce_snapshot()  │  ← YENİ use-case
            │  auction state + DS state        │
            └──────────────┬──────────────────┘
                           │
               ┌───────────▼────────────┐
               │  commerce_outbox.py    │  ← GENİŞLETİLDİ
               │  auction + DS events   │
               └────────────────────────┘
```

**Değişmeyenler:** `CommercePanelWrapper`, `AuctionPanel`, `DirectSalePanel`, `DirectSaleViewerNotifier`, tüm servis ve model katmanları.

---

## 3. Backend — Faz 1

### 3.1 `get_stream_commerce_snapshot` use-case

**Sorun:** `auction.py` router, direct sale domain'ini doğrudan import ediyor.

**Çözüm:** Yeni bir use-case fonksiyonu her iki state'i toplayıp router'a sunar. Router hiçbir domain bilgisi taşımaz.

**Yeni dosya:** `backend/app/use_cases/stream/commerce_snapshot.py`

```python
from app.use_cases.auctions.queries.auction_queries import GetAuctionStateQuery
from app.use_cases.direct_sales import direct_sale_redis as ds_redis

_DS_INACTIVE = frozenset({"ended", "cancelled"})

async def get_stream_commerce_snapshot(stream_id: int) -> dict:
    """
    WS bağlantısı kurulurken gönderilecek başlangıç snapshot'ını döner.
    Router'ın domain katmanlarına doğrudan erişmesi gerekmez.
    """
    auction_state = await GetAuctionStateQuery().execute(stream_id)
    ds_state = await ds_redis.get_state(stream_id)

    active_ds = None
    if ds_state and ds_state.get("status") not in _DS_INACTIVE:
        active_ds = ds_state

    return {"auction": auction_state, "direct_sale": active_ds}
```

**Router değişikliği** (`auction.py` — `auction_ws` endpoint):

```python
# ÖNCE (domain import + inline logic)
from app.use_cases.direct_sales import direct_sale_redis as ds_redis
state = await GetAuctionStateQuery().execute(stream_id)
await websocket.send_json({"type": WS.AUCTION_STATE, **state})
ds_state = await ds_redis.get_state(stream_id)
if ds_state and ds_state.get("status") not in (None, "ended", "cancelled"):
    await websocket.send_json({"type": WS.DIRECT_SALE_STARTED, **ds_state})

# SONRA (tek use-case çağrısı)
from app.use_cases.stream.commerce_snapshot import get_stream_commerce_snapshot
snapshot = await get_stream_commerce_snapshot(stream_id)
await websocket.send_json({"type": WS.AUCTION_STATE, **snapshot["auction"]})
if snapshot["direct_sale"]:
    await websocket.send_json({"type": WS.DIRECT_SALE_STARTED, **snapshot["direct_sale"]})
```

Davranış değişmez; sadece bağımlılık zinciri temizlenir.

---

### 3.2 Outbox'ı Direct Sale Event'lerine Genişlet

**Sorun:** Bağlantı kesilip gelen bir istemci auction event'lerini alıyor (`outbox_replay`) ama direct sale event'lerini almıyor. Satın alım sırasında bağlantı kesilen izleyici eski stok sayısını görür.

**Çözüm:** `auction_outbox.py` → `commerce_outbox.py` olarak genişletilir (veya DS event'leri ek Redis sorted-set'te saklanır). Outbox replay WS connect'te her iki listeyi de gönderir.

**Outbox event'leri — direct sale için kapsam:**

| Event | Replay değeri | Neden |
|---|---|---|
| `direct_sale_started` | Hayır — snapshot yeterli | WS connect'te snapshot zaten gönderiliyor |
| `direct_sale_purchased` | **Evet** | Stok sayısı değişiyor; kaçırılırsa viewer yanlış stok görür |
| `direct_sale_paused` | Evet | State geçişi |
| `direct_sale_resumed` | Evet | State geçişi |
| `direct_sale_sold_out` | Evet | Kritik state |
| `direct_sale_ended` | Evet | Final state |
| `direct_sale_cancelled` | Evet | Final state |

**Redis key:** `commerce:ds_outbox:{stream_id}` — ZSET, score = timestamp, TTL = satış bitişinde silinir (LIFECYCLE cache).

**`direct_sale_commands.py` değişikliği:**

```python
from app.core.commerce_outbox import ds_outbox_push

# purchase, pause, resume, sold_out, end, cancel sonrası:
await ds_outbox_push(stream_id, {"type": WS.DIRECT_SALE_PURCHASED, "remaining_stock": remaining, ...})
```

**`auction.py` WS endpoint değişikliği:**

```python
# Mevcut auction outbox replay'in ardından:
ds_missed = await ds_outbox_replay(stream_id, count=10)
for event in reversed(ds_missed):
    try:
        await websocket.send_json({**event, "replayed": True})
    except Exception:
        break
```

---

## 4. Flutter — Faz 2

### 4.1 `StreamCommerceNotifier<S>` Base Class

**Yeni dosya:** `mobile/lib/providers/stream_commerce_notifier.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api.dart';
import '../services/storage_service.dart';

/// Tüm commerce ViewModel'leri için ortak WS altyapısı.
///
/// Alt sınıf sadece [onCommerceEvent] metodunu implement eder.
/// WS bağlantısı, heartbeat, exponential backoff reconnect ve dispose
/// buraya aittir — domain logic notifier'da kalır.
///
/// [DirectSaleViewerNotifier] bu class'ı extend ETMEZ.
/// Viewer, kendi WS bağlantısı açmaz; state'i host notifier'dan okur.
abstract class StreamCommerceNotifier<S> extends StateNotifier<S> {
  final int streamId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;

  StreamCommerceNotifier(this.streamId, S initialState) : super(initialState) {
    unawaited(_connect());
  }

  String get _wsBase => kBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// Alt sınıf, WS üzerinden gelen her event için bu metodu implement eder.
  /// [type] her zaman non-null ve dolu; [json] raw event verisi.
  void onCommerceEvent(String type, Map<String, dynamic> json);

  Future<void> _connect() async {
    _heartbeat?.cancel();
    final token = await StorageService.getToken();
    _log('WS', 'connecting | streamId=$streamId attempt=$_reconnectAttempt');
    try {
      final uri = Uri.parse('$_wsBase/auction/$streamId/ws');
      _channel = WebSocketChannel.connect(uri);
      if (token != null) {
        _channel!.sink.add(jsonEncode({'token': token}));
        _log('WS', 'connected, auth sent | streamId=$streamId');
      } else {
        _log('WS', 'connected, no token (anonymous) | streamId=$streamId');
      }
      _reconnectAttempt = 0;
      _sub = _channel!.stream.listen(
        _onRaw,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try { _channel?.sink.add('ping'); } catch (_) {}
      });
    } catch (e) {
      _log('WS', 'connect error | streamId=$streamId $e');
      _scheduleReconnect();
    }
  }

  void _onRaw(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null || type.isEmpty) return;
      onCommerceEvent(type, json);
    } catch (e) {
      _log('WS', 'parse error | streamId=$streamId $e');
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _heartbeat?.cancel();
    final delayMs = (1000 * pow(1.5, _reconnectAttempt)).clamp(1000, 60000).toInt();
    _reconnectAttempt++;
    _log('WS', 'reconnect scheduled | streamId=$streamId delay=${delayMs}ms attempt=$_reconnectAttempt');
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _reconnecting = false;
      _sub?.cancel();
      try { _channel?.sink.close(); } catch (_) {}
      unawaited(_connect());
    });
  }

  void _log(String phase, String msg) {
    debugPrint('[COMMERCE][${DateTime.now().toIso8601String()}][$phase] $msg');
  }

  @override
  void dispose() {
    _reconnecting = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
    _log('WS', 'disposed | streamId=$streamId runtimeType=$runtimeType');
    super.dispose();
  }
}
```

**Tasarım kararları:**

- `onCommerceEvent` her event tipini alır; alt sınıf kendi ilgilenmediği tipleri `return` ile atar.
- `_log` helper base class'ta — alt sınıflar kendi prefix'lerini `onCommerceEvent` içinde kullanabilir.
- `DirectSaleViewerNotifier` bu class'ı extend etmez — dokümantasyonda açıkça belirtildi (bkz. sınıf docstring).

---

### 4.2 `AuctionNotifier` Migration

**Dosya:** `mobile/lib/providers/auction_provider.dart` (veya mevcut auction notifier dosyası)

```dart
// ÖNCE: extends StateNotifier<AuctionState>
// SONRA: extends StreamCommerceNotifier<AuctionState>

class AuctionNotifier extends StreamCommerceNotifier<AuctionState> {
  AuctionNotifier(int streamId) : super(streamId, AuctionState.idle());

  @override
  void onCommerceEvent(String type, Map<String, dynamic> json) {
    // Sadece auction event'leri işle
    if (!type.startsWith('auction_') && type != 'state' && type != WS.AUCTION_STATE) return;
    _applyEvent(type, json);
  }

  // _applyEvent, action metodları (bid, start, pause, resume, end, accept vb.)
  // AYNEN kalır — sadece WS altyapısı kaldırılır.
}
```

Kaldırılacaklar: `_channel`, `_sub`, `_heartbeat`, `_reconnecting`, `_reconnectAttempt` field'ları, `_wsBase` getter, `_connect()`, `_scheduleReconnect()`, `dispose()` — bunların hepsi artık base class'ta.

---

### 4.3 `DirectSaleHostNotifier` Migration

**Dosya:** `mobile/lib/providers/direct_sale_provider.dart`

```dart
// ÖNCE: extends StateNotifier<DirectSaleState>
// SONRA: extends StreamCommerceNotifier<DirectSaleState>

class DirectSaleHostNotifier extends StreamCommerceNotifier<DirectSaleState> {
  DirectSaleHostNotifier(int streamId) : super(streamId, DirectSaleState.idle());

  @override
  void onCommerceEvent(String type, Map<String, dynamic> json) {
    if (!type.startsWith('direct_sale_')) return;
    _dsLog('WS', 'event received | type=$type streamId=$streamId');
    _applyWsEvent(type, json);
  }

  // _applyWsEvent, applyState, reset, pause, resume, end, cancel, startSale
  // AYNEN kalır — sadece WS altyapısı kaldırılır.
}
```

`_dsLog` helper: ya base class `_log`'u kullanır (prefix değiştirerek), ya da kendi `_dsLog`'unu tutar. Her ikisi de geçerli.

---

## 5. Dokümantasyon — Faz 3

`documents/architectural_decisions.md` §10 eklenir:

> **Commerce WS Altyapısı — `StreamCommerceNotifier<S>`**  
> Her commerce tipi (Auction, Direct Sale, ileride Flash Sale) bu abstract base class'ı extend eder. WS bağlantısı, heartbeat ve exponential backoff reconnect tek yerde yaşar. Domain logic (event handling, action metodları) notifier'da kalır. UI routing `CommercePanelWrapper`'da kalır. `DirectSaleViewerNotifier` bu class'ı extend etmez — viewer WS bağlantısı açmaz, state'i host notifier'dan okur.

Header'daki "Son güncelleme" satırı da güncellenir.

---

## 6. Değişmeyen Parçalar

Bu refactoring aşağıdaki bileşenlere dokunmaz:

| Bileşen | Neden değişmez |
|---|---|
| `CommercePanelWrapper` | View layer coordinator — zaten clean |
| `AuctionPanel` | Pure view widget |
| `DirectSalePanel` | Pure view widget |
| `DirectSaleViewerNotifier` | WS açmıyor, doğru tasarım |
| `DirectSaleService` | Servis katmanı — doğru bağımlılık |
| `AuctionService` | Servis katmanı — doğru bağımlılık |
| Tüm model sınıfları | Domain modeller — doğru katman |
| `auction_commands.py` | Auction domain — bağımsız |
| `direct_sale_commands.py` | DS domain — bağımsız |

---

## 7. 3. Commerce Tipi Eklemek

Bu refactoring tamamlandıktan sonra ileride bir "Flash Sale" gibi yeni bir commerce tipi eklemek şu adımlara indirgenir:

**Backend:**
1. `flash_sale_redis.py` — state yönetimi
2. `flash_sale_commands.py` — iş mantığı
3. `get_stream_commerce_snapshot()` — flash sale state'ini snapshot'a ekle
4. `commerce_outbox.py` — flash sale event'lerini kaydet

**Flutter:**
1. `FlashSaleState` model
2. `FlashSaleNotifier extends StreamCommerceNotifier<FlashSaleState>` — sadece `onCommerceEvent` implement edilir
3. `FlashSalePanel` widget — pure view
4. `CommercePanelWrapper._CommerceMode` enum'una `flashSale` ekle
5. `_resolveMode()` ve `_forceFlashSale` bayrağı ekle

WS altyapısına, router'a veya outbox'ın temel mekanizmasına dokunulmaz.
