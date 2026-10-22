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
| **teqlik (planlanan)** | 1 teqlik | **₺1,43** (%30) / **₺1,18** (%15) | — | %30 veya %15 (Apple) | İlan güçlendirme |

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

**%30 komisyon ile:**
```
Kullanıcı fiyatı = Net hedef / (1 - 0.30) = 1 TL / 0.70 = 1.4286 TL/teqlik
```

**%15 komisyon ile (Small Business):**
```
Kullanıcı fiyatı = 1 TL / 0.85 = 1.176 TL/teqlik
```

> **Öneri:** İlk lansman için %15 Small Business Program'a başvur, fiyatları buna göre belirle. Eğer programa girilemezse %30 hesabı geçerli.

### 2.3 Önerilen Paket Fiyatları

#### %30 Komisyon Senaryosu (Konservatif / Garantili)

| Paket | teqlik | Bonus | Toplam | App Store Fiyatı | Net Gelir | Efektif TL/teqlik |
|-------|--------|-------|--------|-----------------|-----------|-------------------|
| Başlangıç | 100 | — | 100 | **₺149,99** | ₺104,99 | ₺1,50 |
| Popüler 🔥 | 300 | +50 | 350 | **₺429,99** | ₺300,99 | ₺1,00 |
| Avantaj 💎 | 700 | +150 | 850 | **₺999,99** | ₺699,99 | ₺0,82 |
| Mega | 1500 | +400 | 1900 | **₺2.199,99** | ₺1.539,99 | ₺0,81 |

#### %15 Komisyon Senaryosu (Small Business — Önerilen)

| Paket | teqlik | Bonus | Toplam | App Store Fiyatı | Net Gelir | Efektif TL/teqlik |
|-------|--------|-------|--------|-----------------|-----------|-------------------|
| Başlangıç | 100 | — | 100 | **₺119,99** | ₺101,99 | ₺1,02 |
| Popüler 🔥 | 300 | +50 | 350 | **₺349,99** | ₺297,49 | ₺0,85 |
| Avantaj 💎 | 700 | +150 | 850 | **₺829,99** | ₺705,49 | ₺0,83 |
| Mega | 1500 | +400 | 1900 | **₺1.749,99** | ₺1.487,49 | ₺0,78 |

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

**Refund / Revocation:**
Apple bir satın alımı geri alabilir (`REFUND` App Store Server Notification). Bu geldiğinde politika kararı gerekiyor:
- Seçenek A: Bakiyeden düş (kullanıcı kızabilir)
- Seçenek B: Hesabı askıya al
- Seçenek C: Görmezden gel (Apple'ın para iadesi zaten gerçekleşti)
→ **V1.0 için:** Seçenek C + log kaydı. Refund webhook'u ileriye ertelenebilir.

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

| Özellik | Standart ücreti | PRO tasarrufu |
|---------|----------------|--------------|
| +4 ekstra yenileme/ay | 4 × 10 teqlik × ₺1,43 | **₺57,20** |
| +3 blast/ay | 3 × 10 teqlik × ₺1,43 | **₺42,90** |
| **Toplam aylık teqlik değeri** | **70 teqlik** | **₺100,10** |

> **Sonuç:** PRO ₺99,99'dan fiyatlanırsa kullanıcı "neredeyse sıfır kazanıyor" — abonelik yerine teqlik almak aynı şey. PRO en az %15-20 avantaj sunmalı ki karar net olsun. **Doğru anchor: ₺79,99/ay.** Kullanıcı aylık ₺20 kazanıyor, üstüne rozet + analitik + öncelik geliyor.

**Önerilen PRO Paket Yapısı (Revize):**

| Plan | App Store Fiyatı | Aylık maliyet | Net Gelir (%30) | Net Gelir (%15 SBP) | İndirim |
|------|-----------------|--------------|----------------|--------------------|----|
| 1 Ay | **₺79,99** | ₺79,99 | ₺55,99 | ₺67,99 | — |
| 3 Ay | **₺214,99** | ₺71,66 | ₺150,49 | ₺182,74 | %10,4 |
| 6 Ay | **₺389,99** | ₺65,00 | ₺272,99 | ₺331,49 | %18,7 |
| 12 Ay | **₺679,99** | ₺56,67 | ₺475,99 | ₺577,99 | %29,2 |

> **Neden ₺79,99 değil ₺99,99:** teqlik eşdeğeri aylık ₺100,10 — ₺99,99 ile fiyatlamak "başabaş" demek, kullanıcı neden abone olsun ki? ₺79,99 net bir kazanım mesajı veriyor: "PRO al, aylık ₺20 artı tasarruf et." Türkiye'de Spotify ₺39,99, YouTube ₺49,99 — ₺79,99 bu anchors'ların biraz üstünde ama PRO bir iş aracı, eğlence değil.

> **Yıllık paket önerisi:** ₺679,99 = aylık ₺56,67 → ₺79,99'a göre %29 indirim. Standart endüstri pratiği yıllık için %25-30 indirim. Bu doğru aralıkta.

**PRO Üye Avantajları (Öneri):**

| Özellik | Standart | PRO |
|---------|---------|-----|
| Aktif ilan yenileme (aylık) | 1 ücretsiz | 5 ücretsiz |
| Blast / Kitle Bildirimi | Ücretli | 3/ay ücretsiz |
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
└── Hediye Sistemi (kullanıcılar arası)       ← V1.1/V2.0 — hukuki görüş al
```

---

## 9. Karar Özeti

| Konu | Karar |
|------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 teqlik** |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 teqlik** |
| Efektif teqlik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) |
| teqlik IAP ürün tipi | **Consumable** |
| PRO üyelik IAP ürün tipi | **Auto-Renewable Subscription** (V2.0) |
| Backend doğrulama | App Store Server API v2 JWS |
| Refund politikası V1.0 | Log kaydı, bakiye değişimi yok |
| Android | V1.0 kapsamı dışı |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi |
| Hediye sistemi | V1.1/V2.0 — planlı, hukuki görüş önerilir |
| Başlangıç Boost (İlan Ver'de) | V1.1 — yüksek öncelik |
| PRO anchor fiyatı | **₺79,99/ay** (₺99,99 değil — teqlik eşdeğeri ₺100, başabaş kabul edilemez) |
| PRO planlar | V2.0 — 1ay ₺79,99 / 3ay ₺214,99 / 6ay ₺389,99 / 12ay ₺679,99 |
