# Teqlif VoIP Mimarisi

> Analiz tarihi: 2026-07-30  
> Kapsam: uçtan uca — DB, API, Redis, LiveKit, iOS native, Flutter state machine, push servisleri

---

## 1. Bileşenler

```
┌──────────────────────────────────────────────────────────────────────┐
│                            BACKEND (FastAPI)                         │
│                                                                      │
│  routers/calls.py    ←──── REST API (start / accept / end / reject) │
│  services/livekit.py ←──── LiveKit token üretimi + room yönetimi    │
│  services/apns_service.py ←── APNs VoIP push (.p8 token-auth)       │
│  utils/call_redis.py ←──── Redis key fabrikası + participant SET     │
│  models/call.py      ←──── PostgreSQL: calls + call_participants     │
│  worker.py (ARQ)     ←──── delayed_call_timeout (60s) +             │
│                             invite_timeout (30s)                     │
└──────────┬──────────────────────────────────────┬────────────────────┘
           │  REST/WS                             │ APNs / FCM push
           ▼                                      ▼
┌──────────────────────┐              ┌────────────────────────────────┐
│  Flutter (Dart)      │              │  iOS native (Swift)            │
│                      │              │                                │
│  call_service.dart   │              │  AppDelegate.swift             │
│  ├─ State machine    │              │  ├─ PKPushRegistry             │
│  ├─ LiveKit SDK      │              │  ├─ didReceiveIncomingPushWith  │
│  ├─ ringbackPlayer   │              │  ├─ reportNewIncomingCall       │
│  └─ audioplayers     │              │  └─ CXEndCallAction             │
│                      │              └────────────────────────────────┘
│  call_screen.dart    │
│  incoming_call_overlay.dart
└──────────┬───────────┘
           │ WebRTC / WebSocket
           ▼
┌──────────────────────┐
│  LiveKit SFU         │
│  wss://teqlif.com/rtc│
│  (nginx proxy)       │
└──────────────────────┘
```

---

## 2. Altyapı Katmanı

### PostgreSQL — `calls` tablosu
| Sütun | Tür | Açıklama |
|---|---|---|
| id | int | PK |
| caller_id | int | FK users |
| callee_id | int | FK users |
| room_name | str | LiveKit room adı |
| status | enum | `calling / active / ended / rejected / missed` |
| started_at | datetime | Arama başlangıcı |
| accepted_at | datetime | Kabul zamanı (NULL → cevapsız) |
| ended_at | datetime | Bitiş zamanı |
| duration_seconds | int | Süre |
| had_video | bool | Video açık mıydı |
| max_participants | int | Katılımcı sayısı |

### Redis Key Desenleri
| Key | Tip | TTL | Amaç |
|---|---|---|---|
| `call:{id}:participants` | SET | 3 saat | LiveKit odaya katılan user ID'leri |
| `call:{id}:invite:{uid}` | STRING / NX | 35 saniye | Duplikasyon kilidi (bir kullanıcıya tekrar davet engeli) |
| `call_ended_sent:{id}` | STRING / NX | 60 saniye | `call_ended` WS'inin iki kez gönderilmesini engeller |
| `ws_call_event:{room}:{uid}` | STRING | — | WS bağlantısı yeni kurulduğunda kaçırılan call event'ini tekrarlar |

### LiveKit
- URL: `wss://teqlif.com/rtc` (nginx proxy üzerinden)
- Token: JWT, `LIVEKIT_API_KEY` + `LIVEKIT_API_SECRET` ile imzalanır
- Token'da `caller_token` (caller için) + `callee_token` (callee için) ayrı ayrı üretilir
- Oda her aramayla otomatik oluşturulur (`room_name = call_{id}_{uuid4}`)

---

## 3. Push Teslimat Stratejisi

### iOS
```
Token yaşı ≤ 7 gün   → Yalnız VoIP push (APNs PushKit)
Token yaşı 8–30 gün  → VoIP push + FCM paralel
Token yaşı > 30 gün  → FCM önce; VoIP push yedek
```
VoIP push, APNs PushKit kanalından gönderilir ve **uygulama kapalı olsa bile** iOS'u uyandırır.  
FCM push arka plan bildirimi olarak gelir (uygulama açık olursa WS üzerinden zaten bilgi alınmış olur).

### Android
FCM push (data-only) → `incoming_call_overlay.dart` içindeki bildirim işleyicisi.

### WS (Belt-and-Suspenders)
Callee o anda WS üzerinden bağlı olsa bile push **her zaman** gönderilir; bu sayede WS gecikmesinde push yakalanır.

---

## 4. iOS Native Katmanı (AppDelegate.swift)

```
VoIP Push alındı
  │
  ▼
didReceiveIncomingPushWith()
  ├── dictionary["callee_token"] ?? ""   → data.extra["callee_token"]
  ├── dictionary["livekit_url"]  ?? ""   → data.extra["livekit_url"]
  ├── dictionary["caller_name"]  ?? ""
  ├── dictionary["call_id"]      ?? ""
  └── reportNewIncomingCall(uuid, update, …)
        │
        └── flutter_callkit_incoming plugin → CallKit UI göster

appIsActive == true? → CXEndCallAction (ön plandayken VoIP pop-up'ı kapat)
```

**Önemli detay:** Eksik field'lar `""` (boş string) olarak düşer; `nil` değil. Bu durum Dart tarafında null kontrolünü geçer fakat `_joinRoom("", "")` çağrısına sebep olur (Fixed — bkz. `findings.md` #1).

---

## 5. Flutter State Machine

### Durum Geçişleri

**Arayan (Caller):**
```
idle
  → [startCall()] → calling          ← ringback başlar
  → [call_accepted WS] → connecting
  → [TrackSubscribed/TrackUnmuted] → connected    ← ringback durur, ses başlar
  → [endCall/timeout/reject] → ended/rejected/missed/noAnswer
  → idle
```

**Çağrılan (Callee):**
```
idle
  → [incoming push/WS] → ringing     ← zil çalar
  → [acceptCall()] → connecting
  → [TrackSubscribed local-setup tamamlandı] → connected
  → [endCall/reject] → ended/rejected
  → idle
```

### Durum Değişikliklerinin Sesle İlişkisi

| Durum | Arayan | Çağrılan |
|---|---|---|
| `calling` | ringback.wav başlar | — |
| `ringing` | — | ringtone.wav başlar |
| `connecting` | ringback devam eder | ringtone devam eder |
| `connected` | ringback DURUR; ses başlar | ringtone DURUR; ses başlar |
| `busy/rejected` | busy.wav çalar | — |
| `ended/idle` | her ses durur | her ses durur |

---

## 6. Ön-Bağlantı (Pre-Connect) Mimarisi

Pre-connect, WhatsApp benzeri anlık bağlantı için: callee kabul etmeden **her iki taraf da** LiveKit odasına katılır.

### Arayan Tarafı

```
startCall() POST /calls
  │ → caller_token + room_name döner
  │
  ├── iOS: room.connect() [network-only, mic YOK]
  │     └── room.connect() AVAudioSession'ı SoloAmbient'e çeker
  │           └── ringback bozulur → lines 1484-1504 restore eder
  │                 [KOŞUL: status == calling; connecting ise restore ATLANIR]
  │
  └── Android: room.connect() + setMicrophoneEnabled(true) + pub.mute(stopOnMute:false)
                └── muted audio track pre-publish
```

### Çağrılan Tarafı

```
Incoming push / WS alındı
  │
  ├── VoIP payload'da callee_token varsa: doğrudan _joinRoom()
  └── Yoksa: GET /callee-token → token alındıktan sonra _joinRoom()

_joinRoom() [status = ringing]
  │
  ├── room.connect() [network-only, mic YOK, ringtone korunur]
  │
  └── iOS callee: CallKit audioSessionActivated beklenir (max 4s)
```

### Kabul Akışı

```
Callee: acceptCall()
  │ → _activateCalleeAudio()
  │     ├── AudioSession configure (playAndRecord/voiceChat)
  │     ├── setSpeakerphoneOn(false)
  │     └── setMicrophoneEnabled(true)  ← callee ses track'ını publish eder
  │
  └── status = connecting

Caller: call_accepted WS alındı
  │ → onCallAccepted()
  │     └── status = connecting
  │
  ├── Android: pre-published muted track → unmute()  [FAST PATH ~50ms]
  └── iOS: TrackSubscribed (callee's audio) → setMicrophoneEnabled(true) [~0ms race]
```

### connected Tetikleyicileri

| Koşul | Kaynak |
|---|---|
| `TrackSubscribedEvent` (audio, status ≠ calling/ringing) | Callee audio publish edince |
| `TrackUnmutedEvent` (remote audio, status == connecting) | Android caller muted track unmute edince |
| `peerAlreadyJoined + anyAudioSubscribed` (status ≠ ringing) | Peer zaten odada ve audio aktifse |

---

## 7. iOS Ringback Geri Yükleme Mekanizması

iOS'ta `room.connect()` içride AVAudioSession'ı `SoloAmbient`'e çeker. Bu `audioplayers` ile çalan ringback'i keser. Geri yükleme aşağıdaki blokta yapılır:

```dart
// call_service.dart ~line 1484
if (state.value.status == CallStatus.calling) {   // ← kritik koşul
  await session.configure(playAndRecord / voiceChat);
  if (_ringbackPlayer.state != playing) {
    await _ringbackPlayer.seek(Duration.zero);
    await _ringbackPlayer.resume();
  }
}
```

**Kritik:** Koşul `== calling`'dir. Eğer `room.connect()` tamamlanmadan callee kabul ederse status `connecting`'e geçer → geri yükleme bloğu atlanır → ringback sessizliğe düşer.

---

## 8. ARQ Background Worker Görevleri

| Görev | Gecikme | Tetik | Eylem |
|---|---|---|---|
| `delayed_call_timeout_task` | 60 saniye | startCall | Hâlâ `calling` ise → `call_ended` WS → DB missed |
| `invite_timeout_task` | 30 saniye | startCall | Callee 30s'de cevap vermediyse → `invite_timeout` WS |

---

## 9. Callee Token Üretimi ve Teslimat

```
POST /calls
  ├── caller_token = livekit.create_token(caller_id, room_name, expire=4h)
  ├── callee_token = livekit.create_token(callee_id, room_name, expire=4h)
  │
  └── VoIP payload:
        { callee_token: "...", livekit_url: "...", call_id: "...", ... }

Dart onIncomingCall():
  ├── calleeToken.isEmpty → GET /callee-token (HTTP fetch fallback)
  └── calleeToken.isNotEmpty → doğrudan _joinRoom(calleeToken, livekitUrl)
```

Token süresi 4 saattir. Çok uzun arama beklenmiyor fakat bu süre aşılırsa token geçersiz kalır.

---

## 10. Sinyal Kanal Özeti

| Kanal | Ne zaman | Veri |
|---|---|---|
| WebSocket | Uygulama açıkken | `call_started`, `call_accepted`, `call_ended`, `call_rejected` |
| APNs PushKit | iOS background/killed | VoIP payload (callee_token, livekit_url, caller bilgisi) |
| FCM | Android + iOS background | Bildirim (call_id, caller_name, type=incoming_call) |
| LiveKit events | Bağlantı sonrası | `TrackSubscribed`, `TrackUnmuted`, `ParticipantConnected`, vb. |
