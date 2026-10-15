# VoIP V2.1 — Bulgular ve Düzeltmeler

> Commit aralığı: `3743764a` → `4fccef53`  
> Tarih: Ekim 2026  
> Kapsam: Zombie call cleanup, multi-node LK URL sabitlenmesi, generic LK admin API tasarımı

---

## 1. Tespit Edilen Sorunlar

### 1.1 Stale Ringing State (Zombie Call Bar)

**Semptom:** Kullanıcı foreground'da aktif bir call bar görüyor; backend'de kayıt yok, Redis'te presence yok.

**Kök neden:** `checkActiveCall()` yalnızca `WsConnectedSignal` üzerinden tetikleniyordu. Uygulama arka plandan döndüğünde WS zaten bağlıysa reconnect sinyali gelmez → `checkActiveCall` hiç çağrılmaz → Flutter in-memory state temizlenmez.

**Fix:** `main_screen.dart` `didChangeAppLifecycleState(resumed)` içinde `callStatus == ringing/active/reconnecting` ise `checkActiveCall()` çağrıldı. (`8b0608e5`, `4fccef53`)

---

### 1.2 Zombie Active State (Tek Taraflı Arama)

**Semptom:** "teqlif" uygulamasını kapatmadan bıraktı, call state `active` gösteriyordu; DB'de `ended`, Redis'te boş.

**Kök neden:** `checkActiveCall()` içindeki dedup guard (`if (currentStatus != CallStatus.idle) return`) `active` ve `reconnecting` state'lerini doğrulama yapmadan atlatıyordu. Callee `_hangUpLocally` çağırdığında HTTP `/end` atılmadığı senaryolarda backend'e bildirilmiyordu; ghost cleanup (`cleanup_ghost_calls_task`) ise oda hâlâ LK'da varken `active` kayıtlarına dokunmuyordu.

**Fix:** `checkActiveCall()` içine `active/reconnecting` için ayrı doğrulama bloğu eklendi. Backend `ended/rejected/missed` dönerse `endAllCalls()` + `_hangUpLocally()` tetiklenir. (`4fccef53`)

---

### 1.3 One-Way Audio / No Remote Peer

**Semptom:** Bir taraf bağlantısını kaybetti, diğer taraf `active` state'te bekliyor; ses yok.

**Kök neden:** `_startStatsMonitor()` 5 saniyede bir `remoteParticipants.length` logluyordu ama aksiyon almıyordu.

**Fix:** `_deadPeerTimer` eklendi. `remoteParticipants == 0` durumu 30 saniye devam ederse `endCall()` tetiklenir. Peer geri gelirse timer iptal edilir. `_stopStatsMonitor()` timer'ı da temizler. (`4fccef53`)

---

### 1.4 Multi-Node LK URL Tutarsızlığı

**Semptom:** Caller ve callee birbirine bağlanamıyor; LK room'u boş görünüyor.

**Kök neden:** V2.1'de iki LK node var (node3: `live2.teqlif.com`, node4: `live1.teqlif.com`). Tek bir call için `allocate_node(ServiceType.MEDIA)` bağımsız 5+ kez çağrılıyordu:

| Çağrı noktası | Dosya | Satır |
|---|---|---|
| Callee WS push | `calls.py` | eski 663 |
| Caller `/start` response | `calls.py` | eski 716 |
| VoIP push payload | `calls.py` | eski 434 |
| FCM push payload | `calls.py` | eski 422 |
| `/accept` response | `calls.py` | eski 828 |

Load balancer yük durumuna göre her seferinde farklı node seçebiliyordu → caller node3, callee node4'te → farklı LK room'ları → bağlantı kurulamıyor.

**Fix:** `Call` modeline `livekit_url VARCHAR(300)` eklendi. Call oluşturulurken (sadece bir kez) `allocate_node` çağrılır, URL `call.livekit_url`'e yazılır. Tüm endpoint'ler `call.livekit_url`'i yeniden kullanır. Eski rowlar için `call.livekit_url or allocate_node(...)` fallback. Migration: `zzzzzp_calls_livekit_url`. (`4fccef53`)

---

## 2. Mimari Tespit: LK Admin API ve Multi-Node

### 2.1 V2.1'deki Mevcut Durum

Node3 ve node4, **aynı Redis cluster'ını** (db:1) HAProxy üzerinden paylaşıyor:

```
node3 LiveKit  →  127.0.0.1:6379 (HAProxy)  ─┐
                                               ├→  node1 Redis (db:1)
node4 LiveKit  →  127.0.0.1:6379 (HAProxy)  ─┘
```

LiveKit room koordinasyonu shared Redis üzerinden yapıldığından:
- `list_rooms` hangi node'a atılırsa atılsın tüm odaları döner
- `delete_room` hangi node'a atılırsa atılsın room state'i Redis'ten siler

Bu nedenle V2.1'de `allocate_node` ile rastgele node seçimi admin operasyonlarda şu an çalışıyor. **Ama bu bir mimari garanti değil**, bir yan etkidir.

### 2.2 Kırılan Senaryolar

| Senaryo | Sonuç |
|---|---|
| Gelecekte shared Redis kullanmayan bağımsız LK node eklenir | `list_rooms` eksik sonuç döner; `delete_room` yanlış node'a gider |
| HAProxy devre dışı kalır, bir node farklı Redis'e bağlanır | Kısmi room visibility |
| `cleanup_ghost_calls_task` tek node'dan `list_rooms` çeker | Diğer node'daki active room'lar görünmez → yanlış ghost cleanup |

### 2.3 Generic Çözüm Tasarımı (Uygulanmadı — Sonraki Adım)

`allocate_node` → yeni kaynak yaratırken kullanılır (load balance).  
Admin operasyonlar → tüm node'lara broadcast/union edilmeli.

```
Yeni call/stream  →  allocate_node()      (en uygun node seç, URL kaydet)
list_rooms        →  TÜM node'lara sor, union al
delete_room       →  TÜM node'lara gönder (idempotent, not_found sessiz)
```

**Planlanan değişiklikler:**

1. `EdgeOrchestrator.all_media_nodes()` — tüm sağlıklı media node'larını döner; fallback: `settings.edge_livekit_urls` listesi.

2. `backend/app/services/livekit_service.py` — iki generic utility:
   - `lk_list_all_rooms() → set[str]` — tüm node'lara `list_rooms` atar, union döner
   - `lk_broadcast_delete(room_name)` — tüm node'lara delete atar, `not_found` sessiz yutulur

3. Tüketiciler güncellenir:

| Dosya | Mevcut | Hedef |
|---|---|---|
| `calls.py` `_delete_lk_room` | `allocate_node` | `lk_broadcast_delete` |
| `worker.py` `delayed_call_timeout_task` | `allocate_node` | `lk_broadcast_delete` |
| `worker.py` `cleanup_ghost_calls_task` list | `allocate_node` | `lk_list_all_rooms` |
| `worker.py` `cleanup_ghost_calls_task` delete | `allocate_node` | `lk_broadcast_delete` |
| `worker.py` stale stream cleanup | `allocate_node` | `lk_list_all_rooms` |

4. Stream oluştururken `allocate_node` **değişmez** — load balancing doğru davranış.

Bu tasarım 1 node, shared-Redis multi-node ve future isolated multi-node senaryolarının hepsinde doğru çalışır.

---

## 3. Uygulanan Fix'lerin V2.1 Uyumluluğu

| Fix | V2.1 Uyumu | Not |
|---|---|---|
| `checkActiveCall` active/reconnecting doğrulama | ✅ | WS katmanını bozmaz |
| App resume lifecycle guard genişletmesi | ✅ | Mevcut pattern'e ekleme |
| Dead peer timer (30s) | ✅ | LK SDK `remoteParticipants` kullanıyor, node-agnostic |
| `livekit_url` DB'de saklama | ✅ | V2.1 çok-node mimarisinin doğal gereği |
| Migration `zzzzzp` (ADD COLUMN IF NOT EXISTS) | ✅ | Tek `op.execute()`, asyncpg uyumlu |

---

## 4. State Layer Envanteri

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
| LK room | `lk_broadcast_delete()` (hedef) | Ghost cleanup, timeout, `/end` |

---

## 5. Commit Referansları

| Commit | İçerik |
|---|---|
| `3743764a` | `checkActiveCall` ringing state backend doğrulaması |
| `03bb9fea` | Android CallEventActionCallIncoming HTTP ACK eksikti |
| `f927cd3a` | Background isolate providerContainer bağımlılığı kaldırıldı |
| `045c44c5` | iOS background `call_missed` FCM content-available eksikti |
| `8b0608e5` | `endAllCalls` + app resume ringing check |
| `4fccef53` | Zombie cleanup Fix 1-4 (active doğrulama, app resume genişletme, dead peer timer, livekit_url DB) |
