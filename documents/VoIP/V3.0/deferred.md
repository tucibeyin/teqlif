# VoIP V3.0 — Ertelenen Kapsam

Bu dosya V2.0 refactoring cycle'ında bilinçli olarak kapsam dışı bırakılan konuları kayıt altına alır.
Bir sonraki refactor cycle'ında başlangıç noktası olarak kullanılmalı.

---

## CallRoomAdapter Ekstraksiyonu

**V2.0 sonrası durum:** `call_service.dart` içindeki LiveKit room yönetimi hâlâ `CallService` bünyesinde.

**Neden ertelendi:**
- `_joinRoom` ve `_onRoomEvent` `_hardware.*`, `_setState()`, `endCall()`, timer'lar ile derin coupling içeriyor.
- Ekstraksiyonun kod maliyeti ORTA (2-3 saat), ancak test maliyeti YÜKSEK (2-4 saat, 2 gerçek cihaz).
- iOS `AVAudioSession` sıralaması (`waitForCallkitAudio`, `resumeAfterRoomConnect`, mic açılması) tüm servisin en kırılgan noktası; çalışan kodu kırmak riski maliyetle orantılı değil.
- Pratik kazanım (bug azalma, bakım kolaylığı) ancak LiveKit'i unit test'te mock'lamak gerektiğinde anlam kazanır — şu an böyle bir ihtiyaç yok.

**Önerilen V3.0 yaklaşımı:**

```dart
// call/room/call_room_adapter.dart
class CallRoomAdapter {
  CallRoomAdapter({
    required CallHardwareAdapter hardware,
    required ValueNotifier<bool> preventCallScreenAutoOpen,
    required void Function(String context) onConnected,
    required void Function() onDisconnected,
    required void Function() onReconnecting,
    required void Function() onReconnected,
    required void Function() onPeerJoined,
    required void Function(bool isPoor) onConnectionQuality,
  });

  Future<void> joinRoom({required String livekitUrl, required String token, required CallRole role, required int? callId});
  Future<void> disconnect();
  Future<void> setMicEnabled(bool enabled);
  Future<void> setSpeakerEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();
  Room? get room;
}
```

**Ekstraksiyona dahil edilmesi gereken metodlar (`call_service.dart`'tan taşınacak):**
- `_joinRoom()` (~190 satır) — iOS/Android branching, pre-connect vs post-accept audio sıralaması
- `_onRoomEvent()` (~100 satır) — RoomDisconnected, RoomReconnecting, RoomReconnected, ParticipantConnected, TrackSubscribed, TrackUnmuted
- `_disconnectRoom()` (~30 satır)
- `_transitionToConnected()` (~20 satır)
- `_setupAudioInterruptionListener()` (~25 satır)
- `_startStatsMonitor()` / `_stopStatsMonitor()` (~20 satır)
- `_startNetworkMonitor()` / `_stopNetworkMonitor()` (~15 satır)
- `_startProximitySensor()` / `_stopProximitySensor()` (~20 satır)
- `_ensureMicEnabled()` (~25 satır)
- `toggleMute()`, `setSpeaker()`, `toggleCamera()`, `switchCamera()` (~50 satır)

**Taşındıktan sonra `CallService`'te kalacak:**
- State yönetimi (`_setState`, `state`, `elapsed`)
- Çağrı akışları: `startCall`, `acceptCall`, `rejectCall`, `endCall`
- WS event routing: `processEvent`, `onCallAccepted`, `onCallRejected`, `onCallEnded`, `onCallMissed`, `onIncomingCall`
- Timer orchestration: `_startRingTimer`, `_startCallerStatusPoll`, `_scheduleReset`
- Crash recovery: `checkActiveCall`
- Grup çağrısı: `inviteToCall`, `acceptGroupInvite`, `rejectGroupInvite`, `leaveGroupCall`, `removeParticipant`, grup WS handler'ları

**Kritik test senaryoları (ekstraksiyondan önce ve sonra doğrulanmalı):**
- iOS caller: ringback → pre-connect (`room.connect()`) → `resumeAfterRoomConnect()` → kabul → mic açılması
- iOS callee: `waitForCallkitAudio()` sıralaması → mic → speaker
- Android callee: `onCallConnected()` zamanlaması (CallKit UI güncelleme)
- Pre-connect sırasında `room.connect()` hatası → çağrı korunuyor mu? (ringing/waiting state)
- Reconnecting → active geçişinde ses kesiliyor mu?
- Group invite (iOS): `onAudioSessionActivated()` simülasyonu çalışıyor mu?

---

## Grup Çağrısı HTTP → CallRepository

**V2.0 sonrası durum:** Grup çağrısı endpoint'leri `CallService._post()` ile doğrudan çağrılıyor.

**Neden ertelendi:** Step 4 (CallRepository) kapsamında sadece 1:1 çağrı endpoint'leri taşındı; grup endpoint'leri ayrı bir "follow-up" olarak bırakıldı.

**V3.0'da yapılacak:** `CallRepository`'ye şu metodlar eklenecek:

| Metot | HTTP |
|---|---|
| `inviteParticipant(callId, inviteeId)` | `POST /calls/$id/invite` |
| `acceptGroupInvite(callId, participantId)` | `POST /calls/$id/participants/$pid/accept` |
| `rejectGroupInvite(callId, participantId)` | `POST /calls/$id/participants/$pid/reject` |
| `leaveGroupCall(callId, participantId)` | `POST /calls/$id/participants/$pid/leave` |
| `removeParticipant(callId, userId)` | `POST /calls/$id/participants/$uid/remove` |

Bu taşıma tamamlanınca `CallService`'teki `_post()` ve `_authHeaders()` helper'ları kaldırılabilir. `_getList` (`fetchFollowingForInvite` için) ayrıca değerlendirilmeli — follows verisi aslında başka bir repository'nin sorumluluğu.

---

## V2.0 → V3.0 Beklenen Satır Azalması

| Modül | V2.0 sonu | V3.0 hedefi |
|---|---|---|
| `call_service.dart` | ~2200 satır | ~900 satır |
| `call/room/call_room_adapter.dart` | — | ~400 satır |
| `call/repository/call_repository.dart` | mevcut | +50 satır (grup endpoint'leri) |
