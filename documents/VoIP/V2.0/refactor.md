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
| **Step 4** | `CallRepository` | API katmanı izole — state machine bağımsız | 🔴 |
| **Step 5** | `CallHardwareAdapter` | iOS/Android impl ayrılır | 🔴 |
| **Step 6** | `CallScreenRouter` | Routing merkezlenir | 🔴 |
| **Step 7** | `CallNotifAdapter` | Push layer izole | 🔴 |
| **Step 8** | `CallService` ince orchestrator | Diğerleri hazır olunca | 🔴 |

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

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 3 tamamlanmış olmalı (state naming stabil).

`call_service.dart` içindeki HTTP metotlarını izole et:

```
mobile/lib/call/
  repository/
    call_repository.dart    ← typed API methods
```

```dart
class CallRepository {
  Future<CallStartResult> startCall(int calleeId);
  Future<CallAcceptResult> acceptCall(int callId);
  Future<void> rejectCall(int callId);
  Future<void> endCall(int callId);
  Future<void> reportMissed(int callId);
  Future<ActiveCallResult?> getActiveCall();
  Future<CallStatus> getCallStatus(int callId);
  Future<CalleeTokenResult> getCalleeToken(int callId);
}
```

**Production'a alma:** `CallService` sadece `_repository.*` çağırır, HTTP kodu tamamen dışarı taşındı.

---

## Step 5: `CallHardwareAdapter`

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

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

> **Step 3'te yapıldı:** `idle → ended` caller geçişi state machine'e eklendi; `endReason=permissionDenied` set ediliyor. Step 5'te bu akış `CallHardwareAdapter.requestMicPermission()` üzerinden çalışacak.

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

**Mevcut durum (Step 5 öncesi):** Mic kontrolü `connecting`'e girdikten SONRA yapılıyor (`Permission.microphone.status` — `.request()` değil). `_hangUpLocally(ended, endReason: permissionDenied)` ile cleanup yapılıyor. Step 5'te:
1. `.status` → `.request()` geçişi (OS dialog gösterilsin)
2. Kontrol `connecting`'e girmeden önce yapılsın (`ringing` state'inde)
3. `denied` → `ringing → ended` (connecting hiç girilmez)
4. `permanentlyDenied` → `ringing` kalır (modal)

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

- [ ] `call_hardware_adapter.dart` abstract interface oluşturuldu
- [ ] `ios_call_hardware_adapter.dart` impl yazıldı
- [ ] `android_call_hardware_adapter.dart` impl yazıldı
- [ ] Callee mic check `ringing` state'ine taşındı (`.request()` ile)
- [ ] `room.connect()` sonrası `resumeAudioAfterRoomConnect()` çağrılıyor
- [ ] `CallService` `_hardware.*` çağırıyor; platform kodu service'den tamamen ayrıldı
- [ ] iOS + Android'de ses routing, izin senaryoları manuel test edildi

---

## Step 6: `CallScreenRouter`

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

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

---

## Step 7: `CallNotifAdapter`

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 5 tamamlanmış olmalı.

VoIP token kayıt, FCM token kayıt, CallKit raporlama:

```
mobile/lib/call/
  notif/
    call_notif_adapter.dart
    ios_call_notif_adapter.dart
    android_call_notif_adapter.dart
```

**Token yönetimi — implementasyon notları (VoIP.md §12.2–12.4'ten):**

| Konu | Kural |
|---|---|
| iOS push kanalı | VoIP push her zaman FCM'e tercih edilir — FCM CallKit'i tetikleyemez |
| iOS `var|var` durumu | `voip_token` varsa FCM'e bakma — VoIP push gönder |
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

---

## Step 8: `CallService` İnce Orchestrator

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 1–7 tamamlanmış olmalı.

Bu adımda `call_service.dart` ~2645 satırdan ~300 satıra iner. Tek işi: event gelince doğru modüle iletmek.

```dart
class CallService {
  // Not: CallStateMachine pure static — instance field değil, CallStateMachine.transition() direkt çağrılır.
  final CallRepository _repository;
  final CallHardwareAdapter _hardware;
  final CallNotifAdapter _notif;
  final CallScreenRouter _router;

  // Dışarıya: tek API noktası
  Future<void> startCall(...);
  Future<void> acceptCall();
  Future<void> rejectCall();
  Future<void> endCall();
  void onWsEvent(Map<String, dynamic> data);
  void onPushReceived(Map<String, dynamic> data);
  void onCallkitEvent(CallKitEvent event);
}
```

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
