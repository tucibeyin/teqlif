# Teqlif VoIP Architecture V2.0

> Bu doküman V1.0 (VoIP_decisions.md) üzerine inşa edilmiştir.  
> V1.0 use case kararlarını içerir; V2.0 mimari modeli tanımlar.  
> Her bölüm kararlaştırıldıkça eklenir — yarım bırakılmış bölüm yoktur.

---

## 1. Tasarım Kararları (Axioms)

Bu kararlar tüm mimariyi şekillendirir. Değiştirilmesi büyük etki yaratır.

### 1.1 State machine role-aware, platform-agnostic'tir

State'ler ve transition'lar ne iOS ne Android bilir. "Ringing'den active'e geçmek" her platformda aynı anlam taşır. Platform farkı state'te değil, o transition'ın **side effect implementasyonunda** yaşar.

```
YANLIŞ: iOS_ringing, Android_ringing  (ayrı state'ler)
DOGRU:  ringing → (iOS adapter: AVAudioSession + CallKit)
                → (Android adapter: AudioFocus + Notification)
```

### 1.2 Role, erişilebilir state'leri belirler

Caller ve callee aynı anda farklı state'lerdedir. Bazı state'ler sadece bir role'e aittir.

```
Caller-only:  dialing, waiting
Callee-only:  ringing
Shared:       idle, connecting, active, ended, reconnecting
```

### 1.3 Network kaybı ve crash first-class event'lerdir

"Edge case" değil, her state'te olabilecek tanımlı event'lerdir. State machine her state için bu event'lerin davranışını açıkça tanımlar. Tanımlanmamış kombinasyon yoktur.

### 1.4 Platform farkı adapter katmanında yaşar

```
CallStateMachine      →  ne olur         (Dart, saf logic, platform yok)
CallHardwareAdapter   →  ses nasıl yönetilir  (iOS impl / Android impl ayrı)
CallNotifAdapter      →  bildirim nasıl gider (iOS/VoIP impl / Android/FCM impl ayrı)
CallScreenRouter      →  hangi ekran açılır   (platform-agnostic, role-aware)
```

---

## 2. Üç Boyutlu Model

Her davranış bu üç soruyla tam olarak tanımlanır:

| Boyut    | Soru                          | Değerler                        |
|----------|-------------------------------|---------------------------------|
| State    | Şu an ne durumundayız?        | idle, dialing, waiting, ...     |
| Role     | Bu cihaz kim?                 | caller / callee                 |
| Platform | Bu cihaz ne?                  | iOS / Android                   |

Örnek:  
> **State=ringing, Role=callee, Platform=iOS** →  
> AVAudioSession ringtone kategorisi + CallKit native screen + VoIP push zaten teslim edildi

---

## 3. State Listesi

### 3.1 Normal Flow

| State        | Sahip         | Anlam                                                    |
|--------------|---------------|----------------------------------------------------------|
| `idle`       | caller+callee | Aktif arama yok, sistem dinlemede                        |
| `dialing`    | caller only   | /calls/start isteği gönderildi, sunucu yanıtı bekleniyor |
| `waiting`    | caller only   | Sunucu onayladı, callee'nin yanıtı bekleniyor            |
| `ringing`    | callee only   | Gelen arama bildirimi alındı, kullanıcı kararı bekleniyor|
| `connecting` | caller+callee | Callee kabul etti, LiveKit room bağlantısı kuruluyor     |
| `active`     | caller+callee | Ses bağlantısı kuruldu, arama sürüyor                    |
| `ended`      | caller+callee | Arama sonlandı, cleanup sürüyor (2s reset window)        |

### 3.2 Recovery State

| State          | Sahip         | Anlam                                                         |
|----------------|---------------|---------------------------------------------------------------|
| `reconnecting` | caller+callee | `active` iken network koptu, LiveKit yeniden bağlanmayı deniyor |

`reconnecting` maksimum süre aşılırsa → `ended` geçişi yapılır.

### 3.3 Normal Flow Geçişleri (Özet)

```
CALLER:
  idle → dialing → waiting → connecting → active → ended → idle

CALLEE:
  idle → ringing → connecting → active → ended → idle

RECOVERY:
  active → reconnecting → active   (başarılı)
  active → reconnecting → ended    (timeout)
```

### 3.4 Cross-Cutting Events

Bu event'ler herhangi bir state'te gelebilir. Her state için davranışı Bölüm 5 transition tablosunda tanımlanmıştır.

| Event               | Kaynak                              |
|---------------------|-------------------------------------|
| `network_lost`      | Sistem (iOS/Android connectivity)   |
| `network_restored`  | Sistem                              |
| `app_background`    | Kullanıcı (home/swipe)              |
| `app_foreground`    | Kullanıcı (geri dönüş)              |
| `app_crash`         | Sistem (OOM, exception)             |
| `app_launch`        | Kullanıcı (crash sonrası yeniden aç)|

#### Network kaybında genel kural:
- **WS:** Hemen kapanır, `mark_dm_offline` → Redis temizlenir
- **LiveKit:** Kendi reconnect mekanizması devreye girer
- **Pending state:** `network_restored` event'inde `/calls/active` ile state restore

#### Crash/launch'da genel kural:
- App açılışında `/calls/active` sorgulanır
- Aktif çağrı varsa → ilgili role'e göre state restore
- Aktif çağrı yoksa → `idle`

---

### 3.5 Flutter-Only Terminal State'ler ve EndReason (Step 3 Hedefi)

Aşağıdaki state'ler şu an `CallStatus` enum'unda mevcuttur. Step 3'te `ended + EndReason` yapısına absorbe edilecekler; bu tablo geçiş dönemi için referanstır.

| Mevcut State | DB temsili | EndReason hedefi | Açıklama |
|---|---|---|---|
| `rejected` | `rejected` | `EndReason.rejected` | Callee reddetti |
| `missed` | `missed` | `EndReason.missed` | Ring timeout (server ARQ) |
| `noAnswer` | `missed` (DB'de fark yok) | `EndReason.noAnswer` | Caller 30s timer — POST /missed |
| `busy` | Kayıt oluşmaz | `EndReason.busy` | /start 409 yanıtı |
| `permissionDenied` | Kayıt oluşmaz | `EndReason.permissionDenied` | Mic izni yok |

**EndReason enum (Step 3 sonrası hedef model):**

```dart
enum EndReason {
  normal,           // user_call_end (her iki taraf normalce kapattı)
  rejected,         // callee reddetti
  missed,           // ring timeout — server bildirdi
  noAnswer,         // caller 30s timer
  busy,             // /start 409 — callee meşgul
  permissionDenied, // mic izni reddedildi
  error,            // LiveKit/API kalıcı hata
}
```

**Step 3 sonrası UI geçiş kuralı:**

```dart
// Şu an:
cs.status == CallStatus.rejected
// Step 3 sonrası:
cs.status == CallStatus.ended && cs.endReason == EndReason.rejected
```

**Auto-pop kuralı:** `ended` state'ine girildiğinde `endReason != null` ise call_screen 2s sonra dismiss edilir. `endReason == null` (henüz belirlenmemiş) ise bekler.

---

## 4. Event Kataloğu

Event'ler kaynağına göre gruplandırılmıştır. Her event hangi role'ü etkiler bilgisini taşır. Hangi state'lerde geçerli olduğu Bölüm 5 transition tablosunda tanımlanır.

### 4.1 Kullanıcı Event'leri

Doğrudan kullanıcı etkileşiminden üretilir (dokunuş, swipe, buton).

| Event                | Role   | Açıklama                                              |
|----------------------|--------|-------------------------------------------------------|
| `user_call_start`    | caller | Arama başlat butonuna bastı                           |
| `user_call_accept`   | callee | IncomingCallBar'da kabul taptı                        |
| `user_call_reject`   | callee | IncomingCallBar'da reddet taptı                       |
| `user_call_end`      | both   | Aktif aramada kapat taptı                             |
| `user_call_cancel`   | caller | Callee henüz cevaplamadı, iptal taptı                 |
| `user_swipe_minimize`| callee | IncomingCallBar'ı swipe-up ile küçülttü               |
| `user_swipe_restore` | callee | MinimizedCallBar'ı swipe-down ile geri açtı           |

### 4.2 API Event'leri

HTTP istek yanıtlarından üretilir.

| Event               | Role   | Açıklama                                               |
|---------------------|--------|--------------------------------------------------------|
| `api_start_ok`      | caller | POST /start 200 — call_id + token geldi                |
| `api_start_error`   | caller | POST /start başarısız (busy, network, 5xx)             |
| `api_accept_ok`     | callee | POST /accept 200                                       |
| `api_accept_error`  | callee | POST /accept başarısız                                 |
| `api_end_ok`        | both   | POST /end 200                                          |
| `api_active_found`  | both   | GET /active → aktif arama var (recovery)               |
| `api_active_none`   | both   | GET /active → aktif arama yok (recovery)               |

### 4.3 WebSocket Event'leri

Sunucudan gerçek zamanlı olarak gelir.

| Event               | Role   | Açıklama                                               |
|---------------------|--------|--------------------------------------------------------|
| `ws_call_incoming`  | callee | Gelen arama bildirimi                                  |
| `ws_call_accepted`  | caller | Callee kabul etti                                      |
| `ws_call_rejected`  | caller | Callee reddetti                                        |
| `ws_call_ended`     | callee | Caller aramayı kapattı                                 |
| `ws_call_missed`    | callee | Ring timeout doldu                                     |
| `ws_connected`      | both   | WS bağlantısı kuruldu (recovery tetikler)              |
| `ws_disconnected`   | both   | WS bağlantısı koptu                                    |

### 4.4 Push / CallKit Event'leri

Platform bildirim katmanından üretilir.

| Event                | Role   | Açıklama                                              |
|----------------------|--------|-------------------------------------------------------|
| `voip_push_received` | callee | iOS VoIP push geldi (background / killed)             |
| `fcm_push_received`  | callee | Android FCM push geldi (background / killed)          |
| `callkit_accept`     | callee | iOS native ekranda kabul kaydırdı                     |
| `callkit_decline`    | callee | iOS native ekranda reddet kaydırdı                    |
| `callkit_ended`      | both   | CallKit aramayı sonlandırdı                           |

### 4.5 LiveKit Event'leri

Medya katmanından üretilir.

| Event               | Role   | Açıklama                                               |
|---------------------|--------|--------------------------------------------------------|
| `lk_connect_ok`     | both   | room.connect() başarılı                                |
| `lk_connect_failed` | both   | room.connect() başarısız                               |
| `lk_peer_joined`    | both   | Karşı taraf LiveKit'e bağlandı                         |
| `lk_peer_left`      | both   | Karşı taraf LiveKit'ten ayrıldı                        |
| `lk_reconnecting`   | both   | Network koptu, LiveKit kendi retry'ını başlattı        |
| `lk_reconnected`    | both   | LiveKit retry başarılı                                 |
| `lk_disconnected`   | both   | LiveKit bağlantı tamamen koptu                         |

### 4.6 Timer Event'leri

Dahili zamanlayıcılardan üretilir.

| Event                 | Role   | Açıklama                                             |
|-----------------------|--------|------------------------------------------------------|
| `timer_ring_expired`  | caller | 30s doldu, callee cevaplamadı → missed               |
| `timer_peer_expired`  | both   | 40s doldu, LiveKit'te peer gelmedi                   |
| `timer_connecting_exp`| both   | 15s doldu, connecting state'inde takıldı             |
| `timer_reset_ready`   | both   | Ended'dan sonra 2s bekleme doldu → idle              |

### 4.7 Sistem / OS Event'leri

Cross-cutting — herhangi bir state'te gelebilir.

| Event                  | Role   | Açıklama                                            |
|------------------------|--------|-----------------------------------------------------|
| `network_lost`         | both   | İnternet bağlantısı koptu                           |
| `network_restored`     | both   | İnternet bağlantısı geri geldi                      |
| `app_background`       | both   | Uygulama arka plana geçti                           |
| `app_foreground`       | both   | Uygulama ön plana geçti                             |
| `app_crash`            | both   | Uygulama beklenmedik şekilde kapandı                |
| `app_launch`           | both   | Soğuk başlatma (crash sonrası dahil)                |
| `audio_session_active` | callee | iOS CallKit audio session aktive edildi             |
| `audio_focus_gained`   | callee | Android AudioFocus verildi                          |
| `audio_focus_lost`     | both   | Android AudioFocus başka uygulamaya geçti           |

### 4.8 Hata Event'leri

Herhangi bir katmandaki başarısızlık durumları.

| Event                | Role   | Açıklama                                              |
|----------------------|--------|-------------------------------------------------------|
| `error_mic_denied`   | both   | Mikrofon izni reddedildi                              |
| `error_busy_caller`  | caller | Caller zaten başka aramada                            |
| `error_busy_callee`  | caller | Callee meşgul (409)                                   |
| `error_call_not_found`| both  | Arama bulunamadı (404)                                |
| `error_lk_permanent` | both   | LiveKit retry sonrasında da bağlanamadı               |

---

## 5. Transition Tablosu

Her state için: hangi event, hangi role'de, hangi yeni state'e geçirir.  
Tabloda yer almayan event + state kombinasyonu → **yoksay** (log'la, state değiştirme).

### 5.0 Tasarım Kararları

Bu bölümdeki tablolar aşağıdaki kararlara dayanır.

| # | Konu | Karar | Gerekçe |
|---|------|-------|---------|
| D-1 | `network_lost` in `waiting` timeout | **20s** | Ring timer 30s — hiccup toleransı için yeterli pencere |
| D-2 | Callee fallback ring timer | **45s** | Caller 30s + server ARQ 40s'i de kapsar + buffer |
| D-3 | `lk_peer_left` in `active` timeout | **10s** | Endüstri standardı (WhatsApp/Zoom pattern) |
| D-4 | `audio_focus_lost` state etkisi | **State değişmez** | Adapter içinde yönetilir; state machine görmez |
| D-5 | `reset()` — herhangi state'ten doğrudan `idle` | `reset()` herhangi bir state'ten direkt `idle`'a geçer, `ended`'ı atlar. `rejectCall()` ve `noAnswer` timer şu an bu yolu kullanıyor. State machine `→ idle` geçişlerine izin verir. | Step 8 hedefi: `reject` ve `noAnswer` akışları önce `ended`'a geçip sonra 2s sonra `idle`'a geçecek. Şimdilik `reset()` direkt geçiş için güvenli çünkü ringing/noAnswer'da temizlenecek LK/audio kaynağı yok. |

---

### 5.1 `idle`

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `user_call_start` | caller | `dialing` | /start isteği gönderilir |
| `ws_call_incoming` | callee | `ringing` | WS ile gelen arama |
| `voip_push_received` | callee | `ringing` | Background/killed — VoIP push |
| `fcm_push_received` | callee | `ringing` | Background/killed — FCM push |
| `ws_connected` | both | `idle` → restore? | /active sorgula; aktif arama varsa state restore |
| `app_launch` | both | `idle` → restore? | /active sorgula; aktif arama varsa state restore |
| `error_mic_denied` | caller | `permissionDenied` | Mic kontrolü `dialing`'den önce yapılır; izin yoksa arama başlatılmaz |
| diğer | both | `idle` | Yoksay |

---

### 5.2 `dialing` (caller only)

HTTP isteği uçuşta. Sunucu yanıtı bekleniyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `api_start_ok` | caller | `waiting` | call_id + token alındı |
| `api_start_error` | caller | `ended` | busy / network / 5xx — kullanıcıya hata göster |
| `user_call_cancel` | caller | `ended` | İstek uçuştayken iptal — /end fire-and-forget |
| `network_lost` | caller | `ended` | Request tamamlanamaz |
| `error_mic_denied` | caller | `ended` | İzin yok, arama başlatılamaz |
| diğer | caller | `dialing` | Yoksay |

---

### 5.3 `waiting` (caller only)

Sunucu onayladı. Callee bildirildi. Caller'ın cevap bekleme aşaması.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `ws_call_accepted` | caller | `connecting` | Callee kabul etti, ses aktivasyonu başlar |
| `ws_call_rejected` | caller | `ended` | Callee reddetti |
| `ws_call_missed` | caller | `ended` | Sunucu timeout (ARQ) |
| `timer_ring_expired` | caller | `ended` | 30s doldu → POST /missed |
| `user_call_cancel` | caller | `ended` | POST /end |
| `lk_connect_ok` | caller | `waiting` | Pre-connect tamam, callee hâlâ bekleniyor |
| `network_lost` | caller | `waiting` | D-1: 20s bekle; süre dolunca → `ended` |
| `ws_connected` | caller | `waiting` | /active → hâlâ calling: burada kal |
| `app_background` | caller | `waiting` | Arama devam eder |
| diğer | caller | `waiting` | Yoksay |

> **`error_mic_denied`:** Mic kontrolü `startCall()` içinde `dialing` state'e **girmeden** önce yapılır. Bu nedenle mic izni reddi §5.1 (idle) tablosunda — `idle → permissionDenied` transition'ı olarak modellenmiştir. `dialing` state'inden mic denied event'i gelmez.

---

### 5.4 `ringing` (callee only)

Callee bildirim aldı, kullanıcı kararını bekliyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `user_call_accept` | callee | `connecting` | POST /accept + ses aktivasyonu |
| `user_call_reject` | callee | `ended` | POST /reject |
| `callkit_accept` | callee | `connecting` | iOS native ekrandan kabul |
| `callkit_decline` | callee | `ended` | iOS native ekrandan reddet |
| `ws_call_ended` | callee | `ended` | Caller iptal etti |
| `ws_call_missed` | callee | `ended` | Sunucu timeout bildirdi |
| `timer_ring_expired` | callee | `ended` | D-2: 45s fallback — WS gelmezse kendisi sonlandır |
| `lk_connect_ok` | callee | `ringing` | Pre-connect tamam, hâlâ ringing |
| `ws_call_incoming` | callee | `ringing` | Dedup — zaten burada, yoksay |
| `voip_push_received` | callee | `ringing` | Dedup — yoksay |
| `fcm_push_received` | callee | `ringing` | Dedup — yoksay |
| `error_mic_denied` (denied) | callee | `ended` | acceptCall öncesi mic izni reddedildi; `/reject` fire-and-forget |
| `error_mic_denied` (permanentlyDenied) | callee | `ringing` | State **KALMAZ**; `permPermanentlyDenied=true`; in-app modal + [Ayarlar'a Git]; kullanıcı döndüğünde `/calls/active` check (§15.2–15.3) |
| `network_lost` | callee | `ringing` | Native screen devam eder (CallKit) |
| `ws_connected` | callee | `ringing` | /active → hâlâ calling: burada kal |
| `app_background` | callee | `ringing` | Native screen yönetir |
| diğer | callee | `ringing` | Yoksay |

---

### 5.5 `connecting` (both)

Callee kabul etti. LiveKit bağlantısı ve ses aktivasyonu sürüyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `lk_connect_ok` | caller | `active` | Pre-connect yoksa; Android callee için de geçerli |
| `lk_peer_joined` | caller | `active` | Pre-connect durumunda callee LiveKit'e katıldı |
| `audio_session_active` | callee | `active` | iOS: `_callkitAudioReady` Completer fulfills → mic aktif |
| `audio_focus_gained` | callee | `active` | Android: AudioFocus alındı → mic aktif |
| `api_accept_error` | callee | `ended` | /accept başarısız — caller iptal → 404, veya 5xx |
| `callkit_ended` | both | `ended` | Sistem / native ekran aramayı sonlandırdı |
| `timer_connecting_exp` | both | `ended` | 15s doldu, takıldı |
| `lk_connect_failed` | both | `ended` | Bağlantı kurulamadı |
| `error_lk_permanent` | both | `ended` | LiveKit tamamen vazgeçti |
| `user_call_end` | both | `ended` | Connecting'de kullanıcı kesti |
| `ws_call_ended` | both | `ended` | Karşı taraf connecting'de kesti |
| `network_lost` | both | `ended` | Connecting'de ağ kesilirse retry yok |
| `lk_reconnecting` | both | `reconnecting` | LiveKit kendi retry'ını başlattı — connecting'de de tetiklenebilir |
| diğer | both | `connecting` | Yoksay |

> **Callee mic kontrolü:** Hedef (Step 5 sonrası) — mic izni `connecting`'e **girmeden**, `ringing` state'indeyken kontrol edilir (§5.4 + §15.2). `connecting → permissionDenied` callee geçişi Step 5 öncesi mevcut kodda geçici olarak var; Step 5'te kaldırılacak.

> **iOS Callee — `_callkitAudioReady` Completer:**  
> iOS callee için `connecting→active` iki koşul gerektirir: LiveKit bağlantısı (`lk_connect_ok`) VE AVAudioSession aktivasyonu (`audio_session_active`). Sıra belirsizdir; hangisi geç gelirse o `active`'i tetikler. `_audioSessionActivated` flag erken gelen sinyalin kaybolmasını önler.

---

### 5.6 `active` (both)

Ses bağlantısı kuruldu, arama sürüyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `user_call_end` | both | `ended` | POST /end |
| `ws_call_ended` | both | `ended` | Karşı taraf kapattı |
| `lk_peer_left` | both | `active`* | D-3: 10s peer timer başlar; gelirse devam, gelmezse `ended` |
| `lk_disconnected` | both | `reconnecting` | LiveKit bağlantısı koptu |
| `lk_reconnecting` | both | `reconnecting` | LiveKit kendi retry'ını bildirdi |
| `network_lost` | both | `reconnecting` | Ağ koptu, LiveKit retry başlar |
| `callkit_ended` | both | `ended` | iOS sistem aramayı kapattı |
| `audio_focus_lost` | both | `active` | D-4: State değişmez — adapter yönetir |
| `audio_focus_gained` | both | `active` | D-4: Adapter restore eder |
| `app_background` | both | `active` | Arama arka planda devam eder |
| `app_crash` | both | `active`* | Recovery: app_launch → /active → restore |
| diğer | both | `active` | Yoksay |

---

### 5.7 `reconnecting` (both)

`active` iken bağlantı koptu. LiveKit yeniden bağlanmayı deniyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `lk_reconnected` | both | `active` | Başarılı — devam |
| `lk_disconnected` | both | `reconnecting` | Hâlâ deniyor |
| `timer_peer_expired` | both | `ended` | Timeout — vazgeçildi |
| `error_lk_permanent` | both | `ended` | LiveKit tamamen vazgeçti |
| `user_call_end` | both | `ended` | Kullanıcı reconnecting'de kesti |
| `ws_call_ended` | both | `ended` | Karşı taraf bağlantı beklerken kesti |
| `network_restored` | both | `reconnecting` | Ağ geldi, LiveKit retry devam |
| diğer | both | `reconnecting` | Yoksay |

---

### 5.8 `ended` (both)

Arama sonlandı. 2s cleanup penceresi.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `timer_reset_ready` | both | `idle` | 2s doldu, reset tamamlandı |
| diğer | both | `ended` | Geç gelen event'ler yoksayılır |

---

## 6. Platform Side Effect'leri (Hardware Adapter)

State machine platform-agnostic'tir. Her transition'ın platform-specific side effect'i bu bölümde tanımlanır.

---

### 6.1 iOS — CallHardwareAdapter

**Merkezi otorite:** `AVAudioSession`  
**Arama UI:** CallKit (native sistem ekranı)  
**Audio session aktivasyon sinyali:** `didActivateAudioSession` (CallKit callback)

#### State → Side Effect

| State | Side Effect |
|---|---|
| `dialing` | AVAudioSession: `playAndRecord/voiceChat` configure; ringback başlar (loop) |
| `waiting` | ringback devam |
| `ringing` | VoIP push → `reportNewIncomingCall` → CallKit native screen, sistem zili |
| `connecting` | `_callkitAudioReady` Completer bekler (`didActivateAudioSession` sinyaline kadar) |
| `active` | Completer tamamlanır; `setSpeakerphoneOn(swipeLiveActive)` — session configure SONRASI |
| `reconnecting` | weak.wav earpiece; AVAudioSession değiştirilmez |
| `ended` | ended.wav veya busy.wav earpiece; `provider.reportCall(with:endedAt:reason:)` |
| `idle` | AVAudioSession release; tüm player'lar durdurulur |

#### Kritik kurallar

**`room.connect()` AVAudioSession override:**  
`room.connect()` içeride AVAudioSession'ı `soloAmbient`'e çeker → ringback durur.  
Çözüm: `room.connect()` sonrası `playAndRecord/voiceChat` yeniden configure + ringback resume.

**`setSpeakerphoneOn` sırası:**  
Her zaman `session.configure()` SONRASI çağrılmalı; önce çağrılırsa AVAudioSession override'ı sıfırlar.

**`_callkitAudioReady` Completer:**  
`didActivateAudioSession` sinyali `connecting` state'inde gelir. Sinyal erken gelse dahi `_audioSessionActivated` flag sayesinde Completer kaybolmaz — `_joinRoom()` asla sinyal kaçırmaz.

**Foreground çağrı dismiss (saveEndCall):**  
WS online kullanıcıya push gönderilmez (§9.3). Eğer race condition nedeniyle push gelirse: `appIsActive=true` → `saveEndCall(uuid, 3)` ile `provider.reportCall(ended:)` çağrılır. Bu, `CXCallController` round-trip'inden (~67ms) daha hızlıdır.

---

### 6.2 Android — CallHardwareAdapter

**Merkezi otorite:** `AudioFocus` (AudioManager)  
**Arama UI:** `flutter_callkit_incoming` (bildirim tabanlı — CallKit yok)  
**Audio session aktivasyon sinyali:** YOK — doğrudan configure

#### State → Side Effect

| State | Side Effect |
|---|---|
| `dialing` | AudioSession configure `voiceChat`; ringback `ReleaseMode.loop` başlar |
| `waiting` | ringback devam |
| `ringing` | FCM push → bildirim UI; sistem zili |
| `connecting` | AudioFocus GAIN talep edilir; `_activateCalleeAudio()` doğrudan çağrılır |
| `active` | `setSpeakerphoneOn(swipeLiveActive)` — AudioSession configure SONRASI |
| `reconnecting` | weak.wav; AudioFocus değiştirilmez |
| `ended` | ended.wav / busy.wav (`voiceCommunication` context); AudioFocus abandon |
| `idle` | tüm player'lar durdurulur, AudioFocus release |

#### Kritik kurallar

**`ReleaseMode.loop`:**  
`onPlayerComplete` AudioFocus kaybında tetiklenmez. `ReleaseMode.loop` native MediaPlayer loop kullanır; focus kaybı + resume sonrası loop devam eder.

**`voiceCommunication` context (bitiş sesleri):**  
WebRTC AudioFocus bırakınca Android ses çıkışını speaker'a döndürür. ended.wav / busy.wav için `voiceCommunication` usage context tanımlanmazsa bu sesler speaker'dan çıkar.

**`setCallConnected(uuid)` notu:**  
Android'de yalnızca görsel bildirim günceller; iOS `didActivateAudioSession` eşdeğeri etkisi yoktur.

---

### 6.3 Audio Routing Tablosu

| State | Ses | iOS Çıkış | Android Çıkış |
|---|---|---|---|
| `dialing` / `waiting` | ringback.wav (loop) | Earpiece | Earpiece (voiceCommunication) |
| `ringing` | Sistem zili | Speaker (platform default) | Speaker (platform default) |
| `connecting` | — | Earpiece | Earpiece |
| `active` | Gerçek ses | Caller=Earpiece / Callee=bkz.aşağı | Caller=Earpiece / Callee=bkz.aşağı |
| `reconnecting` | weak.wav | Earpiece | Earpiece |
| `ended` (bağlıyken) | ended.wav | Earpiece | Earpiece (voiceCommunication) |
| `ended` (reject/busy) | busy.wav | Earpiece | Earpiece (voiceCommunication) |
| `idle` | Sessiz | — | — |

**Callee active ses kuralı:**  
Callee SwipeLive'daysa → Speaker, değilse → Earpiece.  
Caller her zaman Earpiece (SwipeLive PiP'teyken de).  
Karar verici: `preventCallScreenAutoOpen` flag'i.

---

### 6.4 Platform Fark Özeti

| Konu | iOS | Android |
|---|---|---|
| Ses otoritesi | AVAudioSession | AudioFocus + AudioManager |
| Arama UI | CallKit (native) | flutter_callkit_incoming (bildirim) |
| Audio session aktivasyon sinyali | `didActivateAudioSession` (CallKit) | Yok — doğrudan configure |
| Ringback loop | ReleaseMode.loop | ReleaseMode.loop |
| `room.connect()` yan etkisi | AVAudioSession → soloAmbient | AudioFocus talep eder |
| `room.connect()` sonrası | playAndRecord yeniden configure | 200ms bekleme + ringback kontrol |
| Speakerphone sırası | `setSpeakerphoneOn` (session.configure sonrası) | `setSpeakerphoneOn` (AudioSession sonrası) |

---

## 7. Call Related UI Routing

`CallScreenRouter` arama state'ini, role'ü ve bağlamı okuyarak hangi ekranın gösterileceğine karar verir. Her ekran kendi state yorumunu yapmaz; routing kararı tek bir yerden çıkar.

---

### 7.1 Ekran Envanteri

| Ekran | Açıklama |
|---|---|
| `CallScreen` | Tam ekran arama ekranı — outgoing, connecting, active, ended |
| `IncomingCallScreen` | Tam ekran gelen arama (callee, foreground, SwipeLive yok) |
| `IncomingCallBar` | Alt bar — gelen arama (callee, SwipeLive aktif) |
| `MinimizedCallBar` | Küçültülmüş durum (swipe-up ile açılır, swipe-down ile restore) |
| CallKit Native Screen | iOS sistem ekranı — VoIP push ile açılır |
| FCM Notification | Android bildirim — background/killed state |

---

### 7.2 Routing Tablosu

| State | Role | Bağlam | Ekran |
|---|---|---|---|
| `idle` | both | — | Yok |
| `dialing` | caller | — | `CallScreen` (calling indicator) |
| `waiting` | caller | — | `CallScreen` (ringing indicator) |
| `ringing` | callee | foreground, SwipeLive yok | `IncomingCallScreen` |
| `ringing` | callee | foreground, SwipeLive aktif | `IncomingCallBar` |
| `ringing` | callee | background / killed (iOS) | CallKit Native Screen (VoIP push) |
| `ringing` | callee | background / killed (Android) | FCM Notification |
| `connecting` | both | — | `CallScreen` (connecting state) |
| `active` | both | `preventCallScreenAutoOpen=false` | `CallScreen` |
| `active` | both | `preventCallScreenAutoOpen=true` | `MinimizedCallBar` (SwipeLive PiP) |
| `reconnecting` | both | — | `CallScreen` (reconnecting indicator) |
| `ended` | both | — | `CallScreen` (ended tone → 2s sonra dismiss) |

---

### 7.3 Routing Kuralları

**Kural 1 — Tek karar noktası:**  
Hangi ekranın açılacağı / kapanacağı `CallScreenRouter`'dan geçer. State değişikliği → router bildirilir → router ekran kararını verir. Ekranlar kendi routing kararı vermez.

**Kural 2 — SwipeLive bağlamı:**  
`preventCallScreenAutoOpen=true` → tam ekran aç değil; `false` → tam ekran aç.  
Bu flag tüm routing noktalarında tutarlı biçimde okunur.

**Kural 3 — Dedup:**  
`ringing` state'inde WS eventi + VoIP push eş zamanlı gelebilir. Router zaten `ringing`'deyse ikinci ekranı açmaz.

**Kural 4 — `ended` 2s window:**  
`ended` state'inde ekran hemen kapanmaz; ended tonu çalınır, `timer_reset_ready` (2s) gelince `idle`'a geçilir ve ekran dismiss edilir.

---

## 8. Modül Mimarisi

### 8.1 Modül Listesi

| Modül | Tek Sorumluluk | Platform |
|---|---|---|
| `CallStateMachine` | State + transition logic; event routing | Dart (pure, platform bağımsız) |
| `CallHardwareAdapter` | Audio session, speakerphone, ringback | iOS impl / Android impl ayrı |
| `CallNotifAdapter` | VoIP / FCM push al-gönder, CallKit raporlama | iOS impl / Android impl ayrı |
| `CallScreenRouter` | Hangi ekran — state × role × context | Dart (UI-aware) |
| `CallRepository` | API çağrıları (/start, /accept, /reject, /end, /active) | Dart |
| `CallService` | Orchestration — modülleri bağlar, dışarıya tek API noktası | Dart |

---

### 8.2 Bağımlılık Akışı

```
[UI / Screen]
      │ (yalnızca CallService'e bağımlı)
      ▼
CallService
  ├── CallStateMachine    ← saf state logic
  ├── CallHardwareAdapter ← ses hardware (iOS/Android impl)
  ├── CallNotifAdapter    ← bildirim (iOS/Android impl)
  ├── CallScreenRouter    ← ekran kararı
  └── CallRepository      ← API / network
```

**Kural:** Bağımlılık tek yönlüdür — dış katmandan iç katmana.  
`CallStateMachine` hiçbir modülü import etmez.  
`CallHardwareAdapter` state'i değiştirmez, event'leri dinler.  
`CallService` orkestra eder; iş mantığı kararı vermez.

---

### 8.3 Sorumluluk Sınırları

| Modül | Evet | Hayır |
|---|---|---|
| `CallStateMachine` | State değiştir, transition tanımla | Platform API, UI, network |
| `CallHardwareAdapter` | AVAudioSession, AudioFocus, speakerphone | State değiştir |
| `CallNotifAdapter` | Push gönder/al, CallKit raporla | State değiştir |
| `CallScreenRouter` | Ekran aç/kapat kararı ver | State değiştir, iş mantığı |
| `CallRepository` | HTTP istek yap, yanıt parse et | İş mantığı kararı |
| `CallService` | Modülleri orkestra et | Doğrudan platform API'ye ulaş |

---

## 9. API / DB / Redis Katmanı

### 9.1 API Kontratları

| Endpoint | Method | Role | Çağrı anı | State transition |
|---|---|---|---|---|
| `/calls/start` | POST | caller | `dialing` girişi | `api_start_ok` → `waiting` |
| `/calls/{id}/accept` | POST | callee | `connecting` girişi | — |
| `/calls/{id}/reject` | POST | callee | `ended` girişi (callee) | — |
| `/calls/{id}/end` | POST | both | `ended` girişi | — |
| `/calls/{id}/missed` | POST | caller | `ended` (ring timeout) | fire-and-forget |
| `/calls/active` | GET | both | App launch + WS reconnect | `api_active_found` → restore |

#### `/calls/start`

```
POST /calls/start
Body: { "callee_id": <int> }

200 → { "call_id": <int>, "room_name": <str>, "livekit_url": <str>, "token": <str> }
409 → error_busy_callee  (USER_BUSY — callee meşgul)
423 → error_busy_caller  (CALLER_BUSY — caller zaten aramada)
```

#### `/calls/accept`

```
POST /calls/{id}/accept

200 → { "token": <str>, "livekit_url": <str>, "accepted_at": <ISO timestamp> }
404 → api_accept_error  (race: caller cancel ile çakıştı — §11.3)
```

#### `/calls/active`

```
GET /calls/active

Her zaman 200 döner — 204 yok.

200 → {
  "active_call": {
    "call_id":     <int>,
    "status":      "calling" | "active",
    "role":        "caller" | "callee",
    "room_name":   <str>,
    "livekit_url": <str>,
    "token":       <str>,
    "other_user":  { "id": <int>, "username": <str>, "avatar": <str> },
    "accepted_at": <ISO timestamp | null>   ← null: callee henüz kabul etmedi
  }
}

200, active_call: null → aktif arama yok (api_active_none)
```

---

### 9.2 DB — Call Record Yaşam Döngüsü

| Olay | DB İşlemi |
|---|---|
| `/calls/start` başarılı | INSERT calls (caller_id, callee_id, status="calling", room_name) |
| Callee accept | UPDATE status="active" |
| Callee reject | UPDATE status="rejected" |
| End (bağlıyken) | UPDATE status="ended" |
| Missed (ring timeout) | UPDATE status="missed" |
| Recovery (`/calls/active`) | SELECT WHERE (caller_id=x OR callee_id=x) AND status IN ("calling","active") |

**status enum:** `calling` → `active` → `ended` / `rejected` / `missed`

> `calling` ve `active` geçici state'lerdir — aramalar tamamlandığında hep terminal state'e döner. `SELECT DISTINCT status FROM calls` sorgusu yalnızca terminal değerleri gösterir; `calling`/`active` yalnızca süregelen aramalarda mevcuttur.

---

#### Flutter-Only State'ler (DB Temsili Yok)

| Flutter State | DB karşılığı | Açıklama |
|---|---|---|
| `noAnswer` | `missed` olarak kaydedilir | Caller ring timer (30s) → POST /missed; DB'de `noAnswer` yok |
| `busy` | Kayıt oluşmaz | /start 409 yanıtı → INSERT hiç yapılmaz |
| `permissionDenied` | Kayıt oluşmaz | Mikrofon izni yok → API çağrısı yapılmaz |
| `reconnecting` | `active` kalır | LiveKit geçici kopma → DB update olmaz |

---

#### Recovery Çeviri Tablosu

`/calls/active` → `status` + `role` → Flutter `CallStatus`:

| DB status | role | Flutter state | Restore davranışı |
|---|---|---|---|
| `calling` | `caller` | `waiting` | callerStatusPoll başlatılır |
| `calling` | `callee` | `ringing` | `onIncomingCall()` ile restore |
| `active` | `caller` | `reconnecting` → `active` | LK room'a yeniden bağlan |
| `active` | `callee` | `reconnecting` → `active` | LK room'a yeniden bağlan |
| `null` (active_call: null) | — | `idle` | Aktif arama yok |

---

### 9.3 Redis Anahtarları

| Anahtar | Değer | TTL | Kullanım |
|---|---|---|---|
| `ws_dm_online:{user_id}` | `1` | 90s | WS presence; connect'te set, disconnect'te del |

**Push skip kararı:**  
`/calls/start` → `is_dm_online(callee_id)` → key varsa push atlanır, WS eventi yeterlidir. Key yoksa (background/killed) push gönderilir.

**TTL mantığı:**  
90s TTL WS keepalive cycle'ını kapsar. Normal disconnect'te `mark_dm_offline` ile silinir; crash durumunda TTL korur.

---

## 10. V1.0 Use Case → V2.0 Eşlemesi

V1.0 `VoIP_decisions.md` içindeki use case'ler V2.0 state transition'larına karşılık gelir. V1.0 kararları geçerliliğini korur; V2.0 bunları modele entegre eder.

| UC | V1.0 Başlık | V2.0 State Akışı | Tetikleyici Event |
|---|---|---|---|
| UC-01 | Normal Arama (Callee Kabul) | `idle→dialing→waiting→connecting→active→ended→idle` | `lk_connect_ok` / `audio_session_active` |
| UC-02 | Callee Reddetti | `waiting→ended` (caller) + `ringing→ended` (callee) | `ws_call_rejected` |
| UC-03 | Caller İptal Etti | `waiting→ended` (caller) + `ringing→ended` (callee) | `user_call_cancel` + `ws_call_ended` |
| UC-04 | Cevap Yok (Timeout) | `waiting→ended` / `ringing→ended` | `timer_ring_expired` / `timer_ring_expired` (D-2) |
| UC-05 | Meşgul (Busy) | `dialing→ended` | `api_start_error` (409) |
| UC-06 | Caller Aktif Aramayi Sonlandırdı | `active→ended→idle` (her iki taraf) | `user_call_end` → `ws_call_ended` |
| UC-07 | Callee Aktif Aramayi Sonlandırdı | `active→ended→idle` (her iki taraf) | `user_call_end` → `ws_call_ended` |
| UC-08 | Aramadayken Yeni Arama | Backend guard aktif; mevcut state değişmez | — |
| UC-09 | Ağ Kesintisi / Yeniden Bağlanma | `active→reconnecting→active` veya `→ended` | `lk_reconnected` / `timer_peer_expired` |
| UC-10 | Mikrofon İzni Reddedildi | Caller: `idle→permissionDenied` (dialing öncesi); Callee denied: `ringing→ended`; Callee permanentlyDenied: state `ringing` kalır, modal (§15) | `error_mic_denied` |

**V1.0'dan V2.0'a taşınan kararlar:**

| V1.0 Bölüm | V2.0 Karşılığı |
|---|---|
| §2.1 iOS AVAudioSession + CallKit | Bölüm 6.1 |
| §2.2 Android AudioFocus | Bölüm 6.2 |
| §2.3 Platform fark tablosu | Bölüm 6.4 |
| §3 Audio routing matrisi | Bölüm 6.3 |
| §4 SwipeLive edge case'ler | Bölüm 7.2 (`preventCallScreenAutoOpen`) |
| §5 Architectural decisions | Bölüm 1 axiom'larının motivasyonu |

---

## 11. Anahtar Akış Sekansları

Transition tablosu "ne → ne" anlatır; sekanslar "ne sırayla" anlatır. Her önemli akış için adım adım sıra.

---

### 11.1 Normal Arama — iOS Caller → iOS Callee (Pre-connect ile)

**Caller tarafı:**

```
1.  user_call_start → state: idle → dialing
2.  POST /calls/start →
      200: {call_id, room_name, token}
    api_start_ok → state: dialing → waiting
3.  ringback başlar (loop)
4.  Pre-connect: room.connect(token) → lk_connect_ok
    (waiting'de alınır, state değişmez — caller callee'yi bekler)
5.  Backend callee'yi bildirir (WS + VoIP push)
6.  Callee kabul eder → backend: ws_call_accepted
    ws_call_accepted → state: waiting → connecting
7.  ringback durur
8.  lk_peer_joined (callee LiveKit'e bağlandı)
    lk_peer_joined → state: connecting → active
9.  Ses aktif, CallScreen güncellenir
```

**Callee tarafı (iOS, foreground):**

```
1.  WS ws_call_incoming → state: idle → ringing
2.  IncomingCallScreen açılır
3.  Kullanıcı kabul → user_call_accept → state: ringing → connecting
4.  POST /calls/accept →
      200: {token}
    api_accept_ok → room.connect(token) başlar
5.  CallKit: action.fulfill() çağrılır
6.  provider(_:didActivate:audioSession:) callback → Flutter method channel → audio_session_active
7.  lk_connect_ok VE audio_session_active her ikisi gelince:
    _callkitAudioReady Completer tamamlanır → state: connecting → active
8.  AVAudioSession: playAndRecord/voiceChat configure
    setSpeakerphoneOn(preventCallScreenAutoOpen)
9.  Mikrofon aktif, ses akışı başlar
```

---

### 11.2 Caller Cancel (Caller waiting, Callee ringing)

```
Caller (waiting)                    Backend                 Callee (ringing)
     |                                 |                          |
     | user_call_cancel                |                          |
     | state: waiting → ended          |                          |
     |---- POST /calls/end ----------->|                          |
     |                                 |--- ws_call_ended ------->|
     |                                 |                ws_call_ended
     |                                 |                state: ringing → ended
     |                                 |                IncomingCallScreen kapanır
     | 2s → timer_reset_ready          |                          |
     | state: ended → idle             |                2s → timer_reset_ready
                                                        state: ended → idle
```

---

### 11.3 Race — Caller Cancel + Callee Accept Çakışması

Bu sekans `api_accept_error`'ın neden transition tablosunda olduğunu gösterir.

```
Caller (waiting)              Backend              Callee (ringing)
     |                           |                       |
     | user_call_cancel           |    user_call_accept   |
     | state: waiting → ended    |   state: ringing → connecting
     |--- POST /calls/end ------>|                       |
     |                           | call.status = "ended" |
     |                           |<--- POST /calls/accept|
     |                           |--- 404 (not found) -->|
     |                           |              api_accept_error
     |                           |              state: connecting → ended
     |                           |
     | Her iki taraf ended → idle (2s sonra)
```

> Callee tarafında `ws_call_ended` da gelebilir (backend /end işledi). İkisi de aynı sonuca getirir: `ended`. Dedup: zaten `ended`'daysa `ws_call_ended` yoksayılır.

---

### 11.4 Crash Recovery (Active Call, Caller Crash)

**Kısa crash (< D-3: 10s):**

```
Caller (active) → CRASH
Callee (active): lk_peer_left → 10s peer timer başlar

Caller: app relaunched
  app_launch → idle → GET /calls/active →
    200: {call_id, token, role="caller", status="calling"}
  api_active_found → state: idle → active (restore)
  room.connect(token) — yeni oturumla bağlan

Callee: 10s dolmadan lk_peer_joined → timer iptal → active devam
```

**Uzun crash (> D-3: 10s):**

```
Caller → CRASH
Callee: lk_peer_left → 10s → timer_peer_expired → state: active → ended

Caller: app relaunched
  app_launch → idle → GET /calls/active →
    204 (arama bitti)
  api_active_none → state: idle kalır
```

---

### 11.5 Network Recovery (Active → Reconnecting → Active)

```
Her iki taraf (active):
  Ağ kesildi → network_lost → state: active → reconnecting
  LiveKit kendi reconnect döngüsünü başlatır
  WS hemen kapanır, mark_dm_offline → Redis temizlenir

Ağ geri geldi → network_restored
  LiveKit retry başarılı → lk_reconnected → state: reconnecting → active
  WS yeniden bağlanır → ws_connected → GET /calls/active → hâlâ calling: state doğrulandı

Retry başarısız (D-3: 40s):
  timer_peer_expired → state: reconnecting → ended
```

---

## 12. CallNotifAdapter Spesifikasyonu

Push bildirim katmanının tam spesifikasyonu. Bu adapter `CallHardwareAdapter` ile aynı seviyede; state değiştirmez, event üretir.

---

### 12.1 Push Payload Formatları

**VoIP Push (iOS APNs — background/killed):**

```json
{
  "call_id": "123",
  "caller_id": "456",
  "caller_username": "ahmet",
  "caller_avatar": "/uploads/avatars/ahmet.jpg",
  "room_name": "lk_room_abc123",
  "livekit_token": "<jwt>",
  "type": "incoming_call"
}
```

**FCM Data Push (Android — background/killed):**

```json
{
  "data": {
    "type": "incoming_call",
    "call_id": "123",
    "caller_id": "456",
    "caller_username": "ahmet",
    "caller_avatar": "/uploads/avatars/ahmet.jpg",
    "room_name": "lk_room_abc123",
    "livekit_token": "<jwt>"
  }
}
```

**Push type değerleri:**

| type | Açıklama | Alıcı event |
|---|---|---|
| `incoming_call` | Yeni arama | `voip_push_received` / `fcm_push_received` |
| `call_cancelled` | Caller iptal etti (background callee) | Background'da CallKit dismiss |
| `call_ended` | Arama bitti | Background'da CallKit dismiss |

---

### 12.2 Token Kayıt Akışı

**iOS VoIP token:**
```
pushRegistry(_:didUpdate:for:) callback
  → token hex string
  → POST /users/me/voip-token { "token": "<hex>" }
```

**iOS FCM token:**
```
Messaging.messaging().token (uygulama açılışında)
  → POST /users/me/fcm-token { "token": "<fcm_token>" }
```

**Android FCM token:**
```
FirebaseMessaging.instance.getToken()
  → POST /users/me/fcm-token { "token": "<fcm_token>" }
```

**Token yenileme:**
- iOS VoIP: `pushRegistry(_:didUpdate:for:)` yeni token → aynı endpoint
- Android/iOS FCM: `FirebaseMessaging.onTokenRefresh` → aynı endpoint
- Token yenileme, uygulama açık olmasa da çalışmalı — arka planda kayıt

**Token geçersizleşme:**
- Kullanıcı uygulamayı yeniden kurduğunda yeni token üretilir. Uygulama ilk açılışta kayıt eder → DB güncellenir.
- Eski (stale) token APNs tarafından reddedilir: backend bu hatayı yakalamalı ve `voip_token = NULL` yapmalıdır.
- FCM stale token: `messaging/invalid-registration-token` hatası → aynı şekilde temizlenmeli.

**Multi-device modeli (mevcut sınırlama):**

V2.0 tek cihaz varsayımı üzerine çalışır: her `POST /users/me/voip-token` öncekinin üzerine yazar. Kullanıcı birden fazla cihazda login olursa yalnızca son kaydeden cihaz push alır.

Çoklu cihaz desteği gerekirse DB modeli şu formata taşınmalıdır:

```
push_tokens(user_id, device_id, token_type, token_value, updated_at)
PK: (user_id, device_id, token_type)
```

Step 7 (`CallNotifAdapter`) bu sınırlamayı bilerek implemente eder. Çoklu cihaz desteği ayrı bir migration olarak ele alınır.

---

### 12.3 Push Skip Kuralı

```
Backend /calls/start:
  callee_ws_connected = is_dm_online(callee_id)  ← Redis: ws_dm_online:{id}

  if callee_ws_connected:
      push ATLA — WS eventi yeterli
  else:
      callee'nin kayıtlı token'larına göre:
        voip_token varsa → VoIP push (iOS — CallKit native screen)
        voip_token yoksa, fcm_token varsa → FCM push (Android)
      her ikisi yoksa → sadece WS eventi (foreground-only teslimat)
```

**iOS'ta VoIP push FCM'e her zaman tercih edilir.**  
FCM data push iOS'ta background/killed state'te CallKit'i tetikleyemez. VoIP push APNs'in yüksek öncelikli kanalıdır ve doğrudan `pushRegistry` callback'ini çalıştırır. iOS FCM token yalnızca non-call bildirimler (sohbet, genel bildirimler) içindir.

---

### 12.4 Token Null Durumu

| voip_token | fcm_token | Sonuç |
|---|---|---|
| var | — | VoIP push — iOS cihazı, FCM henüz kaydolmamış |
| — | var | FCM push — Android cihazı |
| var | var | **VoIP push tercih edilir** — iOS cihazı; FCM yalnızca non-call bildirimler için |
| null | null | Push yok — WS bağlıysa ulaşır, değilse arama kaybolur |

> Token null ise ve WS offline ise callee aramayı hiç görmez. Bu bir hata değil, tasarım gereği — token kayıt başarısız olmuş demektir. Backend bu durumu loglamalı.

---

### 12.5 Background'da `call_cancelled` / `call_ended` İşleme

Callee background'da beklerken caller iptal ederse:

**iOS (background):**
```
VoIP push: type="call_cancelled"   ← VoIP push tercih edilir (yüksek öncelikli APNs kanalı)
  → AppDelegate: saveEndCall(uuid, reason=.remoteEnded)
  → provider.reportCall(with:endedAt:reason:) → CallKit native ekran kapanır
  → Flutter: callkit_ended event → state: ringing → ended
```

**Android (background):**
```
FCM push: type="call_cancelled"
  → flutter_callkit_incoming: hideCallkitIncoming(uuid)
  → Bildirim kaldırılır
  → Flutter: event → state: ringing → ended
```

---

## 13. Log Katmanı

### 13.1 Log Format

**Flutter — `CallService` (orchestrator):**
```
[CALL_PROCESS][<ISO timestamp>][<phase>] <message>
```

**Flutter — Refactored modüller (CallRepository, CallHardwareAdapter, CallNotifAdapter, CallScreenRouter):**
```
[<MODULE>][<ISO timestamp>][<phase>] <message>
```

| Modül | MODULE tag |
|---|---|
| `CallRepository` | `CALL_REPO` |
| `CallHardwareAdapter` (iOS) | `CALL_HW_IOS` |
| `CallHardwareAdapter` (Android) | `CALL_HW_AND` |
| `CallNotifAdapter` | `CALL_NOTIF` |
| `CallScreenRouter` | `CALL_ROUTER` |

**Flutter — UI widget'ları:**
```
[UI_CALL][<component>][<ISO timestamp>] <event> | <detail>
```

**Backend — Python:**
```
[CALL_PROCESS][<severity>] <phase> | <message>
```

---

### 13.2 Flutter Phase Tag'leri

| Tag | Modül | Neyi loglar |
|---|---|---|
| `STATE` | CallService | Her state transition — format §13.3'te |
| `OUT` | CallService / CallRepository | Outgoing caller akışı — /start isteği ve yanıtı |
| `IN` | CallService / CallRepository | Incoming callee akışı — WS eventi, push, /accept |
| `HW` | CallHardwareAdapter | AVAudioSession, AudioFocus, wakelock, routing |
| `PERM` | CallHardwareAdapter | Mic/kamera izin isteği ve sonucu |
| `SOUND` | CallHardwareAdapter | ringback.wav, ended.wav, busy.wav başlat/dur |
| `LK` | CallService | LiveKit — room.connect, disconnect, peer join/leave |
| `TIMER` | CallService | Zamanlayıcı start/fire — ring, connecting, peer timeout |
| `RECOVERY` | CallService | Crash/reconnect recovery — checkActiveCall adımları |
| `EVENT` | CallService | WS event handling |
| `END` | CallService | Arama sonlandırma akışı — `_hangUpLocally` |
| `API` | CallRepository | HTTP istek gönderilmeden önce ve yanıt sonrası |
| `NOTIF` | CallNotifAdapter | Push token kayıt, CallKit raporlama |
| `ROUTER` | CallScreenRouter | resolveScreen kararı |
| `UI` | CallService / UI widget | UI state değişimleri |
| `VIDEO` | CallService | LiveKit video/track event'leri |

**UI Component Tag'leri (`[UI_CALL][component]`):**

| Component | Kullanım |
|---|---|
| `PILL` | GlobalCallOverlay — göster, gizle, tap, end tap |
| `CALL_SCREEN` | CallScreen — status text, auto-pop |
| `INCOMING_SCREEN` | IncomingCallScreen — pop, pushReplacement, permissionDenied dialog |

---

### 13.3 Log Kuralları

**State transition (zorunlu):**

Her `_setState` çağrısından önce `STATE` tag ile loglanır:
```
STATE | ${oldStatus} → ${newStatus} | callId=${id} | role=${role}
```
Geçiş `ended` ise `endReason` da eklenir:
```
STATE | ${oldStatus} → ended | callId=${id} | role=${role} | endReason=${endReason}
```

**HTTP (zorunlu):**

İstek öncesi ve yanıt sonrası `API` tag ile loglanır:
```
API | → POST /calls/start | calleeId=${id}
API | ← 200 /calls/start | callId=${callId}
API | ← 409 /calls/start | USER_BUSY
```

**İzin (zorunlu):**

Her `requestMicPermission()` / `requestCameraPermission()` çağrısı `PERM` tag ile loglanır:
```
PERM | mic request → granted | role=caller
PERM | mic request → denied | role=callee
PERM | mic request → permanentlyDenied | role=callee
```

**Genel kurallar:**

- Sessiz başarılar loglanmaz; yalnızca anlamlı event'ler ve hata durumları.
- `debugPrint` → debug build'de terminale çıkar; release build'de yok olur.
- Backend `logger.info` / `logger.warning` / `logger.error` → production'da kalıcı.
- Her yeni modül `_log(String phase, String msg)` private helper tanımlar; format §13.1'e uyar.

---

### 13.4 Debug Grep Komutu

```bash
# Tüm arama akışı — debug build
flutter run | grep -iE --line-buffered \
  "CALL_PROCESS|CALL_REPO|CALL_HW_IOS|CALL_HW_AND|CALL_NOTIF|CALL_ROUTER|UI_CALL|LIVE_SCREEN_CALL|Multiple devices|Please choose|\[[0-9]+\]:|Launching|Running Gradle|Syncing files"
```

Sadece state geçişleri:
```bash
flutter run 2>&1 | grep -E --line-buffered "STATE \|"
```

Sadece izin + sonlandırma:
```bash
flutter run 2>&1 | grep -E --line-buffered "PERM \||END \||endReason"
```

Sadece ses:
```bash
flutter run 2>&1 | grep -E --line-buffered "SOUND \||HW \|"
```

---

## 14. Exception ve Hata Yönetimi Stratejisi

Her katmandaki hata, §4.8'deki error event'lerinden biriyle state machine'e iletilir. Bu bölüm hangi hata senaryosunun hangi event'i ürettiğini ve Flutter'ın nasıl tepki verdiğini katman katman belirtir.

---

### 14.1 HTTP Katmanı

| Senaryo | HTTP Kodu | Flutter Event | State Geçişi |
|---|---|---|---|
| Callee meşgul | 409 (USER_BUSY) | `error_busy_callee` | `dialing → ended` |
| Caller zaten aramada | 423 (CALLER_BUSY) | `error_busy_caller` | `dialing → ended` |
| Call bulunamadı | 404 | `error_call_not_found` | `connecting → ended` |
| Server hatası | 5xx | `api_start_error` | `dialing → ended` |
| Network timeout | — | `network_lost` | State'e göre §5 |

**Retry politikası:**
- `/calls/accept`: maksimum 4 deneme (network jitter toleransı).
- Diğer tüm POST'lar: tek deneme + hata event'i üretilir.
- `checkActiveCall()`: hata non-fatal — sessizce başarısız olur, `idle` kalır.

---

### 14.2 LiveKit Katmanı

| Senaryo | LK Event | Flutter Event | State Geçişi |
|---|---|---|---|
| `room.connect()` başarısız | — | `lk_connect_failed` | `connecting → ended` |
| Geçici kopukluk | `onReconnecting` | `lk_reconnecting` | `active → reconnecting` |
| Reconnect başarılı | `onReconnected` | `lk_reconnected` | `reconnecting → active` |
| Kalıcı disconnect | `onDisconnected` | `lk_disconnected` | `reconnecting → ended` |
| Peer bağlanmadı (40s) | — | `timer_peer_expired` | `reconnecting → ended` |

> **iOS `room.connect()` yan etkisi:** LiveKit dahili olarak AVAudioSession'ı `soloAmbient`'e çeker → ringback durur. Çözüm: `room.connect()` sonrası `playAndRecord/voiceChat` yeniden configure + ringback resume. Bkz. §6.1.

---

### 14.3 Push Katmanı

| Senaryo | Davranış |
|---|---|
| APNs stale token | Backend APNs hatasını yakalar → `voip_token = NULL` |
| FCM invalid token | Backend `messaging/invalid-registration-token` → `fcm_token = NULL` |
| Her iki token null + WS offline | Arama callee'ye ulaşmaz — backend loglar, sessiz kayıp |
| VoIP push + WS eventi yarışı | Dedup: zaten `ringing`'deyse ikinci kaynak yoksayılır |
| VoIP payload boş token/url | Flutter proaktif `/calls/active` fetch başlatır |

---

### 14.4 Flutter Hata Sınıflandırması

**Fatal — `ended` geçişi tetiklenir:**
- Mikrofon izni reddedildi — caller: `idle → permissionDenied` (arama hiç başlamaz); callee `denied`: `ringing → ended` (kullanıcı OS dialog'unda reddetmiş)
- Mikrofon kalıcı reddedildi — callee `permanentlyDenied`: state `ringing` kalır, modal gösterilir (§15.3); `ended` geçişi kullanıcı [İptal] taptığında veya ring timer dolunca gerçekleşir
- `/calls/start` 4xx / 5xx yanıtı
- `/calls/accept` 404 (race condition — §11.3)
- LiveKit kalıcı disconnect (retry sonrası)
- Connecting timeout (15s)

**Non-fatal — arama devam eder ya da `idle` kalır:**
- `checkActiveCall()` exception → sessiz fail, `idle` kalır
- Elapsed sync başarısız → timer 0'dan başlar
- Avatar yüklenemedi → baş harf fallback
- `accepted_at` parse hatası → local clock kullanılır
- Callee pre-connect (`_fetchCalleeToken`) hatası → `/accept` response token'ı fallback

---

## 15. Hardware İzin Politikası

Arama akışındaki her hardware izninin ne zaman, nasıl ve hangi sonuçla kontrol edileceği. Bu kararlar `CallHardwareAdapter` (Step 5) tarafından implemente edilir; state machine bu detayları görmez.

---

### 15.1 İzin Hiyerarşisi

| İzin | Kritiklik | Gerekçe |
|---|---|---|
| **Mikrofon** | Call-blocking | Ses olmadan anlamlı arama olmaz |
| **Kamera** | Non-blocking | Arama her zaman sesli başlar; kamera isteğe bağlı |
| **Bluetooth** (Android 31+) | Non-blocking | Sadece ses yönlendirmeyi etkiler, aramayı engellemez |

---

### 15.2 Mikrofon İzni

#### Caller yolu

| Adım | Detay |
|---|---|
| Kontrol noktası | `startCall()` — `dialing` state'e girmeden önce |
| Yöntem | `Permission.microphone.request()` — OS dialog gösterir (ilk defa veya tekrar sorulabilirse) |
| `granted` | Normal devam: `idle → dialing` |
| `denied` (kalıcı değil) | `idle → permissionDenied`; kısa hata mesajı; bir sonraki denemede dialog tekrar çıkabilir |
| `permanentlyDenied` | `idle → permissionDenied`, `permPermanentlyDenied=true`; in-app modal: "Mikrofon erişimi Ayarlar'dan verilmeli" + [Ayarlar'a Git] butonu |

#### Callee yolu

| Adım | Detay |
|---|---|
| Kontrol noktası | `acceptCall()` — `connecting` state'e girmeden önce |
| Yöntem | `Permission.microphone.request()` — "Accept" sonrası OS dialog normal UX |
| `granted` | Normal devam: `ringing → connecting` |
| `denied` (kalıcı değil) | `ringing → ended`; kullanıcı OS dialog'unda reddetmiş demektir |
| `permanentlyDenied` | State `ringing` kalır; in-app modal: "Mikrofon erişimi Ayarlar'dan verilmeli" + [Ayarlar'a Git] + [İptal] |

> **`permanentlyDenied` — neden arama hemen bitmez:**  
> Kullanıcı "Kabul Et" taptıktan sonra Ayarlar'dan izin verip geri dönebilir. Caller'ın 30s ring timer'ı içindeyse arama hâlâ `calling` durumunda olabilir. Geri dönüşte `/calls/active` sonucuna göre devam edilir veya sonlandırılır.

---

### 15.3 Kalıcı Reddedilmiş Mic — Callee Ayarlar Dönüş Akışı

```
Kullanıcı "Kabul Et" taptı
    │
    ├── mic permanently denied
    │       │
    │       ▼
    │   State: ringing (değişmez)
    │   Modal: "Mikrofon izni gerekli" + [Ayarlar'a Git] [İptal]
    │       │                                   │
    │       │ [İptal]                  [Ayarlar'a Git]
    │       ▼                                   │
    │   ringing → ended                  iOS/Android Ayarlar açılır
    │                                  app_background → ringing kalır
    │                                           │
    │                               Kullanıcı izin verir → geri döner
    │                                           │
    │                                   app_foreground
    │                                   WS reconnect → /calls/active
    │                                           │
    │                          ┌────────────────┴────────────────┐
    │                    call aktif                         call bitti
    │                 (status=calling)              (missed/ended — timer doldu)
    │                          │                               │
    │                  ringing hâlâ gösterilir          ringing → ended
    │                  Kullanıcı Accept'e tekrar
    │                  basabilir → normal devam
```

---

### 15.4 Kamera İzni

Kamera **hiçbir zaman** call state'i değiştirmez. Aramanın sesli devam etmesi esastır.

| Kontrol noktası | `active` state'de kamera toggle anı |
|---|---|
| `notDetermined` | `Permission.camera.request()` göster; `granted` → `setCameraEnabled(true)` |
| `granted` | Doğrudan `setCameraEnabled(true)` |
| `denied` | Toast: "Kamera erişimi reddedildi"; arama sesli devam eder |
| `permanentlyDenied` | Toast + [Ayarlar'a Git] linki; arama sesli devam eder |

**Kamera asla call-blocking değildir.** Şu an veya gelecekte yalnızca ses + isteğe bağlı video modeli geçerlidir.

---

### 15.5 Bluetooth (Android API 31+)

Arama akışının dışında — app startup sorumluluğu.

| Durum | Davranış |
|---|---|
| `granted` | Bluetooth headset routing otomatik çalışır |
| `denied` / `permanentlyDenied` | Headset routing çalışmaz; arama speaker/earpiece'ten devam eder |

`AVAudioSession` (iOS) Bluetooth'u `allowBluetooth | allowBluetoothA2dp` seçenekleriyle yönetir — iOS'ta ayrıca izin istenmez. Bu kural yalnızca Android API 31+ için geçerlidir.

---

### 15.6 Platform Farkları

| Konu | iOS | Android |
|---|---|---|
| Kalıcı red tespiti | `PermissionStatus.permanentlyDenied` | `shouldShowRequestPermissionRationale = false` |
| Bluetooth izni | Gerekmez — AVAudioSession yönetir | API 31+: `BLUETOOTH_CONNECT` gerekir |
| Mic dialog zamanlaması | `.request()` VoIP push callback'inde de çalışır | `.request()` normal Activity context gerektirir |
| iOS VoIP push + mic denied | `reportNewIncomingCall` çalışır; accept'te mic check | — |
| Android FCM push + mic denied | — | Bildirim gelir; accept'te mic check |

---

### 15.7 `permPermanentlyDenied` State Flag'i

`CallState.permPermanentlyDenied` alanı UI'a iki farklı davranış göstermesini sağlar:

| `permPermanentlyDenied` | UI Davranışı |
|---|---|
| `false` | "Mikrofon izni reddedildi" — kısa hata mesajı; sonraki aramada OS tekrar sorabilir |
| `true` | "Mikrofon izni Ayarlar'dan verilmeli" + [Ayarlar'a Git] butonu |

---

## 16. Resource Management

Bir arama herhangi bir nedenle sonlandığında — normal kapanma, red, timeout, hata, crash —
tüm sistem kaynaklarının doğru sırada ve doğru zamanda serbest bırakılması gerekir.
Bu bölüm her resource için **ne zaman**, **nasıl** ve **hangi koşulda** temizleneceğini tanımlar.

---

### 16.1 Üç Faz Modeli

Cleanup üç fazda gerçekleşir. Her faz bir state'e karşılık gelir.

```
ended state'e giriş
      │
      ▼
 ┌─────────────────────────────────┐
 │  FAZ 1 — Anında (0ms)           │  Medya durdur, LK kes, platform bildir
 └─────────────────────────────────┘
      │
      ▼
 ┌─────────────────────────────────┐
 │  FAZ 2 — 2s Window              │  Son tonu çal, end UI göster
 └─────────────────────────────────┘
      │  timer_reset_ready
      ▼
 ┌─────────────────────────────────┐
 │  FAZ 3 — idle girişinde         │  Audio session kapat, state temizle
 └─────────────────────────────────┘
```

---

### 16.2 Faz 1 — Anında (`ended` state'e girerken)

Sıra önemlidir. Aşağıdaki operasyonlar `_setState(ended)` çağrısı sırasında, state observer'lar uyarılmadan önce gerçekleşir.

#### 16.2.1 Tüm Timer'ları İptal Et

| Timer | Aksiyon |
|---|---|
| `timer_ring_expired` (30s / 45s) | İptal |
| `timer_connecting_exp` (15s) | İptal |
| `timer_peer_expired` (10s / 40s) | İptal |
| `timer_reset_ready` (2s) | Başlat ← bu faza ait tek başlatma |

`timer_reset_ready` dışındaki tüm timer'lar iptal edilir. İptal idempotent'tir — zaten iptal edilmiş timer'ı tekrar iptal etmek hatasızdır.

#### 16.2.2 Kamera Kapat

```dart
if (_cameraEnabled) {
  room.localParticipant?.setCameraEnabled(false);
  _cameraEnabled = false;
}
```

Koşullu: kamera hiç açılmamışsa no-op. LK `room.disconnect()`'tan **önce** çağrılır — disconnect tüm track'leri kapatır ancak biz kullanıcıya kamera göstergesinin anında kapandığını hissettirmek isteriz.

#### 16.2.3 LiveKit Disconnect — Fire-and-Forget

```dart
_room?.disconnect();   // await edilmez
_room = null;
```

State, LK disconnect'i beklemez. LK SDK kendi cleanup'ını yapar; server-side participant ~30s sonra timeout'a düşer. `_room` referansı hemen null'lanır — bellek serbest bırakılır.

#### 16.2.4 Backend Bildir — Fire-and-Forget

```dart
if (_callId != null && !_endReported) {
  _endReported = true;
  _repository.endCall(_callId!).ignore();   // await edilmez
}
```

`_endReported` flag'i ile çift /end isteği engellenir. Önceden gönderilmişse (örn. `user_call_end` zaten POST /end'i tetiklediyse) no-op.

#### 16.2.5 Platform Bildir

**iOS:**
```dart
provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded);
// EndReason'a göre reason seçilir — bkz. §16.6
```

CallKit `provider.reportCall(ended:)` çağrısı iOS için kritiktir. Yapılmazsa:
- Sonraki aramada CallKit duplicate call uyarısı verebilir
- Pil tüketimi artar (aktif call sayıldığı için)
- 30s içinde yapılmadıysa iOS kendi sonlandırır → düzensiz cleanup

**Android:**
```dart
FlutterCallkitIncoming.endCall(uuid);
// veya: FlutterCallkitIncoming.endAllCalls();
```

`endCall` idempotent'tir — zaten kapatılmış aramayı tekrar kapatmak hatasızdır.

**Koşul:** `_callkitReported` flag ile: `reportNewIncomingCall` hiç çağrılmadıysa (örn. caller tarafında ya da WS ile gelen ringing'de CallKit raporlanmadıysa) bu çağrı atlanır.

---

### 16.3 Faz 2 — 2s Window (`ended` state'inde)

`ended` state'ine girildiğinde kullanıcıya son geribildirim verilir. Ekran bu pencerede açık kalır.

#### 16.3.1 Son Ses — EndReason'a Göre

| EndReason | Ses | Kanal |
|---|---|---|
| `normal` | ended.wav | Earpiece |
| `rejected` | busy.wav | Earpiece |
| `missed` | Sessiz | — |
| `noAnswer` | Sessiz | — |
| `busy` | busy.wav | Earpiece |
| `permissionDenied` | Sessiz | — |
| `error` | Sessiz | — |

Ses dosyası zaten çalıyorsa (ringback aktifse) önce durdurulur, ardından son ses başlatılır.

**Süre garantisi:** ended.wav ve busy.wav 2s'den kısa olmalıdır. `timer_reset_ready` (2s) her iki dosyadan da sonra tetiklenir — 2s window bittiğinde ses de biter.

#### 16.3.2 UI

- `CallScreen` `ended` state'ini gösterir (süre, EndReason)
- Auto-pop: 2s sonra `timer_reset_ready → idle` → `idle` geçişinde dismiss
- **Wakelock korunur** — 2s window boyunca ekran açık kalır

---

### 16.4 Faz 3 — Ertelenen (`idle` state'e girerken)

`timer_reset_ready` tetiklenip `ended → idle` geçişi yapıldığında:

#### 16.4.1 Audio Session Kapat

**iOS:**
```dart
try {
  AVAudioSession.sharedInstance().setActive(false,
    options: .notifyOthersOnDeactivation);
} catch { /* hata yoksayılır — session zaten kapalı olabilir */ }
```

`notifyOthersOnDeactivation`: müzik uygulamaları aramanın bittiğini anlayıp audio'yu devralabilir (endüstri standardı).

**Android:**
```dart
audioManager.abandonAudioFocus(_audioFocusChangeListener);
```

#### 16.4.2 Wakelock Bırak

**Android:**
```dart
if (_wakeLock?.isHeld == true) {
  _wakeLock!.release();
}
```

iOS'ta wakelock yönetimi AVAudioSession tarafından yapılır — ayrıca release gerekmez.

#### 16.4.3 State Temizle

```dart
_callId         = null;
_roomName       = null;
_token          = null;
_currentRole    = null;
_endReported    = false;
_callkitReported = false;
_cameraEnabled  = false;
// endReason: CallScreen zaten dismiss edildi; null'lanabilir
```

`_calleeUuid`, `_otherUser` gibi UI'a ait alanlar da bu noktada sıfırlanır.

---

### 16.5 Wakelock Yaşam Döngüsü

| State | Wakelock | Gerekçe |
|---|---|---|
| `idle` → `dialing` | — | Henüz ses yok |
| `dialing` → `waiting` | — | Ringback earpiece'ten, ekranı açık tutmak gerekmiyor |
| `ringing` | — | Sistem zili + ekran zaten açılır (push/CallKit) |
| `connecting` → `active` | **Acquire** | Ses akışı başlar, ekran kapanmamalı |
| `active` | Devam | — |
| `reconnecting` | Devam | Bağlantı koptu ama arama hâlâ teknik olarak aktif |
| `ended` | Devam | 2s window — ekran açık kalmalı |
| `idle` | **Release** | Cleanup tamamlandı |

**Android implementation:** `PowerManager.PARTIAL_WAKE_LOCK` — CPU'yu uyandırır, ekranı açık tutmaz. Ekran `active` state'de kullanıcı etkileşimiyle açıksa `FLAG_KEEP_SCREEN_ON` (WindowManager flag) kullanılır. `FULL_WAKE_LOCK` deprecated, kullanılmaz.

---

### 16.6 iOS CallKit EndReason Eşlemesi

`provider.reportCall(with:endedAt:reason:)` için reason seçimi:

| EndReason | CXCallEndedReason |
|---|---|
| `normal` | `.remoteEnded` (karşı taraf kapattı) veya `.answeredElsewhere` (local bitiş) |
| `rejected` | `.declinedElsewhere` (callee reddetti) |
| `missed` / `noAnswer` | `.unanswered` |
| `busy` | `.failed` |
| `permissionDenied` | `.failed` |
| `error` | `.failed` |

**`normal` için caller/callee farkı:**
- Caller local hangup: `local_call_end → .answeredElsewhere` veya sadece `provider.reportCall` çağrısı yapılmaz (CXEndCallAction zaten tetiklemiştir)
- Callee tarafı bitiriş (`ws_call_ended`): `.remoteEnded`

---

### 16.7 Duplicate Trigger İdempotency

Birden fazla `ended` tetikleyici aynı anda gelebilir (örn. `user_call_end` + `ws_call_ended`).

**Guard mekanizması: state machine.**

State machine `ended → ended` self-transition'ına izin verir (§5.8: "geç gelen event'ler yoksayılır"). İkinci trigger `ended` state'indeyken gelirse `_setState` çağrılmaz — cleanup tekrar çalışmaz.

Tüm cleanup operasyonları ek olarak idempotent yazılır:
- `_endReported` flag → çift /end isteği engeller
- `_callkitReported` flag → çift `reportCall` engeller
- `_cameraEnabled` flag → çift `setCameraEnabled(false)` engeller
- LK `room.disconnect()` → zaten null ise no-op
- Timer cancel → zaten iptal ise no-op

**Ek guard gerekmez.** State machine + idempotent operasyonlar yeterlidir.

---

### 16.8 Kısmi Başlatma Senaryoları

Her resource yalnızca acquire edildiyse release edilir.

| Senaryo | LK disconnect | /end | CallKit reportCall | Wakelock |
|---|---|---|---|---|
| `idle → permissionDenied → ended` | Hayır (LK hiç bağlanmadı) | Hayır (callId yok) | Hayır (CallKit raporlanmadı) | Hayır |
| `dialing → ended` (/start 4xx) | Hayır | Hayır (callId yok) | Hayır | Hayır |
| `waiting → ended` (caller cancel) | Evet (pre-connect yapılmış olabilir) | Evet | Hayır (caller) | Hayır |
| `ringing → ended` (callee reject) | Hayır | Evet | Evet (iOS CallKit raporlanmıştı) | Hayır |
| `connecting → ended` | Evet | Evet | Evet | Evet |
| `active → ended` | Evet | Evet | Evet | Evet |

---

### 16.9 Crash Senaryosu — Resource Durumu

| Resource | Crash'ta ne olur | Recovery |
|---|---|---|
| AVAudioSession | OS process sonunda release eder | Sonraki app açılışında clean |
| AudioFocus | Android OS 200ms-2s içinde abandon eder | Sistem halleder |
| Wakelock | Process ölünce OS release eder | Otomatik |
| Kamera | OS process kapatınca release eder | Otomatik |
| LiveKit room | Participant timeout (~30s) → server-side disconnect | LK server halleder |
| iOS CallKit UI | Stuck call gösterebilir | `call_cancelled`/`call_ended` VoIP push → AppDelegate `saveEndCall(uuid, .remoteEnded)` (§12.5) |
| Android bildirim | Stuck notification | `call_cancelled` FCM push → `hideCallkitIncoming` (§12.5) |
| DB call record | `calling`/`active` kalır | Teqlif-spesifik soru — bkz. §16.10 |

---

### 16.10 Backend Ghost Call Cleanup — Spec

Uygulama çökmesi, sunucu yeniden başlatma veya ağ kesintisi nedeniyle `/end` hiç POST edilemediğinde DB'de `calling`/`active` kayıtlar kalabilir. Bu kayıtların periyodik olarak tespit edilip kapatılması gerekir.

---

#### Tasarım Kararları

**Kural 1 — İki ayrı eşik, iki farklı gerekçe:**

`calling` kaydı için eşik:

```
eşik = max_ring_timeout + güvenlik_tamponu
     = 45s (D-2: callee fallback) + ~4.5 dakika tampon
     = 5 dakika
```

Normal akışta `delayed_call_timeout_task` (per-call ARQ task) 40s'de `missed` yapar — bu birincil mekanizmadır. Ghost cleanup ikincil güvenlik ağıdır: ARQ task'ı kaçırırsa (worker restart, Redis hatası) en geç **5 dakika** sonra kayıt kapanır.

`active` kaydı için eşik:

```
primary signal  : LK room artık yok (otoriter — oda gidince arama da bitmiş)
secondary guard : started_at > 1 saat (LK API geçici hatasında gerçek aramayı kapatmamak için)
```

LK API erişilemezse `active` kayıtlara dokunulmaz — kör temizlik yapmaktansa beklemek tercih edilir.

**Kural 2 — Her cleanup 5 aksiyonu içerir:**

| # | Aksiyon | Gerekçe |
|---|---|---|
| 1 | `status` güncelle (`missed` / `ended`) | DB tutarlılığı |
| 2 | `ended_at = now` | Süre hesabı ve raporlama |
| 3 | WS eventi her iki tarafa | Açık uygulamalar state güncellesin |
| 4 | LK odayı sil | Sunucu kaynağı serbest bırak |
| 5 | `clear_call_redis(call_id)` | Redis participant key temizle |

**Kural 3 — WS eventi hem caller hem callee'ye:**
- `calling → missed` → `{"type": "call_missed"}`
- `active → ended` → `{"type": "call_ended"}`

Kullanıcı uygulamayı açık tutuyorsa bu eventi alır → `ws_call_missed` / `ws_call_ended` → normal state transition.

**Kural 4 — Çalışma sıklığı: 15 dakika yeterlidir.**
Normalin 20× üstünde — ghost'lar 5 dakikalık eşiği aştıktan sonra en fazla bir 15 dakika daha bekler (toplam ~20 dakika worst-case).

---

#### Flutter Crash Recovery Penceresi

| Crash sonrası süre | DB durumu | Flutter davranışı |
|---|---|---|
| < 5 dakika | `calling`/`active` hâlâ var | `/calls/active` → recovery başlatılır (§11.4) |
| 5–20 dakika | Ghost task henüz çalışmamış olabilir | Recovery dener; başarısızsa `ended` |
| > 20 dakika | Ghost task çalışmış → `missed`/`ended` | `/calls/active: null` → `idle` |

Flutter tarafında ek stale cleanup mekanizmasına gerek yoktur.

---

#### Mevcut Uygulama Değerlendirmesi

`cleanup_ghost_calls_task` (ARQ cron, her 15 dk — `app/worker.py`):

| Kural | Durum | Not |
|---|---|---|
| `calling` 5 dakika eşiği | ✅ | `calling_threshold = now - timedelta(minutes=5)` |
| `active` 1 saat + LK room check | ✅ | `active_threshold = now - timedelta(hours=1)` + `lk_rooms` kontrolü |
| LK API hatasında aktif aramalara dokunmama | ✅ | `if lk_rooms is None: continue` |
| `ended_at` set etme | ✅ | Önceki bug düzeltilmiş |
| WS bildirimi her iki tarafa | ✅ | `call_missed` ve `call_ended` publish ediliyor |
| LK odayı sil | ✅ | `DeleteRoomRequest` çağrılıyor |
| `clear_call_redis(call_id)` | ❌ **EKSİK** | Ghost task Redis participant key'i temizlemiyor; `call:{id}:participants` 3h TTL'ine kadar stale kalabilir |

**Gerekli backend fix:** `cleanup_ghost_calls_task` içinde her temizlenen call için `clear_call_redis(call.id)` çağrısı eklenmeli.

---

## Sonraki Adımlar

- [x] **Bölüm 1** — Tasarım kararları (axioms)
- [x] **Bölüm 2** — Üç boyutlu model
- [x] **Bölüm 3** — State listesi + cross-cutting event kuralları
- [x] **Bölüm 4** — Event kataloğu
- [x] **Bölüm 5** — Transition tablosu (api_accept_error + lk_peer_joined + callkit_ended eklendi)
- [x] **Bölüm 6** — Platform side effect'leri (iOS + Android adapter)
- [x] **Bölüm 7** — Call related UI routing
- [x] **Bölüm 8** — Modül mimarisi ve sorumluluk sınırları
- [x] **Bölüm 9** — API / DB / Redis katmanı (DB lifecycle düzeltildi; recovery tablosu + Flutter-only state'ler eklendi)
- [x] **Bölüm 10** — V1.0 use case → V2.0 eşlemesi
- [x] **Bölüm 11** — Anahtar akış sekansları (5 kritik akış)
- [x] **Bölüm 12** — CallNotifAdapter spesifikasyonu
- [x] **Bölüm 13** — Log katmanı (format, phase tag'leri, kurallar)
- [x] **Bölüm 14** — Exception ve hata yönetimi stratejisi
- [x] **Bölüm 15** — Hardware izin politikası (mic/kamera/Bluetooth — caller+callee, platform farkları, kalıcı red akışı)
- [x] **Bölüm 16** — Resource management (3 faz modeli, timer/LK/audio/wakelock/kamera/crash cleanup, idempotency, iOS CallKit reason eşlemesi, backend ghost call cron §16.10)
