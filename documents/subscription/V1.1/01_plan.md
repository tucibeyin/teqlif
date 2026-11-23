# Abonelik V1.1 — 4 Tier Geçiş Planı

**Durum:** Planlama / Tasarım  
**Son güncelleme:** Kasım 2026  
**İlgili ADR:** §13 (Development Workflow), §40 (CreditGate), `credit_service.py`

Bu döküman genişletilebilir yapıdadır. Her bölüm bağımsız tamamlanabilir.  
Tamamlananlar `✅`, devam edenler `🔄`, henüz başlanmayanlar `📋` ile işaretlenir.

---

## İçindekiler

1. [Karar Özeti](#1-karar-özeti)
2. [Tier Tablosu](#2-tier-tablosu)
3. [Backend Değişiklikleri](#3-backend-değişiklikleri)
4. [Flutter / Mobile Değişiklikleri](#4-flutter--mobile-değişiklikleri)
5. [ARB / OTA Lokalizasyon](#5-arb--ota-lokalizasyon)
6. [Ekran Değişiklikleri](#6-ekran-değişiklikleri)
7. [Fiyatlandırma](#7-fiyatlandırma)
8. [UI / UX Tasarımı](#8-ui--ux-tasarımı) 🔄
9. [App Store / Google Play](#9-app-store--google-play) *(TODO)*

---

## 1. Karar Özeti

### Neden 4 Tier?

V1.0'da yalnızca `standard` ve `pro` vardı; 540p / 720p kalite farkı tek başına yeterli
dönüşüm motivasyonu sağlamıyordu. 1080p ve sınırsız yayın saati iki yeni tier'ı
meşrulaştırıyor:

- **Normal → PRO:** Yayın süresi (15h → 30h) ve kalite (540p → 720p) + tüm PRO araçlar
- **PRO → PRO+:** 1080p kalite + yüksek kredi limitleri — ciddi satıcı segmenti
- **PRO+ → PREMIUM:** Sınırsız yayın saati — profesyonel / kurumsal satıcılar

### Yayın Saati Mantığı

Normal kullanıcı için 15 saat/ay ≈ günde ~30 dakika. Aktif mezatçı (3 gün/hafta × 3 saat)
36 saat/ay ihtiyaç duyar — PRO sınırı (30h) altında kalmaz, PRO+'ya yükseltmek zorunda
kalır. Günlük yayıncı (3 saat/gün × 30 gün = 90h) PRO+ sınırını tam dolduruyor → PREMIUM
baskısı. Kayıt izleme süresi (24 saat) MinIO ILM kısıtı nedeniyle tüm ücretli tierlarda aynı kalır.

**Çarpan mantığı:** Normal→PRO: 2× / PRO→PRO+: 3× / PRO+→PREMIUM: sınırsız

---

## 2. Tier Tablosu

✅ **Tamamlandı — Kasım 2026**

| Özellik | Normal | PRO | PRO+ | PREMIUM |
|---------|--------|-----|------|---------|
| **Yayın kalitesi** | 540p | 720p | 1080p | 1080p |
| **Yayın süresi/ay** | 15 saat | 30 saat | 90 saat | Sınırsız |
| **Kayıt izleme** | — | 24 saat | 24 saat | 24 saat |
| **PRO Araçlara erişim** | — | ✓ | ✓ | ✓ |
| | | | | |
| **Blast (ücretsiz/ay)** | 3 | 10 | 20 | 30 |
| **Blast per-op kişi cap** | 5 | 15 | 30 | 50 |
| **Boost (ücretsiz/ay)** | 0 | 3 | 6 | 10 |
| **AI Açıklama (ücretsiz/ay)** | 0 | 6 | 15 | 30 |
| **Reaktivasyon (ücretsiz/ay)** | 0 | 3 | 6 | 10 |
| | | | | |
| **Blast ek kullanım** | 10 teqlik | 10 teqlik | 10 teqlik | 10 teqlik |
| **Boost ek kullanım** | 50 teqlik | 50 teqlik | 50 teqlik | 50 teqlik |
| **AI Açıklama ek kullanım** | 5 teqlik | 5 teqlik | 5 teqlik | 5 teqlik |
| **Reaktivasyon ek kullanım** | 10 teqlik | 10 teqlik | 10 teqlik | 10 teqlik |

> **Not:** Teqlik maliyetleri tüm tierlarda aynı — sadece ücretsiz hak miktarı değişiyor.

---

## 3. Backend Değişiklikleri

### 3.1 `credit_service.py` 📋

**Dosya:** `backend/app/services/credit_service.py`

**`_PREMIUM_TYPES`** genişletilecek:
```python
# Şimdiki:
_PREMIUM_TYPES: frozenset[str] = frozenset({"pro"})

# Yeni:
_PREMIUM_TYPES: frozenset[str] = frozenset({"pro", "pro_plus", "premium"})
```

**`_FEATURES`** dict'e 2 yeni key eklenecek (`free_pro_plus`, `free_premium`):
```python
CreditFeature.BLAST: {
    "key_prefix":          "blast_credits",
    "free_standard":       3,
    "free_pro":            10,   # 6 → 10
    "free_pro_plus":       20,
    "free_premium":        30,
    "cost_teqlik":         10,
    "per_op_cap_standard": 5,
    "per_op_cap_pro":      15,   # 10 → 15
    "per_op_cap_pro_plus": 30,
    "per_op_cap_premium":  50,
},
# ... diğer feature'lar benzer şekilde
```

**`free_limit()` ve `per_op_cap()`** tier-aware dict lookup'a dönüştürülecek:
```python
_TIER_ORDER = ["standard", "pro", "pro_plus", "premium"]

def free_limit(feature: CreditFeature, user_type: str) -> int:
    cfg = _FEATURES[feature]
    key = f"free_{user_type}" if f"free_{user_type}" in cfg else "free_standard"
    return cfg.get(key, cfg["free_standard"])
```

### 3.2 Yayın Saati Takibi 📋

Mevcut `CreditFeature` mekanizması kredi sayımı için yazılmış; yayın saati **dakika cinsinden**
ayrı bir Redis anahtarında takip edilecek. Yeni `CreditFeature.STREAM_MINUTES` eklenmeyecek —
bunun yerine `stream_service.py` içinde ayrı fonksiyon:

```python
# Redis key: stream_minutes:{user_id}:{YYYY-MM}
# Yayın başlarken: dakika rezervasyonu yok, biterken toplam süre eklenir
# Limit kontrolü: yayın başlatma endpoint'inde (routers/streams.py)
```

**Limitler (dakika):**
- Normal: 900 dk (15 saat)
- PRO: 1800 dk (30 saat)
- PRO+: 5400 dk (90 saat)
- PREMIUM: `None` (sınırsız)

### 3.3 `routers/streams.py` 📋

Yayın başlatma endpoint'inde iki kontrol eklenecek:

1. **Kalite kontrolü:** `user_type` → izin verilen maksimum çözünürlük
2. **Süre kontrolü:** Aylık kalan dakika kontrolü (yayın bitişinde sayaç güncelleme)

Mevcut `line 317: if current_user.user_type != 'pro'` → tier-aware fonksiyona taşınacak.

### 3.4 DB Migration 📋

`users.user_type` alanı mevcut `String(20)` — yeni değerler sığar, tip değişikliği gerekmez.
Ancak eski `CHECK` kısıtı varsa güncellenecek:

```sql
-- Alembic migration (multi-statement yasak — ayrı revision'lar)
-- Revision 1: CHECK kısıtını kaldır
-- Revision 2: Yeni CHECK kısıtı ekle
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE users ADD CONSTRAINT users_user_type_check
  CHECK (user_type IN ('standard', 'pro', 'pro_plus', 'premium'));
```

> **ADR Kuralı:** Multi-statement revision yasak; her ALTER ayrı revision.

### 3.5 `routers/auth.py` ve Diğerleri 📋

`user_type == 'pro'` karşılaştırması tüm backend'de taranacak; tier-aware helper'a taşınacak:

```python
def is_paid_tier(user_type: str) -> bool:
    return user_type in _PREMIUM_TYPES

def tier_level(user_type: str) -> int:
    return {"standard": 0, "pro": 1, "pro_plus": 2, "premium": 3}.get(user_type, 0)
```

---

## 4. Flutter / Mobile Değişiklikleri

### 4.1 `models/user.dart` 📋

**Şimdiki durum:**
```dart
bool get isPremium => userType == 'pro';
bool get isPro => userType == 'pro';
```

**Yeni:**
```dart
bool get isPaidTier => ['pro', 'pro_plus', 'premium'].contains(userType);
bool get isPro      => userType == 'pro';
bool get isProPlus  => userType == 'pro_plus';
bool get isPremium  => userType == 'premium';

int get tierLevel => const {'standard': 0, 'pro': 1, 'pro_plus': 2, 'premium': 3}[userType] ?? 0;

String get tierDisplayName => const {
  'standard': 'Normal',
  'pro':      'PRO',
  'pro_plus': 'PRO+',
  'premium':  'PREMIUM',
}[userType] ?? 'Normal';
```

> **Dikkat:** Mevcut `isPremium` bool'u `isPaidTier`'a dönüştürülüyor — tüm kullanım yerlerini
> taramak gerekiyor (grep: `isPremium`).

### 4.2 `pro_hub_screen.dart` ve `pro_hub_view_model.dart` 📋

`isPremium: bool` parametresi → `userType: String` veya `tierLevel: int`'e dönüştürülecek.
`_ProStatusCard` widgeti tier adını ve rengini dinamik gösterecek:

| Tier | Renk | Rozet |
|------|------|-------|
| PRO | Mevcut PRO rengi | PRO |
| PRO+ | Farklılaştırılacak (TODO §8) | PRO+ |
| PREMIUM | Premium renk (TODO §8) | ✦ PREMIUM |

### 4.3 `pro_subscription_view_model.dart` 📋

Şu an yalnızca PRO satın alma akışı mevcut. 4 tier için plan seçimi UI'ı eklenecek.
(Detay: §8 UI/UX)

### 4.4 Stream Kalite Seçimi 📋

`host_stream_screen.dart`'ta yayın başlatma: kullanıcının tier'ına göre izin verilen
maksimum kalite sunulacak. Üst tier kalite seçenekleri kilitli gösterilip tier upgrade
yönlendirmesi yapılacak.

### 4.5 `credit_gate_view_model.dart` 📋

`CreditGateData` modeli tier bazlı limit bilgisini API'den alıyor — backend değişikliği
sonrası Flutter tarafı otomatik doğru limitleri gösterir. Model güncellemesi gerekmez,
API response değişir.

---

## 5. ARB / OTA Lokalizasyon

### 5.1 Yeni Anahtarlar 📋

**Dosyalar:** `documents/language/app_tr.arb` ve 4 dil daha (en, de, ru, ar)

Eklenecek anahtar örnekleri:
```json
"tierPro":           "PRO",
"tierProPlus":       "PRO+",
"tierPremium":       "PREMIUM",
"tierNormal":        "Normal",
"streamHoursLeft":   "Bu ay {hours} saatiniz kaldı",
"streamHoursUsed":   "{used} / {total} saat kullanıldı",
"streamLimitReached":"Aylık yayın limitine ulaştınız",
"upgradeToPro":      "PRO'ya Geç",
"upgradeToProPlus":  "PRO+'ya Geç",
"upgradeToPremium":  "PREMIUM'a Geç",
"proHubStreamHours": "Yayın Saati",
"proHubBlastCredits":"Kitle Bildirimi",
"proHubBoostCredits":"Öne Çıkarma",
"proHubAiCredits":   "AI Açıklama",
"proHubReactCredits":"Reaktivasyon"
```

> **Workflow:** ARB → `git push` → VPS'te `git pull` → `sync_main.py` (ADR §1).
> SQL'e doğrudan yazılmaz.

### 5.2 Mevcut Anahtarlar Güncellenecek 📋

`"pro": "PRO"` anahtarı tier adı olarak değil özellik adı olarak kullanılıyorsa
bağlamına göre ayrıştırılacak.

---

## 6. Ekran Değişiklikleri

### 6.1 PRO Araçlar (`pro_hub_screen.dart`) 📋

- Tier rozeti: Normal → zayıf CTA, PRO/PRO+/PREMIUM → kendi tier bilgisi + yenileme tarihi
- Yayın saati progress bar: `{kullanılan} / {toplam} saat` (sınırsız için farklı UI)
- Kredi kartları: Blast / Boost / AI / Reaktivasyon — ücretsiz hak + kullanılan gösterimi
- Upgrade CTA: kullanıcının bir üst tier'ına yönlendirme (PREMIUM zaten en üst)

### 6.2 Profilim (`profile_screen.dart`) 📋

- Tier rozeti profil başlığına eklenecek (PRO / PRO+ / PREMIUM badge)
- Normal kullanıcıda PRO'ya geç CTA'sı (mevcut varsa güncelleme)

### 6.3 Ayarlar 📋

- Abonelik bölümü: mevcut tier, yenileme tarihi, tier değiştir linki
- (Detay: §8 UI/UX, §9 App Store)

### 6.4 teqlik Cüzdanım (`wallet_repository.dart` → screen) 📋

- Kredi özeti: hangi tier'da olduğu, kalan ücretsiz haklar
- Yayın saati özeti: Cüzdan ekranında da görünebilir (tartışılacak)

### 6.5 Yayın Başlatma (`host_stream_screen.dart`) 📋

- Kalite seçici: tier'a göre izin verilen max kalite
- Aylık kalan süre uyarısı: `< 2 saat kaldı` uyarısı (soft warning)
- Limit dolunca yayın başlatma engeli + upgrade yönlendirme

### 6.6 Abonelik Seçim Ekranı (Yeni veya Mevcut Güncelleme) 📋

4 tier'ı yan yana veya dikey liste olarak gösteren plan seçim UI'ı.
(Detay: §8 UI/UX, §9 App Store fiyatlandırması)

---

## 7. Fiyatlandırma

✅ **Tamamlandı — Kasım 2026**

### 7.1 Aylık Taban Fiyatlar

| Tier | Aylık Fiyat | Yayın Saati | Kalite | Saat Başı Maliyet |
|------|-------------|-------------|--------|-------------------|
| Normal | Ücretsiz | 15 saat | 540p | — |
| PRO | 299,99 ₺ | 30 saat | 720p | ~10 ₺/saat |
| PRO+ | 699,99 ₺ | 90 saat | 1080p | ~7,78 ₺/saat |
| PREMIUM | 1.299,99 ₺ | Sınırsız | 1080p | — |

> Üst tier saat başı maliyeti düşüyor — upgrade'i finansal olarak meşrulaştırır.

### 7.2 Çok Aylık Fiyat Tablosu

Tüm fiyatlar Türkiye App Store fiyat listesinde mevcut. Sıfır çakışma.

| | 1 ay | 3 ay | İndirim | 6 ay | İndirim | 12 ay | İndirim |
|---|---|---|---|---|---|---|---|
| **PRO** | 299,99 ₺ | 799,99 ₺ | %11 | 1.499,99 ₺ | %17 | 2.699,99 ₺ | %25 |
| **PRO+** | 699,99 ₺ | 1.799,99 ₺ | %14 | 3.499,99 ₺ | %17 | 6.299,99 ₺ | %25 |
| **PREMIUM** | 1.299,99 ₺ | 3.299,99 ₺ | %15 | 5.999,99 ₺ | %23 | 11.499,99 ₺ | %26 |

**Yıllık tasarruf (kullanıcıya gösterilebilir):**

| Tier | 12 aylıkta tasarruf |
|------|---------------------|
| PRO | ~900 ₺ ≈ 3 ay ücretsiz |
| PRO+ | ~2.100 ₺ ≈ 3 ay ücretsiz |
| PREMIUM | ~4.100 ₺ ≈ 3+ ay ücretsiz |

### 7.3 App Store Connect Ürün ID'leri

**PRO:**
```
teqlif_pro_1m    → 299,99 ₺
teqlif_pro_3m    → 799,99 ₺
teqlif_pro_6m    → 1.499,99 ₺
teqlif_pro_12m   → 2.699,99 ₺
```

**PRO+ (yeni):**
```
teqlif_pro_plus_1m   → 699,99 ₺
teqlif_pro_plus_3m   → 1.799,99 ₺
teqlif_pro_plus_6m   → 3.499,99 ₺
teqlif_pro_plus_12m  → 6.299,99 ₺
```

**PREMIUM (yeni):**
```
teqlif_premium_1m    → 1.299,99 ₺
teqlif_premium_3m    → 3.299,99 ₺
teqlif_premium_6m    → 5.999,99 ₺
teqlif_premium_12m   → 11.499,99 ₺
```

### 7.4 FOMO Tasarımı — Yayın Saati

| Kullanıcı tipi | Aylık ihtiyaç | Uygun tier | Upgrade baskısı |
|----------------|---------------|------------|-----------------|
| Casual satıcı | 5–10 saat | Normal | PRO CTA |
| Düzenli satıcı | 15–25 saat | PRO | Rahat |
| Aktif mezatçı (3 gün/hafta × 3 saat) | 36 saat | PRO+ | PRO sınırı (30h) aşılıyor |
| Günlük yayıncı (3 saat/gün) | 90 saat | PRO+ dolumu | PREMIUM CTA |

### 7.6 Yayın Geliri Paylaşım Modeli

| Tier | Satıcı payı | Teqlif payı |
|------|-------------|-------------|
| Normal | %50 | %50 |
| PRO | %75 | %25 |
| PRO+ | %90 | %10 |
| PREMIUM | %100 | %0 |

> **V1.0 mevcut durum:** Normal %75, PRO %95 — bu değerler V1.1 ile değişecek.  
> Backend'de `commission_rate` hesaplama mantığı güncellenmeli.

Komisyon oranı üyeliğin en güçlü satış argümanı. "Kazancınızın %100'ü sizin" →
PREMIUM için Üyelik Planları ekranında above-fold'da en öne çıkarılacak kazanım.

### 7.5 Apple / Google Komisyon Notu

- Apple Year 1: %45 Apple alır (Small Business Program'da %30)
- Apple Year 2+: %30 → %25 (Small Business Program)
- Google Play: %15 (ilk 1M USD gelire kadar), sonrası %30
- Net gelir App Store Connect "Proceeds" sütununda görünür; fiyatlandırma bu kesinti
  sonrası karlılık hesabıyla doğrulandı.

---

## 8. UI / UX Tasarımı

🔄 **Planlama / Tasarım — Kasım 2026**

---

### 8.1 Renk Paleti ve Rozet Sistemi

**Öncelik:** PREMIUM > PRO+ > PRO > Normal

| Tier | Renk | Rozet | String |
|------|------|-------|--------|
| PREMIUM | Teqlif cyan | Kral tacı (cyan) | `PREMIUM` |
| PRO+ | Altın sarısı | Kral tacı (altın) | `PRO+` |
| PRO | Altın sarısı | Kral tacı (altın) | `PRO` |
| Normal | — | Yok | — |

**Evrensel badge bileşeni** (tüm ekranlarda aynı):
- Şekil: **rounded rectangle** (köşe yarıçaplı dikdörtgen — oval yok)
- İçerik: tier string'i (`PRO`, `PRO+`, `PREMIUM`)
- Renk: tier rengine göre arka plan / border
- Normal: badge render edilmez

Kral tacı icon'u mevcut haliyle devam eder; rengi ve konumlandırması değişmez.

---

### 8.2 "Canlı" Ekranı

#### Story Feed

| Öncelik | İçerik | Kural |
|---------|--------|-------|
| 1 | Takip edilen + subscription sahibi | PREMIUM > PRO+ > PRO > Normal sırasıyla |
| 2 | Takip edilmeyen PREMIUM | ClickHouse ilgi skoru yüksek olanlar serpiştirilir |

**Serpiştirme kuralı (başlangıç değeri, A/B test ile optimize edilecek):**
- Her 5 takip edilen story'den 3. konuma 1 PREMIUM öneri → **%20 oran**
- Kriter: ClickHouse `user_interest_score` (izleme geçmişi, arama, beğeni)
- İçinde öncelik: daha önce izlenmiş ama takip edilmeyen PREMIUM yayıncılar

#### Canlı Yayın Feed (liste / grid)

```
1. Takip edilen + PREMIUM        ← en üst
2. Takip edilen + PRO+
3. Takip edilen + PRO
4. Takip edilen + Normal
── serpiştirilmiş öneriler ──────
5. Takip edilmeyen + PREMIUM     (ilgi skoru yüksek)
6. Takip edilmeyen + PRO+        (ilgi skoru yüksek)
7. Takip edilmeyen + PRO
8. Takip edilmeyen + Normal
```

- Statik olan tek şey: subscription önceliği
- **Serpiştirilmiş içerik oranı (başlangıç):** Her 4 takip edilende 1 öneri → **%25 oran**
- Mevcut sıralama skoru (`0.55 × interest + 0.30 × hype_score + 0.15 × viewer_count`) korunur;
  takip edilmeyen PREMIUM için `+0.25` subscription ağırlığı eklenir
- Üst üste 2'den fazla serpiştirilmiş öneri gösterilmez
- Kullanıcı "Sadece takip ettiklerim" filtresiyle listeyi daraltabilmeli

---

### 8.3 "İlanlar" Ekranı

- Takip edilenlerin ilanları + araya takip edilmeyenler serpiştirilir (Canlı mantığıyla tutarlı)
- **İlan kartı üzerinde:** Satıcının subscription rozeti — profil avatar yanında/üzerinde
  - PREMIUM satıcı → cyan kral tacı
  - PRO / PRO+ satıcı → altın kral tacı
  - Normal satıcı → rozet yok
- Sıralama: subscription önceliği; aynı tier içinde engagement + güncellik

---

### 8.4 "Keşfet" Ekranı

**Prensip:** Kullanıcıyı boğmadan dengeli içerik karması.

- ClickHouse tabanlı kişiselleştirilmiş feed
- Subscription önceliği var ama yığılma engeli:
  - Üst üste 3'ten fazla PREMIUM içerik gösterilmez
  - Her 5 içerikten en az 1'i Normal/PRO tier
- İçerik tipleri: ilan, canlı yayın, yayıncı hesabı (hepsi subscription rozeti taşır)
- Sıralama ağırlıkları (başlangıç, A/B test ile optimize edilecek):
  `0.6 × ilgi_skoru + 0.3 × subscription_ağırlığı + 0.1 × güncellik`

---

### 8.5 "Mesajlar" Ekranı

Değişiklik yok.

---

### 8.6 "Profilim" Ekranı

- Profil başlığına subscription rozeti eklenir (rounded rect badge)
- Normal kullanıcıda rozet yok; onun yerine PRO CTA butonu görünür
- Mevcut profil layout'u korunur; sadece rozet alanı eklenir

---

### 8.7 teqlik Cüzdanım

#### "PRO'ya Geç" Butonu

| Durum | Metin |
|-------|-------|
| Kullanıcı Normal | "Üyelik Planlarını Gör" (kral tacı icon kalır) |
| Kullanıcı zaten abone | "Üyelik Yükselt" (PRO Araçları butonu ile tutarlı) |
| Kullanıcı PREMIUM | Buton gizlenir |

#### Üyelik Planları Ekranı — 3 Tab

Tab'lar: `PRO` · `PRO+` · `PREMIUM`

**Her tab — above the fold (kaydırmadan görünen alan):**
- Tier adı + kral tacı (tier rengiyle büyük)
- Aylık fiyat büyük punto + "/ ay"
- Süre seçici: `1 ay` · `3 ay` · `6 ay` · `12 ay` → seçime göre fiyat güncellenir + tasarruf etiketi
- En çarpıcı 3 kazanım (büyük, iconlu):
  1. Yayın saati (ör. "90 saat/ay")
  2. Kalite (ör. "1080p Full HD")
  3. Komisyon (ör. "Kazancının %90'ı senin")
- CTA butonu: "PRO+'ya Başla" / "PREMIUM'a Geçiş Yap" (tier rengiyle)

**Below the fold:**
- Tam özellik listesi (Blast, Boost, AI Açıklama, Reaktivasyon limitleri)
- Mevcut tier ile karşılaştırma tablosu
- İptal ve yenileme politikası (küçük yazı)

**UX kuralı:** Kullanıcının mevcut tier tab'ı varsayılan seçili; upgrade CTA bir üst tier'a yönlendirir.

---

### 8.8 Ayarlar Ekranı

Subscription badge bileşeni ilgili tüm satırlarda tutarlı (rounded rect, aynı bileşen):

| Menu item | Badge |
|-----------|-------|
| "PRO Araçları" | Tier badge (sağda) |
| "Canlı Yayınlarım" | Tier badge (sağda) |
| Diğer subscription'a bağlı item'lar | Aynı bileşen |

**Tutarsızlık giderme:** Şu an "PRO Araçları" oval, "Canlı Yayınlarım" rounded rect —
ikisi de rounded rect'e dönüştürülür.

---

### 8.9 Bildirim Ayarları Ekranı

- Subscription modeline göre yazı ve renk dinamik
- Badge şekli: rounded rectangle (Ayarlar ile tutarlı)
- Örn: `[PRO]` "PRO bildirimleri" → tier değişince otomatik güncellenir

---

### 8.10 PRO Araçları Ekranı

- Subscription bilgi alanı: tier rengine göre (cyan / altın)
- **Yayın saati progress bar:**
  - `[████████░░░░░░░] 36 / 90 saat`
  - %80 dolunca → sarı uyarı rengi
  - %100 → kırmızı + "Üyelik Yükselt" soft CTA
  - PREMIUM: progress bar yerine `Sınırsız ✦` gösterimi
- **"PRO'ya Geç" → "Üyelik Yükselt"** → Üyelik Planları ekranı açılır (bir üst tier tab'ı seçili)
- **Komisyon satırı:** "Kazancınızın %X'i sizin" (tier'a göre dinamik)
- Kredi kartları (Blast / Boost / AI / Reaktivasyon): ücretsiz hak tükenince "Teqlik ile devam et" CTA

---

### 8.11 Gözden Kaçan: Yayın Başlatma Ekranı (`host_stream_screen`) 📋

- **Kalite seçici (tier'a göre):**
  - Normal: yalnızca 540p
  - PRO: 540p / 720p
  - PRO+ / PREMIUM: 540p / 720p / 1080p
  - Kilitli seçeneğe dokunulunca: **Üyelik Planları ekranı açılır, gereken tier tab'ı seçili**
    (1080p → PRO+ tab; 720p → PRO tab) ← Karar: Seçenek B ✅
- **Aylık kalan süre uyarısı:**
  - Yayın başlamadan: "Bu ay X saatiniz kaldı" bilgi satırı
  - %20 kalan (ör. 6 saat / 90h PRO+'da): sarı soft uyarı banner
  - 0 saat: yayın başlatma engeli + "Üyelik Yükselt" CTA
- **Yayın bitiş özeti (`GetRecordingSummaryQuery` + komisyon hesabı):**

  **Above fold — en önemli 3 rakam:**
  ```
  ┌─────────────────────────────────┐
  │  Toplam Gelir      3.450 ₺      │  ← auction + direct sale
  │  Net Kazanç        3.105 ₺  %90 │  ← × commission_rate (tier badge ile)
  │  Pik İzleyici          47       │
  └─────────────────────────────────┘
  ```

  **Below fold — detay:**
  - Yayın süresi + bu ay kalan saat (güncellendi)
  - Müzayede özeti: `{N} müzayede, {K} satıldı`
  - Direkt satış: `{N} ürün, {K} sipariş`
  - Beğeni: `{total_likes}`
  - Hediyeler: `{total_teqlik} teqlik alındı`
  - Yayın kaydı linki (PRO+/PREMIUM)

  **Upgrade FOMO satırı** (PREMIUM değilse):
  > "PRO+'ya geçseydiz bu yayından **X ₺ daha fazla** kazanırdınız →"
  > *(fark: `total_revenue × (hedef_tier_commission - mevcut_commission)`)*

---

### 8.12 Gözden Kaçan: İzleyici Ekranı (Viewer Side) 📋

- **Host subscription rozeti:** Canlı yayın sırasında host'un kral tacı rozeti görünür (küçük, üst köşe)
- **Kalite badge'i:** PRO+ / PREMIUM yayıncılarda "1080p" veya "HD" göstergesi
- Bu iki öğe izleyiciye host'un premium statüsünü sinyaller → izleyici FOMO

---

### 8.13 Gözden Kaçan: Kilitli Özellik UI Pattern'ı 📋

Tüm ekranlarda tutarlı:

```
[🔒 1080p Yayın]   "PRO+'ya geçerek 1080p kaliteyle yayın yap →"
```

- Kilit ikonu + opacity düşük özellik gösterimi + kısa CTA
- Tıklanınca: Üyelik Planları ekranı (ilgili tier tab'ı seçili)
- Kullanım yerleri: yayın kalite seçici, PRO Araçları, Keşfet filtreler, yayın başlatma

---

### 8.14 Gözden Kaçan: Subscription Sona Erme Akışı 📋

- **3 gün önce:** Push notification + in-app banner
- **Bitince:** Tier Normal'e düşer
  - Aktif canlı yayın sırasında biterse: mevcut yayın tamamlanır, sonraki yayın kısıtlı
  - Kalan aylık stream saatleri **sıfırlanır** — kalan süre aktarılmaz
- **Yeniden aktivasyon:** "Hoş geldiniz geri" + önceki tier hatırlatıcısı

---

### 8.15 Açık Kararlar (TODO)

- Üyelik Planları ekranı wireframe / tasarım
- `GetRecordingSummaryQuery`'e `commission_rate` ve `net_earnings` alanları eklenmeli (§3 Backend ile bağlantılı)
- Upgrade FOMO satırı için "kaç ₺ daha kazanırdınız" hesabını döndüren backend endpoint

---

## 9. App Store / Google Play

🔄 **Planlama — Kasım 2026**

---

### 9.1 App Store Connect Kurulumu 📋

**Mevcut ürünler (fiyat güncellenecek — uygulama henüz yayında değil):**

| Product ID | Eski fiyat | Yeni fiyat |
|------------|-----------|------------|
| teqlif_pro_1m | 149,99 ₺ | 299,99 ₺ |
| teqlif_pro_3m | 399,99 ₺ | 799,99 ₺ |
| teqlif_pro_6m | 699,99 ₺ | 1.499,99 ₺ |
| teqlif_pro_12m | 1.299,99 ₺ | 2.699,99 ₺ |

**Yeni oluşturulacak ürünler:**

```
teqlif_pro_plus_1m   → 699,99 ₺
teqlif_pro_plus_3m   → 1.799,99 ₺
teqlif_pro_plus_6m   → 3.499,99 ₺
teqlif_pro_plus_12m  → 6.299,99 ₺

teqlif_premium_1m    → 1.299,99 ₺
teqlif_premium_3m    → 3.299,99 ₺
teqlif_premium_6m    → 5.999,99 ₺
teqlif_premium_12m   → 11.499,99 ₺
```

**Subscription Group hiyerarşisi** (App Store Connect'te tier sırası tanımlanmalı):
```
PREMIUM  (seviye 1 — en yüksek)
PRO+     (seviye 2)
PRO      (seviye 3)
```
Bu hiyerarşi Apple'ın otomatik upgrade/downgrade yönetimini sağlar.

**Lokalizasyon:** App Store Connect'te her ürün için TR / EN açıklama metni yazılmalı.

---

### 9.2 Google Play Console Kurulumu 📋

Google Play, App Store'dan farklı bir yapı kullanır: **Subscription + Base Plan + Offer**.

Her tier için:
1. Subscription oluştur (ör. `teqlif_pro_plus`)
2. Base plan ekle: `monthly`, `quarterly`, `biannual`, `annual`
3. Offer (opsiyonel): lansman indirimi, ücretsiz deneme

```
teqlif_pro        → base plans: 1m / 3m / 6m / 12m
teqlif_pro_plus   → base plans: 1m / 3m / 6m / 12m
teqlif_premium    → base plans: 1m / 3m / 6m / 12m
```

**Not:** Google Play ürün ID'leri App Store'dan farklı olabilir; Flutter `in_app_purchase`
paketi her iki platformu soyutlar.

---

### 9.3 Flutter IAP Entegrasyonu (`iap_service.dart`) 📋

**Mevcut durum:**
```dart
const kSubscriptionIds = {
  'teqlif_pro_1m', 'teqlif_pro_3m', 'teqlif_pro_6m', 'teqlif_pro_12m',
};
```

**Yeni durum:**
```dart
const kSubscriptionIds = {
  // PRO
  'teqlif_pro_1m', 'teqlif_pro_3m', 'teqlif_pro_6m', 'teqlif_pro_12m',
  // PRO+
  'teqlif_pro_plus_1m', 'teqlif_pro_plus_3m',
  'teqlif_pro_plus_6m', 'teqlif_pro_plus_12m',
  // PREMIUM
  'teqlif_premium_1m', 'teqlif_premium_3m',
  'teqlif_premium_6m', 'teqlif_premium_12m',
};

// Tier mapping (product ID → user_type)
const kProductTierMap = {
  'teqlif_pro_1m':       'pro',
  'teqlif_pro_3m':       'pro',
  'teqlif_pro_6m':       'pro',
  'teqlif_pro_12m':      'pro',
  'teqlif_pro_plus_1m':  'pro_plus',
  'teqlif_pro_plus_3m':  'pro_plus',
  'teqlif_pro_plus_6m':  'pro_plus',
  'teqlif_pro_plus_12m': 'pro_plus',
  'teqlif_premium_1m':   'premium',
  'teqlif_premium_3m':   'premium',
  'teqlif_premium_6m':   'premium',
  'teqlif_premium_12m':  'premium',
};
```

**Satın alma akışı değişmez** — `purchaseSubscription(productId)` → platforma iletilir →
receipt/token backend'e gönderilir → backend `user_type` günceller → Flutter state refresh.

---

### 9.4 Backend — Webhook ve Receipt Validation 📋

#### Apple (StoreKit 2 / App Store Server Notifications)

Dinlenecek notification type'lar:

| Event | Aksiyon |
|-------|---------|
| `SUBSCRIBED` | `user_type` güncelle |
| `DID_RENEW` | Süre uzat, stream saati sıfırla |
| `EXPIRED` | `user_type = 'standard'`, stream saati sıfırla |
| `DID_CHANGE_RENEWAL_STATUS` (cancel) | Mevcut dönem sonu için işaretle |
| `REVOKED` (iade) | Anında `user_type = 'standard'` |
| `GRACE_PERIOD_EXPIRED` | `user_type = 'standard'` |

**Grace period:** Apple ödeme başarısız olunca 6–16 gün grace tanır.
Bu sürede kullanıcı tier erişimini korur; backend `in_grace_period` flag'i tutmalı.

#### Google Play (RTDN — Real-Time Developer Notifications)

Benzer event'lar: `SUBSCRIPTION_PURCHASED`, `SUBSCRIPTION_RENEWED`,
`SUBSCRIPTION_CANCELED`, `SUBSCRIPTION_EXPIRED`, `SUBSCRIPTION_REVOKED`.

#### Ortak backend endpoint

```
POST /webhooks/apple
POST /webhooks/google
```

Her iki endpoint de sonuçta aynı iç fonksiyonu çağırır:
`update_user_subscription(user_id, new_tier, expires_at)`

---

### 9.5 Subscription State Machine 📋

```
Normal ──────────────────────────────────────────────► PRO
   ▲                                                     │
   │  (expire / cancel / revoke)                         ▼
   └──────── PRO+ ◄──────────────────────────────────── PRO
   └──────── PREMIUM ◄───────────────────────── PRO+
```

**Upgrade:** Anlık geçiş, kalan süre prorata hesaplanır (Apple/Google halleder).  
**Downgrade:** Mevcut dönem sonunda geçerli.  
**Cancel:** Mevcut dönem sonunda Normal'e düşer; erişim hemen kesilmez.  
**Revoke (iade):** Anlık Normal'e düşer; stream saati sıfırlanır.  
**Expire (grace sonrası):** Normal'e düşer; stream saati sıfırlanır.

---

### 9.6 Restore ve Cihaz Değişimi Akışı 📋

**Flutter tarafı:**
- Uygulama açılışında: `restorePurchases()` → platform aktif subscription'ı döner
- Backend'e receipt/token gönderilir → `user_type` senkronize edilir
- "Satın Alımlarımı Geri Yükle" butonu: Ayarlar > Abonelik bölümünde

**Backend tarafı:**
- Receipt validation idempotent olmalı (aynı receipt tekrar gelirse sorun çıkmamalı)
- Cihaz değişiminde kullanıcı aynı Apple/Google hesabıyla giriş yaparsa otomatik restore

---

### 9.7 Promosyon ve Deneme Kararları

**Google Play product ID:** App Store ile aynı isimler (`teqlif_pro_plus_1m` vb.) ✅

#### Ücretsiz Deneme — 7 Gün PRO ✅

- Yeni kayıt olan tüm kullanıcılara 7 günlük PRO denemesi
- Deneme sonrası: ücretli aboneliğe geçiş veya Normal'e düşüş
- App Store Connect: Introductory Offer → Free Trial türü
- Google Play: Free trial base plan offer
- Kural: Her Apple/Google hesabı başına yalnızca bir kez kullanılabilir (platform güvencesi)

#### İlk Ay İndirimli Fiyat (Introductory Offer) ✅

Sadece aylık planlara uygulanır. Çok aylık planların kendi indirim yapısı var (%11–26).  
App Store Connect türü: **Pay as you go** — 1 ay indirimli, sonraki aydan normal fiyat.

| Tier | Normal fiyat | İlk ay (%50) | App Store listesinde |
|------|-------------|--------------|----------------------|
| PRO 1m | 299,99 ₺ | **149,99 ₺** | ✅ |
| PRO+ 1m | 699,99 ₺ | **349,99 ₺** | ✅ |
| PREMIUM 1m | 1.299,99 ₺ | **649,99 ₺** | ✅ |

#### Upgrade Promosyonu ✅

**Model: Mevcut tier fiyatında ilk ay** — kullanıcı yeni tieri için ek ödeme hissetmez.  
App Store Connect: Promotional Offer (mevcut ücretli abonelere özel, subscriber başına 1 kez).

| Yol | Normal fiyat | Promo fiyatı | Tasarruf |
|-----|-------------|--------------|---------|
| PRO → PRO+ | 699,99 ₺ | **299,99 ₺** | 400 ₺ |
| PRO+ → PREMIUM | 1.299,99 ₺ | **699,99 ₺** | 600 ₺ |
| PRO → PREMIUM | 1.299,99 ₺ | **699,99 ₺** | 600 ₺ |

> Psikolojik çerçeveleme: "Bu ay PRO fiyatına PRO+ dene" — ek maliyet hissi yok.  
> Ay 2'den itibaren yeni tier normal fiyatı geçerli.
