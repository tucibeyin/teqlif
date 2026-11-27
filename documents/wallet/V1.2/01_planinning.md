# Wallet V1.2 — teqlik DÖNÜŞÜM Özelliği Planlama Belgesi

**Tarih:** 2026-11-28  
**Yazar:** tucibeyin  
**Durum:** Planlama — Implementasyon başlamadı  
**Bağlı ADR:** §1 (OTA), §9 (Cache), §13 (Workflow), §22–23 (SWR), §40 (CreditGate)

---

## İçindekiler

1. [Özellik Özeti](#1-özellik-özeti)
2. [Mimari Kararlar (ADR)](#2-mimari-kararlar-adr)
3. [Geliştirme Workflow — ADR §13](#3-geliştirme-workflow--adr-13)
4. [Clean Architecture — Katmanlar](#4-clean-architecture--katmanlar)
5. [Clean Code Kuralları](#5-clean-code-kuralları)
6. [PostgreSQL — Veri Modeli ve Kısıtlar](#6-postgresql--veri-modeli-ve-kısıtlar)
7. [Redis — Cache ve Atomik İşlemler](#7-redis--cache-ve-atomik-işlemler)
8. [Event-Driven Mimari](#8-event-driven-mimari)
9. [Event Bus — Flutter](#9-event-bus--flutter)
10. [MVVM — Flutter Yapısı](#10-mvvm--flutter-yapısı)
11. [OTA / ARB Çeviri Kuralları](#11-ota--arb-çeviri-kuralları)
12. [Güvenlik Kuralları](#12-güvenlik-kuralları)
13. [İmplementasyon Sırası (15 Adım)](#13-i̇mplementasyon-sırası-15-adım)
14. [Test Senaryoları](#14-test-senaryoları)

---

## 1. Özellik Özeti

### 1.1 Tab Yapısı Değişikliği

**Mevcut:**
```
[ÜYELİK] [teqlik Al] [Hareketler]
```

**Hedef:**
```
[ÜYELİK] [teqlik AL] [İŞLEMLER]
                           └── [teqlik DÖNÜŞÜM] [HAREKETLER]
```

Değişiklikler:
- `"teqlik Al"` → `"teqlik AL"` (ARB key: `walletTabBuy`)
- `"Hareketler"` → `"İŞLEMLER"` (ARB key: `walletTabTransactions`)
- Yeni alt tab: `"teqlik DÖNÜŞÜM"` (ARB key: `walletTabConversion`)
- Taşınan alt tab: `"HAREKETLER"` (ARB key: `walletTabMovements`)

### 1.2 teqlik DÖNÜŞÜM Sekmesi

**Referans Kartlar (Statik, OTA):**

| İşlem | ARB Key | Kaynak |
|-------|---------|--------|
| Canlı Yayın Dakikası | `walletRateLiveStream` | `TEQLIK_PER_STREAM_MINUTE = 1` |
| İlan Öne Çıkarma (Boost) | `walletRateBoost` | `CREDIT_COSTS_TEQLIK["boost"] = 50` |
| Toplu Kitle Bildirimi (Blast) | `walletRateBlast` | `CREDIT_COSTS_TEQLIK["blast"] = 10` |
| İlan Reaktivasyonu | `walletRateReactivation` | `CREDIT_COSTS_TEQLIK["reactivation"] = 10` |
| Yapay Zeka İlan Açıklaması | `walletRateAiDesc` | `CREDIT_COSTS_TEQLIK["ai_desc"] = 5` |

**Dönüşüm Modalı:**
- Mevcut teqlik bakiyesi (en üstte)
- Stepper + metin input: dakika girişi (≥0, sadece sayı)
- Dinamik hesaplama: `{minutes} dakika = {teqlik} teqlik`
- DÖNÜŞTÜR butonu → onay popup (ONAY / İPTAL)
- Onay sonrası: optimistik UI (teqlik düşer, bonus dakika artar)
- EventBus üzerinden tüm ilgili widget'ları günceller

### 1.3 Yeni Backend Mantığı

**Dönüşüm oranı:** 1 teqlik = 1 dakika yayın kredisi (`TEQLIK_PER_STREAM_MINUTE = 1`)

**Yeni DB alanı:** `users.stream_minutes_bonus INT DEFAULT 0`
- Aylık reset'e dahil **değil** — kullanıcı teqlik ödemişse dakika kalıcı
- Yayın sınırı: `stream_limit_minutes(user_type) + user.stream_minutes_bonus`

---

## 2. Mimari Kararlar (ADR)

### ADR-W1: Dönüşüm Endpoint'i — Yeni Route, CreditGate Dışı

**Karar:** `POST /api/wallet/stream-minutes/convert` yeni route. CreditGate sistemine eklenmez.

**Gerekçe:** CreditGate (§40) ilan/analytics odaklı — wallet'a ait dönüşüm ayrı domain. İleride diğer dönüşüm türleri eklenirse `wallet.py` router altında büyür, CreditGate karmaşıklaşmaz.

**Alternatif reddedilen:** CreditGate'e yeni feature eklemek → cross-domain bağımlılık, test izolasyonu zorlaşır.

---

### ADR-W2: stream_minutes_bonus Aylık Reset'e Dahil Değil

**Karar:** `monthly_stream_minutes_used` her ay sıfırlanır, `stream_minutes_bonus` sıfırlanmaz.

**Gerekçe:** Kullanıcı teqlik vererek dakika satın aldı — aylık reset bu satın almayı geçersiz kılar, bu adaletsiz. Bonus dakikalar tüketilene kadar yaşar.

**Efektif limit formülü:**
```python
effective_limit = stream_limit_minutes(user.user_type) + user.stream_minutes_bonus
remaining = effective_limit - user.monthly_stream_minutes_used
```

---

### ADR-W3: Dönüşüm Atomikliği — PostgreSQL FOR UPDATE + UoW

**Karar:** Teqlik düşme + bonus dakika artışı tek transaction içinde `SELECT ... FOR UPDATE` ile.

**Gerekçe:** İki ayrı UPDATE arasında crash olursa teqlik düşer ama dakika artmaz (ya da tersi). FOR UPDATE ile row lock alınır, UoW commit/rollback garantisi verir.

**Alembic kısıtı:** Migration tek statement, revision ID ≤ 32 karakter, CONCURRENTLY yasak.

---

### ADR-W4: Optimistik UI — EventBus ile Çok Yönlü Güncelleme

**Karar:** API yanıtı beklenmeden UI anında güncellenir; hata gelirse geri alınır.

**Gerekçe:** Kullanıcı deneyimi. Dönüşüm modalı kapandıktan sonra wallet summary ve profil ekranı da güncel görünmeli — EventBus bunu sağlar, `ref.invalidate` yerine seçili.

---

### ADR-W5: Conversion Rates — Backend'den Çekilir, Hardcode Olmaz

**Karar:** `GET /api/wallet/conversion-rates` endpoint'i maliyetleri döndürür.

**Gerekçe:** `CREDIT_COSTS_TEQLIK` ve `TEQLIK_PER_STREAM_MINUTE` backend sabitleri değişebilir. Frontend'e gömülü değerler OTA yapılamaz. Endpoint Redis'te cache'lenir (uzun TTL, değişince invalidate).

---

## 3. Geliştirme Workflow — ADR §13

Her değişiklik öncesinde `teqlif_architectural_decisions.md` okunur.

```
1. Local geliştirme (Mac)
   ├── Clean architecture + clean code
   ├── Bu planning doc'a uyum
   └── ADR kararlarına uyum

2. git push → GitHub

3. git pull (node'da)
   └── sudo -n gerekmez, tucibeyin SSH key'i var

4. Config ayarı (gerekirse)
   └── ssh node1, .env düzenle

5. Canlı log izleme
   └── sudo journalctl -u teqlif -f

6. Test onayı (kullanıcıdan)

7. Dokümantasyon
   └── ADR'ye commit numarasıyla §Wx ekle

8. Node izleme

9. Mimari güncelleme (gerekirse)

10. Cleanup
```

**Restart komutu:**
```bash
# Tek node
sudo teqlif-restart

# Tüm node'lar paralel
for node in node1 node3 node4 node5 node6 node101 nodeMonitor; do
  ssh $node "sudo -n teqlif-restart 2>&1 | tail -5" &
done
wait
```

**Kurallar:**
- `git pull` asla `sudo` ile çalıştırılmaz
- `sudo teqlif-restart` kullanılır, direkt `systemctl restart` asla
- Flutter build komutları kullanıcı kendisi çalıştırır — Claude çalıştırmaz
- `psql`/`pg_dump` TCP için `-h 127.0.0.1` zorunlu

---

## 4. Clean Architecture — Katmanlar

```
┌─────────────────────────────────────────────────┐
│  Presentation (Flutter)                          │
│  ├── Widgets: TeqlikDonusumTab, ConvertMinSheet  │
│  ├── ViewModel: WalletConversionViewModel        │
│  └── Event: WalletConversionSuccessEvent         │
├─────────────────────────────────────────────────┤
│  Application / Use Case (Backend)                │
│  └── ConvertToStreamMinutesCommand               │
├─────────────────────────────────────────────────┤
│  Domain                                          │
│  ├── Entity: User (stream_minutes_bonus)         │
│  ├── Value: ConversionResult                     │
│  └── Rule: effective_limit formula               │
├─────────────────────────────────────────────────┤
│  Infrastructure                                  │
│  ├── DB: PostgreSQL (UoW, FOR UPDATE)            │
│  ├── Cache: Redis (wallet cache, rates cache)    │
│  └── API: wallet.py router                       │
└─────────────────────────────────────────────────┘
```

### Backend Klasör Yapısı

```
backend/app/
├── models/
│   └── user.py                    ← stream_minutes_bonus alanı
├── schemas/
│   └── wallet.py                  ← ConvertRequest, ConvertResponse, RateItem
├── use_cases/wallet/
│   ├── commands/
│   │   └── convert_stream_minutes_command.py   ← NEW
│   └── queries/
│       └── get_conversion_rates_query.py       ← NEW
├── routers/
│   └── wallet.py                  ← /conversion-rates, /stream-minutes/convert
└── services/
    └── tier.py                    ← TEQLIK_PER_STREAM_MINUTE sabiti
```

### Flutter Klasör Yapısı

```
mobile/lib/
├── events/
│   └── event_bus.dart             ← WalletConversionSuccessEvent eklenir
├── screens/viewmodels/
│   └── wallet_conversion_view_model.dart       ← NEW
├── services/
│   └── wallet_service.dart        ← convertToStreamMinutes(), getConversionRates()
└── screens/wallet/
    ├── teqlik_donusum_tab.dart                 ← NEW
    └── convert_minutes_sheet.dart              ← NEW
```

---

## 5. Clean Code Kuralları

### Tek Sorumluluk

| Sınıf | Tek Sorumluluğu |
|-------|----------------|
| `ConvertToStreamMinutesCommand` | Atomik dönüşüm işlemi |
| `WalletConversionViewModel` | UI state yönetimi |
| `ConvertMinutesSheet` | Kullanıcı giriş arayüzü |
| `TeqlikDonusumTab` | Referans kartlar + dönüşüm CTA |

### İsimlendirme

- Backend: `snake_case` (Python)
- Flutter: `camelCase` değişkenler, `PascalCase` sınıflar
- ARB key: `camelCase`, prefix ile (`wallet*`)
- Redis key: `wallet:{userId}:*` pattern

### Yorum Kuralları

- **Neden** yorumu yaz, **ne** yorumu yazma
- `FOR UPDATE` lock'u için neden gerektiğini açıkla
- `stream_minutes_bonus` reset etmeme kararı için yorum ekle

### Hata Yönetimi

Tüm hata kodları domain exception olarak fırlatılır, router'da yakalanır:

```python
class InsufficientTeqlikError(DomainException):
    code = "INSUFFICIENT_TEQLIK"
    status_code = 400

class InvalidConversionAmountError(DomainException):
    code = "INVALID_CONVERSION_AMOUNT"
    status_code = 400
```

Flutter'da ARB key ile gösterilir:
```dart
"INSUFFICIENT_TEQLIK"    → loc.t('walletConvertInsufficient')
"INVALID_CONVERSION_AMOUNT" → loc.t('walletConvertZeroError')
```

---

## 6. PostgreSQL — Veri Modeli ve Kısıtlar

### Yeni Alan

```sql
ALTER TABLE users
  ADD COLUMN stream_minutes_bonus INTEGER NOT NULL DEFAULT 0;
```

### Alembic Migration Kuralları (§feedback_alembic)

- **Multi-statement yasak:** Her migration tek statement
- **Revision ID ≤ 32 karakter**
- **CONCURRENTLY yasak:** `CREATE INDEX CONCURRENTLY` Alembic'te desteklenmez
- Revision ID örneği: `add_stream_minutes_bonus`

```python
# revision: "add_stream_minutes_bonus"
# down_revision: "<önceki_revision>"

def upgrade():
    op.add_column('users',
        sa.Column('stream_minutes_bonus', sa.Integer(), nullable=False,
                  server_default='0'))

def downgrade():
    op.drop_column('users', 'stream_minutes_bonus')
```

### Atomik Dönüşüm — FOR UPDATE

```python
# convert_stream_minutes_command.py

async def execute(self, user_id: int, minutes: int) -> ConversionResult:
    cost = minutes * TEQLIK_PER_STREAM_MINUTE
    async with self.uow:
        # Row lock — concurrent dönüşüm yarışını önler
        user = await self.uow.users.get_for_update(user_id)
        if user.teqlik_balance < cost:
            raise InsufficientTeqlikError()
        if minutes <= 0:
            raise InvalidConversionAmountError()
        user.teqlik_balance -= cost
        user.stream_minutes_bonus += minutes
        await self.uow.commit()
    return ConversionResult(
        spent_teqlik=cost,
        added_minutes=minutes,
        new_balance=user.teqlik_balance,
        new_bonus_minutes=user.stream_minutes_bonus,
    )
```

### Transaction Sınırları

| İşlem | Transaction | Açıklama |
|-------|-------------|----------|
| Dönüşüm | UoW (tek) | teqlik düşer + bonus artar atomik |
| Yayın başlangıcı | UoW (tek) | monthly_used güncellenir |
| Yayın bitişi | UoW (tek) | kalan dakika hesaplanır, bonus önce tükenir |

---

## 7. Redis — Cache ve Atomik İşlemler

### Cache Anahtarları

| Anahtar | TTL | İçerik | Invalidasyon |
|---------|-----|--------|-------------|
| `wallet:{uid}:summary` | 300s (5 dk) | bakiye + bonus dakika | dönüşüm sonrası |
| `wallet:conversion_rates` | 3600s (1 sa) | maliyet listesi | manuel (değişince) |
| `i18n:{lang}` | 90000s (25 sa) | çeviri paketi | sync_translations.py |

### Invalidasyon Stratejisi

```python
# Dönüşüm sonrası wallet summary cache temizle
await redis.delete(f"wallet:{user_id}:summary")

# Conversion rates nadiren değişir — sadece deploy'da temizle
# Manuel: redis-cli DEL wallet:conversion_rates
```

### Cache-First (SWR) Pattern — ADR §23

```dart
// wallet_service.dart — SWR pattern
Future<WalletSummary> getSummary(int userId) async {
  final cached = await _cache.get('wallet_summary_$userId');
  if (cached != null) {
    _refreshInBackground(userId);   // stale-while-revalidate
    return WalletSummary.fromJson(cached);
  }
  return _fetchAndCache(userId);
}
```

### Atomik Lua Script — Yok (Dönüşüm için Gerek Yok)

Dönüşüm atomikliği PostgreSQL FOR UPDATE ile sağlanır. Redis Lua scripti credit_service.py'deki hız sınırı kontrolünde kullanılır — dönüşüm için ayrıca gerek yok.

---

## 8. Event-Driven Mimari

### Olaylar ve Akış

```
Kullanıcı ONAY'a basar
        │
        ▼
WalletConversionViewModel.convert(minutes)
        │  POST /api/wallet/stream-minutes/convert
        ▼
Backend: ConvertToStreamMinutesCommand
        │  FOR UPDATE → teqlik düşer + bonus artar → commit
        ▼
API Response: { spent, added_minutes, new_balance, new_bonus_minutes }
        │
        ▼
ViewModel: state güncellenir (optimistik → confirmed)
        │
        ├──► EventBus.fire(WalletConversionSuccessEvent)
        │         ├── WalletSummaryWidget → bakiye günceller
        │         ├── ProfileScreen → teqlik badge günceller
        │         └── StreamInfoWidget → bonus dakika gösterir
        │
        └──► WalletService.invalidateBalance()
                  └── Redis cache temizlenir
```

### Hata Akışı

```
API hata döndürürse:
        │
        ▼
ViewModel: state revert (optimistik güncelleme geri alınır)
        │
        ▼
TeqToast.error(loc.t('walletConvertInsufficient'))
```

---

## 9. Event Bus — Flutter

### Mevcut Event'ler

```dart
// event_bus.dart (mevcut)
class CreditsChangedEvent {}           // teqlik bakiyesi değişti
class ListingUpdatedEvent { ... }
class StreamStartedEvent { ... }
```

### Yeni Event

```dart
class WalletConversionSuccessEvent {
  final int spentTeqlik;
  final int addedMinutes;
  final int newBalance;
  final int newBonusMinutes;

  const WalletConversionSuccessEvent({
    required this.spentTeqlik,
    required this.addedMinutes,
    required this.newBalance,
    required this.newBonusMinutes,
  });
}
```

### Dinleyiciler

```dart
// WalletSummaryWidget içinde
_sub = EventBus.on<WalletConversionSuccessEvent>().listen((event) {
  setState(() {
    _balance = event.newBalance;
    _bonusMinutes = event.newBonusMinutes;
  });
});

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

**Kural:** Her `listen` için `dispose()` içinde `cancel()` zorunlu — memory leak önlenir.

---

## 10. MVVM — Flutter Yapısı

### ViewModel Sorumlulukları

`WalletConversionViewModel` (AsyncNotifier):

```
✅ ViewModel'in sorumluluğu:
├── UI state: loading, error, success
├── minutes girişi validasyonu (≤0 → hata)
├── Yeterli bakiye kontrolü (client-side ön kontrol)
├── API çağrısını tetiklemek
├── Optimistik UI güncelleme
├── Hata durumunda revert
└── EventBus.fire() tetiklemek

❌ ViewModel'in sorumluluğu DEĞİL:
├── HTTP çağrısı yapmak (WalletService sorumlu)
├── Widget build etmek
├── Navigator çağrısı (Widget sorumlu)
└── Lokalizasyon erişimi (Widget'ta ref.watch)
```

### State Yapısı

```dart
@freezed
class WalletConversionState with _$WalletConversionState {
  const factory WalletConversionState({
    @Default(0) int minutes,
    @Default(false) bool isLoading,
    @Default(false) bool showConfirm,
    String? errorKey,
    ConversionResult? result,
  }) = _WalletConversionState;
}
```

### Widget Sorumlulukları

```
ConvertMinutesSheet (ConsumerStatefulWidget):
├── ref.watch(walletConversionProvider) → state dinle
├── TextField/stepper → ref.read(...).setMinutes(n)
├── DÖNÜŞTÜR butonu → showConfirmDialog()
├── Onay popup → ref.read(...).convert()
└── Hata → TeqToast.error(loc.t(state.errorKey))

TeqlikDonusumTab (ConsumerWidget):
├── Referans kartlar: ListView ile rate listesi
├── Pulsing CTA butonu → ConvertMinutesSheet.show()
└── Mevcut bakiye gösterimi
```

### Provider Yapısı

```dart
// Conversion rates — uzun yaşayan, otomatik dispose yok
final conversionRatesProvider = AsyncNotifierProvider<
    ConversionRatesNotifier, List<RateItem>>(() => ConversionRatesNotifier());

// Sheet state — sheet kapatılınca dispose
final walletConversionProvider = AutoDisposeNotifierProvider<
    WalletConversionViewModel, WalletConversionState>(
  () => WalletConversionViewModel(),
);
```

---

## 11. OTA / ARB Çeviri Kuralları

### Kurallar (ADR §1)

- Tüm kullanıcıya gösterilen yazılar ARB üzerinden
- Hiçbir yazı Flutter kodunda hardcode olmaz
- 5 dil: `tr`, `en`, `ar`, `de`, `ru` — hepsinde aynı key olmalı
- DB'ye direkt SQL yazılmaz — ARB → sync_main.py pipeline

### Eklenen Key'ler (13fa903f commit'inde tamamlandı)

```
walletTabBuy, walletTabTransactions, walletTabConversion, walletTabMovements,
walletConvertTitle, walletConvertBalance, walletConvertMinutesLabel,
walletConvertTeqlikEq, walletConvertButton, walletConvertConfirmTitle,
walletConvertConfirmOk, walletConvertConfirmCancel, walletConvertSuccess,
walletConvertInsufficient, walletConvertZeroError, walletConvertRateInfo,
walletConversionRates, walletRateLiveStream, walletRateBoost, walletRateBlast,
walletRateReactivation, walletRateAiDesc, walletRateRetargeting,
walletBonusMinutes, walletTxnSpendStreamMinutes
```

### Placeholder Kullanımı

```dart
// Parametre interpolasyonu
loc.t('walletConvertTeqlikEq', {
  'minutes': minutes.toString(),
  'teqlik': cost.toString(),
})
// → "{minutes} dakika = {teqlik} teqlik"

loc.t('walletConvertSuccess', {'minutes': result.addedMinutes.toString()})
// → "{minutes} dakika hesabınıza eklendi!"
```

### OTA Sync Komutu

```bash
ssh node1 "cd /var/www/teqlif.com/backend && \
  ../.venv/bin/python3 -c \"\
  import os; [os.environ.update({l.split('=',1)[0].strip():l.split('=',1)[1].strip()}) \
  for l in open('/project/teqlif/config/.env.production') if '=' in l and not l.startswith('#')]; \
  import asyncio; from scripts.sync_translations import sync; asyncio.run(sync())\""
```

---

## 12. Güvenlik Kuralları

| Kural | Kaynak |
|-------|--------|
| `secrets.env` / `.env.*` repoya girmez (PUBLIC repo) | .gitignore |
| `git pull` asla `sudo` ile | §13 |
| Servis restart: `sudo teqlif-restart` | feedback_restart_command |
| Flutter build kullanıcı yapar | feedback_flutter_build |
| `psql`/`pg_dump` TCP: `-h 127.0.0.1` | feedback_psql_peer_auth |
| fail2ban yasak — CrowdSec | feedback_crowdsec_not_fail2ban |
| Tokenlar/sırlar `.env` dosyalarından | Kod içinde hardcode yasak |
| Alembic: multi-statement, CONCURRENTLY yasak | feedback_alembic |

### Rate Limiting

Dönüşüm endpoint'ine rate limit eklenir:
```python
# wallet.py router'da
@router.post("/stream-minutes/convert")
@rate_limit(key="wallet_convert:{user_id}", limit=10, window=60)
async def convert_stream_minutes(...):
```

### Input Validasyonu

```python
class ConvertRequest(BaseModel):
    minutes: int = Field(gt=0, le=10000, description="Dönüştürülecek dakika sayısı")
```

---

## 13. İmplementasyon Sırası (15 Adım)

| # | Görev | Dosya | Not |
|---|-------|-------|-----|
| 1 | `TEQLIK_PER_STREAM_MINUTE = 1` sabiti ekle | `tier.py` | Mevcut `CREDIT_COSTS_TEQLIK` yanına |
| 2 | Alembic migration: `stream_minutes_bonus` | yeni migration | Revision ID ≤ 32 char |
| 3 | `user.py` model: `stream_minutes_bonus` alanı | `models/user.py` | `default=0` |
| 4 | `GET /api/wallet/conversion-rates` endpoint | `wallet.py` + use case | Redis cache 1h |
| 5 | `ConvertToStreamMinutesCommand` use case | `use_cases/wallet/commands/` | FOR UPDATE |
| 6 | `POST /api/wallet/stream-minutes/convert` | `wallet.py` | Rate limit + hata kodları |
| 7 | `start_stream.py` efektif limit güncelle | `use_cases/streams/` | bonus dahil hesap |
| 8 | `stream_finalizer.py` bonus önce tükenir | `use_cases/streams/` | bonus → monthly sırası |
| 9 | `GET /api/wallet/summary` → `stream_minutes_bonus` ekle | `wallet.py` | Mevcut response'a alan ekle |
| 10 | `WalletConversionSuccessEvent` | `event_bus.dart` | Yeni event sınıfı |
| 11 | `wallet_service.dart` yeni metodlar | `wallet_service.dart` | convertToStreamMinutes, getConversionRates |
| 12 | `WalletConversionViewModel` | `viewmodels/` | AutoDisposeNotifier |
| 13 | `convert_minutes_sheet.dart` | `screens/wallet/` | Bottom sheet, stepper, onay popup |
| 14 | `teqlik_donusum_tab.dart` | `screens/wallet/` | Referans kartlar + pulsing CTA |
| 15 | `profile_screen.dart` tab refactor | `profile_screen.dart` | Tab 2→"teqlik AL", Tab 3→"İŞLEMLER" + alt tab controller |

**Sonraki adımlar (commit → push → restart):**
```bash
git add <files>
git commit -m "feat(wallet): V1.2 teqlik DÖNÜŞÜM özelliği"
git push
for node in node1 node3 node4 node5 node6 node101 nodeMonitor; do
  ssh $node "sudo -n teqlif-restart 2>&1 | tail -5" &
done; wait
```

---

## 14. Test Senaryoları

### Backend

| Senaryo | Beklenen |
|---------|---------|
| 10 teqlik ile 10 dakika dönüştür | ✅ bakiye -10, bonus +10 |
| 0 dakika gönder | ❌ 400 INVALID_CONVERSION_AMOUNT |
| Bakiyeden fazla dakika iste | ❌ 400 INSUFFICIENT_TEQLIK |
| Eş zamanlı iki dönüşüm (aynı kullanıcı) | Sadece biri başarılı, biri INSUFFICIENT_TEQLIK |
| `stream_minutes_bonus` aylık reset'ten etkilenmez | Reset sonrası bonus korunur |
| Bonus dakika efektif limitten sayılır | `start_stream` bonus + monthly limit kullanır |

### Flutter

| Senaryo | Beklenen |
|---------|---------|
| Stepper ile dakika artır | Hesaplanan teqlik dinamik güncellenir |
| Negatif sayı gir | Input 0'a sıfırlanır, hata gösterilmez |
| Yeterli bakiye yok | DÖNÜŞTÜR tıklanınca `walletConvertInsufficient` toast |
| Başarılı dönüşüm | Modal kapanır, `walletConvertSuccess` toast, bakiye günceller |
| EventBus | WalletSummaryWidget bakiyeyi günceller |
| Dark mode | Tüm renkler token üzerinden, hardcode renk yok |
| AR dili | RTL layout bozulmuyor |

### Regresyon

| Alan | Kontrol |
|------|---------|
| Mevcut HAREKETLER tab | İçerik ve işlevsellik korundu |
| ÜYELİK tab | Değişmedi |
| CreditGate (boost/blast) | Dönüşüm eklenince etkilenmedi |
| Yayın başlatma limiti | Aylık limit hâlâ çalışıyor |
