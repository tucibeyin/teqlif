# Açık Artırma Sistemi — Kapsamlı Refactor Planı

> **Versiyon:** 2.0 — Tüm sistem katmanları dahil  
> **Kaynak:** auction_findings.md + kaynak kod analizi  
> **Kapsam:** Backend · Redis · PostgreSQL · ClickHouse · ML/Trust Score · Admin API · Flutter

---

## Bölüm 1 — Mimari Düzeltmeler (Clean Architecture)

### 1.1 `mute_key` Import Bağımlılığı Düzelt

**Sorun:** `auction_commands.py` içinde `from app.routers.moderation import mute_key` kullanıldı.  
Use Case → Router bağımlılığı; Dependency Rule ihlali.

**Çözüm:** Sadece import yolunu değiştir:
```python
# ÖNCE
from app.routers.moderation import mute_key

# SONRA
from app.services.moderation_service import mute_key
```

---

### 1.2 `ModerationService.system_mute()` Metodu — WS Senkronizasyonu

**Sorun:** `place_bid()` içinde `redis.sadd(mute_key)` çağrısı yapılıyor ama `publish_mod_event()` çağrılmıyor.  
Host client mute'dan haberdar olmuyor → unmute bug'ı.

**Çözüm:** `moderation_service.py`'ye yeni metot:
```python
async def system_mute(self, stream_id: int, user_id: int, reason: str) -> None:
    """Sistem tarafından (shill fraud) tetiklenen mute — WS event dahil."""
    redis = await get_redis()
    await redis.sadd(mute_key(stream_id), str(user_id))
    await redis.expire(mute_key(stream_id), _TTL)
    # Shill kaynaklı olduğunu meta'ya yaz (host override için)
    await redis.hset(f"shill_mute:{stream_id}", str(user_id), reason)
    await redis.expire(f"shill_mute:{stream_id}", _TTL)
    await publish_mod_event(stream_id, WS.MUTED, user_id, reason=reason, source="system")
```

`place_bid()` içindeki direkt Redis yazımı bu metotla değiştirilecek.

**Redis etkileri:**
- `stream:{stream_id}:muted` — mevcut; değişmez
- `shill_mute:{stream_id}` → **YENİ** hash key: `{user_id: reason}`, 24h TTL

---

### 1.3 `FraudDetectionService` — Sorumluluk Ayrımı

**Sorun:** Shill scoring, log yazımı, sayaç yönetimi hepsi `place_bid()` içine gömülü.

**Çözüm:** `backend/app/services/fraud_detection_service.py` oluştur:
```python
@dataclass
class FraudDecision:
    action: Literal["allow", "warn", "mute"]
    score: int
    reason: str

class FraudDetectionService:
    async def evaluate_bid(
        self, bidder_ip, host_ip, user, stream_id
    ) -> FraudDecision: ...
```

`place_bid()` sadece kararı tüketir:
```python
decision = await FraudDetectionService().evaluate_bid(...)
if decision.action == "mute":
    await ModerationService(self.uow.session).system_mute(...)
    raise ForbiddenException(code="BID_BLOCKED_MUTE")
```

---

## Bölüm 2 — Shill Bidding Algoritması

### 2.1 Score Sabitleri — False Positive Düzeltmesi

**Mevcut:** Verified + köklü hesap 3 teklifte mute eşiğine ulaşıyor (IP tek başına dominat).

```python
# MEVCUT
_SHILL_SCORE_IP_MATCH   = 40
_SHILL_SCORE_UNVERIFIED = 30
_SHILL_SCORE_NEW_ACCOUNT = 20
_SHILL_SCORE_REPEAT     = 15   # max 2x = 30
_SHILL_THRESHOLD_MUTE   = 70   # IP(40)+prior_2(30) = 3 teklifte mute

# ÖNERİLEN
_SHILL_SCORE_IP_MATCH    = 30  # Düşürüldü: tek başına dominat olmamalı
_SHILL_SCORE_UNVERIFIED  = 35  # Yükseltildi: doğrulanmamış + IP ciddi sinyal
_SHILL_SCORE_NEW_ACCOUNT = 25  # Hafif yükseltildi
_SHILL_SCORE_REPEAT      = 10  # Azaltıldı: daha yavaş birikim
_SHILL_THRESHOLD_MUTE    = 80  # Yükseltildi: daha zor aşılır
_SHILL_THRESHOLD_WARN    = 45  # Eşzamanlı güncelleme
```

**Simülasyon sonuçları (verified + eski hesap, aynı IP):**
```
Teklif 1: IP(+30) → 30 — WARN eşiği altı, tamamen geçer
Teklif 2: IP(+30) + prior_1(+10) = 40 — Eşiğin altı, geçer
Teklif 3: IP(+30) + prior_2(+20) = 50 — WARN eşiği altı, geçer
Teklif 4: IP(+30) + prior_3(+30)* = 60 — Eşiğin altı, geçer
         (*max 30 çünkü repeat max 3x10=30)
```
→ Verified + eski hesap artık sadece IP üzerinden asla mute edilmez.

**Simülasyon (unverified + yeni hesap, aynı IP):**
```
Teklif 1: IP(+30) + unverified(+35) + new(+25) = 90 → MUTE (ilk teklifte)
```
→ Gerçek şüpheli senaryolarda hâlâ etkili.

### 2.2 Shill Mute Geri Alınabilirliği

`system_mute()` meta hash sayesinde host unmute yapabilir:
```python
# ModerationService.unmute() içinde
await redis.hdel(f"shill_mute:{stream_id}", str(target.id))
```

---

## Bölüm 3 — ClickHouse Tracking Boşlukları

### 3.1 Mevcut Durum
| Event | Şu an track ediliyor mu? | Nerede? |
|---|---|---|
| `bid_placed` | ✅ | `auction.py` router, `buffer_user_event` |
| `auction_won` | ✅ | `accept_bid()`, `accept_buy_it_now()` |
| `auction_ended` | ✅ | `end_auction()` |
| `listing_sold` | ✅ | `accept_bid()` |
| `bid_blocked_shill` | ❌ **YOK** | — |
| `bid_blocked_verify` | ❌ **YOK** | — |
| `bid_rate_limited` | ❌ **YOK** | — |
| `system_mute_applied` | ❌ **YOK** | — |
| `shill_warn` | ❌ **YOK** | — |

### 3.2 Eklenecek Event'ler

`FraudDetectionService.evaluate_bid()` kararını ClickHouse'a yazacak:

```python
# warn kararında
await buffer_user_event(
    event_type="bid_fraud_warn",
    item_id=stream_id,
    item_type="stream",
    user_id=user.id,
    price_point=float(data.amount),
)

# mute kararında
await buffer_user_event(
    event_type="bid_fraud_mute",
    item_id=stream_id,
    item_type="stream",
    user_id=user.id,
    price_point=float(data.amount),
)
```

`auction.py` router'da, başarılı bid dışında reject durumları da:
```python
# Hız sınırı aşıldığında
await buffer_user_event(event_type="bid_rate_limited", ...)
# Verify eksikse
await buffer_user_event(event_type="bid_blocked_verify", ...)
```

**Faydası:** Trust score ve ML modelleri bu sinyalleri kullanabilecek.

---

## Bölüm 4 — Trust Score Sistemi Etkisi

### 4.1 Mevcut Sinyaller (compute_trust_scores_task)
```
Sinyal 1: Tamamlanan artırma sayısı      → auction_won + auction_ended (ClickHouse)
Sinyal 2: Kazanım oranı                  → auction_won / total
Sinyal 3: Aktif ilan sürümlülüğü         → PostgreSQL
Sinyal 4: Hesap yaşı                     → PostgreSQL
Sinyal 5: Düşük bid_hesitation oranı     → ClickHouse
```

### 4.2 False Positive Etkisi (Şu anki sorun)
`teqlif` shill mute ile bloke edildi → artırma tamamlanamadı → `auction_ended` event'i yazılmadı → Trust Score hesabında kayıp. **Meşru kullanıcı haksız yere trust score kaybediyor.**

### 4.3 Önerilen Sinyal Eklentisi

`compute_trust_scores_task`'e **fraud warn/mute sayısı** eklenmeli, ama dikkatli:

```python
# Negatif sinyal: çok sayıda fraud warn varsa güven azalır
fraud_warn_count = countIf(event_type = 'bid_fraud_warn')
fraud_mute_count = countIf(event_type = 'bid_fraud_mute')

# Ceza sadece yüksek fraud_mute sayısında (>=3) uygulanır
# 1-2 fraud_warn ceza vermez (false positive koruması)
fraud_penalty = min(fraud_mute_count * 5, 15)  # max -15 puan
```

Bu, gerçek shill yapanları cezalandırır ama yanlışlıkla mute edilenlere zarar vermez.

---

## Bölüm 5 — Admin API Eksiklikleri

### 5.1 Mevcut Admin Yetenekleri
`/api/admin-data` altında:
- Kullanıcı yönetimi (suspend/verify)
- Stream yönetimi (aktif stream'leri bitir)
- İlan yönetimi
- Raporlar
- TUCi airdrop
- Push notification

### 5.2 Eksik: Fraud/Shill Mute Yönetimi
Admin şu an `fraud_log` (Redis ZADD) okuyamıyor. Hiçbir admin endpoint'i yok:
- Fraud log görüntüleme
- Shill mute'ları listeleme/kaldırma
- Belirli bir kullanıcı/stream için shill sayacını sıfırlama

**Eklenecek endpoint'ler** (`/api/admin-data`'ya):

```
GET  /api/admin-data/fraud-log              → Son N fraud kaydı
GET  /api/admin-data/streams/{id}/mutes     → Stream mute listesi (sistem + manuel ayrımı)
DEL  /api/admin-data/streams/{id}/mutes/{user_id} → Admin force unmute
DEL  /api/admin-data/shill-counter/{stream_id}/{user_id} → Shill sayacını sıfırla
```

### 5.3 Eksik: Host Unmute API Düzeltmesi
`POST /api/moderation/{stream_id}/unmute` — host sistem mute'larını override edebilmeli.  
`_resolve_actors()` self-check aynı kalır; ama shill_mute meta hash kontrolü eklenmeli.

---

## Bölüm 6 — PostgreSQL DB Değişiklikleri

### 6.1 Mevcut Durum
Fraud girişimleri şu an:
- Redis ZADD `fraud_log` (30 günlük)
- PostgreSQL `user_interactions` tablosuna `fraud_attempt` (auction_utils._log_fraud_attempt)

### 6.2 Öneri: Dedicated Fraud Events Tablosu (Opsiyonel)

Mevcut `user_interactions` tablo yeterli mi? Evet — `interaction_type="fraud_attempt"` zaten kaydediliyor. Ancak admin sorgulaması için indeks eksik.

```sql
-- Mevcut tablo için indeks ekle (yeni tablo gerekmez)
CREATE INDEX CONCURRENTLY IF NOT EXISTS
  ix_user_interactions_fraud
  ON user_interactions (user_id, interaction_type, created_at DESC)
  WHERE interaction_type = 'fraud_attempt';
```

### 6.3 `shill_mute` Bilgisi Redis'te Kalmalı

DB'ye taşımak gerekmez. Redis `shill_mute:{stream_id}` hash key ile stream TTL'ine bağlı yaşar. Stream bitince otomatik temizlenir.

---

## Bölüm 7 — Flutter UX Düzeltmeleri

### 7.1 LIVE_UI_ACTIVE Döngüsü

**Sorun:** Feed poller yayın izlerken çalışmaya devam ediyor; her çağrıda `LIVE_UI_ACTIVE` event'i tetikleniyor. Navigation stack sürekli yeniden inşa ediliyor.

**Çözüm:** `swipe_live_screen.dart` / `live_list_screen.dart` içindeki feed poller'a guard:
```dart
// Yayın izleniyorsa feed update event'inden stream güncellemesini atla
if (_isInLiveRoom && streams.any((s) => s.id == _currentStreamId)) return;
```

### 7.2 Sistem Mute WS Event İşlenmeli

`swipe_live_screen.dart` içindeki WS handler'a `reason=system` gelen `MUTED` event'i işlenmeli:
```dart
case "muted":
  final source = msg["source"];
  if (source == "system") {
    // "Şüpheli teklif tespit edildi" mesajı göster
    TeqToast.warning(loc.t('bidFraudDetected'));
  }
  break;
```

---

## Bölüm 8 — Öncelik Matrisi

| # | Bileşen | Değişiklik | Etki | Öncelik |
|---|---|---|---|---|
| 1 | `moderation_service.py` | `system_mute()` + WS event + meta hash | Host unmute bug düzelir | 🔴 P0 |
| 2 | `auction_commands.py` | Shill score sabitleri güncelle | False positive önlenir | 🔴 P0 |
| 3 | `auction_commands.py` | Direkt Redis → `system_mute()` | Mimari tutarlılık | 🔴 P0 |
| 4 | `auction_commands.py` | Import yolu düzelt | Clean Arch uyumu | 🟠 P1 |
| 5 | `fraud_detection_service.py` | Yeni servis | Test edilebilirlik | 🟠 P1 |
| 6 | `database_clickhouse.py` | Fraud event tracking ekle | ML/Trust Score beslemesi | 🟠 P1 |
| 7 | `admin_data.py` | Fraud log + mute yönetim endpoint'leri | Admin operasyon | 🟠 P1 |
| 8 | `worker.py` | Trust score'a fraud sinyali ekle | ML kalitesi | 🟡 P2 |
| 9 | `user_interactions` indeks | PostgreSQL fraud index | Sorgu performansı | 🟡 P2 |
| 10 | `error_handlers.py` | `user=guest` log bug | Log kalitesi | 🟡 P2 |
| 11 | Flutter WS handler | `reason=system` mute mesajı | UX netliği | 🟡 P2 |
| 12 | Flutter feed poller | Guard ekle | Navigation tutarlılığı | 🟡 P2 |

