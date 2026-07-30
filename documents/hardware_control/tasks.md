# Kamera & Mikrofon — Görev Listesi

Referans: [findings.md](findings.md) · [mic_cam_control_architecture.md](mic_cam_control_architecture.md)

---

## ✅ T-HC-01 · `isPermanentlyDenied` ayrımı — Host yayın başlangıcı

**Bulgu:** F-01  
**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:333–342`  
**Şiddet:** Yüksek

**Yapılacak:**
- `camStatus.isDenied || micStatus.isDenied` yerine ayrı kontrol: `isPermanentlyDenied` ise "Ayarları Aç" butonu içeren dialog/overlay göster
- `isDenied` (kalıcı değil) ise mevcut hata mesajı yeterli; `openAppSettings()` eklemeye gerek yok
- Hata overlay'ine `openAppSettings()` çağıran bir buton ekle (iOS ve Android'de `permission_handler` paketi ile)
- `StreamService.cancelStream()` her iki durumda da çağrılmalı

**Kabul kriteri:** Kamera iznini kalıcı olarak reddeden bir kullanıcı "Ayarlar'a Git" butonunu görür ve yönlendirilir.

---

## ✅ T-HC-02 · Runtime izin kaldırma — Lifecycle re-check (Host Yayın)

**Bulgu:** F-02  
**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart` + `stream_connection_manager.dart:85–90`  
**Şiddet:** Kritik

**Yapılacak:**
- `host_stream_screen.dart`'ta `WidgetsBindingObserver` mixin'i ekle
- `didChangeAppLifecycleState(AppLifecycleState.resumed)` tetiklendiğinde:
  - `Permission.camera.status` ve `Permission.microphone.status` kontrol et
  - İzin kaldırıldıysa `_cameraEnabled` / `_micEnabled` state'ini gerçek durumla senkronize et
  - Kullanıcıya toast/snackbar ile bildirim ver: "Kamera iznin kaldırılmış"
- Alternatif: `StreamConnectionManager._handleForegroundTransition()` içinde host yayın için izin kontrolü tetikle (servis katmanına taşıma)

**Kabul kriteri:** Yayın sırasında izin kaldırılıp geri dönüldüğünde UI gerçek donanım durumunu yansıtır, kamera butonu "kapalı" gösterir.

---

## ✅ T-HC-03 · `_toggleMic()` / `_toggleCamera()` hata yönetimi

**Bulgu:** F-03  
**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:453–462`  
**Şiddet:** Yüksek

**Yapılacak:**
```dart
Future<void> _toggleMic() async {
  final target = !_micEnabled;
  try {
    await _room?.localParticipant?.setMicrophoneEnabled(target);
    setState(() => _micEnabled = target);
  } catch (e) {
    // State flip etme — donanım değişmedi
    TeqToast.error(loc.t('micToggleFailed'));
  }
}
```
Aynı pattern `_toggleCamera()` için de uygulanmalı. State flip'i başarılı `await` sonrasına taşı.

**Kabul kriteri:** Mikrofon toggle'ı başarısız olduğunda kullanıcıya bildirim gelir, UI önceki durumda kalır.

---

## ✅ T-HC-04 · Co-host yükseltmesinde izin kontrolü

**Bulgu:** F-04  
**Dosya:** `mobile/lib/services/stream_connection_manager.dart:314–337`  
**Şiddet:** Yüksek

**Yapılacak:**
- `upgradeToCoHost()` başında `Permission.camera.request()` + `Permission.microphone.request()` ekle
- Reddedilirse: `throw PermissionDeniedException(permanentlyDenied: ...)` fırlat ya da `bool` döndür
- `_acceptCoHostInvite()` içinde bu sonucu yakala ve kullanıcıya göster:
  - `isDenied` → "Kamera ve mikrofon izni gerekli"
  - `isPermanentlyDenied` → "Ayarları Aç" butonu
- `catch (e)` bloğunu sadece `debugPrint` bırakma; upstream'e ilet

**Kabul kriteri:** Kamera izni olmayan viewer sahneye davet edildiğinde anlamlı hata mesajı görür, host da neden bağlanamadığını anlayabilir.

---

## ✅ T-HC-05 · Bağlantı sırasında kamera/mikrofon başlatma hatası ayrımı

**Bulgu:** F-05  
**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:375–435`  
**Şiddet:** Orta

**Yapılacak:**
- `setCameraEnabled(true)` + `setMicrophoneEnabled(true)` çağrılarını ayrı bir try/catch bloğuna al
- Hata durumunda `_error` yerine toast göster ve yayını bağlı ama karanlık modda bırak (kamera açılmadı ama yayın iptal edilmedi)
- Alternatif minimal fix: mevcut `try` bloğunda bu satırları `try-catch` ile sarmala, hata logla ve Sentry'e gönder

**Kabul kriteri:** LiveKit bağlandı ama kamera açılamadıysa kullanıcıya "kamera başlatılamadı" mesajı gelir, yayın iptal edilmez.

---

## ✅ T-HC-06 · Mesajlaşmada video seçimi izin kontrolü

**Bulgu:** F-06  
**Dosya:** `mobile/lib/screens/messages_screen.dart:1439–1474`  
**Şiddet:** Orta

**Yapılacak:**
- `_pickAndSendVideo()` içinde `picked == null` durumunda fotoğraf için olan pattern'i uygula:
```dart
if (picked == null) {
  final status = await Permission.camera.status;
  if (status.isPermanentlyDenied) await openAppSettings();
  return;
}
```

**Kabul kriteri:** Video seçimi izin yoksa fotoğraf seçimiyle aynı davranışı gösterir.

---

## ✅ T-HC-07 · İlan oluşturma/düzenleme — kamera izin yönetimi

**Bulgu:** F-07  
**Dosyalar:** `mobile/lib/screens/create_listing_screen.dart`, `mobile/lib/screens/edit_listing_screen.dart`  
**Şiddet:** Orta

**Yapılacak:**
- Her iki ekranda `import 'package:permission_handler/permission_handler.dart'` ekle
- `_pickImages(ImageSource.camera)` ve `_pickVideo(ImageSource.camera)` çağrılarından önce izin kontrolü ekle
- Galeri seçimi için `Permission.photos` (iOS) / `Permission.storage` (Android <13) kontrol et
- Ortak yardımcı bir `_requestAndPickImage(source)` metodu her iki ekrana da eklenebilir (kod tekrarını azaltır)
- Pattern:
  ```dart
  // Kamera için
  if (source == ImageSource.camera) {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) await openAppSettings();
      return;
    }
  }
  ```

**Kabul kriteri:** Kamera izninin olmadığı durumda kullanıcıya açıklayıcı mesaj/yönlendirme gelir, picker sessizce çalışmaz.

---

## ✅ T-HC-08 · Story yükleme — kamera izin yönetimi

**Bulgu:** F-08  
**Dosya:** `mobile/lib/widgets/live/story_tray.dart:81–160`  
**Şiddet:** Orta

**Yapılacak:**
- `_pickAndUploadPhoto()` ve `_pickAndUploadVideo()` içinde T-HC-07 ile aynı pattern
- Galeri seçimi ayrı, kamera seçimi ayrı kontrol
- `picked == null` durumunda `isPermanentlyDenied` kontrolü

**Kabul kriteri:** Story kamera özelliği izin yokken sessiz başarısız olmaz.

---

## ✅ T-HC-09 · Profil fotoğrafı — kamera izin yönetimi

**Bulgu:** F-09  
**Dosya:** `mobile/lib/screens/profile_screen.dart:2562`  
**Şiddet:** Düşük

**Yapılacak:**
- `picker.pickImage()` öncesi `Permission.camera.request()` ekle
- `null` dönüşünde `isPermanentlyDenied → openAppSettings()` kontrol et

**Kabul kriteri:** Profil fotoğrafı kamera ile değiştirilmek istendiğinde izin yoksa kullanıcı yönlendirilir.

---

## ✅ T-HC-10 · Proaktif mikrofon isteği — sonucu takip et

**Bulgu:** F-10  
**Dosya:** `mobile/lib/screens/main_screen.dart:122`  
**Şiddet:** Düşük

**Yapılacak:**
- `Permission.microphone.request()` sonucunu `await` ile bekle
- Sonucu bir shared preference veya provider state'e yaz (örn. `micPermissionGranted: bool`)
- `CallService.startCall()` bu state'i kullanarak önce local check yapabilir, sistem diyaloğunu gereksiz yere açmaz
- Alternatif minimal fix: sadece `await` ekle, log at — en azından crash analitiklerinde takip edilsin

**Kabul kriteri:** Uygulama açılışında alınan mikrofon izni sonucu bir yerde saklanır ve `CallService` bunu kullanır.

---

## Uygulama Sırası (Önerilen)

```
Sprint 1 — Kritik + Yüksek
  T-HC-02  Runtime izin kaldırma (Kritik)
  T-HC-03  Toggle try/catch (Yüksek)
  T-HC-04  Co-host izin kontrolü (Yüksek)
  T-HC-01  isPermanentlyDenied ayrımı (Yüksek)

Sprint 2 — Orta
  T-HC-07  İlan oluşturma/düzenleme (Orta)
  T-HC-08  Story (Orta)
  T-HC-06  Mesajlaşma video (Orta)
  T-HC-05  Bağlantı hata ayrımı (Orta)

Sprint 3 — Düşük
  T-HC-09  Profil fotoğrafı (Düşük)
  T-HC-10  Proaktif istek takibi (Düşük)
```

---

## Lokalizasyon Anahtarları (Yeni Eklenmesi Gerekenler)

| Anahtar | Türkçe öneri |
|---------|-------------|
| `permCameraRequired` | Kamera izni gerekli |
| `permMicRequired` | Mikrofon izni gerekli |
| `permPermanentlyDenied` | Bu özellik için izin gerekli. Ayarlardan etkinleştir. |
| `permOpenSettings` | Ayarları Aç |
| `micToggleFailed` | Mikrofon değiştirilemedi |
| `cameraToggleFailed` | Kamera değiştirilemedi |
| `permRevokedDuringLive` | Kamera izni kaldırıldı |
