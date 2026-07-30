# Açık Artırma Sistemi — Test Senaryoları

> **Format:** Her task için: ön koşul → adımlar → beklenen sonuç → Redis doğrulama  
> **Redis komutları:** VPS'te `redis-cli` ile çalıştır  
> **Log takibi:** `sudo journalctl -u teqlif -f` ile canlı log izle

---

## T-01 + T-02 + T-03 — Shill Mute Sistemi

> **Değişiklikler:** `system_mute()` metodu, shill score sabitleri, WS event

### Senaryo A — Verified + Eski Hesap + Aynı IP (False Positive Koruması)

**Amaç:** Verified ve köklü hesap, aynı ağdan bağlansa bile hiçbir zaman otomatik mute edilmemeli.

**Ön koşul:**
- İki cihaz veya iki tarayıcı sekmesi aynı ağdan (aynı Wi-Fi/NAT) bağlı
- `teqlif` kullanıcısı: verified (telefon doğrulanmış), hesap yaşı > 7 gün
- `tesbih` kullanıcısı: canlı yayın açık, artırma başlatılmış

**Adımlar:**
1. `teqlif` kullanıcısı ile yayına gir
2. Artırmaya teklif ver (₺25)
3. Teklif ver (₺50)
4. Teklif ver (₺75)
5. Teklif ver (₺100)
6. Teklif ver (₺150)

**Beklenen sonuç:**
- Tüm teklifler `HTTP 200` ile kabul edilmeli
- Kullanıcı hiçbir zaman mute edilmemeli
- Logda `shill_score` değerleri: 30 → 40 → 50 → 50 → 50 (eşik 80'e ulaşmaz)

**Redis doğrulaması (VPS'te):**
```bash
# Stream ID'yi log'dan veya API'den bul
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 0  ← mute edilmedi
```

---

### Senaryo B — Unverified + Yeni Hesap + Aynı IP (İlk Teklifte Mute)

**Amaç:** Şüpheli profil (doğrulanmamış + yeni hesap) aynı ağdan bağlandığında ilk teklifte mute edilmeli.

**Ön koşul:**
- `testuser_yeni` adında test hesabı: email/telefon doğrulanmamış, hesap yaşı < 7 gün
- Host ile aynı ağdan bağlı (aynı Wi-Fi)
- Canlı yayında artırma aktif

**Adımlar:**
1. `testuser_yeni` ile yayına gir
2. Artırmaya bir teklif ver

**Beklenen sonuç:**
- `HTTP 403 BID_BLOCKED_MUTE` hatası
- Log satırı:
  ```
  [MOD] SYSTEM_MUTE | stream_id=X user_id=Y reason=shill_bidding
  [FRAUD_ATTEMPT] type=shill_bidding stream_id=X user_id=Y
  ```
- Host client'ında kullanıcı mute göstergesi görünmeli (WS MUTED event — source="system")

**Redis doğrulaması:**
```bash
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 1  ← mute edildi

HGET shill_mute:{stream_id} {user_id}
# Beklenen: "shill_bidding"

TTL stream:{stream_id}:muted
# Beklenen: 0–86400 arası pozitif sayı  ← TTL set edilmiş (eskiden -1 dönerdi)

TTL shill_mute:{stream_id}
# Beklenen: 0–86400 arası pozitif sayı
```

---

### Senaryo C — Unverified + Eski Hesap + Aynı IP (3. Teklifte Mute)

**Amaç:** Doğrulanmamış ama köklü hesap, 3. teklifte mute edilmeli.

**Ön koşul:**
- `testuser_eski` adında test hesabı: email/telefon doğrulanmamış, hesap yaşı > 7 gün
- Host ile aynı ağdan bağlı

**Adımlar:**
1. `testuser_eski` ile yayına gir
2. Teklif 1 ver → `HTTP 200` + log `shill_score=65` beklenir (WARN eşiği 45'i geçer)
3. Teklif 2 ver → `HTTP 200` + log `shill_score=75` beklenir (WARN)
4. Teklif 3 ver → `HTTP 403 BID_BLOCKED_MUTE` + log `shill_score=85`

**Beklenen sonuç:**
- Teklif 1 ve 2 geçer (WARN, sayaç artar)
- Teklif 3 bloke edilir
- `[MOD] SYSTEM_MUTE` log satırı görünür

**Redis doğrulaması:**
```bash
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 1

GET shill_cnt:{stream_id}:{user_id}
# Beklenen: "2"  ← 2 WARN birikmiş

TTL stream:{stream_id}:muted
# Beklenen: pozitif sayı (TTL set edilmiş)
```

---

## T-04 — Host Shill Mute'u Kaldırabilmeli

**Amaç:** Senaryo B veya C ile mute edilen bir kullanıcıyı host unmute yapabilmeli.

**Ön koşul:**
- Senaryo B veya C tamamlanmış, kullanıcı shill mute'lu

**Adımlar:**
1. Host olarak moderasyon panelini aç
2. Mute'lu kullanıcıyı bul
3. Unmute butonuna bas

**Beklenen sonuç:**
- Unmute başarılı — `HTTP 200`
- Kullanıcı tekrar teklif verebilmeli
- Host client'ında kullanıcı unmute göstergesi güncellenmeli

**Redis doğrulaması (unmute sonrası):**
```bash
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 0  ← mute kaldırıldı

HGET shill_mute:{stream_id} {user_id}
# Beklened: (nil)  ← meta hash da temizlendi
```

---

## WS Event Doğrulaması (T-01 + T-04)

**Amaç:** Host client'ının shill mute anında WS MUTED event aldığını doğrula.

**Adımlar:**
1. Flutter loglarını izle (Debug console veya `flutter logs`)
2. Senaryo B'yi uygula (shill mute)

**Beklenen Flutter log:**
```
WS received: {type: "muted", user_id: X, source: "system", reason: "shill_bidding"}
```

**Eskiden:** Bu event hiç gelmiyordu → host UI'da kullanıcı "mute değil" görünüyordu.  
**Şimdi:** Event geliyor → host UI anında güncelleniyor, unmute yapabilmeli.

---

---

## T-05 + T-16 — Clean Architecture: Router Import Temizliği

> **Değişiklikler:**
> - `mute_key` → `app.services.moderation_service` (2 lazy import kaldırıldı)
> - `push_notification` → `app.services.notification_service` (3 lazy import kaldırıldı + yeni servis dosyası)
> - `auction_commands.py` artık hiçbir router modülünü import etmiyor

**Amaç:** Servisin çalışmaya devam ettiğini doğrula — davranışsal fark yok, sadece import yolu değişti.

**Ön koşul:** VPS'te deploy tamamlanmış (`git pull && sudo systemctl restart teqlif`)

### Test A — Shill Mute Hâlâ Çalışıyor

1. Unverified + yeni hesap + aynı ağdan teklif ver
2. `HTTP 403 BID_BLOCKED_MUTE` beklenir
3. Log: `[MOD] SYSTEM_MUTE | stream_id=X user_id=Y reason=shill_bidding`

**Redis doğrulaması:**
```bash
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 1
```

### Test B — push_notification Hâlâ Çalışıyor

1. Artırma sonuçlandır (accept_bid veya BIN kabul et)
2. Kazanan kullanıcıya push notification geldiğini doğrula
3. Log: `[PUSH] push_notification çağrıldı | user_id=X | type=...`

**Beklenen:** Davranış değişmez; sadece `[PUSH]` log satırları notification_service'ten geliyor (router'dan değil)

### Test C — Servis Başlatma Hatası Yok

VPS'te restart sonrası:
```bash
sudo journalctl -u teqlif -f | grep -E "ERROR|ImportError|ModuleNotFoundError"
```
**Beklenen:** Import hatası yok, servis temiz başlıyor.

---

---

## T-06 + T-07 — FraudDetectionService + ClickHouse Fraud Tracking

> **Değişiklikler:** Shill detection mantığı `FraudDetectionService.evaluate_bid()`'e taşındı; ClickHouse fraud event'leri eklendi

**Amaç:** Davranışsal fark yok — shill mute aynı çalışmalı. ClickHouse'da yeni event type'ları görünmeli.

**Ön koşul:** VPS'te deploy tamamlanmış

### Test A — Servis Başlatma Hatası Yok

```bash
sudo journalctl -u teqlif -f | grep -E "ERROR|ImportError|ModuleNotFoundError"
```
**Beklenen:** Temiz başlangıç, import hatası yok.

### Test B — Shill WARN ClickHouse Event'i

1. Unverified + eski hesap + aynı IP → 2 teklif ver (WARN aşamalı)
2. Logda `[FRAUD_ATTEMPT] type=shill_bidding` satırları görünmeli
3. Teklif geçmeli (WARN kararı teklifi bloke etmez)

**ClickHouse doğrulaması (opsiyonel):**
```sql
SELECT event_type, count() FROM user_events
WHERE event_type IN ('bid_fraud_warn', 'bid_fraud_mute', 'bid_blocked_verify')
GROUP BY event_type ORDER BY event_type;
```
**Beklenen:** `bid_fraud_warn` satırı görünür.

### Test C — Troll Teklif (BID_BLOCKED_VERIFY) ClickHouse Event'i

1. Doğrulanmamış hesapla yüksek teklif (₺6000+) ver
2. `HTTP 403 BID_BLOCKED_VERIFY` alınmalı
3. ClickHouse'da `bid_blocked_verify` event'i görünmeli

**Logda:**
```
[FRAUD_ATTEMPT] type=troll_bid_no_phone stream_id=X user_id=Y ...
```

### Test D — Shill MUTE Hâlâ Çalışıyor

T-01/T-02 testleriyle aynı — Unverified + yeni hesap + aynı IP → `HTTP 403 BID_BLOCKED_MUTE`  
Bu test artık `FraudDetectionService`'in içinden geliyor.

---

---

## T-08 — Admin API: Fraud & Mute Yönetimi

> **Yeni endpoint'ler:** `/api/admin-data/fraud-log`, `/streams/{id}/mutes`, `/streams/{id}/mutes/{uid}`, `/shill-counter/{sid}/{uid}`

**Ön koşul:** VPS'te deploy tamamlanmış, admin token'ı hazır

### Test A — Fraud Log Listesi

```bash
curl -H "Authorization: Bearer <admin_token>" \
  "https://www.teqlif.com/api/admin-data/fraud-log?limit=10"
```

**Beklenen:** Son fraud girişimleri JSON olarak döner
```json
{"count": N, "entries": [{"fraud_type": "shill_bidding", "stream_id": ..., "timestamp": ...}, ...]}
```

### Test B — Stream Mute Listesi

```bash
# Önce shill mute oluştur (T-01 Senaryo B)
# Sonra listele:
curl -H "Authorization: Bearer <admin_token>" \
  "https://www.teqlif.com/api/admin-data/streams/{stream_id}/mutes"
```

**Beklenen:**
```json
{
  "stream_id": X,
  "muted_count": 1,
  "muted_set_ttl": 86XXX,
  "users": [{"user_id": Y, "username": "...", "shill_reason": "shill_bidding"}]
}
```

### Test C — Admin Force Unmute

```bash
curl -X DELETE -H "Authorization: Bearer <admin_token>" \
  "https://www.teqlif.com/api/admin-data/streams/{stream_id}/mutes/{user_id}"
```

**Beklenen:** `{"ok": true, "stream_id": X, "user_id": Y}`

**Redis doğrulaması:**
```bash
SISMEMBER stream:{stream_id}:muted {user_id}
# Beklenen: (integer) 0

HGET shill_mute:{stream_id} {user_id}
# Beklenen: (nil)
```

### Test D — Shill Sayacı Sıfırlama

```bash
curl -X DELETE -H "Authorization: Bearer <admin_token>" \
  "https://www.teqlif.com/api/admin-data/shill-counter/{stream_id}/{user_id}"
```

**Beklenen:** `{"ok": true, "deleted": true}`

**Redis doğrulaması:**
```bash
GET shill_cnt:{stream_id}:{user_id}
# Beklenen: (nil)
```

---

> Bu dosya her yeni task tamamlandıkça güncellenir.  
> Tamamlanan testler: **T-01, T-02, T-03, T-04, T-05, T-06, T-07, T-08, T-16**  
> Bekleyen testler: T-09, T-10~T-15, T-17, T-18
