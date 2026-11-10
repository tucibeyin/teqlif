# teqlif Platformu — Apple In-App Purchase (IAP), Subscriptions (PRO) & Wallet Tutarlılık Mimarisi Raporu (V1.0)

**Tarih:** 10 Kasım 2026  
**Kapsam:**
- **Client Katmanı (Flutter / StoreKit 2):** `mobile/lib/services/iap_service.dart`, `mobile/lib/services/wallet_service.dart`, `mobile/lib/widgets/pro_subscription_sheet.dart`, `mobile/lib/screens/profile_screen.dart`, `mobile/lib/screens/viewmodels/pro_hub_view_model.dart`
- **Backend Doğrulama & İş Mantığı (FastAPI):** `backend/app/routers/wallet.py`, `backend/app/use_cases/wallet/commands/verify_purchase_command.py`, `backend/app/services/store/apple_verifier.py`, `backend/app/services/store/apple_server_api.py`, `backend/app/services/store/notifications/apple_handler.py`, `backend/app/use_cases/wallet/commands/handle_store_refund_command.py`, `backend/app/use_cases/wallet/commands/reconcile_subscription_command.py`
- **Asenkron Görev Kuyruğu & Dağıtık Katman:** `backend/app/tasks/wallet_tasks.py`, ARQ Worker (`process_store_notification_task`), Redis Cluster (Velocity limits, Distributed mutex, Idempotency keys)
- **Veritabanı & Finansal Defter (PostgreSQL 17):** `users`, `teqlik_transactions`, `wallet_ledger`, `refund_log`, `withdrawal_requests`, Alembic migration `zzzzzx_wallet_v10.py` & `zzzzzx_wallet_v10b.py`  
**Amaç:** teqlif ekosisteminde Apple üzerinden gerçekleştirilen tüketilebilir (consumable) teqlik alımları, otomatik yenilenen PRO abonelikleri, webhook (App Store Server Notifications V2) yaşam döngüsü, iade (refund/revoke) operasyonları ve cüzdan bakiye güncellemelerini; **Clean Code**, **Clean Architecture (Hexagonal Ports & Adapters)**, **MVVM**, **ADR §8 (MVVM Kuralı)**, **ADR §12 (Wallet & Cüzdan Bütünlüğü)**, **Apple App Store Review Guidelines (§3.1.1 / §3.1.2)**, **RFC 7515 (JSON Web Signature - JWS)**, **OWASP Mobile Top 10** ve **Finansal ACID Defter (Double-Entry Bookkeeping)** standartları doğrultusunda uçtan uca analiz ederek; fon kayıplarını, yarış koşullarını (race condition), çift harcama (double-spending) açıklarını ve veri tutarsızlıklarını somut çözüm reçeteleriyle belgelemek.

---

## 🏗️ 1. Katman Bazlı Mimari ve Endüstriyel Değerlendirme

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              1. CLIENT KATMANI (Flutter iOS)                           │
│  - Presentation: ProfileScreen (_WalletTab, _TeqlikPacksSheet), ProSubscriptionSheet    │
│  - Services: IAPService (in_app_purchase / StoreKit 2), WalletService                  │
│  - Local Storage & Cache: Hive Encrypted Box (api_cache: 'user_wallet_data'), Prefs    │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │ HTTP POST /wallet/purchase/verify
                                            │ (JWS signedTransactionInfo Payload)
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              2. APPLE STOREKIT INFRASTRUCTURE                          │
│  - StoreKit 2 Payment Queue & Transaction Receipt Signing (ES256 + x5c Chain)          │
│  - App Store Server Notifications V2 (S2S Push: SUBSCRIBED, DID_RENEW, REFUND, REVOKE)  │
│  - App Store Server API V1/V2 (S2S Pull Reconciliation: /inApps/v1/subscriptions/{id}) │
└─────────────┬───────────────────────────────────────────────────────────┬──────────────┘
              │ Webhook Push (POST /store-notifications/apple)            │ S2S Pull Sync
              ▼                                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              3. BACKEND KATMANI (FastAPI)                              │
│  - Routers: /api/wallet (verify, sync, summary, store-notifications)                   │
│  - Cryptographic Verification: AppleVerifier (x5c Root CA G3, Leeway, Claims Check)    │
│  - Use Cases / Commands: VerifyPurchaseCommand, ReconcileSubscriptionCommand           │
│  - Background Workers: ARQ (process_store_notification_task, HandleStoreRefundCommand) │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │
                     ┌──────────────────────┴──────────────────────┐
                     ▼                                             ▼
┌──────────────────────────────────────────┐  ┌──────────────────────────────────────────┐
│        4. DAĞITIK DURUM & REDIS          │  │     5. VERİTABANI & FİNANSAL DEFTER      │
│  - Velocity Limit: rate:iap:{device_id}   │  │  - PostgreSQL 17: ACID Transactions      │
│  - Session Invalidation: session:user:*  │  │  - users (teqlik_balance, pro_expires_at)│
│  - Lock/Mutex: lock:iap:verify:{tx_id}   │  │  - teqlik_transactions (uq_store_tx idx) │
│  - Idempotency: notif:uuid:{notif_id}    │  │  - wallet_ledger (Double-entry audit)    │
│  - S2S Rate Guard: sub_sync:{user_id}    │  │  - refund_log (Apple iade kayıtları)     │
└──────────────────────────────────────────┘  └──────────────────────────────────────────┘
```

### 1.1 Katman 1: Mobil İstemci (Flutter StoreKit 2 & MVVM)
* **StoreKit 2 Yaşam Döngüsü ve İşlem Kapatma (Transaction Finalization):**
  - *Kritik İhlal (P0 Fon Kaybı):* `mobile/lib/services/iap_service.dart` içinde `_onPurchaseUpdates` dinleyicisi, Apple StoreKit kuyruğundan gelen satın almayı henüz sunucuya göndermeden veya doğrulama sonucunu beklemeden **satır 100-102'de `_iap.completePurchase(purchase)` çağırmaktadır**.
  - *Mekanizma:* `completePurchase` StoreKit'e `finishTransaction` sinyali gönderir ve işlemi ödeme kuyruğundan kalıcı olarak siler. Eğer ardından gelen `_verifyWithBackend` çağrısı ağ kesintisi, sunucu 502/504 hatası veya uygulama çökmesi nedeniyle başarısız olursa, işlem Apple tarafında tamamlanmış ancak Teqlif sunucusunda teqlik veya PRO aboneliği **asla hesaba geçmemiş** olur. Kullanıcı parasını ödediği halde hakkını alamaz ve işlem yerel kuyruktan silindiği için bir daha otomatik tetiklenemez.
* **MVVM ve Katman İzolasyonu (ADR §8):**
  - *İhlal:* `ProSubscriptionSheet` (`pro_subscription_sheet.dart:64`) ve `ProfileScreen` (`profile_screen.dart:4065`), herhangi bir ViewModel (`ProHubViewModel`, `WalletViewModel`) aracılığı olmadan doğrudan `IAPService()` singleton'ına bağlanmakta, `purchaseStream` dinlemekte ve UI üzerinde setState ile durum yönetmektedir.
  - *İhlal:* `WalletService` doğrudan ham `http.get` / `http.post` çağrıları yapmakta; merkezi `ApiClient` (token refresh, interceptor, retry, rate limit) mimarisini baypas etmektedir.
* **Önbellek Tutarsızlığı (Local Cache Desynchronization):**
  - Satın alma sunucuda başarıyla doğrulandığında (`resp.statusCode == 200`), mobil tarafta `WalletService.invalidateBalance()` veya `eventBus.fire(CreditsChangedEvent())` çağrılmamaktadır. Profil ekranı dışında (örneğin canlı yayın hediye modalı veya ilan öne çıkarma ekranında) yapılan alımlarda, yerel Hive kutusundaki `user_wallet_data` önbelleği 2 dakika boyunca bayat kalır.

---

### 1.2 Katman 2: Backend Doğrulama ve Kriptografi (FastAPI & Apple Verifier)
* **Kriptografik x5c Sertifika Zinciri Zafiyeti (P0 Kriptografik Açık):**
  - `backend/app/services/store/apple_verifier.py` dosyasındaki `_verify_x5c_chain()` metodu, JWS başlığındaki `x5c` dizisinden Root CA'yı alıp fingerprint kontrolü (`_APPLE_ROOT_CA_FINGERPRINT`) yapmaktadır; ancak **yaprak (leaf) sertifikanın ara sertifika (G3 CA) tarafından, ara sertifikanın da Root CA tarafından imzalandığını (Issuer Signature Validation) doğrulamamaktadır**.
  - *İstismar:* Kötü niyetli bir kullanıcı, kendi ürettiği sahte CA ve yaprak sertifika ile imzaladığı bir JWS fişinin `x5c` dizisinin 3. elemanına Apple'ın genel erişime açık gerçek Root CA sertifikasını ekleyerek backend'e yollayabilir. Kod, dizideki Root sertifikanın fingerprint'ini doğru bulacak ve saldırganın sahte yaprak anahtarıyla JWT imzasını geçerli sayacaktır. Bu durum, sisteme tek kuruş ödemeden sınırsız teqlik ve yıllık PRO aboneliği basılmasına olanak tanır.
* **Eşzamanlı Doğrulama Yarış Koşulu (Race Condition & Unhandled 500):**
  - `VerifyPurchaseCommand.execute()` içinde mükerrer işlem kontrolü, non-locking `SELECT id FROM teqlik_transactions ... LIMIT 1` ile yapılmaktadır. Aynı fiş için eşzamanlı gelen iki istek (örneğin agresif mobil retry veya paralel HTTP istekleri), `SELECT` adımını aynı anda geçmekte ve ikinci işlem veritabanındaki `uq_store_tx` partial unique index'e çarparak yakalanmamış (unhandled) bir SQLAlchemy `IntegrityError` fırlatmaktadır. Bu durum istemciye 409 Conflict yerine HTTP 500 Internal Server Error dönmesine neden olur.

---

### 1.3 Katman 3: Apple Entegrasyonu (ASSN V2 Webhook & S2S Pull Sync)
* **ASSN V2 Webhook İdempotensi Eksikliği:**
  - `backend/app/services/store/notifications/apple_handler.py` ve `wallet_tasks.py`, Apple tarafından gönderilen bildirimlerdeki benzersiz `notificationUUID` değerini Redis veya DB'de kaydetmemekte ve kontrol etmemektedir. Apple'ın ağ gecikmelerinde veya 5xx yanıtlarında gönderdiği mükerrer bildirimler (retries), aynı abonelik yenilemesini veya durum geçişini mükerrer şekilde işleme sokar.
* **Abonelik İadelerinde (Refund) Hakların Geri Alınamaması:**
  - `backend/app/use_cases/wallet/commands/handle_store_refund_command.py` içinde `_parse_refund` sonrası orijinal işlem aranırken sabit olarak `AND transaction_type = 'iap_purchase'` filtresi çalıştırılmaktadır. Oysa abonelik işlemleri veritabanına `pro_subscription_monthly`, `pro_subscription_annual` gibi tiplerle kaydedilmektedir.
  - Apple müşteri hizmetleri üzerinden PRO aboneliğini iade eden bir kullanıcının `REFUND` bildirimi geldiğinde, sistem işlemi bulamaz (`tx is None`), sessizce çıkar ve kullanıcının `pro_expires_at` süresini iptal etmez. Kullanıcı parasını geri aldığı halde PRO haklarını süresi bitene kadar ücretsiz kullanmaya devam eder.

---

### 1.4 Katman 4: Dağıtık Durum, Redis ve Eşzamanlılık
* **Cihaz ID Manipülasyonu ve Hız Limiti (Velocity Limit) Baypası:**
  - `backend/app/use_cases/wallet/commands/verify_purchase_command.py` içindeki günlük ₺5.000 limit kontrolü sadece `rate:iap:{device_id}` anahtarına bağlanmıştır.
  - Mobil tarafta `_getOrCreateDeviceId()` metodu, `SharedPreferences` içinde rastgele 32 karakterlik bir hex dizgi üretmektedir. Uygulama verisini temizleyen, uygulamayı silip yükleyen veya doğrudan API'ye sahte `device_id` gönderen bir saldırgan bu limiti tamamen baypas edebilmektedir. Hız limitinin kullanıcı ID (`rate:iap:user:{user_id}`) ile birleştirilmemesi ciddi bir dolandırıcılık (fraud) açığıdır.
* **Kilitlenmeyen Dağıtık İşlem (Distributed Mutex Yokluğu):**
  - Satın alma doğrulama akışında Redis üzerinde `store_transaction_id` bazlı bir dağıtık kilit (`Redlock` / `SET NX EX`) bulunmamaktadır.

---

### 1.5 Katman 5: Veritabanı Mimarisi ve Finansal Çift Girişli Defter (Ledger)
* **Atomik Olmayan Bakiye ve Defter (Ledger) Senkronizasyonu:**
  - `VerifyPurchaseCommand._handle_consumable()` içinde önce `UPDATE users SET teqlik_balance = teqlik_balance + :amt`, ardından ayrı bir `SELECT teqlik_balance FROM users` çalıştırılmakta ve elde edilen değer `wallet_ledger.balance_after` kolonuna yazılmaktadır.
  - Eşzamanlı bir başka cüzdan hareketi (örneğin bir hediye gönderimi veya açık artırma teklifi) bu iki sorgunun arasına girdiğinde, defterdeki `balance_after` kullanıcının gerçek bakiye geçmişiyle uyuşmaz ve finansal denetim (audit) izi bozulur. Doğrusu `UPDATE ... RETURNING teqlik_balance` sonucunu doğrudan deftere yazmaktır.
* **ORM Modeli ile Alembic Şeması Arasında Senkronizasyon Eksikliği:**
  - `backend/alembic/versions/zzzzzx_wallet_v10b.py` dosyasında `users.pending_refund` kolonu eklenmiş olmasına rağmen, `backend/app/models/user.py` dosyasındaki SQLAlchemy `User` modelinde `pending_refund` alanı tanımlanmamıştır. Bu durum ORM seviyesinde bu alana erişildiğinde `AttributeError` patlamasına yol açar.

---

## 📌 2. Uçtan Uca Önceliklendirme ve Özet Tablosu

| ID | Seviye | Katman | Bileşen / Dosya | Zaaf / Hata Türü | Etki Alanı | Durum |
| :---: | :---: | :---: | :--- | :--- | :--- | :---: |
| **IAP-01** | 🔴 **P0** | **Client** | `iap_service.dart` (L100-102) | Sunucu Doğrulaması Öncesi Erken `completePurchase()` Çağrısı | Ağ hatasında fon kaybı, teqlik/PRO teslim edilmemesi, App Store 3.1.1 reddi | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-02** | 🔴 **P0** | **Backend** | `apple_verifier.py` (L37-62) | x5c Sertifika Zincirinde İmza Doğrulaması (Issuer Verify) Eksikliği | Sahte Apple JWS fişleri ile ücretsiz sınırsız teqlik ve PRO üretimi | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-03** | 🔴 **P0** | **Backend** | `verify_purchase_command.py` (L102-117) | Replay Kontrolünde Kilitsiz SELECT & Yakalanmayan `IntegrityError` | Eşzamanlı isteklerde HTTP 500 çökmesi, mükerrer bakiye riski | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-04** | 🟠 **P1** | **Backend** | `verify_purchase_command.py` (L157-198) | Atomik Olmayan Bakiye Güncellemesi & Ayrık `SELECT teqlik_balance` | Yarış durumlarında `wallet_ledger.balance_after` tutarsızlığı | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-05** | 🟠 **P1** | **Backend** | `apple_handler.py` & `wallet_tasks.py` | ASSN V2 Webhook Bildirimlerinde `notificationUUID` İdempotensi Yokluğu | Ağ tekrarlarında mükerrer abonelik işleme, worker kuyruk tıkanması | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-06** | 🟠 **P1** | **Backend** | `handle_store_refund_command.py` (L40-58) | Abonelik İadelerinde Sabit `transaction_type = 'iap_purchase'` Araması | Apple'dan iade alan PRO abonelerin haklarının iptal edilememesi (Haksız Kazanç) | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-07** | 🟠 **P1** | **Cross** | `iap_service.dart` & `verify_purchase_command.py` | İstemci Kontrolündeki `device_id` ile Velocity Limit Baypası | Günlük ₺5.000 limitin aşılması, çalıntı kart / fraud istismarı | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-08** | 🟡 **P2** | **DB/ORM** | `user.py` vs `zzzzzx_wallet_v10b.py` | SQLAlchemy `User` Modelinde `pending_refund` Kolonunun Tanımlanmamış Olması | ORM erişiminde `AttributeError`, admin panelinde negatif bakiye filtreleme hatası | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-09** | 🟡 **P2** | **Cross** | `iap_service.dart` & `wallet.py` | Satın Alma Sonrası Mobil Hive Önbelleğinin İptal Edilmemesi & WS Push Eksikliği | Satın alma sonrası cüzdanın 2 dakika boyunca eski bakiyeyi göstermesi | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-10** | 🟡 **P2** | **Client** | `pro_subscription_sheet.dart` & `profile_screen.dart` | View Katmanında Doğrudan `IAPService` Erişimi & Ham HTTP Çağrıları (ADR §8) | MVVM ihlali, test edilemezlik, token refresh mekanizmasının çiğnenmesi | ✅ `cd9c30d8` · 2026-11-10 |
| **IAP-11** | 🟢 **P3** | **Backend** | `reconcile_subscription_command.py` (L98) | Subscription Reconciliation Sırasında Naive UTC / Tzinfo Uyuşmazlığı | `replace(tzinfo=timezone.utc)` kaynaklı potansiyel datetime TypeError | ✅ `ee4e050e` · 2026-11-10 |
| **IAP-12** | 🟢 **P3** | **Backend** | `verify_purchase_command.py` (L71-76) | DB İşlemi Rollback Olduğunda Redis Velocity Sayacının Geri Alınamaması | Başarısız işlemlerde kullanıcının günlük satın alma kotasının haksız yanması | ✅ `ee4e050e` · 2026-11-10 |

---

## 🔍 3. Detaylı Bulgular ve Somut Çözüm Reçeteleri

---

### IAP-01 · 🔴 P0 (Kritik) · Sunucu Doğrulaması Öncesi Erken `completePurchase()` Çağrısı (Fon Kaybı & Unfulfilled Purchase)

* **Katman:** Client (Mobil Flutter / iOS StoreKit)
* **Etkilenen Dosya:** `mobile/lib/services/iap_service.dart` (Satır 98–116)
* **İlgili Standart:** Apple App Store Review Guidelines (§3.1.1 In-App Purchase), StoreKit 2 Best Practices ("Finishing a Transaction")

#### Kök Neden ve Problem Analizi
`IAPService._onPurchaseUpdates` metodu incelendiğinde:
```dart
// mobile/lib/services/iap_service.dart:98-115
Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
  for (final purchase in purchases) {
    if (purchase.pendingCompletePurchase) {
      _iap.completePurchase(purchase); // ❌ ERKEN ÇAĞRI: Fiș backend'e gitmeden StoreKit kuyruğundan siliniyor!
    }
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      final ok = await _verifyWithBackend(purchase);
      if (ok) {
        _purchaseController.add(purchase);
      } else {
        _purchaseController.addError(Exception('IAP_BACKEND_FAILED'));
      }
    } ...
  }
}
```
StoreKit mimarisinde `completePurchase()`, işletim sistemine `"Bu ürün kullanıcıya teslim edildi, işlemi ödeme kuyruğundan kalıcı olarak kaldır"` talimatını verir. Kod satır 101'de bu işlemi henüz backend'e sormadan çağırmaktadır.
Eğer kullanıcı satın alma butonuna bastıktan sonra:
1. Telefon tünelden geçer veya Wi-Fi koparsa,
2. Sunucu 502/504 Bad Gateway verirse,
3. Telefonun şarjı bitip kapanırsa veya uygulama crash olursa,

İşlem StoreKit kuyruğundan silinmiş olur; ancak backend `/wallet/purchase/verify` çağrısını almadığı için veritabanında teqlik bakiyesi eklenmez. Tüketilebilir (consumable) paketler Apple tarafından "Restore Purchases" ile geri getirilemediğinden, kullanıcının parası Apple tarafından tahsil edilmiş fakat ürün teqlif tarafından teslim edilmemiş olur. Bu durum doğrudan App Store hesap incelemesine ve uygulama reddine yol açar.

#### Çözüm Reçetesi
`completePurchase(purchase)` çağrısı, **yalnızca ve yalnızca** `_verifyWithBackend(purchase)` fonksiyonu `true` döndükten sonra veya sunucu HTTP 409 (Replay / zaten işlendi) teyidi verdiğinde çalıştırılmalıdır:

```dart
// mobile/lib/services/iap_service.dart
Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
  for (final purchase in purchases) {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // 1. Önce sunucu tarafında doğrula ve bakiyeyi/aboneliği hesaba geç
      final ok = await _verifyWithBackend(purchase);
      if (ok) {
        // 2. YALNIZCA sunucu teslimatı onayladıysa StoreKit kuyruğunu temizle
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        // 3. Yerel cüzdan önbelleğini anında düşür ve event fırlat
        await WalletService.invalidateBalance();
        _purchaseController.add(purchase);
      } else {
        // Sunucuya ulaşılamadıysa completePurchase ÇAĞRILMAZ!
        // İşlem StoreKit kuyruğunda bekler; uygulama bir sonraki açılışında otomatik tekrar dener.
        debugPrint('[IAP] Backend doğrulaması başarısız, işlem kuyrukta tutuluyor: ${purchase.purchaseID}');
        _purchaseController.addError(Exception('IAP_BACKEND_FAILED'));
      }
    } else if (purchase.status == PurchaseStatus.error) {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      debugPrint('[IAP] purchase error: ${purchase.error}');
      _purchaseController.add(purchase);
    }
  }
}
```

---

### IAP-02 · 🔴 P0 (Kritik) · x5c Sertifika Zincirinde İmza Doğrulaması Eksikliği (Forged JWS Receipt Bypass)

* **Katman:** Backend (FastAPI / Store Verifier)
* **Etkilenen Dosya:** `backend/app/services/store/apple_verifier.py` (Satır 37–62)
* **İlgili Standart:** RFC 7515 (JSON Web Signature - x5c Verification), RFC 5280 (PKI Certificate Path Validation)

#### Kök Neden ve Problem Analizi
`_verify_x5c_chain` fonksiyonu şu şekilde yazılmıştır:
```python
# backend/app/services/store/apple_verifier.py:37-62
def _verify_x5c_chain(jws_string: str) -> object:
    header = jwt.get_unverified_header(jws_string)
    x5c = header.get("x5c", [])
    if len(x5c) < 3:
        raise ValueError("x5c zinciri eksik (leaf + G3 CA + Root CA gerekli)")

    certs = [load_der_x509_certificate(b64decode(c)) for c in x5c]
    leaf_cert, g3_ca, root_ca = certs[0], certs[1], certs[2]

    # 1. Root CA fingerprint kontrolü (MITM koruması)
    actual = root_ca.fingerprint(hashes.SHA256()).hex()
    if actual != _APPLE_ROOT_CA_FINGERPRINT:
        raise ValueError(f"Apple Root CA fingerprint eşleşmiyor: {actual}")

    # 2. Sertifika süresi kontrolü
    now = datetime.now(timezone.utc)
    for cert in [leaf_cert, g3_ca]:
        if cert.not_valid_after_utc < now:
            raise ValueError(f"Sertifika süresi dolmuş: {cert.subject}")

    # 3. Zincir imzası: leaf → G3 CA → Root CA
    #    cryptography kütüphanesi CRL/OCSP yapmaz; tam PKI chain verify W1.1+
    #    Şu an: fingerprint + süre + JWT imzası yeterli güvenlik sağlar.
    return leaf_cert.public_key()
```
Yorum satırında `"fingerprint + süre + JWT imzası yeterli güvenlik sağlar"` yazılması **temel bir kriptografik yanılgıdır**.
X.509 standartlarında bir sertifika zincirinin güvenilirliği, her alt sertifikanın üst otorite tarafından kriptografik olarak imzalanmış olmasına (`issuer signature verification`) dayanır.
Mevcut kodda:
1. `root_ca`'nın parmak izi kontrol edilmektedir (Apple Root CA G3 parmak iziyle eşleşir).
2. Ancak `g3_ca` sertifikasını `root_ca`'nın imzalayıp imzalamadığı kontrol **edilmemektedir**.
3. `leaf_cert` sertifikasını `g3_ca`'nın imzalayıp imzalamadığı kontrol **edilmemektedir**.

> [!CAUTION]
> **Saldırı Senaryosu (Zero-Cost Unlimited Coins & PRO Exploit):**
> Saldırgan kendi bilgisayarında OpenSSL ile bir Sahte CA (`Fake CA`) ve bu CA ile imzalanmış bir Sahte Yaprak Sertifika (`Fake Leaf`) üretir.
> Ardından Apple'ın web sitesinden herkese açık `Apple Root CA - G3` sertifikasını indirir.
> JWS header'ına `x5c: [Fake Leaf, Fake CA, Real Apple Root CA]` koyar.
> Payload kısmına `{"productId": "teqlik_pack_1000", "transactionId": "fake_9999", "environment": "Production", ...}` yazar ve kendi Fake Leaf private key'i ile ES256 imzalar.
> Backend `root_ca.fingerprint`'e bakar: gerçek Apple Root olduğu için onaylar.
> Ardından `leaf_cert.public_key()` döner ve JWT imzası saldırganın kendi yaprak anahtarıyla doğrulandığı için `jwt.decode` BAŞARILI olur!
> Saldırgan 1 TL bile ödemeden veritabanına 1.200 teqlik veya 1 yıllık PRO aboneliği ekletir!

#### Çözüm Reçetesi
`cryptography.hazmat.primitives.asymmetric` kullanılarak sertifika zinciri imzaları hiyerarşik olarak doğrulanmalıdır:

```python
# backend/app/services/store/apple_verifier.py
from cryptography.hazmat.primitives.asymmetric import ec, padding

def _verify_x5c_chain(jws_string: str) -> object:
    header = jwt.get_unverified_header(jws_string)
    x5c = header.get("x5c", [])
    if len(x5c) < 3:
        raise ValueError("x5c zinciri eksik (leaf + G3 CA + Root CA gerekli)")

    certs = [load_der_x509_certificate(b64decode(c)) for c in x5c]
    leaf_cert, intermediate_ca, root_ca = certs[0], certs[1], certs[2]

    # 1. Root CA fingerprint kontrolü (Apple Root CA G3)
    actual_root_fp = root_ca.fingerprint(hashes.SHA256()).hex()
    if actual_root_fp != _APPLE_ROOT_CA_FINGERPRINT:
        raise ValueError(f"Apple Root CA fingerprint eşleşmiyor: {actual_root_fp}")

    # 2. Sertifika geçerlilik süreleri kontrolü
    now = datetime.now(timezone.utc)
    for cert in certs:
        if cert.not_valid_after_utc < now or cert.not_valid_before_utc > now:
            raise ValueError(f"Sertifika geçerlilik süresi dışında: {cert.subject}")

    # 3. Kriptografik İmza Zinciri Doğrulaması (PKI Path Validation)
    try:
        # Intermediate CA, Root CA tarafından imzalanmış mı?
        root_public_key = root_ca.public_key()
        root_public_key.verify(
            intermediate_ca.signature,
            intermediate_ca.tbs_certificate_bytes,
            ec.ECDSA(intermediate_ca.signature_hash_algorithm)
            if isinstance(root_public_key, ec.EllipticCurvePublicKey)
            else padding.PKCS1v15(),
            intermediate_ca.signature_hash_algorithm,
        )

        # Leaf Cert, Intermediate CA tarafından imzalanmış mı?
        inter_public_key = intermediate_ca.public_key()
        inter_public_key.verify(
            leaf_cert.signature,
            leaf_cert.tbs_certificate_bytes,
            ec.ECDSA(leaf_cert.signature_hash_algorithm)
            if isinstance(inter_public_key, ec.EllipticCurvePublicKey)
            else padding.PKCS1v15(),
            leaf_cert.signature_hash_algorithm,
        )
    except Exception as exc:
        raise ValueError(f"x5c sertifika imza zinciri doğrulanamadı: {exc}") from exc

    return leaf_cert.public_key()
```

---

### IAP-03 · 🔴 P0 (Kritik) · Replay Kontrolünde Kilitsiz SELECT & Yakalanmayan `IntegrityError`

* **Katman:** Backend & DB
* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/verify_purchase_command.py` (Satır 102–117, 157–179)
* **İlgili Standart:** ACID İzolasyonu (Read Committed Race Condition), REST Idempotency Standartları

#### Kök Neden ve Problem Analizi
`VerifyPurchaseCommand.execute()` içindeki mükerrer işlem (replay) engelleme kodu:
```python
# backend/app/use_cases/wallet/commands/verify_purchase_command.py:102-117
existing = await self._session.execute(
    text(
        "SELECT id FROM teqlik_transactions "
        "WHERE store_platform = :platform "
        "AND store_transaction_id = :tx_id "
        "LIMIT 1"
    ),
    {"platform": platform, "tx_id": result.transaction_id},
)
if existing.fetchone() is not None:
    raise ConflictException(code="IAP_ALREADY_PROCESSED")
```
Bu desende **Time-of-Check to Time-of-Use (TOCTOU)** yarış koşulu bulunmaktadır:
1. İstemci aynı fiş için neredeyse eşzamanlı iki istek gönderir (İstek A ve İstek B).
2. İstek A ve İstek B aynı anda `SELECT id FROM teqlik_transactions` çalıştırır; her ikisi de `None` döner.
3. İstek A `UPDATE users SET teqlik_balance = teqlik_balance + 100` yapar ve `INSERT INTO teqlik_transactions` çalıştırır.
4. İstek B `users` satır kilidini bekler; İstek A commit edildiğinde İstek B de bakiyeyi bir kez daha artırmaya çalışır veya `INSERT INTO teqlik_transactions` adımına geçer.
5. Veritabanındaki `uq_store_tx` unique indeksi devreye girer ve İstek B için `asyncpg.exceptions.UniqueViolationError` patlatır.
6. `VerifyPurchaseCommand` bu `IntegrityError`'ı yakalamadığı için FastAPI en dışta yakalayıp istemciye **HTTP 500 Internal Server Error** döner.

İstemci HTTP 500 aldığında `iap_service.dart:150` devreye girip 2 saniye sonra tekrar dener. Bu durum gereksiz hata loglarına, mobil tarafta satın alma takılmalarına ve eşzamanlılık penceresinde bakiye yarışlarına sebep olur.

#### Çözüm Reçetesi
İşlem iki aşamalı korunmalıdır:
1. **Redis Dağıtık Mutex:** `lock:iap:verify:{platform}:{tx_id}` ile eşzamanlı istekler en dışta serileştirilmelidir.
2. **DB `IntegrityError` Yakalama:** DB seviyesindeki olası çakışmalar yakalanarak zarif bir `ConflictException(code="IAP_ALREADY_PROCESSED")` (HTTP 409) yanıtına dönüştürülmelidir.

```python
# backend/app/use_cases/wallet/commands/verify_purchase_command.py
from sqlalchemy.exc import IntegrityError

# 1. Redis Mutex ile eşzamanlı girişleri engelle
lock_key = f"lock:iap:verify:{platform}:{result.transaction_id}"
is_locked = await redis.set(lock_key, "1", nx=True, ex=30)
if not is_locked:
    raise ConflictException(code="IAP_CONCURRENT_VERIFICATION")

try:
    # 2. Var olan kayıt kontrolü
    existing = await self._session.execute(...)
    if existing.fetchone() is not None:
        raise ConflictException(code="IAP_ALREADY_PROCESSED")

    # 3. İlgili kayıt işlemleri...
    ...
except IntegrityError as exc:
    if "uq_store_tx" in str(exc):
        logger.warning("[VerifyPurchase] Mükerrer tx_id DB indeksine takıldı: %s", result.transaction_id)
        raise ConflictException(code="IAP_ALREADY_PROCESSED")
    raise
finally:
    await redis.delete(lock_key)
```

---

### IAP-04 · 🟠 P1 (Yüksek) · Atomik Olmayan Bakiye Güncellemesi & Ayrık `SELECT teqlik_balance`

* **Katman:** DB Architecture & Finansal Defter
* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/verify_purchase_command.py` (Satır 157–198)
* **İlgili Standart:** ADR §12 (Wallet Atomic Update), Double-Entry Bookkeeping İlkeleri

#### Kök Neden ve Problem Analizi
`_handle_consumable` içerisindeki bakiye ve defter yazım akışı:
```python
# backend/app/use_cases/wallet/commands/verify_purchase_command.py:157-198
# 1. Bakiye artırılıyor
await self._session.execute(
    text("UPDATE users SET teqlik_balance = teqlik_balance + :amt WHERE id = :uid"),
    {"amt": teqlik_amount, "uid": user_id},
)

# 2. Transaction tablosuna yazılıyor
tx_row = await self._session.execute(
    text("INSERT INTO teqlik_transactions ... RETURNING id"), ...
)
tx_id_db = tx_row.fetchone()[0]

# 3. ❌ AYRIK SELECT: Bakiye tekrar okunuyor
balance_row = await self._session.execute(
    text("SELECT teqlik_balance FROM users WHERE id = :uid"),
    {"uid": user_id},
)
balance_after = balance_row.fetchone()[0]

# 4. Deftere yazılıyor
await self._session.execute(
    text("INSERT INTO wallet_ledger (..., balance_after, ...) VALUES (..., :bal, ...)"),
    {"bal": balance_after, ...},
)
```
Adım 1 ile Adım 3 birbirinden bağımsızdır. `UPDATE` sırasında oluşan yeni bakiye doğrudan yakalanmamakta, sonradan ayrı bir `SELECT` ile çekilmektedir.
PostgreSQL `Read Committed` izolasyon seviyesinde, bu transaction commit edilmeden hemen önce araya giren başka bir işlem (örneğin arka planda tamamlanan bir airdrop veya eşzamanlı harcama) `users` satırını etkilerse veya okuma kirli olursa, `wallet_ledger` tablosuna yazılan `balance_after` değeri ile transaction'ın yarattığı gerçek matematiksel bakiye desekronize olur. ADR §12'de açıkça belirtildiği üzere bakiye güncellemeleri her zaman `RETURNING` ile tek hamlede alınmalıdır.

#### Çözüm Reçetesi
Bakiye güncellemesi `RETURNING teqlik_balance` ile tek SQL ifadesinde atomik olarak alınmalı ve deftere bu değer geçirilmelidir:

```python
# Doğru ve Atomik Uygulama:
bal_row = await self._session.execute(
    text(
        "UPDATE users SET teqlik_balance = teqlik_balance + :amt "
        "WHERE id = :uid "
        "RETURNING teqlik_balance"
    ),
    {"amt": teqlik_amount, "uid": user_id},
)
balance_after = bal_row.fetchone()[0]

# tx_row insert...
# wallet_ledger insert(:bal -> balance_after)
```

---

### IAP-05 · 🟠 P1 (Yüksek) · ASSN V2 Webhook Bildirimlerinde `notificationUUID` İdempotensi Yokluğu

* **Katman:** Backend (Apple Notifications & ARQ Tasks)
* **Etkilenen Dosya:** `backend/app/services/store/notifications/apple_handler.py` (Satır 27–106), `backend/app/tasks/wallet_tasks.py`
* **İlgili Standart:** Apple App Store Server Notifications V2 Specification (Deduplication)

#### Kök Neden ve Problem Analizi
Apple ASSN V2 spesifikasyonuna göre:
> *"Each notification has a unique notificationUUID. Your server might receive the same notification multiple times due to retries. Use notificationUUID to ensure idempotent processing."*

Mevcut sistemde `AppleNotificationHandler.handle()` metodu `claims = verify_signed_payload_jws(signed_payload)` yaptıktan sonra doğrudan iş mantığına geçmektedir. `claims.get("notificationUUID")` değeri ne Redis'te ne de veritabanında saklanmaktadır.
Apple bir HTTP timeout aldığında veya sunucu yeniden başlatıldığında aynı bildirimi dakikalar/saatler içinde tekrar gönderir. `DID_RENEW`, `SUBSCRIBED` veya `REVOKE` bildirimleri her seferinde tekrar çalıştırılarak gereksiz DB yükü oluşturur ve yarış durumlarını tetikler.

#### Çözüm Reçetesi
Redis üzerinde `notif:uuid:{notification_uuid}` anahtarı 72 saatlik TTL ile atomik `SET NX` işletilmeli, bildirim daha önce görüldüyse derhal atlanmalıdır:

```python
# backend/app/services/store/notifications/apple_handler.py
async def handle(self, signed_payload: str) -> None:
    claims = verify_signed_payload_jws(signed_payload)
    notif_uuid = claims.get("notificationUUID")

    if notif_uuid:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        # 72 saatlik idempotency kilidi
        acquired = await redis.set(f"notif:apple:uuid:{notif_uuid}", "1", nx=True, ex=259200)
        if not acquired:
            logger.info("[AppleNotif] Mükerrer bildirim atlandı | uuid=%s", notif_uuid)
            return

    # Normal işleme devam...
```

---

### IAP-06 · 🟠 P1 (Yüksek) · Abonelik İadelerinde Sabit `transaction_type = 'iap_purchase'` Araması

* **Katman:** Backend (Refund & Revocation)
* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/handle_store_refund_command.py` (Satır 40–58)
* **İlgili Standart:** Apple App Store Server Notifications (REFUND Event for Auto-Renewable Subscriptions)

#### Kök Neden ve Problem Analizi
`HandleStoreRefundCommand.execute` metodunda orijinal işlemi bulmak için çalıştırılan sorgu:
```python
# backend/app/use_cases/wallet/commands/handle_store_refund_command.py:40-49
tx_row = await self._session.execute(
    text(
        "SELECT id, user_id, amount, product_type "
        "FROM teqlik_transactions "
        "WHERE store_platform = :plat "
        "AND store_transaction_id = :tid "
        "AND transaction_type = 'iap_purchase' "  # ❌ HATA: Yalnızca consumable paketleri arıyor!
        "LIMIT 1"
    ),
    {"plat": platform, "tid": transaction_id},
)
```
Oysa `VerifyPurchaseCommand._handle_subscription()` içinde abonelikler şu şekilde kaydedilmektedir:
`transaction_type: f"pro_subscription_{plan_type}"` (ör. `pro_subscription_monthly`).
Bir kullanıcı Apple üzerinden PRO aboneliğini iade ettiğinde (`notificationType: REFUND`):
1. `HandleStoreRefundCommand` tetiklenir.
2. `WHERE transaction_type = 'iap_purchase'` filtresi abonelik kaydıyla eşleşmez.
3. `tx is None` olur ve fonksiyon `logger.warning("[Refund] Bilinmeyen transaction")` basarak sessizce çıkar.
4. Kullanıcının `user_type = 'standard'` yapılmaz, `pro_expires_at` sıfırlanmaz. Kullanıcı parasını Apple'dan geri almasına rağmen sistemde PRO olmaya devam eder.

#### Çözüm Reçetesi
Sorgu `product_type`'ı da kapsayacak şekilde genişletilmeli; işlem bir abonelik ise kullanıcının PRO statüsü derhal iptal edilmelidir:

```python
# backend/app/use_cases/wallet/commands/handle_store_refund_command.py
tx_row = await self._session.execute(
    text(
        "SELECT id, user_id, amount, product_type, transaction_type "
        "FROM teqlik_transactions "
        "WHERE store_platform = :plat "
        "AND store_transaction_id = :tid "
        "LIMIT 1"
    ),
    {"plat": platform, "tid": transaction_id},
)
tx = tx_row.fetchone()
if tx is None:
    logger.warning("[Refund] Bilinmeyen transaction | platform=%s tid=%s", platform, transaction_id)
    return

_tx_id, user_id, original_teqlik, product_type, tx_type = tx

# Eğer iade edilen ürün bir PRO abonelik ise PRO yetkilerini derhal düşür
if product_type == "subscription" or tx_type.startswith("pro_subscription"):
    await self._session.execute(
        text(
            "UPDATE users SET "
            "user_type = 'standard', "
            "plan_type = NULL, "
            "pro_expires_at = NULL, "
            "pro_grace_until = NULL "
            "WHERE id = :uid"
        ),
        {"uid": user_id},
    )
    logger.info("[Refund] Abonelik iadesi işlendi, kullanıcı standart plana düşürüldü | user_id=%s", user_id)
```

---

### IAP-07 · 🟠 P1 (Yüksek) · İstemci Kontrolündeki `device_id` ile Velocity Limit Baypası

* **Katman:** Cross (Mobil & Backend Güvenlik)
* **Etkilenen Dosya:** `mobile/lib/services/iap_service.dart` (Satır 14–27), `backend/app/use_cases/wallet/commands/verify_purchase_command.py` (Satır 121–136)
* **İlgili Standart:** OWASP Mobile M9 (Insecure Data Storage), Finansal Fraud Önleme Standartları

#### Kök Neden ve Problem Analizi
Hız limiti doğrulaması backend'de şu şekilde çalışmaktadır:
```python
# backend/app/use_cases/wallet/commands/verify_purchase_command.py:70-71
if device_id:
    key = f"rate:iap:{device_id}"
    ...
```
Mobil istemcide `device_id` üretimi:
```dart
// mobile/lib/services/iap_service.dart:18-23
final rng = Random.secure();
id = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
await prefs.setString(_kDeviceIdKey, id);
```
1. `device_id` donanımsal bir kimlik (IDFV veya Keychain destekli UUID) değil, basit bir `SharedPreferences` string'idir.
2. Kullanıcı uygulamayı silip yüklediğinde veya uygulama verilerini sildiğinde yeni bir `device_id` atanır.
3. Kötü niyetli biri doğrudan HTTP API'ye her istekte farklı bir `device_id` parametresi yollayarak ₺5.000'lik limiti sonsuz kez delebilir.
4. En önemlisi: Hız limiti **kullanıcı ID (`user_id`)** bazında tutulmamaktadır! Aynı kullanıcı tek bir hesapla sınırsız hacimde harcama yapabilir.

#### Çözüm Reçetesi
Hız limiti hem `device_id` hem de `user_id` bazında çift katmanlı kontrol edilmeli; fail-closed mantık her ikisine de uygulanmalıdır:

```python
# backend/app/use_cases/wallet/commands/verify_purchase_command.py
# 1. Kullanıcı bazlı hız limiti (₺5.000 / 24 saat)
user_velocity_key = f"rate:iap:user:{user_id}"
await _check_velocity(redis, user_velocity_key, effective_try_amount)

# 2. Cihaz bazlı hız limiti (₺5.000 / 24 saat)
if device_id:
    device_velocity_key = f"rate:iap:device:{device_id}"
    await _check_velocity(redis, device_velocity_key, effective_try_amount)
```

Mobil tarafta ise `device_id`, uygulama silinse bile silinmeyen iOS Keychain / Android KeyStore (`flutter_secure_storage`) üzerinde saklanmalıdır.

---

### IAP-08 · 🟡 P2 (Orta) · SQLAlchemy `User` Modelinde `pending_refund` Kolonunun Tanımlanmamış Olması

* **Katman:** DB Architecture & ORM
* **Etkilenen Dosya:** `backend/app/models/user.py` (Satır 30–75) vs `backend/alembic/versions/zzzzzx_wallet_v10b.py` (Satır 18–24)
* **İlgili Standart:** SQLAlchemy 2.0 Declarative Mapping Bütünlüğü

#### Kök Neden ve Problem Analizi
Alembic migration dosyasında (`zzzzzx_wallet_v10b.py`):
```python
op.execute(sa.text("ALTER TABLE users ADD COLUMN IF NOT EXISTS pending_refund BOOLEAN NOT NULL DEFAULT false"))
```
Veritabanı tablosuna `pending_refund` kolonu başarıyla eklenmiştir ve `handle_store_refund_command.py` ham SQL ile `UPDATE users SET pending_refund = true` yapmaktadır.
Fakat `backend/app/models/user.py` dosyası incelendiğinde `User` modelinde bu kolon tanımlanmamıştır.
Sonuç olarak:
- FastAPI içinde `current_user.pending_refund` okumak istendiğinde kod `AttributeError: 'User' object has no attribute 'pending_refund'` hatası verir.
- Pydantic şemalarında veya admin sorgularında ORM üzerinden negatif bakiyeli ve inceleme bekleyen kullanıcılar listelenemez.

#### Çözüm Reçetesi
`backend/app/models/user.py` içerisine eksik alan eklenmelidir:

```python
# backend/app/models/user.py
class User(Base):
    ...
    pending_refund: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )
```

---

### IAP-09 · 🟡 P2 (Orta) · Satın Alma Sonrası Mobil Hive Önbelleğinin İptal Edilmemesi & WS Push Eksikliği

* **Katman:** Cross (Client Önbellek & Realtime WS)
* **Etkilenen Dosya:** `mobile/lib/services/iap_service.dart`, `mobile/lib/services/wallet_service.dart`, `backend/app/routers/wallet.py`
* **İlgili Standart:** ADR §9 (Cache Invalidation & Freshness), CACHE-23 Standardı

#### Kök Neden ve Problem Analizi
1. `backend/app/routers/wallet.py:verify_purchase` başarılı olduğunda `await invalidate_user_session_cache(current_user.id)` çağrılmakta, ancak kullanıcıya WebSocket üzerinden bir `CACHE_INVALIDATE` olayı gönderilmemektedir.
2. Mobil tarafta `iap_service.dart` içinde satın alma doğrulandığında `WalletService.invalidateBalance()` çağrılmamaktadır.
3. Kullanıcı profildeki cüzdan sekmesi yerine bir canlı yayındayken veya ilan boost ekranındayken teqlik paketi satın aldığında, `user_wallet_data` Hive önbelleği silinmez. Kullanıcı satın alma yapmasına rağmen arayüzde eski bakiye görünmeye devam eder; bu da kullanıcının işlemin gerçekleşmediğini sanıp tekrar satın alma butonuna basmasına yol açar.

#### Çözüm Reçetesi
1. `IAPService._verifyWithBackend` sonrasında `WalletService.invalidateBalance()` ve `eventBus.fire(CreditsChangedEvent())` tetiklenmelidir.
2. Backend'de satın alma işlemi tamamlandığında WebSocket üzerinden kullanıcıya anlık bildirim atılmalıdır:

```python
# backend/app/routers/wallet.py
await db.commit()
await invalidate_user_session_cache(current_user.id)

# CACHE-23 standardına uygun WebSocket Invalidation
await publish_chat(
    f"notif:{current_user.id}",
    {
        "type": "cache_invalidate",
        "scope": "wallet",
        "user_id": current_user.id,
    },
)
```

---

### IAP-10 · 🟡 P2 (Orta) · View Katmanında Doğrudan `IAPService` Erişimi & Ham HTTP Çağrıları

* **Katman:** Client (Architecture & Clean Code)
* **Etkilenen Dosya:** `mobile/lib/screens/profile_screen.dart`, `mobile/lib/widgets/pro_subscription_sheet.dart`, `mobile/lib/services/wallet_service.dart`
* **İlgili Standart:** ADR §8 (MVVM & Repository Layer Pattern)

#### Kök Neden ve Problem Analizi
ADR §8 açıkça şunu belirtir:
> *"View sınıfları veri katmanını ve doğrudan HTTP servislerini bilemez. Tüm durumlar ViewModel üzerinden yönetilmeli, tüm API çağrıları Repository üzerinden geçmelidir."*

- `profile_screen.dart` (~8000 satır) içerisinde `_WalletTab` doğrudan `final _iap = IAPService()` oluşturmakta, stream dinlemekte ve doğrudan `WalletService.getBalance()` çağırmaktadır.
- `pro_subscription_sheet.dart` yine doğrudan `_iap` nesnesiyle konuşmaktadır.
- `WalletService` doğrudan Dart'ın ham `package:http/http.dart` kütüphanesini kullanmakta; bu durum 401 durumunda token yenileme (token refresh), 429 durumunda exponential backoff ve timeout yönetimini devre dışı bırakmaktadır.

#### Çözüm Reçetesi
1. `WalletRepository` oluşturularak `WalletService` işlevleri buraya taşınmalı ve `ApiClient.call()` üzerinden çalışmalıdır.
2. `WalletViewModel` ve `ProSubscriptionViewModel` oluşturulup IAP durumları (`purchaseStream`, `products`, `isPurchasing`) Riverpod StateNotifier üzerinden UI'a sunulmalıdır.

---

### IAP-11 · 🟢 P3 (Düşük) · Subscription Reconciliation Sırasında Naive UTC / Tzinfo Uyuşmazlığı

* **Katman:** Backend
* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/reconcile_subscription_command.py` (Satır 98)
* **İlgili Standart:** Python Datetime Timezone Awareness Best Practices

#### Kök Neden ve Problem Analizi
`ReconcileSubscriptionCommand` içindeki karşılaştırma:
```python
expires_changed = (
    apple_status.expires_at is not None
    and pro_expires_at is not None
    and abs((apple_status.expires_at - pro_expires_at.replace(tzinfo=timezone.utc)).total_seconds()) > 60
)
```
Eğer veritabanı sürücüsü (asyncpg) `pro_expires_at` alanını zaten timezone-aware (`tzinfo=datetime.timezone.utc`) olarak dönerse, `.replace(tzinfo=timezone.utc)` çağrısı gereksizdir ve timezone kaymalarında yanlış sonuç verebilir. Eğer naive dönerse doğrudan çıkarma işlemi Python'da `TypeError: can't subtract offset-naive and offset-aware datetimes` fırlatır.

#### Çözüm Reçetesi
Tarih nesnesi güvenli normalize edilmelidir:
```python
def _to_utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)

db_exp = _to_utc(pro_expires_at)
apple_exp = _to_utc(apple_status.expires_at)
if db_exp and apple_exp:
    expires_changed = abs((apple_exp - db_exp).total_seconds()) > 60
```

---

### IAP-12 · 🟢 P3 (Düşük) · DB İşlemi Rollback Olduğunda Redis Velocity Sayacının Geri Alınamaması

* **Katman:** Backend (Redis & ACID Sınırları)
* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/verify_purchase_command.py` (Satır 71–76), `backend/app/routers/wallet.py`

#### Kök Neden ve Problem Analizi
`verify_purchase_command.py` içinde `_check_velocity()` fonksiyonu Lua script ile Redis'teki harcama sayacını atomik olarak artırır.
Ancak ardından gelen veritabanı yazma işlemi (örneğin DB bağlantı kopması, deadlock veya disk dolması sebebiyle) başarısız olup rollback olduğunda, Redis sayacı artmış olarak kalır. Kullanıcı teqlik alamadığı bir işlem yüzünden günlük ₺5.000'lik kotasından harcamış olur.

#### Çözüm Reçetesi
DB işlemi başarısız olduğunda Redis sayacını `DECRBYFLOAT` ile telafi eden bir `try...except` mekanizması veya Redis artırımını DB commit aşamasına erteleyen Two-Phase mantık kurulmalıdır.

---

## 🔄 4. Çapraz Katman Finansal Tutarlılık ve Yaşam Döngüsü Matrisi

Aşağıdaki matris, bir In-App Purchase işleminin farklı yaşam döngüsü adımlarında sistemin tüm bileşenlerindeki beklenen ve fiili durumunu özetler:

| Yaşam Döngüsü Senaryosu | Apple StoreKit Durumu | Mobil İstemci (Hive / UI) | Backend Durumu | PostgreSQL (DB & Ledger) | Redis Durumu |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Normal Consumable Alımı (Happy Path)** | `PURCHASED` → Sunucu onayı sonrası `finishTransaction` | Önce yükleniyor, verify sonrası `+teqlik` anında bakiye artışı | JWS x5c tam doğrulanır, Replay yoksa onay | `users.teqlik_balance + N`, `teqlik_transactions` INSERT, `wallet_ledger` INSERT | Mutex alınır ve silinir, Velocity güncellenir, Auth session cache silinir |
| **Ağ Kesintisi / 502 Bad Gateway** | `PURCHASED` (Kuyrukta beklemeli) | **HATA (Şu anki kod kuyruktan siliyor - P0!)** | İstek sunucuya ulaşamaz | Hiçbir kayıt değişmez (Rollback) | Değişiklik yok |
| **Eşzamanlı Replay / Mükerrer İstek** | Tekil Transaction ID | İlk istek `true`, ikinci istek `409 Conflict` (başarılı sayar) | Mutex ilkini geçirir, ikincisi replay yakalar | Tekil `uq_store_tx` kuralı korunur, çift bakiye engellenir | İkinci istek DB'ye varmadan Redis'te bloklanır |
| **Abonelik Otomatik Yenileme (DID_RENEW)** | Apple S2S Webhook V2 gönderir | Uygulama açılışında `syncSubscription` veya WS invalidation | `notificationUUID` idempotensi kontrol edilir | `users.pro_expires_at` yeni tarihe uzatılır, ledger'a log atılır | `session:user:{id}` temizlenir |
| **Kullanıcı PRO İadesi Aldı (REFUND)** | Apple S2S Webhook V2 `REFUND` | İlk profil açılışında standart plana düşer | **HATA (Şu anki kod iadeyi bulamıyor - P1!)** | `users.user_type='standard'`, `pro_expires_at=NULL` yapılmalıdır | Oturum önbelleği temizlenmelidir |
| **Consumable İadesi & Eksi Bakiye** | Apple S2S Webhook V2 `REFUND` | Bakiye negatif gösterilir, harcama kilitlenir | `HandleStoreRefundCommand` çalışır | `teqlik_balance - N` (negatif olabilir), `users.pending_refund = true`, `refund_log` INSERT | Admin telemetrisi tetiklenir |

---

## ⚖️ 5. Son Karar, Mimari Hüküm ve Aksiyon Planı

### Mimari Hüküm
teqlif platformunun Apple IAP ve Cüzdan mimarisi; StoreKit 2 JWS formatını benimsemesi, sunucu tarafında x5c zinciri kontrolü öngörmesi, veritabanında partial unique index (`uq_store_tx`) ve çift girişli muhasebe defteri (`wallet_ledger`) tasarlamış olması açısından modern ve doğru niyetlerle kurgulanmıştır.

Bununla birlikte, **üretim ortamında doğrudan finansal kayba ve güvenlik ihlaline yol açacak 3 adet Kritik (P0) zaaf tespit edilmiştir**:
1. **İstemcide fiş doğrulanmadan `completePurchase` çağrılması:** Ağ kopmalarında kullanıcı parasını ödediği halde hakkını kalıcı olarak kaybetmektedir.
2. **Apple Verifier'da x5c imza zinciri kontrolünün atlanması:** Herhangi bir kullanıcının sahte sertifikalarla sınırsız ve ücretsiz bakiye üretmesine olanak tanımaktadır.
3. **Replay kontrolündeki yarış koşulu:** Mükerrer isteklerde HTTP 500 hataları ve bakiye sapmaları yaratmaktadır.

### Kademeli Aksiyon Yol Haritası

```mermaid
flowchart TD
    subgraph Faz 1: Acil Finansal Güvenlik (P0)
        F1A["IAP-01: completePurchase'i verify sonrasına taşı"] --> F1B["IAP-02: x5c hiyerarşik imza doğrulamasını yaz"]
        F1B --> F1C["IAP-03: Replay kontrolüne Redis Mutex & IntegrityError koruması ekle"]
    end
    
    subgraph Faz 2: Veri Bütünlüğü & Webhook (P1)
        F2A["IAP-04: users UPDATE RETURNING ile atomik defter yazımı"] --> F2B["IAP-05: ASSN V2 notificationUUID idempotensi"]
        F2B --> F2C["IAP-06: Subscription iadelerinde PRO iptali"]
        F2C --> F2D["IAP-07: Velocity limitini user_id ile birleştir"]
    end

    subgraph Faz 3: Mimari Temizlik & MVVM (P2 / P3)
        F3A["IAP-08: SQLAlchemy User modeline pending_refund ekle"] --> F3B["IAP-09: Satın alma sonrası Hive invalidate & WS push"]
        F3B --> F3C["IAP-10: WalletRepository & ProSubscriptionViewModel MVVM dönüşümü"]
    end

    Faz 1 --> Faz 2 --> Faz 3
```

1. **Faz 1 (Hemen / P0 Öncelik):**
   - `mobile/lib/services/iap_service.dart` içinde `completePurchase` çağrısını satır 100'den alıp `_verifyWithBackend` sonrasına taşıyın.
   - `backend/app/services/store/apple_verifier.py` içindeki `_verify_x5c_chain` metoduna `cryptography` ile sertifika imza doğrulamasını (`root -> intermediate -> leaf`) ekleyin.
   - `backend/app/use_cases/wallet/commands/verify_purchase_command.py` içine Redis dağıtık kilidini ve `IntegrityError` yakalayıcısını ekleyin.

2. **Faz 2 (Kısa Vade / P1 Öncelik):**
   - `_handle_consumable` ve `_handle_subscription` metodlarını `UPDATE ... RETURNING` desenine geçirin.
   - `AppleNotificationHandler` ve `wallet_tasks.py` içerisine `notificationUUID` Redis kontrolü koyun.
   - `handle_store_refund_command.py` içindeki sorguyu abonelik tiplerini de kapsayacak şekilde güncelleyip PRO iptal mantığını bağlayın.
   - Hız limitini `rate:iap:user:{user_id}` bazında da çalıştırın.

3. **Faz 3 (Mimari Standartlaşma / P2-P3):**
   - `backend/app/models/user.py` içine `pending_refund` kolonunu ekleyin.
   - Satın alma sonrası mobil Hive önbelleğini temizleyen ve backend'den WebSocket invalidation yayan akışı tamamlayın.
   - UI katmanındaki doğrudan servis erişimlerini ADR §8 uyarınca Repository ve ViewModel katmanlarına refactor edin.

---

## 📋 V1.0 Sonrası Code Review — Residual Fixes (2026-11-10)

12/12 bulgu tamamlandıktan sonra gerçekleştirilen kod incelemesinde 6 ek konu tespit edilmiş ve aynı gün düzeltilmiştir.

| # | Öncelik | Dosya | Sorun | Commit |
|---|---------|-------|-------|--------|
| Açık 1 | P1 | `verify_purchase_command.py` | `user_key` velocity check `if device_id:` bloğu içindeydi — `device_id` gönderilmediğinde kullanıcı velocity tamamen atlanıyordu | `9cf79fac` |
| Açık 2 | P1 | `wallet_tasks.py` | REFUND bildirimleri `apple_handler.handle()` üzerinden geçmediğinden `notificationUUID` idempotensi kontrolü bypass ediliyordu | `9cf79fac` |
| Açık 3 | P1 | `apple_verifier.py` | `_verify_cert_signed_by()` yalnızca EC anahtarlarını destekliyordu; Apple WDRCA G1-G5 RSA tabanlı CA'lar için `ValueError` fırlatıyordu | `9cf79fac` |
| Açık 4 | P2 | `profile_screen.dart` | `_WalletScreenState` ve alt widget'lar IAP-10 sonrasında hâlâ `WalletService.*` statik metodlarını kullanıyordu; `walletRepositoryProvider`'a geçirildi; `_IbanPreRegistrationSheet` → `ConsumerStatefulWidget` | `9cf79fac` · `bfa00891` |
| Açık 5 | P2 | `iap_service.dart` | `else` dalındaki `completePurchase` çağrısı `.pending` (Ask to Buy / 3D Secure) durumunda da tetikleniyordu | `9cf79fac` |
| Açık 6 | P3 | `verify_purchase_command.py` | `except (BadRequestException, ConflictException): raise` velocity rollback'i atlıyordu; `ConflictException` (IntegrityError duplicate) sonrası velocity sayacı geri alınmıyordu | `9cf79fac` |

