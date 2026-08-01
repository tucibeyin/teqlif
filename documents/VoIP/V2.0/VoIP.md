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

## Sonraki Adımlar

Aşağıdaki bölümler sıradaki oturumlarda tamamlanacak:

- [ ] **Bölüm 5** — Tam transition tablosu (her state × her event × her role)
- [ ] **Bölüm 6** — Platform side effect'leri (iOS adapter / Android adapter)
- [ ] **Bölüm 7** — Screen routing tablosu (CallScreenRouter kararları)
- [ ] **Bölüm 8** — Modül mimarisi ve sorumluluk sınırları
- [ ] **Bölüm 9** — V1.0 use case'lerinin V2.0 state machine'e eşlemesi
