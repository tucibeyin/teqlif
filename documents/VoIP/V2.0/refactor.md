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
| **Step 2** | State isim uyumu (rename) | State machine temiz olduktan sonra güvenli | ✅ `f47c2460` |
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

**Durum:** ✅ Tamamlandı  
**Başlangıç:** 2026-08-01  
**Tamamlanma:** 2026-08-01  
**Commit:** `f47c2460`

**Oluşturulan dosyalar:** —

**Değiştirilen dosyalar:**
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

AVAudioSession, AudioFocus, ringback, speakerphone ve **hardware izin yönetimi** — platform'a göre ayrı impl.

```
mobile/lib/call/
  hardware/
    call_hardware_adapter.dart      ← abstract interface
    ios_call_hardware_adapter.dart  ← iOS impl
    android_call_hardware_adapter.dart ← Android impl
```

### 5.1 İzin Kontrol Interface'i

```dart
abstract class CallHardwareAdapter {
  // Mic izni iste. granted | denied | permanentlyDenied döner.
  Future<PermissionStatus> requestMicPermission();

  // Kamera izni iste. granted | denied | permanentlyDenied döner.
  Future<PermissionStatus> requestCameraPermission();

  // AVAudioSession / AudioFocus kurulumu
  Future<void> setupAudioSession();
  Future<void> teardownAudioSession();

  // Speakerphone, ringback, vibration...
  void setSpeaker(bool enabled);
  void startRingback();
  void stopRingback();
}
```

### 5.2 Caller Mic Akışı (startCall içinde)

```
Permission.microphone.request()
  → granted           → dialing state'e geç
  → denied            → idle → permissionDenied (OS dialog'da kullanıcı reddetmiş)
  → permanentlyDenied → idle → permissionDenied, permPermanentlyDenied=true
                        UI: in-app modal + [Ayarlar'a Git]
```

### 5.3 Callee Mic Akışı (acceptCall içinde, ringing state'de)

```
Permission.microphone.request()
  → granted           → ringing → connecting (normal devam)
  → denied            → ringing → ended (OS dialog'da reddetmiş)
  → permanentlyDenied → state ringing KALIR
                        UI: in-app modal + [Ayarlar'a Git] [İptal]
                        Kullanıcı Settings'den döndüğünde → app_foreground → /calls/active check
                        → hâlâ calling: ringing devam, tekrar Accept edilebilir
                        → bitmişse: ringing → ended
```

**State machine değişikliği (Step 5'te):**  
`connecting → permissionDenied` callee transition'ı kaldırılır — mic check artık `connecting`'e girmeden olacak.

### 5.4 Kamera İzin Akışı (toggleCamera sırasında)

```
Permission.camera.request()
  → granted           → setCameraEnabled(true)
  → denied            → toast: "Kamera erişimi reddedildi"
  → permanentlyDenied → toast + [Ayarlar'a Git]
```

CallStatus değişmez. Arama sesli devam eder.

### 5.5 Bluetooth Android 31+

`BLUETOOTH_CONNECT` app startup'ta istenir (arama akışı dışında). Bu adımda audit edilir; call_service.dart'taki mevcut initialization kodu `CallHardwareAdapter.init()`'e taşınır.

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
