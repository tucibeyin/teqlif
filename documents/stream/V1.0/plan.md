# LiveKit Canlı Yayın — V1.0 İyileştirme Planı

> **Oluşturulma:** 2026-09-05  
> **Hedef:** Self-hosted LiveKit SFU'yu VPS'te tutarken CPU yükünü minimuma indirmek; kalite kararını host'un ağ koşuluna bırakmak (BWE), simulcast kullanmamak.  
> **Mimari uyum:** `teqlif_architectural_decisions.md` — MVVM, StreamCommerceNotifier, cache taxonomy, handleError, OTA localization.

---

## 1. Mimari Gerçekler ve Kararlar

### 1.1 SFU'nun Değişmez Kısıtı

Self-hosted LiveKit SFU ile stream paketleri **her zaman VPS ağ arayüzünden geçer** — bu SFU mimarisinin matematiksel gerçeğidir:

```
Host → [VPS LiveKit SFU] → Viewer 1
                         → Viewer 2
                         → Viewer 3
```

"Stream VPS'ten geçmesin" hedefi yalnızca şu alternatiflerle mümkündür:

| Seçenek | Durum | Karar |
|---|---|---|
| LiveKit Cloud | Ücretli (~$0.005/katılımcı/dk) | ❌ Dışarıdan servis alınmayacak |
| Cloudflare Calls | Ucuz, CDN tabanlı SFU | ❌ Dışarıdan servis alınmayacak |
| CDN + HLS Egress | 10-30sn latency | ❌ UX için kabul edilemez |
| P2P WebRTC | Çok sayıda viewer için imkânsız | ❌ Teknik kısıt |

**Karar:** Self-hosted SFU'da kalınır. Optimizasyon hedefi ağ trafiğini sıfırlamak değil; **CPU yükünü sıfırlamak** ve **egress bantını en aza indirmektir.**

### 1.2 Kalite Stratejisi — Tek Katman, Ağa Bırak

**Karar: Simulcast kullanılmayacak.**

Gerekçe:
- Host ve viewer ikisi de mobil — ağ koşulu her ikisi için de değişken
- Simulcast host'a ~%33 fazla upload maliyeti + uzun yayınlarda ısınma
- WebRTC'nin yerleşik BWE (Bandwidth Estimation), tek stream'in bitrate'ini host'un ağına göre zaten otomatik ayarlar
- Erken aşamada kullanıcı verisi olmadan katman optimizasyonu yapmak anlamsız

**Nasıl çalışır:**
```
Host WiFi güçlü → BWE 1.2 Mbps → tüm viewer'lar iyi kalite
Host 4G orta    → BWE 600 kbps → tüm viewer'lar orta kalite
Host zayıf ağ  → BWE 200 kbps → tüm viewer'lar düşük kalite
```

**İleride simulcast'e geçiş koşulu:** Şu sinyaller gelince değerlendirilir:
- Viewer tarafında yoğun buffer/kopma şikayeti
- Host'un ağı iyi olmasına rağmen viewer'lar kötü kalite alıyor

### 1.3 Viewer Tracking Sahipliği — LiveKit Webhook

**Karar: Viewer count ve seans verisi LiveKit webhook'tan yönetilecek.**

Gerekçe:
- Analytics gereksinimi var — anlık sayaç yetmez, kim/ne zaman/ne kadar süre izledi verisi gerekiyor
- Chat WS'ye bağımlı sayaç sessiz viewer'ları sayamıyor
- `participant_left` webhook tüm ayrılış türlerini yakalar (temiz çıkış, crash, network drop) — `leave_stream` API'si bunu yapamaz
- Tek kaynak gerçek → tutarlılık problemi ortadan kalkar

**Akış:**
```
LiveKit → webhook: participant_joined (type=viewer)
  → Redis INCR live:viewers:{stream_id}      ← live UI için anlık sayaç
  → LiveStreamViewer.joined_at = now         ← analytics kaydı

LiveKit → webhook: participant_left (type=viewer)
  → Redis DECR live:viewers:{stream_id}      ← live UI için anlık sayaç
  → LiveStreamViewer.left_at = now           ← analytics kaydı
```

**Bu kararın etkilediği noktalar (ilgili adımlar geldiğinde birlikte değerlendirilecek):**

- `chat_commands.py` viewer INCR/DECR → kaldırılacak (Faz 8'e not düşüldü)
- `leave_stream` API endpoint → "best-effort, anında güncelleme" optimizasyonu olarak kalır; birincil kaynak değil (Faz 5'e not düşüldü)
- `join_stream` API endpoint → DB insert kalır, Redis'e dokunmaz (Faz 8'e not düşüldü)
- `live:room_to_stream:{room_name}` → yeni mapping key gerekiyor; LiveKit webhook `room_name` veriyor ama key'lerimiz `stream_id` bazlı olacak (Faz 8'e not düşüldü)
- `live:viewer_set:{stream_id}` (username set) → webhook'ta kullanıcı adı yok, sadece participant identity var; bu key'in rolü netleştirilmeli (Faz 8'e not düşüldü)

### 1.4 Reconnect Token Stratejisi

**Karar: Reconnect akışı fresh token alacak — stream state doğrulaması birincil kazanım.**

Gerekçe:
- Eski token ile reconnect, stream'in hâlâ canlı olup olmadığını doğrulamıyor
- Stream webhook tarafından kapatılmışsa 3 başarısız deneme (2+4+8 sn) sonra kullanıcı home'a gönderiliyor — nedenini bilmeden
- Fresh token endpoint aynı anda iki şey yapıyor: stream durumunu kontrol eder, geçerliyse yeni token üretir
- Token TTL şimdilik 24 saat kalır; endpoint olduğunda TTL düşürme tek satır değişiklik

**Akış:**
```
RoomDisconnectedEvent
  → GET /streams/{id}/token
      ├─ 200 + fresh token  → room.connect(url, freshToken)
      └─ 404 / 410          → "yayın sona erdi" UI → temiz çıkış, retry yok
```

**Bu kararın etkilediği noktalar:**
- Faz 2.2 (host reconnect): `widget.streamToken.token` yerine endpoint'ten fresh token (Faz 2.2'ye not düşüldü)
- Faz 3.2 (viewer reconnect): aynı pattern — viewer için de fresh token endpoint (Faz 3.2'ye not düşüldü)
- Yeni backend endpoint gerekiyor: `GET /streams/{id}/token` — stream canlıysa token döner, değilse 410 (Faz 2.2'ye eklendi)
- `make_livekit_token` TTL parametresi şimdilik 24h; ileride stream süresi + buffer olarak düşürülebilir

### 1.5 Stream Kapatma — Tek Helper, Çok Yol

**Karar: `finalize_stream()` shared helper — tüm kapatma yolları buradan geçer.**

Gerekçe:
- `EndStreamCommand`, `force_close_stream`, `admin_end_stream` aynı işi üç ayrı yerde farklı eksiklerle yapıyor
- Yeni cleanup adımı eklendiğinde (peak_viewer_count snapshot, yeni Redis key vb.) üç yeri birden hatırlamak gerekiyor — bu bakım borcu
- `admin_end_stream` şu an LiveKit room silmiyor, WS STREAM_ENDED normal path üzerinden gitmiyor — helper hepsini kapsayınca admin eksikliği de otomatik kapanır

**Akış:**
```
EndStreamCommand    ─┐
force_close_stream  ─┼─→ finalize_stream(stream, db, redis)
admin_end_stream    ─┘      ├── DB: viewer_count + peak snapshot
                            ├── DB: LiveStreamViewer.left_at toplu güncelleme
                            ├── LiveKit room sil
                            ├── Redis temizle (tüm live:* key'ler)
                            └── WS STREAM_ENDED
```

**Bu kararın etkilediği noktalar:**
- Faz 7: ayrı ayrı B-5/B-6 değişiklikleri yerine `finalize_stream` yazılacak (Faz 7'ye yansıtıldı)
- Faz 5.3 (`force_close_stream` left_at toplu güncelleme): `finalize_stream` içine alındı, ayrı faz değil
- `admin_data.py::admin_end_stream`: LiveKit silme + WS eksikliği `finalize_stream` ile kapanır

### 1.6 Mevcut Durum ile Örtüşme

`Room()` sıfır parametre ile çağrılıyor — simulcast zaten kapalı, BWE aktif. **Karar ile örtüşüyor.**

Eksikler: `maxBitrate` tanımlı değil (SDK varsayılanı 3.2 Mbps), çözünürlük kısıtı yok (kamera native çözünürlükte yakalıyor — muhtemelen 1080p), degradation preference ayarlanmamış (encoder bozulma stratejisi belirsiz). Faz 1 üçünü birden düzeltiyor:

```dart
// ÖNCE
final room = Room();

// SONRA
final room = Room(
  roomOptions: const RoomOptions(
    defaultVideoPublishOptions: VideoPublishOptions(
      simulcast: false,
      videoEncoding: VideoEncoding(
        maxBitrate: 1_500_000,  // 1.5 Mbps — 720p@30fps için uygun tavan
        maxFramerate: 30,
      ),
    ),
    defaultAudioPublishOptions: AudioPublishOptions(
      audioBitrate: 128000,
    ),
  ),
);
```

---

## 2. Mevcut Durum Analizi

### 2.1 Şu Anki Kod (Gerçek Durum)

```dart
// host_stream_screen.dart:494
final room = Room();  // ← hiç parametre yok

// host_stream_screen.dart:532
await room.localParticipant?.setCameraEnabled(true);  // ← hiç parametre yok
```

**Sonuç:**
- Host tek kalite katmanı gönderiyor (simulcast KAPALI)
- Çözünürlük ve bitrate SDK'nın belirsiz varsayılanına bırakılmış
- Dynacast çalışamaz — elimine edeceği alternatif katman yok
- AdaptiveStream işlevsiz — seçecek katman yok
- VPS transcode yapmıyor ✅ (SFU hiç yapamaz) — ama tek kalite herkese gidiyor

```dart
// stream_connection_manager.dart:226
final room = Room();  // ← viewer tarafı da opsiyonsuz
```

### 2.2 Ne Çalışıyor ✅

| Alan | Durum |
|---|---|
| Webhook endpoint (`POST /api/webhooks/livekit`) | Mevcut, HMAC imzalı |
| `room_finished` → force_close_stream (60s delay) | ARQ job ile restart-safe |
| `participant_left` → 2 dakika grace period | ARQ job + `live:host_reconnect:{id}` Redis key |
| `participant_joined` → grace timer iptal | Çalışıyor |
| Viewer `autoSubscribe: false` | Manuel subscription — bandwidth verimli |
| Host background permission re-check | `didChangeAppLifecycleState.resumed` |
| Cohost `AcceptCohostInviteCommand` | `UpdateParticipantRequest` + yeni token döner |

### 2.3 Eksikler / Hatalar ❌

#### Host (Mobile)
| # | Sorun | Etki |
|---|---|---|
| H-1 | `Room()` opsiyonsuz — `maxBitrate` belirsiz, SDK varsayılanı 3.2 Mbps | Host gereksiz band harcar |
| H-2 | `RoomDisconnectedEvent` → sadece home'a yönlendirme | Geçici kopukta yayın ölüyor |
| H-3 | Background geçişinde kamera kapatılmıyor | Host donmuş görünür, bant harcanır |
| H-4 | `confirmLive` hatası → yalnızca permission denied'da `cancelStream` | Diğer hatalarda pending stream DB'de kalıyor |
| H-5 | `_autoCaptureThumbnail`: timer `try` bloğu içinde — hata olunca timer ölür | Ağ hatası sonrası thumbnail bir daha güncellenmez |
| H-6 | `_removeCoHost` (mobile): `_log.captureException` var ama `handleError()` yok | Host hata alıyor ama kullanıcıya hiç gösterilmiyor |
| H-7 | `_showViewers()`, `_showPinInput()`: ham `showModalBottomSheet` kullanıyor | `TeqBottomSheet.show()` design system standardına uymuyor |

#### Viewer (Mobile)
| # | Sorun | Etki |
|---|---|---|
| V-1 | `RoomDisconnectedEvent` handler var ama reconnect yok | Geçici kopukta kullanıcı yayından atılıyor |

#### Backend
| # | Sorun | Etki |
|---|---|---|
| B-1 | `RemoveCohostCommand`: `UpdateParticipantRequest` hatası `except: pass` ile yutulmuş | Sessiz başarısızlık |
| B-2 | `AcceptCohostInviteCommand`: hata yakalanıyor ama akış devam ediyor | Cohost token alıyor ama LiveKit izni yok |
| B-3 | `ConfirmLiveCommand` başarısız olursa `cancelStream` çağrılmıyor | Ölü pending stream'ler DB'de birikir |
| B-4 | `leave_stream` endpoint tamamen boş stub — sadece log yazıyor | `LiveStreamViewer` kaydı hiç güncellenmiyor; `left_at` eklenmiş olsa bile yazılmaz |
| B-5 | `EndStreamCommand` Redis temizlemiyor — `live:viewers:*`, `live:viewer_set:*`, `live:pip_viewer_set:*` bellekte kalıyor | Normal bitiş sonrası stale data; yalnızca `force_close_stream` temizliyor |
| B-6 | `EndStreamCommand` biterken `live:viewers:{room_name}` sayacını `stream.viewer_count` DB kolonuna yazmıyor | Stream sonrası izlenme istatistiği sıfır/stale — `my-history` yanlış gösteriyor |
| B-7 | `StartStreamCommand` eşzamanlı yayın guard yok — aynı host birden fazla aktif stream açabilir | Orphaned stream'ler DB'de birikir; webhook grace sonra temizler ama aralıkta tutarsız durum |
| B-8 | `stream:stats:{stream_id}` Redis key: `StreamAnalyticsProjector` yazıyor, hiçbir endpoint okumuyor, hiç temizlenmiyor | Ölü kod + Redis memory leak |
| B-9 | Redis viewer tracking 4 farklı key, 3 farklı temizleme yolu — şema dağınık | `live:viewer_set` hem `stream_id` hem `room_name` ile keyleniyor; hangi key yetkili belirsiz — **Karar 1.3: webhook sahipliğine geçişle çözülecek** |

#### DB
| # | Sorun | Etki |
|---|---|---|
| D-1 | `LiveStreamViewer` tablosunda `left_at` kolonu yok | Seans süresi hesaplanamıyor |

---

## 3. Hedef Mimari

```
Host cihazı
  └── tek kalite (BWE yönetimli, tavan 1.2 Mbps) ─→ LiveKit SFU (VPS) ─→ tüm viewer'lar
                                                       sadece UDP forward
```

**VPS yükü:** 0 transcode. Yalnızca UDP forward + WebSocket signaling.  
**Kalite kararı:** Host'un ağ koşulu belirler — BWE tavan dahilinde otomatik ayarlar.

---

## 4. Optimizasyon Pipeline'ı

### 4.1 Host Cihazı → SFU (Upload)

**Tek kalite, BWE yönetimli.** Simulcast yok — host ağ koşuluna göre BWE otomatik bitrate seçer, tavan 1.5 Mbps.

**FPS:** 30fps canlı yayın için standart.

### 4.2 VPS SFU Kernel Ayarları

WebRTC tamamen UDP. Linux varsayılan UDP buffer'ları küçük → paket kaybı artar → NACK (yeniden iletim) → CPU yükü gereksiz artar:

```bash
# /etc/sysctl.conf — LiveKit resmi önerisi
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.netdev_max_backlog=5000
```

```bash
sudo sysctl -p  # restart gerektirmez, hemen aktif
```

### 4.3 LiveKit Server Config — Per-Room Limit

`livekit.yaml` içinde tek yayının VPS uplink'ini doldurmasını engelle:

```yaml
room:
  max_participants: 500
  subscriber_bandwidth_limit: 800000   # viewer başına max 800 kbps
  publisher_bandwidth_limit: 2000000   # host max 2 Mbps göndersin
```

### 4.4 SFU → Viewer (Egress)

Tek kalite model — viewer ne alacağı host'un ağ kalitesiyle belirlenir. AdaptiveStream/Dynacast aktif değil.

---

## 5. Faz Planı

---

### Faz 1 — Host Yayın Parametreleri

**Etki:** Çözünürlük kısıtı, bitrate tavanı ve degradation preference — üçü birden.  
**Dosyalar:**
- `mobile/lib/screens/live/host_stream_screen.dart` (~satır 494 `Room()`, ~satır 532 `setCameraEnabled`)

**Karar (Adım 5):**
- Çözünürlük: **720p** — `VideoParametersPresets.h720_169`
- Bitrate tavanı: **1.5 Mbps** — 720p@30fps için uygun (önceki plan 1.2 Mbps'ti, 720p için düşük)
- Degradation: **`balanced`** — ağ bozulunca BWE bitrate düşürürken WebRTC hem çözünürlüğü hem FPS'i orantılı azaltır; 720p'de bloklanma yerine temiz düşük çözünürlük
- V2'de explicit tier switching (720p → 540p → 360p) değerlendirilebilir

```dart
// ÖNCE
final room = Room();
// ...
await room.localParticipant?.setCameraEnabled(true);

// SONRA — Room oluşturma
final room = Room(
  roomOptions: const RoomOptions(
    defaultVideoPublishOptions: VideoPublishOptions(
      simulcast: false,
      videoEncoding: VideoEncoding(
        maxBitrate: 1_500_000,  // 1.5 Mbps — 720p@30fps tavanı
        maxFramerate: 30,
      ),
    ),
    defaultAudioPublishOptions: AudioPublishOptions(
      audioBitrate: 128000,
    ),
  ),
);

// SONRA — kamera açma: çözünürlük + degradation
await room.localParticipant?.setCameraEnabled(
  true,
  cameraCaptureOptions: const CameraCaptureOptions(
    params: VideoParametersPresets.h720_169,       // 1280×720 yakalama
    degradationPreference: RTCDegradationPreference.balanced, // ağ bozulunca hem res hem fps düşer
  ),
);
```

---

### Faz 2 — Host Hata Yönetimi

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart`

#### 2.1 Background Geçişinde Kamera Kapatma (H-3)

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
    _handleHostBackground();
    return;
  }
  if (state == AppLifecycleState.resumed) {
    _recheckPermissionsAfterResume();  // mevcut
  }
}

Future<void> _handleHostBackground() async {
  if (_room == null || _error != null) return;
  if (_cameraEnabled) {
    await _room?.localParticipant?.setCameraEnabled(false);
    if (mounted) {
      TeqToast.warning(ref.read(localizationProvider).tOr(
        'hostCameraDisabledBackground',
        'Uygulama arka plana geçti — kamera duraklatıldı',
      ));
    }
  }
}
```

#### 2.2 `RoomDisconnectedEvent` → Retry (H-2)

> **Karar 1.4:** Reconnect öncesinde `GET /streams/{id}/token` endpoint'i çağrılır. Stream sona erdiyse retry yapılmaz, kullanıcıya temiz mesaj gösterilir.

**Yeni backend endpoint:**
```python
# backend/app/routers/streams.py
@router.get("/{stream_id}/token", response_model=StreamTokenOut)
async def refresh_stream_token(stream_id: int, current_user: User = ...):
    stream = await db.get(LiveStream, stream_id)
    if not stream or not stream.is_live:
        raise HTTPException(status_code=410, detail={"error": {"code": "STREAM_ENDED"}})
    # Host yayını yayınlar, viewer yalnızca abone olur — caller'ın kimliğine göre otomatik
    can_publish = stream.host_id == current_user.id
    token = make_livekit_token(stream, current_user, can_publish=can_publish)
    return StreamTokenOut(token=token, livekit_url=settings.livekit_url)
```

**Mobile (host reconnect):**
```dart
_listener!.on<RoomDisconnectedEvent>((event) {
  if (!mounted) return;
  final reason = event.reason;
  if (reason == DisconnectReason.CLIENT_INITIATED ||
      reason == DisconnectReason.ROOM_DELETED) {
    _endStream();
    return;
  }
  _scheduleReconnect();
});

int _reconnectAttempts = 0;
Timer? _reconnectTimer;
static const _maxReconnectAttempts = 3;

void _scheduleReconnect() {
  if (_reconnectAttempts >= _maxReconnectAttempts) {
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    return;
  }
  final delay = Duration(seconds: 2 << _reconnectAttempts); // 2s, 4s, 8s
  _reconnectAttempts++;
  _reconnectTimer = Timer(delay, _reconnect);
}

Future<void> _reconnect() async {
  if (!mounted || _room == null) return;
  try {
    // Karar 1.4: fresh token al — stream state doğrulaması burada yapılıyor
    final freshToken = await StreamService.refreshStreamToken(widget.streamToken.streamId);
    await _room!.connect(freshToken.livekitUrl, freshToken.token);
    _reconnectAttempts = 0;
  } on AppException catch (e) {
    if (e.code == 'STREAM_ENDED') {
      // Stream kapanmış — retry değil, temiz çıkış
      if (mounted) _showStreamEndedAndExit();
      return;
    }
    _scheduleReconnect();
  } catch (_) {
    _scheduleReconnect();
  }
}
```

> **Mimari borç notu:** `_reconnectAttempts`, `_reconnectTimer`, `_scheduleReconnect()` idealde ViewModel'de olmalı. Ancak `HostStreamViewModel` şu an stateless proxy olduğu için V1.0'da widget'a ekleniyor. V2 MVVM migrasyonunda burası taşınacak.

#### 2.3 `confirmLive` Hatası → `cancelStream` (H-5)

```dart
try {
  await StreamService.confirmLive(widget.streamToken.streamId, ...);
} catch (e) {
  StreamService.cancelStream(widget.streamToken.streamId).ignore();
  if (mounted) {
    setState(() => _error = ref.read(localizationProvider).tOr(
      'streamConfirmFailed',
      'Yayın başlatılamadı',
    ));
  }
  return;
}
```

---

### Faz 3 — Viewer AdaptiveStream + Reconnect

**Dosya:** `mobile/lib/services/stream_connection_manager.dart`

#### 3.1 Viewer `RoomOptions` (V-1)

Simulcast kullanılmadığı için `adaptiveStream` ve `dynacast` anlamsızdır — seçecek/durduracak katman yok. Viewer tarafı da `Room()` olarak kalır. Bu faz yalnızca reconnect mantığını kapsar.

#### 3.2 Viewer Reconnect — Exponential Backoff (V-2)

> **Karar 1.4:** Viewer reconnect da fresh token pattern'ini izler. `GET /streams/{id}/token` viewer için de aynı endpoint — sadece `can_publish: false` token döner.

`_setupListeners()` içine:

```dart
session.listener!.on<RoomDisconnectedEvent>((event) {
  if (session.isDisposed || session.streamEnded) return;
  if (event.reason == DisconnectReason.ROOM_DELETED) {
    session.streamEnded = true;
    session.update();
    return;
  }
  _scheduleViewerReconnect(session);
});
```

```dart
final Map<int, int> _reconnectAttempts = {};
final Map<int, Timer> _reconnectTimers = {};

void _scheduleViewerReconnect(LiveSession session) {
  final attempts = _reconnectAttempts[session.streamId] ?? 0;
  if (attempts >= 4) {
    session.error = Exception('Bağlantı yeniden kurulamadı');
    session.update();
    return;
  }
  _reconnectAttempts[session.streamId] = attempts + 1;
  final delay = Duration(milliseconds: 500 * (1 << attempts)); // 500ms, 1s, 2s, 4s
  _reconnectTimers[session.streamId]?.cancel();
  _reconnectTimers[session.streamId] = Timer(delay, () => _reconnectRoom(session));
}

Future<void> _reconnectRoom(LiveSession session) async {
  try {
    // Karar 1.4: fresh token — stream sona erdiyse STREAM_ENDED alır, retry yapılmaz
    final freshToken = await StreamService.refreshStreamToken(session.streamId);
    await _connectRoom(session, token: freshToken);
    _reconnectAttempts.remove(session.streamId);
  } on AppException catch (e) {
    if (e.code == 'STREAM_ENDED') {
      session.streamEnded = true;
      session.update();
      return;
    }
    _scheduleViewerReconnect(session);
  } catch (_) {
    _scheduleViewerReconnect(session);
  }
}
```

`_disconnect(id)` içinde temizleme:
```dart
_reconnectAttempts.remove(id);
_reconnectTimers[id]?.cancel();
_reconnectTimers.remove(id);
```

---

### Faz 4 — Backend Cohost Hata Yönetimi

**Dosya:** `backend/app/use_cases/streams/commands/cohost_commands.py`

#### 4.1 `RemoveCohostCommand` — Sessiz Başarısızlığı Kaldır (B-1)

```python
# ÖNCE
except Exception as e:
    pass

# SONRA
except Exception as e:
    logger.error(
        "[COHOST] UpdateParticipant başarısız (remove) | stream=%s user=%s | %s",
        stream_id, target.id, e,
    )
    raise BadRequestException(code="COHOST_REMOVE_FAILED")
```

#### 4.2 `AcceptCohostInviteCommand` — LiveKit Hatası Token Vermemeli (B-2)

```python
# ÖNCE — hata loglanıyor ama token vermeye devam ediyor
except Exception as e:
    logger.error("[COHOST] Yetki yükseltilirken hata: %s", str(e))

# SONRA
except Exception as e:
    logger.error("[COHOST] Yetki yükseltilirken hata: %s", str(e), exc_info=True)
    raise BadRequestException(code="COHOST_GRANT_FAILED")
```

Mobile:
```dart
try {
  final token = await StreamService.acceptCohostInvite(streamId);
  _reconnectAsCohost(token);
} catch (e) {
  handleError(e, ref.read(localizationProvider));
}
```

#### 4.3 `ConfirmLiveCommand` — Hata Sonrası Cleanup (B-3)

```python
# lifecycle_commands.py
try:
    stream.is_live = True
    # ... commit
except Exception as exc:
    try:
        from app.use_cases.streams.stream_utils import delete_livekit_room
        await delete_livekit_room(stream.room_name)
        await self.uow.session.delete(stream)
        await self.uow.session.commit()
    except Exception:
        pass  # webhook 2dk'da temizler
    raise DatabaseException(code="CONFIRM_LIVE_FAILED") from exc
```

---

### Faz 5 — DB: `left_at` Kolonu + `leave_stream` Endpoint Fix

**Ön koşul:** `leave_stream` endpoint şu an boş stub — önce endpoint düzeltilmeli, sonra `left_at` anlamlı olur.

**Mimari uyum:** Alembic — revision ID ≤ 32 karakter, her SQL ayrı `op.execute()`.

#### 5.1 Migration

```python
def upgrade() -> None:
    # left_at: viewer seans süresi (Faz 5)
    op.execute(
        "ALTER TABLE live_stream_viewers ADD COLUMN left_at TIMESTAMP WITH TIME ZONE"
    )
    op.execute(
        "CREATE INDEX ix_live_stream_viewers_left_at ON live_stream_viewers (left_at)"
    )
    # peak_viewer_count: yayın boyunca ulaşılan maksimum eşzamanlı izleyici (Faz 7.2)
    op.execute(
        "ALTER TABLE live_streams ADD COLUMN peak_viewer_count INTEGER"
    )

def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_live_stream_viewers_left_at")
    op.execute("ALTER TABLE live_stream_viewers DROP COLUMN IF EXISTS left_at")
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS peak_viewer_count")
```

#### 5.2 `leave_stream` Endpoint Fix (B-4)

> **Not (Karar 1.3):** `left_at`'in birincil kaynağı artık bu endpoint değil, `participant_left` webhook event'ı. Bu endpoint "best-effort, temiz çıkış optimizasyonu" rolünde kalır — kullanıcı uygulamayı normal kapattığında anında yazılır, crash/kill durumunda webhook yazar. İkisi de yazarsa `left_at` zaten dolu olduğu için güncelleme yapılmaz.

`backend/app/routers/streams.py` — şu an sadece log yazıyor:

```python
@router.delete("/{stream_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_stream(stream_id: int, db: AsyncSession = ..., current_user: User = ...):
    # Mevcut: sadece logger.info — DB'ye hiçbir şey yazılmıyor
    
    # Hedef: LiveStreamViewer kaydını kapat
    viewer = await db.scalar(
        select(LiveStreamViewer).where(
            LiveStreamViewer.stream_id == stream_id,
            LiveStreamViewer.user_id == current_user.id,
            LiveStreamViewer.left_at.is_(None),
        )
    )
    if viewer:
        viewer.left_at = datetime.now(timezone.utc)
        await db.commit()
    
    logger.info("[STREAMS] Yayından ayrılındı | stream_id=%s user_id=%s", stream_id, current_user.id)
```

#### 5.3 `force_close_stream` Toplu Güncelleme

> **Karar 1.5:** Bu adım `finalize_stream` helper içine taşındı (Faz 7.1). `force_close_stream` ve `EndStreamCommand` her ikisi de helper'ı çağıracağı için burada ayrıca yazılmasına gerek kalmadı.

---

### ~~Faz 6~~ — ❌ Kaldırıldı

> **Karar (Adım 4 analizi):** Faz 6'nın önerdiği `live:stream:{stream_id}:viewer_count` iç içe naming stili mevcut codebase ile çelişiyor — tüm diğer LIFECYCLE key'leri `live:{type}:{id}` düz stilini kullanıyor. `live:stream:{stream_id}:is_live` key'inin hiçbir okuyucusu yok — `stream.is_live` DB alanı yeterli. Bu fazın kararları Faz 8'e taşındı ve orada canonical şema tanımlandı.

---

### Faz 7 — `finalize_stream` Helper + Veri Bütünlüğü

**Amaç:** Tüm stream kapatma yollarını tek bir helper üzerinden konsolide et; veri bütünlüğü sorunlarını (B-5, B-6) ve admin eksikliğini birlikte çöz.

**Karar 1.5:** `finalize_stream` shared helper — `EndStreamCommand`, `force_close_stream`, `admin_end_stream` hepsi bunu çağırır.

#### 7.1 `finalize_stream` Helper Oluştur

**Yeni dosya:** `backend/app/use_cases/streams/stream_finalizer.py`

```python
async def finalize_stream(stream: LiveStream, db: AsyncSession) -> None:
    """Tüm stream kapatma yollarının ortak cleanup helper'ı.
    Çağıran: EndStreamCommand, force_close_stream, admin_end_stream.
    """
    redis = await get_redis()

    # 1. İstatistik snapshot — Redis silinmeden önce
    live_count = await redis.get(f"live:viewers:{stream.id}")
    peak_count = await redis.get(f"live:peak_viewers:{stream.id}")
    if live_count is not None:
        stream.viewer_count = max(stream.viewer_count or 0, int(live_count))
    if peak_count is not None:
        stream.peak_viewer_count = int(peak_count)

    # 2. DB: stream kapat
    stream.is_live = False
    stream.ended_at = datetime.now(timezone.utc)

    # 3. DB: açık kalan viewer seanslarını kapat
    await db.execute(
        update(LiveStreamViewer)
        .where(
            LiveStreamViewer.stream_id == stream.id,
            LiveStreamViewer.left_at.is_(None),
        )
        .values(left_at=datetime.now(timezone.utc))
    )

    await db.commit()

    # 4. LiveKit room sil (idempotent — 404 sessizce geçilir)
    try:
        await delete_livekit_room(stream.room_name)
    except Exception:
        pass  # Webhook zaten sildiyse 404 — kabul edilebilir

    # 5. Redis temizle — Faz 8 canonical şeması: tüm key'ler stream_id bazlı
    await redis.delete(
        f"live:viewers:{stream.id}",
        f"live:peak_viewers:{stream.id}",
        f"live:viewer_set:{stream.id}",
        f"live:room_to_stream:{stream.room_name}",
        f"live:pip_viewer_set:{stream.id}",
        f"live:host_reconnect:{stream.id}",
        f"stream:stats:{stream.id}",
    )

    # 6. WS bildirimi
    await ws_manager.broadcast(
        f"stream:{stream.id}",
        {"type": WS.STREAM_ENDED},
    )
```

#### 7.2 Kapatma Yollarını Helper'a Bağla

**`EndStreamCommand`** — host kendi kapatıyor:
```python
# Mevcut DB/LiveKit/WS mantığını kaldır, helper'a delege et
await finalize_stream(stream, self.uow.session)
```

**`force_close_stream`** — webhook timeout:
```python
await finalize_stream(stream, db)
```

**`admin_end_stream`** — admin panel (şu an LiveKit silmiyor, WS eksik):
```python
await finalize_stream(stream, db)
# Artık LiveKit + Redis + WS hepsi kapsanıyor
```

#### 7.3 Eşzamanlı Yayın Guard (B-7)

**Dosya:** `backend/app/use_cases/streams/commands/start_stream.py`

```python
existing = await self.uow.session.scalar(
    select(LiveStream).where(
        LiveStream.host_id == self.user_id,
        LiveStream.ended_at.is_(None),
    )
)
if existing:
    raise BadRequestException(code="STREAM_ALREADY_ACTIVE")
```

Mobile'da `STREAM_ALREADY_ACTIVE` hatası `handleError()` ile gösterilir.

#### 7.4 `stream:stats` Dead Code Kaldırma (B-8)

**Dosya:** `backend/app/use_cases/streams/projectors/stream_projector.py`

`StreamStartedEvent` handler'ındaki `stream:stats:{stream_id}` yazımını kaldır — hiçbir endpoint okumuyor, `finalize_stream` zaten temizliyor.

---

### Faz 8 — Redis Viewer Tracking Şema Birleştirme (B-9)

> **Karar 1.3 bu fazı şekillendiriyor** — viewer count ve `left_at` artık webhook sahipliğinde. Bu faz o kararın Redis ve kod tarafını uygular.

**Mevcut kaos:**
| Key | Kim yazar | Kim okur | Kim temizler |
|---|---|---|---|
| `live:viewers:{room_name}` | chat_commands.py | stream_utils.py, get_raid_targets | force_close_stream ✅ EndStreamCommand ❌ |
| `live:viewer_set:{stream_id}` | chat_commands.py (SADD username) | audience_insights (yanlış key!) | force_close_stream ❌ EndStreamCommand ❌ |
| `live:viewer_set:{room_name}` | — | audience_insights (SMEMBERS) | hiçbiri ❌ |
| `live:pip_viewer_set:{stream_id}` | pip_enter/pip_exit | audience_insights | force_close_stream ❌ EndStreamCommand ❌ |
| `stream:stats:{stream_id}` | stream_projector | hiçbiri | hiçbiri ❌ |

**Hedef şema (canonical — Faz 6 yerine bu geçerli):**

```
live:viewers:{stream_id}           # anlık sayaç — webhook INCR/DECR
live:peak_viewers:{stream_id}      # peak sayaç — webhook günceller (chat_utils'ten taşınır)
live:room_to_stream:{room_name}    # mapping cache — start_stream'de yazılır, webhook lookup için
live:pip_viewer_set:{stream_id}    # user_id set — pip_enter/exit (değişmez)
live:host_reconnect:{stream_id}    # reconnect grace — zaten doğru, dokunulmaz
```

`live:viewer_set` (username set) kaldırılıyor — `audience_insights` bu veriyi `LiveStreamViewer` DB tablosundan okuyacak.  
`live:stream:{id}:viewer_count` ve `live:stream:{id}:is_live` (Faz 6 önerisiydi) — hiç eklenmeyecek.

**Geçiş adımları:**
1. `start_stream`: `live:room_to_stream:{room_name}` → `stream_id` mapping'ini Redis'e yaz (TTL = 48h)
2. `webhooks.py`: `participant_joined/left` event'larında mapping'i okuyarak `stream_id`'yi çöz; Redis INCR/DECR (`live:viewers` ve `live:peak_viewers`) + `LiveStreamViewer` güncelle
3. `chat_commands.py`: viewer INCR/DECR ve SADD username kaldır — sadece mesajlaşma kalır
4. `join_stream` command: `LiveStreamViewer` DB insert kalır, Redis'e dokunmaz
5. `audience_insights`: `live:viewer_set` yerine `LiveStreamViewer` tablosunu sorgula
6. `force_close_stream`, `EndStreamCommand`, `admin_end_stream`: tüm key'leri temizlesin — `live:viewers:{stream_id}`, `live:peak_viewers:{stream_id}`, `live:room_to_stream:{room_name}`, `live:pip_viewer_set:{stream_id}`

> **Admin cleanup notu:** `admin_data.py::admin_end_stream` şu an yalnızca `live:viewers:{room_name}` siliyor; LiveKit room'u silmiyor, WS STREAM_ENDED normal path üzerinden gitmiyor. Bu DRY ihlali Adım 8'de ayrıca tartışılacak.

> **Açık soru (Faz 8 uygulandığında tartışılacak):** `live:viewer_set` kaldırılınca `audience_insights`'ın "anlık izleyenler" listesi `left_at IS NULL` DB sorgusuyla geliyor — gerçek zamanlı değil. Yüksek trafikte sorgu maliyeti değerlendirilmeli.

---

### Faz 11 — Stream State Machine: Explicit `status` Kolonu

**Amaç:** `is_live: bool` + `ended_at: datetime | None` kombinasyonundan çıkarılan implicit state'i, explicit `status` enum kolonuyla formalize etmek.

**Mevcut sorun:**
```python
# Her command'da ayrı ayrı, merkezi değil:
if not stream.is_live: raise         # join_stream
if stream.is_live: ...               # misc_commands
if not stream or not stream.is_live: # cohost_commands (3 yerde)
```
`is_live=True, ended_at=datetime` kombinasyonu teorik olarak oluşabilir — race condition'da tutarsız durum.

**Karar:** Explicit `StreamStatus` enum + merkezi transition guard.

#### 11.1 Migration

**Not:** Faz 5.1 migration'ından ayrı bir migration dosyası — her concern ayrı.

```python
# revision ID ≤ 32 karakter
def upgrade() -> None:
    op.execute(
        "ALTER TABLE live_streams ADD COLUMN status VARCHAR(10) NOT NULL DEFAULT 'pending'"
    )
    op.execute(
        """UPDATE live_streams SET status = CASE
            WHEN ended_at IS NOT NULL THEN 'ended'
            WHEN is_live = TRUE       THEN 'live'
            ELSE                           'pending'
        END"""
    )
    op.execute(
        "CREATE INDEX ix_live_streams_status ON live_streams (status)"
    )

def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_live_streams_status")
    op.execute("ALTER TABLE live_streams DROP COLUMN IF EXISTS status")
```

#### 11.2 Model Güncellemesi

**Dosya:** `backend/app/models/stream.py`

```python
import enum

class StreamStatus(str, enum.Enum):
    PENDING = "pending"
    LIVE    = "live"
    ENDED   = "ended"

class LiveStream(Base):
    # ...
    status: Mapped[str] = mapped_column(String(10), default=StreamStatus.PENDING)
    # is_live kalır (backward compat) — ileride kaldırılacak (V2)
    # ended_at kalır — timing bilgisi için hâlâ gerekli
```

#### 11.3 Geçiş Matrisi ve Guard'lar

| Geçiş | Command |
|---|---|
| `pending → live` | `ConfirmLiveCommand` |
| `live → ended` | `finalize_stream` (tüm kapatma yolları) |
| `pending → ended` | `cancelStream`, `confirmLive` hatası |
| `live → pending` | ❌ geçersiz |
| `ended → *` | ❌ geçersiz |

**Tüm `is_live` kontrolleri `status` ile değiştirilir:**

```python
# ÖNCE — 15+ yerde
if not stream.is_live:
    raise BadRequestException(code="STREAM_NOT_LIVE")

# SONRA — merkezi pattern
if stream.status != StreamStatus.LIVE:
    raise BadRequestException(code="STREAM_NOT_LIVE")
```

**Etkilenen dosyalar** (`grep -rn "is_live" backend/app` ile doğrula):
- `streams.py`, `chat.py`, `admin_data.py` routers
- `join_stream.py`, `cohost_commands.py`, `misc_commands.py`, `force_close_stream.py`
- `moderation_service.py`, `auction_commands.py`, `direct_sale_commands.py`

#### 11.4 `finalize_stream` Güncellemesi

```python
async def finalize_stream(stream, db):
    # ...
    stream.status   = StreamStatus.ENDED   # ← yeni
    stream.is_live  = False                 # backward compat, ileride kaldırılacak
    stream.ended_at = datetime.now(timezone.utc)
```

#### 11.5 `ConfirmLiveCommand` Güncellemesi

```python
stream.status  = StreamStatus.LIVE   # ← yeni
stream.is_live = True                 # backward compat
```

---

### Faz 10 — Push Notification Fan-out: Multicast + ARQ

**Amaç:** Yayın bildirimi fan-out'unu N eşzamanlı task'tan O(N/500) HTTP isteğine indirmek.

**İki bağımsız sorun:**

**Sorun 1 — `asyncio.create_task` döngüsü:** 10.000 takipçi → 10.000 eşzamanlı task, hepsi aynı anda FCM'e çarpıyor.

**Sorun 2 — `_send_http` her çağrıda yeni credentials:** `service_account.Credentials.from_service_account_file()` her push'ta çağrılıyor → service account dosya okuma + OAuth token talebi her takipçi için tekrarlanıyor.

#### 10.1 `FirebaseAdapter.send_multicast` Implementasyonu + Credential Paylaşımı

**Dosya:** `backend/app/infrastructure/adapters/firebase_adapter.py`

```python
class FirebaseAdapter(PushNotificationPort):

    def __init__(self, project_id, sa_path):
        self._project_id = project_id
        self._sa_path = sa_path
        self._session = None  # paylaşılan AuthorizedSession — init'te kurulur

    def _get_session(self):
        if self._session is None and self._sa_path and self._project_id:
            from google.oauth2 import service_account
            import google.auth.transport.requests
            creds = service_account.Credentials.from_service_account_file(
                self._sa_path,
                scopes=["https://www.googleapis.com/auth/cloud-platform"],
            )
            self._session = google.auth.transport.requests.AuthorizedSession(creds)
        return self._session

    async def send_multicast(
        self, tokens: list[str], title: str, body: str, data: dict = None
    ) -> dict:
        """FCM V1 multicast — 500 token'a tek HTTP isteği. Batch'ler halinde."""
        if not tokens:
            return {"success": 0, "failure": 0}

        results = {"success": 0, "failure": 0}
        BATCH = 500
        for i in range(0, len(tokens), BATCH):
            batch_tokens = tokens[i:i + BATCH]
            ok, fail = await asyncio.to_thread(
                self._send_multicast_http, batch_tokens, title, body, data
            )
            results["success"] += ok
            results["failure"] += fail
        return results

    def _send_multicast_http(self, tokens, title, body, data):
        """FCM V1 /messages:send — her token için ayrı message objesi."""
        session = self._get_session()
        url = self.FCM_SEND_URL.format(project_id=self._project_id)
        success, failure = 0, 0
        for token in tokens:
            msg = self._build_message(token, title, body, data, False, None, None)
            try:
                resp = session.post(url, json={"message": msg}, timeout=30)
                if resp.status_code == 200:
                    success += 1
                else:
                    failure += 1
            except Exception:
                failure += 1
        return success, failure
```

> **Not:** FCM V1 API, HTTP v1 batch endpoint'i kaldırdı (2024). Gerçek multicast için her token'a ayrı istek atılıyor ama `AuthorizedSession` paylaşıldığı için OAuth overhead ortadan kalkıyor. Firebase Admin SDK'nın `send_each_for_multicast` fonksiyonu da aynı şeyi yapıyor.

#### 10.2 `notify_followers_task` → ARQ Job

**Dosya:** `backend/app/use_cases/streams/stream_utils.py`

```python
async def notify_followers_task(user_id, username, stream_title, stream_id) -> None:
    # ÖNCE: asyncio.create_task döngüsü — N eşzamanlı task
    # SONRA: ARQ job enqueue — restart-safe, rate-controlled

    try:
        from app.core.task_queue import arq_pool
        await arq_pool.enqueue_job(
            "send_stream_started_notifications",
            user_id, username, stream_title, stream_id,
        )
    except Exception as exc:
        logger.error("[STREAMS] Bildirim job enqueue başarısız | %s", exc, exc_info=True)
```

**Dosya:** `backend/app/worker.py`

```python
async def send_stream_started_notifications(
    ctx, host_id: int, username: str, stream_title: str | None, stream_id: int
) -> None:
    from app.models.follow import Follow
    from app.core.di import push_port

    async with AsyncSessionLocal() as db:
        # Tüm takipçilerin device token'larını batch'li çek
        follower_ids = await db.scalars(
            select(Follow.follower_id).where(Follow.followed_id == host_id)
        )
        tokens = await _collect_tokens_for_users(db, list(follower_ids))

    if not tokens:
        return

    loc_title = f"@{username} canlı yayın başlattı"  # OTA: notifStreamStarted
    await push_port.send_multicast(
        tokens=tokens,
        title=loc_title,
        body=stream_title or "",
        data={"type": "stream_started", "stream_id": str(stream_id)},
    )
```

**Sonuç:** 10.000 takipçi × 1.2 cihaz ort. = ~12.000 token → ceil(12.000/500) = **24 HTTP isteği** (10.000 yerine). OAuth overhead: 1 (paylaşılan session).

---

### Faz 9 — Mobile UI Küçük Düzeltmeler

#### 9.1 Thumbnail Timer Güvenliği (H-5)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart`

```dart
// ÖNCE — timer sadece başarıda yeniden başlar
try {
  // ... upload
  _thumbTimer = Timer(..., _autoCaptureThumbnail);
} catch (e, st) {
  _log.captureException(e, ...);
  // timer burada duruyor!
}

// SONRA — her durumda yeniden dene
try {
  // ... upload
} catch (e, st) {
  _log.captureException(e, ...);
} finally {
  if (mounted) {
    _thumbTimer = Timer(const Duration(seconds: _kThumbnailRefreshSeconds), _autoCaptureThumbnail);
  }
}
```

#### 9.2 `_removeCoHost` UI Feedback (H-6)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart`

```dart
// ÖNCE
} catch (e, st) {
  _log.captureException(e, stackTrace: st, tag: 'HostStream.removeCoHost');
}

// SONRA
} catch (e, st) {
  _log.captureException(e, stackTrace: st, tag: 'HostStream.removeCoHost');
  if (mounted) handleError(e, ref.read(localizationProvider));
}
```

#### 9.3 `_showViewers()` / `_showPinInput()` → `TeqBottomSheet.show()` (H-7)

**Dosya:** `mobile/lib/screens/live/host_stream_screen.dart`

Ham `showModalBottomSheet` çağrılarını `TeqBottomSheet.show()` ile değiştir — design system standardı.

---

## 6. Uygulama Öncelik Sırası

| Öncelik | Faz | Etki | Efor |
|---|---|---|---|
| 🔴 P0 | Faz 1 — Host Yayın Parametreleri | 720p + 1.5 Mbps tavan + balanced degradation — çözünürlük, bitrate, bozulma stratejisi | Küçük — RoomOptions + setCameraEnabled |
| 🔴 P0 | Faz 7.3 — Eşzamanlı yayın guard | Orphaned stream'leri engeller | Küçük |
| 🟠 P1 | VPS sysctl UDP buffer | Paket kaybı ↓, NACK ↓ | Çok küçük — 1 komut |
| 🟠 P1 | Faz 2.1 — Host background kamera | Donuk görüntü fix | Küçük |
| 🟠 P1 | Faz 4.1 — RemoveCohost hata | Sessiz bug fix | Küçük |
| 🟠 P1 | **Faz 8 → Faz 7 sırasıyla** — Redis key şeması önce | Faz 7 `stream_id` key'lerini kullanır; Faz 8 şemayı kurar — bu ikisi birlikte uygulanmalı | — |
| 🟠 P1 | Faz 7.1 — EndStreamCommand Redis cleanup | Normal bitiş sonrası stale data temizlenir; Faz 8 key şeması tamamlanmadan test edilemez | Küçük |
| 🟠 P1 | Faz 7.2 — EndStreamCommand viewer_count snapshot | Stream istatistikleri doğru yazılır | Küçük |
| 🟡 P2 | Faz 2.2 — Host reconnect | Yayın sürekliliği | Orta |
| 🟡 P2 | Faz 3.2 — Viewer reconnect | İzleyici sürekliliği | Orta |
| 🟡 P2 | Faz 2.3 — confirmLive cleanup | DB temizliği | Küçük |
| 🟡 P2 | Faz 4.2 — AcceptCohost hata | Cohost güvenilirlik | Küçük |
| 🟡 P2 | Faz 9.1 — Thumbnail timer fix | Hata sonrası thumbnail sürdürülebilir | Küçük |
| 🟡 P2 | Faz 9.2 — removeCoHost UI feedback | Sessiz hata → kullanıcıya gösterilir | Küçük |
| 🟢 P3 | Faz 5 — left_at | Analytics temeli | Küçük (migration) |
| ~~🟢 P3~~ | ~~Faz 6~~ | ~~Kaldırıldı — Faz 8'e taşındı~~ | — |
| 🟢 P3 | Faz 7.4 — stream:stats dead code kaldır | Redis temizliği | Küçük |
| 🟢 P3 | Faz 8 — Redis viewer tracking şema birleştirme | Mimari temizlik | Orta |
| 🟢 P3 | Faz 9.3 — TeqBottomSheet migration | Design system uyumu | Küçük |
| 🟢 P3 | LiveKit livekit.yaml bandwidth limit | Burst koruması | Küçük |
| 🟠 P1 | Faz 10 — Push fan-out: multicast + ARQ | N task → 24 HTTP isteği; restart-safe | Orta |
| 🟠 P1 | Faz 11 — Stream status enum | Implicit state → explicit, race condition riski kapanır | Orta (migration + 15 dosya) |

---

## 7. Mimari Uyum Kontrol Listesi

| Kural | Durum |
|---|---|
| MVVM — ViewModel'dan UI'a tek yönlü akış | ⚠️ **Mimari borç:** `HostStreamViewModel` şu an stateless proxy — tüm state `_HostStreamScreenState`'te (2434 satır God Widget). Reconnect, viewer count, cohost, medya kontrolleri hepsi widget'ta. V1.0 fazları bu yapıya dokunmadan uygulanıyor; **V2'de `HostStreamViewModel` → `StateNotifier` migrasyonu planlanmalı.** |
| `handleError()` — tüm hata yollarında | Faz 2.3, Faz 4 — plan'da var |
| OTA Localization — yeni stringler ARB'ye | `hostCameraDisabledBackground`, `streamConfirmFailed` — eklenecek |
| LIFECYCLE cache — stream state | Faz 8 — canonical key şeması tanımlandı |
| Alembic — her SQL ayrı `op.execute()` | Faz 5 migration — uyumlu |
| Alembic revision ID ≤ 32 karakter | Faz 5 — dikkat edilecek |
| `delayed_state_transition` — asyncio.sleep yasak | Reconnect `Timer` kullanıyor — uyumlu |
| ARQ job — restart-safe state değişimleri | Webhook zaten ARQ kullanıyor |
| `StreamCommerceNotifier` pattern | Viewer `RoomDisconnectedEvent` → notifier state güncellemesi |

---

## 8. Test Senaryoları

### Faz 1 — Bitrate Tavanı
1. Host yayın aç → LiveKit dashboard → room inspector → published bitrate 1.2 Mbps tavanını aşıyor mu?
2. Host zayıf ağda → BWE bitrate'i otomatik düşürüyor mu?

### Faz 2 — Host Dayanıklılık
1. WiFi kes (<2dk) → WiFi aç → yayın devam ediyor mu?
2. WiFi kes (>2dk) → webhook yayını otomatik kapattı mı?
3. Background → kamera kapatıldı mı? Foreground → açıldı mı?
4. `confirmLive` başarısız → pending stream DB'den silindi mi?

### Faz 3 — Viewer Dayanıklılık
1. WiFi kes → 4 deneme → bağlantı geri gelince otomatik reconnect
2. Host yayını kapatınca `streamEnded` state'i doğru geliyor mu?

### Faz 4 — Cohost
1. Cohost davet → kabul → yayın aç → çalışıyor mu?
2. LiveKit sunucu hatası → `COHOST_GRANT_FAILED` mobile'da görünüyor mu?
3. Cohost çıkar → hata loglanıyor mu?

### Faz 7 — EndStreamCommand Veri Bütünlüğü
1. Host yayını kapat → Redis'te `live:viewers:*` ve `live:viewer_set:*` key'leri silindi mi? (`redis-cli KEYS 'live:*'`)
2. Host yayını kapat → `stream.viewer_count` DB'de anlık izleyici sayısını yansıtıyor mu?
3. Aynı host aynı anda iki yayın başlatmayı dene → `STREAM_ALREADY_ACTIVE` hatası alıyor mu?

### Faz 8 — Redis Şema Birleştirme
1. Viewer katıl → `live:viewers:{stream_id}` sayacı artıyor mu?
2. Viewer ayrıl → sayaç azalıyor mu?
3. `audience_insights` endpoint'i doğru viewer setini dönüyor mu?

### Faz 4.3 — confirmLive Cleanup
1. LiveKit'e bağlanılamama simüle et → `confirmLive` hata dönsün → stream DB'de `pending` değil, silinmiş mi?
2. `GET /api/streams/{id}` 404 dönüyor mu?

### Faz 9 — Mobile UI
1. Thumbnail upload başarısız → 60 saniye sonra otomatik tekrar deneniyor mu?
2. RemoveCoHost başarısız → host kullanıcıya hata toast'u görüyor mu?
3. Viewers ve pin modalleri `TeqBottomSheet.show()` ile açılıyor mu?

### Faz 10 — Push Fan-out
1. 10 takipçili test hesabı → yayın başlat → ARQ job `send_stream_started_notifications` kuyruğa girdi mi? (`redis-cli LRANGE arq:queue:default 0 -1`)
2. Job tamamlandı → tüm takipçilere bildirim gönderildi mi?
3. `firebase_adapter._get_session()` ikinci çağrıda credentials yeniden oluşturmuyor mu? (log'da tek "credentials created" satırı)

### Faz 11 — Stream State Machine
1. `confirmLive` başarılı → `status = 'live'` ve `is_live = True` aynı anda yazıldı mı? (`SELECT status, is_live FROM live_streams WHERE id = ?`)
2. `finalize_stream` çalıştı → `status = 'ended'` ve `ended_at IS NOT NULL` aynı anda mı?
3. `join_stream` → `status = 'pending'` stream'e → `STREAM_NOT_LIVE` hatası mı?
4. `join_stream` → `status = 'ended'` stream'e → `STREAM_NOT_LIVE` hatası mı?

### VPS sysctl — UDP Buffer
1. `sysctl net.core.rmem_max` → 7500000 döndü mü?
2. `sysctl net.core.wmem_max` → 7500000 döndü mü?
3. LiveKit dashboard → "Packet Loss" metriği uygulama öncesi/sonrası karşılaştır (referans: LiveKit → Rooms → room adı → Diagnostics)

---

## 9. Commit Stratejisi

```
feat(live): host RoomOptions — 720p + maxBitrate 1.5 Mbps tavan + balanced degradation (Faz 1)
ops(live): VPS sysctl UDP buffer tuning
feat(live): host background camera pause (Faz 2.1)
feat(live): host reconnect exponential backoff + /token endpoint (Faz 2.2)
i18n(live): ARB strings — hostCameraDisabledBackground, streamConfirmFailed (Faz 2)
fix(live): confirmLive error → cancelStream cleanup (Faz 2.3)
feat(live): viewer reconnect exponential backoff (Faz 3.2)
fix(live): cohost remove/accept silent error → log + raise (Faz 4)
fix(live): leave_stream endpoint DB update + left_at migration (Faz 5)
refactor(live): unify Redis viewer tracking key schema — canonical stream_id keys (Faz 8)
refactor(live): finalize_stream helper — tüm kapatma yolları konsolide (Faz 7.1-7.2)
fix(live): StartStreamCommand concurrent stream guard (Faz 7.3)
refactor(live): remove stream:stats dead read model (Faz 7.4)
fix(live): thumbnail timer always reschedule in finally block (Faz 9.1)
fix(live): removeCoHost — surface error to host via handleError (Faz 9.2)
refactor(live): viewers/pin modals → TeqBottomSheet.show() (Faz 9.3)
refactor(push): FirebaseAdapter send_multicast + shared credentials (Faz 10.1)
refactor(push): notify_followers_task → ARQ job + multicast (Faz 10.2)
feat(live): StreamStatus enum + status migration + is_live → status geçişi (Faz 11)
```
