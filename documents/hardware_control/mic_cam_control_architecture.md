# Kamera & Mikrofon Kontrol Mimarisi

## 1. Genel Bakış

Teqlif uygulaması kamera ve mikrofona beş farklı bağlamda erişir. Her bağlam bugün farklı bir sorumluluk modeli kullanıyor; bu belge mevcut mimariyi, doğru mimariyi ve ikisi arasındaki farkı tanımlar.

---

## 2. İzin Katmanları

```
┌─────────────────────────────────────────┐
│              UI (Screen)                │
│  Kullanıcıya izin diyaloğu / hata göster│
└──────────────┬──────────────────────────┘
               │ permission state
┌──────────────▼──────────────────────────┐
│         Service / Manager               │
│  CallService, StreamConnectionManager  │
│  İzin kontrolü + donanım başlatma       │
└──────────────┬──────────────────────────┘
               │ hardware access
┌──────────────▼──────────────────────────┐
│    permission_handler / LiveKit SDK     │
│    ImagePicker / record (audio)         │
└─────────────────────────────────────────┘
```

**Clean Architecture kuralı:** İzin kontrolü servis katmanında yapılmalı, UI yalnızca state'e reaksiyon göstermeli. Bugün bu kural sadece `CallService`'te tutarlı biçimde uygulanıyor.

---

## 3. Bağlam Bazlı Mevcut Durum

### 3.1 Sesli Arama (`CallService`)

**Sorumluluk modeli: Servis katmanı — Doğru**

```
CallService.startCall()
  └─ Permission.microphone.request()
       ├─ granted  → CallStatus.calling (devam)
       └─ denied   → CallStatus.permissionDenied
                      + permPermanentlyDenied: bool

CallService.acceptCall()
  └─ Permission.microphone.status  (request değil, check)
       ├─ granted  → CallStatus.connecting
       └─ denied   → CallStatus.permissionDenied
                      + _hangUpLocally()
                      + showWarningNotification()
```

`CallStatus` bir state machine; `permissionDenied` ayrı bir durum. `permPermanentlyDenied` flag'i taşınıyor ancak `call_screen.dart`'ta "Ayarları Aç" UI'ına bağlantı doğrulanamadı.

---

### 3.2 Canlı Yayın — Host (`host_stream_screen.dart`)

**Sorumluluk modeli: Screen katmanı — Kısmen Doğru**

```
_connect()
  ├─ Permission.camera.request()
  ├─ Permission.microphone.request()
  │    ├─ isDenied (cam veya mic)
  │    │    └─ _error = 'livePermissionRequired'
  │    │       StreamService.cancelStream()
  │    └─ granted → LiveKit connect()
  │                  setCameraEnabled(true)     ← try/catch yok
  │                  setMicrophoneEnabled(true)  ← try/catch yok
  │
  └─ catch(e) → _error = 'Yayına bağlanılamadı'

_toggleMic()  → setMicrophoneEnabled()  ← try/catch yok
_toggleCamera() → setCameraEnabled()   ← try/catch yok
```

İzin kontrolü screen içinde. `isPermanentlyDenied` ayrımı yok. Runtime izin kaldırma senaryosu (`AppLifecycle.resumed`) işlenmiyor.

---

### 3.3 Canlı Yayın — Co-Host (`StreamConnectionManager`)

**Sorumluluk modeli: Servis katmanı — Eksik**

```
upgradeToCoHost()
  └─ setCameraEnabled(true)      ← izin kontrolü yok
     setMicrophoneEnabled(true)  ← izin kontrolü yok
     catch(e) → debugPrint()     ← kullanıcıya bildirim yok
```

Viewer'ın kamera/mikrofon iznine sahip olduğu varsayılıyor. Hata yakalanıyor ama işlenmiyor.

---

### 3.4 Mesajlaşma (`messages_screen.dart`)

**Sorumluluk modeli: Screen katmanı — Kısmen Doğru**

```
_pickAndSendImage(camera)
  └─ ImagePicker().pickImage()
       ├─ picked != null → upload
       └─ picked == null
            └─ Permission.camera.status
                 ├─ isPermanentlyDenied → openAppSettings()
                 └─ diğer → sessiz çıkış

_startRecording()
  └─ _recorder.start()
       catch(_)
         └─ Permission.microphone.status
              ├─ isPermanentlyDenied → openAppSettings()
              └─ diğer → snackbar ("Kayıt başlatılamadı")

_pickAndSendVideo()
  └─ ImagePicker().pickVideo()
       ├─ picked != null → upload
       └─ picked == null → sessiz çıkış  ← isPermanentlyDenied kontrolü eksik
```

Fotoğraf ve ses kaydı için `isPermanentlyDenied → openAppSettings()` zinciri mevcut. Video için bu zincir eksik.

---

### 3.5 İlan Oluşturma / Düzenleme

**Sorumluluk modeli: Yok**

```
_pickImages(camera)   → ImagePicker().pickImage()  ← izin kontrolü yok
_pickVideo(camera)    → ImagePicker().pickVideo()  ← izin kontrolü yok
_pickImages(gallery)  → ImagePicker().pickMultiImage() ← izin kontrolü yok
```

`permission_handler` import bile yok. `null` dönüşte sessiz çıkış.

---

### 3.6 Story Yükleme (`story_tray.dart`)

**Sorumluluk modeli: Yok**

```
_pickAndUploadPhoto(camera/gallery)
  └─ ImagePicker().pickImage()
       ├─ picked != null → upload
       └─ picked == null → sessiz çıkış  ← izin kontrolü yok

_pickAndUploadVideo(camera/gallery)
  └─ ImagePicker().pickVideo()
       ├─ picked != null → upload
       └─ picked == null → sessiz çıkış  ← izin kontrolü yok
```

---

### 3.7 Profil Fotoğrafı (`profile_screen.dart`)

**Sorumluluk modeli: Yok**

```
picker.pickImage(source)
  ├─ picked != null → upload
  └─ picked == null → sessiz çıkış  ← izin kontrolü yok
```

---

### 3.8 Uygulama Başlangıcı (`main_screen.dart`)

```
// initState sonrası, WidgetsBinding.instance.addPostFrameCallback
Permission.microphone.request();  // await yok, sonuç yok sayılıyor
```

Proaktif mikrofon isteği fire-and-forget olarak yapılıyor. Arama özelliği için önhazırlık niyetiyle konulmuş ancak sonucu hiçbir yere bağlı değil.

---

## 4. Runtime İzin Kaldırma Akışı

Kullanıcı yayındayken veya aramadayken sistem ayarlarından izni kaldırırsa:

```
iOS/Android → OS kamera/mikrofon stream'ini keser
     │
     ▼
AppLifecycleState.inactive (home'a geçiş)
     │
     ▼
StreamConnectionManager.didChangeAppLifecycleState()
  └─ _isBackground = true → _handleBackgroundTransition()
       └─ track subscription'ları yönetir, izin kontrol etmez

AppLifecycleState.resumed (geri dönüş)
  └─ _isBackground = false → _handleForegroundTransition()
       └─ track subscription'ları restore eder, izin kontrol etmez
```

**Sonuç:** UI `_cameraEnabled = true` gösterir, donanım kapalıdır. Tutarsız state.

---

## 5. Hedef Mimari

```
┌──────────────────────────────────────────────────────────┐
│  PermissionService (yeni — merkezi)                      │
│                                                          │
│  checkAndRequest(Permission) → PermissionResult          │
│    PermissionResult.granted                              │
│    PermissionResult.denied                               │
│    PermissionResult.permanentlyDenied → openAppSettings  │
│                                                          │
│  checkOnResume(List<Permission>) → PermissionCheckResult │
│    Lifecycle.resumed'da çağrılır                         │
└──────────┬───────────────────────────────────────────────┘
           │
           ├─── CallService (izin kontrolü zaten burada)
           │      → permPermanentlyDenied UI bağlantısı ekle
           │
           ├─── StreamConnectionManager
           │      → upgradeToCoHost öncesi izin kontrol
           │      → didChangeAppLifecycleState'de izin re-check
           │
           └─── ImagePicker çağrı noktaları
                  → create_listing, edit_listing, story, profile
                  → ortak _pickWithPermission() yardımcı metodu
```

---

## 6. Platform Davranış Tablosu

| Durum | iOS | Android |
|-------|-----|---------|
| İlk istek, kullanıcı "İzin Ver" | `granted` | `granted` |
| İlk istek, kullanıcı "Reddet" | `denied` | `denied` |
| İkinci kez istek, daha önce reddedildi | `denied` (dialog yok) | `denied` veya dialog (rationale) |
| "Bir daha sorma" seçildi (Android) | — | `permanentlyDenied` |
| Ayarlardan kaldırıldı | `denied` (bir sonraki request'te) | `denied` |
| Uygulama yayında, OS stream kesti | LiveKit sessizce durur | LiveKit sessizce durur |

> iOS'ta `denied` ve `permanentlyDenied` pratikte aynı davranışı gösterir: dialog çıkmaz. Her iki durumda da `openAppSettings()` zorunludur.
