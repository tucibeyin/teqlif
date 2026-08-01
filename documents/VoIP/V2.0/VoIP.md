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

---

## 4. Cross-Cutting Events

Bu event'ler herhangi bir state'te gelebilir. Her state için davranışı aşağıdaki tablolarda tanımlanacaktır (bkz. Bölüm 5).

| Event               | Kaynak                              |
|---------------------|-------------------------------------|
| `network_lost`      | Sistem (iOS/Android connectivity)   |
| `network_restored`  | Sistem                              |
| `app_background`    | Kullanıcı (home/swipe)              |
| `app_foreground`    | Kullanıcı (geri dönüş)              |
| `app_crash`         | Sistem (OOM, exception)             |
| `app_launch`        | Kullanıcı (crash sonrası yeniden aç)|

### Network kaybında genel kural:
- **WS:** Hemen kapanır, `mark_dm_offline` → Redis temizlenir
- **LiveKit:** Kendi reconnect mekanizması devreye girer
- **Pending state:** `network_restored` event'inde `/calls/active` ile state restore

### Crash/launch'da genel kural:
- App açılışında `/calls/active` sorgulanır
- Aktif çağrı varsa → ilgili role'e göre state restore
- Aktif çağrı yoksa → `idle`

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
| `network_lost` | callee | `ringing` | Native screen devam eder (CallKit) |
| `ws_connected` | callee | `ringing` | /active → hâlâ calling: burada kal |
| `app_background` | callee | `ringing` | Native screen yönetir |
| diğer | callee | `ringing` | Yoksay |

---

### 5.5 `connecting` (both)

Callee kabul etti. LiveKit bağlantısı ve ses aktivasyonu sürüyor.

| Event | Role | Yeni State | Not |
|---|---|---|---|
| `lk_connect_ok` | both | `active` | Bağlantı kuruldu |
| `audio_session_active` | callee | `active` | iOS — CallKit audio session aktif |
| `audio_focus_gained` | callee | `active` | Android — AudioFocus alındı |
| `timer_connecting_exp` | both | `ended` | 15s doldu, takıldı |
| `lk_connect_failed` | both | `ended` | Bağlantı kurulamadı |
| `error_lk_permanent` | both | `ended` | LiveKit tamamen vazgeçti |
| `user_call_end` | both | `ended` | Connecting'de kullanıcı kesti |
| `ws_call_ended` | both | `ended` | Karşı taraf connecting'de kesti |
| `network_lost` | both | `ended` | Connecting'de ağ kesilirse retry yok |
| diğer | both | `connecting` | Yoksay |

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

## Sonraki Adımlar

Aşağıdaki bölümler sıradaki oturumlarda tamamlanacak:

- [x] **Bölüm 4** — Event kataloğu
- [x] **Bölüm 5** — Transition tablosu
- [ ] **Bölüm 6** — Platform side effect'leri (iOS adapter / Android adapter)
- [ ] **Bölüm 7** — Screen routing tablosu (CallScreenRouter kararları)
- [ ] **Bölüm 8** — Modül mimarisi ve sorumluluk sınırları
- [ ] **Bölüm 9** — V1.0 use case'lerinin V2.0 state machine'e eşlemesi
