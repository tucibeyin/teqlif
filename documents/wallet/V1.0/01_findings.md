# teqlik Wallet — V1.0 Bulgular & Karar Belgesi

**Tarih:** 2026-10-23  
**Kapsam:** iOS IAP entegrasyonu, fiyatlandırma stratejisi, UX mimarisi, Apple uyum gereksinimleri, yayıncı TL kazanç ve IBAN çekim sistemi  
**Durum:** Araştırma tamamlandı — implementasyon bekliyor

---

## 1. Rakip Platform Fiyat Analizi

### 1.1 Platform Karşılaştırma Tablosu

| Platform | Birim | iOS Fiyatı | Web Fiyatı | Platform Payı | Kullanım Amacı |
|----------|-------|-----------|-----------|--------------|----------------|
| **TikTok Coin** | 1 Coin | **₺0,88** (App Store) | **₺0,50–0,57** | ~%50 gifting + store cut | Yayıncıya hediye |
| **Twitch Bits** | 1 Bit | TRY yok | $0,014 | ~%29 | Yayıncıya destek |
| **YouTube Super Chat** | Sabit tier | $2–$500 TRY eşd. | $2–$500 | %30 | Yayın anında destek |
| **Instagram Stars** | 1 Star | TR'de yok | ~$0,020 | ~%50 | İçerik üretici |
| **Twitter/X Tips** | — | %0 (ext. işlemci) | %0 | **%0 X kesmez** | Doğrudan yaratıcı |
| **Snapchat Tokens** | — | — | — | — | **Şubat 2025'te kapatıldı** |
| **teqlik (planlanan)** | 1 teqlik | **₺1,50** (%30) / **₺1,20** (%15) | — | %30 veya %15 (Apple) | İlan güçlendirme |

> **TikTok iOS vs Web:** App Store'da ₺0,88/coin, web'de ₺0,50/coin. Fark = Apple'ın %30'u + TikTok margin koruması. Bu, teqlik ekranında "web'den al" ibaresi kullanılamayacağını doğruluyor (Kural 3.1.1 ihlali).
>
> **Instagram Stars:** Türkiye'de henüz aktif değil; yalnızca ABD ve seçili ülkelerde mevcut.
>
> **Twitter/X:** Harici ödeme işlemcisi (PayPal, Venmo); X %0 komisyon alıyor ancak iOS App Store üzerinden alım zorunlu olmadığından Apple da kesmiyor. Sanal para birimi yok.
>
> **Meta stratejisi:** Stars satışını kasıtlı olarak kendi web mağazasına taşıdı; Apple/Google %30'dan kaçınmak için. Teqlif'in bu opsiyonu yok — teqlik dijital özellik kilidini açtığı için Apple Kural 3.1.1 kesinlikle geçerli.

### 1.2 Piyasa Okuma

- **TikTok Coin** iOS'ta ₺0,88/coin, web'de ₺0,50/coin — App Store ek maliyeti net görünüyor. Platform yayıncıya %50 aktarıyor. Amaç yaratıcı tipping, ilan güçlendirme değil.
- **Snapchat Tokens** Şubat 2025'te tamamen kapatıldı — sanal para stratejisi başarısız oldu.
- **Twitch Bits** en şeffaf model: kullanıcıya maliyet, yaratıcıya gelir açıkça yayımlıyor. %29 platform payı Apple ile neredeyse aynı.
- **YouTube/Meta:** %30 komisyon modeli — Google Play / Apple Pay üzerinden veya doğrudan web ödeme.
- **teqlik farklı konumda:** Sosyal medyada sanal para = yaratıcıya hediye. teqlik = kullanıcının **kendi ilanına yatırım**. Bu fiyat duyarlılığını azaltır — kullanıcı doğrudan ROI (daha fazla görüntülenme, satış) bekliyor.

---

## 2. Apple Komisyon Analizi & teqlik Fiyatlandırması

### 2.1 Apple Komisyon Yapısı

| Program | Oran | Koşul |
|---------|------|-------|
| Standart | **%30** | Tüm geliştiriciler |
| Small Business Program | **%15** | Yıllık net gelir < $1M (komisyon sonrası) |

> **Small Business Program** Apple'ın 2021'de başlattığı program hâlâ aktif. Teqlif'in ilk yıl için bu programa girmesi kuvvetle muhtemel. Kayıt zorunlu — otomatik değil. Başvuru: App Store Connect → Agreements, Tax, and Banking.
>
> **Önemli:** Gelir $1M'ı aşarsa yıl ortasında bile %30'a geçer. İlk lansman için %15 ile başlayıp planlama buna göre yapılmalı.

### 2.2 Hedef Fiyat Mantığı

Hedef: **1 teqlik = 1 TL net gelir** (Apple komisyonu kullanıcıya yansıtılıyor)

> **⚠️ Türkiye KDV Notu:** Apple Türkiye App Store fiyatlarına **%20 KDV dahildir**. Apple KDV'yi devlete remit eder, kalan tutardan komisyon alır. Formül: `Net = Fiyat ÷ 1,20 × (1 − komisyon)`. Bu ek %14,3'lük düzeltme tüm gelir projeksiyonlarına yansıtılmıştır. Önceki hesaplamalar bu kalemi eksik içeriyordu.

**%30 komisyon ile (KDV %20 dahil):**
```
Net = Fiyat ÷ 1,20 × 0,70
Fiyat = 1 TL ÷ 0,5833 = 1,714 TL/teqlik  (₺1 net için gerçek hedef)
```
Mevcut fiyatlandırma: ₺149,99 → 100 teqlik → ₺0,875 net/teqlik

**%15 komisyon ile (Small Business, KDV %20 dahil):**
```
Net = Fiyat ÷ 1,20 × 0,85
Fiyat = 1 TL ÷ 0,7083 = 1,412 TL/teqlik  (₺1 net için gerçek hedef)
```
Mevcut fiyatlandırma: ₺119,99 → 100 teqlik → ₺0,850 net/teqlik

> **Öneri:** İlk lansman için %15 Small Business Program'a başvur, fiyatları buna göre belirle. Eğer programa girilemezse %30 hesabı geçerli.

### 2.3 Önerilen Paket Fiyatları

#### %30 Komisyon Senaryosu (Konservatif / Garantili)

| Paket | teqlik | Bonus | Toplam | App Store Fiyatı | Net Gelir (KDV+%30)¹ | Efektif TL/teqlik² |
|-------|--------|-------|--------|-----------------|----------------------|--------------------|
| Başlangıç | 100 | — | 100 | **₺149,99** | **₺87,49** | ₺1,50 |
| Popüler 🔥 | 300 | +50 | 350 | **₺429,99** | **₺250,83** | ₺1,23 |
| Avantaj 💎 | 700 | +150 | 850 | **₺999,99** | **₺583,33** | ₺1,18 |
| Mega | 1500 | +400 | 1900 | **₺2.199,99** | **₺1.283,33** | ₺1,16 |

> ¹ Net = Fiyat ÷ 1,20 × 0,70 (KDV %20 ve Apple %30 sonrası)
> ² Efektif TL/teqlik = App Store Fiyatı ÷ Toplam teqlik — kullanıcının ödediği birim maliyet

#### %15 Komisyon Senaryosu (Small Business — Önerilen)

| Paket | teqlik | Bonus | Toplam | App Store Fiyatı | Net Gelir (KDV+%15)¹ | Efektif TL/teqlik² |
|-------|--------|-------|--------|-----------------|----------------------|--------------------|
| Başlangıç | 100 | — | 100 | **₺119,99** | **₺84,99** | ₺1,20 |
| Popüler 🔥 | 300 | +50 | 350 | **₺349,99** | **₺247,91** | ₺1,00 |
| Avantaj 💎 | 700 | +150 | 850 | **₺829,99** | **₺587,91** | ₺0,98 |
| Mega | 1500 | +400 | 1900 | **₺1.749,99** | **₺1.239,58** | ₺0,92 |

> ¹ Net = Fiyat ÷ 1,20 × 0,85 (KDV %20 ve SBP %15 sonrası)
> ² Efektif TL/teqlik = App Store Fiyatı ÷ Toplam teqlik — kullanıcının ödediği birim maliyet

> **App Store Fiyat Tier'ları:** Apple'ın TRY tier listesi 2023 yeniden yapılandırması sonrası ~900 seçeneğe genişledi. ₺119,99 / ₺149,99 / ₺349,99 / ₺429,99 / ₺829,99 / ₺999,99 / ₺1.749,99 / ₺2.199,99 tier'larının App Store Connect → Pricing'den doğrulanması gerekiyor. Tam liste ancak App Store Connect'te görülüyor.

### 2.4 Birim Maliyet Rehberi (Kullanıcı Perspektifi)

**%30 / ₺149,99 → 100 teqlik paketi bazında:**

| İşlem | Maliyet | ₺149,99 Paketi ile |
|-------|---------|-------------------|
| AI Açıklama (5 teqlik) | ₺7,50 | 20 üretim |
| Blast / Kitle Bildirimi (10 teqlik) | ₺15,00 | 10 gönderim |
| İlan Yenileme (10 teqlik) | ₺15,00 | 10 yenileme |
| İlan Boost (50 teqlik) | ₺75,00 | 2 boost |

---

## 3. Apple App Store Uyum Gereksinimleri

### 3.1 Zorunlu Kurallar (İhlali = Red)

**Kural 3.1.1 — Zorunlu IAP:**
- teqlik dijital özellik kilidi açtığı için Apple IAP **zorunlu**
- Ekranda asla şu ibareler yer alamaz:
  - "Web sitemizden daha ucuza alın"
  - "Kredi kartı / havale ile öde"
  - Harici ödeme sitesine herhangi bir link

**Consumable Ürün Tipi:**
- App Store Connect'te ürün tipi: `Consumable` (Tüketilebilir)
- Abonelik (`Auto-Renewable Subscription`) veya `Non-Consumable` **değil**

**Hardcoded Fiyat Yasak:**
- ARB dosyalarına veya Dart koduna `₺149,99` yazılmaz
- Fiyat her zaman `ProductDetails.price` ile StoreKit'ten okunur
- Aynı kullanıcı ABD Apple ID ile giriş yapınca `$4.99`, DE ID ile `€4,49` görmeli

**Zorunlu Yasal Footer (App Review arar):**
```
Satın alınan teqlik'ler nakde çevrilemez veya devredilemez. 
Satın alımlar Apple Kimliği hesabınız üzerinden faturalandırılır.
[Kullanım Koşulları]  [Gizlilik Politikası]
```

### 3.2 UX Zorunlulukları

**İptal sessiz olmalı:** Kullanıcı Face ID / Touch ID ekranını kapattığında veya "İptal" dediğinde:
- Kırmızı snackbar yok
- Hata dialog yok
- Sessizce eski ekrana dön

**Çift tıklama koruması:** Paket tıklanınca tüm kartlar geçici `disabled` olur, StoreKit sheet açılana kadar başka dokunuş kabul edilmez.

**Bekleyen işlemler (Unfinished Transactions):** Kullanıcı ödeme onayladıktan sonra internet koparsa:
- Apple StoreKit transaction'ı kendi kuyruğunda tutar
- Uygulama her açılışında `purchaseStream` dinlenmeli
- Bekleyen fişler backend'e iletilip bakiye yüklenmeli
- Kullanıcının parası havada kalmamalı

---

## 4. Teknik Mimari

### 4.1 Flutter Tarafı

**Gereken paket:** `in_app_purchase` (pub.dev resmi plugin — iOS StoreKit 2 + Android Billing desteği)

**Önerilen modül yapısı** (profile_screen.dart'tan bağımsız):
```
mobile/lib/
  ├── models/
  │    └── teqlik_package.dart         // id, teqlikAmount, bonusAmount, isPopular, isBestValue
  ├── services/
  │    └── iap_service.dart            // StoreKit bağlantısı, purchaseStream yönetimi
  ├── screens/wallet/
  │    ├── viewmodels/
  │    │    └── wallet_view_model.dart // Riverpod Notifier: bakiye, paketler, satın alma durumları
  │    ├── wallet_screen.dart          // Ana Scaffold
  │    └── widgets/
  │         ├── teqlik_package_card.dart
  │         ├── hero_balance_card.dart
  │         └── teqlik_utility_guide.dart
```

> **Mevcut durum:** `WalletScreen` hâlâ `profile_screen.dart` içinde — 5000+ satırlık dosya. V1.0 implementasyonunda ayrı modüle çıkarılmalı.

### 4.2 Backend Tarafı

#### 4.2.1 Apple IAP Doğrulama

**Gerekli endpoint:** `POST /api/wallet/apple-verify`

**Akış:**
```
Mobil StoreKit   →  signedTransactionInfo (JWS)  →  POST /api/wallet/apple-verify
                                                          │
                                               JWS doğrulama (Apple x5c sertifika zinciri)
                                                          │
                                               transaction_id unique check (Replay koruması)
                                                          │
                                               teqlik_balance += amount  (atomik)
                                                          │
                                               TeqlikTransaction kaydı
                                                          │
                                               200 OK → {new_balance: X}
```

**Kritik: JWS Doğrulama Detayları**
- Apple App Store Server API v2 → JWS formatında imzalı JWT
- Doğrulama için Apple'ın x5c sertifika zinciri verify edilmeli: `rootCA → G3 CA → leaf cert`
- Python kütüphanesi: `PyJWT` + `cryptography` paketi
- **Sandbox vs Production:** Farklı Apple endpoint'leri kullanılır:
  - Sandbox: `api.sandbox.storekit.itunes.apple.com`
  - Production: `api.storekit.itunes.apple.com`
- Konfigürasyonda `APPLE_ENVIRONMENT=sandbox|production` ayrımı zorunlu

**JWS Doğrulama — Zorunlu Güvenlik Kontrolleri (`verify_apple_receipt_command.py`):**
```python
# JWS decode edildikten sonra payload'da şunlar HARDCODED doğrulanmalı:
assert payload["environment"] == "Production"          # Sandbox makbuzu prod'a geçemez
assert payload["bundleId"]    == "com.teqlif.app"      # Başka uygulamanın makbuzu reddedilir
assert payload["productId"]   in VALID_PRODUCT_IDS     # Sadece bilinen 4 paketin ID'si
# Bu 3 kontrol atlansa jailbreak araçlarıyla (LocalIAPStore) bedavadan teqlik yüklenebilir.
```

**Günlük IAP Hız Limiti (Velocity Limit):**
```
Aynı Apple ID / cihaz kimliğinden 24 saatte maksimum ₺5.000 satın alma.
Eşik aşılırsa: 429 → fraud_flag = True → admin incelemesi.
Teqlik_transactions tablosunda device_id (StoreKit appAccountToken) saklanmalı.
```

**Replay Saldırısı Koruması:**
```sql
-- Gerekli migration:
ALTER TABLE teqlik_transactions ADD COLUMN apple_transaction_id VARCHAR(64) UNIQUE;
```
Aynı `transaction_id` ile ikinci istek → HTTP 409 dönmeli, bakiye yüklenmemeli.

**Refund / Revocation — ⚠️ V1.0 ZORUNLU:**
Apple bir satın alımı geri alabilir (`REFUND` App Store Server Notification). "Görmezden gel" politikası aktif bir açık yaratır: kullanıcı büyük paket alır, tüm özellikleri hemen harcar (boost, blast), ardından Apple'dan iade alır. Teqlif para iadesi yapar ama harcanan teqlik geri dönmez. Türkiye mobil gaming'de "refund çetesi" belgelenmiş bir risktir.

**Politika (V1.0 zorunlu):**
- `REFUND` event → apple_transaction_id ile işlemi bul
- Bakiyeden düş (iade edilen teqlik miktarı kadar)
- Bakiye < 0 olursa: `pending_refund` flag + insan incelemesi tetikle
- Tüm refund olayları `refund_log` tablosuna yaz

**Refund webhook akışı:**
```
Apple → POST /api/wallet/apple-notifications
  eventType: "REFUND"
  → apple_transaction_id ile TeqlikTransaction'ı bul (iade_miktarı, orijinal_miktar)
  → teqlik_balance -= iade_miktarı  (atomik)
  → bakiye < 0 ise: users.pending_refund = true

  → Orantılı hediye kazancı iptali (anti-fraud):
       iade_oranı = iade_miktarı / orijinal_miktar
       iptal_tl   = users.tl_pending_balance × iade_oranı
       UPDATE gift_events
         SET payout_status = 'cancelled_refund'
         WHERE sender_id = kullanıcı
           AND payout_status = 'pending'
         ORDER BY sent_at ASC          -- en eskiden başla
         LIMIT (en fazla iptal_tl'yi karşılayana kadar)
       tl_pending_balance -= iptal_tl  (atomik)

     Not: IAP transaction → bireysel hediyeler arasında tam iz mümkün değil;
     orantılı iptal yaklaşık ama yeterli koruma sağlar. Sadece 'pending'
     bakiye etkilenir — zaten released olan kazançlara dokunulmaz.

  → RefundLog kaydı oluştur (iade_miktarı + iptal_tl)
  → 200 OK döndür (Apple retry yapar 4xx'te)
```

#### 4.2.2 Yayıncı TL Kazanç Sistemi (V1.0)

**Yeni tablolar (migration gerekli):**
```sql
-- ── V1.0 Migration ────────────────────────────────────────────────────────────
-- users tablosuna ekle
ALTER TABLE users
  ADD COLUMN tl_earnings_balance  NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN tl_pending_balance   NUMERIC(10,2) NOT NULL DEFAULT 0.00;
  -- ⚠️ tl_earnings_balance'a CHECK (>= 0) KONULMAMALI:
  -- Apple iadesi geldiğinde bakiye negatife düşebilir (borç mahsubu).
  -- DB constraint hatası Apple webhook'unun 500 alıp sonsuz retry'a girmesine yol açar.

-- Çekim talepleri — V1.0: talep toplama modeli (gerçek transfer V1.5)
CREATE TABLE withdrawal_requests (
  id                SERIAL PRIMARY KEY,
  user_id           INTEGER NOT NULL REFERENCES users(id),
  amount_tl         NUMERIC(10,2) NOT NULL,
  iban              VARCHAR(34) NOT NULL,
  account_holder    VARCHAR(120) NOT NULL,
  status            VARCHAR(20) NOT NULL DEFAULT 'pending',
                    -- pending | approved | completed | rejected
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at      TIMESTAMPTZ,
  admin_note        TEXT
);
-- V1.5'te eklenecek kolonlar (şimdi eklenmez):
--   fee_tl NUMERIC(10,2), mernis_name VARCHAR(120), mernis_verified_at TIMESTAMPTZ

-- ── V1.5 Migration (şimdi yazılmaz, referans) ─────────────────────────────────
-- ALTER TABLE users
--   ADD COLUMN monthly_free_withdrawals_used INTEGER NOT NULL DEFAULT 0,
--   ADD COLUMN rolling_reserve_expires_at    TIMESTAMPTZ,
--   ADD COLUMN rolling_reserve_limit_tl      NUMERIC(10,2) NOT NULL DEFAULT 2500.00,
--   ADD COLUMN is_in_debt                    BOOLEAN NOT NULL DEFAULT false,
--   ADD COLUMN account_frozen                BOOLEAN NOT NULL DEFAULT false,
--   ADD COLUMN account_frozen_reason         VARCHAR(120),
--   ADD COLUMN mernis_verified               BOOLEAN NOT NULL DEFAULT false,
--   ADD COLUMN mernis_verified_at            TIMESTAMPTZ;
-- CREATE TABLE user_kyc (  -- TCKN şifreli (AES-256), düzyazı asla DB'de olmaz
--   user_id INTEGER PRIMARY KEY REFERENCES users(id),
--   tckn_encrypted BYTEA NOT NULL,
--   birth_year SMALLINT NOT NULL,
--   created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- );

-- gift_events tablosuna kazanç takip kolonları
-- (T+14 cron ve refund iptali için event bazında iz)
-- earnings_tl: NUMERIC(10,4) — 1 teqlik × %95 × ₺0,50 = ₺0,4750; 2 hane ile saklanamaz.
-- Kullanıcı bakiyelerine aktarımda ROUND_DOWN(2) uygulanır (bkz. T+14 cron ve withdraw).
ALTER TABLE gift_events
  ADD COLUMN earnings_tl   NUMERIC(10,4) NOT NULL DEFAULT 0.0000,
  ADD COLUMN payout_status VARCHAR(20)   NOT NULL DEFAULT 'pending',
                           -- pending | released | cancelled_refund
  ADD COLUMN released_at   TIMESTAMPTZ;

CREATE INDEX idx_gift_events_payout
  ON gift_events (payout_status, sent_at)
  WHERE payout_status = 'pending';
```

**Rate Limiting — send-gift (Redis Token Bucket):**
```
Canlı yayında saniyede 50 hediye → PostgreSQL + Redis + WebSocket kilitlenir.
Kullanıcı başına sınır (Redis SETNX + TTL):
  Normal:  saniyede maks. 2 hediye (burst: 5)
  Aşılırsa: HTTP 429 — "Çok hızlı! Biraz bekleyin."
  Kötü niyet tespiti (burst limit 10×): sender'ı 10 dakika bloke et.

Redis key: rate:gift:{sender_id}  |  TTL: 1 saniye  |  increment > limit → red
```

**Güncellenecek Use Case — `app/use_cases/wallet/commands/send_gift_command.py`:**

Clean Architecture kuralı gereği iş mantığı `wallet.py` router'da değil; `app/use_cases/wallet/commands/` altında ayrı command sınıflarında tutulur (mevcut `transfer_teqlik.py` patterniyle aynı). Tüm wallet use case'leri:
```
app/use_cases/wallet/
  commands/
    send_gift_command.py          ← TL dönüşüm + atomik SQL
    request_withdrawal_command.py ← ücret hesabı + credit_service.py
    verify_apple_receipt_command.py
    handle_apple_refund_command.py
  queries/
    get_wallet_summary_query.py
```

```
İzleyici → hediye seçer (gift_name + cost) → stream_id ile gönderir
  Gönderenden:   teqlik_balance -= cost                              (atomik ham SQL)
  Yayıncıya:     tl_pending_balance += ROUND_DOWN(cost × pay_rate × 0,50, 2)  (atomik)
  gift_events:   earnings_tl = Decimal(str(cost)) * pay_rate * Decimal("0.50")
                 → NUMERIC(10,4) olarak kayıt — kuruş kaybı olmadan
  Platform net:  kalan Teqlif kasasında

  Decimal hassasiyeti (zorunlu): Python float yerine Decimal kullan.
    earnings = Decimal(str(cost)) * Decimal(str(pay_rate)) * Decimal("0.50")
    earnings_rounded = earnings.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    tl_pending_balance += earnings_rounded  (ham SQL ile atomik)
```
Dönüşüm kuru: **1 teqlik hediye = ₺0,50 net nakit** (V1.0'da sabit kur)

Geçerli hediye tipleri: `clap`(1) · `tea`(5) · `fire`(10) · `diamond`(50) · `crown`(100) · `golden_hammer`(250) · `rocket`(500) · `trophy`(1000)

| Katman | Hediye | Maliyet | PRO host (%95) | Std host (%70) | Teqlif net (PRO) | Teqlif net (Std) |
|--------|--------|---------|----------------|----------------|-----------------|-----------------|
| Mikro | 👏 Alkış | 1 teqlik | ₺0,47 | ₺0,35 | ₺0,40 | ₺0,53 |
| Mikro | ☕ Çay | 5 teqlik | ₺2,37 | ₺1,75 | ₺2,00 | ₺2,63 |
| Standart | 🔥 Alev | 10 teqlik | ₺4,75 | ₺3,50 | ₺4,00 | ₺5,25 |
| Standart | 💎 Elmas | 50 teqlik | ₺23,75 | ₺17,50 | ₺20,00 | ₺26,25 |
| Premium | 👑 Taç | 100 teqlik | ₺47,50 | ₺35,00 | ₺40,00 | ₺52,50 |
| Premium | 🔨 Altın Tokmak | 250 teqlik | ₺118,75 | ₺87,50 | ₺100,00 | ₺131,25 |
| VIP | 🚀 Roket | 500 teqlik | ₺237,50 | ₺175,00 | ₺200,00 | ₺262,50 |
| VIP | 🏆 Şampiyon Kupası | 1.000 teqlik | ₺475,00 | ₺350,00 | ₺400,00 | ₺525,00 |

> Teqlif net = cost × 0,875 (100-pak IAP net/teqlik) − host payı. Mega paketten alındığında (0,675 TL/teqlik) net ₺0,20–₺0,40/teqlik'e iner — tüm senaryolarda Teqlif kârdadır.

**Yeni endpointler (router yalnızca delege eder, mantık use case'lerde):**
```
GET  /api/wallet/summary  →  get_wallet_summary_query.py
  → { teqlik_balance, tl_earnings_balance, tl_pending_balance,
      free_withdrawals_remaining }   ← 2 - monthly_free_withdrawals_used

POST /api/wallet/withdraw  →  request_withdrawal_command.py
  — V1.0: TALEP TOPLAMA MODU (gerçek banka transferi yok) —
  Body: { amount_tl, iban, account_holder_name }
  Kurallar:
    - amount_tl >= 500  (minimum çekim)
    - Kullanıcının aktif pending talebi yoksa işlem alınır (çift talep önlemi)
      SELECT id FROM withdrawal_requests
        WHERE user_id = :uid AND status IN ('pending','approved') LIMIT 1
      Varsa: 409 "İncelemede bekleyen bir talebiniz var"
    - Bakiye atomik olarak ANINDA düşülür (double-spend önlemi):
        UPDATE users
          SET tl_earnings_balance = tl_earnings_balance - :amount_tl
          WHERE id = :uid AND tl_earnings_balance >= :amount_tl
          RETURNING tl_earnings_balance;
        -- 0 satır dönerse → 400 yetersiz bakiye
    - withdrawal_requests INSERT (status='pending') — aynı transaction içinde
    - Yanıt mesajı (Seçenek A):
        "Talebiniz başarıyla alındı. Lansman beta dönemi kapsamında ilk çekim
         talepleri güvenlik incelemesinin ardından işleme alınacaktır."
  → 200 OK | 400 yetersiz bakiye / limit | 409 aktif talep var

  Admin Red Akışı (admin panel):
    UPDATE users SET tl_earnings_balance = tl_earnings_balance + :amount_tl WHERE id = :uid;
    UPDATE withdrawal_requests SET status='rejected', admin_note=:note, processed_at=NOW()
      WHERE id = :wid;
    → Bakiye kullanıcıya anında iade edilir; kullanıcıya bildirim gönderilir.

  — Seçenek C: Kazancı Teqlik'e Dönüştür (+%10 Bonus) —
  POST /api/wallet/convert-to-teqlik
    Body: { amount_tl }
    Kurallar:
      - tl_earnings_balance >= amount_tl
      - teqlik_amount = FLOOR(amount_tl / 0.875) * 1.10  (100-pak kur + %10 bonus)
      - tl_earnings_balance -= amount_tl  (atomik)
      - teqlik_balance += teqlik_amount  (atomik)
    → Para ekosisteme kilitlenir, gerçek transfer gerekmez.
    → Yayıncıya motivasyon: "Kazancınla 110 teqlik al, 100 teqlik fiyatına!"
```

> **V1.5'te eklenecek (withdraw tam akış):** MERNIS/KYC doğrulama, IBAN checksum, Redis distributed lock, atomik SQL WHERE bakiye düşümü, ₺15 çekim ücreti, PRO 2× ücretsiz kota, Rolling Reserve limiti, banka transfer API entegrasyonu.

**T+14 Holding — ARQ cron görevi (idempotent):**

Her iki cron görevi `worker.py`'ye değil; **`deploy/scale/V2.1/schedule.yaml`** dosyasına `batch` altında eklenir. `schedule_loader.py` bu dosyayı okur, `teqlif-agent/watchdog.py` görevi izler — cron doğrudan koda yazılırsa agent tarafından izlenemez.

```python
# Her gün 02:00 UTC — pending → released (tam idempotent)
# schedule.yaml: batch.release_pending_earnings, watchdog_m: 30
async def release_pending_earnings_task():
    """14 günü dolan gift_events.payout_status='pending' → 'released', balance aktar."""
    # BEGIN TRANSACTION
    #
    # 1. Aktarılacak hediyeleri kilitle ve topla
    #    SELECT receiver_id, SUM(earnings_tl) AS total_raw
    #    FROM gift_events
    #    WHERE payout_status = 'pending'
    #      AND sent_at <= NOW() - INTERVAL '14 days'
    #    GROUP BY receiver_id
    #    FOR UPDATE SKIP LOCKED
    #
    # 2. Kullanıcı bakiyelerini güncelle — TRUNC(total_raw, 2) uygulanır
    #    (gift_events.earnings_tl NUMERIC(10,4); kullanıcıya aktarılırken 2 haneye indirilir)
    #    PostgreSQL ROUND(x,2) en yakına yuvarlar — 0.4750 → 0.48 (yanlış).
    #    TRUNC(x,2) aşağı keser     — 0.4750 → 0.47 (doğru, platform aleyhine kuruş yok).
    #    UPDATE users SET
    #      tl_earnings_balance += TRUNC(total_raw, 2),
    #      tl_pending_balance  -= TRUNC(total_raw, 2)
    #    WHERE id = receiver_id
    #
    # 3. Event'leri released olarak işaretle
    #    UPDATE gift_events SET
    #      payout_status = 'released',
    #      released_at   = NOW()
    #    WHERE payout_status = 'pending'
    #      AND sent_at <= NOW() - INTERVAL '14 days'
    #
    # COMMIT
    #
    # Cron iki kez çalışsa, yeniden başlasa, yarıda kalsa güvenli:
    # 'released' satırlar WHERE payout_status = 'pending' koşuluna girmez.

# Her ayın 1'i 00:05 UTC — PRO çekim kotasını sıfırla
# schedule.yaml: batch.reset_monthly_withdrawal_quota, watchdog_m: 60
async def reset_monthly_withdrawal_quota_task():
    # UPDATE users SET monthly_free_withdrawals_used = 0 WHERE is_pro = true
```

> **Neden T+14:** Apple chargebackları teorik 120 güne kadar açık olsa da pratikte %99'u 14 gün içinde kapanır. Daha uzun beklemek yayıncı deneyimini bozar. Büyük miktarlarda (>₺5.000 tek hediye) T+30 uygulanabilir (V1.1 iyileştirmesi).

**Çekim Sonrası Apple İadesi — Negatif Bakiye ve Borç Mahsubu:**

T+14 penceresi chargebackların büyük çoğunluğunu yakalar; ancak Apple iadesi teorik olarak 120 güne kadar açıktır. Para çekildikten sonra iade gelirse:

```
Apple → REFUND webhook (18. gün, para çekilmişti)
  → apple_transaction_id ile TeqlikTransaction bul
  → teqlik_balance -= iade_miktarı  (atomik)
  → Orantılı gift iptali (payout_status='cancelled_refund', yukarıdaki refund akışı)
  → İptal edilecek pending bakiye kalmamışsa (para çekilmiş):
       tl_earnings_balance -= iptal_tl  → bakiye negatife düşebilir
       users.pending_refund = True      → admin incelemesi tetiklenir

Sonraki yayın kazançları negatif bakiyeyi kapatır (borç mahsubu):
  tl_earnings_balance 0'ın altındayken T+14 aktarımı durdurmaz — kazançlar
  negatif bakiyeyi karşılayana kadar tl_earnings_balance'ta birikir,
  yayıncı çekim talebinde bakiye > 0 ise izin verilir.

⚠️ tl_earnings_balance'a CHECK (tl_earnings_balance >= 0) constraint'i KONULMAMALI:
   Apple webhook isteği DB constraint hatasıyla 500 dönerse Apple sonsuz retry
   döngüsüne girer ve aynı iade birden çok kez işlenebilir.
```

### 4.4 Güvenlik & Anti-Fraud Mimarisi

**V1.0'da aktif olan güvenlik katmanları:**

| Katman | Mekanizma | Amaç |
|--------|-----------|-------|
| IAP güvenliği | JWS environment + bundleId + productId hardcoded | Sandbox / sahte makbuz engeli |
| IAP hız limiti | Redis velocity ₺5.000/gün/cihaz | Çalıntı kart flood |
| send-gift hız limiti | Redis Token Bucket 2/sn per user | DB/WS flood |
| Replay koruması | apple_transaction_id UNIQUE | Çift yükleme |
| Çift talep önlemi | Aktif pending varken yeni talep reddi | Aynı bakiyeye çift talep |
| Refund → gift iptali | Orantılı payout_status='cancelled_refund' | IAP iadesi hediye kazancını iptal eder |
| Negatif bakiye | CHECK constraint yok; tl_earnings_balance eksilir | Apple webhook 500 vermez |
| T+14 kilitli bakiye | pending bakiye 14 gün çekilemez | Apple iade penceresi sigortası |

**V1.5'te devreye girecek güvenlik katmanları:**

**Rolling Reserve — Yeni Yayıncı Kademeli Çekim Kotası:**
```
Hesap oluşturulunca: rolling_reserve_expires_at = NOW() + 90 gün
İlk 90 gün:  maksimum tek çekim = rolling_reserve_limit_tl (₺2.500)
90 gün sonra: sınır kalkar
```
Organize refund çetelerinin "teqlik al → hediye yağdır → ₺9.500 çek → iadeyi al" döngüsünü maddi olarak imkânsız kılar.

**MERNIS / KYC Doğrulama (İlk Gerçek Çekim Zorunlu):**
```
NVİ MERNIS SOAP API: TCKN + Ad + Soyad + Doğum Yılı doğrulama
TCKN: AES-256 şifreli user_kyc tablosunda — veritabanında düzyazı asla yok
Admin onayında: IBAN alıcı adı ↔ MERNIS adı birebir eşleşmeli
```
Emniyet / Savcılık yazısında kimliğe anında ulaşılır.

**Negatif Bakiye & Borç Mahsubu:**
```
Çekim sonrası iade → tl_earnings_balance negatife düşer → is_in_debt = true
Sonraki kazançlar eksi bakiyeyi kapatır (borç mahsubu)
30 gün ödenmez → account_frozen = true → tüm ilanlar pasif
```

**Admin Maker-Checker:**
```
₺2.500 altı:  tek admin onayı
₺2.500–₺10.000: iki admin onayı
₺10.000+:    Maker-Checker + 2FA
Her onay audit_log'a yazılır (kim, ne zaman, IP)
```

**IBAN Checksum + Banka API:**
```
TR + 24 karakter + mod-97 format kontrolü
Kurumsal banka toplu ödeme API'si (şirket kuruluşu sonrası)
```

### 4.3 Mevcut Backend Durumu

| Bileşen | Durum |
|---------|-------|
| `teqlik_balance` kolonu (users) | ✅ Mevcut |
| `TeqlikTransaction` tablosu | ✅ Mevcut |
| `credit_service.py` (harcama sistemi) | ✅ Olgun |
| `wallet.py` router `/topup-manual` | ⚠️ 503 dönüyor (placeholder) |
| `POST /api/wallet/apple-verify` | ❌ Yazılmamış |
| JWS doğrulama kütüphanesi | ❌ Kurulmamış |
| `apple_transaction_id` unique index | ❌ Migration yok |
| Sandbox/production config | ❌ Yok |

**V1.0 kapsamı:**

| Bileşen | Durum |
|---------|-------|
| `tl_earnings_balance` + `tl_pending_balance` (users) | ❌ Migration yok |
| `withdrawal_requests` tablosu (talep toplama) | ❌ Migration yok |
| `gift_events` (`earnings_tl` NUMERIC(10,4), `payout_status`, `released_at`) | ❌ Migration yok |
| `use_cases/wallet/commands/` + `queries/` use case yapısı | ❌ Yazılmamış |
| `verify_apple_receipt_command.py` (JWS + env/bundleId + velocity limit) | ❌ Yazılmamış |
| `send_gift_command.py` (Decimal + atomik SQL + Redis rate limit) | ❌ Yazılmamış |
| `request_withdrawal_command.py` (talep modu — bakiye kontrolü + pending insert) | ❌ Yazılmamış |
| `convert_to_teqlik_command.py` (Seçenek C, +%10 bonus) | ❌ Yazılmamış |
| `get_wallet_summary_query.py` | ❌ Yazılmamış |
| Refund webhook → orantılı gift iptali + negatif bakiye | ⚠️ Güncellenmeli |
| `schedule.yaml` T+14 cron (`release_pending_earnings`, watchdog_m:30) | ❌ Eklenmemiş |

**V1.5 kapsamı (şimdi yazılmaz):**

| Bileşen | Not |
|---------|-----|
| MERNIS/KYC kolonları + `user_kyc` şifreli tablo | Şirket kuruluşu sonrası |
| Rolling Reserve kolonları | Gerçek transfer başlayınca |
| `is_in_debt`, `account_frozen` kolonları | V1.5 migration |
| `monthly_free_withdrawals_used` + aylık reset cron | Gerçek ücret akışıyla birlikte |
| `request_withdrawal_command.py` tam akış (MERNIS + lock + atomik düşüm + ücret) | V1.5 rewrite |
| Admin Maker-Checker paneli | Şirket + banka API sonrası |
| Banka transfer API entegrasyonu | Şirket kuruluşu zorunlu |

---

## 5. UX & Ekran Mimarisi

### 5.1 Ekran Yapısı (Onaylanan — İki Bölmeli Cüzdan)

```
┌──────────────────────────────────────────────┐
│  AppBar: Cüzdanım         [İşlem Geçmişi]    │
├──────────────────────────────────────────────┤
│  ╔══════════════════════════════════════════╗ │
│  ║  KART 1: teqlik Bakiyem                 ║ │
│  ║  • Bakiye: 140 teqlik  [PRO rozeti]     ║ │
│  ║  • Bakiye yüklenince sayı yukarı sayar  ║ │
│  ║  [  teqlik Satın Al  ]                  ║ │
│  ║  *(Bu bakiye ASLA nakde çevrilemez)*    ║ │
│  ╚══════════════════════════════════════════╝ │
├──────────────────────────────────────────────┤
│  ╔══════════════════════════════════════════╗ │
│  ║  KART 2: Yayın Kazançlarım  [herkese]   ║ │
│  ║                                          ║ │
│  ║  [Kazanç varsa — yayıncı]               ║ │
│  ║  • Mevcut bakiye: ₺1.450,00             ║ │
│  ║  • Bekleyen (T+14): ₺230,00             ║ │
│  ║                                          ║ │
│  ║  [ Teqlik'e Dönüştür (+%10 bonus) ]     ║ │
│  ║  [ Çekim Talebi Oluştur (IBAN)    ]     ║ │
│  ║                                          ║ │
│  ║  ⚠️ Çekim talepleri beta güvenlik       ║ │
│  ║  incelemesi sonrası işleme alınır        ║ │
│  ║  Min. çekim ₺500 — Kaynak: hediyeler    ║ │
│  ║                                          ║ │
│  ║  [Kazanç yoksa — henüz yayın yapmamış]  ║ │
│  ║  💡 Yayın aç, izleyicilerden hediye     ║ │
│  ║     topla, IBAN'ına nakit kazan!        ║ │
│  ║  [  Yayın Başlat  ]                     ║ │
│  ╚══════════════════════════════════════════╝ │
├──────────────────────────────────────────────┤
│  2 sütunlu paket grid (4 kart)               │
│  ┌──────────────┐  ┌──────────────┐         │
│  │  100 teqlik  │  │ 🔥 EN POPÜLER│         │
│  │   ₺149,99    │  │  300 teqlik  │         │
│  │              │  │   ₺429,99    │         │
│  │              │  │  (+50 Bonus) │         │
│  └──────────────┘  └──────────────┘         │
│  ┌──────────────┐  ┌──────────────┐         │
│  │💎 EN İYİ DEĞ.│  │ 1500 teqlik  │         │
│  │  700 teqlik  │  │   ₺2.199,99  │         │
│  │   ₺999,99    │  │ (+400 Bonus) │         │
│  │ (+150 Bonus) │  │              │         │
│  └──────────────┘  └──────────────┘         │
├──────────────────────────────────────────────┤
│  "teqlik ile neler yapabilirsin?"            │
│  ⚡ 50 teqlik = 1 İlan Boost                 │
│  📣 10 teqlik = Kitle Bildirimi (Blast)      │
│  🤖 5 teqlik  = AI Açıklama                  │
│  🔄 10 teqlik = İlan Yenileme                │
├──────────────────────────────────────────────┤
│  [Yasal footer — zorunlu Apple metni]        │
└──────────────────────────────────────────────┘
```

> **Apple uyum notu:** teqlik satın alma Kart 1'de — tamamen IAP üzerinden, Kural 3.1.1 uyumlu. Kart 2 yalnızca izleyicilerden kazanılan geliri gösteriyor; kullanıcı satın aldığı teqliği nakde çeviremiyor. Apple bu modele itiraz etmiyor (TikTok, Twitch aynı ayrımı kullanıyor). Kart 2'nin tüm kullanıcılara gösterilmesi — kazanç yokken "Yayın Başlat" CTA'sıyla — organik büyüme döngüsü yaratır: sıradan alıcı/satıcıyı yayıncıya dönüştürür.

### 5.2 Satın Alma Akışı

```
[Kart Tıklandı]
      │
      ▼
[Haptic Light] + Tüm kartlar disabled
      │
      ▼
[StoreKit Sheet — Face ID / Touch ID]
      │
      ├─► [İptal] ──► Sessizce kapat, kartlar re-enabled
      │
      ▼
[Apple Ödemesi Onaylandı]
      │
      ▼
[Overlay: "Ödemeniz doğrulanıyor..."]
      │
      ▼
[POST /api/wallet/apple-verify]
      │
      ├─► [200 OK]  ──► Haptic Heavy + Konfeti animasyonu
      │                 Bakiye sayacı yukarı sayar
      │                 CreditsChangedEvent fire edilir
      │                 TeqSnackBar: "300 teqlik yüklendi!"
      │
      └─► [Ağ Hatası / Gecikme] ──► StoreKit kuyruğa alır
                                   "Ödemeniz güvende, kontrol ediliyor."
                                   Uygulama açılışında tekrar denenir
```

---

## 6. Implementasyon Sırası (Öncelik Sıralı)

### 6.1 teqlik IAP (Satın Alma)

| # | Görev | Yapan | Blokör mu? |
|---|-------|-------|-----------|
| 1 | App Store Connect — 4 Consumable IAP ürünü kaydet | **Kullanıcı** | Evet |
| 2 | Apple Small Business Program'a başvur | **Kullanıcı** | Evet (fiyat etkiler) |
| 3 | `apple_transaction_id UNIQUE` migration | Backend | Evet |
| 4 | Backend `POST /api/wallet/apple-verify` + JWS doğrulama | Backend | Evet |
| 4b | Backend `POST /api/wallet/apple-notifications` + Refund webhook | Backend | **Evet** |
| 5 | Sandbox test ortamı konfigürasyonu | Backend | Evet |
| 6 | `in_app_purchase` Flutter paketi ekle | Mobile | Evet |
| 7 | `IAPService` + `purchaseStream` dinleyici | Mobile | Evet |
| 8 | `WalletScreen` modüle taşı + paket grid UI | Mobile | Hayır |
| 9 | Hero Balance Card animasyonu | Mobile | Hayır |
| 10 | Konfeti / başarı animasyonu (Lottie) | Mobile | Hayır |
| 11 | App Store Review öncesi yasal footer kontrolü | QA | Evet |

### 6.2 Yayıncı TL Kazanç & Çekim Sistemi — V1.0 Görevleri

| # | Görev | Yapan | Blokör mu? |
|---|-------|-------|-----------|
| W1 | Migration: users (tl_earnings_balance, tl_pending_balance) + `withdrawal_requests` (id, user_id, amount_tl, iban, account_holder, status, created_at, processed_at, admin_note) + `gift_events` (earnings_tl NUMERIC(10,4), payout_status, released_at) | Backend | Evet |
| W2 | `gift_events` payout index (`idx_gift_events_payout`) | Backend | Evet |
| W3 | `use_cases/wallet/commands/` yapısı oluştur | Backend | Evet |
| W4 | `verify_apple_receipt_command.py`: x5c zincir + environment/bundleId/productId hardcoded + velocity limit (Redis, ₺5.000/gün/cihaz) | Backend | Evet |
| W5 | `send_gift_command.py`: Decimal hassasiyeti + atomik SQL + Redis Token Bucket (2/sn per user) + 8 hediye tipi | Backend | Evet |
| W6 | `get_wallet_summary_query.py`: teqlik + TL bakiyeleri tek sorguda | Backend | Evet |
| W7 | `request_withdrawal_command.py`: bakiye atomik düşüm (UPDATE WHERE tl_earnings_balance >= amount, 0 satır → 400) + aktif pending yok kontrolü + withdrawal_requests INSERT — aynı transaction | Backend | Evet |
| W7b | `convert_to_teqlik_command.py`: Seçenek C (+%10 bonus, atomik SQL) | Backend | Evet |
| W7c | `schedule.yaml`: `release_pending_earnings` (02:00 UTC, watchdog_m:30) | Backend | Evet |
| W8 | `handle_apple_refund_command.py`: orantılı gift iptali + negatif bakiye desteği | Backend | Evet |
| W9 | Cüzdan Kart 2 UI: kazanç > 0 → "Teqlik'e Dönüştür" + "Çekim Talebi"; kazanç = 0 → "Yayın Başlat" CTA | Mobile | Hayır |
| W10 | Çekim talebi formu (IBAN + ad-soyad; beta güvenlik notu göster) | Mobile | Hayır |
| W11 | 5 dil ARB: `giftNameClap`, `giftNameTea`, `giftNameGoldenHammer`, `giftNameRocket`, `giftNameTrophy`, `walletConvertToTeqlik`, `walletWithdrawRequestNote`, `walletPendingEarningsDesc` | Mobile | Hayır |
| W12 | Admin panel: bekleyen çekim talepleri listesi + Onayla / Reddet butonları (red durumunda bakiye iadesi: `tl_earnings_balance += amount_tl`) | Backend/Admin | Hayır |

### 6.3 V1.5'e Ertelenen Özellikler

Aşağıdaki özellikler **şirket kuruluşu tamamlanana ve gerçek banka transfer akışı hazırlanana kadar** kodlanmaz.

| # | Özellik | Ön koşul | Notlar |
|---|---------|---------|--------|
| V15-1 | Gerçek banka transfer API entegrasyonu | LTD/şahıs şirketi + kurumsal banka anlaşması | MASAK zorunlu; şahıs olarak büyük tutarlar sorun çıkarır |
| V15-2 | MERNIS/KYC: TCKN doğrulama (NVİ SOAP API) | Şirket kaydı + API sözleşmesi | `user_kyc` şifreli tablo; AES-256 |
| V15-3 | Rolling Reserve (ilk 90 gün ₺2.500 limit) | Gerçek transfer başlayınca | `rolling_reserve_expires_at` + `rolling_reserve_limit_tl` migration |
| V15-4 | `account_frozen` & `is_in_debt` zorunlu takibi | Gerçek transfer başlayınca | 30 gün ödenmeyen borç → hesap dondur |
| V15-5 | `monthly_free_withdrawals_used` + aylık reset cron | Gerçek transfer + PRO abonelik sistemi | PRO kullanıcıya 2× ücretsiz çekim hakkı |
| V15-6 | Çekim ücreti (₺15 / işlem) + PRO 2× ücretsiz kota | Gerçek transfer | `withdrawal_requests.fee_tl` kolonu V1.5 migration'ında eklenir |
| V15-7 | IBAN checksum (TR + 24 karakter + mod-97) | V1.5 form | V1.0'da yalnızca uzunluk kontrolü yeterli |
| V15-8 | Admin Maker-Checker (₺2.500+ çift onay, ₺10.000+ 2FA) | Gerçek transfer | Audit log zorunlu |
| V15-9 | `request_withdrawal_command.py` tam akış | Tüm V1.5 bileşenleri | V1.0 sürümü komple rewrite edilir |
| V15-10 | Web mağazası (teqlif.com/cuzdan, %2,5 işlemci ücreti) | Şirket + web ödeme altyapısı | Apple bypass — yalnızca web alımlar |

---

## 7. Analizde Güçlü / Eksik Noktalar

### 7.1 Analizde Doğru ve Kritik

- Apple Kural 3.1.1 zorunlu IAP uyarısı ✅
- Consumable ürün tipi ✅
- Hardcoded fiyat yasağı ✅
- İptal sessiz olmalı ✅
- Bekleyen işlem (Unfinished Transaction) uyarısı ✅
- Mimari modülerleştirme önerisi ✅
- Yasal footer zorunluluğu ✅

### 7.2 Analizde Eksik Kalan

- **JWS Sandbox vs Production farkı** — belirtilmemiş, runtime hatası riski
- **Replay saldırısı** — `apple_transaction_id` unique index belirtilmemiş
- **Refund/Revocation** — Apple iade bildirimi senaryosu hiç değinilmemiş
- **App Store Connect Price Tier kısıtlaması** — istediğin TL fiyatını yazamazsın, tier'lardan seçilir
- **Small Business Program** — %15 seçeneğinden hiç bahsedilmemiş (fiyatı %21 ucuzlatıyor)
- **Android** — Google Play Billing tamamen farklı; analiz yalnızca iOS kapsamında
- **StoreKit 2 vs StoreKit 1** — hangi versiyon kullanılacağı belirsiz (StoreKit 2 iOS 15+ gerektirir)

---

## 8. teqlik Ekosistem Haritası & Genişleme Alanları

### 8.1 Mevcut teqlik Kullanım Alanları

| Alan | Ekran | Maliyet | Durum |
|------|-------|---------|-------|
| AI Açıklama | İlan Ver (create_listing_screen) | 5 teqlik | ✅ Aktif |
| İlan Yenileme | İlan Detay + Profil toggle | 10 teqlik | ✅ Aktif |
| Blast / Kitle Bildirimi | İlan Detay | 10 teqlik | ✅ Aktif |
| İlan Boost (Öne Çıkarma) | İlan Detay | 50 teqlik | ✅ Aktif |

### 8.2 Hediye (Gift) Sistemi — Canlı Yayın

**Kapsam: Hediyeler yalnızca canlı yayın sırasında gönderilebilir.** Genel kullanıcı-kullanıcı hediyesi veya doğrudan teqlik transferi yoktur ve planlanmamıştır.

**V1.0'da güncellenecek** — `POST /api/wallet/send-gift` (`wallet.py:191`): şu an teqlik → teqlik aktarımı; V1.0'da teqlik → TL kazanca dönüştürülecek:
```
İzleyici → hediye seçer (gift_name + cost) → stream_id ile gönderir
  Gönderenden:   teqlik_balance -= cost                          (atomik)
  Yayıncıya:     tl_pending_balance += cost × pay_rate × ₺0,50  (atomik, T+14 kilitli)
  Platform net:  kalan Teqlif kasasında
```
Dönüşüm kuru: **1 teqlik hediye = ₺0,50 net nakit** (sabit, V1.0'da kilitlenecek)

**İletişim stratejisi:** Yayıncıya oranları anlatırken hayal kırıklığı yaratmamak kritik. "100 TL'lik hediyenin 95 TL'si senin" demek yanlış — yayıncı hesabında ₺47,50 görünce tepki verir. Doğru anlatım: *"Canlı yayında toplanan hediyelerin net havuzunun %95'i PRO yayıncılara ödenir — 1 teqlik hediye = ₺0,50 net nakit değer."* Bu oran cüzdan ekranında şeffaf tablo olarak gösterilir.

**V1.0 hediye kalemleri** (8 katman, `swipe_live_screen.dart:925` güncellenecek):

| Katman | Emoji | Ad | Kod | Maliyet | PRO host (%95) | Std host (%70) | Teqlif net¹ | Animasyon |
|--------|-------|----|-----|---------|----------------|----------------|------------|-----------|
| Mikro | 👏 | Alkış | `clap` | 1 teqlik | ₺0,47 | ₺0,35 | ₺0,40 | Yüzen ikon |
| Mikro | ☕ | Çay | `tea` | 5 teqlik | ₺2,37 | ₺1,75 | ₺2,00 | Yüzen ikon |
| Standart | 🔥 | Alev | `fire` | 10 teqlik | ₺4,75 | ₺3,50 | ₺4,00 | Yüzen ikon |
| Standart | 💎 | Elmas | `diamond` | 50 teqlik | ₺23,75 | ₺17,50 | ₺20,00 | Parlama efekti |
| Premium | 👑 | Taç | `crown` | 100 teqlik | ₺47,50 | ₺35,00 | ₺40,00 | Parlama efekti |
| Premium | 🔨 | Altın Tokmak | `golden_hammer` | 250 teqlik | ₺118,75 | ₺87,50 | ₺100,00 | Tam ekran Lottie |
| VIP | 🚀 | Roket | `rocket` | 500 teqlik | ₺237,50 | ₺175,00 | ₺200,00 | Tam ekran Lottie |
| VIP | 🏆 | Şampiyon Kupası | `trophy` | 1.000 teqlik | ₺475,00 | ₺350,00 | ₺400,00 | Tam ekran Lottie + 10sn banner |

> ¹ Teqlif net = 100-pak senaryo (₺0,875/teqlik IAP net). Mega paketten alındığında ₺0,675/teqlik'e iner; tüm senaryolarda Teqlif kârdadır.

**Animasyon katmanları (UX):**
- **1–10 teqlik (Mikro/Standart):** Sağdan yukarı süzülen küçük yüzen ikon + hafif haptic
- **50–100 teqlik (Premium):** Yayın ekranı ortasında 2 saniyelik parlama + chat'te renkli mesaj
- **250–1.000 teqlik (VIP):** Tam ekran Lottie animasyonu, ağır haptic, chat üstünde 10 saniye sabit altın banner: *"@kullanıcı yayıncıya Şampiyon Kupası gönderdi!"*

**🔨 Altın Tokmak — Mezat Kültürü:** 250 teqlik'lik bu hediye mezat kapanış anına özgüdür. Ürünü kazanan alıcının "satıldı" coşkusuyla mezatçıya atması platforma özgü bir geleneğe dönüşür.

**PRO yayıncı flywheel:** Standart ve PRO arasındaki oran farkı her hediyede birikir. PRO abonelik bedelini aylık Taç hediyelerinden karşılamak için gereken sayı: ₺79,99 ÷ (₺47,50 − ₺35,00) = **6,4 Taç/ay**. Ayda yalnızca 6–7 Taç alan PRO yayıncının abonelik bedeli otomatik amortize olur. Üstüne 3 ücretsiz Boost (₺225), 6 AI Açıklama (₺45), 720p HD yayın ve 2 ücretsiz çekim hakkı eklenir.

**Bakiye yetersiz → PiP akışı** (`swipe_live_screen.dart:945`):
Kullanıcı hediye atmak isteyip bakiyesi yetmediğinde `_handleLoadBalance()` tetiklenir: yayın PiP moduna alınır, cüzdan ekranı açılır. iOS IAP ile teqlik yükleme geldikten sonra kullanıcı Face ID ile paketi alıp canlı yayına döner — mezatı kaçırmadan satın alma.

**Replay/VOD erişimi:** Canlı yayın kaydına (stream_recordings) erişim **PRO zorunludur** (`streams.py:310`). Standart kullanıcı replay ekranını göremez.

**Yayın kalitesi — `host_stream_view_model.dart:24`:**

| Mod | Ana çözünürlük | Simulcast katmanları | Maks bitrate |
|-----|---------------|---------------------|-------------|
| PRO | **720p** | 720p + 540p + 360p | 1.700 kbps |
| Standart | **540p** | 540p + 360p + 240p | 800 kbps |
| PiP | 360p | — (`VideoQuality.LOW`) | — |

### 8.3 İlan Ver Ekranında Ek teqlik Noktaları

**Mevcut:** AI Açıklama (5 teqlik) — create_listing_screen'de aktif.

**Endüstri pratiklerinden:**
- **Sahibinden.com:** İlan oluşturma sırasında "Öne Çıkar" seçeneği (kredi gerektirir)
- **OLX:** "Urgent" / "Top Ad" eklenebilir paketler, ilan oluştururken ödeme
- **Wallapop:** Oluşturma sırasında highlight opsiyonu

**Potansiyel ekleme — İlan Ver'de "Başlangıç Boost" seçeneği:**
```
İlanını Oluştur → Özet Ekranı
  ┌─────────────────────────────────────┐
  │  ✨ İlanını hemen öne çıkar         │
  │  50 teqlik ile ilk 24 saat vitrin  │
  │  [Ekle]          [Geç]             │
  └─────────────────────────────────────┘
```
→ Dönüşüm oranı yüksek (kullanıcı motivasyonun en yüksek olduğu an)
→ V1.1 için öncelikli özellik

### 8.4 PRO Üyelik — Endüstri Analizi & Apple IAP Tipi

**Kritik fark — IAP Ürün Tipi:**

| Ürün Tipi | Kullanım | Apple Komisyonu |
|-----------|---------|----------------|
| Consumable | teqlik paketleri | **%30 her zaman** (SBP: %15) |
| Auto-Renewable Subscription | PRO üyelik | **%30 yıl 1 → %15 yıl 2+** |

> Auto-Renewable Subscription, abonelik 1 yılı geçince Apple otomatik olarak %15'e geçiyor. Consumable için bu indirim yok. PRO üyelik için subscription modeli hem Apple açısından daha avantajlı hem de iş modeli açısından öngörülebilir gelir sağlıyor.

**Endüstri PRO Fiyatları (Marketplace / Classified Apps):**

| Platform | 1 Ay | Yıllık | Özellikler |
|---------|------|--------|-----------|
| MoxMarket (NZ) | $5 NZD | — | 2 boost/ay, düşük komisyon |
| Moonsted (Global) | $10.99 USD | $79.99 USD | Priority listing, boost |
| OLX Pro (global) | ~$15 USD | ~$120 USD | İlan önceliği, rozet |
| Sahibinden Pro | Belirsiz | — | Emlak/Galeri odaklı |

**Türkiye referans abonelik fiyatları (App Store 2025):**

| Servis | Aylık |
|--------|-------|
| Spotify | ~₺39,99 |
| YouTube Premium | ~₺49,99 |
| LinkedIn Career | ~₺249,99 |

**PRO Fiyat Metodolojisi — teqlik değeri üzerinden:**

PRO'nun aylık sunduğu teqlik tasarrufu (30% komisyon senaryosunda iOS fiyatlarıyla):

PRO faydaları `credit_service.py` kodundan doğrulandı (free_standard vs free_pro alanları):

| Özellik | Standart (free) | PRO (free) | PRO tasarrufu |
|---------|----------------|------------|--------------|
| İlan Boost | 0/ay | 3/ay | 3 × 50 teqlik × ₺1,50 = **₺225,00** |
| AI Açıklama | 0/ay | 6/ay | 6 × 5 teqlik × ₺1,50 = **₺45,00** |
| Blast / Kitle Bildir. | 3/ay | 6/ay | +3 × 10 teqlik × ₺1,50 = **₺45,00** |
| İlan Yenileme | 0/ay | 3/ay | 3 × 10 teqlik × ₺1,50 = **₺45,00** |
| **Toplam aylık teqlik değeri** | — | — | **240 teqlik → ₺360,00** |

> **Sonuç:** PRO ₺79,99/ay ile kullanıcı **₺360 değerinde özellik** alıyor — %78 tasarruf. Bu, fiyatın çok altında değer (deliberate under-pricing): platformda tutulma oranını artırmak ve PRO'yu "kaçırılmaz fırsat" konumuna taşımak için doğru strateji. **₺79,99 anchor kesinlikle doğru.** Rozet + analitik + öncelik bonuslarla daha da güçleniyor.

**Önerilen PRO Paket Yapısı (Revize):**

| Plan | App Store Fiyatı | Aylık maliyet | Net (KDV+%30)¹ | Net (KDV+%15 SBP)¹ | İndirim |
|------|-----------------|--------------|----------------|--------------------|----|
| 1 Ay | **₺79,99** | ₺79,99 | **₺46,66** | **₺56,66** | — |
| 3 Ay | **₺214,99** | ₺71,66 | **₺125,41** | **₺152,28** | %10,4 |
| 6 Ay | **₺389,99** | ₺65,00 | **₺227,49** | **₺276,24** | %18,7 |
| 12 Ay | **₺679,99** | ₺56,67 | **₺396,66** | **₺481,66** | %29,2 |

> ¹ Net = Fiyat ÷ 1,20 × (1 − komisyon) — Türkiye KDV %20 dahil

> **Neden ₺79,99 değil ₺99,99:** PRO'nun gerçek aylık teqlik değeri **₺360** (240 teqlik — Boost+AI+Blast+Yenileme). ₺79,99 bu değerin %22'si — kullanıcı için "kaçırılmaz fırsat", Teqlif için ise yüksek retention ve daha fazla organik PRO dönüşümü. Türkiye'de Spotify ₺39,99, YouTube ₺49,99 — ₺79,99 bu anchors'ların biraz üstünde ama PRO bir iş aracı, eğlence değil.

> **Yıllık paket önerisi:** ₺679,99 = aylık ₺56,67 → ₺79,99'a göre %29 indirim. Standart endüstri pratiği yıllık için %25-30 indirim. Bu doğru aralıkta.

**PRO Üye Avantajları (`credit_service.py` free_standard vs free_pro'dan doğrulandı):**

| Özellik | Standart | PRO |
|---------|---------|-----|
| İlan Boost (aylık) | 0 ücretsiz | **3 ücretsiz** |
| AI Açıklama (aylık) | 0 ücretsiz | **6 ücretsiz** |
| Blast / Kitle Bildirimi (aylık) | 3 ücretsiz | **6 ücretsiz** (+3 extra) |
| İlan Yenileme / Reactivation (aylık) | 0 ücretsiz | **3 ücretsiz** |
| Yayın kalitesi | 540p ana (max 800 kbps) | **720p ana (max 1.700 kbps)** |
| Replay/VOD erişimi | — | ✓ PRO zorunlu (streams.py:310) |
| Profil rozeti | — | ✓ Doğrulanmış rozet |
| İlan sıralaması | Normal | Aynı kategoride +öncelik |
| İstatistik / Analytics | Temel | Detaylı (görüntülenme, tıklama) |
| Müşteri desteği | Standart | Öncelikli |

> **App Store Connect'te iki ayrı ürün grubu gerekiyor:** Consumable grubu (teqlik paketleri) + Auto-Renewable Subscription grubu (PRO planlar). Her grup ayrı Apple onayından geçiyor.

### 8.5 Tüm Gelir Akışı Haritası (V1.0 + V1.5 + V2.0)

```
Teqlif Gelir Akışı
├── Consumable IAP (teqlik paketleri)          ← V1.0
│    ├── 100 teqlik — ₺149,99
│    ├── 300 teqlik +50 bonus — ₺429,99  
│    ├── 700 teqlik +150 bonus — ₺999,99
│    └── 1500 teqlik +400 bonus — ₺2.199,99
│
├── Web Mağazası (teqlif.com/cuzdan)           ← V1.5 — Apple bypass
│    ├── Aynı 4 paket, yalnızca %2,5 işlemci komisyonu
│    ├── Apple komisyonu (%15–%30) tamamen sıfır
│    ├── Kullanıcıya "web'den al" söylenmez (Kural 3.1.1)
│    │   → Kullanıcı kendi inisiyatifiyle tarayıcıdan gelir
│    └── iOS IAP margin gap: ₺149,99 → Teqlif net ₺87,49 (IAP) vs ₺146,24 (web)
│
├── Auto-Renewable Subscription (PRO)         ← V2.0
│    ├── 1 Ay — ₺79,99
│    ├── 3 Ay — ₺214,99
│    ├── 6 Ay — ₺389,99
│    └── 12 Ay — ₺679,99
│
├── Enterprise PRO Subscription               ← V2.0
│    └── ₺249,99/ay — %98 pay, ₺0 çekim ücreti, sınırsız replay
│
├── teqlik Harcama Noktaları
│    ├── AI Açıklama (5 teqlik) — create_listing_screen ✅
│    ├── İlan Yenileme (10 teqlik) ✅
│    ├── Blast / Kitle Bildirimi (10 teqlik) ✅
│    ├── İlan Boost (50 teqlik) ✅
│    └── Başlangıç Boost (ilan oluşturulurken, 50 teqlik) ← V1.1
│
├── Canlı Yayın Hediyesi (send-gift)           ← V1.0 — PRO %95 / Std %70
│    └── Teqlif net: her Taç hediyesinde ₺40,00–₺52,50
│
└── Çekim Ücreti                               ← V1.5
     ├── Standart: ₺15 sabit/işlem (direkt marj)
     └── PRO: 2 ücretsiz/ay → 3. çekimden itibaren ₺15
         (aylık reset ARQ cron — PRO'ya geçiş teşviki)
         (V1.0'da talep toplama modu — gerçek transfer yok, ücret de yok)
```

---

## 9. Ekonomik Model & Platform Sürdürülebilirlik Analizi

### 9.1 teqlik Ekosistemi — Paranın Akışı

```
Kullanıcı
   │
   ├─► [A] Para ile teqlik satın alır (IAP)
   │        Apple %30 + KDV %20 → Teqlif %58,3 net alır
   │        Örnek: ₺149,99 ÷ 1,20 × 0,70 = Teqlif ₺87,49 net
   │
   ├─► [B] teqlik harcar (özellikler)
   │        Teqlif %100 net tutar (Apple'a ek kesinti yok)
   │        → AI Açıklama, Boost, Blast, Yenileme, Hediye
   │
   └─► [C] PRO satın alır
            ├─► Para ile (IAP/Subscription): KDV+%30 → Teqlif %58,3 net
            └─► teqlik ile (PRO Pass): Teqlif %100 net (para zaten [A]'da kesildi)
```

**Kritik insight:** teqlik harcamak (B ve C-teqlik yolu) Apple'a ek komisyon ödetmiyor. Apple zaten [A] aşamasında kesiyor. Yani **teqlik ne kadar çok kullanılırsa birim başına marjimiz o kadar artar** — çünkü alım anında Apple bir kez kesiyor, harcamada bir daha kesmiyor.

**Hibrit Döngü Ekonomisi (V1.0):** teqlik satın alma kapalı döngü olmaya devam ediyor — kullanıcı satın aldığı teqliği doğrudan nakde çeviremiyor. Ancak yayıncılar hediyelerden kazandıkları TL'yi IBAN'a çekebiliyor (V1.0).

- **İzleyici teqlik alımı (kapalı):** IAP ile giren teqlik doğrudan dışarı çıkmaz. Kullanıcı Boost, Blast, AI veya hediye için harcar. Apple Kural 3.1.1 tam uyumlu.
- **Yayıncı TL kazancı (açık):** Hediyelerden elde edilen TL "emek karşılığı kazanç" — Apple/Google bu çıkışa karışmaz (TikTok, Twitch modeli). BDDK/MASAK: yayıncı "satın aldığı jetonları" değil, "hak ettiği geliri" çekiyor; platform komisyon kesip gönderdiği için bu bir ödeme kuruluşu işlemi değil, istihdam benzeri gelir ödemesi.
- **Finansal kaldıraç:** Satılan teqlikin özellik harcaması (Boost/Blast/AI) kısmı dormant kalırsa sıfır maliyetli gelir. Hediye kısmı TL'ye dönüşse de Teqlif kasasında net marj kalıyor (her Crown hediyesinde ₺40–₺52,50).

### 9.2 PRO Hybrid Ödeme Modeli (Para + teqlik)

**Apple Uyum Tespiti:** IAP ile satın alınan teqlikin uygulama içinde PRO erişimi açmak için harcanması Apple kılavuzlarınca izin verilen bir model. Guideline 3.1.2(a) abonelik benzeri içeriklerin consumable credits ile açılmasına izin veriyor — oyunlarda yaygın pratik.

**İki ayrı ürün:**

| Ürün | Tip | Açıklama |
|------|-----|----------|
| PRO Subscription | Auto-Renewable Subscription | Apple otomatik yeniler, yönetir |
| PRO Pass | Consumable | 30 günlük PRO erişimi — para veya teqlik |

Kullanıcıya sunulacak seçenekler:

```
┌─────────────────────────────────────────────────────────┐
│  PRO Üyelik — 1 Aylık                                   │
│                                                         │
│  ┌──────────────────┐   ┌──────────────────────────┐    │
│  │  ₺79,99 / ay    │   │  56 teqlik               │    │
│  │  Apple ile öde  │   │  Bakiyenden harca         │    │
│  │  (otomatik yenir)│   │  (manuel, tek seferlik)  │    │
│  └──────────────────┘   └──────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Teqlif için marj karşılaştırması:**

| Ödeme yolu | Kullanıcı öder | Teqlif net alır | Fark |
|-----------|---------------|----------------|------|
| Apple IAP (Subscription %30, KDV-düzeltmeli) | ₺79,99 | **₺46,66** | baseline |
| teqlik ile (56 teqlik) | ₺64,96–₺84,00* | **₺49,00** | +₺2,34 |

> *56 teqlik: mega paketten (₺1,16/teqlik): 56×₺1,16=₺64,96; başlangıç paketten (₺1,50/teqlik): 56×₺1,50=₺84,00. Teqlif net = 56 × ₺0,875 (100-paket KDV-düzeltmeli) ≈ ₺49,00.

**Sonuç: PRO'yu teqlik ile ödemek her iki taraf için avantajlıdır:**
- Kullanıcı: büyük paket aldıysa (700+ veya 1900 teqlik) PRO maliyeti ₺65–₺70 → ₺79,99 cash'dan net ucuz
- Teqlif: Apple'a ek kesinti yok → subscription'a göre %5 daha fazla net (₺49 vs ₺46,66). Küçük fark ama PRO hacminde kümülatif anlamlı.

### 9.3 teqlik Fiyat Dengesi — Harcama vs Yükleme

**Mevcut teqlik harcama oranları:**

| Özellik | Maliyet | Aylık kullanım (tahmin) |
|---------|---------|------------------------|
| AI Açıklama | 5 teqlik | 2-3× / ilan oluşturma |
| İlan Yenileme | 10 teqlik | 1× / ay (pasif ilan) |
| Blast | 10 teqlik | 1-2× / ay |
| İlan Boost | 50 teqlik | 1× / ay |
| PRO Pass (teqlik) | 56 teqlik | Aylık sabit |

**Tipik kullanıcı profilleri:**

| Profil | Aylık harcama | Aylık teqlik maliyeti | Önerilen paket |
|--------|--------------|----------------------|----------------|
| Hafif (1 ilan, 1 blast) | 15 teqlik | ₺21,45 | 100 teqlik paketi |
| Orta (2 ilan, 1 boost, 2 blast) | 130 teqlik | ₺185,90 | 300 teqlik paketi |
| Ağır (3 ilan, 2 boost, 3 blast, AI) | 245 teqlik | ₺350,35 | 700 teqlik paketi |
| PRO (teqlik + özellikler) | 56+130 = 186 teqlik | — | PRO + 300 paket |

**Paket boyut optimizasyonu:**
100 teqlik → hafif kullanıcı için 5-7 ay yeter → tekrar satın alım düşük.
300 teqlik → orta kullanıcı için 2-3 ay → iyi tekrar alım döngüsü.
→ **300 teqlik "en popüler" paketi olarak öne çıkarılması ekonomik olarak doğru.**

### 9.4 Platform Ölçek Ekonomisi — Hayatta Kalma Analizi

**Altyapı tahmini maliyet (mevcut 6 node):**

| Kalem | Aylık TL tahmini |
|-------|-----------------|
| 6× VPS (node1-6 + monitor) | ₺25.000 – ₺35.000 |
| MinIO storage | ₺3.000 – ₺5.000 |
| CDN / Cloudflare | ₺1.000 – ₺2.000 |
| LiveKit / streaming | ₺2.000 – ₺4.000 |
| Diğer (Stalwart, monitoring) | ₺1.000 – ₺2.000 |
| **Toplam altyapı** | **~₺32.000 – ₺48.000** |

**Breakeven hesabı (%30 Apple komisyonu):**

Altyapı ortalaması: ₺40.000/ay

| Senaryo | Aylık ödeme yapan kullanıcı | ARPPU | Brüt gelir | Net (KDV+%30)¹ | Kâr/Zarar |
|---------|---------------------------|-------|-----------|----------------|-----------|
| Minimal | 500 | ₺100 | ₺50.000 | ₺29.165 | **-₺10.835** |
| **Breakeven** | **686** | ₺100 | ₺68.600 | **₺40.016** | **≈₺0** |
| Sağlıklı | 1.500 | ₺120 | ₺180.000 | ₺105.000 | **+₺65.000** |
| Büyüme | 5.000 | ₺150 | ₺750.000 | ₺437.500 | **+₺397.500** |

> ¹ Net = Brüt ÷ 1,20 × 0,70 (Türkiye KDV %20 + Apple %30 sonrası)
>
> **ARPPU:** ₺100 brüt konservatif tahmin. Orta profil kullanıcı 130 teqlik/ay için brüt ₺185 → KDV+%30 sonrası Teqlif net ~₺108. Breakeven eşiği önceki analizde 650 kullanıcı olarak hesaplandı; KDV düzeltmesiyle **686'ya yükseld**i (5,5% fark).

**Dönüşüm hunisi varsayımları:**

```
Kayıtlı kullanıcı: 100.000
       │ MAU %20 (sector avg)
       ▼
Aylık aktif: 20.000
       │ Ödeme dönüşüm %5-8
       ▼
Ödeme yapan: 1.000 – 1.600          ← Breakeven aralığı
       │ PRO dönüşüm %15
       ▼
PRO abonesi: 150 – 240
```

**Kritik dönüşüm noktası:** CreditGate sistemi (mevcut) bu dönüşüm oranını artırıyor. Kullanıcı özelliği kullanmak isteyip teqliği yoksa ödeme ekranı açılıyor — bu "in-moment" dönüşüm en yüksek verimli yoldur (kullanıcı halihazırda motive).

### 9.5 teqlik Flywheel (Çark) Etkisi

```
                 ┌─────────────────────┐
                 │  Kullanıcı teqlik   │
            ┌───►   satın alır         │
            │    └─────────────────────┘
            │               │
            │    ┌──────────▼──────────┐
            │    │  Özellik kullanır   │◄──────────────┐
            │    │  (boost/blast/AI)   │               │
            │    └─────────────────────┘               │
            │               │                         │
            │    ┌──────────▼──────────┐    ┌─────────┴──────────┐
            │    │  İlanı daha fazla   │    │  Hediye alır        │
            │    │  görüntülenir       │    │  (başka kullanıcıdan│
            │    └─────────────────────┘    └────────────────────┘
            │               │
            │    ┌──────────▼──────────┐
            │    │  Daha hızlı satar   │
            │    │  veya daha fazla    │
            │    │  teklif alır        │
            │    └─────────────────────┘
            │               │
            │    ┌──────────▼──────────┐
            │    │  Platforma güvenir  │
            └────   Tekrar teqlik alır │
                 └─────────────────────┘
```

**Çarkı döndüren unsurlar:**
1. **CreditGate:** Özellik kapısı → organik dönüşüm
2. **Başlangıç Boost (V1.1):** İlan oluştururken tek tık → yüksek motivasyon anında teqlik harcama
3. **Hediye sistemi:** Teqlif'e para girmeden teqlik dolaşımı → sosyal proof, yeni kullanıcı çekişi
4. **PRO teşviki:** 56 teqlik PRO Pass → büyük paket (300+ teqlik) almayı teşvik eder — mega pakette efektif PRO maliyeti ₺64,96

### 9.6 PRO Ekonomisi — teqlik Tüketiminin Artısı

PRO abonesi olmak paradoksal görünüyor: "ücretsiz özellik verince teqlik harcamazlar."

Ancak veriler tersi gösteriyor (SaaS'ta yaygın pattern):
- PRO kullanıcılar platforma **daha bağlı** → daha fazla ilan açar
- Daha fazla ilan = daha fazla boost/blast ihtiyacı (ücretsiz limit aşılınca ücretli)
- PRO limitini aşan kullanıcı → zaten teqlik satın almaya alışkın
- **PRO + teqlik harcama birbirini besler, yemez**

**PRO Cohort Davranış Tahmini:**

| Metrik | Standart kullanıcı | PRO kullanıcı |
|--------|-------------------|---------------|
| Aylık aktif gün | 6 | 18 |
| Aylık ilan sayısı | 1.2 | 3.5 |
| Aylık teqlik harcama | 25 teqlik | 95 teqlik |
| Aylık gelir (Teqlif net, KDV+%30) | ₺14,58 | ₺46,66 abonelik + ₺55,41 teqlik = **₺102,07** |

PRO kullanıcı standart kullanıcının **~7×** gelirine katkı yapıyor.

> **Enterprise PRO (V2.0):** Düzenli büyük ciro yapan satıcılar ve profesyonel yayıncılar için üst segment plan: **₺249,99/ay**, %98 yayıncı pay oranı, sınırsız replay erişimi, ₺0 çekim ücreti (unlimited), öncelikli müşteri desteği. V1.0'da yalnızca PRO ve Standart olmak üzere iki tier; Enterprise V2.0 kapsamında.

### 9.7 teqlik Bonus Ekonomisi — Paket Teşvik Sistemi

Bonus teqlik sistemi hem kullanıcı teşviki hem de ekonomik güvence sağlıyor:

| Paket | Ödenen | Alınan | Bonus | Birim fiyat* | Teqlif net (KDV+%30) |
|-------|--------|--------|-------|-------------|---------------------|
| 100 | ₺149,99 | 100 | — | ₺1,50 | **₺87,49** |
| 300+50 | ₺429,99 | 350 | 50 teqlik | ₺1,23 | **₺250,83** |
| 700+150 | ₺999,99 | 850 | 150 teqlik | ₺1,18 | **₺583,33** |
| 1500+400 | ₺2.199,99 | 1900 | 400 teqlik | ₺1,16 | **₺1.283,33** |

> *Birim fiyat = kullanıcının ödediği birim maliyet (App Store fiyatı ÷ toplam teqlik)

**Bonus teqlik Teqlif için maliyeti:**
Kullanıcıya 50 bonus teqlik veriyoruz (300 pakette) → bu 50 teqlik gelecekte kullanıldığında bize ek maliyet yok; zaten paket satışından aldık. Bonus sadece "önceden ödenmiş" teqlik — değeri ₺0 ek maliyet, ₺50 kullanıcı algı değeri.

### 9.8 Gelir Akışı Özeti — Tüm Senaryolar

**Yıllık 1.000 aktif ödeme yapan kullanıcı senaryosu:**

| Gelir kaynağı | Aylık brüt | Apple sonrası net |
|--------------|-----------|-----------------|
| teqlik paket satışları (%60 kullanıcı, ort. ₺200) | ₺120.000 | **₺70.000** |
| PRO Subscription (%15, ₺79,99) | ₺11.999 | **₺7.000** |
| PRO Pass (teqlik ile, %5, 56 teqlik) | Zaten teqlik gelirinde | **₺2.450*** |
| **Toplam** | | **~₺79.450** |

> *56 teqlik × 50 kullanıcı × ₺0,875 net/teqlik = ₺2.450 (teqlik gelirinin marj-üstü kısmı; zaten ₺70.000'e dahil — ayrı gösterildi)
>
> **KDV düzeltmesi etkisi:** Önceki projeksiyon ₺96.399 net gösteriyordu (%30 kesinti varsayımıyla). KDV %20 dahil edilince ₺79.450'ye geriledi — ₺16.949 fark (%17,5). Bu fark tüm finansal planlama dökümanlarına yansıtılmalı.

**Altyapı ₺40.000 → Net kâr: ~₺39.450/ay** (1.000 ödeme yapan kullanıcıda)

---

## 10. Karar Özeti

| Konu | Karar | Sürüm |
|------|-------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 | V1.0 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 teqlik** | V1.0 |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 teqlik** | V1.0 |
| Efektif teqlik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) | V1.0 |
| teqlik IAP ürün tipi | **Consumable** | V1.0 |
| PRO üyelik IAP ürün tipi | **Auto-Renewable Subscription** | V2.0 |
| Backend doğrulama | App Store Server API v2 JWS | V1.0 |
| Refund politikası | REFUND webhook zorunlu — bakiyeden düş + orantılı gift iptali + çekim sonrası negatif bakiye (borç mahsubu) + NO CHECK CONSTRAINT | V1.0 |
| Android | V1.0 kapsamı dışı | — |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi | V1.0 |
| Hediye sistemi (teqlik → TL dönüşüm) | **V1.0** — send-gift güncellenmeli | V1.0 |
| Hediye kalemleri | **8 katman** — clap(1)·tea(5)·fire(10)·diamond(50)·crown(100)·golden_hammer(250)·rocket(500)·trophy(1000) | V1.0 |
| Animasyon katmanları | Mikro/Std: yüzen ikon · Premium: parlama · VIP: tam ekran Lottie + banner | V1.0 |
| Yayıncı TL kazanç takibi | Hediyelerden tl_pending_balance birikimi; T+14 cron ile tl_earnings_balance'a aktarım | V1.0 |
| IBAN çekim modu | **Talep toplama** — bakiye talep anında atomik düşülür; red → iade; onay → zaten düşüldü; gerçek banka transferi yok | V1.0 |
| Seçenek C (Teqlik'e Dönüştür) | tl_earnings_balance → teqlik +%10 bonus; atomik SQL | V1.0 |
| T+14 holding süresi | **V1.0 zorunlu** — Apple refund sigortası; idempotent cron + `FOR UPDATE SKIP LOCKED` | V1.0 |
| Minimum çekim eşiği | **₺500** | V1.0 |
| TL dönüşüm kuru | **1 teqlik = ₺0,50 net nakit** (sabit V1.0) | V1.0 |
| earnings_tl veri tipi | `gift_events.earnings_tl` → **NUMERIC(10,4)** (₺0,475 kuruş kaybı önlemi) | V1.0 |
| Yuvarlama kuralı | earnings ledger NUMERIC(10,4); kullanıcı bakiyesine aktarımda `TRUNC(x, 2)` — PostgreSQL `ROUND()` değil (0.4750 → 0.47, platform aleyhine kuruş kaybı yok) | V1.0 |
| Negatif bakiye | `tl_earnings_balance` negatife düşebilir; CHECK constraint yok; borç mahsubu ile kapanır | V1.0 |
| Backend mimari | İş mantığı `use_cases/wallet/commands/` + `queries/`; `wallet.py` router sadece delege | V1.0 |
| Cron yerleşimi | `schedule.yaml`'da tanımlanır (worker.py'ye değil); watchdog_m ile izlenir | V1.0 |
| i18n ARB | 5 dil ARB: 5 yeni hediye adı + walletConvertToTeqlik + walletWithdrawRequestNote + walletPendingEarningsDesc | V1.0 |
| IAP velocity limit | ₺5.000/gün/cihaz Redis rate limit; aşılırsa fraud_flag + admin alarmı | V1.0 |
| send-gift rate limit | Redis Token Bucket: 2/sn per user (burst 5); aşılırsa 429 | V1.0 |
| İletişim stratejisi (hediye oranları) | "Net havuzun %95'i PRO yayıncılara ödenir" — "100 TL'lik hediyenin 95 TL'si" değil | V1.0 |
| Gerçek banka transfer API | Şirket kuruluşu sonrası (LTD zorunlu) | **V1.5** |
| MERNIS / KYC | İlk gerçek çekim zorunlu; TCKN AES-256 şifreli `user_kyc` tablosunda | **V1.5** |
| Rolling Reserve | Yeni yayıncı 90 gün max ₺2.500/çekim | **V1.5** |
| IBAN checksum | TR + 24 karakter + mod-97 doğrulama | **V1.5** |
| Çekim ücreti | ₺15 sabit — PRO ayda 2 ücretsiz | **V1.5** |
| Concurrency (withdraw) | Redis SETNX lock:withdraw:{uid} EX 10 + atomik SQL WHERE bakiye | **V1.5** |
| Borç dondurma | 30 günlük ödenmemiş borçta account_frozen; tüm ilanlar pasif | **V1.5** |
| Admin Maker-Checker | ₺2.500+ çekimde 2 admin onayı; ₺10.000+ 2FA zorunlu | **V1.5** |
| Web mağazası (teqlif.com/cuzdan) | %2,5 işlemci komisyonu, Apple bypass | **V1.5** |
| Başlangıç Boost (İlan Ver'de) | İlan oluşturulurken 50 teqlik Boost seçeneği | V1.1 |
| PRO anchor fiyatı | **₺79,99/ay** (teqlik eşdeğeri: büyük pakette ₺64,96 — cash'dan ucuz) | V2.0 |
| PRO Pass fiyatı (teqlik) | **56 teqlik** — mega pakette ₺64,96 efektif vs ₺79,99 cash | V2.0 |
| PRO planlar | 1ay ₺79,99 / 3ay ₺214,99 / 6ay ₺389,99 / 12ay ₺679,99 | V2.0 |
| Enterprise PRO | ₺249,99/ay, %98 pay, ₺0 çekim, sınırsız replay | V2.0 |
