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

> Bu dosya her yeni task tamamlandıkça güncellenir.  
> Tamamlanan testler: **T-01, T-02, T-03, T-04**  
> Bekleyen testler: T-05, T-06, T-07, T-08, T-09, T-10~T-18
