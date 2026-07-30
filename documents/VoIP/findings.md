# VoIP Bulgular

> Analiz tarihi: 2026-07-30  
> Öncelik: P0 = acil/bloke edici, P1 = ciddi/kullanıcıya görünür, P2 = orta, P3 = düşük

---

## P0 — Kritik

### F1: iOS Arayanında Ringback Sessizliğe Düşüyor (Callee Hızlı Kabul Ederse)

**Konum:** `call_service.dart` ~line 1484  
**Senaryo:**
1. iOS arayan `room.connect()` başlatır → AVAudioSession SoloAmbient'e çekilir → ringback kesilir
2. Callee, `room.connect()` tamamlanmadan kabul eder → `call_accepted` WS → status = `connecting`
3. Geri yükleme bloğu `if (status == calling)` kontrolü yapar → `connecting` olduğu için ATLANIR
4. Ringback hiç devam etmez; arayan, callee'nin sesi gelene kadar sessizlik duyar

**Etki:** Kullanıcı deneyimi ciddi biçimde bozulur: arayan, karşı tarafın cevap verdiğini anlayamaz; sohbet başladığında birden ses gelir.

**Kök neden:** `connecting` durumunda ringback restore edilmiyor çünkü restore mantığı yalnızca `calling` durumunu kontrol ediyor.

---

### F2: iOS Arayanında Callee Sesi Duyulurken Arayan Mic 1.65 Saniye Aktif Olmayabilir

**Konum:** `call_service.dart` ~line 1699 (P0 FIX yorumu)  
**Senaryo:**
1. `TrackSubscribedEvent` (callee audio) → status = `connected` → ringback durur → caller mic `setMicrophoneEnabled(true)` çağrılır
2. `call_accepted` WS bu olaydan ~1.65 saniye sonra gelir

**Etki:** Caller callee'yi duyarken callee, caller'ı ~birkaç yüz ms–1.65s duyamaz. Kuantuma bağlı; bazı çağrılarda kayda değer.

**Not:** WS gecikme nedeni araştırılmamış; backend'den ölçüm logu yok.

---

## P1 — Ciddi

### F3: `connecting` Durumunda `TrackSubscribed` Muted Track ile `connected`'a Geçiş

**Konum:** `call_service.dart` ~line 1688  
**Senaryo:**
- `TrackSubscribedEvent` (audio, connecting state) → `connected` set edilir
- Ama subscription olayı track henüz muted iken de gelebilir (Android caller muted pre-publish → callee connecting iken subscribe oluyor)
- Gerçek ses henüz akmıyor, ringback durdu, ekran "bağlandı" gösteriyor

**Mevcut koruma:** Android caller pre-publish track için `TrackUnmutedEvent` (line 1744) ayrı olarak işleniyor. Ancak callee tarafı için `TrackSubscribed` yeterli güvenceyi vermiyor; `isMuted` kontrolü yok.

**Etki:** Kısa bir "sessiz bağlanma" hissi; callee konuşmaya başlamadan önce arayan "bağlandı" sanır.

---

### F4: Android Arayanında Muted Pre-Publish Audio Focus Çakışması

**Konum:** `call_service.dart` ~line 1462  
**Senaryo:**
1. Android caller `room.connect()` + `setMicrophoneEnabled(true)` + `pub.mute()` yapar
2. WebRTC audio stack, `AudioManager.STREAM_VOICE_CALL` için audio focus talep eder
3. `audioplayers` ringback `AudioManager.STREAM_MUSIC` üzerinde çalıyor
4. Android OS, voice call focus gelince müzik stream'ini duck eder veya keser
5. Ringback sessizleşir ya da kaybolur

**Mevcut varsayım** (line 1454 yorum): "Android'de audio focus sistemi farklı çalıştığı için sorun yaratmaz" — bu varsayım yanlış olabilir.

**Etki:** Android arayanında ringback kesilir; F1 ile aynı kullanıcı deneyimi bozukluğu.

---

### F5: `peerAlreadyJoined + anyAudioSubscribed` Doğrudan `connected`'a Atlayabilir

**Konum:** `call_service.dart` ~line 1558  
**Senaryo:**
- Caller room.connect() tamamlandığında callee çoktan odadaydı ve audio subscribe edilmişti
- `connected` state direkt set edilir; `connecting` aşaması atlanır
- `onCallAccepted()` henüz gelmemişse `acceptedAt` NULL kalabilir → süre ölçümü bozulur

**Etki:** Arama süresi logu yanlış; `_startElapsedTimer()` doğru zamanla başlamayabilir.

---

### F6: WS `call_accepted` Backend Tarafından Geç Gönderiliyor

**Bulgular:**
- iOS caller tarafında `TrackSubscribedEvent`, `call_accepted` WS'inden ~1.65 saniye **önce** geliyor (line 1701 yorum)
- Bu, callee'nin LiveKit pre-connect'i tamamlayıp backend'e kabul bildirdiği süre ile WS iletim gecikmesinin toplamı
- Backend, `POST /calls/{id}/accept` sonrasında WS gönderirken LiveKit event'leri daha hızlı yayılıyor

**Etki:** F2 ile iç içe; WS gecikme kaynağı tespit edilmemiş. Backend'de arama kabul logu yok.

---

### F7: `livekit_url` Tutarsızlığı

**Konum:** `backend/app/config.py` line 19, test logları  
**Detay:**
- Config: `livekit_url = "wss://teqlif.com/rtc"` (nginx proxy)
- Test loglarında WS üzerinden gelen `livekit_url` değeri: `wss://live.teqlif.com` (doğrudan sunucu)
- VoIP payload: `livekit_url` config'den alınır → `wss://teqlif.com/rtc`
- Bu iki URL farklı; WS kanalından gelen aramayla VoIP push kanalından gelen arama farklı LK endpoint'e bağlanır

**Etki:** WS yoluyla gelen çağrılarda callee farklı LK URL'sine bağlanabilir; bağlantı kurulursa sorun yok ama tutarsızlık hata izlemeyi güçleştirir.

---

## P2 — Orta

### F8: `call_ended_sent` NX Lock 60 Saniye Sonra Sona Eriyor

**Konum:** `call_redis.py`  
**Senaryo:** `end_call` iki kez tetiklenirse (timeout worker + manual end) ve aralarında >60 saniye geçmişse, ikinci `call_ended` WS de gönderilir.  
**Etki:** Nadir; sadece 60+ saniye gecikmeli çift-end senaryosunda sorun.

---

### F9: `clear_call_redis()` Tutarsız Çağrılıyor

**Konum:** `calls.py` end/reject/timeout yolları  
**Detay:** Redis key temizleme (`call_redis.clear_call_redis()`) bazı kod yollarında atlanabiliyor. `call:{id}:participants` SET 3 saat TTL ile kendiliğinden temizleniyor ama `invite` ve `ended` lock'ları geride kalabilir.  
**Etki:** Redis hafıza baskısı düşük; ancak yeniden arama senaryosunda eski lock aktif kalabilir.

---

### F10: Backend Gerçek "Audio Aktif" Anını Bilmiyor

**Detay:** Backend, `accepted_at` kaydeder ama iki tarafın gerçekten ses alışverişi başladığı anı (`connected` state) bilmiyor. `duration_seconds` hesaplaması `accepted_at → ended_at` üzerinden yapılıyor.  
**Etki:** Kısa bir ses gecikmesi (F1, F2) süre ölçümüne dahil oluyor; billing/analitik amaçlar için aşım anlamında önemsiz ama ince bir tutarsızlık.

---

### F11: iOS CallKit Otomatik Kapanıyor — Uygulama Ön Planda İken

**Konum:** `AppDelegate.swift` `appIsActive` guard  
**Detay:** Uygulama ön plandayken VoIP push gelirse `CXEndCallAction` ile CallKit otomatik kapatılıyor. Bu, ön plan aramasını WS'e bırakmak için kasıtlı bir tasarım; ancak WS gecikmeli gelirse kısa süreliğine boş ekrana düşülüyor.  
**Etki:** Düşük; ön planda WS akışı hızlı çalışırsa sorun yok.

---

### F12: Token Süresi 4 Saat — Reconnect Senaryosunda Risk

**Konum:** `calls.py` token üretimi  
**Detay:** `callee_token` üretim anından itibaren 4 saat geçerli. Uzun aramalar veya bağlantı kesintisi sonrası token yenileme mekanizması yok.  
**Etki:** >4 saat arama teorik olarak token invalidation yaşayabilir; pratikte düşük risk.

---

### F13: `invite_timeout` (30s) ile `delayed_call_timeout` (60s) Arası Boşluk

**Konum:** `worker.py`  
**Detay:** 30–60 saniye arasında invite_timeout WS gönderilir ama DB hâlâ `calling`'dir. Bu sürede yeni bir çağrı başlatılabilir mi, mevcut call kaydı çakışır mı?  
**Etki:** Nadir edge case; kullanıcı arka arkaya hızlı arama yaparsa test edilmemiş.

---

## P3 — Düşük / UX / Temizlik

### F14: Caller `connecting` Durumunda UI "Arıyor" Yazıyor

**Konum:** `call_screen.dart`  
**Detay:** `calling` → `connecting` geçişinde ekran metnini değiştiren bir ayrım yok. Her iki durumda da "Arıyor" görünüyor.  
**Etki:** UX — kullanıcı kabul edildiğini anlamıyor; ringback F1 nedeniyle sessizse daha da kafa karışıklığı.

---

### F15: Arama Süresi Timer'ı `connected` Tetikleyicisine Göre Başlıyor — Tutarsız

**Konum:** `call_service.dart` `_startElapsedTimer()`  
**Detay:** Timer; `TrackSubscribed`, `TrackUnmuted` veya `peerAlreadyJoined` ile başlıyor. Üç farklı kod yolu var, `acceptedAt` assign'ı da karmaşık (`_acceptedAt` private field vs `state.acceptedAt`).  
**Etki:** Düşük; ama zaman ölçümü birden fazla path üzerinden geliyor — refactor fırsatı.

---

### F16: Ringback Player State'i `_handleStatusChange` Dışında da Değiştiriliyor

**Konum:** `call_service.dart` `stopRingtoneAndVibration()` direct calls  
**Detay:** Ringback durdurma hem `_handleStatusChange` içinde hem de `TrackSubscribedEvent` handler'ında çağrılıyor. Çift durdurma zararsız ama durum kontrolü merkezileşmemiş.  
**Etki:** Kodsal tutarsızlık; refactor fırsatı.

---

### F17: `CallStatus.reconnecting` Peer'a Bildirilmiyor

**Detay:** Bağlantı kopukluğu yaşansa bile karşı taraf "bağlandı" durumunda kalır. Sunucu tarafı katılım durumu (LiveKit participant event) backend'e iletilmiyor.  
**Etki:** UX — bir taraf ağ kaybı yaşarken diğeri ekranda süre sayacının ilerlediğini görür.
