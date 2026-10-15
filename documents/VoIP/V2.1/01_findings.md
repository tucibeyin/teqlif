# VoIP V2.1 — Bulgular ve Düzeltmeler

> Commit aralığı: `3743764a` → `e9e14073`  
> Tarih: Ekim 2026  
> Kapsam: Zombie call cleanup, multi-node LK URL sabitlenmesi, generic LK admin API

---

## 1. Tespit Edilen Sorunlar ve Düzeltmeleri

### 1.1 Stale Ringing State (Zombie Call Bar)

**Semptom:** Kullanıcı foreground'da aktif bir call bar görüyor; backend'de kayıt yok, Redis'te presence yok.

**Kök neden:** `checkActiveCall()` yalnızca `WsConnectedSignal` üzerinden tetikleniyordu. Uygulama arka plandan döndüğünde WS zaten bağlıysa reconnect sinyali gelmez → `checkActiveCall` hiç çağrılmaz → Flutter in-memory state temizlenmez.

**Düzeltme:** `main_screen.dart` `didChangeAppLifecycleState(resumed)` içinde `callStatus == ringing/active/reconnecting` ise `checkActiveCall()` çağrıldı. (`8b0608e5`, `4fccef53`)

---

### 1.2 Zombie Active State (Tek Taraflı Arama)

**Semptom:** Kullanıcı uygulamayı kapatmadan bıraktı, call state `active` gösteriyordu; DB'de `ended`, Redis'te boş.

**Kök neden:** `checkActiveCall()` içindeki dedup guard (`if (currentStatus != CallStatus.idle) return`) `active` ve `reconnecting` state'lerini doğrulama yapmadan atlıyordu. Callee `_hangUpLocally` çağırdığında HTTP `/end` atılmadığı senaryolarda backend bildirilmiyordu. Ghost cleanup (`cleanup_ghost_calls_task`) ise oda hâlâ LK'da varken `active` kayıtlarına dokunmuyordu.

**Düzeltme:** `checkActiveCall()` içine `active/reconnecting` için ayrı doğrulama bloğu eklendi. Backend `ended/rejected/missed` dönerse `endAllCalls()` + `_hangUpLocally()` tetiklenir. (`4fccef53`)

---

### 1.3 One-Way Audio / No Remote Peer (Dead Peer Timer)

**Semptom:** Bir taraf bağlantısını kaybetti, diğer taraf `active` state'te bekliyor; ses yok.

**Kök neden:** `_startStatsMonitor()` her 5 saniyede bir `remoteParticipants.length` logluyordu ama aksiyon almıyordu.

**Düzeltme:** `_deadPeerTimer` eklendi. `remoteParticipants == 0` durumu 30 saniye devam ederse `endCall()` tetiklenir. Peer geri gelirse timer iptal edilir. `_stopStatsMonitor()` ve `reset()` timer'ı da temizler. (`4fccef53`)

---

### 1.4 Multi-Node LK URL Tutarsızlığı

**Semptom:** Caller ve callee birbirine bağlanamıyor; LK room boş görünüyor.

**Kök neden:** V2.1'de iki LK node var (node3: `live2.teqlif.com`, node4: `live1.teqlif.com`). Tek bir call için `allocate_node(ServiceType.MEDIA)` bağımsız 5+ kez çağrılıyordu:

| Çağrı noktası | Eski davranış |
|---|---|
| Callee WS push | `allocate_node()` → rastgele node |
| Caller `/start` response | `allocate_node()` → rastgele node |
| VoIP push payload | `allocate_node()` → rastgele node |
| FCM push payload | `allocate_node()` → rastgele node |
| `/accept` response | `allocate_node()` → rastgele node |

Load balancer yük durumuna göre her seferinde farklı node seçebiliyordu → caller node3, callee node4'te → farklı LK room'ları → bağlantı kurulamıyor.

**Düzeltme:** `Call` modeline `livekit_url VARCHAR(300)` eklendi. Call oluşturulurken (sadece bir kez) `allocate_node` çağrılır, URL `call.livekit_url`'e yazılır. Tüm endpoint'ler `call.livekit_url`'i yeniden kullanır. Eski satırlar için `call.livekit_url or allocate_node(...)` fallback. Migration: `zzzzzp_calls_livekit_url`. (`4fccef53`)

---

### 1.5 LK Admin API'nin Multi-Node Kör Noktası

**Kök neden:** `_delete_lk_room`, `delayed_call_timeout_task`, `cleanup_ghost_calls_task` ve stream cleanup task'ları — hepsi `allocate_node()` ile rastgele bir node seçip LK admin API'sini çağırıyordu. `allocate_node` yük dengeleme içindir; admin operasyonlar için tasarlanmamıştır.

**V2.1'deki gizli garanti:** Node3 ve node4, HAProxy üzerinden aynı Redis cluster'ını (db:1) paylaşıyor:

```
node3 LiveKit  →  127.0.0.1:6379 (HAProxy)  ─┐
                                               ├→  node1 Redis (db:1)
node4 LiveKit  →  127.0.0.1:6379 (HAProxy)  ─┘
```

LiveKit room koordinasyonu shared Redis üzerinden yapıldığından `list_rooms` veya `delete_room` hangi node'a atılırsa atılsın şu an aynı sonucu veriyor. Ancak bu bir mimari garanti değil — shared Redis kullanmayan bir node eklenmesi veya HAProxy arızası bu davranışı kırar.

**Düzeltme:** Generic multi-node LK admin API katmanı oluşturuldu. (`e9e14073`)

---

## 2. Generic LK Admin API Mimarisi

### 2.1 Temel Ayrım

```
allocate_node()          →  yeni kaynak yaratırken (load balance, en uygun node seçer)
lk_list_all_rooms()      →  tüm node'lara sor, oda isimlerinin union'ını döner
lk_broadcast_delete()    →  tüm node'lara delete_room atar (idempotent, not_found sessiz)
```

### 2.2 Yeni Bileşenler

**`EdgeOrchestrator.all_media_nodes()`** (`edge_orchestrator.py`)  
Tüm sağlıklı media node'larını döner. Metrik yoksa `settings.edge_livekit_urls` listesi fallback.

**`backend/app/services/livekit_service.py`**

| Fonksiyon | Davranış |
|---|---|
| `lk_list_all_rooms()` | Tüm node'lara `ListRooms` atar, `set[str]` döner |
| `lk_list_all_rooms_with_participants()` | Tüm node'lara atar, `{room: num_participants}` döner; aynı oda birden fazla node'da görünürse max participant seçilir |
| `lk_broadcast_delete(room, livekit_url)` | Tüm node'lara `DeleteRoom` atar; `livekit_url` verilirse o URL öncelikli; `not_found` sessiz yutulur |

### 2.3 Migrate Edilen Çağrı Noktaları

| Dosya | Task / Endpoint | Eski | Yeni |
|---|---|---|---|
| `calls.py` | `_delete_lk_room` | `allocate_node` | `lk_broadcast_delete` (+ `call.livekit_url` hint) |
| `worker.py` | `delayed_call_timeout_task` | `allocate_node` | `lk_broadcast_delete` |
| `worker.py` | `cleanup_ghost_calls_task` list | `allocate_node` | `lk_list_all_rooms` |
| `worker.py` | `cleanup_ghost_calls_task` delete | `allocate_node` | `lk_broadcast_delete` |
| `worker.py` | `cleanup_stale_streams_task` | `allocate_node` | `lk_list_all_rooms_with_participants` |
| `worker.py` | `delayed_close_stream_task` | `allocate_node` | `lk_list_all_rooms` |

`allocate_node` yalnızca yeni call ve stream oluşturulurken kullanılmaya devam eder.

### 2.4 Node Sayısı Senaryoları

| Senaryo | `lk_list_all_rooms` | `lk_broadcast_delete` |
|---|---|---|
| 1 LK node | Tek node'a istek, sonuç doğru | Tek node'a istek, sonuç doğru |
| 2 node, shared Redis (V2.1 mevcut) | İki istek, union = tam liste | İki istek, her ikisi de siler (idempotent) |
| 2 node, isolated Redis (gelecek) | İki istek, union = tam liste | Her node kendi room'unu siler |

---

## 3. State Layer Envanteri

Bir VoIP call'da temizlenmesi gereken tüm state katmanları:

| Katman | Temizleme sorumlusu | Tetikleyici |
|---|---|---|
| Redis presence (`user:call_presence:*`) | `clear_presence()` | `/end`, ghost cleanup, missed |
| Redis call keys (`call:*`) | `clear_call_redis()` | `/end`, ghost cleanup |
| DB call status | `call.status = ended/missed` | `/end`, ghost cleanup, timeout |
| Flutter CallState (Riverpod) | `_setState(idle)` / `_hangUpLocally` | WS event, `checkActiveCall`, dead peer |
| iOS CallKit | `endAllCalls()` / `reportCallEnded` | Tüm Flutter cleanup path'leri |
| Android notification | `FlutterCallkitIncoming.endCall()` | WS call_ended/call_missed FCM |
| WS lock | `releaseConnectionLock()` | `_hangUpLocally`, `reset()` |
| Audio session | `_hardware.deactivateAudioSession()` | `_hangUpLocally` |
| Wakelock | `_hardware.releaseWakelock()` | `_hangUpLocally` |
| LK room | `lk_broadcast_delete()` | Ghost cleanup, timeout, `/end`, reject |

---

## 4. V2.1 Uyumluluk Özeti

| Değişiklik | V2.1 Uyumu | Açıklama |
|---|---|---|
| `checkActiveCall` active/reconnecting doğrulaması | ✅ | WS katmanını bozmaz |
| App resume lifecycle guard genişletmesi | ✅ | Mevcut pattern'e ekleme |
| Dead peer timer (30s) | ✅ | LK SDK `remoteParticipants`, node-agnostic |
| `livekit_url` DB'de saklama | ✅ | V2.1 çok-node mimarisinin doğal gereği |
| Migration `zzzzzp` (ADD COLUMN IF NOT EXISTS) | ✅ | Tek `op.execute()`, asyncpg uyumlu |
| `lk_broadcast_delete` + `lk_list_all_rooms` | ✅ | 1 node, shared-Redis ve isolated multi-node'da doğru |

---

## 5. Commit Referansları

| Commit | İçerik |
|---|---|
| `3743764a` | `checkActiveCall` ringing state backend doğrulaması |
| `03bb9fea` | Android CallEventActionCallIncoming HTTP ACK eksikti |
| `f927cd3a` | Background isolate providerContainer bağımlılığı kaldırıldı |
| `045c44c5` | iOS background `call_missed` FCM content-available eksikti |
| `8b0608e5` | `endAllCalls` + app resume ringing check |
| `4fccef53` | Zombie cleanup Fix 1–4 (active doğrulama, app resume genişletme, dead peer timer, livekit_url DB) |
| `e9e14073` | Generic multi-node LK admin API — `lk_broadcast_delete` + `lk_list_all_rooms` |
