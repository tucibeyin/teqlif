# Kamera & Mikrofon — Bulgular

## F-01 · `isPermanentlyDenied` ayrımı yok (Host Yayın)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:333`

**Durum:** `isDenied || isPermanentlyDenied` eşit muamele görüyor. İkisi için de aynı hata metni gösteriliyor, "Ayarları Aç" butonu yok.

**Etki:** iOS'ta bir kez reddedilen izin bir daha sorulamaz. Kullanıcı hata mesajı görür ama nereye gideceğini bilemez; yayın açamaz.

**Senaryo:** Kullanıcı kamerayı ilk açışta "İzin Verme" der → host yayın ekranına tekrar gider → hata mesajı görür → butona tekrar basınca aynı hata (dialog çıkmaz) → uygulamayı siler.

---

## F-02 · Runtime izin kaldırma — UI tutarsızlığı (Host Yayın)

**Dosya:** `mobile/lib/services/stream_connection_manager.dart:79` + `host_stream_screen.dart:459–462`

**Durum:** Kullanıcı yayındayken Ayarlar'dan kamera veya mikrofon iznini kaldırıp geri döndüğünde `didChangeAppLifecycleState` izin kontrolü yapmıyor. `_cameraEnabled` ve `_micEnabled` state değişkenleri eski değerlerinde kalıyor; UI kamera/mikrofon "açık" gösteriyor ama donanım kapalı.

**Etki:** Yayıncı kamerasının açık olduğunu sanır. İzleyiciler siyah ekran görür. Kamera toggle butonuna basılırsa `setCameraEnabled()` exception fırlatabilir (try/catch yok).

**Senaryo:** Yayın açık → Home'a geç → Ayarlar → Kamera izni kaldır → Geri dön → Kamera butonu "açık" gösteriyor → İzleyici siyah ekran görüyor.

---

## F-03 · `_toggleMic()` ve `_toggleCamera()` try/catch yok (Host Yayın)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:453–462`

**Durum:**
```dart
Future<void> _toggleMic() async {
    _micEnabled = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    setState(() {});
}
```
`setMicrophoneEnabled()` exception fırlatırsa (izin kaldırıldı, donanım hatası, Bluetooth kopması) hata yutulur. `_micEnabled` flip'lendi ama donanım değişmedi — kalıcı tutarsızlık.

**Etki:** Kullanıcı "Sesi Aç" der, sistem kabul eder, ama ses açılmaz. Bir sonraki toggle ters yönde çalışır.

---

## F-04 · Co-host yükseltmesinde izin kontrolü yok

**Dosya:** `mobile/lib/services/stream_connection_manager.dart:314–337`

**Durum:** `upgradeToCoHost()` doğrudan `setCameraEnabled(true)` + `setMicrophoneEnabled(true)` çağırıyor. Viewer'ın kamera/mikrofon iznine sahip olduğu varsayılıyor.

**Etki:** İzin yoksa LiveKit exception fırlatır, `catch` bloğu sadece `debugPrint` yapıyor. Kullanıcı "sahneye çıktım" sanır ama ne kamerası açılır ne de bildirim gelir. Host viewer'ın bağlı olmadığını görür, neden olduğunu bilemez.

**Senaryo:** Viewer kamera iznini hiç vermemiş → Sahneye davet edilir → Kabul eder → Ekranda co-host olarak gösterilir → Kamera açılmaz → Sessiz hata.

---

## F-05 · `setCameraEnabled` / `setMicrophoneEnabled` bağlantı sırasında hata yönetimi yok (Host Yayın)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart:380–381`

**Durum:**
```dart
await room.connect(...);
await room.localParticipant?.setCameraEnabled(true);   // ← try/catch yok
await room.localParticipant?.setMicrophoneEnabled(true); // ← try/catch yok
```
LiveKit bağlantısı başarılı olsa bile kamera/mikrofon başlatma başarısız olabilir. Bu satırlar dış `try/catch` bloğu içinde ama `catch` sadece bağlantı hatasını yakalamak için tasarlanmış; "bağlandı ama kamera açılmadı" senaryosuna özel mesaj yok.

**Etki:** `_error = 'Yayına bağlanılamadı'` gösterilir; asıl sorun kamera/mikrofon başlatma hatasıdır, tanılama güçleşir.

---

## F-06 · Mesajlaşmada video seçiminde sessiz başarısızlık

**Dosya:** `mobile/lib/screens/messages_screen.dart:1439–1474`

**Durum:** `_pickAndSendVideo()` içinde `picked == null` ise sadece `return` yapılıyor. Fotoğraf ve ses kaydı için olan `isPermanentlyDenied → openAppSettings()` zinciri video için uygulanmamış.

**Etki:** Kullanıcı video kamerasına izin vermemişse veya izni kaldırmışsa "Video Ekle" butonu sessizce çalışmaz. Fotoğraf seçimiyle davranış tutarsız.

---

## F-07 · İlan oluşturma/düzenleme — sıfır izin yönetimi

**Dosyalar:** `mobile/lib/screens/create_listing_screen.dart`, `mobile/lib/screens/edit_listing_screen.dart`

**Durum:** `permission_handler` import'u bile yok. Kameradan fotoğraf veya video çekilmek istendiğinde:
```dart
final picked = await _picker.pickImage(source: ImageSource.camera);
if (picked == null) return; // sessiz çıkış
```

**Etki:** Kullanıcı "Fotoğraf Çek" butonuna basar → izin reddedilirse picker null döner → hiçbir şey olmaz → butonun bozuk olduğunu sanır. İlan fotoğrafsız kalabilir.

---

## F-08 · Story yükleme — sıfır izin yönetimi

**Dosya:** `mobile/lib/widgets/live/story_tray.dart:81–109`, `112–160`

**Durum:** Hem `_pickAndUploadPhoto()` hem `_pickAndUploadVideo()` kamera/galeri için izin kontrolü yapmıyor.

**Etki:** F-07 ile aynı: sessiz başarısızlık. Story özelliği kullanıcıya "çalışmıyor" gibi görünür.

---

## F-09 · Profil fotoğrafı — sıfır izin yönetimi

**Dosya:** `mobile/lib/screens/profile_screen.dart:2562`

**Durum:** `picker.pickImage(source: source)` doğrudan çağrılıyor, `null` kontrolü yok, izin kontrolü yok.

**Etki:** Kullanıcı profil fotoğrafını kamerayla değiştirmeye çalışırsa ve izin yoksa: hiçbir şey olmaz.

---

## F-10 · Proaktif mikrofon isteği sonucu yok sayılıyor

**Dosya:** `mobile/lib/screens/main_screen.dart:122`

**Durum:**
```dart
Permission.microphone.request(); // await yok
```
Sonuç hiçbir state'e bağlanmıyor. Uygulama açılışında kullanıcıdan mikrofon izni istenebilir ama "Reddet" derse bu bilgi `CallService` tarafından bilinmiyor; arama açılmaya çalışıldığında yeniden isteniyor.

**Etki:** Düşük ciddiyet. Kullanıcı deneyimini bozmaz ama gereksiz izin diyaloğu açılışta çıkabilir ve sonucu takip edilmediği için profillenemiyor.

---

## Özet Tablosu

| # | Alan | Şiddet | Tür |
|---|------|--------|-----|
| F-01 | Host yayın — `isPermanentlyDenied` yok | Yüksek | UX |
| F-02 | Host yayın — runtime izin kaldırma | Kritik | State tutarsızlığı |
| F-03 | Host yayın — toggle try/catch yok | Yüksek | Hata yönetimi |
| F-04 | Co-host — izin kontrolü yok | Yüksek | Hata yönetimi |
| F-05 | Host yayın — bağlantı sırasında hata ayrımı yok | Orta | Hata yönetimi |
| F-06 | Mesajlaşma — video sessiz başarısızlık | Orta | UX |
| F-07 | İlan oluşturma/düzenleme — sıfır izin yönetimi | Orta | UX |
| F-08 | Story — sıfır izin yönetimi | Orta | UX |
| F-09 | Profil fotoğrafı — sıfır izin yönetimi | Düşük | UX |
| F-10 | Proaktif mikrofon isteği fire-and-forget | Düşük | Tasarım |
