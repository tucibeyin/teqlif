# Yapay Zeka Fiyat Danışmanı — Özellik Dokümantasyonu ve Kaldırma Planı

## 1. Özellik Açıklaması

### Ne yapar?

Yapay Zeka Fiyat Danışmanı, kullanıcının ilan oluştururken veya düzenlerken fiyat alanının hemen altında görünen bir butondur. Butona tıklandığında, platformdaki benzer ürünlerin geçmiş satış verilerini analiz eden bir backend endpoint'i çağrılır ve aşağıdaki çıktılar kullanıcıya gösterilir:

- Önerilen başlangıç fiyatı (`suggested_start_price`)
- Beklenen kapanış fiyatı (`expected_close_price`)
- Güven seviyesi (`confidence`)
- Fiyat aralığı — minimum/maksimum
- Öneri metni (`advice`)

### Kullanım modeli

| Kullanıcı tipi | Kota | Ücret |
|---|---|---|
| Pro | 6 sorgu / ay (ücretsiz) | — |
| Standart | Sınırsız | 5 TL / sorgu (TUCi wallet) |

### Kredi takibi

Pro Hub'daki "Konsolide Krediler" kartında (`_CreditsSummaryCard`) AI fiyatlandırma için ayrı bir satır gösterilir. Kota her ay `renewal_date`'de backend tarafından sıfırlanır.

---

## 2. Dahil Olan Dosyalar

### Backend — dokunulmayacak

| Endpoint | Amaç |
|---|---|
| `GET /analytics/ai-price-credits` | Kullanıcının kalan kredisini döner |
| `POST /analytics/ai-pricing` | Fiyat tahmini üretir |

Backend endpoint'leri bu kaldırma işleminde değiştirilmez. Özellik yeniden açılmak istendiğinde hazır olacak.

### Mobile — Flutter

#### `mobile/lib/services/analytics_service.dart`

- **Satır 264-275:** `getAiPriceCredits()` — `GET /analytics/ai-price-credits` çağrısı yapar, `Map<String, dynamic>?` döner.
- Bu metot **silinmeyecek**; sadece çağrıldığı yerler devre dışı bırakılacak.

#### `mobile/lib/screens/create_listing_screen.dart`

- **Satır 190:** `_loadAiCredits()` çağrısı — `_loadProStatus()` içinde, kullanıcı pro ise tetiklenir. ← devre dışı bırakılacak
- **Satır 197-201:** `_loadAiCredits()` metot tanımı — `getAiPriceCredits()` çağırır, `_aiCreditsRemaining`'i set eder. ← fonksiyon kalacak, çağrısı kapatılacak
- **Satır 1504-1509:** `_AiPriceButton(...)` widget çağrısı — fiyat alanının altında render eder. ← gizlenecek
- **Satır 1518-1590:** `class _AiPriceButton extends ConsumerWidget` — widget sınıfı tanımı. ← **silinmeyecek**

#### `mobile/lib/screens/edit_listing_screen.dart`

- **Satır 123:** `_loadAiCredits()` çağrısı — `_loadProStatus()` içinde, kullanıcı pro ise tetiklenir. ← devre dışı bırakılacak
- **Satır 128-135:** `_loadAiCredits()` metot tanımı. ← fonksiyon kalacak, çağrısı kapatılacak
- **Satır 1038-1043:** `_AiPriceButton(...)` widget çağrısı. ← gizlenecek
- **Satır 1105+:** `class _AiPriceButton extends StatelessWidget` — widget sınıfı tanımı. ← **silinmeyecek**

#### `mobile/lib/screens/pro_hub_screen.dart`

- **Satır 65-73:** `_CreditsSummaryCard(aiCredits: state.aiCredits, ...)` çağrısı — `aiCredits` parametresi kaldırılacak.
- **Satır 687-704:** `class _CreditsSummaryCard` tanımı — `aiCredits` field ve constructor parametresi kaldırılacak.
- **Satır 761-769:** `CreditItemModel` (AI fiyatlandırma satırı) `items` listesinde — bu blok kaldırılacak:
  ```dart
  CreditItemModel(
    icon: Icons.psychology_outlined,
    iconColor: const Color(0xFFF59E0B),
    titleBuilder: (l) => loc.t('proCreditsAiName'),
    descBuilder: (l) => loc.t('proCreditsAiDesc'),
    data: aiCredits,
    defaultPremiumLimit: 6,
    defaultFreeLimit: 0,
  ),
  ```

#### `mobile/lib/screens/viewmodels/pro_hub_view_model.dart`

- **Satır 11:** `final Map<String, dynamic>? aiCredits;` — `ProHubState` field'ı kaldırılacak.
- **Satır 29-49:** `copyWith` içindeki `aiCredits` parametresi kaldırılacak.
- **Satır 96-112:** `loadCredits()` içindeki `Future.wait` listesinden `AnalyticsService.getAiPriceCredits()` (index 2) kaldırılacak; sonraki index'ler kaydırılacak:
  ```
  Önce:   results[2]=aiCredits, results[3]=aiDescCredits, results[4]=reactivationCredits
  Sonra:  results[2]=aiDescCredits, results[3]=reactivationCredits
  ```
- **Satır 107:** `aiCredits: results[2]` satırı kaldırılacak.

### Frontend — Web

#### `frontend/pro-plan.html`

- **Satır 760-779:** İki `<tr>` bloğu kaldırılacak:
  - `<tr class="feat-row" data-key="ai">` — "Yapay Zeka Fiyat Danışmanı" özellik satırı (başlık + fiyat + ~₺30/ay kart)
  - `<tr class="desc-row" data-key="ai">` — açıklama satırı
- **Satır 781:** `<!-- 3b -->` yorumu `<!-- 3 -->` olarak güncellenecek (numaralama tutarlılığı).
- Kaldırma sonrası tasarruf tablosu (`~₺30/ay`) değişkenliği kontrol edilecek — bu satır kendine ait olduğundan toplam hesaba dahil değil, güvenle kaldırılabilir.

---

## 3. Kaldırma Yaklaşımı

### İlke: Gizle, silme

Mobil tarafta widget sınıfları ve servis metotları **silinmeyecek**. Sadece çağrı noktaları devre dışı bırakılacak. Bu sayede özellik yeniden açılmak istendiğinde sadece çağrılar geri alınacak, yeni kod yazılmayacak.

### create_listing_screen.dart

1. `_loadProStatus()` içindeki `_loadAiCredits()` çağrısını (satır 190) kaldır — `_loadAiDescCredits()` çağrısı kalacak.
2. `_AiPriceButton(...)` widget çağrısını (satır 1504-1509) ve hemen öncesindeki `const SizedBox(height: 10)` ayracını kaldır.

### edit_listing_screen.dart

1. `_loadProStatus()` içindeki `if (isPro) _loadAiCredits();` çağrısını (satır 123) kaldır.
2. `_AiPriceButton(...)` widget çağrısını (satır 1038-1043) ve hemen öncesindeki `const SizedBox(height: 10)` ayracını kaldır.

### pro_hub_view_model.dart

1. `ProHubState` class'ından `aiCredits` field'ını kaldır.
2. `copyWith` metodundan `aiCredits` parametresini ve ilgili satırı kaldır.
3. `loadCredits()` içindeki `Future.wait` listesinden `AnalyticsService.getAiPriceCredits()` satırını kaldır.
4. `state = state.copyWith(...)` içinden `aiCredits: results[2]` satırını kaldır; sonraki index'leri `results[2]` ve `results[3]` olarak düzelt.

### pro_hub_screen.dart

1. `_CreditsSummaryCard` çağrısından (satır 65-73) `aiCredits: state.aiCredits,` parametresini kaldır.
2. `_CreditsSummaryCard` sınıf tanımından `aiCredits` field, constructor parametresi ve `CreditItemModel` bloğunu kaldır.

### frontend/pro-plan.html

1. `<!-- 3 -->` başlıklı iki `<tr>` bloğunu kaldır (satır 760-779: `feat-row` ve `desc-row`, `data-key="ai"`).
2. `<!-- 3b -->` yorumunu `<!-- 3 -->` olarak güncelle.

---

## 4. Yeniden Açma Rehberi

Özelliği yeniden etkinleştirmek için aşağıdaki adımları tersten uygula:

### create_listing_screen.dart

1. `_loadProStatus()` içinde `_loadAiCredits()` çağrısını geri ekle:
   ```dart
   if (isPro) {
     _loadAiCredits();       // ← ekle
     _loadAiDescCredits();
   }
   ```
2. Fiyat alanının altına `_AiPriceButton` widget'ını geri ekle:
   ```dart
   const SizedBox(height: 10),
   _AiPriceButton(
     loading: _aiLoading,
     isPro: _isPro,
     creditsRemaining: _aiCreditsRemaining,
     onTap: _fetchAiPriceEstimate,
   ),
   ```

### edit_listing_screen.dart

1. `_loadProStatus()` içinde `_loadAiCredits()` çağrısını geri ekle:
   ```dart
   if (isPro) _loadAiCredits();
   ```
2. Fiyat alanının altına `_AiPriceButton` widget'ını geri ekle (aynı yapı).

### pro_hub_view_model.dart

1. `ProHubState`'e `aiCredits` field'ını geri ekle:
   ```dart
   final Map<String, dynamic>? aiCredits;
   ```
2. `copyWith`'e `aiCredits` parametresini geri ekle.
3. `Future.wait` listesine `AnalyticsService.getAiPriceCredits()` satırını index 2'ye geri ekle; sonraki index'leri 3 ve 4 olarak güncelle.
4. `state.copyWith(...)` içine `aiCredits: results[2]` satırını geri ekle.

### pro_hub_screen.dart

1. `_CreditsSummaryCard` çağrısına `aiCredits: state.aiCredits,` parametresini geri ekle.
2. `_CreditsSummaryCard` sınıfına `aiCredits` field, constructor parametresi ve aşağıdaki `CreditItemModel` bloğunu geri ekle:
   ```dart
   CreditItemModel(
     icon: Icons.psychology_outlined,
     iconColor: const Color(0xFFF59E0B),
     titleBuilder: (l) => loc.t('proCreditsAiName'),
     descBuilder: (l) => loc.t('proCreditsAiDesc'),
     data: aiCredits,
     defaultPremiumLimit: 6,
     defaultFreeLimit: 0,
   ),
   ```

### frontend/pro-plan.html

1. `<!-- 2 -->` (Analytics satırı) ile `<!-- 3 -->` (AI Desc satırı) arasına aşağıdaki iki `<tr>` bloğunu geri ekle:
   ```html
   <!-- 3 -->
   <tr class="feat-row" data-key="ai">
       <td class="td-feat">
           <div class="feat-inner">
               <span><svg class="svg-icon"><use href="#ic-robot"></use></svg> Yapay Zeka Fiyat Danışmanı</span>
               <span class="feat-chevron">▾</span>
           </div>
       </td>
       <td class="td-std"><span class="v-dim">5 TL/kullanım</span></td>
       <td class="td-pro"><span class="v-ok"><svg class="svg-icon"><use href="#ic-bolt"></use></svg> 6 adet / ay</span></td>
       <td class="td-val">
           <div class="val-card">
               <div class="val-amount">~₺30/ay</div>
               <div class="val-desc">6 sorgu × 5 TL<br>= 30 TL tasarruf</div>
           </div>
       </td>
   </tr>
   <tr class="desc-row" data-key="ai">
       <td colspan="4"><div class="desc-inner">İlan oluştururken yapay zeka, platformdaki benzer ürünlerin geçmiş satışlarını analiz ederek size en rekabetçi fiyatı saniyeler içinde önerir. Pro kullanıcılar ayda 6 sorgu ücretsiz kullanabilir; standart kullanıcılar her sorgu için 5 TL öder.</div></td>
   </tr>
   ```
2. Mevcut `<!-- 3 -->` yorumunu `<!-- 3b -->` olarak güncelle (AI Desc satırı).

---

## 5. Kaldırma Gerekçesi

Bu özellik, mevcut ortamda her ilan oluşturma ve düzenleme ekranı açıldığında bir network çağrısı (`GET /analytics/ai-price-credits`) tetiklenmesine yol açmaktadır. Pro Hub açılışında da 5 paralel API çağrısından biri bu endpoint'e gitmektedir. Özellik kapatılarak bu gereksiz network yükü ortadan kaldırılmakta, backend endpoint'leri ise ileride yeniden açılmak üzere korunmaktadır.
