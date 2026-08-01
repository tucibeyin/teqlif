# VoIP Arama Kararları

Bu dosya, Teqlif'teki arama akışına dair tüm ürün ve mimari kararları tutar.  
**Arama sürecini etkileyen her kod değişikliğinden önce bu dosyaya bak.**

> `VoIP_architecture.md` — altyapı ve state machine teknik detayları  
> `VoIP_decisions.md` (bu dosya) — use case'ler, donanım yönetimi ve SwipeLive kararları

**Son güncelleme:** Ağustos 2026

---

## İçindekiler

1. [Use Case Kataloğu](#1-use-case-kataloğu)
2. [Platform Audio Donanım Yönetimi](#2-platform-audio-donanım-yönetimi)
3. [Audio Routing Karar Matrisi](#3-audio-routing-karar-matrisi)
4. [SwipeLive Edge Case](#4-swipelive-edge-case)

---

## 1. Use Case Kataloğu

Endüstri standardı arama senaryoları. Her use case; beklenen state geçişini, ses davranışını ve her iki platform için özel notları içerir.

---

### UC-01 — Arama Başlatıldı (Caller Bekliyor)

**Akış:** `idle → calling`

| Taraf | Davranış |
|---|---|
| Caller | ringback.wav loop'ta çalar (earpiece) |
| Callee | Sistem zil sesi çalar (speaker — platform default) |

**Timeout:** 30 saniye. Callee cevap vermezse → UC-04.  
**iOS:** CallKit arama ekranı gösterilir. Pre-connect: room.connect() network-only (mic YOK, ringback korunur).  
**Android:** flutter_callkit_incoming bildirimi gösterilir. Pre-connect: room.connect() + muted audio track pre-publish.

---

### UC-02 — Arama Kabul Edildi (Bağlantı Kuruldu)

**Akış:** `calling → connecting → connected`

| Taraf | Ses Çıkışı | Notlar |
|---|---|---|
| Caller | Earpiece (her koşulda) | Ringback durur, karşı taraf sesi gelir |
| Callee (normal) | Earpiece | Zil durur, caller sesi gelir |
| Callee (SwipeLive'da) | Speaker | Bkz. [Bölüm 4](#4-swipelive-edge-case) |

**`connected` tetikleyicileri** (kaynak `VoIP_architecture.md §6`):
- `TrackSubscribedEvent` (audio, status ≠ calling/ringing)
- `TrackUnmutedEvent` (remote audio, status == connecting)
- `peerAlreadyJoined + anyAudioSubscribed` (status ≠ ringing)

---

### UC-03 — Callee Reddetti

**Akış:** `calling → rejected → idle`

| Taraf | Davranış |
|---|---|
| Caller | busy.wav earpiece'te çalar, biter → idle |
| Callee | Arama ekranı kapanır |

busy.wav bittikten sonra SwipeLive içerik sesi açılır (varsa). Bkz. [Bölüm 4](#4-swipelive-edge-case).

---

### UC-04 — Cevap Yok (Timeout)

**Akış:** `calling → noAnswer → idle`

30 saniye içinde callee cevap vermezse ARQ worker `call_missed` WS eventi gönderir.

| Taraf | Davranış |
|---|---|
| Caller | Ringback durur, `noAnswer` ekranı 2s → idle |
| Callee | Cevapsız arama bildirimi |

Ses yoktur (busy.wav çalmaz). SwipeLive içerik sesi otomatik açılır.

---

### UC-05 — Callee Meşgul (Başka Aramadayken)

**Akış:** `calling → busy → idle`

Callee'nin aktif bir araması varken yeni arama gelir; backend otomatik reject eder.

| Taraf | Davranış |
|---|---|
| Caller | busy.wav earpiece'te çalar → idle |
| Callee | İkinci arama sessizce reddedilir, mevcut arama devam eder |

---

### UC-06 — Caller Aktif Aramayı Sonlandırdı

**Akış:** `connected → ended → idle`

| Taraf | Davranış |
|---|---|
| Caller | ended.wav earpiece'te çalar → idle |
| Callee | `call_ended` WS eventi → ended.wav earpiece → idle |

ended.wav bittikten sonra SwipeLive içerik sesi açılır (varsa).

---

### UC-07 — Callee Aktif Aramayı Sonlandırdı

**Akış:** `connected → ended → idle`

UC-06 ile aynı son durum; tetikleyen taraf farklı.

| Taraf | Davranış |
|---|---|
| Callee | ended.wav earpiece'te çalar → idle |
| Caller | `call_ended` WS eventi → ended.wav earpiece → idle |

---

### UC-08 — Aramadayken Yeni Arama Geldi

İki senaryo:

**a) Caller aktif bir aramadayken yeni callee olarak arama aldı:**  
Backend `hasActiveCall` guard'ı → gelen arama otomatik reject edilir. Mevcut arama kesintisiz devam eder. Caller'a bildirim gitmez.

**b) Callee aktif bir aramadayken yeni caller'dan arama aldı:**  
Aynı guard → UC-05 (meşgul) akışı tetiklenir. Yeni caller busy.wav duyar.

> Her iki senaryoda da mevcut aramanın ses yönlendirmesi değişmez.

---

### UC-09 — Ağ Kesintisi / Yeniden Bağlanma

**Akış:** `connected → reconnecting → connected` veya `reconnecting → ended`

| Durum | Davranış |
|---|---|
| Kısa kesinti (LiveKit otomatik reconnect) | weak.wav earpiece → bağlandığında devam |
| Uzun kesinti (LiveKit timeout) | `RoomDisconnectedEvent` → ended akışı |

Ses yönlendirmesi (earpiece/speaker) reconnecting boyunca korunur. Audio session sıfırlanmaz.

---

### UC-10 — Mikrofon İzni Reddedildi

**Akış:** `idle → permissionDenied → idle`

| Durum | Davranış |
|---|---|
| Caller mic izni yok | `startCall()` çağrılır → izin iste → reddedilirse `permissionDenied` |
| Callee mic izni yok | `acceptCall()` → izin kontrol → reddedilirse uyarı bildirimi + `endCall` |

Ses yönlendirmesi gerekmez; arama hiç başlamaz.  
**iOS:** Ayarlar'a yönlendir (`openAppSettings`).  
**Android:** İzin kalıcı reddedildiyse `isPermanentlyDenied: true` ile ayarlar açılır.

---

## 2. Platform Audio Donanım Yönetimi

iOS ve Android'de ses yönlendirme altyapısı köklü biçimde farklıdır. Bu farkları bilmeden yapılan implementasyonlar platforma özgü bug üretir.

---

### 2.1 iOS — AVAudioSession + CallKit

**Merkezi otorite: AVAudioSession**

iOS'ta tüm ses yönlendirmesi `AVAudioSession` üzerinden yönetilir. Hangi uygulamanın sesi kontrol ettiği, hangi ses akışının (earpiece/speaker/bluetooth) kullanıldığı buradan belirlenir.

```
AVAudioSession kategorileri (kullanılanlar):
  .soloAmbient     → ön ısıtma (app başlangıcı)
  .playAndRecord   → arama süresi boyunca (mic + ses aynı anda)
  .voiceChat       → mode (earpiece default, echo cancellation aktif)
```

**CallKit audio session yaşam döngüsü:**

```
Callee aramayı kabul eder
  │
  ▼
action.fulfill() — AppDelegate.swift
  │
  ▼
provider(_:didActivate:audioSession:) — CallKit
  │
  ▼
Flutter: 'audioSessionActivated' method channel sinyali
  │
  ▼
_joinRoom() / _activateCalleeAudio() Completer tamamlanır
  │
  ▼
AudioSession.configure(playAndRecord/voiceChat) + setMicrophoneEnabled(true)
```

> ⚠️ `didActivateAudioSession` Completer (`_callkitAudioReady`), sinyal erken gelse dahi flag (`_audioSessionActivated`) sayesinde kaybolmaz.

**Kritik davranış — room.connect() AVAudioSession override:**  
LiveKit'in `room.connect()` çağrısı içeride AVAudioSession'ı `soloAmbient`'e çeker. Bu, `audioplayers` ile çalan ringback'i keser.  
**Çözüm:** `room.connect()` tamamlandıktan sonra `playAndRecord/voiceChat` olarak yeniden configure et ve ringback'i resume et.

**Speakerphone yönetimi (iOS):**
```dart
Hardware.instance.setSpeakerphoneOn(true/false)
// AVAudioSession override ettikten SONRA çağrılmalı;
// önce çağrılırsa AVAudioSession sıfırlar.
```

---

### 2.2 Android — AudioFocus + AudioManager

**Merkezi otorite: AudioFocus sistemi**

Android'de ses yönlendirmesi `AudioFocus` request/abandon mekanizması üzerinden yönetilir. Her uygulamanın hangi focus seviyesini istediğini beyan etmesi gerekir; daha yüksek öncelikli focus'lar diğerlerini ducklar veya durdurur.

```
AudioFocus seviyeleri:
  AUDIOFOCUS_GAIN                → kalıcı, tam kontrol (WebRTC araması)
  AUDIOFOCUS_GAIN_TRANSIENT      → kısa süreli (geçici ses)
  AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK → düşük öncelik, duck edilebilir

AudioFocus kayıp tepkileri (uygulama aldığında):
  AUDIOFOCUS_LOSS                → durdur
  AUDIOFOCUS_LOSS_TRANSIENT      → duraklat
  AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK → ses kıs
```

**WebRTC + audioplayers etkileşimi:**

```
setMicrophoneEnabled(true) çağrılır
  │
  ▼
WebRTC: AUDIOFOCUS_GAIN talep eder (STREAM_VOICE_CALL)
  │
  ▼
audioplayers MediaPlayer: AUDIOFOCUS_LOSS_TRANSIENT alır
  │
  ▼
MediaPlayer duraklayabilir → onPlayerComplete ASLA tetiklenmez
  │
  ▼
Ringback tek kez çalar, durur, bir daha başlamaz ← BUG
```

**Çözüm — ReleaseMode.loop:**  
`ReleaseMode.stop` + `onPlayerComplete` callback güvenilir değil çünkü `onPlayerComplete` yalnızca doğal bitişte tetiklenir; focus kaybı nedeniyle duran player tetiklemez.  
`ReleaseMode.loop` native MediaPlayer loop mekanizmasını kullanır; focus kaybından sonra resume edildiğinde looplamaya devam eder.

```dart
// YANLIŞ — Android'de focus kaybında loop durar
await _ringbackPlayer.setReleaseMode(ReleaseMode.stop);

// DOĞRU — focus kaybından sonra resume → loop devam eder
await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
```

**_audioPlayer context — earpiece kalıcılığı:**  
WebRTC, bağlantı sonunda audio focus'u bırakır. Bu noktada Android ses çıkışını varsayılan (speaker) routinge döndürür. `_audioPlayer` (busy.wav, ended.wav, weak.wav) için `voiceCommunication` usage context tanımlanmazsa bu sesler speaker'a yönlenir.

```dart
// _preloadRingback() içinde bir kez set edilir
await _audioPlayer.setAudioContext(ap.AudioContext(
  android: const ap.AudioContextAndroid(
    usageType: ap.AndroidUsageType.voiceCommunication,
    contentType: ap.AndroidContentType.sonification,
    audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
  ),
));
```

**CallKit yoktur (Android):**  
Android'de `flutter_callkit_incoming` bildirim UI'ı sağlar; ancak iOS CallKit'in sunduğu `didActivateAudioSession`, `setCallConnected` gibi audio session yaşam döngüsü sinyalleri yoktur. Bu nedenle:
- Callee kabul akışı: `_activateCalleeAudio()` doğrudan AudioSession configure + mic enable çağırır.
- `setCallConnected(uuid)` görsel sinyal içindir; audio session üzerinde iOS eşdeğeri etkisi yoktur.

**Speakerphone yönetimi (Android):**
```dart
Hardware.instance.setSpeakerphoneOn(true/false)
// AudioSession configure SONRASI çağrılmalı;
// AudioManager'ın STREAM_VOICE_CALL üzerinde doğrudan etkisi var.
```

---

### 2.3 Platform Fark Özeti

| Konu | iOS | Android |
|---|---|---|
| Ses otoritesi | AVAudioSession | AudioFocus + AudioManager |
| Arama UI | CallKit (native) | flutter_callkit_incoming (bildirim) |
| Audio session aktivasyon sinyali | `didActivateAudioSession` (CallKit) | Yok — doğrudan configure |
| Ringback loop yöntemi | ReleaseMode.loop | ReleaseMode.loop |
| room.connect() yan etkisi | AVAudioSession → soloAmbient | Audio focus talep eder |
| room.connect() sonrası | playAndRecord yeniden configure | 200ms bekleme + ringback kontrol |
| Speakerphone | `setSpeakerphoneOn` (AVAudioSession sonrası) | `setSpeakerphoneOn` (AudioSession sonrası) |
| Pre-connect mic | YOK (ringback korunur) | Muted pre-publish (fast unmute) |

---

## 3. Audio Routing Karar Matrisi

### 3.1 Ses Çıkışı Kararı

**Kural:** Aramayı yapan her zaman earpiece; aranan ise SwipeLive'daysa speaker, değilse earpiece.

| Taraf | SwipeLive | iOS Çıkış | Android Çıkış |
|---|---|---|---|
| Caller | Hayır | Earpiece | Earpiece |
| Caller | Evet (PiP'te) | Earpiece | Earpiece |
| Callee | Hayır | Earpiece | Earpiece |
| Callee | Evet | Speaker | Speaker |

> ⚠️ "SwipeLive'dayken arama başlatmak" = kullanıcı yayını PiP'e alıp arama yaptı. Caller her zaman earpiece.

---

### 3.2 State × Ses Kanalı

| State | Ses | iOS Çıkış | Android Çıkış |
|---|---|---|---|
| `calling` | ringback.wav (loop) | Earpiece | Earpiece (voiceCommunication) |
| `ringing` | Sistem zili | Speaker (platform default) | Speaker (platform default) |
| `connecting` | — (geçiş anı) | Earpiece | Earpiece |
| `connected` | Gerçek ses | Caller=Earpiece / Callee=bkz.§3.1 | Caller=Earpiece / Callee=bkz.§3.1 |
| `rejected` / `busy` | busy.wav | Earpiece | Earpiece (voiceCommunication context) |
| `ended` (bağlıyken) | ended.wav | Earpiece | Earpiece (voiceCommunication context) |
| `ended` (bağlanmadan) | — | — | — |
| `noAnswer` | — | — | — |
| `reconnecting` | weak.wav | Earpiece | Earpiece |
| `idle` | Ses yok | — | — |

---

### 3.3 iOS AVAudioSession Configure Sırası

**Kural:** `setSpeakerphoneOn` her zaman `session.configure()` çağrısından SONRA yapılır.

```
session.configure(playAndRecord / voiceChat)
  └── Hardware.instance.setSpeakerphoneOn(swipeLiveActive)
```

---

### 3.4 Android AudioSession Sırası

**Kural:** `setSpeakerphoneOn` AudioSession configure SONRASI; bitiş seslerinde voiceCommunication context sayesinde WebRTC focus bırakıldığında routing değişmez.

```
AudioSession.configure(voiceChat / androidAudioAttributes: voiceCommunication)
  └── Hardware.instance.setSpeakerphoneOn(swipeLiveActive)
```

---

## 4. SwipeLive Edge Case

SwipeLive = feed ekranı. İçerik türü fark etmez:
- Canlı yayın (live stream)
- Videolu ilan (video listing)
- Statik ilan (ses yoktur, bu kural geçersizdir)

**Genel kural:** Arama süresince içerik videosu/yayını devam eder, yalnızca sesi kesilir. Arama sonlandığında ses otomatik açılır.

---

### 4.1 Caller SwipeLive'dayken (PiP'te Arama Başlattı)

| Olay | İçerik Video | İçerik Ses | Arama Sesi |
|---|---|---|---|
| Arama başladı | Devam eder | **Kesilir** | Earpiece (ringback) |
| Callee kabul etti | Devam eder | Kesilir | Earpiece (ses) |
| Arama bitti (her sonuç) | Devam eder | **Açılır** | — |
| busy.wav / ended.wav çalıyor | Devam eder | Kesilir | Earpiece |
| busy.wav / ended.wav bitti | Devam eder | **Açılır** | — |

---

### 4.2 Callee SwipeLive'dayken (Yayın İzlerken Arama Aldı)

| Olay | İçerik Video | İçerik Ses | Arama Sesi |
|---|---|---|---|
| Arama geldi (ringing) | Devam eder | **Kesilir** | — (sistem zili speaker'da) |
| Callee kabul etti | Devam eder | Kesilir | **Speaker** |
| Callee reddetti | Devam eder | **Açılır** | — |
| Arama bitti (kabul sonrası) | Devam eder | **Açılır** | — |
| Cevap vermedi (timeout) | Devam eder | **Açılır** | — |

---

### 4.3 Her İki Taraf da SwipeLive'dayken

Her taraf kendi kuralını bağımsız uygular:
- Caller → Earpiece, içerik sesi kesilir
- Callee → Speaker, içerik sesi kesilir
- Arama bitince her iki tarafın içerik sesi açılır

---

### 4.4 Implementasyon Notu — `preventCallScreenAutoOpen`

`CallService.preventCallScreenAutoOpen` SwipeLive'da aktiftir. Bu flag şu kararı sürüyor:

```dart
final speakerTarget = preventCallScreenAutoOpen.value;
// true  → SwipeLive'da, speaker kullan
// false → normal, earpiece kullan
Hardware.instance.setSpeakerphoneOn(speakerTarget);
```

Bu flag tüm audio session configure çağrılarından sonra tutarlı biçimde uygulanmalıdır. Eksik uygulandığı nokta → routing bug.

---

### 4.5 SwipeLive İçerik Ses Kontrolü

İçerik sesini açıp kapatmak `CallService` sorumluluğunda değildir. `CallService` state değişikliklerini yayar; SwipeLive ekranı bu state'i dinleyerek kendi ses kontrolünü yapar.

```
CallState.status değişti
  → SwipeLive listener
      ├── calling/ringing/connecting/connected → içerik ses = 0
      └── idle/ended/rejected/missed/noAnswer → içerik ses = 1
```

> ⚠️ busy.wav / ended.wav çalarken içerik sesi kapalı kalır. Ses, `idle` state'ine geçişte açılır — bu seslerin bitmesini beklemek gerekmez çünkü `idle` geçişi zaten bu seslerin ardından gelir.
