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
| `calling` | `dialing` + `waiting` | BÖLÜNÜYOR |
| `ringing` | `ringing` | Aynı ✓ |
| `connecting` | `connecting` | Aynı ✓ |
| `connected` | `active` | YENİDEN ADLANDIRILACAK |
| `ended` | `ended` | Aynı ✓ |
| `reconnecting` | `reconnecting` | Aynı ✓ |
| `rejected` | `ended` (reason=rejected) | ABSORBE |
| `missed` | `ended` (reason=missed) | ABSORBE |
| `noAnswer` | `ended` (reason=noAnswer) | ABSORBE |
| `busy` | `ended` (reason=busy) | ABSORBE |
| `permissionDenied` | `ended` (reason=permissionDenied) | ABSORBE |

**`connected` → `active` etkisi:** 7 dosya, 20 referans — derleyici bulur, Step 2'de yapılır.  
**Terminal state'lerin absorbe edilmesi:** `EndReason` field eklenir, enum değerleri kaldırılır — Step 3'te yapılır.

---

## 3. Migration Sırası

Her adım bir öncekine bağımlı, ama mevcut sistemi bozmadan production'a alınabilir.

**Durum ikonları:** 🔴 Başlamadı · 🟡 Devam ediyor · ✅ Tamamlandı

| Adım | Ne | Neden Önce | Durum |
|---|---|---|---|
| **Step 1** | `CallStateMachine` + `CallRole` | Saf Dart, sıfır bağımlılık, her şeyin temeli | ✅ `cc9bd511` |
| **Step 2** | State isim uyumu (rename) | State machine temiz olduktan sonra güvenli | 🔴 |
| **Step 3** | `EndReason` + terminal state'leri absorbe et | İsim uyumu sonrası | 🔴 |
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

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 1 tamamlanmış olmalı.

**Değişiklikler:**
- `CallStatus.calling` → `CallStatus.waiting` *(ve ayrı `dialing` eklenir)*
- `CallStatus.connected` → `CallStatus.active`
- Etkilenen dosyalar: 7 dosya, ~23 referans — derleyici kılavuzluk eder

**Approach:** Tek commit, hepsi birden. Rename sırasında `calling` kaldırılmadan önce `dialing` eklenir (HTTP request uçuşta aşaması).

**Production'a alma:** Compile + test = ship.

---

## Step 3: `EndReason` + Terminal State Absorbe

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 2 tamamlanmış olmalı.

`rejected`, `missed`, `noAnswer`, `busy`, `permissionDenied` → `ended` + `EndReason` field.

```dart
enum EndReason { normal, rejected, missed, noAnswer, busy, permissionDenied, error }

// CallState'e eklenir:
final EndReason? endReason;
```

UI'da `cs.status == CallStatus.rejected` → `cs.status == CallStatus.ended && cs.endReason == EndReason.rejected`

**Production'a alma:** UI dosyaları teker teker güncellenir, her biri bağımsız commit.

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

AVAudioSession, AudioFocus, ringback, speakerphone — platform'a göre ayrı impl:

```
mobile/lib/call/
  hardware/
    call_hardware_adapter.dart      ← abstract interface
    ios_call_hardware_adapter.dart  ← iOS impl
    android_call_hardware_adapter.dart ← Android impl
```

**Production'a alma:** `CallService` `_hardware.*` çağırır. Platform kodu service'den tamamen ayrılır.

---

## Step 6: `CallScreenRouter`

**Durum:** 🔴 Başlamadı  
**Başlangıç:** —  
**Tamamlanma:** —  
**Commit:** —

**Bağımlılık:** Step 2 tamamlanmış olmalı (state names stabil).

Ekran kararlarını merkeze al — mevcut dağınık `isCallScreenVisible`, `preventCallScreenAutoOpen` mantığı:

```
mobile/lib/call/
  routing/
    call_screen_router.dart
```

```dart
class CallScreenRouter {
  static CallScreen resolveScreen({
    required CallStatus status,
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
  final CallStateMachine _machine;
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
| — | Step 1 hard block | `assert` + log, return değil | Production güvenliliği — test sonrası Step 2'de hard block açılır |
| — | Terminal state absorbe zamanı | Step 3 (Step 2 sonrası) | İsimler stabil olmadan absorbe riski yüksek |
