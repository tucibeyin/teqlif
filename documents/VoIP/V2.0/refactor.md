# VoIP V2.0 Refactoring Roadmap

> Bu belge `VoIP.md` kılavuzunu koda dönüştürme planıdır.  
> Her adım bağımsız olarak production'a alınabilir.  
> Her adım tamamlandıkça `[ ]` → `[x]` işaretlenir.

---

## 1. Mevcut Durum Analizi

`mobile/lib/services/call_service.dart` — **2645 satır, tek sınıf.**

İçinde karışık olan sorumluluklar:

| Sorumluluk | V2.0 Karşılığı | Durum |
|---|---|---|
| State + transition logic | `CallStateMachine` | İçine gömülü |
| AVAudioSession, AudioFocus, ringback | `CallHardwareAdapter` | İçine gömülü |
| HTTP çağrıları (/start, /accept, /end...) | `CallRepository` | İçine gömülü |
| Push token kayıt, CallKit raporlama | `CallNotifAdapter` | İçine gömülü |
| Ekran açma kararı (overlay/screen) | `CallScreenRouter` | `CallService` + overlay widget'lar |
| Orchestration | `CallService` | Var, ama tek başına |

**Mevcut `_allowedTransitions` tablosu (line 366):**  
Zaten var — log-only guard olarak. İlk adımda bunu formal bir state machine'e dönüştüreceğiz.

---

## 2. State İsim Uyumu

V2.0 ile mevcut kod arasındaki isimlendirme farkı. Bu fark Step 2'de kapatılır.

| Mevcut `CallStatus` | V2.0 State | Değişiklik |
|---|---|---|
| `idle` | `idle` | Aynı ✓ |
| `calling` | `dialing` + `waiting` | TAMAMLANDI ✓ (Step 2) |
| `ringing` | `ringing` | Aynı ✓ |
| `connecting` | `connecting` | Aynı ✓ |
| `connected` | `active` | TAMAMLANDI ✓ (Step 2) |
| `ended` | `ended` | Aynı ✓ |
| `reconnecting` | `reconnecting` | Aynı ✓ |
| `rejected` | `ended` (reason=rejected) | ABSORBE — Step 3 |
| `missed` | `ended` (reason=missed) | ABSORBE — Step 3 |
| `noAnswer` | `ended` (reason=noAnswer) | ABSORBE — Step 3 |
| `busy` | `ended` (reason=busy) | ABSORBE — Step 3 |
| `permissionDenied` | `ended` (reason=permissionDenied) | ABSORBE — Step 3 |

**`calling` → `dialing`+`waiting` ve `connected` → `active` etkisi:** 8 dosya, tamamı Step 2'de değiştirildi.  
**Terminal state'lerin absorbe edilmesi:** `EndReason` field eklenir, enum değerleri kaldırılır — Step 3'te yapılır.

---

## 3. Migration Sırası

Her adım bir öncekine bağımlı, ama mevcut sistemi bozmadan production'a alınabilir.

**Durum ikonları:** 🔴 Başlamadı · 🟡 Devam ediyor · ✅ Tamamlandı

| Adım | Ne | Neden Önce | Durum |
|---|---|---|---|
| **Step 1** | `CallStateMachine` + `CallRole` | Saf Dart, sıfır bağımlılık, her şeyin temeli | ✅ `cc9bd511` |
| **Step 2** | State isim uyumu (rename) | State machine temiz olduktan sonra güvenli | ✅ `f47c2460` + `662e165a` |
| **Step 3** | `EndReason` + terminal state'leri absorbe et | İsim uyumu sonrası | ✅ `d961e82e` + `e153e1a2` |
| **Step 4** | `CallRepository` | API katmanı izole — state machine bağımsız | ✅ |
| **Step 5** | `CallHardwareAdapter` | iOS/Android impl ayrılır | ✅ |
| **Step 6** | `CallScreenRouter` | Routing merkezlenir | ✅ |
| **Step 7** | `CallNotifAdapter` | Push layer izole | ✅ |
| **Step 8** | `CallService` ince orchestrator | Diğerleri hazır olunca | ✅ |
| **Step 9** | Grup call HTTP → `CallRepository` | Step 4 additive extension | ✅ |
| **Step 10** | `CallRoomAdapter` | Step 9 tamamlanmış olmalı | ✅ |
| **Step 11** | System event routing + D-1 impl | `CallRoomAdapter` sonrası; network monitor refaktörü | ✅ |
| **Step 12** | Hardware/media state → adapter'lara taşı | Step 5 + Step 10 tamamlanmış olmalı | ✅ |
| **Step 13** | UI routing state → `CallScreenRouter` | Step 6 tamamlanmış olmalı | ✅ |
| **Step 14** | `fetchFollowingForInvite` → sosyal servis | Step 4 tabanına ihtiyaç var | ✅ |

---

## Step 1: `CallStateMachine` + `CallRole`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-01  
**Tamamlanma:** 2026-08-01  
**Commit:** `cc9bd511`  
**Oluşturulan dosyalar:**
- `mobile/lib/call/state/call_status.dart`
- `mobile/lib/call/state/call_role.dart`
- `mobile/lib/call/state/call_state_machine.dart`
- `mobile/test/call/state/call_state_machine_test.dart` — 42 test, tamamı geçiyor

**Değiştirilen dosyalar:**
- `mobile/lib/services/call_service.dart` — `CallStatus` kaldırıldı (re-export ile), `_currentRole` eklendi, `_setState` guard delegate edildi, `_allowedTransitions` tablosu kaldırıldı

---

**Hedef:** `call_service.dart` içindeki transition logic'i, `_allowedTransitions` tablosunu ve role kavramını saf bir Dart sınıfına taşı.

**Neden ilk:** Saf Dart, platform API yok, Flutter bağımlılığı yok. Test edilebilir. `CallService` behavior'ı değişmez — sadece delegate eder.

**Production safety:** `CallService` aynı public API'yi sunar. Hiçbir ekran, hiçbir WS handler değişmez. Compile + mevcut manual test = ship.

### 1.1 Dosya Yapısı

```
mobile/lib/
  call/
    state/
      call_role.dart           ← caller / callee enum
      call_state_machine.dart  ← transition logic
    call_service.dart          ← mevcut (bu adımda sadece delegate eklenir)
```

### 1.2 `CallRole`

```dart
// mobile/lib/call/state/call_role.dart

enum CallRole { caller, callee }
```

### 1.3 `CallStateMachine` — Public Interface

```dart
// mobile/lib/call/state/call_state_machine.dart

class CallStateMachine {
  /// Geçerli bir transition ise yeni state'i döner.
  /// Geçersiz kombinasyon → null döner (caller log'lar, state değiştirmez).
  static CallStatus? transition({
    required CallStatus current,
    required CallStatus next,
    required CallRole role,
  });

  /// Bu state + role için geçerli hedef state'lerin listesi.
  static Set<CallStatus> allowedTargets(CallStatus current, CallRole role);

  /// Bu state aktif bir arama state'i mi?
  static bool isActiveCallState(CallStatus status);
}
```

### 1.4 Transition Tablosu (mevcut `_allowedTransitions` → V2.0 uyumlu)

Mevcut `_allowedTransitions` log-only guard. Yeni versiyonda `role` parametresi eklenir:

```dart
static const Map<CallStatus, Set<CallStatus>> _callerTransitions = {
  CallStatus.idle:         {CallStatus.calling},
  CallStatus.calling:      {CallStatus.connecting, CallStatus.ended,
                            CallStatus.rejected, CallStatus.missed,
                            CallStatus.noAnswer, CallStatus.busy, CallStatus.idle},
  CallStatus.connecting:   {CallStatus.connected, CallStatus.ended,
                            CallStatus.idle, CallStatus.reconnecting},
  CallStatus.connected:    {CallStatus.ended, CallStatus.reconnecting, CallStatus.idle},
  CallStatus.reconnecting: {CallStatus.connected, CallStatus.ended, CallStatus.idle},
  CallStatus.ended:        {CallStatus.idle, CallStatus.calling},
};

static const Map<CallStatus, Set<CallStatus>> _calleeTransitions = {
  CallStatus.idle:         {CallStatus.ringing},
  CallStatus.ringing:      {CallStatus.connecting, CallStatus.ended,
                            CallStatus.missed, CallStatus.rejected, CallStatus.idle},
  CallStatus.connecting:   {CallStatus.connected, CallStatus.ended,
                            CallStatus.idle, CallStatus.reconnecting},
  CallStatus.connected:    {CallStatus.ended, CallStatus.reconnecting, CallStatus.idle},
  CallStatus.reconnecting: {CallStatus.connected, CallStatus.ended, CallStatus.idle},
  CallStatus.ended:        {CallStatus.idle},
};
```

### 1.5 `CallService` Wiring

`_setState` içindeki satır sayısı değişmez; sadece guard delegate'e gider:

```dart
// ÖNCE (call_service.dart line 384)
final allowed = _allowedTransitions[oldStatus] ?? {};
if (!allowed.contains(s.status)) {
  _cpLog('STATE', 'WARN unexpected transition ...');
}

// SONRA
final newStatus = CallStateMachine.transition(
  current: oldStatus,
  next: s.status,
  role: _currentRole,   // caller veya callee — ringing=callee, calling=caller
);
if (newStatus == null) {
  _cpLog('STATE', 'WARN blocked transition ${oldStatus.name} → ${s.status.name}');
  return; // hard block — Step 1'de test edilir, sonra açılır
}
```

> **Not:** Hard block (return) ilk anda riskli görünür. Bu yüzden Step 1'de `_cpLog` + `assert(false)` kullanılır, `return` Step 2'ye bırakılır. Test ortamında assert, production'da log — yeterli güvence.

### 1.6 `_currentRole` Nasıl Belirlenir

Mevcut kodda role implicit. Şimdi explicit hale getirilir:

```dart
CallRole? _currentRole;

// startCall() → _currentRole = CallRole.caller
// onIncomingCall() → _currentRole = CallRole.callee
// reset() → _currentRole = null
```

### 1.7 Test Stratejisi

`CallStateMachine` saf Dart — Flutter test runner gerek yok:

```dart
// test/call/state/call_state_machine_test.dart

test('caller: idle → calling geçişi geçerli', () {
  expect(
    CallStateMachine.transition(
      current: CallStatus.idle,
      next: CallStatus.calling,
      role: CallRole.caller,
    ),
    equals(CallStatus.calling),
  );
});

test('callee: idle → calling geçişi geçersiz (caller-only state)', () {
  expect(
    CallStateMachine.transition(
      current: CallStatus.idle,
      next: CallStatus.calling,
      role: CallRole.callee,
    ),
    isNull,
  );
});

test('her state için reconnecting → active geçişi geçerli (her iki role)', () {
  for (final role in CallRole.values) {
    expect(
      CallStateMachine.transition(
        current: CallStatus.reconnecting,
        next: CallStatus.connected,
        role: role,
      ),
      equals(CallStatus.connected),
    );
  }
});
```

### 1.8 Production'a Alma Kriterleri

- [ ] `CallStateMachine` dosyası oluşturuldu
- [ ] `CallRole` dosyası oluşturuldu
- [ ] `_currentRole` `CallService`'e eklendi, `startCall` ve `onIncomingCall`'da set ediliyor
- [ ] `_setState` guard `CallStateMachine.transition`'a delegate etti
- [ ] Tüm mevcut transition'lar için test yazıldı ve geçiyor
- [ ] iOS + Android'de normal arama akışı manuel test edildi
- [ ] CI build geçiyor

---

## Step 2: State İsim Uyumu (Rename)

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-01  
**Tamamlanma:** 2026-08-01  
**Commit:** `f47c2460` (rename) + `662e165a` (regression fix)

**Oluşturulan dosyalar:** —

**Değiştirilen dosyalar (f47c2460):**
- `mobile/lib/call/state/call_status.dart` — `calling` kaldırıldı; `dialing` + `waiting` eklendi; `connected` → `active`
- `mobile/lib/call/state/call_state_machine.dart` — transition tabloları güncellendi; `isActiveCallState` genişledi
- `mobile/test/call/state/call_state_machine_test.dart` — 48 test (42→48); tamamı geçiyor
- `mobile/lib/services/call_service.dart` — `dialing` (HTTP in-flight), `waiting` (callId geldi), `active` olarak ayrıştırıldı; `hasActiveCall` genişledi
- `mobile/lib/screens/call_screen.dart` — `active`, `dialing || waiting` switch case
- `mobile/lib/services/push_notification_service.dart` — `active`, `waiting`
- `mobile/lib/widgets/global_call_overlay.dart` — `active`
- `mobile/lib/widgets/incoming_call_overlay.dart` — `dialing || waiting || connecting || active`

**Split noktası:** `startCall` → POST /calls/start → 200 response: `dialing → waiting` (callId atandığı an).  
**Tek commit:** tüm 8 dosya birden değişti.

**Değiştirilen dosyalar (662e165a) — V2.0 tutarlılık review sonrası regression fix:**
- `mobile/lib/call/state/call_state_machine.dart`
  - `_callerTransitions[idle]` → `permissionDenied` eklendi (Step 1 hard block regresyonu)
  - `_calleeTransitions[connecting]` → `permissionDenied` eklendi (callee acceptCall yolu)
  - `_callerTransitions[permissionDenied]` → `ended` eklendi (`_hangUpLocally` uyumluluğu)
  - `_calleeTransitions[permissionDenied]` → `ended` eklendi
  - `_unknownRoleTransitions[idle]` + `[connecting]` → `permissionDenied` eklendi
- `mobile/test/call/state/call_state_machine_test.dart` — 53 test (48→53); 5 yeni test; tamamı geçiyor
- `mobile/lib/services/call_service.dart` — stale 2-satır yorum bloğu kaldırıldı

---

## Step 3: `EndReason` + Terminal State Absorbe

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-01  
**Tamamlanma:** 2026-08-01  
**Commit A:** `d961e82e` — EndReason additive (non-breaking)  
**Commit B:** `e153e1a2` — terminal state'ler ended+EndReason'a absorbe

**Bağımlılık:** Step 2 tamamlanmış olmalı.

---

### 3.1 Hedef

`rejected`, `missed`, `noAnswer`, `busy`, `permissionDenied` → `CallStatus.ended + EndReason` field.  
Bu 5 state `CallStatus`'tan kaldırılır; state machine yalınlaşır.

---

### 3.2 `EndReason` Enum (VoIP.md §3.5)

```dart
// mobile/lib/call/state/end_reason.dart  ← yeni dosya
enum EndReason {
  normal,           // user_call_end (her iki taraf normalce kapattı)
  rejected,         // callee reddetti
  missed,           // ring timeout — server bildirdi (ARQ)
  noAnswer,         // caller 30s timer doldu
  busy,             // /start 409 — callee meşgul
  permissionDenied, // mic izni reddedildi (caller veya callee denied)
  error,            // LiveKit/API kalıcı hata
}
```

---

### 3.3 `CallState` Değişikliği

```dart
// call_state.dart — mevcut alanlar korunur, endReason eklenir
class CallState {
  // ...mevcut alanlar...
  final EndReason? endReason;  // null = henüz belirlenmedi veya aktif arama

  const CallState({
    // ...
    this.endReason,
  });

  CallState copyWith({
    // ...
    EndReason? endReason,
    bool clearEndReason = false,  // reset() için: null'a çek
  }) {
    return CallState(
      // ...
      endReason: clearEndReason ? null : (endReason ?? this.endReason),
    );
  }
}
```

---

### 3.4 `call_service.dart` Migrasyon Haritası

| Mevcut `_setState` çağrısı | Yeni çağrı | Kaynak event |
|---|---|---|
| `status: CallStatus.rejected` | `status: ended, endReason: EndReason.rejected` | POST /reject 200 veya ws_call_rejected |
| `status: CallStatus.missed` | `status: ended, endReason: EndReason.missed` | ws_call_missed (callee ve caller) |
| `status: CallStatus.noAnswer` | `status: ended, endReason: EndReason.noAnswer` | caller 30s ringTimer |
| `status: CallStatus.busy` | `status: ended, endReason: EndReason.busy` | /start 409 |
| `status: CallStatus.permissionDenied` | `status: ended, endReason: EndReason.permissionDenied` | mic izni reddi (caller) |
| `status: CallStatus.ended` (normal) | `status: ended, endReason: EndReason.normal` | user_call_end, ws_call_ended |
| `status: CallStatus.ended` (LK hata) | `status: ended, endReason: EndReason.error` | lk_connect_failed, error_lk_permanent |

> **Not:** Callee denied mic (`ringing → ended`) zaten `ended` geçiyor; buna `endReason: EndReason.permissionDenied` eklenir.  
> Callee permanentlyDenied: state `ringing` kalıyor, `ended` tetiklenmez — endReason yok.

---

### 3.5 State Machine Değişiklikleri

**Phase A (migrasyon öncesi):**  
`_callerTransitions[idle]`'a `CallStatus.ended` ekle — mic izni reddi artık `idle → ended` doğrudan geçer.

```dart
CallStatus.idle: {
  CallStatus.dialing,
  CallStatus.ended,          // ← YENİ: mic izni reddi (permissionDenied kaldırılıyor)
  // CallStatus.permissionDenied  kaldırılacak
},
```

**Phase B (terminal state'ler temizlenince):**  
`_callerTransitions`, `_calleeTransitions`, `_unknownRoleTransitions` tablolarından `rejected`, `missed`, `noAnswer`, `busy`, `permissionDenied` hedef ve kaynak state'leri tamamen kaldırılır.

---

### 3.6 UI Migrasyon Kuralı

```dart
// ÖNCE:
cs.status == CallStatus.rejected
cs.status == CallStatus.missed
cs.status == CallStatus.busy
cs.status == CallStatus.permissionDenied

// SONRA:
cs.status == CallStatus.ended && cs.endReason == EndReason.rejected
cs.status == CallStatus.ended && cs.endReason == EndReason.missed
cs.status == CallStatus.ended && cs.endReason == EndReason.busy
cs.status == CallStatus.ended && cs.endReason == EndReason.permissionDenied
```

**Auto-pop kuralı (VoIP.md §3.5):** `ended` + `endReason != null` → 2s sonra dismiss.  
`endReason == null` → bekle (henüz belirlenmemiş).

---

### 3.7 İki Commit Stratejisi

**Commit A — Additive (non-breaking):**
- `end_reason.dart` oluştur
- `call_state.dart` → `endReason` ekle
- `call_state_machine.dart` → Phase A: `idle → ended` caller'a ekle
- `call_service.dart` → tüm terminal `_setState` çağrıları `ended + endReason`'a migrate
- UI dosyaları → `cs.status == ended && cs.endReason == X` kontrolüne geç
- Test: terminal state → ended+reason testleri güncelle

**Commit B — Cleanup:**
- `call_status.dart` → `rejected/missed/noAnswer/busy/permissionDenied` kaldır
- `call_state_machine.dart` → Phase B: tüm tablolardan terminal state'ler kaldır
- Test: artık geçersiz transition testleri kaldır, 53 → ~42 test

---

### 3.8 Etkilenen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `mobile/lib/call/state/end_reason.dart` | YENİ: EndReason enum |
| `mobile/lib/call/state/call_state.dart` | `endReason` field + copyWith |
| `mobile/lib/call/state/call_status.dart` | Commit B: 5 enum değeri kaldır |
| `mobile/lib/call/state/call_state_machine.dart` | Phase A+B state machine güncellemesi |
| `mobile/test/call/state/call_state_machine_test.dart` | Test güncellemesi |
| `mobile/lib/services/call_service.dart` | Migrasyon haritası (§3.4) |
| `mobile/lib/screens/call_screen.dart` | UI migrasyon (§3.6) |
| `mobile/lib/widgets/global_call_overlay.dart` | UI migrasyon |
| `mobile/lib/widgets/incoming_call_overlay.dart` | UI migrasyon |
| `mobile/lib/services/push_notification_service.dart` | Varsa terminal state kontrolü |

---

### 3.9 Production'a Alma Kriterleri

- [x] `end_reason.dart` oluşturuldu
- [x] `CallState.endReason` eklendi
- [x] `call_service.dart` terminal `_setState` çağrıları migrate edildi
- [x] UI dosyaları `ended + endReason` kontrolüne geçti
- [x] `call_status.dart` terminal state'ler kaldırıldı
- [x] State machine temizlendi
- [x] Testler güncellendi ve geçiyor (54→45 test)
- [ ] iOS + Android'de reject / missed / busy / noAnswer / permissionDenied senaryoları manuel test edildi

---

## Step 4: `CallRepository`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-01  
**Tamamlanma:** 2026-08-01  
**Commit:** `88d5f76a`

**Bağımlılık:** Step 3 tamamlanmış olmalı (state naming stabil).

**Log standardı (VoIP.md §13):** `CALL_REPO` MODULE tag, `API` phase.

---

### 4.1 Dosya Yapısı

```
mobile/lib/call/
  repository/
    call_repository.dart    ← CallRepository sınıfı + tüm result type'lar
```

---

### 4.2 Result Types

```dart
class CallStartResult {
  final int callId;
  final String roomName;
  final String livekitUrl;
  final String token;
}

class CallAcceptResult {
  final DateTime? acceptedAt;
  final String? token;
  final String? livekitUrl;
}

class ActiveCallResult {
  final int callId;
  final String status;       // backend string: "calling" | "active" | ...
  final String role;         // "caller" | "callee"
  final String roomName;
  final String livekitUrl;
  final String token;
  final Map<String, dynamic> otherUser;
  final DateTime? acceptedAt;
}

class CalleeTokenResult {
  final String? token;
  final String? livekitUrl;
  final String? roomName;
}
```

---

### 4.3 Repository Metotları

| Metot | HTTP | Fire-and-forget? | Retry? | Notlar |
|---|---|---|---|---|
| `startCall(calleeId)` | `POST /calls/start` | Hayır | Hayır | AppException propagate (USER_BUSY vb.) |
| `acceptCall(callId)` | `POST /calls/$id/accept` | Hayır | Evet (max 4, 500ms·n backoff) | state guard retry'da değil, caller'da |
| `rejectCall(callId)` | `POST /calls/$id/reject` | Evet | Hayır | catchError log |
| `endCall(callId)` | `POST /calls/$id/end` | Evet | Evet (1 retry, 500ms) | catchError log |
| `reportMissed(callId)` | `POST /calls/$id/missed` | Evet | Hayır | catchError log |
| `reportConnected(callId)` | `POST /calls/$id/connected` | Evet | Hayır | catchError log |
| `getActiveCall()` | `GET /calls/active` | Hayır | Hayır | null döner active_call yoksa |
| `getCallStatus(callId)` | `GET /calls/$id/status` | Hayır | Hayır | String döner: "calling"\|"active"\|... |
| `getCalleeToken(callId)` | `GET /calls/$id/callee-token` | Hayır | Hayır | token/url null olabilir |

**Auth:** Constructor parametresiz; `StorageService.instance.getAccessToken()` + `apiCall()` util direkt çağrılır (mevcut `_post`/`_get` patterni ile özdeş).

**acceptCall retry:** Retry döngüsü `CallRepository`'de — ama `status != connecting` abort kontrolü caller (CallService) sorumluluğunda. Repository sadece HTTP dener, abort sinyalini `abortSignal` callback ile alır:

```dart
Future<CallAcceptResult> acceptCall(
  int callId, {
  required bool Function() shouldAbort,  // () => status != connecting
});
```

---

### 4.4 call_service.dart Değişiklikleri

Eklenenler:
```dart
final _repository = CallRepository();
```

Her `_post('/calls/...')` ve `_get('/calls/...')` çağrısı `_repository.*` ile değiştirilir:

| Eski | Yeni |
|---|---|
| `_post('/calls/start', {'callee_id': id})` | `_repository.startCall(id)` |
| `_post('/calls/$id/accept')` (retry döngüsü) | `_repository.acceptCall(id, shouldAbort: ...)` |
| `_post('/calls/$id/reject').catchError(...)` | `_repository.rejectCall(id)` |
| `_post('/calls/$id/end').catchError(...)` (retry) | `_repository.endCall(id)` |
| `_post('/calls/$id/missed')` | `_repository.reportMissed(id)` |
| `_post('/calls/$id/connected').catchError(...)` | `_repository.reportConnected(id)` |
| `_get('/calls/active')` | `_repository.getActiveCall()` |
| `_get('/calls/$id/status')` | `_repository.getCallStatus(id)` |
| `_get('/calls/$id/callee-token')` | `_repository.getCalleeToken(id)` |

**Kapsam dışı (Step 4'te taşınmaz):**  
Group call endpoint'leri (`/invite`, `/participants/*`) — bunlar farklı flow, ayrı adımda.  
`_post`/`_get`/`_getList` helper'ları call_service'de kalır (group call'lar için hâlâ lazım).

---

### 4.5 Checklist

- [x] `call_repository.dart` oluşturuldu (result types + sınıf)
- [x] `_log()` helper: `[CALL_REPO][timestamp][API]` formatı
- [x] Her HTTP istek öncesi + yanıt sonrası log (§13.3)
- [x] `acceptCall` retry + `shouldAbort` callback
- [x] `endCall` fire-and-forget + 1 retry
- [x] `call_service.dart`: `_repository` field eklendi
- [x] Tüm call endpoint `_post`/`_get` çağrıları repository'e taşındı
- [x] `dart analyze` sıfır hata
- [x] Reject / endCall / accept senaryoları manuel test (Android→iOS)

**Test notu (2026-08-01):** Tüm CALL_REPO log path'leri doğrulandı (getCallStatus, acceptCall attempt=1 SUCCESS, rejectCall f-a-f OK, endCall f-a-f OK, reportConnected OK). Refactordan kaynaklanan sıfır hata. Testte tespit edilen iki sorun (uygulama ön plandayken iOS native Call Screen flash, arayan bitirince FCM call_ended notification) Step 7 (CallNotifAdapter) scope'unda — şu an dokunulmadı.

**Production'a alma:** `CallService` sadece `_repository.*` çağırır, call-related HTTP kodu tamamen dışarı taşındı.

---

## Step 5: `CallHardwareAdapter`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-02  
**Tamamlanma:** 2026-08-02  
**Commit (ilk):** `8159d4d6`

**Bağımlılık:** Step 4 tamamlanmış olmalı.

AVAudioSession, AudioFocus, ringback, speakerphone ve **hardware izin yönetimi** — platform'a göre ayrı impl. Klavuz: VoIP.md §6 (tüm state→side effect tabloları) + §15 (hardware izin politikası).

```
mobile/lib/call/
  hardware/
    call_hardware_adapter.dart         ← abstract interface
    ios_call_hardware_adapter.dart     ← iOS impl
    android_call_hardware_adapter.dart ← Android impl
```

---

### 5.1 Abstract Interface

```dart
abstract class CallHardwareAdapter {
  // ── Lifecycle ──────────────────────────────────────────────────────────────
  // Bluetooth CONNECT (Android 31+) ve başlangıç audio routing kurulumu.
  Future<void> init();
  Future<void> dispose();

  // ── İzin kontrolleri ───────────────────────────────────────────────────────
  // granted | denied | permanentlyDenied döner.
  Future<PermissionStatus> requestMicPermission();
  Future<PermissionStatus> requestCameraPermission();

  // ── Audio session yönetimi ─────────────────────────────────────────────────
  // iOS: AVAudioSession playAndRecord/voiceChat configure
  // Android: AudioFocus GAIN talebi
  Future<void> setupAudioSession();

  // iOS: AVAudioSession deactivate; Android: AudioFocus abandon
  Future<void> teardownAudioSession();

  // room.connect() AVAudioSession'ı override eder (§6.1 kritik kural).
  // connect() tamamlandıktan sonra playAndRecord/voiceChat yeniden configure
  // + ringback resume için çağrılır.
  Future<void> resumeAudioAfterRoomConnect();

  // ── Ringback (caller) ──────────────────────────────────────────────────────
  void startRingback();
  void stopRingback();

  // ── Ringer / vibration (callee) ────────────────────────────────────────────
  void startRinger();
  void stopRinger();

  // ── Bitiş sesleri ──────────────────────────────────────────────────────────
  // iOS: earpiece; Android: voiceCommunication context earpiece (§6.2 kritik kural)
  void playEndedSound();
  void playBusySound();

  // ── Speakerphone ───────────────────────────────────────────────────────────
  // Her zaman setupAudioSession()/resumeAudioAfterRoomConnect() SONRASI çağrılmalı.
  Future<void> setSpeaker(bool enabled);
}
```

---

### 5.2 State → Side Effect Tablosu (VoIP.md §6'dan türetildi)

Her state geçişinde `CallService` adapter metodunu çağırır:

| State | iOS çağrısı | Android çağrısı |
|---|---|---|
| `dialing` | `setupAudioSession()` + `startRingback()` | `setupAudioSession()` + `startRingback()` |
| `waiting` | — (ringback devam) | — (ringback devam) |
| `ringing` | `startRinger()` (CallKit sistem zili) | `startRinger()` (FCM bildirim + sistem zili) |
| `connecting` | `_callkitAudioReady` Completer bekler | `setupAudioSession()` direkt |
| `active` | `setSpeaker(swipeLive)` (Completer tamamlanınca) | `setSpeaker(swipeLive)` |
| `reconnecting` | `playWeakSound()` | `playWeakSound()` |
| `ended` | `playEndedSound()` / `playBusySound()` | `playEndedSound()` / `playBusySound()` |
| `idle` | `teardownAudioSession()` | `teardownAudioSession()` |

---

### 5.3 Caller Mic Akışı — `startCall()` içinde (VoIP.md §15.2)

Mic kontrolü `dialing`'e girmeden **önce**, `idle` state'indeyken yapılır:

```
requestMicPermission()
  → granted           → idle → dialing (normal devam)
  → denied            → idle → ended (endReason=permissionDenied)
                        _scheduleReset() → idle
  → permanentlyDenied → idle → ended (endReason=permissionDenied, permPermanentlyDenied=true)
                        UI: in-app modal + [Ayarlar'a Git]
                        _scheduleReset() → idle
```

> **Step 3'te yapıldı:** `idle → ended` caller geçişi state machine'e eklendi; `endReason=permissionDenied` set ediliyor. **Step 5'te tamamlandı:** `CallHardwareAdapter.requestMicPermission()` üzerinden çalışıyor.

---

### 5.4 Callee Mic Akışı — `acceptCall()` içinde (VoIP.md §15.2–15.3)

**Hedef (Step 5 sonrası):** Mic kontrolü `connecting`'e girmeden **önce**, `ringing` state'indeyken yapılır:

```
requestMicPermission()
  → granted           → ringing → connecting (normal devam)
  → denied            → ringing → ended (endReason=permissionDenied)
                        /reject fire-and-forget
  → permanentlyDenied → state ringing KALIR (geçiş yok)
                        permPermanentlyDenied=true
                        UI: in-app modal + [Ayarlar'a Git] [İptal]
                        Kullanıcı Settings'den döndüğünde:
                          app_foreground → /calls/active check
                          → hâlâ ringing: tekrar Accept edilebilir
                          → bitmişse: ringing → ended
```

**Step 5'te tamamlandı:** `.request()` ile OS dialog gösteriliyor; kontrol `connecting`'e girmeden yapılıyor (`ringing` state'inde). `denied` → `ringing → ended`; `permanentlyDenied` → `ringing` kalır (modal `IncomingCallScreen`/`IncomingCallBar` sorumluluğu — §15.3).

---

### 5.5 Kamera İzin Akışı — `toggleCamera()` sırasında (VoIP.md §15.4)

```
requestCameraPermission()
  → granted           → setCameraEnabled(true)
  → denied            → toast: "Kamera erişimi reddedildi"
  → permanentlyDenied → toast + [Ayarlar'a Git]
```

`CallStatus` değişmez. Arama sesli devam eder.

---

### 5.6 Bluetooth Android 31+ (VoIP.md §15.5)

`BLUETOOTH_CONNECT` izni `init()` içinde istenir (arama akışı dışında, app startup).  
Reddedilirse headset routing çalışmaz, arama devam eder.  
Mevcut `call_service.dart` initialization kodu `CallHardwareAdapter.init()`'e taşınır.

---

### 5.7 iOS Kritik Kural — `room.connect()` Sonrası Audio (VoIP.md §6.1)

`room.connect()` içeride AVAudioSession'ı `soloAmbient`'e çeker → ringback durur.  
Connect tamamlandıktan sonra `resumeAudioAfterRoomConnect()` çağrılır:
1. `playAndRecord/voiceChat` yeniden configure
2. Ringback devam

---

### 5.8 Production'a Alma Kriterleri

- [x] `call_hardware_adapter.dart` abstract interface oluşturuldu
- [x] `ios_call_hardware_adapter.dart` impl yazıldı
- [x] `android_call_hardware_adapter.dart` impl yazıldı
- [x] Callee mic check `ringing` state'ine taşındı (`.request()` ile, `connecting`'e girmeden önce)
- [x] `room.connect()` sonrası `_hardware.resumeAfterRoomConnect()` çağrılıyor (iOS)
- [x] `CallService` `_hardware.*` çağırıyor; platform kodu service'den tamamen ayrıldı
- [x] **[BUG FIX]** Callee `permanentlyDenied`: state `ringing` kalıyor, `permPermanentlyDenied=true` set ediliyor (VoIP.md §15.3)
- [x] **[BUG FIX]** Callee mic `denied`: `_repository.rejectCall(callId)` çağrılıyor, caller beklemiyor (VoIP.md §15.2)
- [x] **[EKSIK UI FIX]** Caller `permanentlyDenied` → `GlobalCallOverlay._handleCallerPermissionDenied()` eklendi: Snackbar/AlertDialog (VoIP.md §7.3 Kural 5)
- [x] **[EKSIK UI FIX]** Callee `permanentlyDenied` → `IncomingCallScreen._showPermPermanentlyDeniedModal()` + `IncomingCallBar` await+check eklendi (VoIP.md §15.3)
- [ ] iOS + Android'de ses routing, izin senaryoları manuel test edildi

**Test notu:** dart analyze 0 error. Manuel test: ses routing (earpiece/speaker), mic permission dialog, iOS ringback restore, Android setCallConnected davranışı doğrulanmalı.

---

## Step 6: `CallScreenRouter`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-02  
**Tamamlanma:** 2026-08-02  
**Commit:** `adf96514`

**Bağımlılık:** Step 3 tamamlanmış olmalı (CallStatus + EndReason stabil).

Ekran kararlarını merkeze al — mevcut dağınık `isCallScreenVisible`, `preventCallScreenAutoOpen` mantığı:

```
mobile/lib/call/
  routing/
    call_screen_router.dart
```

VoIP.md §7.1 altı ekran tipi tanımlar:

| Ekran | Kime | Tetikleyen |
|---|---|---|
| `CallScreen` | Caller + Callee | App önplanda, aktif arama |
| `IncomingCallScreen` | Callee | App önplanda, ringing state |
| `IncomingCallBar` | Callee | App arka planda veya SwipeLive aktifken, ringing |
| `MinimizedCallBar` | Caller + Callee | App arka planda veya SwipeLive aktifken, active/reconnecting |
| CallKit Native UI | iOS Callee | OS seviyesi — router karar vermez |
| FCM Notification | Android Callee | OS seviyesi — router karar vermez |

Router sadece uygulama içi kararları verir; OS-seviyesi UI'yi (CallKit / FCM) adapter katmanı yönetir.

```dart
/// Uygulama içi ekran kararı. OS-seviyesi UI (CallKit, FCM bildirim) dahil değil.
enum CallScreenDecision {
  callScreen,       // Caller/Callee önplanda, aktif arama (dialing→active→reconnecting)
  incomingScreen,   // Callee önplanda, ringing
  incomingBar,      // Callee arka planda / SwipeLive aktif, ringing
  minimizedBar,     // Caller/Callee arka planda / SwipeLive aktif, active/reconnecting
  none,             // idle veya ended — ekran açılmaz / kapatılır
}

class CallScreenRouter {
  static CallScreenDecision resolveScreen({
    required CallStatus status,
    required EndReason? endReason,
    required CallRole role,
    required bool swipeLiveActive,
    required bool isBackground,
    required TargetPlatform platform,
  });
}
```

**`ended + permissionDenied + !isCallScreenVisible` (VoIP.md §7.3 Kural 5):**

Bu case `CallScreenRouter`'ın kapsamı dışındadır — router ekran kararı verir, hata bildirimi değil. `GlobalCallOverlay` doğrudan state'i dinleyerek handle eder:

```dart
// GlobalCallOverlay._onStateChange() içinde
if (cs.status == CallStatus.ended &&
    cs.endReason == EndReason.permissionDenied &&
    !_cs.isCallScreenVisible.value) {
  if (cs.permPermanentlyDenied) {
    // AlertDialog: "Mikrofon erişimi Ayarlar'dan verilmeli" + [Ayarlar'a Git]
    _showMicPermissionDialog(context);
  } else {
    // Snackbar: "Mikrofon izni gerekli"
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
}
```

Callee `permanentlyDenied` case'i `IncomingCallScreen`/`IncomingCallBar` sorumluluğundadır (§15.3) — `GlobalCallOverlay` müdahale etmez.
```

### Production'a Alma Kriterleri

- [x] `call_screen_router.dart` — `CallScreenDecision` enum + `resolveScreen()` static method
- [x] `CallService.currentRole` getter — router'ın role'e erişimi için
- [x] `incoming_call_overlay._onCallState()` — router üzerinden karar; inline status enum karşılaştırması kaldırıldı
- [x] `dart analyze` 0 hata
- [ ] Dialing/waiting/connecting/active/ended state'leri için routing kararlarının doğru ekrana yönlendirdiği manuel test

**Production'a alma:** `CallScreenDecision` enum tek karar noktası; `incoming_call_overlay` routing mantığını doğrudan barındırmıyor.

---

## Step 7: `CallNotifAdapter`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-02  
**Tamamlanma:** 2026-08-02  
**Commit:** `061bf1ac`

**Bağımlılık:** Step 5 tamamlanmış olmalı.

VoIP token kayıt, FCM token kayıt, CallKit raporlama:

```
mobile/lib/call/
  notif/
    call_notif_adapter.dart         ← abstract base + formatCallId() + sendWithRetry()
    ios_call_notif_adapter.dart     ← VoIP token retry + FCM + CallKit endCall/endAllCalls
    android_call_notif_adapter.dart ← FCM only (voipToken=null) + CallKit endCall/endAllCalls
```

**Token yönetimi — implementasyon notları (VoIP.md §12.2–12.4'ten):**

| Konu | Kural |
|---|---|
| iOS push kanalı | VoIP push her zaman FCM'e tercih edilir — FCM CallKit'i tetikleyemez |
| iOS `var\|var` durumu | `voip_token` varsa FCM'e bakma — VoIP push gönder |
| Android | Yalnızca FCM token; voip_token register edilmez |
| Stale token | APNs/FCM hata döndürürse backend `voip_token = NULL` / FCM token sil |
| Multi-device | Mevcut model tek cihaz varsayımı — son kaydeden kazanır; çoklu cihaz desteği bu adımın kapsamı dışında |

**Backend `/calls/start` push seçim mantığı:**
```python
if callee_ws_connected:
    pass  # WS yeterli
elif callee.voip_token:
    send_voip_push(callee.voip_token, payload)   # iOS
elif callee.fcm_token:
    send_fcm_push(callee.fcm_token, payload)     # Android
# else: foreground-only (WS bağlıysa alır, değilse kaybolur)
```

### Checklist

- [x] `call_notif_adapter.dart` — abstract interface + `formatCallId()` + `sendWithRetry()` oluşturuldu
- [x] `ios_call_notif_adapter.dart` — `registerTokens()`: FCM + VoIP token (3s retry) + `AuthService.saveDeviceTokens()`
- [x] `android_call_notif_adapter.dart` — `registerTokens()`: FCM only (`voipToken: null`) + `AuthService.saveDeviceTokens()`
- [x] `call_service.dart`: `_notif` field eklendi (Platform.isIOS seçer); `_hangUpLocally` + `reset()` → `_notif.reportCallEnded()` / `_notif.endAllCalls()`
- [x] `call_service.dart`: `_formatToUuid()` kaldırıldı → `CallNotifAdapter.formatCallId()` (6 call site)
- [x] `push_notification_service.dart`: `_registerToken()` + `_sendTokenToBackend()` kaldırıldı (dead code); tüm call site'lar `notifAdapter.registerTokens()` kullanıyor
- [x] `push_notification_service.dart`: `auth_service.dart` import kaldırıldı (artık kullanılmıyor)
- [x] `dart analyze` 0 warning (2 pre-existing info: unnecessary_import + deprecated_member_use)
- [ ] iOS + Android'de token registration, VoIP token retry, callkit dismissal manuel test edildi

**`dismissIncomingCall` NOT:** Yalnızca notification-triggered reject akışında (`push_notification_service._rejectCallById`) gerekli — normal call end adapter'ında değil. Adapter'a taşınmadı.  
**`FlutterCallkitIncoming` import NOT:** `call_service.dart`'ta kaldı — `startCall()` (iOS outgoing indicator) + ghost/busy dismissal `onIncomingCall()` hâlâ direkt çağırıyor.

---

## Step 8: `CallState` Ekstraksiyonu + Dead Code Temizliği

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-02  
**Tamamlanma:** 2026-08-02  
**Commit:** `(aşağıda)`

**Bağımlılık:** Step 1–7 tamamlanmış olmalı.

**Orijinal hedef (aspirasyonel):** `call_service.dart` ~2645 → ~300 satır.  
**Gerçekleşen:** 2297 → 2186 satır. LiveKit room yönetimi (`_joinRoom`, `_onRoomEvent`, ~600 satır) audio session kırılganlığı nedeniyle V3.0'a ertelendi — bkz. `documents/VoIP/V3.0/deferred.md`.

**Yapılanlar:**

- `CallState` → `call/state/call_state.dart` ayrı dosyaya taşındı (111 satır azalma)
- `CallApiException` kaldırıldı (dosya dışında hiçbir yerde kullanılmıyordu, dead code)
- `call_service.dart`: `import + export '../call/state/call_state.dart'` eklendi — tüm mevcut importlar kırılmadan çalışıyor

### Checklist

- [x] `call/state/call_state.dart` oluşturuldu — `CallStatus`, `EndReason`, `CallParticipant`/`GroupInvite` bağımlılıkları doğru import edildi
- [x] `CallApiException` kaldırıldı (dead code — dosya dışında referans yoktu)
- [x] `call_service.dart` → `export '../call/state/call_state.dart'` eklendi, tüketici dosyalar değişmedi
- [x] `dart analyze` 0 warning (2 pre-existing info: unnecessary_import + deprecated_member_use)
- [x] V3.0 ertelenen kapsam `documents/VoIP/V3.0/deferred.md`'de belgelendi

**V2.0 refactoring cycle tamamlandı.** Çıkarılan modüller:

| Modül | Dosya | Satır |
|---|---|---|
| `CallStateMachine` + `CallRole` | `call/state/call_state_machine.dart` | Step 1 |
| `EndReason` | `call/state/end_reason.dart` | Step 3 |
| `CallRepository` | `call/repository/call_repository.dart` | Step 4 |
| `CallHardwareAdapter` (iOS + Android) | `call/hardware/` | Step 5 |
| `CallScreenRouter` | `call/routing/call_screen_router.dart` | Step 6 |
| `CallNotifAdapter` (iOS + Android) | `call/notif/` | Step 7 |
| `CallState` | `call/state/call_state.dart` | Step 8 |

---

## Step 9: Grup Call HTTP → `CallRepository`

**Durum:** ✅ Tamamlandı  
**Commit:** `6e03ee03`

**Bağımlılık:** Step 4 tamamlanmış olmalı (additive extension).

Step 4'te yalnızca 1:1 çağrı endpoint'leri `CallRepository`'ye taşındı. Grup çağrısı endpoint'leri `CallService._post()` üzerinden çağrılıyordu. Bu step'te 5 grup endpoint'i repository'ye taşındı; `_post()` kaldırıldı, `_authHeaders()` + `_getList()` `fetchFollowingForInvite` için kaldı (Step 14'te temizlenecek).

### 9.1 `CallRepository`'ye Eklenecek Metodlar

| Metot | HTTP | Fire-and-forget? |
|---|---|---|
| `inviteParticipant(callId, inviteeId)` | `POST /calls/$id/invite` | Hayır (rethrow) |
| `acceptGroupParticipant(callId, participantId)` | `POST /calls/$id/participants/$pid/accept` | Hayır (response döner) |
| `rejectGroupParticipant(callId, participantId)` | `POST /calls/$id/participants/$pid/reject` | Evet |
| `leaveGroupCall(callId, participantId)` | `POST /calls/$id/participants/$pid/leave` | Evet |
| `removeParticipant(callId, userId)` | `POST /calls/$id/participants/$uid/remove` | Hayır (rethrow) |

### 9.2 `call_service.dart` Değişiklikleri

Her `_post('/calls/...')` grup çağrısı `_repository.*` ile değiştirilir.

`_getList('/follows/$myId/following')` çağrısı `fetchFollowingForInvite()` içinde kullanılıyor — follows verisi call repository'nin sorumluluğu değil, ayrı bir endpoint. `_getList` + `_authHeaders` bu step'te **kaldırılmaz** (Step 10 kapsamında değerlendirmeye alınır).

### 9.3 Checklist

- [x] `call_repository.dart`: 5 grup endpoint metodu eklendi (inviteParticipant, acceptGroupParticipant, rejectGroupParticipant, leaveGroupCall, removeParticipant)
- [x] `call_service.dart`: grup call `_post()` çağrıları `_repository.*`'e migrate edildi
- [x] `call_service.dart`: `_post()` kaldırıldı; `_authHeaders()` + `_getList()` `fetchFollowingForInvite` için kaldı
- [x] `dart analyze` 0 warning (2 pre-existing info)
- [ ] Grup davet alma / kabul / red / ayrılma / çıkarma senaryoları manuel test edildi

---

## Step 10: `CallRoomAdapter`

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-02  
**Tamamlanma:** 2026-08-02  
**Commit:** (bu commit)

**Bağımlılık:** Step 9 tamamlanmış olmalı.

LiveKit room yönetimini `CallService`'ten izole eder.

```
mobile/lib/call/
  room/
    call_room_adapter.dart    ← tüm LiveKit room mantığı burada
```

**Mimari karar:** Tek dosya, callback-based coupling. Adapter constructor'ı 6 parametre alır: `hardware`, `preventCallScreenAutoOpen`, `getState`, `setState`, `onConnected`, `endCall`. Bu yeterli izolasyon sağladı; ayrı interface dosyası gerekmedi.

**Kapsam dışı bırakılanlar** (iç içe geçmiş bağımlılık nedeniyle):
- `_transitionToConnected` — `stopRingtoneAndVibration`, `_startProximitySensor`, `_repository.reportConnected` çağırıyor; CallService'te kaldı
- `_startStatsMonitor/Network/ProximitySensor` — `setSpeaker()` döngüsü nedeniyle CallService'te kaldı
- `toggleMute`, `setSpeaker`, `toggleCamera`, `switchCamera` — public API, `_roomAdapter.room` getter üzerinden erişiyor

### 10.1 Gerçekleştirilen Interface

```dart
class CallRoomAdapter {
  CallRoomAdapter({
    required CallHardwareAdapter hardware,
    required ValueNotifier<bool> preventCallScreenAutoOpen,
    required CallState Function() getState,
    required void Function(CallState) setState,
    required void Function(String context) onConnected,
    required void Function() endCall,
  });

  Room? get room;
  bool get isJoiningRoom;

  Future<void> joinRoom({required String livekitUrl, required String token});
  Future<void> activateCalleeAudio();
  Future<void> disconnect();
}
```

### 10.2 `call_service.dart`'tan Taşınanlar

- `_joinRoom()` (~190 satır) → `joinRoom()` ✅
- `_onRoomEvent()` (~195 satır) → `_onRoomEvent()` (private) ✅
- `_activateCalleeAudio()` (~57 satır) → `activateCalleeAudio()` ✅
- `_setupAudioInterruptionListener()` (~25 satır) → private, `joinRoom()` sonunda çağrılır ✅
- `_room`, `_roomEventsSubscription`, `_audioInterruptionSubscription`, `_peerTimeoutTimer`, `_isJoiningRoom` → adapter'a taşındı ✅
- `_disconnectRoom()` → timer'ları iptal edip `_roomAdapter.disconnect()` çağırır ✅

### 10.3 Kritik Test Senaryoları

- iOS caller: ringback → pre-connect → `resumeAfterRoomConnect()` → kabul → mic açılması
- iOS callee: `waitForCallkitAudio()` sıralaması → mic → speaker
- Android callee: `onCallConnected()` zamanlaması
- Pre-connect sırasında `room.connect()` hatası → çağrı korunuyor mu?
- Reconnecting → active geçişinde ses kesiliyor mu?
- Group invite (iOS): `onAudioSessionActivated()` simülasyonu çalışıyor mu?

### 10.4 Checklist

- [x] `call_room_adapter.dart` oluşturuldu (`mobile/lib/call/room/`)
- [x] `call_service.dart`: `_room` ve ilgili field'lar kaldırıldı, `_roomAdapter` eklendi
- [x] Constructor'da `_roomAdapter` initialize edildi (6 callback)
- [x] Tüm `_joinRoom()` → `_roomAdapter.joinRoom()` delegate edildi
- [x] Tüm `_activateCalleeAudio()` → `_roomAdapter.activateCalleeAudio()` delegate edildi
- [x] `_room` referansları → `_roomAdapter.room` güncellendi (37+ yer)
- [x] `_disconnectRoom()` → orchestration sadece, room cleanup `adapter.disconnect()`'e
- [x] `dart analyze` 0 warning ✅
- [ ] Tüm kritik test senaryoları (§10.3) her iki platformda doğrulanacak

---

## Step 11: System Event Routing + D-1 Implementation

**Durum:** 🔴 Başlamadı  
**Bağımlılık:** Step 10 tamamlanmış olmalı.

VoIP.md §5.9 (D-6) kararının implementasyonu. Mevcut `_startNetworkMonitor` sadece `active`/`reconnecting`'i izliyor ve sadece log yazıyor — processEvent çağırmıyor. D-1 (20s timer for `network_lost` in `waiting`) hiç implement edilmemiş.

### 11.1 Değişiklikler

**`call_service.dart` — `_startNetworkMonitor` refaktörü:**

```dart
void _startNetworkMonitor() {
  _networkSub?.cancel();
  _prevNetworkType = null;
  _cpLog('LK', 'networkMonitor START | callId=${state.value.callId}');
  _networkSub = Connectivity().onConnectivityChanged.listen((results) {
    final activeStatuses = {
      CallStatus.dialing, CallStatus.waiting, CallStatus.connecting,
      CallStatus.active, CallStatus.reconnecting,
    };
    if (!activeStatuses.contains(state.value.status)) return;

    final newType = results.isNotEmpty ? results.first : ConnectivityResult.none;
    if (newType == _prevNetworkType) return;
    final prevType = _prevNetworkType;
    _prevNetworkType = newType;

    if (newType == ConnectivityResult.none) {
      _cpLog('LK', 'networkChange → network_lost | status=${state.value.status.name}');
      _handleSystemEvent('network_lost');
    } else if (prevType == ConnectivityResult.none) {
      _cpLog('LK', 'networkChange → network_restored | status=${state.value.status.name}');
      _handleSystemEvent('network_restored');
    }
  });
}

void _handleSystemEvent(String type) {
  final status = state.value.status;
  switch (type) {
    case 'network_lost':
      if (status == CallStatus.waiting) {
        // D-1: 20s bekle, sonra ended
        _networkLostInWaitingTimer?.cancel();
        _networkLostInWaitingTimer = Timer(const Duration(seconds: 20), () {
          if (state.value.status == CallStatus.waiting) {
            _cpLog('TIMER', 'D-1 timer fired: waiting + network_lost → ended');
            _hangUpLocally(endReason: EndReason.error);
          }
        });
      } else if (status == CallStatus.dialing) {
        _hangUpLocally(endReason: EndReason.error);
      } else if (status == CallStatus.connecting) {
        _hangUpLocally(endReason: EndReason.error);
      }
      // active → reconnecting zaten LiveKit'in kendi reconnect mekanizması
      // reconnecting → LK retry devam eder, timer_peer_expired ile zaten yönetiliyor
    case 'network_restored':
      if (status == CallStatus.waiting) {
        _networkLostInWaitingTimer?.cancel();
        _networkLostInWaitingTimer = null;
        _cpLog('LK', 'D-1 timer CANCELLED — network restored in waiting');
      }
      // reconnecting: LK retry kendisi devam eder
  }
}
```

**Yeni field:**
```dart
Timer? _networkLostInWaitingTimer;
```

**`_disconnectRoom()` veya `reset()` içinde:**
```dart
_networkLostInWaitingTimer?.cancel();
_networkLostInWaitingTimer = null;
```

### 11.2 Transition Tablosu Doğrulaması

§5.2 `dialing` + `network_lost` → `ended` ✅ (yeni kod)  
§5.3 `waiting` + `network_lost` → 20s timer → `ended` ✅ (D-1, yeni kod)  
§5.3 `waiting` + `network_restored` → timer iptal ✅ (yeni kod)  
§5.5 `connecting` + `network_lost` → `ended` ✅ (yeni kod)  
§5.6 `active` + `network_lost` → `reconnecting` — LK kendi halleder, kod yok (doğru)  
§5.7 `reconnecting` + `network_restored` → `reconnecting` — LK retry devam, kod yok (doğru)  

### 11.3 Checklist

- [x] `_startNetworkMonitor` tüm aktif state'leri kapsıyor (`dialing`, `waiting`, `connecting`, `active`, `reconnecting`)
- [x] `_handleNetworkLost` ve `_handleNetworkRestored` metodları eklendi
- [x] `_networkLostInWaitingTimer` field eklendi
- [x] `_disconnectRoom()` içinde timer iptal ediliyor
- [x] `reset()` içinde timer iptal ediliyor
- [x] `startCall` başında `_startNetworkMonitor()` çağrısı — `dialing` state'ini de kapsar
- [x] D-1: `waiting` + `network_lost` → 20s → `ended` implement edildi
- [x] `waiting` + `network_restored` → D-1 timer iptal
- [x] `dialing` + `network_lost` → `ended` implement edildi
- [x] `connecting` + `network_lost` → `ended` implement edildi
- [x] `dart analyze` 0 warning ✅

---

## Step 12: Hardware/Media State → Adapter'lara Taşı

**Durum:** ✅ Tamamlandı  
**Bağımlılık:** Step 5 (`CallHardwareAdapter`) + Step 10 (`CallRoomAdapter`) tamamlanmış olmalı.

VoIP.md D-7 kararının implementasyonu. `CallState.isSpeaker`, `CallState.localVideoEnabled`, `CallState.remoteVideoEnabled` domain state'ten çıkar; ilgili adapter'lara `ValueNotifier<bool>` olarak taşınır.

### 12.1 `isSpeaker` → `CallHardwareAdapter`

**`call_hardware_adapter.dart`'a ekle:**
```dart
final ValueNotifier<bool> isSpeaker = ValueNotifier<bool>(false);
```

**`setSpeaker()` metodu güncellemesi (adapter içinde):**
```dart
Future<void> setSpeaker(bool enabled) async {
  // mevcut platform kodu...
  isSpeaker.value = enabled;
}
```

**`call_service.dart` — `setSpeaker()` değişikliği:**
```dart
// ÖNCE:
Future<void> setSpeaker(bool enabled) async {
  await _hardware.setSpeaker(enabled);
  _setState(state.value.copyWith(isSpeaker: enabled));  // ← kaldırılacak
}

// SONRA:
Future<void> setSpeaker(bool enabled) async {
  await _hardware.setSpeaker(enabled);
  // isSpeaker artık _hardware.isSpeaker ValueNotifier üzerinden
}
```

**`call_service.dart` — UI erişim için getter:**
```dart
ValueNotifier<bool> get isSpeaker => _hardware.isSpeaker;
```

**Proximity sensor güncelleme:**
```dart
// Mevcut: state.value.isSpeaker
// Yeni:   _hardware.isSpeaker.value
if (isNear && _hardware.isSpeaker.value) { ... }
```

### 12.2 `localVideoEnabled`/`remoteVideoEnabled` → `CallRoomAdapter`

**`call_room_adapter.dart`'a ekle:**
```dart
final ValueNotifier<bool> localVideoEnabled = ValueNotifier<bool>(false);
final ValueNotifier<bool> remoteVideoEnabled = ValueNotifier<bool>(false);
```

**Güncelleme noktaları (`call_room_adapter.dart` içinde `_onRoomEvent`):**
- `lk_peer_joined` / track update → `remoteVideoEnabled.value = ...`
- `lk_peer_left` → `remoteVideoEnabled.value = false`

**`call_service.dart` — `toggleCamera()` değişikliği:**
```dart
// ÖNCE:
_setState(state.value.copyWith(localVideoEnabled: !enabled));

// SONRA:
_roomAdapter.localVideoEnabled.value = !enabled;
```

**`call_service.dart` — UI erişim için getter'lar:**
```dart
ValueNotifier<bool> get localVideoEnabled => _roomAdapter.localVideoEnabled;
ValueNotifier<bool> get remoteVideoEnabled => _roomAdapter.remoteVideoEnabled;
```

### 12.3 `CallState` Temizliği

`CallState` sınıfından kaldırılacak field'lar:
- `isSpeaker`
- `localVideoEnabled`
- `remoteVideoEnabled`

`copyWith` parametrelerinden de kaldırılır.

**UI consumer güncellemesi:**
```dart
// ÖNCE: cs.state.value.isSpeaker
// SONRA: cs.isSpeaker.value

// ÖNCE: cs.state.value.localVideoEnabled
// SONRA: cs.localVideoEnabled.value

// ÖNCE: cs.state.value.remoteVideoEnabled
// SONRA: cs.remoteVideoEnabled.value
```

UI widget'larında `ValueListenableBuilder` veya `.addListener` kullanarak güncel değer okunur.

### 12.4 Checklist

- [x] `CallHardwareAdapter.isSpeaker: ValueNotifier<bool>` eklendi
- [x] `CallHardwareAdapter.setSpeaker()` notifier'ı günceller
- [x] `CallRoomAdapter.localVideoEnabled: ValueNotifier<bool>` eklendi
- [x] `CallRoomAdapter.remoteVideoEnabled: ValueNotifier<bool>` eklendi
- [x] `CallState` — `isSpeaker`, `localVideoEnabled`, `remoteVideoEnabled` kaldırıldı
- [x] `CallService` — `isSpeaker`, `localVideoEnabled`, `remoteVideoEnabled` getter'ları eklendi
- [x] `CallService._startProximitySensor` → `_hardware.isSpeaker.value` güncellendi
- [x] `CallService.setSpeaker()` → `_setState` satırı kaldırıldı
- [x] `CallService.toggleCamera()` → `_roomAdapter.localVideoEnabled.value` güncellendi
- [x] Tüm UI consumer'lar güncellendi (`call_screen.dart`, `global_call_overlay.dart`)
- [x] `dart analyze` 0 error ✅

---

## Step 13: UI Routing State → `CallScreenRouter`

**Durum:** ✅ Tamamlandı  
**Bağımlılık:** Step 6 (`CallScreenRouter`) tamamlanmış olmalı.

VoIP.md D-8 kararının implementasyonu. `isCallScreenVisible` ve `preventCallScreenAutoOpen` `CallService`'ten `CallScreenRouter`'a taşınır.

### 13.1 `isCallScreenVisible` → `CallScreenRouter`

Bu notifier `CallScreenRouter` tarafından set edilir — ekranın açılıp kapandığını router bilir.

**`call_screen_router.dart`'a taşı:**
```dart
final ValueNotifier<bool> isCallScreenVisible = ValueNotifier<bool>(false);
```

**`call_service.dart`:**
```dart
// Kaldırılır:
// final isCallScreenVisible = ValueNotifier<bool>(false);

// Eklenir (geriye dönük uyumluluk için getter):
ValueNotifier<bool> get isCallScreenVisible => _router.isCallScreenVisible;
```

### 13.2 `preventCallScreenAutoOpen` → `CallScreenRouter`

Bu notifier SwipeLive widget'ı tarafından set edilir; `CallScreenRouter`'ın routing kararını etkiler.

**`call_screen_router.dart`'a taşı:**
```dart
final ValueNotifier<bool> preventCallScreenAutoOpen = ValueNotifier<bool>(false);
```

**`call_service.dart`:**
```dart
// Kaldırılır:
// final preventCallScreenAutoOpen = ValueNotifier<bool>(false);

// Getter — SwipeLive ve CallRoomAdapter hâlâ erişebilsin:
ValueNotifier<bool> get preventCallScreenAutoOpen => _router.preventCallScreenAutoOpen;
```

**`CallRoomAdapter` bağımlılığı:**  
`CallRoomAdapter` constructor'ı şu an `preventCallScreenAutoOpen` alıyor. Step 13 sonrasında bu parametre hâlâ geçilebilir — değer `_router.preventCallScreenAutoOpen`'dan gelir; interface değişmez.

### 13.3 `reset()` güncelleme

Mevcut `reset()` içinde:
```dart
preventCallScreenAutoOpen.value = false;
```
Bu satır Step 13 sonrasında otomatik olarak `_router.preventCallScreenAutoOpen.value = false` ile eşdeğer olur (getter üzerinden).

### 13.4 Checklist

- [x] `CallScreenRouter.isCallScreenVisible` eklendi
- [x] `CallScreenRouter.preventCallScreenAutoOpen` eklendi
- [x] `CallService.isCallScreenVisible` — field kaldırıldı, getter eklendi
- [x] `CallService.preventCallScreenAutoOpen` — field kaldırıldı, getter eklendi
- [x] Tüm consumer'lar hâlâ `cs.isCallScreenVisible` / `cs.preventCallScreenAutoOpen` üzerinden erişiyor (getter sayesinde arayüz değişmez)
- [x] `dart analyze` 0 error ✅

---

## Step 14: `fetchFollowingForInvite` → Sosyal Servis

**Durum:** ✅ Tamamlandı  
**Bağımlılık:** `_post`/`_get`/`_authHeaders` metodları `CallService`'ten hâlâ kaldırılmamış olabilir — Step 9'dan sonra sadece `fetchFollowingForInvite` bunu kullanıyor.

### 14.1 Sorun

`CallService.fetchFollowingForInvite()` `/follows/$myId/following` endpoint'ini çağırıyor. Bu sosyal domain verisi — arama servisiyle ilgisi yok. Step 9'da `_post`/`_get`/`_authHeaders` kaldırılması planlanmıştı ama bu metod yüzünden yapılamadı.

### 14.2 Çözüm

**Option A (tercih edilen):** `fetchFollowingForInvite` `CallRepository`'ye değil, yeni bir `FollowsRepository` veya mevcut bir sosyal servise taşınır. Grup arama UI'ı bu servisi doğrudan çağırır.

**Option B (minimal):** `fetchFollowingForInvite` `CallRepository`'ye geçici olarak taşınır (diğer call API çağrıları ile aynı yerde), `CallService`'ten kaldırılır. Tam ayrıştırma ayrı bir adımda yapılır.

### 14.3 Checklist

- [x] `fetchFollowingForInvite` `CallService`'ten kaldırıldı
- [x] `FollowsService` olarak `mobile/lib/services/follows_service.dart`'a taşındı (Option A)
- [x] `_getList`, `_authHeaders` `CallService`'ten kaldırıldı (artık kullanan yok)
- [x] `dart:convert`, `package:http/http.dart` `CallService`'ten kaldırıldı
- [x] `call_screen.dart` → `FollowsService.fetchFollowingForInvite()` kullanıyor
- [x] `dart analyze` 0 error ✅

---

## Karar Logu

Refactoring sırasında alınan kararlar buraya kaydedilir.

| Tarih | Konu | Karar | Gerekçe |
|---|---|---|---|
| 2026-08-01 | Step 1 hard block | `assert` + log, return değil | Production güvenliliği — test sonrası Step 2'de hard block açılır |
| 2026-08-01 | Terminal state absorbe zamanı | Step 3 (Step 2 sonrası) | İsimler stabil olmadan absorbe riski yüksek |
| 2026-08-01 | iOS push kanalı seçimi | VoIP push > FCM; voip_token varsa FCM göz ardı edilir | FCM data push iOS background'da CallKit'i tetikleyemez; VoIP push APNs'in yüksek öncelikli kanalıdır — gözlemlenen FCM/VoIP karışıklığının kök nedeni |
| 2026-08-01 | Multi-device token modeli | Tek cihaz varsayımı (son kaydeden kazanır) | V2.0 kapsamı dışında; gerekirse `(user_id, device_id, token_type)` PK'lı tablo migrasyonu ayrı adım olarak ele alınır |
| 2026-08-01 | `idle → permissionDenied` transition | Caller tablosuna eklendi | Step 1 hard block regresyonu: mic izni reddinde `_setState(permissionDenied)` `idle`'dan çağrılıyor; önceden log-only guard'da gizleniyordu |
| 2026-08-01 | `connecting → permissionDenied` transition | Callee tablosuna eklendi; `permissionDenied → ended` de eklendi | Callee acceptCall yolunda mic yoksa `connecting → permissionDenied → ended` gerekiyor; `_hangUpLocally(ended)` permissionDenied üzerinden çalışmalı |
| 2026-08-01 | `connecting → reconnecting` belgelendi | VoIP.md §5.5'e eklendi | `RoomReconnectingEvent` connecting state'indeyken de tetiklenebilir; kod izin veriyor ama doc eksikti |
| 2026-08-01 | Hardware izin politikası | VoIP.md §15 olarak eklendi | Her kombinasyonun davranışı tanımlanmadan Step 5 uygulaması riskli; endüstri standardı analizi sonrası karara varıldı |
| 2026-08-01 | Mikrofon = call-blocking | Her iki taraf için de `.request()` ile kontrol edilir; izin yoksa arama başlamaz/devam etmez | Mikrofonsuz sesli arama anlamsız; industry standard (WhatsApp, FaceTime) |
| 2026-08-01 | Kamera = non-blocking, audio-first | Toggle sırasında `.request()` gösterilir; CallStatus değişmez; direkt görüntülü arama planlanmıyor | Kullanıcı kararı: "şuan sadece arama temelli görüntülü konuşma var" |
| 2026-08-01 | Bluetooth Android 31+ = app startup | Arama akışı dışında; başlangıçta istenir; reddedilirse headset routing çalışmaz, arama devam eder | Arama sırasında `BLUETOOTH_CONNECT` istenmesi hatalı UX; app startup'ta halledilmeli |
| 2026-08-01 | Kalıcı reddedilmiş mic — callee | State `ringing` kalır; in-app modal + Ayarlar butonu; kullanıcı döndüğünde tekrar Accept edebilir | Kullanıcı kararı: "kullanıcıya fırsat verilsin"; hemen bitirmek yerine Settings redirect |
| 2026-08-01 | Callee mic check timing değişikliği | Mevcut: `.status` SONRA `connecting`; Hedef: `.request()` ÖNCE `connecting` — Step 5'te uygulanacak | Yanlış timing: kullanıcı OS dialog'unu görmeden `connecting` state'e giriyor |
| 2026-08-01 | `connecting → permissionDenied` callee geçici | Step 5'te kaldırılacak (mic check `connecting`'e girmeden olacak) | Şimdilik mevcut code ile uyumlu; Step 5 sonrası dead code olur |
| 2026-08-01 | Ghost cleanup Redis gap (backend bug) | `cleanup_ghost_calls_task` içine `clear_call_redis(call_id)` çağrısı eklenmeli | §16.10 spec review sırasında tespit edildi: ghost temizlenince `call:{id}:participants` key (3h TTL) temizlenmiyor; `delayed_call_timeout_task` bunu yapıyor ama ghost task yapmıyor — stale Redis state 3 saate kadar kalabilir |
| 2026-08-02 | Caller mic denied UI kararı | `GlobalCallOverlay` handle eder — CallScreen açılmaz | `idle → ended (permissionDenied)` case'inde `isCallScreenVisible=false`; CallScreen açmak semantik olarak yanlış ("arama başlamadı"); Overlay zaten `!isCallScreenVisible` durumunda call UI fallback görevi yapıyor |
| 2026-08-02 | D-6 system event routing | Network olayları `processEvent` üzerinden geçer | Mevcut `_startNetworkMonitor` sadece logluyor ve sadece `active`/`reconnecting`'i izliyor; D-1 implement edilmemiş; unified event bus prensibi state geçişi üretebilecek her olayın tek noktadan girmesini gerektirir |
| 2026-08-02 | D-7 hardware/media state ownership | `isSpeaker`, `localVideoEnabled`, `remoteVideoEnabled` domain state'ten çıkar | D-4'ün genelleştirilmesi; `CallState` yalnızca domain state taşımalı; adapter'larda `ValueNotifier` + `CallService` getter pattern |
| 2026-08-02 | D-8 UI routing state ownership | `isCallScreenVisible`, `preventCallScreenAutoOpen` CallScreenRouter'a taşınır | CallService'in bu routing flag'lerini tutması single responsibility ihlali; CallScreenRouter zaten ekran kararını veriyor — bu flag'leri de o yönetmeli |
