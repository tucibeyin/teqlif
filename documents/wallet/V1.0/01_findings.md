# teqlik Wallet — V1.0 Bulgular & Karar Belgesi

**Tarih:** 2026-10-23  
**Kapsam:** iOS IAP entegrasyonu, fiyatlandırma stratejisi, UX mimarisi, Apple uyum gereksinimleri  
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
  → apple_transaction_id ile TeqlikTransaction'ı bul
  → teqlik_balance -= iade_miktarı  (atomik)
  → bakiye < 0 ise: users.pending_refund = true
  → RefundLog kaydı oluştur
  → 200 OK döndür (Apple retry yapar 4xx'te)
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

---

## 5. UX & Ekran Mimarisi

### 5.1 Ekran Yapısı (Onaylanan)

```
┌──────────────────────────────────────────────┐
│  AppBar: Cüzdanım         [İşlem Geçmişi]    │
├──────────────────────────────────────────────┤
│  Hero Balance Card (altın gradyan)           │
│  • Bakiye: 140 teqlik  [PRO rozeti]          │
│  • Bakiye yüklenince sayı yukarı sayar       │
├──────────────────────────────────────────────┤
│  [ teqlik Yükle ] | [ İşlem Geçmişi ]       │
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

### 8.2 Hediye (Gift) Sistemi — Planlı Özellik

**Konsept:** Kullanıcı A, kullanıcı B'ye teqlik gönderir (örn. bir satıcıya "teşekkür" veya "boost yap" desteği).

**Apple IAP perspektifi:** Hediye transferi yeni bir Apple IAP satın alımı DEĞİLdir — halihazırda satın alınmış teqlik bakiyesinin kullanıcılar arasında aktarılmasıdır. Apple bunu yasaklamıyor; App Review kılavuzlarında "transferable virtual currency" özel bir kısıt içermiyor.

**Endüstri notu:** Kullanıcılar arası sanal para hediyesi classified/marketplace uygulamalarında nadir — çoğu uygulama bunu desteklemiyor. Bu, teqlik için differentiating bir özellik.

**Tasarım gereksinimleri:**

```
Kullanıcı B'nin profili / ilan detayı
  [Hediye Gönder 🎁]
       │
       ▼
  Miktar seç: [10] [25] [50] [100] veya özel giriş
  "Gönderilecek: 50 teqlik"
       │
       ▼
  [Onayla] → Bakiye kontrol → Transfer → Bildirim
```

**Akış:**
- Gönderen: bakiyeden düşülür, işlem geçmişine "Hediye gönderildi → @kullanıcıB" yazılır
- Alan: bakiyeye eklenir, bildirim: "@kullanıcıA sana 50 teqlik hediye gönderdi!"

**Risk azaltma kuralları (zorunlu):**
- Minimum hediye: 10 teqlik
- Maksimum günlük gönderim: 200 teqlik / kullanıcı (döngüsel kullanımı engeller)
- Alıcı sadece **aynı gün içinde alınan hediyeyi** transfer edemez (24s bekleme — self-transfer döngüsünü kırar)
- Backend: `gift_transactions` tablosu, `giver_id + receiver_id + created_at` loglama

**BDDK/MASAK notu:** Sanal oyun parası gibi kapalı ekosistem kurrencies Türkiye'de ödeme aracı sayılmıyor. Ancak bu konu hukuki belirsizlik taşıdığından, hediye sistemi açıldığında bir hukuki görüş alınması tavsiye edilir.

**Scope:** Hediye sistemi teqlik satın alma akışına bağımlı değil — backend tek endpoint, bağımsız geliştirilebilir. V1.1 veya V2.0 planlanabilir.

> **Not — Canlı Yayın Hediyesi (Ayrı Sistem):** `POST /api/wallet/send-gift` endpoint'i ZATEN mevcuttur (`wallet.py:191`) ancak bu `stream_id` zorunlu bir **canlı yayın hediyesidir** — izleyiciden yayıncıya, yayın sırasında. PRO yayıncı %95, standart yayıncı %70 komisyon alır. Bu §8.2'deki genel kullanıcıdan-kullanıcıya hediye sisteminden bağımsızdır; canlı yayın akışının IAP ile teqlik yükleme gelmesiyle hedge cirosu doğrudan büyüyecek.

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
| Profil rozeti | — | ✓ Doğrulanmış rozet |
| İlan sıralaması | Normal | Aynı kategoride +öncelik |
| İstatistik / Analytics | Temel | Detaylı (görüntülenme, tıklama) |
| Müşteri desteği | Standart | Öncelikli |

> **App Store Connect'te iki ayrı ürün grubu gerekiyor:** Consumable grubu (teqlik paketleri) + Auto-Renewable Subscription grubu (PRO planlar). Her grup ayrı Apple onayından geçiyor.

### 8.5 Tüm Gelir Akışı Haritası (V1.0 + V2.0)

```
TEQLif Gelir Akışı
├── Consumable IAP (teqlik paketleri)
│    ├── 100 teqlik — ₺149,99
│    ├── 300 teqlik +50 bonus — ₺429,99  
│    ├── 700 teqlik +150 bonus — ₺999,99
│    └── 1500 teqlik +400 bonus — ₺2.199,99
│
├── Auto-Renewable Subscription (PRO)         ← V2.0
│    ├── 1 Ay — ₺79,99
│    ├── 3 Ay — ₺214,99
│    ├── 6 Ay — ₺389,99
│    └── 12 Ay — ₺679,99
│
├── teqlik Harcama Noktaları
│    ├── AI Açıklama (5 teqlik) — create_listing_screen ✅
│    ├── İlan Yenileme (10 teqlik) ✅
│    ├── Blast / Kitle Bildirimi (10 teqlik) ✅
│    ├── İlan Boost (50 teqlik) ✅
│    └── Başlangıç Boost (ilan oluşturulurken, 50 teqlik) ← V1.1
│
├── Canlı Yayın Hediyesi (send-gift)           ← ✅ V1.0 mevcut — stream_id ile, PRO %95 / std %70
└── Genel Kullanıcı-Kullanıcı Hediye          ← V1.1/V2.0 — hukuki görüş al
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

| Konu | Karar |
|------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 teqlik** |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 teqlik** |
| Efektif teqlik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) |
| teqlik IAP ürün tipi | **Consumable** |
| PRO üyelik IAP ürün tipi | **Auto-Renewable Subscription** (V2.0) |
| Backend doğrulama | App Store Server API v2 JWS |
| Refund politikası V1.0 | **REFUND webhook zorunlu** — bakiyeden düş + pending_refund flag |
| Android | V1.0 kapsamı dışı |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi |
| Hediye sistemi | V1.1/V2.0 — planlı, hukuki görüş önerilir |
| Başlangıç Boost (İlan Ver'de) | V1.1 — yüksek öncelik |
| PRO anchor fiyatı | **₺79,99/ay** (₺99,99 değil — teqlik eşdeğeri ₺100, başabaş kabul edilemez) |
| PRO Pass fiyatı (teqlik) | **56 teqlik** — büyük pakette ₺64,96 efektif maliyet vs ₺79,99 cash |
| PRO planlar | V2.0 — 1ay ₺79,99 / 3ay ₺214,99 / 6ay ₺389,99 / 12ay ₺679,99 |
