# TEQlik Wallet — V1.0 Bulgular & Karar Belgesi

**Tarih:** 2026-10-23  
**Kapsam:** iOS IAP entegrasyonu, fiyatlandırma stratejisi, UX mimarisi, Apple uyum gereksinimleri  
**Durum:** Araştırma tamamlandı — implementasyon bekliyor

---

## 1. Rakip Platform Fiyat Analizi

### 1.1 Platform Karşılaştırma Tablosu

| Platform | Birim | Kullanıcı Öder | Oluşturucu Alır | Platform Payı | Kullanım Amacı |
|----------|-------|---------------|----------------|--------------|----------------|
| **TikTok Coin** | 1 Coin | **₺0,50** (TR, 2024–25 aktif) | ~₺0,25 (Diamond) | ~%50 | Yayıncıya hediye gönderme |
| **Twitch Bits** | 1 Bit | $0,014 (~₺0,45) | $0,01 (~₺0,32) | ~%29 | Yayıncıya destek |
| **YouTube Super Chat/Thanks** | Sabit tier | $2–$500 (TRY eşdeğeri) | Gelirin %70'i | %30 | Video/yayın anında destek |
| **Instagram Stars** | 1 Star | ~$0,020 | $0,01 | ~%50 | İçerik üretici desteği |
| **Snapchat Tokens** | — | — | — | — | **10 Şubat 2025'te kapatıldı** |
| **TEQlik (planlanan)** | 1 TEQlik | **₺1,43** (%30) / **₺1,18** (%15) | ₺1,00 (net) | %30 veya %15 (Apple) | İlan güçlendirme, AI, Blast |

> **Not — TikTok Coins:** ₺0,50/coin sabit birim fiyat; ancak TikTok yayıncıya yalnızca %50 aktarıyor (Diamond sistemi). TEQlik'ten 3× daha ucuz görünse de kullanım amacı farklı — yayıncı tipping, ilan güçlendirme değil.
>
> **Not — Instagram Stars:** Türkiye'de henüz aktif değil; yalnızca ABD ve seçili ülkelerde.
>
> **Not — Facebook Stars:** Meta 2021'de Stars satışını kendi web mağazasına taşıdı; Apple/Google %30'dan kaçınmak için. Bu, TEQlik'ten farklı iş modeli — burada kullanıcı kendi ilanına yatırım yapıyor.

### 1.2 Piyasa Okuma

- **TikTok Coin** ₺0,50/coin — platform yayıncıya %50 aktarıyor, %50'sini kendisi alıyor. Amaç yaratıcı tipping, ilan yönetimi değil.
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

## 8. Karar Özeti

| Konu | Karar |
|------|-------|
| Apple komisyon senaryosu | Small Business (%15) için başvur; fallback %30 |
| Başlangıç paketi fiyatı (%30) | **₺149,99 → 100 TEQLik** |
| Başlangıç paketi fiyatı (%15) | **₺119,99 → 100 TEQLik** |
| Efektif TEQLik/TL oranı | ₺1,43 (%30) veya ₺1,18 (%15) |
| IAP ürün tipi | Consumable |
| Backend doğrulama | App Store Server API v2 JWS |
| Refund politikası V1.0 | Log kaydı, bakiye değişimi yok |
| Android | V1.0 kapsamı dışı |
| Tab yapısı | Tab 1: Mağaza, Tab 2: İşlem Geçmişi |
