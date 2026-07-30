# Açık Artırma Sistemi — Görev Listesi

> **Kaynak:** PLAN.md v2.0  
> **Kapsam:** Backend · Redis · PostgreSQL · ClickHouse · ML · Admin API · Flutter  
> **Durum:** `[ ]` Bekliyor · `[/]` Devam ediyor · `[x]` Tamamlandı

---

## 🔴 P0 — Kritik (Bloğu Kıran Buglar)

### T-01: `system_mute()` metodunu ModerationService'e ekle
**Dosya:** `backend/app/services/moderation_service.py`
- [ ] `system_mute(self, stream_id, user_id, reason)` async metodu yaz
- [ ] `redis.sadd(mute_key(stream_id), str(user_id))` + `expire` ekle
- [ ] `redis.hset(f"shill_mute:{stream_id}", str(user_id), reason)` + `expire(_TTL)` ekle  ← **YENİ Redis key**
- [ ] `publish_mod_event(stream_id, WS.MUTED, user_id, reason=reason, source="system")` çağır
- [ ] Logger: `[MOD] SYSTEM_MUTE | stream_id=... user_id=... reason=...`

### T-02: `place_bid()` içindeki shill mute'u `system_mute()`'a taşı
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py` — L567-569
- [ ] `await redis.sadd(mute_key(stream_id), str(user.id))` satırını kaldır
- [ ] `await ModerationService(self.uow.session).system_mute(stream_id, user.id, reason="shill_bidding")` ile değiştir
- [ ] ModerationService'in bu use case içinde db session olmadan çalışabildiğini doğrula

### T-03: Shill score sabitlerini güncelle
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py` — L71-76
- [ ] `_SHILL_SCORE_IP_MATCH`   : `40` → `30`
- [ ] `_SHILL_SCORE_UNVERIFIED` : `30` → `35`
- [ ] `_SHILL_SCORE_NEW_ACCOUNT`: `20` → `25`
- [ ] `_SHILL_SCORE_REPEAT`     : `15` → `10`
- [ ] `_SHILL_THRESHOLD_MUTE`   : `70` → `80`
- [ ] `_SHILL_THRESHOLD_WARN`   : `40` → `45`
- [ ] Değişiklik sonrası 3 senaryo doğrula (kağıt üzerinde):
  - Verified + eski hesap + aynı IP → mute olmamalı
  - Unverified + yeni hesap + aynı IP → ilk teklifte mute
  - Unverified + eski hesap + aynı IP → WARN, 3-4 teklifte mute

### T-04: Host sistem mute'larını override edebilmeli
**Dosya:** `backend/app/services/moderation_service.py`
- [ ] `unmute()` metoduna `shill_mute:{stream_id}` hash temizlemesini ekle:
  `await redis.hdel(f"shill_mute:{stream_id}", str(target.id))`
- [ ] `_resolve_actors()` içindeki self-check'in sistem mute senaryosunda çalışmamasını doğrula

---

## 🟠 P1 — Yüksek (Mimari + Tracking)

### T-05: `mute_key` import yolunu düzelt
**Dosya:** `backend/app/use_cases/auctions/commands/auction_commands.py` — L512, L714
- [ ] `from app.routers.moderation import mute_key` → `from app.services.moderation_service import mute_key`
- [ ] İki lokasyonu güncelle (L512 ve L714)
- [ ] `app.routers.moderation` re-export'larının (`# noqa: F401`) bozulmadığını doğrula

### T-06: `FraudDetectionService` sınıfını oluştur
**Dosya:** `backend/app/services/fraud_detection_service.py` — **YENİ DOSYA**
- [ ] `FraudDecision(action, score, reason)` dataclass tanımla
- [ ] `FraudDetectionService.evaluate_bid(bidder_ip, host_ip, user, stream_id) -> FraudDecision` metodu yaz
  - Shill score hesaplama mantığını buraya taşı
  - `shill_cnt:{stream_id}:{user_id}` sayaç okuma/yazma buraya taşı
  - `_log_fraud_attempt()` çağrısını buraya ekle
  - `FraudDecision` döndür
- [ ] `place_bid()` içindeki shill blok kodunu kaldır, `FraudDetectionService().evaluate_bid()` çağrısıyla değiştir

### T-07: ClickHouse — Fraud event tracking ekle
**Dosya:** `backend/app/services/fraud_detection_service.py` (T-06 içinde)
- [ ] WARN kararında: `buffer_user_event(event_type="bid_fraud_warn", item_id=stream_id, item_type="stream", user_id=user.id, price_point=amount)`
- [ ] MUTE kararında: `buffer_user_event(event_type="bid_fraud_mute", ...)`

**Dosya:** `backend/app/routers/auction.py`
- [ ] `place_bid` endpoint'inde `BID_BLOCKED_VERIFY` hatasında `buffer_user_event(event_type="bid_blocked_verify", ...)` ekle
  - `try/except` ile yakalanıp event yazılabilir veya exception handler'da

**Etki:** Bu event'ler ClickHouse `user_events` tablosuna düşecek → Trust Score ML beslenecek

### T-08: Admin API — Fraud & Mute yönetim endpoint'leri
**Dosya:** `backend/app/routers/admin_data.py`
- [ ] `GET /api/admin-data/fraud-log` — Redis ZADD `fraud_log` son 50 kaydı döndür
  ```python
  entries = await redis.zrevrange("fraud_log", 0, 49, withscores=True)
  ```
- [ ] `GET /api/admin-data/streams/{stream_id}/mutes` — muted set + shill_mute meta hash döndür
- [ ] `DELETE /api/admin-data/streams/{stream_id}/mutes/{user_id}` — admin force unmute
  - `redis.srem(mute_key(stream_id), str(user_id))`
  - `redis.hdel(f"shill_mute:{stream_id}", str(user_id))`
  - `publish_mod_event()` ile WS event yayınla
- [ ] `DELETE /api/admin-data/shill-counter/{stream_id}/{user_id}` — shill sayacını sıfırla
  - `redis.delete(f"shill_cnt:{stream_id}:{user_id}")`

---

## 🟡 P2 — Orta (ML · DB · Flutter · Log)

### T-09: Trust Score — Fraud sinyali ekle
**Dosya:** `backend/app/worker.py` — `compute_trust_scores_task`
- [ ] ClickHouse sorgusuna fraud event sayılarını ekle:
  ```sql
  countIf(event_type = 'bid_fraud_mute') AS fraud_mutes,
  countIf(event_type = 'bid_fraud_warn') AS fraud_warns
  ```
- [ ] Skor hesabına negatif sinyal ekle:
  ```python
  # fraud_mute >= 3 ise ceza (1-2 false positive için ceza yok)
  fraud_penalty = min(max(0, ch["fraud_mutes"] - 2) * 5, 15)
  total -= _safe(fraud_penalty)
  ```
- [ ] Değişiklik sonrası mevcut kullanıcıların skor dağılımını doğrula

### T-10: PostgreSQL — `user_interactions` fraud indeksi
**Dosya:** Alembic migration veya direkt SQL
- [ ] Migration yaz:
  ```sql
  CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_user_interactions_fraud
  ON user_interactions (user_id, interaction_type, created_at DESC)
  WHERE interaction_type = 'fraud_attempt';
  ```
- [ ] Alembic env ile uygula ve verify et

### T-11: Error handler `user=guest` log bug
**Dosya:** `backend/app/core/error_handlers.py`
- [ ] `DomainError` handler'da `request.state` üzerinden kullanıcı bilgisini oku
- [ ] Authenticated isteklerde `username` doğru loglandığını test et

### T-12: Flutter — Sistem mute WS event mesajı
**Dosya:** `mobile/lib/screens/live/swipe_live_screen.dart` (ve viewer_stream_screen eğer varsa)
- [ ] `MUTED` WS event handler'ında `source` alanını kontrol et:
  ```dart
  if (msg["source"] == "system") {
    TeqToast.warning(loc.t('bidFraudDetected'));
  }
  ```
- [ ] `bidFraudDetected` ARB key'ini tüm dil dosyalarına ekle

### T-13: Flutter — Feed poller guard
**Dosya:** `mobile/lib/screens/live/live_list_screen.dart` veya `swipe_live_screen.dart`
- [ ] Yayın izleniyorken feed update tetiklenince `LIVE_UI_ACTIVE` event'inin atlanmasını sağla
- [ ] `_isInLiveRoom` flag veya aktif stream ID kontrolü ekle

---

## 📋 Doküman Güncellemeleri

### T-14: `auction_architecture.md` güncelle
- [ ] Bölüm 11 (Bilinen Kısıtlar): T-01~T-06 tamamlandıktan sonra "Çözüldü" olarak işaretle
- [ ] Yeni `FraudDetectionService` mimarisini ekle
- [ ] `system_mute()` akışını ve yeni Redis key'ini ekle
- [ ] Yeni ClickHouse event listesini ekle
- [ ] Yeni Admin endpoint'lerini API tablosuna ekle

---

## Bağımlılık Grafiği

```
T-01 (system_mute) ───────────────────────────────────────────────────►
T-02 (place_bid güncelle) ──── T-01 tamamlanmalı ─────────────────────►
T-03 (shill sabitler) ──────── bağımsız ──────────────────────────────►
T-04 (host override) ───────── T-01 tamamlanmalı ─────────────────────►
T-05 (import düzelt) ───────── bağımsız ──────────────────────────────►
T-06 (FraudService) ────────── T-05 sonrası ──────────────────────────►
T-07 (ClickHouse tracking) ─── T-06 içinde ──────────────────────────►
T-08 (Admin API) ───────────── bağımsız ──────────────────────────────►
T-09 (Trust Score ML) ──────── T-07 sonrası (CH event'leri gerekli) ─►
T-10 (PG indeks) ───────────── bağımsız, herhangi bir anda ──────────►
T-11 (log bug) ─────────────── bağımsız ──────────────────────────────►
T-12 (Flutter WS msg) ──────── T-01 sonrası (source field gerekli) ──►
T-13 (Flutter poller) ──────── bağımsız ──────────────────────────────►
T-14 (docs) ────────────────── tüm P0/P1 sonrası ─────────────────────►
```

---

## Etkilenen Dosyalar Özeti

| Dosya | Değişiklik Türü |
|---|---|
| `backend/app/services/moderation_service.py` | `system_mute()` ekle |
| `backend/app/services/fraud_detection_service.py` | **YENİ DOSYA** |
| `backend/app/use_cases/auctions/commands/auction_commands.py` | Import + shill sabitler + system_mute çağrısı |
| `backend/app/routers/admin_data.py` | 4 yeni endpoint |
| `backend/app/core/error_handlers.py` | user context fix |
| `backend/app/worker.py` | compute_trust_scores_task — fraud sinyal |
| `mobile/lib/screens/live/swipe_live_screen.dart` | WS MUTED handler + feed guard |
| `mobile/lib/l10n/*.arb` | `bidFraudDetected` key |
| Alembic migration | `ix_user_interactions_fraud` indeksi |
| `documents/auction/auction_architecture.md` | Güncel mimari dökümantasyonu |

