# TEQlik Wallet — V1.0 Bulgular & Karar Belgesi

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
| **TEQlik (planlanan)** | 1 TEQLik | **₺1,43** (%30) / **₺1,18** (%15) | — | %30 veya %15 (Apple) | İlan güçlendirme |

> **TikTok iOS vs Web:** App Store'da ₺0,88/coin, web'de ₺0,50/coin. Fark = Apple'ın %30'u + TikTok margin koruması. Bu, TEQlik ekranında "web'den al" ibaresi kullanılamayacağını doğruluyor (Kural 3.1.1 ihlali).
>
> **Instagram Stars:** Türkiye'de henüz aktif değil; yalnızca ABD ve seçili ülkelerde mevcut.
>
> **Twitter/X:** Harici ödeme işlemcisi (PayPal, Venmo); X %0 komisyon alıyor ancak iOS App Store üzerinden alım zorunlu olmadığından Apple da kesmiyor. Sanal para birimi yok.
>
> **Meta stratejisi:** Stars satışını kasıtlı olarak kendi web mağazasına taşıdı; Apple/Google %30'dan kaçınmak için. Teqlif'in bu opsiyonu yok — TEQlik dijital özellik kilidini açtığı için Apple Kural 3.1.1 kesinlikle geçerli.

### 1.2 Piyasa Okuma

- **TikTok Coin** iOS'ta ₺0,88/coin, web'de ₺0,50/coin — App Store ek maliyeti net görünüyor. Platform yayıncıya %50 aktarıyor. Amaç yaratıcı tipping, ilan güçlendirme değil.
- **Snapchat Tokens** Şubat 2025'te tamamen kapatıldı — sanal para stratejisi başarısız oldu.
- **Twitch Bits** en şeffaf model: kullanıcıya maliyet, yaratıcıya gelir açıkça yayımlıyor. %29 platform payı Apple ile neredeyse aynı.
- **YouTube/Meta:** %30 komisyon modeli — Google Play / Apple Pay üzerinden veya doğrudan web ödeme.
- **TEQlik farklı konumda:** Sosyal medyada sanal para = yaratıcıya hediye. TEQlik = kullanıcının **kendi ilanına yatırım**. Bu fiyat duyarlılığını azaltır — kullanıcı doğrudan ROI (daha fazla görüntülenme, satış) bekliyor.

---

## 2. Apple Komisyon Analizi & TEQlik Fiyatlandırması

### 2.1 Apple Komisyon Yapısı

| Program | Oran | Koşul |
|---------|------|-------|
| Standart | **%30** | Tüm geliştiriciler |
| Small Business Program | **%15** | Yıllık net gelir < $1M (komisyon sonrası) |

> **Small Business Program** Apple'ın 2021'de başlattığı program hâlâ aktif. Teqlif'in ilk yıl için bu programa girmesi kuvvetle muhtemel. Kayıt zorunlu — otomatik değil. Başvuru: App Store Connect → Agreements, Tax, and Banking.
>
> **Önemli:** Gelir $1M'ı aşarsa yıl ortasında bile %30'a geçer. İlk lansman için %15 ile başlayıp planlama buna göre yapılmalı.

### 2.2 Hedef Fiyat Mantığı

Hedef: **1 TEQLik = 1 TL net gelir** (Apple komisyonu kullanıcıya yansıtılıyor)

**%30 komisyon ile:**
```
Kullanıcı fiyatı = Net hedef / (1 - 0.30) = 1 TL / 0.70 = 1.4286 TL/TEQLik
```

**%15 komisyon ile (Small Business):**
```
Kullanıcı fiyatı = 1 TL / 0.85 = 1.176 TL/TEQLik
```

> **Öneri:** İlk lansman için %15 Small Business Program'a başvur, fiyatları buna göre belirle. Eğer programa girilemezse %30 hesabı geçerli.

### 2.3 Önerilen Paket Fiyatları

#### %30 Komisyon Senaryosu (Konservatif / Garantili)

| Paket | TEQlik | Bonus | Toplam | App Store Fiyatı | Net Gelir | Efektif TL/TEQLik |
|-------|--------|-------|--------|-----------------|-----------|-------------------|
| Başlangıç | 100 | — | 100 | **₺149,99** | ₺104,99 | ₺1,50 |
| Popüler 🔥 | 300 | +50 | 350 | **₺429,99** | ₺300,99 | ₺1,00 |
| Avantaj 💎 | 700 | +150 | 850 | **₺999,99** | ₺699,99 | ₺0,82 |
| Mega | 1500 | +400 | 1900 | **₺2.199,99** | ₺1.539,99 | ₺0,81 |

#### %15 Komisyon Senaryosu (Small Business — Önerilen)

| Paket | TEQlik | Bonus | Toplam | App Store Fiyatı | Net Gelir | Efektif TL/TEQLik |
|-------|--------|-------|--------|-----------------|-----------|-------------------|
| Başlangıç | 100 | — | 100 | **₺119,99** | ₺101,99 | ₺1,02 |
| Popüler 🔥 | 300 | +50 | 350 | **₺349,99** | ₺297,49 | ₺0,85 |
| Avantaj 💎 | 700 | +150 | 850 | **₺829,99** | ₺705,49 | ₺0,83 |
| Mega | 1500 | +400 | 1900 | **₺1.749,99** | ₺1.487,49 | ₺0,78 |

> **App Store Fiyat Tier'ları:** Apple'ın TRY tier listesi 2023 yeniden yapılandırması sonrası ~900 seçeneğe genişledi. ₺119,99 / ₺149,99 / ₺349,99 / ₺429,99 / ₺829,99 / ₺999,99 / ₺1.749,99 / ₺2.199,99 tier'larının App Store Connect → Pricing'den doğrulanması gerekiyor. Tam liste ancak App Store Connect'te görülüyor.

### 2.4 Birim Maliyet Rehberi (Kullanıcı Perspektifi)

**%30 / ₺149,99 → 100 TEQLik paketi bazında:**

| İşlem | Maliyet | ₺149,99 Paketi ile |
|-------|---------|-------------------|
| AI Açıklama (5 TEQLik) | ₺7,50 | 20 üretim |
| Blast / Kitle Bildirimi (10 TEQLik) | ₺15,00 | 10 gönderim |
| İlan Yenileme (10 TEQLik) | ₺15,00 | 10 yenileme |
| İlan Boost (50 TEQLik) | ₺75,00 | 2 boost |

---

## 3. Apple App Store Uyum Gereksinimleri

### 3.1 Zorunlu Kurallar (İhlali = Red)

**Kural 3.1.1 — Zorunlu IAP:**
- TEQlik dijital özellik kilidi açtığı için Apple IAP **zorunlu**
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
Satın alınan TEQlik'ler nakde çevrilemez veya devredilemez. 
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
│  • Bakiye: 140 TEQLik  [PRO rozeti]          │
│  • Bakiye yüklenince sayı yukarı sayar       │
├──────────────────────────────────────────────┤
│  [ TEQLik Yükle ] | [ İşlem Geçmişi ]       │
├──────────────────────────────────────────────┤
│  2 sütunlu paket grid (4 kart)               │
│  ┌──────────────┐  ┌──────────────┐         │
│  │  100 TEQLik  │  │ 🔥 EN POPÜLER│         │
│  │   ₺149,99    │  │  300 TEQLik  │         │
│  │              │  │   ₺429,99    │         │
│  │              │  │  (+50 Bonus) │         │
│  └──────────────┘  └──────────────┘         │
│  ┌──────────────┐  ┌──────────────┐         │
│  │💎 EN İYİ DEĞ.│  │ 1500 TEQLik  │         │
│  │  700 TEQLik  │  │   ₺2.199,99  │         │
│  │   ₺999,99    │  │ (+400 Bonus) │         │
│  │ (+150 Bonus) │  │              │         │
│  └──────────────┘  └──────────────┘         │
├──────────────────────────────────────────────┤
│  "TEQLik ile neler yapabilirsin?"            │
│  ⚡ 50 TEQLik = 1 İlan Boost                 │
│  📣 10 TEQLik = Kitle Bildirimi (Blast)      │
│  🤖 5 TEQLik  = AI Açıklama                  │
│  🔄 10 TEQLik = İlan Yenileme                │
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
      │                 TeqSnackBar: "300 TEQLik yüklendi!"
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

## 8. TEQLik Ekosistem Haritası & Genişleme Alanları

### 8.1 Mevcut TEQLik Kullanım Alanları

| Alan | Ekran | Maliyet | Durum |
|------|-------|---------|-------|
| AI Açıklama | İlan Ver (create_listing_screen) | 5 TEQLik | ✅ Aktif |
| İlan Yenileme | İlan Detay + Profil toggle | 10 TEQLik | ✅ Aktif |
| Blast / Kitle Bildirimi | İlan Detay | 10 TEQLik | ✅ Aktif |
| İlan Boost (Öne Çıkarma) | İlan Detay | 50 TEQLik | ✅ Aktif |

### 8.2 Hediye (Gift) Sistemi — Endüstri Analizi

**Konsept:** Kullanıcı A, kullanıcı B'ye TEQLik gönderir (örn. "Çok beğendim, boost yap" hediyesi).

**Endüstri pratikleri:**
- **OfferUp "Props":** Satıcıya beğeni/saygı gönderme — ancak parasal değer taşımıyor, sembolik
- **Etsy Gift Cards:** Harici hediye kartı sistemi; in-app transfer yok
- **Depop / Vinted:** Kullanıcılar arası para transferi yok; ödeme yalnızca satış üzerinden
- **Facebook Marketplace:** Kullanıcı arası transfer yok

**Risk analizi:**
- ✅ Sosyal etkileşimi artırır, elde tutma (retention) yükseltir
- ❌ Sahte hesap döngüsü riski: kullanıcı A kendi B hesabına gönderir, iade gibi kullanır
- ❌ Apple perspektifi: Kullanıcılar arası transferable virtual currency → App Review ek dikkat gerektirir
- ❌ Para transferi regülasyonu riski (BDDK, MASAK) — Türkiye'de sanal para transferi düzenleyici belirsizlik

**Karar önerisi — V1.0 dışında tut.** Hediye sistemi regülasyon riski ve sahte kullanım karmaşıklığı nedeniyle ilk versiyona eklenmemeli. V2.0 roadmap'e alınabilir, ancak hukuki değerlendirme şart.

### 8.3 İlan Ver Ekranında Ek TEQLik Noktaları

**Mevcut:** AI Açıklama (5 TEQLik) — create_listing_screen'de aktif.

**Endüstri pratiklerinden:**
- **Sahibinden.com:** İlan oluşturma sırasında "Öne Çıkar" seçeneği (kredi gerektirir)
- **OLX:** "Urgent" / "Top Ad" eklenebilir paketler, ilan oluştururken ödeme
- **Wallapop:** Oluşturma sırasında highlight opsiyonu

**Potansiyel ekleme — İlan Ver'de "Başlangıç Boost" seçeneği:**
```
İlanını Oluştur → Özet Ekranı
  ┌─────────────────────────────────────┐
  │  ✨ İlanını hemen öne çıkar         │
  │  50 TEQLik ile ilk 24 saat vitrin  │
  │  [Ekle]          [Geç]             │
  └─────────────────────────────────────┘
```
→ Dönüşüm oranı yüksek (kullanıcı motivasyonun en yüksek olduğu an)
→ V1.1 için öncelikli özellik

### 8.4 PRO Üyelik — Endüstri Analizi & Apple IAP Tipi

**Kritik fark — IAP Ürün Tipi:**

| Ürün Tipi | Kullanım | Apple Komisyonu |
|-----------|---------|----------------|
| Consumable | TEQLik paketleri | **%30 her zaman** (SBP: %15) |
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

**Önerilen PRO Paket Yapısı:**

| Plan | App Store Fiyatı | Net Gelir (%30) | Avantajlar |
|------|-----------------|----------------|-----------|
| 1 Ay | **₺99,99** | ₺69,99 | — |
| 3 Ay | **₺269,99** | ₺188,99 | %10 indirim |
| 6 Ay | **₺499,99** | ₺349,99 | %17 indirim |
| 12 Ay | **₺899,99** | ₺629,99 | %25 indirim |

**PRO Üye Avantajları (Öneri):**

| Özellik | Standart | PRO |
|---------|---------|-----|
| Aktif ilan yenileme (aylık) | 1 ücretsiz | 5 ücretsiz |
| Blast / Kitle Bildirimi | Ücretli | 3/ay ücretsiz |
| Profil rozeti | — | ✓ Doğrulanmış rozet |
| İlan sıralaması | Normal | Aynı kategoride +öncelik |
| İstatistik / Analytics | Temel | Detaylı (görüntülenme, tıklama) |
| Müşteri desteği | Standart | Öncelikli |

> **App Store Connect'te iki ayrı ürün grubu gerekiyor:** Consumable grubu (TEQLik paketleri) + Auto-Renewable Subscription grubu (PRO planlar). Her grup ayrı Apple onayından geçiyor.

### 8.5 Tüm Gelir Akışı Haritası (V1.0 + V2.0)

```
TEQLif Gelir Akışı
├── Consumable IAP (TEQLik paketleri)
│    ├── 100 TEQLik — ₺149,99
│    ├── 300 TEQLik +50 bonus — ₺429,99  
│    ├── 700 TEQLik +150 bonus — ₺999,99
│    └── 1500 TEQLik +400 bonus — ₺2.199,99
│
├── Auto-Renewable Subscription (PRO)         ← V2.0
│    ├── 1 Ay — ₺99,99
│    ├── 3 Ay — ₺269,99
│    ├── 6 Ay — ₺499,99
│    └── 12 Ay — ₺899,99
│
├── TEQLik Harcama Noktaları
│    ├── AI Açıklama (5 TEQLik) — create_listing_screen ✅
│    ├── İlan Yenileme (10 TEQLik) ✅
│    ├── Blast / Kitle Bildirimi (10 TEQLik) ✅
│    ├── İlan Boost (50 TEQLik) ✅
│    └── Başlangıç Boost (ilan oluşturulurken, 50 TEQLik) ← V1.1
│
└── Hediye Sistemi (kullanıcılar arası)       ← V3.0 (hukuki değerlendirme şart)
```

---

## 9. Karar Özeti

| Konu | Karar |
|------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 TEQLik** |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 TEQLik** |
| Efektif TEQLik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) |
| TEQLik IAP ürün tipi | **Consumable** |
| PRO üyelik IAP ürün tipi | **Auto-Renewable Subscription** (V2.0) |
| Backend doğrulama | App Store Server API v2 JWS |
| Refund politikası V1.0 | Log kaydı, bakiye değişimi yok |
| Android | V1.0 kapsamı dışı |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi |
| Hediye sistemi | V3.0 — hukuki değerlendirme şart |
| Başlangıç Boost (İlan Ver'de) | V1.1 — yüksek öncelik |
| PRO planlar | V2.0 — aylık ₺99,99 / 3 ay ₺269,99 / 6 ay ₺499,99 / 12 ay ₺899,99 |
