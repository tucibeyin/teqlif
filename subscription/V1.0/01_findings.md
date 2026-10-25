# teqlif PRO Abonelik — V1.0 Kararlar & Bulgular

> Tarih: Ekim 2026 | Platform: iOS (öncelikli) + Android | Durum: Karar verildi, implement edilmedi

---

## 1. PRO STRATEJİSİ

### Temel Karar

teqlif'te alıcı–satıcı profil ayrımı yoktur. Herkes yayın açabilir, teklif verebilir, hediye gönderebilir. PRO, belirli bir kullanıcı tipini değil **ticaret niyetini** kilitleyen bir katmandır.

PRO ile gelen tek fark: canlı yayın içindeki **Açık Artırma** ve **Direkt Satış** bileşenleri.

### Ne PRO gerektirir

| Özellik | Ücretsiz | PRO |
|---------|----------|-----|
| Canlı yayın açma | ✓ | ✓ |
| Chat, hediye, beğeni | ✓ | ✓ |
| Yayın izleme | ✓ | ✓ |
| İlan pazaryeri | ✓ | ✓ |
| Teklif verme (alıcı) | ✓ | ✓ |
| **Açık Artırma başlatma** | — | ✓ |
| **Direkt Satış başlatma** | — | ✓ |

> teqlif para transferi yapmaz. Platform; açık artırma sürecini, teklifleri, satış fiyatını ve kazananı kayıt altına alıp UI'da gösterir. Ödeme taraflar arasında gerçekleşir.

---

## 2. PRO FİYATLANDIRMASI

### Abonelik Planları (güncel App Store fiyatları)

| Plan | Brüt Fiyat | Aylık Eşdeğer | İndirim | Net (×0,5542) | Net/ay |
|------|-----------|---------------|---------|---------------|--------|
| 1m | ₺149,99 | ₺149,99 | — | ₺83,12 | ₺83,12 |
| 3m | ₺399,99 | ₺133,33 | -%11 | ₺221,67 | ₺73,89 |
| 6m | ₺699,99 | ₺116,67 | -%22 | ₺387,91 | ₺64,65 |
| 12m | ₺1.299,99 | ₺108,33 | -%28 | ₺720,41 | ₺60,03 |

**Ağırlıklı ortalama net/abone/ay** (dağılım %40/%30/%20/%10): **₺74,35**

### Komisyon Yapısı

- KDV: %18 → Platform komisyonu: %30 → **Net proceeds: %55,42**

---

## 3. UX AKIŞI — CANLIYAYIN'DA PRO KAPISI

### Prensip

Butonlar herkese gösterilir. Gate, taplama anında devreye girer. Bu yaklaşım:
- Özellik varlığını tüm kullanıcılara gösterir
- Tap = niyet sinyali → dönüşüm için en güçlü an
- Canva / Spotify / LinkedIn ile aynı endüstri standardı

### Akış

```
Host "Yayın Aç" → Canlı Yayın Ekranı
│
├── Commerce Widget — PRO kullanıcı
│     [Açık Artırma Başlat]  [Direkt Satış Ekle]
│     → Doğrudan kullanır
│
└── Commerce Widget — Non-PRO kullanıcı
      [Açık Artırma Başlat]  [Direkt Satış Ekle]  ← görünür, tıklanabilir
             ↓ tıklar
      PRO Modal (bottom sheet)
             ↓ reddederse
      Yayın devam eder (modal kapanır, butonlar yerinde kalır)
```

### PRO Modal İçeriği

```
┌──────────────────────────────────────────┐
│  Canlı yayında sat                       │
│  Alıcılar anında teklif versin           │
│  Tüm süreç kayıt altında                 │
│                                          │
│  ✦ 1 ay ücretsiz — kredi kartı gerekmez  │
│  ✦ İstersen 3 ay boyunca %50 indirimli   │
│                                          │
│  [Ücretsiz Başla]      [Şimdi Değil]     │
└──────────────────────────────────────────┘
```

### Modal Yorgunluğu — 3 Tap Kuralı

| Tap sayısı | Gösterim |
|-----------|---------|
| 1–2 | Tam modal |
| 3+ | Minimal nudge: "PRO dene →" chip |

Tap sayısı local storage + backend'de tutulur.

---

## 4. YAYIM SONU ANALİZ EKRANI — UPSELL

Non-PRO kullanıcı yayını bitirdiğinde analiz ekranında kişiselleştirilmiş PRO daveti gösterilir.

**Örnek mesaj:**

> "Bu yayında 63 kişi izledi, 12 hediye aldın.  
> Açık Artırma veya Direkt Satış açsaydın alıcılar anlık teklif verebilirdi.  
> [PRO'yu 1 ay ücretsiz dene]"

Kullanıcının kendi verisiyle somutlaştırılmış davet → en yüksek conversion anı.

---

## 5. iOS'TA İNDİRİMLİ ABONELİK SATIŞI — TEKNİK GEREKSİNİMLER

### 5.1 Apple'ın Teklif Tipleri

#### A. Introductory Offer (Giriş Teklifi)
- Her Apple ID, her subscription group için **yalnızca bir kez** kullanabilir
- Yeni abone edinimi için: free trial + arkasından indirimli dönem zincirlenir
- App Store Connect'te tanımlanır, kod gerekmez

**Önerilen zincir:**
```
1 ay ücretsiz → 2 ay ₺74,99 (-%50) → sonrasında normal fiyat
```
App Store Connect'te "Free Trial (1 month)" + "Pay As You Go (2 months at ₺74,99)" olarak ayarlanır.

#### B. Promotional Offer (Tanıtım Teklifi)
- Mevcut veya eski abone için (introductory'yi zaten kullanmış kişi)
- Server-side imza (signature) gerektirir — backend üretir
- Yenileme öncesi, churn sonrası win-back veya özel kampanya için kullanılır
- StoreKit 2 (iOS 15+) ile yönetilir

#### C. Offer Codes (Teklif Kodları)
- Tek kullanımlık kodlar, kampanya veya influencer dağıtımı için
- App Store Connect'ten üretilir, kullanıcıya doğrudan verilir

### 5.2 App Store Connect Kurulum Adımları

```
1. Subscription Group oluştur
   → Adı: "teqlif PRO"

2. Subscription Products ekle
   → com.teqlif.pro.1m   (₺149,99 — 1 ay)
   → com.teqlif.pro.3m   (₺399,99 — 3 ay)
   → com.teqlif.pro.6m   (₺699,99 — 6 ay)
   → com.teqlif.pro.12m  (₺1.299,99 — 12 ay)

3. Introductory Offer tanımla (1m planına bağla)
   → Tip: Free Trial → 1 Month
   → Ardından: Pay As You Go → 2 months → ₺74,99/ay

4. Promotional Offer tanımla (win-back için)
   → Reference Name: "winback_50"
   → 1 Month → ₺74,99

5. Server Notification URL ayarla (App Store Server Notifications v2)
   → https://api.teqlif.com/webhooks/apple
   → Events: SUBSCRIBED, DID_RENEW, DID_FAIL_TO_RENEW, EXPIRED, REFUND
```

### 5.3 Flutter Tarafı

**Önerilen kütüphane: RevenueCat** (`purchases_flutter`)

RevenueCat, StoreKit 2 karmaşıklığını, receipt validation'ı, entitlement yönetimini ve webhook'ları soyutlar. Doğrudan StoreKit 2 kullanmak mümkün ama RevenueCat bu işi çok daha hızlı ve güvenli yapar.

```dart
// Kurulum
await Purchases.configure(PurchasesConfiguration(apiKey));

// Mevcut entitlement kontrolü
CustomerInfo info = await Purchases.getCustomerInfo();
bool isPro = info.entitlements.active.containsKey('pro');

// Introductory offer ile satın alma (1m plan)
Offerings offerings = await Purchases.getOfferings();
Package? monthly = offerings.current?.monthly;
if (monthly != null) {
  await Purchases.purchasePackage(monthly);
}

// Promotional offer (win-back) — backend imzası gerekir
PromotionalOffer promoOffer = await Purchases.getPromotionalOffer(
  product,
  discount,
);
await Purchases.purchaseDiscountedPackage(package, promoOffer);
```

### 5.4 Backend Gereksinimleri

```
1. Apple Server Notifications webhook endpoint
   POST /webhooks/apple
   → Subscription eventlerini PostgreSQL'e kaydet
   → PRO durumunu Redis'te cache'le (TTL: 1 saat)

2. Promotional Offer imzası üretme endpoint
   GET /api/v1/subscription/promo-offer-signature
   → Apple'ın beklediği ECDSA imzasını üretir
   → Private key: secrets.env'de saklanır, repoya girmez

3. Entitlement kontrolü
   → Her API isteğinde JWT'den user_id al
   → Redis'ten PRO durumunu kontrol et
   → Miss durumunda Apple Receipt Validation veya RevenueCat API ile doğrula
```

### 5.5 Sandbox Test Ortamı

- Xcode → Sandbox Apple ID ile test
- Introductory offer yalnızca gerçek Apple ID'de çalışır (sandbox'ta da ayrı hesap gerekir)
- RevenueCat dashboard'da test purchase'ları canlı görülür

---

## 6. ÖZET — KARAR TABLOSU

| Konu | Karar |
|------|-------|
| PRO kapısı | Açık Artırma + Direkt Satış |
| Buton görünürlüğü | Herkese gösterilir, tap'ta modal |
| Trial süresi | 1 ay ücretsiz (iOS introductory offer) |
| İndirimli geçiş | 2 ay ₺74,99 (pay-as-you-go, introductory zinciri) |
| Modal yorgunluğu | 3+ tap → minimal nudge |
| Yayın sonu upsell | Kişiselleştirilmiş analiz + PRO daveti |
| iOS kütüphane | RevenueCat (purchases_flutter) |
| Backend offer tipi | Introductory (yeni) + Promotional (win-back) |
| Para transferi | Platform dışı — teqlif sadece süreci kaydeder |
