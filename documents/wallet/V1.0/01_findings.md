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

## 3. Apple App Store — Manuel Adımlar & Uyum Gereksinimleri

### 3.0 App Store Connect'te Yapılacak Manuel Adımlar (Koddan Önce)

Aşağıdaki adımlar App Store Connect panelinde elle yapılır; bunlar tamamlanmadan kod tarafı çalışmaz.

**Adım 1 — Small Business Program Başvurusu**
- App Store Connect → **Agreements, Tax, and Banking** → Small Business Program
- Yıllık net gelir < $1M ise %15 komisyon için başvur (otomatik değil, manuel başvuru zorunlu)
- Onay 1–3 iş günü. Başvurulmadan tüm alımlar %30 komisyonla açılır.
- URL: `appstoreconnect.apple.com/agreements` → "Request Small Business Program"

**Adım 2 — IAP Ürünlerini Oluştur (Consumable × 4)**
- App Store Connect → uygulamanı seç → **In-App Purchases** → (+) → **Consumable**

| Product ID | Display Name (TR) | Fiyat Tier (%30) | Fiyat Tier (%15) |
|------------|------------------|-----------------|-----------------|
| `teqlik_pack_100` | 100 teqlik | ₺149,99 (Tier ~35) | ₺119,99 (Tier ~28) |
| `teqlik_pack_250` | 250 teqlik + 25 Bonus | ₺349,99 | ₺279,99 |
| `teqlik_pack_500` | 500 teqlik + 75 Bonus | ₺649,99 | ₺519,99 |
| `teqlik_pack_1000` | 1000 teqlik + 200 Bonus | ₺1.199,99 | ₺949,99 |

Her ürün için doldurulacaklar:
- **Reference Name**: `teqlik_100_tr` (dahili ad, Store'da görünmez)
- **Product ID**: yukarıdaki tablo (büyük/küçük harf duyarlı — Flutter kodu ile birebir eşleşmeli)
- **Pricing**: tier seç (₺ fiyatlar Apple'ın tier tablosundan — sabit kur Apple'ın kendi oranıyla)
- **Localizations**: TR dili için başlık + kısa açıklama ekle
- **Review Information**: screenshot + "Bu uygulama içi satın alım teqlik dijital token'ı sağlar, yalnızca uygulama içinde kullanılır" notu
- Ürünü **Ready to Submit** durumuna al (uygulama App Review'dan geçince otomatik aktif)

**Adım 3 — App Store Server Notifications V2 Yapılandırması**
- App Store Connect → uygulamanı seç → **App Information** → **App Store Server Notifications**
- **Production URL**: `https://api.teqlif.com/api/wallet/apple-notifications`
- **Sandbox URL**: `https://api-staging.teqlif.com/v1/wallet/apple-notifications`
- **Version**: **Version 2** seç (V1 hatalı/eksik bildirim gönderir)
- "Send Test Notification" ile doğrula — backend `200 OK` dönmeli

**Adım 4 — Sandbox Test Hesapları**
- App Store Connect → **Users and Access** → **Sandbox** → Testers → (+)
- En az 2 sandbox hesap oluştur: `sandbox1@teqlif.com`, `sandbox2@teqlif.com`
- Bu hesaplar gerçek para harcamaz; `StoreKit.environment = "Sandbox"` ile işaretlenir
- Simulator'da IAP çalışmaz — fiziksel cihaz + sandbox hesap zorunlu

**Adım 5 — Tax & Banking Bilgileri (Ödemeler için Zorunlu)**
- App Store Connect → **Agreements, Tax, and Banking** → Paid Apps sözleşmesini imzala
- Banka hesabı ve vergi bilgileri girilmeden Apple ödeme yapmaz
- **Apple ödeme takvimi**: Net-33 ile Net-45 gün (ayın kapanış dönemine göre değişir). Örnek: Ekim satışları en erken Kasım sonunda hesapta. V1.0'da gerçek banka transferi yapılmadığı için bu gecikme kritiktir — Teqlif, Apple'dan parayı tahsil etmeden kullanıcıya ödeme yapamaz. Seçenek C (Teqlik'e Dönüştür) bu gecikmeyi bypass eder; nakit ön kayıt ise Apple ödemesi alınana kadar listede bekler.

**Adım 6 — PRO Abonelik Grubu Oluştur (Auto-Renewable Subscription)**
- App Store Connect → uygulamanı seç → **Subscriptions** sekmesi → (+) → **Create Subscription Group**
- **Grup Adı**: `Teqlif PRO`
- Grup içinde 4 abonelik planı oluştur: (+) → **Auto-Renewable Subscription**

| Product ID | Display Name (TR) | Süre | Fiyat (%30) | Fiyat (%15/SBP) | İndirim |
|------------|------------------|------|------------|----------------|---------|
| `teqlif_pro_1m` | Teqlif PRO — 1 Ay | 1 Month | ₺149,99/ay | ₺119,99/ay | — |
| `teqlif_pro_3m` | Teqlif PRO — 3 Ay | 3 Months | ₺404,99/3ay | ₺323,99/3ay | %10 |
| `teqlif_pro_6m` | Teqlif PRO — 6 Ay | 6 Months | ₺764,99/6ay | ₺611,99/6ay | %15 |
| `teqlif_pro_12m` | Teqlif PRO — 1 Yıl | 1 Year | ₺1.349,99/yıl | ₺1.079,99/yıl | %25 |

Her abonelik planı için doldurulacaklar:
- **Reference Name**: `teqlif_pro_1m_tr` (dahili ad)
- **Product ID**: yukarıdaki tablo (Flutter kodu ile birebir eşleşmeli)
- **Subscription Duration**: ilgili süre seçeneği
- **Pricing**: tier seç; 3/6/12 aylık planlarda aylık eşdeğer daha düşük olduğu açıkça görülmeli
- **Localizations**: TR + EN dili için başlık + fayda listesi (HD yayın, %95 hediye payı, gelişmiş analitik, Replay izleme)
- **Review Information**: "PRO abonelik dijital özellikler sağlar; otomatik yenileme Apple Kimliği ile faturalandırılır"
- **App Review'dan önce**: EULA (Kullanım Şartları) ve Gizlilik Politikası linklerini ekle

Apple Zorunlulukları (PRO satın alma ekranında zorunlu metin):
```
"Abonelik otomatik olarak yenilenir. Apple Kimliği ayarlarınızdan
istediğiniz zaman iptal edebilirsiniz."
```

---

### 3.1 Zorunlu Kurallar (İhlali = Red)

**Kural 3.1.1 — Zorunlu IAP:**
- teqlik dijital özellik kilidi açtığı için Apple IAP **zorunlu**
- Ekranda asla şu ibareler yer alamaz:
  - "Web sitemizden daha ucuza alın"
  - "Kredi kartı / havale ile öde"
  - Harici ödeme sitesine herhangi bir link

**IAP Ürün Tipleri:**
- teqlik paketleri (4 adet): App Store Connect'te `Consumable` (Tüketilebilir)
- PRO abonelik (4 plan): App Store Connect'te `Auto-Renewable Subscription`
- `Non-Consumable` tipi kullanılmaz

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

### 4.0 teqlik Yaşam Döngüsü Haritası

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  [1. DOĞUŞ — Minting]                                                            │
│  App Store IAP → JWS doğrulama (leeway=60, bundleId, env=Prod)                  │
│               → Replay koruması (apple_transaction_id UNIQUE)                    │
│               → users.teqlik_balance += amount                                   │
│               → teqlik_transactions (raw_receipt arşivi)                         │
└────────────────────────────┬─────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
┌─────────────────────────┐   ┌────────────────────────────────────────┐
│  [2. İÇ TÜKETİM]        │   │  [3. HEDİYELEŞME]                     │
│  Boost·Blast·AI·PRO Sub │   │  Canlı mezatta 8 katman hediye         │
│  Nakit çıkışı: ₺0        │   │  Gönderen: teqlik_balance -= cost      │
│  Teqlif marjı: %100     │   │  Alıcı: tl_pending_balance +=          │
│  (Yeniden [2]'ye döner) │   │    TRUNC(cost×pay_rate×0.50,2)         │
└─────────────────────────┘   │  payout_status='pending' (başından)    │
                              │  Kilit: LEAST(sender,host) sırası      │
                              │  Rate:  Redis Token Bucket 2/sn        │
                              └────────────────┬───────────────────────┘
                                               │
                                               ▼
                              ┌────────────────────────────────────┐
                              │  [4. ESCROW — T+14]                │
                              │  gift_events.payout_status='pending'│
                              │  14 gün boyunca dokunulamaz        │
                              └────────────────┬───────────────────┘
                                               ▼ 02:15 UTC — CTE Cron
                              ┌────────────────────────────────────┐
                              │  [5. OLGUNLAŞMA]                   │
                              │  WITH locked_events AS (           │
                              │    ... FOR UPDATE SKIP LOCKED      │
                              │  ) SELECT ... GROUP BY             │
                              │  tl_pending → tl_earnings_balance  │
                              │  _agent_ok(ctx, "release_pending") │
                              └───────────────┬────────────────────┘
                                              │
                                       ┌──────┴──────┐
                                       ▼             ▼
                              ┌─────────────────┐  ┌──────────────────────────────────────┐
                              │ [6A. Seçenek C] │  │ [6B. ÇIKIŞ — IBAN Çekim]             │
                              │ tl_earnings →   │  │ tl_earnings_balance atomik düşülür   │
                              │ teqlik +%10     │  │ withdrawal_requests status='pending' │
                              │ FLOOR formülü   │  │ cancel_withdrawal (anında iade)      │
                              │ Para ÇIKMAZ     │  │ Gerçek transfer: LTD + banka API     │
                              └─────────────────┘  └──────────────────────────────────────┘

cashout_enabled=false (V1.0 başlangıç): Adım 4-5 arka planda çalışır; Kart 2'de TL
  bakiyesi, IBAN butonu ve Seçenek C gösterilmez. Yayıncı TL biriktirir, göremez.
cashout_enabled=true (V1.1 — şirket kurulduktan sonra): tüm adımlar + Kart 2 UI aktif.
  Aktivasyon: redis-cli SET teqlif:config:cashout_enabled 1  (App Store build gerekmez)
```

### 4.1 Flutter Tarafı

**Gereken paket:** `in_app_purchase` (pub.dev resmi plugin — iOS StoreKit 2 + Android Billing desteği)

**Önerilen modül yapısı** (profile_screen.dart'tan bağımsız):
```
mobile/lib/
  ├── models/
  │    ├── teqlik_package.dart         // id, teqlikAmount, bonusAmount, isPopular, isBestValue
  │    └── pro_subscription_plan.dart  // id, duration, price, discountPercent
  ├── services/
  │    └── iap_service.dart            // Unified StoreKit listener: purchaseStream hem consumable hem subscription dinler
  │                                    //   productID.startsWith('teqlik_pack_') → wallet credit
  │                                    //   productID.startsWith('teqlif_pro_')  → POST /api/wallet/apple-verify
  ├── screens/wallet/
  │    ├── viewmodels/
  │    │    └── wallet_view_model.dart // Riverpod Notifier: bakiye, paketler, satın alma durumları, pro_status
  │    ├── wallet_screen.dart          // Ana Scaffold — Kart 1'de PRO rozeti
  │    └── widgets/
  │         ├── teqlik_package_card.dart
  │         ├── hero_balance_card.dart
  │         ├── teqlik_utility_guide.dart
  │         └── iban_pre_registration_sheet.dart  // Glassmorphism bottom sheet: yasal uyum panosu + IBAN formatter + banka logosu + simülatör + "Sıraya Gir" CTA
  ├── screens/pro/
  │    ├── pro_subscription_sheet.dart // Glassmorphism PRO satış bottom sheet:
  │    │                               //   1/3/6/12 ay seçim kartları, her plan fiyat + tasarruf badge
  │    │                               //   "Ücretsiz Dene" intro offer (App Store Connect'te tanımlanmışsa)
  │    │                               //   PRO faydaları listesi, "Satın Alımları Geri Yükle" butonu (zorunlu)
  │    │                               //   Yasal abonelik metni (otomatik yenileme uyarısı — Apple zorunluluğu)
  │    └── pro_badge_widget.dart       // Kart 1 + profil fotoğrafı üzerinde PRO rozeti
```

> **IAPService birleşik listener:** `purchaseStream` tek noktada dinlenir; `productID` prefix'e göre consumable veya subscription dalına yönlendirilir. Restore Purchases (`restorePurchases()`) çağrısı `purchaseStream`'den geçer; AppStore daha önce satın alınmış abonelikleri tekrar yayınlar — ayrı bir restore endpoint'i yoktur, StoreKit'in yerleşik mekanizması kullanılır.

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
VALID_CONSUMABLE_IDS   = {"teqlik_pack_100", "teqlik_pack_250", "teqlik_pack_500", "teqlik_pack_1000"}
VALID_SUBSCRIPTION_IDS = {"teqlif_pro_1m", "teqlif_pro_3m", "teqlif_pro_6m", "teqlif_pro_12m"}
VALID_PRODUCT_IDS      = VALID_CONSUMABLE_IDS | VALID_SUBSCRIPTION_IDS

# 1. x5c sertifika zinciri doğrulama (leaf → G3 CA → Apple Root CA)
# 2. jwt.decode ile JWS doğrulama — leeway=60 zorunlu:
#    jwt.decode(signed_transaction, cert_chain[0].public_key(),
#               algorithms=["ES256"], leeway=60)
#    leeway=60: NTP clock skew toleransı. Node 1 saati Apple'dan 2-3 sn geri
#    kalırsa "Token used before issued" hatası üretilir, geçerli IAP reddedilir.
# 3. Payload hardcoded doğrulama:
assert payload["environment"] == "Production"          # Sandbox makbuzu prod'a geçemez
assert payload["bundleId"]    == "com.teqlif.app"      # Başka uygulamanın makbuzu reddedilir
assert payload["productId"]   in VALID_PRODUCT_IDS     # Bilinen consumable + subscription ID'ler
# Bu kontroller atlansa jailbreak araçlarıyla (LocalIAPStore) bedavadan teqlik yüklenebilir.

# 4. Ürün tipine göre dispatch:
product_id = payload["productId"]
if product_id in VALID_CONSUMABLE_IDS:
    # Consumable → teqlik_balance += amount, TeqlikTransaction kaydı (product_type='consumable')
    ...
elif product_id in VALID_SUBSCRIPTION_IDS:
    # Subscription → user_type='pro', pro_expires_at=expires_date, plan_type=...,
    #   premium_since=NOW(), apple_original_transaction_id=original_transaction_id
    #   TeqlikTransaction kaydı (product_type='subscription')
    #   Daha önce aktif PRO varsa (yenileme) → pro_expires_at güncelle, premium_since dokunma
    ...
```

**Günlük IAP Hız Limiti (Velocity Limit):**
```
Aynı Apple ID / cihaz kimliğinden 24 saatte maksimum ₺5.000 satın alma.
Eşik aşılırsa: 429 → fraud_flag = True → admin incelemesi.
Teqlik_transactions tablosunda device_id (StoreKit appAccountToken) saklanmalı.
```

**Replay Saldırısı Koruması + Ham Fiş Arşivi:**
```sql
-- Gerekli migration (V1.0 — W1'e dahil):
ALTER TABLE teqlik_transactions
  ADD COLUMN apple_transaction_id VARCHAR(64) UNIQUE,
  ADD COLUMN raw_receipt          TEXT;
-- apple_transaction_id: aynı transaction_id → HTTP 409, bakiye yüklenmez.
-- raw_receipt: Apple'ın kriptografik imzalı signedTransactionInfo (JWS string) tam
--   olarak saklanır. PostgreSQL satırı tek başına Apple dispute veya chargeback
--   davasında delil sayılmaz; orijinal JWS ile Apple kök sertifikasından bağımsız
--   doğrulama yapılabilir. 3-5 yıl sonra bile geçerlidir.
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
  Body: { signedPayload: "<JWS string>" }

  ──── ADIM 0: Hızlı 200 OK — Ağır İşlemi ARQ Kuyruğuna At ────────────────────
  x5c sertifika zinciri doğrulaması CPU yoğun, DB işlemi I/O yoğundur.
  Bu ikisi FastAPI main thread'inde senkron çalışırsa Apple refund dalgasında
  Uvicorn worker'ları tükenir, normal mobil kullanıcılar 504 alır.

  Endpoint yalnızca şunu yapar:
    1. signedPayload'u Redis kuyruğuna yaz (< 5ms)
    2. Apple'a 200 OK döndür (Apple 4xx alırsa 3 gün retry storm başlatır)
  ARQ worker (handle_apple_refund_task) kuyruktaki payload'u alıp işler.
  ──────────────────────────────────────────────────────────────────────────────

  ──── ADIM 1: signedPayload JWS Doğrulaması (ARQ worker'da, içeriğe bakmadan önce) ────
  signedPayload kendisi de Apple tarafından imzalı bir JWS'dir.
  İçindeki event type'a güvenmeden önce Apple root sertifikasıyla doğrulanmalı:

    header = jwt.get_unverified_header(signed_payload)
    # header["x5c"][0] → leaf cert, [1] → G3 CA, [2] → Apple Root CA
    cert_chain = [load_der_x509_certificate(b64decode(c)) for c in header["x5c"]]
    # 1. Zincir doğrulama: leaf → G3 CA → Apple Root CA imzası kontrol et
    # 2. Apple Root CA hash'i hardcoded doğrula (MITM koruması):
    #    SHA-256: 4f5f 4b63 75d8 91ab 4333 1ea9 2b25 5a00 ... (Apple'ın yayımladığı sabit hash)
    # 3. cert_chain[0].not_valid_after > datetime.utcnow() (sertifika süresi)
    # 4. jwt.decode(signed_payload, cert_chain[0].public_key(), algorithms=["ES256"],
    #              leeway=60)  ← zorunlu: NTP saat kayması (clock skew) toleransı.
    #    leeway olmadan Node 1 saati Apple'dan 2-3 sn geri kalırsa geçerli fişler
    #    "Token used before issued" hatasıyla reddedilir, satın alım başarısız olur.
  Bu doğrulama atlanırsa saldırgan sahte POST → gift_events iptal ettirebilir.
  ──────────────────────────────────────────────────────────────────────────────

  eventType: "REFUND"
  → apple_transaction_id ile TeqlikTransaction'ı bul (iade_miktarı, orijinal_miktar)
  → teqlik_balance -= iade_miktarı  (atomik; negatife düşebilir)
     CHECK (>= 0) constraint'i OLMAMALI — webhook 500 alırsa Apple 3 gün retry storm başlatır.
  → bakiye < 0 ise: users.pending_refund = true

  → Orantılı hediye kazancı iptali (anti-fraud):
       iade_oranı = iade_miktarı / orijinal_miktar
       iptal_tl   = users.tl_pending_balance × iade_oranı
       UPDATE gift_events SET payout_status = 'cancelled_refund'
         WHERE sender_id = kullanıcı AND payout_status = 'pending'
         ORDER BY sent_at ASC LIMIT (iptal_tl'yi karşılayana kadar)
       tl_pending_balance -= iptal_tl  (atomik)
       IAP transaction → bireysel hediyeler arasında tam iz mümkün değil;
       orantılı iptal yaklaşık ama yeterli koruma sağlar.

  → RefundLog kaydı oluştur
  → 200 OK döndür (Apple retry yapar 4xx'te)
```

#### 4.2.2 Yayıncı Hakediş Sistemi

> **Strateji:** Tüm altyapı baştan kurulur — migration, use case'ler, T+14 cron, tüm endpointler. Yayıncı TL hakedişi ilk günden itibaren `gift_events.earnings_tl`'ye kaydedilir; `payout_status='pending'` ile T+14 cronu başından işler. Şirket kuruluşuna kadar `cashout_enabled=false` dönülür; şirket kurulduktan sonra Redis key güncellenerek tüm birikmiş hakediş anında görünür hale gelir — App Store build gerekmez.

**Feature Flag (Backend-Driven OTA):**
```
# Redis (prod, Node 1):
SET teqlif:config:cashout_enabled 0   # şirket kurulduktan sonra: SET teqlif:config:cashout_enabled 1

# GET /api/wallet/summary response:
{ "teqlik_balance": 140, "tl_earnings_balance": 1450.00, "tl_pending_balance": 230.00,
  "cashout_enabled": false }

# Flutter: summary.cashoutEnabled == false → Kart 2 TL bakiyesi + IBAN sheet + Seçenek C gizlenir
#           summary.cashoutEnabled == true  → Kart 2 tam aktif, cashout açık
# Backend: get_wallet_summary_query.py Redis'ten cashout_enabled okur, response'a ekler.
#          Cashout endpointleri (withdraw, convert) cashout_enabled=false iken 403 döner.
```

**Migration — Tek Seferlik (tüm tablo ve kolonlar upfront):**
```sql
-- ── Wallet Migration (tek seferlik — tüm kolonlar baştan oluşturulur) ─────────
-- users: TL bakiye kolonları (baştan oluşturulur; CASHOUT_ENABLED=false iken UI gizler)
ALTER TABLE users
  ADD COLUMN tl_earnings_balance  NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  ADD COLUMN tl_pending_balance   NUMERIC(10,2) NOT NULL DEFAULT 0.00;
  -- ⚠️ CHECK (>= 0) KONULMAMALI (ikisi de):
  -- Apple iadesi geldiğinde teqlik_balance ve tl_earnings_balance negatife düşebilir.
  -- DB constraint hatası Apple webhook'unun 500 alıp sonsuz retry storm başlatmasına yol açar.

-- gift_events: payout_status='pending' başından itibaren; T+14 cron tüm kayıtları işler
ALTER TABLE gift_events
  ADD COLUMN earnings_tl   NUMERIC(10,4) NOT NULL DEFAULT 0.0000,
  ADD COLUMN payout_status VARCHAR(20)   NOT NULL DEFAULT 'pending',
                           -- pending | released | cancelled_refund
  ADD COLUMN released_at   TIMESTAMPTZ;

CREATE INDEX idx_gift_events_payout
  ON gift_events (payout_status, sent_at)
  WHERE payout_status = 'pending';

-- PRO abonelik kolonları (users) — baştan oluşturulur
ALTER TABLE users
  ADD COLUMN pro_expires_at               TIMESTAMPTZ NULL,
  ADD COLUMN pro_grace_until              TIMESTAMPTZ NULL,
  ADD COLUMN apple_original_transaction_id VARCHAR(64) NULL;
  -- pro_expires_at: Apple'ın expiresDate değeri; NULL iken kullanıcı standart
  -- pro_grace_until: Apple billing retry grace period bitişi (maks 6 gün); NULL ise grace yok
  -- apple_original_transaction_id: abonelik zincirini izlemek için; yenilemede değişmez
  -- NOT: CHECK (pro_expires_at > NOW()) KONULMAMALI — cron ve webhook çakışırsa deadlock riski;
  --      süreli kontrol uygulama katmanında yapılır (pro_expires_at IS NULL koşulu).

CREATE INDEX idx_users_pro_status
  ON users (user_type, pro_expires_at)
  WHERE user_type = 'pro';

-- teqlik_transactions: ürün tipi ayrımı
ALTER TABLE teqlik_transactions
  ADD COLUMN product_type VARCHAR(20) NOT NULL DEFAULT 'consumable';
  -- 'consumable' (teqlik paketi) | 'subscription' (PRO abonelik)

-- withdrawal_requests: baştan oluşturulur (CASHOUT_ENABLED=false iken kullanılmaz)
CREATE TABLE withdrawal_requests (
  id                SERIAL PRIMARY KEY,
  user_id           INTEGER NOT NULL REFERENCES users(id),
  amount_tl         NUMERIC(10,2) NOT NULL,
  iban              VARCHAR(34) NOT NULL,
  account_holder    VARCHAR(120) NOT NULL,
  status            VARCHAR(20) NOT NULL DEFAULT 'pending',
                    -- pending | approved | completed | rejected | cancelled
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at      TIMESTAMPTZ,
  cancelled_at      TIMESTAMPTZ,
  admin_note        TEXT
);

-- ── V1.1 Migration (şirket kurulduktan sonra — hukuki/KYC kolonları) ──────────
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
-- ALTER TABLE withdrawal_requests
--   ADD COLUMN fee_tl              NUMERIC(10,2),
--   ADD COLUMN gross_amount_tl     NUMERIC(10,2),
--   ADD COLUMN withholding_tax_tl  NUMERIC(10,2),
--   ADD COLUMN net_amount_tl       NUMERIC(10,2);
```

**Rate Limiting — send-gift (Redis Token Bucket):**
```
Canlı yayında saniyede 50 hediye → PostgreSQL + Redis + WebSocket kilitlenir.
Kullanıcı başına sınır (Redis SETNX + TTL):
  Normal:  saniyede maks. 2 hediye (burst: 5)
  Aşılırsa: HTTP 429 — "Çok hızlı! Biraz bekleyin."
  Kötü niyet tespiti (burst limit 10×): sender'ı 10 dakika bloke et.

Redis key: rate:gift:{sender_id}  |  TTL: 1 saniye  |  increment > limit → red

Redis Çöküşünde Fail Davranışı (redis.exceptions.ConnectionError):
  send-gift: Fail-Safe — try/except ile hata yakalanır, işlem atomik DB kontrolüne
    devredilir (teqlik_balance >= cost WHERE koşulu), yayın kesilmez.
  IAP hız limiti (rate:iap:{device}): Fail-Closed — Redis bağlantısı yoksa satın
    alma işlemi reddedilir (429); şüpheli anda para yükletme kabul edilmez.
```

**Host Row Contention & Deadlock Önleme (Yüksek Yük):**
```
Mezatın son 10 saniyesinde 500 izleyici aynı anda yayıncıya hediye yağdırırsa,
her send_gift işlemi User(host_id) satırına RowExclusiveLock koyar — 500 transaction
tek satır için kuyruğa girer, p99 latency 50ms → 3.000ms'ye fırlar.

Deadlock önlemi — deterministik kilit sıralaması:
  Her zaman LEAST(sender_id, host_id) önce, GREATEST sonra kilitlenir.
  İki yönlü işlem (A→B ve B→A aynı anda) deadlock üretmez.

  # send_gift_command.py içinde:
  first_id  = min(sender_id, host_id)
  second_id = max(sender_id, host_id)
  await conn.execute("SELECT id FROM users WHERE id = $1 FOR UPDATE", first_id)
  await conn.execute("SELECT id FROM users WHERE id = $1 FOR UPDATE", second_id)
  # Ardından UPDATE'ler

PgBouncer pool (6432) transaction pooling modunda çalışır; mezat burst'leri için
max_client_conn ve default_pool_size değerleri V2.1 cluster.yaml'daki Node 1
donanımına (bare-metal, dedicated CPU) göre önceden ayarlanmış olmalıdır.
```

**Use Case Yapısı — `app/use_cases/wallet/commands/`:**

Clean Architecture kuralı gereği iş mantığı `wallet.py` router'da değil; `use_cases/wallet/commands/` altında ayrı command sınıflarında tutulur.

```
app/use_cases/wallet/
  commands/
    send_gift_command.py                       ← tl_pending_balance += TRUNC(cost×pay_rate×0.50,2)
    verify_apple_receipt_command.py            ← JWS doğrulama + x5c zinciri; consumable/subscription dispatch
    handle_apple_notification_command.py       ← Apple Notifications V2: DID_RENEW/EXPIRED/GRACE/REFUND
    handle_apple_refund_command.py             ← orantılı gift iptali + negatif bakiye
    request_withdrawal_command.py              ← tl_earnings_balance atomik düşüm
    cancel_withdrawal_request_command.py       ← status='pending' → 'cancelled' + iade
    convert_to_teqlik_command.py               ← Seçenek C +%10 bonus, atomik SQL
  queries/
    get_wallet_summary_query.py
```

**send_gift akışı (tek implementasyon — CASHOUT_ENABLED bağımsız):**
```
İzleyici → hediye seçer (gift_name + cost) → stream_id ile gönderir

  Gönderenden:   teqlik_balance -= cost                                      (atomik)
  Yayıncıya:     tl_pending_balance += TRUNC(cost × pay_rate × 0.50, 2)     (atomik; PRO: %95, Std: %70)
  gift_events:   earnings_tl = TRUNC(cost × pay_rate × 0.50, 4)
                 payout_status = 'pending'   ← T+14 cron başından itibaren işler
  Platform net:  kalan Teqlif kasasında

  Decimal hassasiyeti (zorunlu): Python float yerine Decimal kullan.
    earnings_tl = TRUNC(Decimal(str(cost)) * pay_rate * Decimal("0.50"), 4)
    tl_pending  = TRUNC(Decimal(str(cost)) * pay_rate * Decimal("0.50"), 2)

  Post-commit domain events (zorunlu kural):
    WebSocket broadcast (hediye animasyonu) + push notification
    → `async with uow:` bloğu DIŞINDA, `await uow.commit()` SONRASI tetiklenir.
    Sebep: Redis pub/sub gecikmesi (ws.send/notify süresi belirsiz) transaction
    kilidini uzatır; bakiye DB'ye yazılmadan event fırlatılırsa tutarsızlık doğar.
    Doğru sıra:
      async with uow:
          uow.repo.save(gift_event); uow.repo.update_balances(...)
      await uow.commit()          # kilit serbest
      await ws_manager.broadcast(room_id, gift_payload)   # lock dışı
      await push_service.notify(broadcaster_id, payload)  # lock dışı
```

Dönüşüm kuru: **1 teqlik hediye = ₺0,50 net nakit** (sabit)

Geçerli hediye tipleri: `clap`(1) · `tea`(5) · `fire`(10) · `diamond`(50) · `crown`(100) · `golden_hammer`(250) · `rocket`(500) · `trophy`(1000)

| Katman | Hediye | Maliyet | PRO (TL pending) | Std (TL pending) | Teqlif net |
|--------|--------|---------|-----------------|-----------------|-----------|
| Mikro | 👏 Alkış | 1 tqlk | ₺0,47 | ₺0,35 | ₺0,40 |
| Mikro | ☕ Çay | 5 tqlk | ₺2,37 | ₺1,75 | ₺2,00 |
| Standart | 🔥 Alev | 10 tqlk | ₺4,75 | ₺3,50 | ₺4,00 |
| Standart | 💎 Elmas | 50 tqlk | ₺23,75 | ₺17,50 | ₺20,00 |
| Premium | 👑 Taç | 100 tqlk | ₺47,50 | ₺35,00 | ₺40,00 |
| Premium | 🔨 Altın Tokmak | 250 tqlk | ₺118,75 | ₺87,50 | ₺100,00 |
| VIP | 🚀 Roket | 500 tqlk | ₺237,50 | ₺175,00 | ₺200,00 |
| VIP | 🏆 Şampiyon Kupası | 1.000 tqlk | ₺475,00 | ₺350,00 | ₺400,00 |

> TL değerleri 100-pak fiyatı (₺0,875/teqlik) baz alınarak hesaplanır; mega paketten alındığında (₺0,675/teqlik) Teqlif net ₺0,20–₺0,40/teqlik'e iner — tüm senaryolarda Teqlif kârdadır.

**Endpointler (tamamı baştan implemente edilir; CASHOUT_ENABLED yalnızca UI'ı etkiler):**
```
GET  /api/wallet/summary  →  get_wallet_summary_query.py
  → { teqlik_balance, tl_earnings_balance, tl_pending_balance, cashout_enabled: bool }
  cashout_enabled: Redis'ten okunur (GET teqlif:config:cashout_enabled); 0/yoksa false, 1 ise true.
  Flutter: cashout_enabled==false → tl_ değerleri alınır ama Kart 2'de gösterilmez;
           cashout_enabled==true  → Kart 2 tam aktif, TL bakiyesi + IBAN sheet + Seçenek C gösterilir.

POST /api/wallet/withdraw  →  request_withdrawal_command.py
  Body: { amount_tl, iban, account_holder_name }
  Kurallar:
    - amount_tl >= 500  (minimum çekim)
    - Aktif pending talep yoksa kabul edilir (409 "İncelemede bekleyen talebiniz var")
    - Bakiye atomik düşüm (double-spend önlemi):
        UPDATE users SET tl_earnings_balance = tl_earnings_balance - :amount_tl
          WHERE id = :uid AND tl_earnings_balance >= :amount_tl RETURNING tl_earnings_balance;
        -- 0 satır → 400 yetersiz bakiye
    - withdrawal_requests INSERT status='pending' — aynı transaction
  → 200 OK | 400 bakiye yetersiz | 409 aktif talep var

  Admin Red Akışı:
    UPDATE users SET tl_earnings_balance = tl_earnings_balance + :amount_tl WHERE id = :uid;
    UPDATE withdrawal_requests SET status='rejected', admin_note=:note, processed_at=NOW() WHERE id = :wid;

DELETE /api/wallet/withdraw/{request_id}  →  cancel_withdrawal_request_command.py
  - status == 'pending' kontrolü + yetki kontrolü (403 başkasının talebi)
  - UPDATE users SET tl_earnings_balance += amount_tl (atomik iade)
  - UPDATE withdrawal_requests SET status='cancelled', cancelled_at=NOW()
  → 200 OK | 403 | 409 iptal edilemez statü

POST /api/wallet/convert-to-teqlik  →  convert_to_teqlik_command.py  (Seçenek C, +%10 bonus)
  - tl_earnings_balance >= amount_tl
  - base = FLOOR(amount_tl / 0.875); total = FLOOR(base × 1.10)
  - tl_earnings_balance -= amount_tl (atomik); teqlik_balance += total (atomik)
  - Modal yasal uyarısı (kullanıcı onaylamadan işlem tamamlanmaz):
      "⚠️ Dönüştürülen teqlik'ler kalıcı olarak ilan güçlendirme ve mezat harcamaları
       için kullanılır; tekrar nakde çevrilemez veya TL bakiyesine geri döndürülemez."
      [ Anladım, {total} Teqlik'e Dönüştür ]
  → Para tek yönlü olarak ekosisteme kilitlenir — cashout_enabled=true (V1.1) ile aktive edilir.
```

**T+14 Holding — ARQ cron görevi (başından itibaren aktif, idempotent):**

Her iki cron görevi `worker.py`'ye değil; **`deploy/scale/V2.1/schedule.yaml`** dosyasına `batch` altında eklenir. `schedule_loader.py` bu dosyayı okur, `teqlif-agent/watchdog.py` görevi izler — cron doğrudan koda yazılırsa agent tarafından izlenemez.

```python
# Her gün 02:15 UTC — pending → released (tam idempotent)
# schedule.yaml: batch.release_pending_earnings, watchdog_m: 30
# 02:15 UTC: Her Pazar 02:00'de başlayan pg_basebackup (Node 2 fiziksel yedek)
# ile disk I/O çakışmasını önlemek için 15 dk ötelendi.
async def release_pending_earnings_task():
    """14 günü dolan gift_events.payout_status='pending' → 'released', balance aktar."""
    # BEGIN TRANSACTION
    #
    # 1. Aktarılacak hediyeleri kilitle ve topla — CTE zorunlu
    #    PostgreSQL'de GROUP BY + FOR UPDATE aynı sorguda geçersizdir (aggregate'e satır kilidi uygulanamaz).
    #    Önce satırlar kilitlenir, ardından kilitlenen satırlar üzerinden toplama yapılır:
    #
    #    WITH locked_events AS (
    #        SELECT id, receiver_id, earnings_tl
    #        FROM gift_events
    #        WHERE payout_status = 'pending'
    #          AND sent_at <= NOW() - INTERVAL '14 days'
    #        FOR UPDATE SKIP LOCKED
    #    )
    #    SELECT receiver_id, SUM(earnings_tl) AS total_raw
    #    FROM locked_events
    #    GROUP BY receiver_id
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
    #
    # worker.py _SCHEDULE_FUNCTIONS sözlüğüne bu fonksiyon elle eklenmeli.
    # Fonksiyonun en sonunda watchdog sinyali zorunludur:
    await _agent_ok(ctx, "release_pending_earnings_task")
    # teqlif-agent Redis teqlif:agent:job_ok hash'ini bu çağrıyla günceller.
    # Satır eksik kalırsa watchdog her gün 02:45'te sahte alarm (False Positive) üretir.

# Her ayın 1'i 00:05 UTC — PRO çekim kotasını sıfırla
# schedule.yaml: batch.reset_monthly_withdrawal_quota, watchdog_m: 60
async def reset_monthly_withdrawal_quota_task():
    # UPDATE users SET monthly_free_withdrawals_used = 0 WHERE is_pro = true

# Her gün 00:00 UTC — Finansal Mutabakat (Reconciliation)
# schedule.yaml: batch.daily_financial_reconciliation, watchdog_m: 10
async def daily_financial_reconciliation_task():
    """
    Sistemdeki tüm bakiyelerin matematiksel tutarlılığını doğrular.
    1 kuruş (₺0.01) fark bile Critical Alert üretir — race condition,
    Decimal hatası veya yetkisiz müdahale göstergesidir.

    Denklem:
      Toplam teqlik_balance (tüm kullanıcılar)
      + Toplam harcanan teqlik (tüm TeqlikTransaction type='spend')
      == Toplam yüklenen teqlik (tüm TeqlikTransaction type='iap')

      Toplam tl_earnings_balance + tl_pending_balance
      == SUM(gift_events.earnings_tl WHERE payout_status IN ('pending','released'))
       - SUM(withdrawal_requests.amount_tl WHERE status='completed')

    Fark != 0.00 TL → Telegram Critical Alert + admin_flags kaydı.
    0 satır sonuç → sessiz başarı (watchdog_m izler; cron çalışmazsa alarm).
    """
```

**Worker Havuzu İzolasyonu (Bulkhead) — ARQ Kuyruk Seçimi:**
```
worker.py'de iki ayrı worker havuzu tanımlıdır:
  WorkerSettings         → queue_name="default"   (batch işler, ML, temizlikler; timeout 300sn)
  WorkerSettingsCritical → queue_name="critical"  (anlık bildirimler; timeout 30sn, max_jobs 50)

Cüzdan bildirimleri kuyruk seçimi:
  handle_apple_refund_command  → queue_name="default"
    (ağır JWS + DB işlemi; gecikme tolere edilir)

  Withdrawal durum değişimi push bildirimi (approved/rejected/completed) → queue_name="critical"
    (kullanıcı anlık bilgilendirilmeli; gece 05:30 ML eğitimiyle aynı default kuyruğa atılırsa
     dakikalarca bloklanabilir)

Dispatch örneği:
  await arq_pool.enqueue_job(
      "send_push_notification_task",
      user_id=uid, title="...", body="...",
      _queue_name="critical",
  )
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

### 4.2.3 PRO Abonelik Sistemi

**PRO Faydaları (mevcut backend kodu zaten user_type='pro' destekliyor):**

| Fayda | Standart | PRO |
|-------|----------|-----|
| Yayın kalitesi | 540p | 720p HD |
| Hediye gelir payı | %70 | %95 |
| Replay (VOD) izleme | Yok | Var |
| Ücretsiz kredit kotaları | Standart | Arttırılmış |
| Gelişmiş analitik | Temel | Tam |
| Çekim ücreti (V1.1) | ₺15/işlem | 2× ücretsiz/ay |

**Apple Notifications V2 Webhook (`handle_apple_notification_command.py`):**
```
POST /api/wallet/apple-notifications
  Body: { signedPayload: "<JWS string>" }

  ──── 200 OK hemen döner, ağır iş ARQ kuyruğuna atılır (refund ile aynı pattern) ────

  handle_apple_notification_task (ARQ worker — queue_name="default"):

  x5c sertifika zinciri doğrulaması (signedPayload JWS imzası) → payload parse

  notificationType: DID_RENEW
    → user.pro_expires_at = new_expires_date  (uzatılır)
    → user.pro_grace_until = NULL             (grace bitti, ödeme geldi)
    → user.user_type zaten 'pro', dokunma
    → push: "PRO üyeliğiniz yenilendi ✓"

  notificationType: DID_RENEW + subtype: BILLING_RETRY
    → user.pro_grace_until = grace_expires_date  (Apple 6 güne kadar retry eder)
    → user.user_type = 'pro'  (grace süresince PRO kalır — kesilmez)
    → push: "Ödeme alınamadı, tekrar deneniyor — üyeliğiniz devam ediyor"

  notificationType: EXPIRED veya subtype: GRACE_PERIOD_EXPIRED
    → user.user_type = 'standard'
    → user.pro_expires_at = NULL
    → user.pro_grace_until = NULL
    → push: "PRO üyeliğiniz sona erdi"

  notificationType: REVOKE (fraud/chargeback)
    → user.user_type = 'standard' (anında)
    → user.pro_expires_at = NULL
    → refund akışı: teqlik_balance azalt (paketle gelen bonuslar varsa orantılı)
```

**Gece Cron — check_expired_pro_users_task (03:00 UTC):**
```python
# Her gün 03:00 UTC — webhook kaçırma sigortası (network glitch / worker restart)
# schedule.yaml: batch.check_expired_pro_users, watchdog_m: 60
async def check_expired_pro_users_task():
    """
    pro_expires_at geçmiş ve grace_period'u da bitmiş PRO kullanıcıları standard'a çeker.
    Apple webhook (EXPIRED) zaten yapar — bu cron webhook kaçırma sigortasıdır.
    """
    # UPDATE users
    # SET user_type = 'standard', pro_expires_at = NULL, pro_grace_until = NULL
    # WHERE user_type = 'pro'
    #   AND pro_expires_at < NOW()
    #   AND (pro_grace_until IS NULL OR pro_grace_until < NOW())
    await _agent_ok(ctx, "check_expired_pro_users_task")
```

**Grace Period Mantığı (Billing Retry):**
- Apple ödeme başarısız olursa kullanıcıya hemen `standard` yapılmaz
- `pro_grace_until` = Apple'ın DID_RENEW+BILLING_RETRY bildirimindeki `gracePeriodExpiresDate` (maks 6 gün)
- Grace süresince kullanıcı PRO kalır, `pro_grace_until` dolarsa (cron veya GRACE_PERIOD_EXPIRED webhook) `standard` yapılır
- Ödeme gelirse DID_RENEW → `pro_grace_until = NULL`, kullanıcı kesintisiz PRO

**plan_type değerleri (users.plan_type mevcut kolon):**
```
teqlif_pro_1m  → plan_type = 'monthly'
teqlif_pro_3m  → plan_type = 'quarterly'
teqlif_pro_6m  → plan_type = 'biannual'
teqlif_pro_12m → plan_type = 'annual'
```

### 4.4 Güvenlik & Anti-Fraud Mimarisi

**V1.0'da aktif olan güvenlik katmanları:**

| Katman | Mekanizma | Amaç |
|--------|-----------|-------|
| IAP güvenliği | JWS environment + bundleId + productId hardcoded + `leeway=60` (clock skew) | Sandbox / sahte makbuz + NTP kaymasından kaynaklanan geçerli fatura reddi engeli |
| IAP hız limiti | Redis velocity ₺5.000/gün/cihaz; Redis çökerse Fail-Closed (işlem reddedilir) | Çalıntı kart flood |
| send-gift hız limiti | Redis Token Bucket 2/sn per user; Redis çökerse Fail-Safe (DB atomik kontrole düşer, yayın kesilmez) | DB/WS flood |
| Replay koruması | apple_transaction_id UNIQUE | Çift yükleme |
| Çift talep önlemi | Aktif pending varken yeni talep reddi | Aynı bakiyeye çift talep |
| Refund → gift iptali | orantılı payout_status='cancelled_refund'; tl_pending_balance azalt; negatif bakiye | IAP iadesi hediye kazancını da iptal eder |
| Negatif bakiye | CHECK constraint yok; hem tl_earnings_balance hem teqlik_balance eksilir | Apple webhook 500 vermez, retry storm başlamaz |
| T+14 kilitli bakiye | pending bakiye 14 gün çekilemez | Apple iade penceresi sigortası |
| Webhook async | 200 OK hemen döner, signedPayload ARQ kuyruğuna atılır; ağır JWS + DB işlemi worker'da | Apple refund dalgasında Uvicorn thread starvation önlenir |
| Host row contention | send_gift deterministik kilit sırası: LEAST(sender_id, host_id) önce kilitlenir | Mezat burst'inde deadlock önlenir |
| Anti-arbitraj kilit | teqlik → TL dönüşümü yoktur (`/convert-teqlik-to-tl` endpoint'i asla olmayacak); teqlik kazancını hediye yoluyla nakde çevirmeye kalkmak %40 kayıp yaratır: ₺500 → 628 tqlk → PRO yayıncıya hediye → ₺298,30 (628 × 0.95 × ₺0.50); Teqlif kâr eder | teqlik tek yönlü kapalı döngü — kasayı korur |

**V1.1'de devreye girecek güvenlik katmanları (şirket kuruluşu sonrası):**

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

**Tüm wallet bileşenleri (backend upfront):**

| Bileşen | Durum |
|---------|-------|
| `tl_earnings_balance` + `tl_pending_balance` (users) | ❌ Migration yok |
| `withdrawal_requests` tablosu | ❌ Migration yok |
| `gift_events` (`earnings_tl` NUMERIC(10,4), `payout_status='pending'`, `released_at`) | ❌ Migration yok |
| `use_cases/wallet/commands/` + `queries/` use case yapısı | ❌ Yazılmamış |
| `verify_apple_receipt_command.py` (JWS + env/bundleId + velocity limit) | ❌ Yazılmamış |
| `send_gift_command.py` (payout_status='pending', tl_pending +=, Decimal + atomik) | ❌ Yazılmamış |
| `request_withdrawal_command.py` (bakiye kontrolü + pending insert) | ❌ Yazılmamış |
| `cancel_withdrawal_request_command.py` (pending → cancelled + bakiye iade) | ❌ Yazılmamış |
| `convert_to_teqlik_command.py` (Seçenek C, +%10 bonus) | ❌ Yazılmamış |
| `get_wallet_summary_query.py` (tl_ balansları dahil) | ❌ Yazılmamış |
| `handle_apple_refund_command.py` (orantılı gift iptali + negatif bakiye) | ❌ Yazılmamış |
| `teqlik_transactions` (apple_transaction_id UNIQUE + raw_receipt TEXT + product_type) | ❌ Migration yok |
| `daily_financial_reconciliation` cron (00:00 UTC, watchdog_m:10) | ❌ Eklenmemiş |
| `schedule.yaml` T+14 cron (`release_pending_earnings`, watchdog_m:30) | ❌ Eklenmemiş |
| **PRO Abonelik** | |
| `users` (pro_expires_at, pro_grace_until, apple_original_transaction_id) | ❌ Migration yok |
| `verify_apple_receipt_command.py` consumable + subscription dispatch | ❌ Yazılmamış |
| `handle_apple_notification_command.py` (DID_RENEW/EXPIRED/GRACE/REVOKE) | ❌ Yazılmamış |
| `schedule.yaml` check_expired_pro_users (03:00 UTC, watchdog_m:60) | ❌ Eklenmemiş |
| PRO subscription Flutter UI (ProSubscriptionSheet, Restore Purchases) | ❌ Yazılmamış |

**Neden Gerçek Banka Transferi CASHOUT_ENABLED=false Döneminde Yapılmıyor — İki Bağımsız Neden:**

1. **MASAK/Hukuki**: Şirket kuruluşu tamamlanmadan kişisel hesaptan toplu kullanıcı transferi "şüpheli ticari faaliyet" sayılır (banka hesabı bloke riski).
2. **Apple Net-45 Nakit Akışı**: Apple App Store ödemeleri Net-33 ile Net-45 gün arasında geliştiricinin banka hesabına yatar. Ekim satışları en erken Kasım sonunda gelir. Yayıncı 14. günde çekim talep etseydi, Teqlif henüz Apple'dan tahsil etmemiş parayı kendi cebinden ödemek zorunda kalacaktı — negatif nakit akışı tuzağı. Seçenek C (Teqlik'e Dönüştür) ekosistemi kapatır ve bu gecikmeyi tamamen bypass eder; nakit ön kayıt ise Apple ödemesi geldiğinde işleme alınır.

**CASHOUT_ENABLED=true öncesi tamamlanması gereken hukuki/regülatif bileşenler (V1.1 §6.3):**

| Bileşen | Ön Koşul |
|---------|----------|
| MERNIS/KYC kolonları + `user_kyc` AES-256 şifreli tablo | Şirket kaydı + NVİ SOAP API sözleşmesi |
| Rolling Reserve kolonları (`rolling_reserve_expires_at`, `rolling_reserve_limit_tl`) | Gerçek transfer akışı |
| `is_in_debt`, `account_frozen`, `account_frozen_reason` kolonları | Gerçek transfer akışı |
| `monthly_free_withdrawals_used` + aylık reset cron | PRO abonelik + gerçek ücret akışı |
| `request_withdrawal_command.py` KYC/ücret entegrasyonu (MERNIS + Redis lock + ücret kolonları) | Şirket + banka API |
| Admin Maker-Checker paneli (₺2.500+ çift onay, ₺10.000+ 2FA) | Şirket + banka API |
| Banka transfer API entegrasyonu | LTD/şahıs şirketi + kurumsal banka anlaşması |

---

## 5. UX & Ekran Mimarisi

### 5.1 Ekran Yapısı (Onaylanan — İki Bölmeli Cüzdan)

```
┌──────────────────────────────────────────────┐
│  AppBar: Cüzdanım         [İşlem Geçmişi]    │
├──────────────────────────────────────────────┤
│  ╔══════════════════════════════════════════╗ │
│  ║  KART 1: teqlik Bakiyem                 ║ │
│  ║  • Bakiye: 140 teqlik  [PRO ✦ rozeti]  ║ │
│  ║  • Bakiye yüklenince sayı yukarı sayar  ║ │
│  ║  [  teqlik Satın Al  ]                  ║ │
│  ║  [  PRO'ya Yükselt  ]  (PRO değilse)   ║ │
│  ║  *(Bu bakiye ASLA nakde çevrilemez)*    ║ │
│  ╚══════════════════════════════════════════╝ │
├──────────────────────────────────────────────┤
│  ╔══════════════════════════════════════════╗ │
│  ║  KART 2: Yayın Kazançlarım  [herkese]   ║ │
│  ║  (Koyu zümrüt/altın — glassmorphism)    ║ │
│  ║                                          ║ │
│  ║  [Kazanç varsa — yayıncı]               ║ │
│  ║  • Çekilebilir Bakiye: ₺1.450,00 🔒     ║ │
│  ║  • Bekleyen (T+14)  : ₺230,00           ║ │
│  ║                                          ║ │
│  ║  [BİRİNCİL — neon/göz alıcı buton]     ║ │
│  ║  ⚡ ANINDA KULLAN                        ║ │
│  ║    +%10 Bonusla Teqlik'e Dönüştür       ║ │
│  ║  (₺1.450 ➔ ₺1.595 değerinde ilan gücü) ║ │
│  ║                                          ║ │
│  ║  [İKİNCİL — şeffaf hatlı buton]        ║ │
│  ║  🏦 Nakit Transferi İçin IBAN Tanımla   ║ │
│  ║     (Ön Kayıt)                          ║ │
│  ║                                          ║ │
│  ║  [IBAN kaydı varsa — sıra durumu]       ║ │
│  ║  📋 Sıra No: #42 — Ön Kayıt Alındı     ║ │
│  ║  Kurumsal entegrasyon açılınca bildirim ║ │
│  ║  [İptal Et]  [Teqlik'e Dönüştür +%10]  ║ │
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

**Kart 2 Görsel Tasarımı:** Kart 1 (enerjik mor/neon — teqlik satın alma enerjisi) ile bilinçli kontrast kurulur. Kart 2 koyu zümrüt yeşili + altın aksanlı glassmorphism/sheen doku kullanır — "kazanılmış para" hissini Kart 1'den ayırt eder ve fintech premium estetiği verir.

**Terminoloji Standardı:** Uygulama genelinde "Para Çekme" / "Çekim" ifadeleri kullanılmaz. Seçenek C birincil CTA'dır; nakit yol ikincil ve "ön kayıt" olarak konumlandırılır.

| Kullanılmayacak | Kullanılacak |
|-----------------|--------------|
| Para Çekme | Nakit Transfer Ön Kaydı |
| Çekim Talebi | IBAN Ön Kaydı |
| İncelemede / Bekliyor | Sıranızda |
| Reddedildi | IBAN Güncellemesi Gerekiyor |
| Beta güvenlik denetimi | Kurumsal finans entegrasyonu |

**Neden bu framing:** V1.0'da şirket kuruluşu henüz tamamlanmamıştır. Kişisel hesaptan kullanıcı IBAN'ına toplu para transferi MASAK kapsamında "şüpheli ticari faaliyet / vergisiz kazanç aktarımı" riski taşır ve banka hesabı bloke edilebilir. Kullanıcıya "3 gün içinde yatacak" gibi bir söz verilmez; süreç başından "kurumsal banka entegrasyonu tamamlandığında" olarak çerçevelenir. Şirketleşip banka API'si alındığında sistemde doğrulanmış IBAN listesi ve sıra numaraları hazır bekler.

**IBAN Ön Kayıt Akışı (Glassmorphism Bottom Sheet):**

"Nakit Transferi İçin IBAN Tanımla" butonuna basıldığında tam ekran modal yerine arka plan hafif karartılmış/bulanıklaştırılmış Bottom Sheet açılır:

```
┌─ 🛡️ Yasal Uyum & Kurumsal Finans Protokolü ───────┐
│     Resmi Hakediş Transferi — Ön Kayıt             │
├────────────────────────────────────────────────────┤
│  "Teqlif, yayıncılarının finansal güvenliğini en   │
│  üst düzeyde tutmak amacıyla resmi bankacılık,     │
│  vergi mevzuatı ve MASAK kurallarına tam uyumlu    │
│  kurumsal ödeme altyapısını hazırlamaktadır.       │
│  Kazandığınız tüm bakiye sistemimizde kuruşu       │
│  kuruşuna güvence altındadır ve asla silinmez.     │
│  IBAN bilgilerinizi şimdiden tanımlayarak          │
│  Öncelikli Transfer Sırası'na katılabilirsiniz."   │
├────────────────────────────────────────────────────┤
│  Çekilebilir Bakiye                                │
│  ┌──────────────────────────────────────────────┐  │
│  │  ₺1.450,00  (zümrüt/altın degrade)          │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Tutar                                             │
│  [ ₺500 (Min) ]  [ ₺1.000 ]  [ Bakiyenin Tamamı ] │
│  veya manuel giriş: [_________]                    │
│                                                    │
│  IBAN                                              │
│  [📋 Panodan Yapıştır]                             │
│  [ TR | 00 0000 0000 0000 0000 00   [🏦 Logo] ]    │
│                                                    │
│  Hesap Sahibi                                      │
│  [ Ahmet Yılmaz (profil adından öneri) ]           │
│  ℹ️ IBAN üzerindeki isim profil adıyla             │
│     birebir uyuşmalıdır                            │
├────────────────────────────────────────────────────┤
│  ✨ Banka açılışını beklemek istemiyor musunuz?    │
│  Kazancınızı +%10 Bonusla teqlik'e çevirip         │
│  ilanlarınızı hemen vitrine taşıyabilirsiniz.      │
│  [ Şimdi Teqlik'e Dönüştür (+%10) ]               │
├────────────────────────────────────────────────────┤
│  [ 📝  Bilgilerimi Kaydet ve Sıraya Gir ]          │
└────────────────────────────────────────────────────┘
```

Bakiye talep anında atomik olarak düşülür (`UPDATE WHERE tl_earnings_balance >= amount`); `withdrawal_requests INSERT (status='pending')` aynı transaction'da.

**IBAN Kaydı Sonrası Kart 2 Durumu:** `withdrawal_requests.status` (pending / approved / rejected) Kart 2'yi sıra görünümüne dönüştürür. Referans numarası `#Queue-{id}` formatında gösterilir:

```
📋 Sıra No: #Queue-00042
Kurumsal banka entegrasyonumuz açıldığında
transferiniz sırayla işleme alınacaktır.

[ İptal Et ve Bakiyeyi Geri Al ]
[ Teqlik'e Dönüştür (+%10) ]
```

**Uygulama içi mesaj metinleri:**

Kayıt başarılı (BottomSheet kapanırken Snackbar):
> Başlık: **Kaydınız Başarıyla Alındı 📋**
> "IBAN bilgileriniz güvenle kaydedildi ve Öncelikli Transfer Listesi'ne (#Queue-42) eklendiniz. Kurumsal banka transferleri başladığında bildirim alacaksınız. Dilediğiniz an bu talebi iptal edip bakiyenizi bonuslu teqlik olarak da kullanabilirsiniz."

IBAN güncellemesi gerektiğinde (admin `rejected` → bakiye iade → push notification):
> Başlık: **IBAN Güncellemesi Gerekiyor ℹ️**
> "Kayıtlı IBAN bilgilerinizde bir uyumsuzluk tespit edildi. ₺1.000 tutarındaki bakiyeniz eksiksiz olarak cüzdanınıza iade edildi. IBAN bilgilerinizi güncelleyerek dilediğiniz zaman yeniden sıraya girebilirsiniz."

**Dönüştürme Simülatörü (Seçenek C — Anlık Hesap Gösterimi):**

"⚡ ANINDA KULLAN" butonuna veya Bottom Sheet'teki "Teqlik'e Dönüştür" kartına basıldığında, kullanıcı bakiyesini girmeden önce interaktif bir hesap özeti görür. Bakiye TextFormField'a yazıldıkça sonuç gerçek zamanlı güncellenir:

```
┌─ Teqlik'e Dönüştür ───────────────────────────────┐
│  Ne kadar dönüştürmek istiyorsunuz?                │
│  [_₺500_________________]  (max ₺1.450)            │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │  ₺500  →  571 teqlik                        │  │
│  │       +  57 bonus (%10)                     │  │
│  │  ─────────────────────────────              │  │
│  │  Toplam  628 teqlik                         │  │
│  │  (Piyasa değeri: ≈ ₺550)                    │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  [ ⚡ 628 Teqlik Al ]                             │
└────────────────────────────────────────────────────┘
```

Hesaplama formülü (Flutter tarafında, sunucuya göndermeden önce):
```dart
// teqlik_amount = FLOOR(amount_tl / 0.875) * 1.10
// bonus = teqlik_amount - FLOOR(amount_tl / 0.875)
// Örn: FLOOR(500 / 0.875) = 571 teqlik baz; 571 * 1.10 = 628.1 → FLOOR → 628
double base = (amountTl / 0.875).floor().toDouble();
double total = (base * 1.10).floor().toDouble();
double bonus = total - base;  // 57
```
Sunucu da aynı formülü uygular; Flutter gösterimi sadece kullanıcı bilgisi amaçlı.

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

### 6.0 Uygulama İlkeleri

Tüm W1–W13 görevleri aşağıdaki ilkelere uygun geliştirilir:

| # | İlke | Açıklama |
|---|------|---------|
| 1 | **Clean Code** | Tek sorumluluk, anlamlı isimlendirme, yorum yerine okunabilir kod |
| 2 | **Clean Architecture** | Use case katmanı domain'den bağımsız; router sadece delege eder |
| 3 | **MVVM** | Flutter tarafında ViewModel (Riverpod Provider/Notifier) — UI'da iş mantığı yok |
| 4 | **OTA / ARB** | Kullanıcıya gösterilen tüm metinler ARB'ye eklenir; hardcoded string yasak |
| 5 | **ADR uyumu** | Her karar `documents/teqlif_architectural_decisions.md` ile çelişmez |
| 6 | **ADR workflow** | Geliştirme ADR §13'teki 10 adımlı workflow'a göre ilerler |
| 7 | **Commit takibi** | Her görev tamamlandığında bu döküman ilgili commit hash'i ile güncellenir |

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
| 12 | App Store Connect — Subscription Group "Teqlif PRO" + 4 plan (teqlif_pro_1m/3m/6m/12m); EULA + Gizlilik linki + otomatik yenileme metni ekle | **Kullanıcı** | Evet |

### 6.2 Yayıncı Hakediş Sistemi — Görevler (Tüm Altyapı Upfront)

| # | Görev | Yapan | Blokör mu? |
|---|-------|-------|-----------|
| W1 | Migration: `users` (tl_earnings_balance, tl_pending_balance, **pro_expires_at TIMESTAMPTZ, pro_grace_until TIMESTAMPTZ, apple_original_transaction_id VARCHAR(64)**) + `withdrawal_requests` + `gift_events` (earnings_tl NUMERIC(10,4), payout_status DEFAULT 'pending', released_at) + `teqlik_transactions` (apple_transaction_id VARCHAR(64) UNIQUE, raw_receipt TEXT, **product_type VARCHAR(20) DEFAULT 'consumable'**) + `idx_users_pro_status` (user_type, pro_expires_at WHERE user_type='pro') | Backend | Evet |
| W2 | `gift_events` payout index (`idx_gift_events_payout` WHERE payout_status = 'pending') | Backend | Evet |
| W3 | `use_cases/wallet/commands/` yapısı oluştur | Backend | Evet |
| W4 | `verify_apple_receipt_command.py`: x5c zincir + `jwt.decode(leeway=60)` (clock skew) + environment/bundleId hardcoded + velocity limit (Redis, ₺5.000/gün/cihaz; Redis çökerse Fail-Closed) + `raw_receipt=signedTransactionInfo` kaydı; **productId dispatch**: `teqlik_pack_*` → consumable (teqlik_balance +=), `teqlif_pro_*` → subscription (user_type='pro', pro_expires_at, plan_type, apple_original_transaction_id) | Backend | Evet |
| W4c | `handle_apple_notification_command.py`: Apple Notifications V2 webhook; ARQ async (200 OK hemen → payload kuyruğa); DID_RENEW → pro_expires_at uzat; DID_RENEW+BILLING_RETRY → pro_grace_until; EXPIRED/GRACE_PERIOD_EXPIRED → standard; REVOKE → standard + refund akışı | Backend | Evet |
| W5 | `send_gift_command.py`: `tl_pending_balance += TRUNC(cost × pay_rate × 0.50, 2)` + `payout_status='pending'` + earnings_tl NUMERIC(10,4) kaydı + Decimal hassasiyeti + atomik SQL + LEAST(sender,host) kilit sırası + Redis Token Bucket (2/sn) + 8 hediye tipi; **post-commit**: WebSocket broadcast + push notification UoW commit'ten SONRA, transaction bloğu dışında tetiklenir (kilit çakışmasını önler) | Backend | Evet |
| W6 | `get_wallet_summary_query.py`: teqlik_balance + tl_earnings_balance + tl_pending_balance + **cashout_enabled: bool** döndürür; cashout_enabled Redis'ten okunur (`GET teqlif:config:cashout_enabled`; 0/yoksa false, 1 ise true); Flutter bu flag'i API response'undan okur — statik sabit veya .env değil | Backend | Evet |
| W7 | `request_withdrawal_command.py`: tl_earnings_balance atomik düşüm (UPDATE WHERE >= amount, 0 satır → 400) + aktif pending yok kontrolü (409) + withdrawal_requests INSERT — aynı transaction | Backend | Hayır |
| W7b | `convert_to_teqlik_command.py`: Seçenek C (+%10 bonus, atomik SQL) — modal yasal uyarısı zorunlu | Backend | Hayır |
| W7c | `schedule.yaml`: `release_pending_earnings` (02:15 UTC, watchdog_m:30) + `daily_financial_reconciliation` (00:00 UTC, watchdog_m:10) + **`check_expired_pro_users` (03:00 UTC, watchdog_m:60)** — 02:15: Pazar 02:00 pg_basebackup çakışması önlenir; 03:00: webhook kaçırma sigortası; her fonksiyon `worker.py` `_SCHEDULE_FUNCTIONS` sözlüğüne eklenmeli + `await _agent_ok(ctx, "<task_name>")` son satır zorunlu (eksik → sahte alarm) | Backend | Hayır |
| W7e | `cancel_withdrawal_request_command.py`: status='pending' → 'cancelled' + atomik bakiye iadesi + 403 yetki / 409 statü kontrolü; `DELETE /api/wallet/withdraw/{id}` | Backend | Hayır |
| W8 | `handle_apple_refund_command.py`: orantılı gift iptali (payout_status='cancelled_refund', tl_pending_balance azalt) + negatif bakiye + `pending_refund=True`; NO CHECK constraint (webhook retry storm önlemi) | Backend | Evet |
| W9 | Kart 2 UI: `cashout_enabled` flag `GET /api/wallet/summary` response'undan okunur (statik sabit değil); cashout_enabled==false → "Yayın Başlat" CTA (glassmorphism koyu zümrüt/altın kart); cashout_enabled==true → birincil "⚡ ANINDA KULLAN (+%10 Teqlik'e Dönüştür)", ikincil "🏦 Nakit Transferi İçin IBAN Tanımla"; aktif talep varsa sıra kartı (📋 #Queue-{id}, İptal Et, Teqlik'e Dönüştür); hediye ekranında combo tap sayacı (x2/x5/x10 + burst animasyonu) — **optimistic UI**: sayaç animasyonu anlık güncellenir, backend debit debounced (örn. 300ms); bakiye yetersizse toast ile geri al; **`AppLifecycleState.resumed`**: uygulama arka plandan öne gelince `GET /api/wallet/summary` yeniden çekilir (App Store dönüşünde bakiye güncellenmesi için) | Mobile | Hayır |
| W10 | IBAN Ön Kayıt Bottom Sheet: tutar çipleri (₺500 Min / ₺1.000 / Tamamı); IBAN TR formatı + banka logosu; Seçenek C simülatörü (₺500 → 571+57 = 628 teqlik, FLOOR anlık); "Bilgilerimi Kaydet ve Sıraya Gir" CTA (Slide to Confirm YOK); MASAK yasal uyarı panosu | Mobile | Hayır |
| W11 | 5 dil ARB: `giftNameClap`, `giftNameTea`, `giftNameGoldenHammer`, `giftNameRocket`, `giftNameTrophy`, `walletConvertToTeqlik`, `walletIbanPreRegistrationTitle`, `walletIbanRegistrationSuccess`, `walletIbanRejected`, `walletQueueNumber`, `walletPendingEarningsDesc`, `walletStartStreamCta`; **Arapça RTL**: `Directionality.of(context)` ile yön tespiti, gradient yönleri RTL'e göre tersler, `chevron_right`/`chevron_left` dinamik seçilir; **para miktarları**: `NumberFormat.currency(locale: locale.toString(), symbol: '₺')` — string birleştirme (`'₺' + amount`) yasak; **çoğul kurallar**: gün ve teqlik sayıları için ICU plural syntax `{count, plural, =1{# gün} other{# gün}}` | Mobile | Hayır |
| W12 | Admin panel: bekleyen çekim talepleri + Onayla / Reddet (red → `tl_earnings_balance += amount_tl`) | Backend/Admin | Hayır |
| W13 | PRO Abonelik UI: `ProSubscriptionSheet` (glassmorphism — 1/3/6/12 ay plan seçim kartları, fiyat + tasarruf badge, PRO fayda listesi); `pro_badge_widget.dart` (Kart 1 + profil); Kart 1 "PRO'ya Yükselt" CTA (PRO değilse); `IAPService` unified purchaseStream (`teqlif_pro_*` prefix → verify endpoint); **"Satın Alımları Geri Yükle"** butonu (`restorePurchases()` — Apple Guideline 3.1.1 zorunlu); otomatik yenileme uyarı metni (Apple zorunluluğu); `AppLifecycleState.resumed` → wallet summary yenile (PRO badge güncelleme) | Mobile | Hayır |

### 6.3 V1.1'e Ertelenen Özellikler (şirket kuruluşu sonrası)

Aşağıdaki özellikler **şirket kuruluşu tamamlanana kadar** kodlanmaz. Tüm backend use case'leri (W1–W13) ve T+14 cron V1.0'da kurulmuştur; bu liste yalnızca hukuki/regülatif ön koşul gerektiren ek özellikleri içerir. `CASHOUT_ENABLED=true` yapılmadan önce V11-1 ile V11-8 tamamlanmalıdır.

| # | Özellik | Ön koşul | Notlar |
|---|---------|---------|--------|
| V11-1 | `CASHOUT_ENABLED=true` aktive et (Redis key → 1) + gerçek banka transfer API entegrasyonu | LTD/şahıs şirketi + kurumsal banka anlaşması | MASAK zorunlu |
| V11-2 | MERNIS/KYC: TCKN doğrulama (NVİ SOAP API) | Şirket kaydı + API sözleşmesi | `user_kyc` şifreli tablo; AES-256 |
| V11-3 | Rolling Reserve (ilk 90 gün ₺2.500 limit) | Gerçek transfer başlayınca | `rolling_reserve_expires_at` + `rolling_reserve_limit_tl` migration |
| V11-4 | `account_frozen` & `is_in_debt` zorunlu takibi | Gerçek transfer başlayınca | 30 gün ödenmeyen borç → hesap dondur |
| V11-5 | `monthly_free_withdrawals_used` + aylık reset cron | Gerçek transfer (PRO abonelik V1.0'da kurulu) | PRO kullanıcıya 2× ücretsiz çekim hakkı; `reset_monthly_withdrawal_quota` cron ekle |
| V11-6 | Çekim ücreti (₺15 / işlem) + PRO 2× ücretsiz kota | Gerçek transfer | `withdrawal_requests.fee_tl` + `gross_amount_tl` + `withholding_tax_tl` + `net_amount_tl` migration |
| V11-7 | IBAN checksum (TR + 24 karakter + mod-97) | V1.1 form | CASHOUT_ENABLED=false döneminde yalnızca format kontrolü yeterli |
| V11-8 | Admin Maker-Checker (₺2.500+ çift onay, ₺10.000+ 2FA) | Gerçek transfer | Audit log zorunlu |
| V11-9 | Web mağazası (teqlif.com/cuzdan, %2,5 işlemci ücreti) | Şirket + web ödeme altyapısı | Apple bypass — yalnızca web alımlar |
| V11-10 | Finansal soğuk arşiv: SHA-256 imzalı CSV/JSONL → `backups/financial_archives/` + `offsite_sync.sh` uzak depo (Hetzner/B2/S3 Glacier) | Gerçek transfer başlayınca | TTK + MASAK 5-10 yıl saklama; WORM |
| V11-11 | Vergi / Stopaj / Gider Pusulası: Sosyal İçerik Üreticiliği İstisnası belgesi veya Gider Pusulası + stopaj | Şirket + mali müşavir | Beyanname döküm raporu admin panelinde |

### 6.4 V3.0 Vizyon — teqlik Çift Yönlü Para Birimi (Süper Uygulama)

> Bu vizyon; WeChat Pay, Mercado Pago, Roblox DevEx modelinin Teqlif uyarlamasıdır. V1.0–V1.1 mimarisi (atomik kilitler, NUMERIC(10,4) hassasiyeti, T+14 escrow, çift cüzdan ayrımı) bu vizyona geçişte kodları çöpe atmadan BaaS API'si bağlanarak genişleyecek şekilde tasarlanmıştır.

**Aşılması gereken 3 duvar:**

| Duvar | Sorun | Çözüm |
|-------|-------|-------|
| Apple Kural 3.1.5 | IAP ile alınan teqlik fiziksel ürün satışında kullanılamaz; Apple %30 keser, Teqlif batar | teqlif.com/cuzdan üzerinden web alımı (%2–3 POS komisyonu); uygulama içi fiziksel alımlarda Apple IAP değil doğrudan kart/Masterpass altyapısı |
| TCMB 6493 E-Para Kanunu | Üçüncü kişiler arası sanal jeton takası + IBAN'a çekim = E-Para İhracı → 100M+ TL sermaye ve TCMB lisansı | Papara, Param, Sipay veya İyzico ile BaaS/White-Label ortaklığı; parayı Teqlif değil lisanslı kuruluş tutar (Escrow/Havuz); Teqlif yalnızca arayüz |
| AML / MASAK | Çalıntı kartla teqlik al → sahte satış → temiz nakit çek | Satıcı MERNIS + IBAN eşleşmesi zorunlu; kargo teslim onayına T+7/T+14 bloke; rolling reserve |

**2 Katmanlı teqlik Modeli (V3.0):**
```
[A] Satın Alınan teqlik (Purchased)
    • Web/kart ile alınır (%2–3 komisyon)
    • İlanlarda teklif, ürün satın alma, hediye için harcanır
    • ASLA doğrudan nakde çevrilemez (Apple engeli + AML)

[B] Kazanılan teqlik (Earned)
    • Yalnızca başarılı mezat/ürün satışı veya canlı yayın hediyesinden
    • Kargo → alıcı "Teslim Aldım" → T+14 serbest
    • %5–10 platform komisyonu ile IBAN'a nakit çekilebilir
```

**4 Gelir Kanalı (V3.0):**
```
1. Giriş-Çıkış Makası (Spread): Alımda ₺1,10/teqlik, nakit çekimde ₺0,90/teqlik → %10 otomatik platform komisyonu
2. Kasa Rezervi Faizi (Float): Kullanıcıların harcamadığı teqlik TL karşılığı → gecelik repo/faiz geliri
3. Teklif Teminatı (Bid Collateral): Mezattan cayma → teminat teqlik satıcıya/platforma tazminat
4. Hızlı Çekim Ücreti: 3 iş günü ücretsiz; FAST anında çekim ₺20 veya %1 ek komisyon
```

**3 Fazlı Yol Haritası:**
```
FAZ 1 (Şu an — V1.0): Saf teqlik kapalı döngü. Apple StoreKit 2, 8 katmanlı
  hediye, ilan özellikleri. Nakit çıkışı sıfır. Kullanıcı kitlesi büyütülür.

FAZ 2 (Şirket — V1.1): LTD kuruluşu. İyzico/PayTR Güvenli Ödeme/Havuz Hesap.
  Ürün satışında "Param Güvende" escrow. Kargo onayı → IBAN transferi.

FAZ 3 (Süper-App — V3.0): BaaS ortaklığı (Param/Papara). teqlik çift yönlü:
  Ürün alımında harcanır, tekliflerde teminat olur, satıcı kazandığı teqlik'i
  %5–10 komisyonla IBAN'a çeker. Türkiye'nin en büyük sosyal ticaret fintech'i.
```

---

## 7. Analizde Güçlü / Eksik Noktalar

### 7.1 Analizde Doğru ve Kritik

- Apple Kural 3.1.1 zorunlu IAP uyarısı ✅
- Consumable (teqlik paketleri) + Auto-Renewable Subscription (PRO) ürün tipleri ✅
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

**Güncellenecek** — `POST /api/wallet/send-gift` (`wallet.py:191`): şu an teqlik → teqlik aktarımı; implementasyonda teqlik → TL kazanca dönüştürülecek:
```
İzleyici → hediye seçer (gift_name + cost) → stream_id ile gönderir
  Gönderenden:   teqlik_balance -= cost                                   (atomik)
  Yayıncıya:     tl_pending_balance += TRUNC(cost × pay_rate × 0.50, 2)  (atomik, T+14 kilitli)
  payout_status: 'pending'  ← T+14 cron başından itibaren işler
  Platform net:  kalan Teqlif kasasında
```
Dönüşüm kuru: **1 teqlik hediye = ₺0,50 net nakit** (sabit)

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

**Hediye Combo Tap (Ardışık Gönderim):** Yoğun anlarda (mezatın son 10 saniyesi gibi) aynı hediye butonuna art arda basıldığında combo sayacı görsel katmanı aktif olur: x2 → x5 → x10 patlamaları, tırmanan pitch ses efekti. Mevcut Token Bucket (burst: 5) bu davranışı zaten kapsar — backend kuralı değişmez, yalnızca Flutter UI katmanında combo counter animasyonu eklenir. Her dokunuş ayrı bir `send_gift` çağrısıdır; sunucu rate limit kuralları aynı kalır.

**PRO yayıncı flywheel:** Standart ve PRO arasındaki oran farkı her hediyede birikir. PRO abonelik bedelini aylık Taç hediyelerinden karşılamak için gereken sayı (%30 komisyon, 1 aylık plan ₺149,99): ₺149,99 ÷ (₺47,50 − ₺35,00) = **12 Taç/ay**. Small Business Program (%15, ₺119,99/ay) senaryosunda: 9,6 Taç/ay. Aylık 10 Taç alan PRO yayıncının abonelik bedeli otomatik amortize olur. Üstüne arttırılmış kredi kotaları, 720p HD yayın ve V1.1'de 2× ücretsiz çekim hakkı eklenir.

**Bakiye yetersiz → PiP akışı** (`swipe_live_screen.dart:945`):
Kullanıcı hediye atmak isteyip bakiyesi yetmediğinde `_handleLoadBalance()` tetiklenir: yayın PiP moduna alınır, cüzdan ekranı açılır. iOS IAP ile teqlik yükleme geldikten sonra kullanıcı Face ID ile paketi alıp canlı yayına döner — mezatı kaçırmadan satın alma.

**Replay/VOD erişimi:** Canlı yayın kaydına (stream_recordings) erişim **PRO zorunludur** (`streams.py:310`). Standart kullanıcı replay ekranını göremez. Erişim süresi `cluster.yaml` disk politikasıyla sınırlıdır: `minio_expiry_days: 2` (Node 1 MinIO'dan 48 saat sonra silinir) + `retention_days: 15` (Node 2 soğuk depoda 15 gün tutulur). PRO kullanıcı son **14 güne** ait yayın kaydını izleyebilir; daha eski kayıtlar 404 döner.

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

> **Sonuç:** PRO ₺149,99/ay ile kullanıcı **₺360 değerinde ücretsiz kredi + HD yayın + Replay** alıyor — teqlik harcamasına göre %58 tasarruf. Deliberate under-pricing: yüksek retention + organik PRO dönüşümü için. Türkiye'de Spotify ₺39,99, YouTube ₺49,99 — ₺149,99 daha yüksek ama PRO bir iş aracı: satıcı/yayıncı kazancı geri döner.

**V1.0 PRO Paket Yapısı:**

| Plan | App Store Fiyatı | Aylık eşdeğer | Net (KDV+%30)¹ | Net (KDV+%15 SBP)¹ | İndirim |
|------|-----------------|--------------|----------------|--------------------|----|
| 1 Ay (teqlif_pro_1m) | **₺149,99** | ₺149,99 | **₺87,49** | **₺106,24** | — |
| 3 Ay (teqlif_pro_3m) | **₺404,99** | ₺135,00 | **₺236,24** | **₺286,66** | %10 |
| 6 Ay (teqlif_pro_6m) | **₺764,99** | ₺127,50 | **₺445,82** | **₺541,24** | %15 |
| 12 Ay (teqlif_pro_12m) | **₺1.349,99** | ₺112,50 | **₺787,49** | **₺956,24** | %25 |

> ¹ Net = Fiyat ÷ 1,20 × (1 − komisyon) — Türkiye KDV %20 dahil

> **Yıllık paket:** ₺1.349,99 = aylık ₺112,50 → ₺149,99'a göre %25 indirim. Standart endüstri pratiği %25-30 → doğru aralıkta.

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

### 8.5 Tüm Gelir Akışı Haritası (V1.0 + V1.1+)

```
Teqlif Gelir Akışı
├── Consumable IAP (teqlik paketleri)          ← V1.0
│    ├── 100 teqlik — ₺149,99
│    ├── 300 teqlik +50 bonus — ₺429,99  
│    ├── 700 teqlik +150 bonus — ₺999,99
│    └── 1500 teqlik +400 bonus — ₺2.199,99
│
├── Auto-Renewable Subscription (PRO)         ← V1.0
│    ├── 1 Ay — ₺149,99/ay  (teqlif_pro_1m)
│    ├── 3 Ay — ₺404,99/3ay (teqlif_pro_3m) — %10 tasarruf
│    ├── 6 Ay — ₺764,99/6ay (teqlif_pro_6m) — %15 tasarruf
│    └── 12 Ay — ₺1.349,99/yıl (teqlif_pro_12m) — %25 tasarruf
│
├── Web Mağazası (teqlif.com/cuzdan)           ← V1.1 — Apple bypass
│    ├── Aynı 4 paket, yalnızca %2,5 işlemci komisyonu
│    ├── Apple komisyonu (%15–%30) tamamen sıfır
│    ├── Kullanıcıya "web'den al" söylenmez (Kural 3.1.1)
│    │   → Kullanıcı kendi inisiyatifiyle tarayıcıdan gelir
│    └── iOS IAP margin gap: ₺149,99 → Teqlif net ₺87,49 (IAP) vs ₺146,24 (web)
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
└── Çekim Ücreti                               ← V1.1
     ├── Standart: ₺15 sabit/işlem (direkt marj)
     └── PRO: 2 ücretsiz/ay → 3. çekimden itibaren ₺15
         (aylık reset ARQ cron — PRO'ya geçiş teşviki)
         (V1.0'da talep toplama modu — gerçek transfer yok, ücret de yok)
```

---

## 9. Ekonomik Model & Platform Sürdürülebilirlik Analizi

### 9.1 teqlik Ekosistemi — Paranın Akışı

```
İzleyici Kredi Kartı (App Store)
         │  ₺149,99 (100 teqlik paketi)
         ▼
[ Apple Kasası ] ─────────────────────────────────────────┐
   • %20 KDV devlete gider (₺25,00)                       │ Apple Net-45 Gün
   • %30 Apple komisyonu (₺37,50)                         │ bekletir
   • Teqlif Net Hakediş: ₺87,49 (₺0,875 / teqlik)         │
         │                                                ▼
         ▼                                       [ Teqlif Banka Hesabı ]
[ Kullanıcı Cüzdanı ]                                     (₺87,49 nakit girer)
   100 teqlik yüklenir (Sanal Değer)
         │
         ├──────────────────────┬──────────────────────┬──────────────────────┐
         │                      │                      │                      │
         ▼                      ▼                      ▼                      ▼
  [ İlan Özelliği ]     [ Canlı Yayın Hediyesi ]  [ PRO Abonelik ]      [ IBAN Ön Kayıt ]
  Boost / AI / Blast     PRO Yayıncıya Taç(100)    ₺149,99/ay Apple    Yayıncı ₺500+
  • Yayıncı payı: ₺0     • Yayıncıya: ₺47,50       • Nakit çıkış: ₺0  çekim talep eder
  • Nakit çıkış: ₺0        (T+14 kilitli)           • Teqlif net: ₺87,49• Nakit çıkış: ₺0
  • Teqlif kârı: %100    • Teqlif net: ₺40,00       (MRR + KDV+%30)     (Queue listesi)
                           • Brüt marj: %45,7

```

**Paranın Üç Kolu — Her Biri Teqlif Lehine:**
- **Kol 1 (Özellik harcaması):** Kullanıcı Boost/AI/Blast yaparken %100 net marj. Apple harcamadan ek kesinti almaz — alım anında bir kez kesti, bitti.
- **Kol 2 (Hediye):** Yayıncı T+14 havuzundaki TL'yi büyük ihtimalle Seçenek C ile teqlik'e çevirir (%65+ kullanıcı bu yolu seçer) — Teqlif'ten nakit çıkış sıfır. Nakit çekse bile %30–45 Teqlif payı kasada kalır.
- **Kol 3 (IBAN Ön Kayıt):** V1.0'da gerçek transfer yok; Apple'dan para gelmeden liste tutulur, V1.1'de transfer başladığında bile çekim ücreti + komisyon farkı kasada kalır.

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
   └─► [C] PRO Abonelik (V1.0: yalnızca Apple Auto-Renewable Subscription)
            → KDV+%30 → Teqlif %58,3 net; MRR sağlar; Apple otomatik yönetir
```

**Kritik insight:** teqlik harcamak (B ve C-teqlik yolu) Apple'a ek komisyon ödetmiyor. Apple zaten [A] aşamasında kesiyor. Yani **teqlik ne kadar çok kullanılırsa birim başına marjimiz o kadar artar** — çünkü alım anında Apple bir kez kesiyor, harcamada bir daha kesmiyor.

**Hibrit Döngü Ekonomisi (V1.0):** teqlik satın alma kapalı döngü olmaya devam ediyor — kullanıcı satın aldığı teqliği doğrudan nakde çeviremiyor. Ancak yayıncılar hediyelerden kazandıkları TL'yi IBAN'a çekebiliyor (V1.0).

- **İzleyici teqlik alımı (kapalı):** IAP ile giren teqlik doğrudan dışarı çıkmaz. Kullanıcı Boost, Blast, AI veya hediye için harcar. Apple Kural 3.1.1 tam uyumlu.
- **Yayıncı TL kazancı (açık):** Hediyelerden elde edilen TL "emek karşılığı kazanç" — Apple/Google bu çıkışa karışmaz (TikTok, Twitch modeli). BDDK/MASAK: yayıncı "satın aldığı jetonları" değil, "hak ettiği geliri" çekiyor; platform komisyon kesip gönderdiği için bu bir ödeme kuruluşu işlemi değil, istihdam benzeri gelir ödemesi.
- **Finansal kaldıraç:** Satılan teqlikin özellik harcaması (Boost/Blast/AI) kısmı dormant kalırsa sıfır maliyetli gelir. Hediye kısmı TL'ye dönüşse de Teqlif kasasında net marj kalıyor (her Crown hediyesinde ₺40–₺52,50).

### 9.2 PRO Abonelik Ekonomisi (V1.0 — Apple Auto-Renewable Subscription)

**V1.0 PRO modeli:** Yalnızca Apple Auto-Renewable Subscription. Teqlik token ile PRO alma V1.1'e ertelendi.

**V1.0 PRO fiyatları:**

| Plan | Apple fiyatı | Teqlif net (%30, KDV %20) | Aylık eşdeğer net |
|------|-------------|--------------------------|-------------------|
| 1 Ay (teqlif_pro_1m) | ₺149,99/ay | **₺87,49** | ₺87,49 |
| 3 Ay (teqlif_pro_3m) | ₺404,99/3ay | ₺236,24 | **₺78,75** |
| 6 Ay (teqlif_pro_6m) | ₺764,99/6ay | **₺445,82** | ₺74,30 |
| 12 Ay (teqlif_pro_12m) | ₺1.349,99/yıl | **₺787,49** | ₺65,62 |

> Small Business Program (%15, KDV %20) senaryosunda 1 aylık Teqlif net: ₺106,24.

**V1.0 ProSubscriptionSheet — kullanıcıya sunulacak görünüm:**

```
┌─────────────────────────────────────────────────────────┐
│  Teqlif PRO                                             │
│                                                         │
│  [ 1 AY ]   [ 3 AY -%10 ]   [ 6 AY -%15 ]  [ 1 YIL -%25 EN İYİ ]
│                                                         │
│  ₺149,99 / ay                                           │
│  ✦ 720p HD yayın                                        │
│  ✦ Hediyelerden %95 pay (Standart: %70)                 │
│  ✦ Replay (son 14 gün) izleme                           │
│  ✦ Gelişmiş analitik                                    │
│                                                         │
│  [ PRO'ya Geç ]                                         │
│  Abonelik otomatik yenilenir. Apple Kimliği             │
│  ayarlarından istediğinizde iptal edebilirsiniz.        │
│  ─────────────────────────────────────────             │
│  [ Satın Alımları Geri Yükle ]  (zorunlu)               │
└─────────────────────────────────────────────────────────┘
```

**Marj notu:** Subscription geliri consumable'dan farklı değil; Apple aynı KDV+komisyon mekanizmasını uyguluyor. MRR (Monthly Recurring Revenue) avantajı: consumable tek seferlik, subscription öngörülebilir nakit akışı sağlar.

**V1.1+ için değerlendirilebilir:** teqlik token ile PRO Pass (30 gün erişim için 120 teqlik harcama) — Apple Guideline 3.1.2(a) buna izin veriyor; consumable credits ile abonelik benzeri içerik açmak yaygın oyun pratiği. Bu modelde Teqlif Apple'a ek kesinti vermez (alım anında kesilmişti), kullanıcıya büyük paket alma teşviki verir.

### 9.3 teqlik Fiyat Dengesi — Harcama vs Yükleme

**Mevcut teqlik harcama oranları:**

| Özellik | Maliyet | Aylık kullanım (tahmin) |
|---------|---------|------------------------|
| AI Açıklama | 5 teqlik | 2-3× / ilan oluşturma |
| İlan Yenileme | 10 teqlik | 1× / ay (pasif ilan) |
| Blast | 10 teqlik | 1-2× / ay |
| İlan Boost | 50 teqlik | 1× / ay |
| PRO Abonelik | ₺149,99/ay (Apple) | Aylık sabit (Auto-Renewable) |

**Tipik kullanıcı profilleri:**

| Profil | Aylık harcama | Aylık teqlik maliyeti | Önerilen paket |
|--------|--------------|----------------------|----------------|
| Hafif (1 ilan, 1 blast) | 15 teqlik | ₺21,45 | 100 teqlik paketi |
| Orta (2 ilan, 1 boost, 2 blast) | 130 teqlik | ₺185,90 | 300 teqlik paketi |
| Ağır (3 ilan, 2 boost, 3 blast, AI) | 245 teqlik | ₺350,35 | 700 teqlik paketi |
| PRO (Abonelik + özellikler) | 130 teqlik + ₺149,99/ay | — | PRO sub + 300 paket |

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
4. **PRO teşviki:** PRO Abonelik aylık ₺149,99 → büyük paket (300+ teqlik) alma motivasyonu sağlar; yıllık plan ₺112,50/ay efektif maliyete iner

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

> **Enterprise PRO (V1.1+):** Düzenli büyük ciro yapan satıcılar ve profesyonel yayıncılar için üst segment plan: **₺249,99/ay**, %98 yayıncı pay oranı, sınırsız replay erişimi, ₺0 çekim ücreti (unlimited), öncelikli müşteri desteği. V1.0'da yalnızca PRO ve Standart olmak üzere iki tier; Enterprise V1.1+ kapsamında.

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
| PRO Subscription (%15, ₺149,99) | ₺22.499 | **₺13.124** |
| **Toplam** | | **~₺83.124** |
>
> **KDV düzeltmesi etkisi:** Önceki projeksiyon ₺96.399 net gösteriyordu (%30 kesinti varsayımıyla). KDV %20 dahil edilince ₺79.450'ye geriledi — ₺16.949 fark (%17,5). Bu fark tüm finansal planlama dökümanlarına yansıtılmalı.

**Altyapı ₺40.000 → Net kâr: ~₺43.124/ay** (1.000 ödeme yapan kullanıcıda)

### 9.9 Karma Kohort Simülasyonu — 1 Aylık Gerçekçi Ekosistem (1.000 Aktif Kullanıcı)

**A. Sisteme Giren Gelirler (IAP Satışları):**

| Kullanıcı Segmenti | Adet | Paket | Brüt | KDV (%20) | Apple (%30) | Teqlif Net |
|--------------------|------|-------|------|-----------|-------------|------------|
| Küçük Alıcılar | 500 | 100 teqlik (₺149,99) | ₺74.995,00 | ₺12.499,17 | ₺18.748,75 | ₺43.747,08 |
| Orta Alıcılar | 200 | 350 teqlik (₺429,99) | ₺85.998,00 | ₺14.333,00 | ₺21.499,50 | ₺50.165,50 |
| Mezat Balinaları | 40 | 1.900 teqlik (₺2.199,99) | ₺87.999,60 | ₺14.666,60 | ₺21.999,90 | ₺51.333,10 |
| PRO Aboneler | 150 | 1 Ay PRO (₺149,99 IAP) | ₺22.498,50 | ₺3.749,75 | ₺5.624,63 | ₺13.124,12 |
| **TOPLAM** | **890** | | **₺271.491,10** | **₺45.248,52** | **₺67.872,78** | **₺158.369,80** |

**B. İçerideki Harcama & Hakediş Dağılımı (266.000 teqlik):**

| Kullanım Alanı | Harcanan teqlik | Yayıncı Hakedişi (TL) | Teqlif Kasasında Kalan |
|----------------|-----------------|----------------------|----------------------|
| İlan Boost & Vitrin | 90.000 | ₺0,00 | ₺62.100,00 (%100 net) |
| AI Açıklama & Blast | 26.000 | ₺0,00 | ₺17.940,00 (%100 net) |
| Canlı Yayın Hediyeleri (PRO %95) | 100.000 | ₺47.500,00 (T+14 havuzda) | ₺21.500,00 (net komisyon) |
| Canlı Yayın Hediyeleri (Std %70) | 30.000 | ₺10.500,00 (T+14 havuzda) | ₺10.200,00 (net komisyon) |
| **TOPLAM** | **246.000** | **₺58.000,00** | **₺111.740,00** |

**C. Yayıncı Çıkış Kanalları (₺58.000 toplam hakediş):**

| Kanal | Oran | Tutar | Teqlif'ten Nakit Çıkışı |
|-------|------|-------|------------------------|
| Seçenek C (Teqlik'e Dönüştür +%10) | %65 | ₺37.700 → 47.392 teqlik | **₺0,00** — para kapalı döngüde kaldı |
| IBAN Ön Kayıt (#Queue listesi) | %25 | ₺14.500 → sıra listesi | **₺0,00** — V1.1'e kadar bekler |
| T+14 Havuzu (olgunlaşmadı) | %10 | ₺5.800 → henüz serbest değil | **₺0,00** |

**D. 1 Aylık Net Finansal Sonuç:**

| Kalem | Tutar |
|-------|-------|
| Apple'dan gelen net tahsilat | +₺158.369,80 |
| Teqlif'ten çıkan gerçek nakit (V1.0) | ₺0,00 |
| Altyapı VPS giderleri (Node 1–6 + nodeMonitor) | −₺40.000,00 |
| **Aylık Net Nakit Akışı Kârı** | **+₺118.369,80** |

> V1.1'de ₺14.500 Queue sırası ödendiğinde bile aylık net: **+₺103.869,80** — sistemin kendini finanse etmesi için gerekli olan V1.1 banka entegrasyonu maliyetini fazlasıyla karşılar.

### 9.10 Platform Savunma Matrisi — Tüm Edge Case'ler

| # | Senaryo | Risk | Savunma Mekanizması | Sonuç |
|---|---------|------|---------------------|-------|
| E1 | **Refund Çetesi:** Kullanıcı 1.000 teqlik alır, hediye atar, Apple'dan iade ister | Platform yayıncıya ödedi, Apple parayı geri aldı — çifte zarar | `handle_apple_refund_command.py`: T+14 dolmamış hediyelerde `cancelled_refund`, `tl_pending_balance` düşülür | Yayıncıya haksız para gitmez; Teqlif kasasından 1 kuruş çıkmaz |
| E2 | **Geç Apple İadesi:** İade 20. günde geldi, bakiye serbest kalmıştı | `tl_earnings_balance` negatife düşer; DB CHECK varsa webhook 500 verir ve sonsuz retry döner | DB'de `CHECK (>= 0)` yasak. `tl_earnings_balance` negatife düşer, `pending_refund = True` bayrağı | Borç mahsubu: sonraki kazançlar eksi bakiyeyi kapatır; webhook asla 500 vermez |
| E3 | **Apple Net-45 Uçurumu:** Hediye 14. günde serbest, yayıncı nakit istiyor; Apple Teqlif'e 45. günde öder | Teqlif tahsil etmediği parayı cebinden ödemek zorunda — nakit iflası | V1.0 Ön Kayıt modu: nakit çekim hemen yapılmaz; birincil buton Seçenek C (+%10 bonus) | Yayıncı ilan gücüne çevirir; nakit çıkışı sıfırlanır |
| E4 | **Kullanıcı Sırada Beklerken Vazgeçer:** ₺500 çekim sırasında akşam mezatını kaçırmak istemez | Bakiye kilitli kalırsa müşteri memnuniyetsizliği, churn riski | `cancel_withdrawal_request_command.py` (`DELETE /withdraw/{id}`): tek tıkla iptal, bakiye anında iade | Kullanıcı 628 teqlik'e çevirip mezatta teklif verir; para platformda kalır |
| E5 | **Bot Gift Flood:** Script ile saniyede 100 hediye, DB ve WebSocket çöküşü | Sunucu kilitlenmesi, bakiye senkron hataları | Redis Token Bucket: 2/sn (burst 5); limit aşılırsa 429; ısrar ederse 10 dk ban | Sunucu yükü sabit kalır; kilitlenme yaşanmaz |
| E6 | **MASAK/CİMER Şikâyeti:** "Teqlif paramı vermiyor" | Yetkisiz bankacılık/ödeme kuruluşu soruşturması | Arayüzde ödeme sözü yok; "Kurumsal bankacılık öncesi Ön Kayıt ve Hakediş Koruma Sırası" — kullanıcı istediğinde iptal edip içeride kullanabilir | Hukuken "yetkisiz para transferi" oluşmaz; kapalı döngü beta yazılım testi |
| E7 | **Kuruş Kaçağı:** 10.000 adet 1 teqlik hediye, PRO payı ₺0,4750; ROUND yapılırsa ₺0,005 × 10.000 = ₺50 buharlaşır | Platform aleyhine kuruş kaçağı | `gift_events.earnings_tl` NUMERIC(10,4); kullanıcı bakiyesine aktarımda `TRUNC(x, 2)`; ₺0,4750 → ₺0,47 | Kuruş kaçağı sıfır; küsurat Teqlif lehine |

### 9.11 Bu Platform Neden Batmaz — Dört Temel Güç

**1. Parayı Önden Tahsil Eder (Negatif İşletme Sermayesi Avantajı)**
Kullanıcı teqlik'i alırken para kasaya girer. Özellikler kullanıldıkça veya yayıncı nakde dönüştürdükçe yükümlülük erir. Teqlif hiçbir zaman "önce hizmeti ver, sonra para al" pozisyonunda değil — tam tersi.

**2. Kendi Parasını Basar (Sıfır Maliyetli Büyüme)**
Kullanıcıya verilen +%10 bonusların veya dönüşüm teşviklerinin Teqlif'e maliyeti ₺0'dır. Sanal token basıp dağıtarak nakit çıkışını engeller, kullanıcı bağlılığını pekiştirir.

**3. Her İşlemden Komisyon Alır (Katmanlı Marj)**
- İlan özelliği: %100 Teqlif marjı
- Hediye: %30–45 Teqlif marjı
- PRO Subscription: %87,49 net / ay (KDV+%30 sonrası — Apple bir kez keser)
- Çekim (V1.1): ₺15 sabit ücret + Rolling Reserve faiz fırsatı

**4. Hukuki Zırh Tamamdır (V1.0)**
Şirketleşene kadar dışarıya 1 TL bile kontrolsüz para çıkarmadığı için maliye ve MASAK karşısında temiz: kapalı döngü, beta yazılım testi. V1.1'de şirket + MASAK uyumu ile tam lisanslı operasyon.

### 9.12 V2.1 Altyapı Teknolojileri — Kullanım Karması

**4 Katmanlı Transaction Güvencesi (RPO ≈ 0):**
```
Katman 1 — pg_receivewal (Anlık WAL Stream, Node 1 → Node 2 WireGuard)
  Her cüzdan transaction'ı tamamlanır tamamlanmaz Node 2'ye stream edilir.
  Node 1 fiziksel olarak yok olsa bile tek kuruş veri kaybı sıfır.

Katman 2 — pg_dump (Her gün 03:00 UTC, mantıksal yedek)
  Node 2 Node 1'den mantıksal SQL yedeği çeker; pg_restore --list bütünlük testi.

Katman 3 — pg_basebackup (Her Pazar 02:00 UTC, fiziksel snapshot)
  Disk blok seviyesinde tam kopya. Cüzdan kron 02:15'te başlar — çakışma sıfır.

Katman 4 — daily_financial_reconciliation (Her gün 00:00 UTC, watchdog_m:10)
  Toplam bakiye == Yüklemeler - Harcamalar - Çekimler.
  1 kuruş sapma → Telegram Critical Alert + admin_flags kaydı.
```

**scale/V2.1 Bileşen Kullanım Karması:**

| Teknoloji | Cüzdan Mimarisindeki Kullanımı |
|-----------|-------------------------------|
| Bare Metal NVMe (Node 1) | Atomik bakiye kilitleri + PgBouncer connection pool — disk I/O darboğazı yok |
| WireGuard Mesh (10.10.0.0/24) | pg_receivewal şifreli P2P tünel; Node 1 ↔ Node 2 anlık finansal veri akışı |
| ClickHouse (Node 2) | `sync_pg_to_clickhouse_task` (01:50 UTC) — hediye kazançları analitik motoruna; ana DB yükten arındırılmış |
| ARQ & schedule.yaml | Cron doğrudan koda gömülmez; merkezi IaC + `_agent_ok` watchdog sinyali |
| Redis Core (Node 1:6379) | Token Bucket rate limit (2/sn), IAP velocity limit (₺5.000/gün/cihaz), Fail-Safe/Fail-Closed |
| Bulkhead Workers | Cüzdan durum bildirimleri → `queue_name="critical"` (30sn); ML eğitimleri → `default` — karşılıklı blok yok |
| LiveKit + PiP (Node 3/4) | Bakiye bitince video kesilmeden PiP; StoreKit satın alma Node 1 üzerinden bağımsız akar |

---

## 10. Karar Özeti

| Konu | Karar | Sürüm |
|------|-------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 | V1.0 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 teqlik** | V1.0 |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 teqlik** | V1.0 |
| Efektif teqlik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) | V1.0 |
| teqlik IAP ürün tipi | **Consumable** | V1.0 |
| PRO üyelik IAP ürün tipi | **Auto-Renewable Subscription** | V1.0 |
| Backend doğrulama | App Store Server API v2 JWS | V1.0 |
| Refund politikası | REFUND webhook zorunlu — bakiyeden düş + orantılı gift iptali + çekim sonrası negatif bakiye (borç mahsubu) + NO CHECK CONSTRAINT | V1.0 |
| Android | V1.0 kapsamı dışı | — |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi | V1.0 |
| Hediye sistemi (teqlik → TL dönüşüm) | **V1.0** — send-gift güncellenmeli; payout_status='pending' başından | V1.0 |
| Hediye kalemleri | **8 katman** — clap(1)·tea(5)·fire(10)·diamond(50)·crown(100)·golden_hammer(250)·rocket(500)·trophy(1000) | V1.0 |
| Animasyon katmanları | Mikro/Std: yüzen ikon · Premium: parlama · VIP: tam ekran Lottie + banner | V1.0 |
| Yayıncı TL kazanç takibi | Hediyelerden tl_pending_balance birikimi (başından); T+14 cron ile tl_earnings_balance'a aktarım; CASHOUT_ENABLED=false → UI gizler | V1.0 |
| IBAN çekim modu | **Talep toplama** — baştan implemente; CASHOUT_ENABLED=false → UI'da gizli; bakiye talep anında atomik düşülür; red → iade; gerçek banka transferi V15-1 sonrası | V1.0 |
| Seçenek C (Teqlik'e Dönüştür) | tl_earnings_balance → teqlik +%10 bonus; atomik SQL; CASHOUT_ENABLED=false → UI'da gizli | V1.0 |
| T+14 holding süresi | **Başından aktif** — Apple refund sigortası; idempotent cron + CTE `WITH locked_events AS (... FOR UPDATE SKIP LOCKED) SELECT ... GROUP BY`; CASHOUT_ENABLED'dan bağımsız çalışır | V1.0 |
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
| Apple Net-45 nakit akışı | Apple ödemeleri Net-33/45 gün sonra gelir; yayıncıya 14. günde nakit ödenmesi imkânsız — Seçenek C bu gecikmeyi bypass eder, nakit ön kayıt Apple ödemesi gelince işleme alınır | V1.0 |
| Kullanıcı çekim iptal hakkı | `cancel_withdrawal_request_command` — status='pending' talebi kullanıcı iptal edebilir; bakiye anında iade, statüsü 'cancelled' | V1.0 |
| Apple Notifications V2 JWS doğrulama | `signedPayload` Apple x5c sertifika zincirine karşı doğrulanmadan event type'a güvenilmez; leaf cert + G3 CA + Root CA + sertifika süresi zorunlu | V1.0 |
| Dönüştürme simülatörü | TextFormField değişince anlık FLOOR hesabı: "₺500 → 571 + 57 bonus = 628 teqlik"; Flutter tarafı önizleme, sunucu aynı formülü uygular | V1.0 |
| Gerçek banka transfer API | Şirket kuruluşu sonrası (LTD zorunlu) | **V1.1** |
| MERNIS / KYC | İlk gerçek çekim zorunlu; TCKN AES-256 şifreli `user_kyc` tablosunda | **V1.1** |
| Rolling Reserve | Yeni yayıncı 90 gün max ₺2.500/çekim | **V1.1** |
| IBAN checksum | TR + 24 karakter + mod-97 doğrulama | **V1.1** |
| Çekim ücreti | ₺15 sabit — PRO ayda 2 ücretsiz | **V1.1** |
| Concurrency (withdraw) | Redis SETNX lock:withdraw:{uid} EX 10 + atomik SQL WHERE bakiye | **V1.1** |
| Borç dondurma | 30 günlük ödenmemiş borçta account_frozen; tüm ilanlar pasif | **V1.1** |
| Admin Maker-Checker | ₺2.500+ çekimde 2 admin onayı; ₺10.000+ 2FA zorunlu | **V1.1** |
| Web mağazası (teqlif.com/cuzdan) | %2,5 işlemci komisyonu, Apple bypass | **V1.1** |
| Başlangıç Boost (İlan Ver'de) | İlan oluşturulurken 50 teqlik Boost seçeneği | V1.1 |
| PRO anchor fiyatı | **₺149,99/ay** (Subscription Group: Teqlif PRO) | V1.0 |
| PRO planlar | teqlif_pro_1m ₺149,99 / teqlif_pro_3m ₺404,99 / teqlif_pro_6m ₺764,99 / teqlif_pro_12m ₺1.349,99 | V1.0 |
| PRO Pass (teqlik ile) | teqlik bazlı PRO Pass | **V1.1** |
| Enterprise PRO | ₺249,99/ay, %98 pay, ₺0 çekim, sınırsız replay | **V1.1+** |
