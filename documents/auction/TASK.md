# Açık Artırma Sistemi — Görev Listesi

> **Kaynak:** PLAN.md v2.0  
> **Kapsam:** Backend · Redis · PostgreSQL · ClickHouse · ML · Admin API · Flutter  
> **Durum:** `[ ]` Bekliyor · `[/]` Devam ediyor · `[x]` Tamamlandı

---

## 🔴 P0 — Kritik (Bloğu Kıran Buglar)

### T-01: `system_mute()` metodunu ModerationService'e ekle
**Dosya:** `backend/app/services/moderation_service.py`
- [x] `system_mute(self, stream_id, user_id, reason)` async metodu yaz
- [x] `redis.sadd(mute_key(stream_id), str(user_id))` + `expire` ekle
- [x] `redis.hset(f"shill_mute:{stream_id}", str(user_id), reason)` + `expire(_TTL)` ekle  ← **YENİ Redis key**
- [x] `publish_mod_event(stream_id, WS.MUTED, user_id, reason=reason, source="system")` çağır
- [x] Logger: `[MOD] SYSTEM_MUTE | stream_id=... user_id=... reason=...`

### T-02: `place_bid()` içindeki shill mute'u `system_mute()`'a taşı
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py` — L567-569
- [x] `await redis.sadd(mute_key(stream_id), str(user.id))` satırını kaldır
- [x] `await ModerationService(self.uow.session).system_mute(stream_id, user.id, reason="shill_bidding")` ile değiştir
- [x] ModerationService.system_mute() self.db kullanmıyor — session geçmek zararsız ✅

### T-03: Shill score sabitlerini güncelle
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py` — L71-76
- [x] `_SHILL_SCORE_IP_MATCH`   : `40` → `30`
- [x] `_SHILL_SCORE_UNVERIFIED` : `30` → `35`
- [x] `_SHILL_SCORE_NEW_ACCOUNT`: `20` → `25`
- [x] `_SHILL_SCORE_REPEAT`     : `15` → `10`
- [x] `_SHILL_THRESHOLD_MUTE`   : `70` → `80`
- [x] `_SHILL_THRESHOLD_WARN`   : `40` → `45`
- [x] Senaryo doğrulaması:
  - Verified + eski hesap + aynı IP: maks 30+20=50 → asla 80'e ulaşmaz ✅
  - Unverified + yeni hesap + aynı IP: 30+35+25=90 → ilk teklifte mute ✅
  - Unverified + eski hesap + aynı IP: teklif 3'te 30+35+20=85 → mute ✅

### T-04: Host sistem mute'larını override edebilmeli
**Dosya:** `backend/app/services/moderation_service.py`
- [x] `unmute()` metoduna `redis.hdel(f"shill_mute:{stream_id}", str(target.id))` eklendi
- [x] `_resolve_actors()` self-check `STREAM_MOD_SELF_FORBIDDEN` — sistem mute'unda host, kendi kendini hedef almaz (farklı user_id) ✅

---

## 🟠 P1 — Yüksek (Mimari + Tracking)

### T-05: `mute_key` import yolunu düzelt ✅
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py`
- [x] `from app.routers.moderation import mute_key` lazy importlar kaldırıldı (2 lokasyon)
- [x] Modül seviyesinde `from app.services.moderation_service import mute_key` eklendi
- [x] Router re-export'ları (`# noqa: F401`) bozulmadı

### T-06: `FraudDetectionService` sınıfını oluştur ✅
**Dosya:** `backend/app/services/fraud_detection_service.py` — **YENİ DOSYA**
- [x] `FraudDecision(action, score, reason)` dataclass tanımlandı
- [x] `FraudDetectionService.evaluate_bid(stream_id, user, bidder_ip, host_ip, amount) -> FraudDecision` yazıldı
  - Shill score hesaplama mantığı taşındı
  - `shill_cnt:{stream_id}:{user_id}` sayaç okuma/yazma taşındı
  - `_log_fraud_attempt()` (Redis ZADD) taşındı ve fraud_detection_service'te tanımlandı
  - `FraudDecision(PASS/WARN/MUTE)` döndürülüyor
- [x] `place_bid()` shill bloğu kaldırıldı → `FraudDetectionService(self.uow.session).evaluate_bid()` kullanılıyor
- [x] auction_utils'ten `_log_fraud_attempt` import'u kaldırıldı (eski imza çakışması temizlendi)

### T-07: ClickHouse — Fraud event tracking ekle ✅
**Dosya:** `backend/app/services/fraud_detection_service.py`
- [x] WARN: `track_user_event(event_type="bid_fraud_warn", ...)`
- [x] MUTE: `track_user_event(event_type="bid_fraud_mute", ...)`

**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py`
- [x] `BID_BLOCKED_VERIFY` öncesi `track_user_event(event_type="bid_blocked_verify", ...)` eklendi

**Etki:** Bu event'ler ClickHouse `user_events` tablosuna düşecek → Trust Score ML beslenecek

### T-08: Admin API — Fraud & Mute yönetim endpoint'leri ✅
**Dosya:** `backend/app/routers/admin_data.py`
- [x] `GET /api/admin-data/fraud-log` — Redis ZADD `fraud_log` son 50 kaydı döndür (limit query param, max 200)
- [x] `GET /api/admin-data/streams/{stream_id}/mutes` — muted set + shill_mute meta hash + TTL döndür
- [x] `DELETE /api/admin-data/streams/{stream_id}/mutes/{user_id}` — admin force unmute
  - `redis.srem(mute_key(stream_id), str(user_id))`
  - `redis.hdel(f"shill_mute:{stream_id}", str(user_id))`
  - `publish_mod_event()` ile WS UNMUTED event yayınla (source="admin")
- [x] `DELETE /api/admin-data/shill-counter/{stream_id}/{user_id}` — shill sayacını sıfırla

---

## 🟡 P2 — Orta (ML · DB · Flutter · Log)

### T-09: Trust Score — Fraud sinyali ekle ✅
**Dosya:** `backend/app/worker.py` — `compute_trust_scores_task`
- [x] ClickHouse sorgusuna `fraud_mutes` ve `fraud_warns` kolonları eklendi
- [x] result_rows unpack ve ch_data dict güncellendi
- [x] Skor hesabına negatif sinyal eklendi: `fraud_penalty = min(max(0, fraud_mutes - 2) * 5, 15)` (max -15 puan)
- [ ] Değişiklik sonrası mevcut kullanıcıların skor dağılımını doğrula (deploy sonrası 02:15'te çalışır)

### T-10: PostgreSQL — `user_interactions` fraud indeksi ✅
**Dosya:** Direkt SQL (VPS'te çalıştırıldı)
- [x] `ix_user_interactions_fraud` oluşturuldu (kısmi indeks, WHERE interaction_type = 'fraud_attempt')

### T-11: Error handler `user=guest` log bug ✅
**Dosya:** `backend/app/utils/auth.py` + `backend/app/core/error_handlers.py`
- [x] `get_current_user`'a `request: Request` parametresi eklendi; `request.state.user = user` set ediliyor
- [x] `error_handlers.py`'de `user_label = @username#id` formatına geçildi (her iki handler)

### T-12: Flutter — Sistem mute WS event mesajı ✅
**Dosya:** `mobile/lib/widgets/chat_panel.dart`
- [x] `muted` WS event handler'ında `source == 'system'` kontrolü eklendi
- [x] `TeqToast.warning(loc.t('bidFraudDetected'))` çağrısı eklendi
- [x] `teq_toast.dart` import'u eklendi
- [ ] `bidFraudDetected` key'i translations tablosuna eklenmeli (SQL aşağıda)

### T-13: Flutter — Feed poller guard
**Dosya:** `mobile/lib/screens/live/live_list_screen.dart` veya `swipe_live_screen.dart`
- [ ] Yayın izleniyorken feed update tetiklenince `LIVE_UI_ACTIVE` event'inin atlanmasını sağla
- [ ] `_isInLiveRoom` flag veya aktif stream ID kontrolü ekle

---

## 🔵 Ek Bulgular (F-07 ~ F-11)

### T-15: `stream:{stream_id}:muted` — TTL Fix
**Dosya:** `backend/app/services/moderation_service.py`  
**Not:** T-01 (`system_mute()`) uygulanınca otomatik çözülür — `system_mute()` içinde `expire()` çağrısı var. T-01 ile birlikte tamamlanmış sayılır.
- [ ] T-01 uygulandıktan sonra `stream:{stream_id}:muted` set'inin TTL aldığını doğrula
- [ ] Eski stream key'lerinin temizlenip temizlenmediğini Redis'te kontrol et (opsiyonel tek seferlik cleanup script)

### T-16: `auction_commands.py` — `push_notification` Router Import Düzelt ✅
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py`
- [x] `push_notification` fonksiyonu `app.routers.notifications`'dan `app.services.notification_service`'e taşındı
- [x] `from app.routers.notifications import push_notification` lazy importlar kaldırıldı (3 lokasyon)
- [x] Modül seviyesinde `from app.services.notification_service import push_notification` eklendi
- [x] `notifications.py` re-export ile geriye dönük uyumluluk korundu

### T-17: PostgreSQL — Artırma Sorgu İndeksleri ✅
**Dosya:** Direkt SQL (VPS'te çalıştırıldı)
- [x] `ix_bids_bidder_id` — zaten vardı
- [x] `ix_auctions_winner_id` — zaten vardı
- [x] `ix_purchases_buyer_type` — yeni oluşturuldu
- [x] `ix_purchases_auction_id` — zaten vardı

### T-18: ClickHouse — BIN Flow ve Pause/Resume Event Tracking
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py`
- [ ] `accept_buy_it_now()` içine `buy_it_now_accepted` event ekle
  `buffer_user_event(event_type="buy_it_now_accepted", item_id=stream_id, item_type="stream", user_id=buyer_id, price_point=bin_price)`
- [ ] `reject_buy_it_now()` içine `buy_it_now_rejected` event ekle  
  `buffer_user_event(event_type="buy_it_now_rejected", item_id=stream_id, item_type="stream", user_id=buyer_id, price_point=bin_price)`
- [ ] `pause_auction()` içine `auction_paused` event ekle
- [ ] `resume_auction()` içine `auction_resumed` event ekle
- [ ] Tüm event type'ları `PLAN.md Bölüm 10`'da belgelenmiş olarak işaretle
- [ ] T-07 kapsamına dahil edilebilir (aynı tracking görevi)

---

## 📋 Doküman Güncellemeleri

### T-14: `auction_architecture.md` güncelle
- [x] Bölüm 13 (PostgreSQL Derinlemesine) — eklendi
- [x] Bölüm 14 (Redis Key Haritası / TTL Envanteri) — eklendi
- [x] Bölüm 15 (Analytics ve Tracking Katmanı) — eklendi
- [x] Bölüm 16 (ML / AI Fırsatları) — eklendi
- [x] Bölüm 12 (Bilinen Kısıtlar): F-07~F-10 eklendi
- [ ] Bölüm 12: T-01~T-06 tamamlandıktan sonra çözülen sorunları "Çözüldü" olarak işaretle
- [ ] Yeni `FraudDetectionService` mimarisini ekle (T-06 uygulandıktan sonra)
- [ ] Yeni Admin endpoint'lerini API tablosuna ekle (T-08 uygulandıktan sonra)

---

## Bağımlılık Grafiği (Güncellenmiş)

```
T-01 (system_mute + TTL) ─────────────────────────────────────────────►
T-02 (place_bid güncelle) ──── T-01 tamamlanmalı ─────────────────────►
T-03 (shill sabitler) ──────── bağımsız ──────────────────────────────►
T-04 (host override) ───────── T-01 tamamlanmalı ─────────────────────►
T-05 (mute_key import düzelt) ─ bağımsız ─────────────────────────────►
T-16 (push_notification import)─ T-05 ile birlikte ──────────────────►
T-06 (FraudService) ────────── T-05 sonrası ──────────────────────────►
T-07 (ClickHouse fraud track.)── T-06 içinde ────────────────────────►
T-18 (ClickHouse BIN/pause)──── T-07 ile birlikte ───────────────────►
T-08 (Admin API) ───────────── bağımsız ──────────────────────────────►
T-09 (Trust Score ML) ──────── T-07 sonrası (CH event'leri gerekli) ─►
T-10 (PG fraud index) ──────── bağımsız, herhangi bir anda ──────────►
T-17 (PG artırma indeksler) ─── T-10 ile birleştirilebilir ──────────►
T-15 (muted set TTL check) ──── T-01 sonrası doğrulama ─────────────►
T-11 (log bug) ─────────────── bağımsız ──────────────────────────────►
T-12 (Flutter WS msg) ──────── T-01 sonrası (source field gerekli) ──►
T-13 (Flutter poller) ──────── bağımsız ──────────────────────────────►
T-14 (docs) ────────────────── tüm P0/P1 sonrası ─────────────────────►
```

---

## Etkilenen Dosyalar Özeti (Güncellenmiş)

| Dosya | Değişiklik Türü |
|---|---|
| `backend/app/services/moderation_service.py` | `system_mute()` + TTL ekle |
| `backend/app/services/fraud_detection_service.py` | **YENİ DOSYA** |
| `backend/app/use_cases/auctions/commands/auction_commands.py` | Import (×2) + shill sabitler + system_mute + BIN/pause events |
| `backend/app/routers/admin_data.py` | 4 yeni endpoint |
| `backend/app/core/error_handlers.py` | user context fix |
| `backend/app/worker.py` | compute_trust_scores_task — fraud sinyal |
| `mobile/lib/screens/live/swipe_live_screen.dart` | WS MUTED handler + feed guard |
| `mobile/lib/l10n/*.arb` | `bidFraudDetected` key |
| Alembic migration | `ix_user_interactions_fraud` + 4 artırma sorgu index |
| `documents/auction/auction_architecture.md` | Bölüm 13-16 eklendi ✅ |

