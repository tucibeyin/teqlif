# VoIP Görev Listesi

> Öncelik sırası: P0 → P1 → P2 → P3  
> Hedef: WhatsApp kalitesinde güvenilir ses, doğru UX feedback, temiz mimari

---

## P0 — Acil (Kullanıcıya Bloke Edici)

### ✅ T1: iOS Ringback Geri Yükleme — `connecting` Durumunu Dahil Et

**Bulgu:** F1 | **Durum:** TAMAMLANDI  
`call_service.dart` ~1484: restore bloğu `calling || connecting` koşuluna genişletildi. `postConnectStatus` değişkeni alınarak `room.connect()` tamamlandığında anlık durum doğru kontrol ediliyor.

---

### ✅ T2: Android Caller Ringback — Audio Focus Guard Eklendi

**Bulgu:** F4 | **Durum:** TAMAMLANDI  
`call_service.dart`: Android pre-publish'ten 200ms sonra `_ringbackPlayer.state != playing` kontrolü eklendi; kesilmişse yeniden başlatılıyor. Backend olmayan ortamlarda da log üretiliyor → ileride cihazda doğrulanabilir.

---

## P1 — Ciddi (Kullanıcıya Görünür)

### ✅ T3: `TrackSubscribed` → `connected` Geçişinde `isMuted` Kontrolü

**Bulgu:** F3 | **Durum:** TAMAMLANDI  
`call_service.dart`: `event.publication.muted` true ise erken return → `TrackUnmuted`'ı bekle. Gerçek ses akışı olmadan `connected` state'e geçiş engellendi.

---

### ✅ T4: `connecting` Durumunda UI "Bağlanıyor" Göster

**Bulgu:** F14 | **Durum:** ZATEN UYGULANMIŞTI  
`call_screen.dart` + localization: `CallStatus.connecting → loc.t('callConnecting')` → "Bağlanıyor..." — değişiklik gerekmedi.

---

### ✅ T5: `livekit_url` Tek Kaynak

**Bulgu:** F7 | **Durum:** KOD ZATEN DOĞRU  
Tüm `livekit_url` referansları `settings.livekit_url`'dan geliyor. Test loglarındaki farklı URL, VPS `.env`'nin farklı değer içermesinden kaynaklanıyor — kod değişikliği gerekmedi.

---

### ✅ T6: Backend'e `call_connected` Olayı + `connected_at` Alanı Ekle

**Bulgu:** F10 | **Durum:** TAMAMLANDI  
- `call.py`: `connected_at: Optional[datetime]` alanı eklendi  
- `calls.py`: `POST /calls/{id}/connected` endpoint eklendi; ilk çağrıda `connected_at` damgalanıyor  
- `end_call`: `connected_at` varsa `duration_seconds = ended_at - connected_at` kullanıyor  
- `call_service.dart`: `_transitionToConnected()` helper içinden otomatik `POST /calls/{id}/connected` çağrısı yapılıyor  
- **⚠️ VPS'te aşağıdaki SQL çalıştırılmalı:**

```sql
ALTER TABLE calls ADD COLUMN IF NOT EXISTS connected_at TIMESTAMP WITH TIME ZONE;
```

---

## P2 — Orta

### ✅ T7: `clear_call_redis()` Her Çıkış Yolunda

**Bulgu:** F9 | **Durum:** TAMAMLANDI  
- `calls.py` import'a `clear_call_redis` eklendi  
- `reject_call`, `end_call`, `missed_call` — her biri `try/except` ile `clear_call_redis` çağırıyor  
- `worker.py` `delayed_call_timeout_task` — commit sonrası `clear_call_redis` eklendi

---

### ✅ T8: Accept Endpoint Token Gen Gecikme Logu

**Bulgu:** F2, F6 | **Durum:** TAMAMLANDI  
`calls.py` accept endpoint: `time.monotonic()` ile `_make_livekit_token()` süresi ölçüldü → `token_gen_ms` log'a eklendi. Sonraki testlerde gecikme kaynağı tespit edilebilir.

---

### ✅ T9: Remote Katılımcı Bağlantı Kalitesi Takibi

**Bulgu:** F17 | **Durum:** KISMİ — LiveKit katmanında uygulandı  
`call_service.dart`: `ParticipantConnectionQualityUpdatedEvent` artık hem local hem remote katılımcı için `isPoorConnection` güncelliyor. Remote bağlantısı kopunca peer tarafında da zayıf bağlantı göstergesi devreye giriyor.  
Backend WS sinyali (`call_reconnecting` event) ileride eklenebilir; mevcut LiveKit kalite eventi çoğu durumda yeterli.

---

### ✅ T10: Timeout Tutarlılığı

**Bulgu:** F13 | **Durum:** TAMAMLANDI  
`calls.py`: `_CALL_RING_TIMEOUT = 30` + `_CALL_RING_TIMEOUT_BACKUP = 40` sabitleri eklendi. ARQ `delayed_call_timeout_task` 60s yerine artık `_CALL_RING_TIMEOUT_BACKUP` (40s) ile enqueue ediliyor. Flutter'ın 30s timer'ından 10s sonra backup devreye giriyor.

---

## P3 — Temizlik / UX İyileştirme

### ✅ T11: Ringback Durdurma Merkezi — T12 ile Kapsandı

**Bulgu:** F16 | **Durum:** T12 ile ÇÖZÜLDİ  
`_transitionToConnected()` helper'ı `stopRingtoneAndVibration()` çağırıyor. TrackSubscribed/TrackUnmuted handler'larından doğrudan ringback durduran kod kaldırıldı.

---

### ✅ T12: `_transitionToConnected()` Merkezi Helper

**Bulgu:** F15 | **Durum:** TAMAMLANDI  
`call_service.dart`: `_transitionToConnected(context: String)` yeni metodu eklendi. İçinde:
- `stopRingtoneAndVibration()`
- `_setState(connected, acceptedAt: _acceptedAt)`
- `_startElapsedTimer()`, `_startProximitySensor()`, `_startStatsMonitor()`, `_startNetworkMonitor()`
- `POST /calls/{id}/connected` (T6)

4 farklı çağrı noktası (`peerAlreadyJoined`, `TrackSubscribed`, `TrackUnmuted`, `_activateCalleeAudio`) bu helper'a yönlendirildi.

---

### ✅ T13: `call_ended_sent` NX Lock TTL → 300s

**Bulgu:** F8 | **Durum:** TAMAMLANDI  
`calls.py` end_call: `ex=60` → `ex=300` (5 dakika). Duplikasyon penceresi 5 dakikaya uzatıldı.

---

## Özet Tablo

| # | Öncelik | Başlık | Durum |
|---|---|---|---|
| T1 | P0 | iOS ringback restore `connecting` dahil | ✅ |
| T2 | P0 | Android pre-publish audio focus guard | ✅ |
| T3 | P1 | `TrackSubscribed` muted check | ✅ |
| T4 | P1 | UI `connecting` → "Bağlanıyor" | ✅ (zaten vardı) |
| T5 | P1 | `livekit_url` tek kaynak | ✅ (kod zaten doğruydu) |
| T6 | P1 | `connected_at` + `/connected` endpoint | ✅ (SQL VPS'te çalıştırılmalı) |
| T7 | P2 | `clear_call_redis` tutarlılık | ✅ |
| T8 | P2 | Accept token_gen_ms logu | ✅ |
| T9 | P2 | Remote kalite takibi (reconnecting UX) | ✅ kısmi |
| T10 | P2 | Timeout sabitleri 40s backup | ✅ |
| T11 | P3 | Ringback merkezileştirme | ✅ (T12 ile) |
| T12 | P3 | `_transitionToConnected()` helper | ✅ |
| T13 | P3 | NX TTL 300s | ✅ |

---

## VPS'te Yapılacaklar

```sql
-- T6: connected_at alanı (migration olmadan doğrudan ALTER TABLE)
ALTER TABLE calls ADD COLUMN IF NOT EXISTS connected_at TIMESTAMP WITH TIME ZONE;
```

Ardından: `git pull && sudo systemctl restart teqlif`
