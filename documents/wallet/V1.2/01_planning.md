# Wallet V1.2 — İŞLEMLER Sekmesi & teqlik DÖNÜŞÜM

**Tarih:** 2026-11-28  
**Durum:** Planlama

---

## 1. Kapsam

### 1.1 UI Değişiklikleri

| # | Mevcut | Yeni |
|---|--------|------|
| Tab 2 label | `teqlik Al` | `teqlik AL` (büyük harf, ARB key güncelleme) |
| Tab 3 label | `Hareketler` | `İŞLEMLER` |
| Tab 3 yapısı | Düz liste | 2 alt-sekme: `teqlik DÖNÜŞÜM` + `HAREKETLER` |

**Ana sekme yapısı (değişmez):**
```
┌─────────────┬─────────────┬─────────────┐
│   ÜYELİK    │  teqlik AL  │  İŞLEMLER   │
└─────────────┴─────────────┴─────────────┘
```

**İŞLEMLER içi alt-sekmeler:**
```
┌──────────────────────────┬────────────────┐
│     teqlik DÖNÜŞÜM       │   HAREKETLER   │
└──────────────────────────┴────────────────┘
```

### 1.2 Yeni Özellik: teqlik → Yayın Dakikası Dönüşümü

**Kural:** 1 teqlik = 1 dakika canlı yayın kredisi  
**Oran sabiti:** Backend'de tek kaynak (`TEQLIK_PER_STREAM_MINUTE = 1`)

---

## 2. teqlik DÖNÜŞÜM Sekmesi İçeriği

### 2.1 Bilgi Referans Kartları (salt okunur)

Sistemdeki tüm teqlik harcama işlemleri ve birim maliyetleri:

| İşlem | Mevcut Maliyet | transaction_type |
|-------|---------------|-----------------|
| **Canlı Yayın Dakikası** (YENİ) | 1 teqlik/dk | `spend_stream_minutes` |
| (Boost) İlan Öne Çıkarma | 50 teqlik | `spend_boost` |
| (Blast) Toplu Kitle Bildirimi | 10 teqlik | `spend_blast` |
| İlan Reaktivasyonu | 10 teqlik | `spend_reactivation` |
| Yapay Zeka İlan Açıklaması | 5 teqlik | `spend_ai_desc` |
| Yeniden Ulaşma (Retargeting) | 10 teqlik | `spend_retargeting` |
| Canlı Hediye | hediye değeri | `send_gift` |

> **Not:** Maliyetler `credit_service.py → CREDIT_COSTS_TEQLIK` üzerinden çekilmeli;  
> frontend'e statik hardcode edilmemeli. Backend yeni endpoint'e maliyet haritasını döner.

### 2.2 Dönüşüm Modülü (Canlı Yayın Dakikası)

**Dikkat çeken dönüşüm CTA'sı:**
- Nabız atan animasyonlu ikon (pulsing `Icons.swap_horiz` veya `FontAwesomeIcons.arrowsRotate`)
- Basıldığında `showModalBottomSheet` açılır

**Modal İçeriği:**
```
┌──────────────────────────────────────┐
│  Mevcut Bakiye: [XXX teqlik]         │
├──────────────────────────────────────┤
│  Yayın Dakikası Ekle                 │
│  ┌────────────────────┐  ━━━━━━━━━━ │
│  │  [−] [ 0 ] [+]    │  = 0 teqlik │
│  └────────────────────┘             │
│            [DÖNÜŞTÜR]                │
├──────────────────────────────────────┤
│  Bilgi: 1 dakika = 1 teqlik         │
└──────────────────────────────────────┘
```

**Onay Popup'ı:**
```
┌──────────────────────────────────────┐
│  Dönüşümü Onayla                     │
│  30 dakika = 30 teqlik               │
│            [İPTAL]  [ONAY]           │
└──────────────────────────────────────┘
```

**UX kuralları:**
- Input sadece pozitif tam sayı; `−` değer girilememeli
- Bakiye yetersizse `DÖNÜŞTÜR` butonu disabled + uyarı mesajı
- `ONAY` → optimistic UI (bakiye hemen düşer, spinner) → EventBus fire → hata varsa rollback + snackbar
- Başarı: `CreditsChangedEvent` + `WalletConversionSuccessEvent` → hero card balancesi güncellenir

---

## 3. Backend Değişiklikleri

### 3.1 DB Migration (Alembic)

**Yeni kolon:** `users.stream_minutes_bonus INT DEFAULT 0 NOT NULL`

```sql
ALTER TABLE users ADD COLUMN stream_minutes_bonus INTEGER NOT NULL DEFAULT 0;
```

- **Semantik:** Teqlik ile satın alınan, aylık yayın kotasına ek dakika havuzu
- **Sıfırlama:** Aylık reset'te SIFIRLANMAZ (kullanıcı teqlik ödedi)
- **Tüketim:** Aylık kota dolduğunda bu havuzdan çekilir

**Migration ID kısıtı:** ≤ 32 karakter (ADR feedback kuralı)

### 3.2 Yayın Limiti Kontrolü Güncellemesi

**Dosya:** `start_stream.py`

```python
# Mevcut
limit = stream_limit_minutes(user.user_type)
if limit is not None and (user.monthly_stream_minutes_used or 0) >= limit:
    raise BadRequestException(code="STREAM_MONTHLY_LIMIT_REACHED")

# Yeni
limit = stream_limit_minutes(user.user_type)
bonus = user.stream_minutes_bonus or 0
effective_limit = (limit + bonus) if limit is not None else None
if effective_limit is not None and (user.monthly_stream_minutes_used or 0) >= effective_limit:
    raise BadRequestException(code="STREAM_MONTHLY_LIMIT_REACHED")
```

**Dosya:** `stream_finalizer.py` — bonus tüketim mantığı:
```python
# Yayın bitiminde bonus tüketimi
if limit is not None:
    total_used = user.monthly_stream_minutes_used
    if total_used > limit and user.stream_minutes_bonus > 0:
        bonus_consumed = min(total_used - limit, user.stream_minutes_bonus)
        user.stream_minutes_bonus = max(0, user.stream_minutes_bonus - bonus_consumed)
```

### 3.3 Yeni Endpoint

**Route:** `POST /api/wallet/stream-minutes/convert`

```python
class StreamMinutesConvertRequest(BaseModel):
    minutes: int = Field(gt=0, le=10000)  # max 10k dakika = ~167 saat

@router.post("/stream-minutes/convert")
async def convert_teqlik_to_stream_minutes(
    body: StreamMinutesConvertRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.convert_to_stream_minutes_command import ConvertToStreamMinutesCommand
    result = await ConvertToStreamMinutesCommand(db).execute(
        user_id=current_user.id,
        minutes=body.minutes,
    )
    await db.commit()
    return result
```

### 3.4 Use Case: ConvertToStreamMinutesCommand

**Dosya:** `use_cases/wallet/commands/convert_to_stream_minutes_command.py`

**Mantık:**
1. `user.teqlik_balance >= minutes` kontrol (1:1 oran)
2. `user.teqlik_balance -= minutes` (atomik — SELECT FOR UPDATE)
3. `user.stream_minutes_bonus += minutes`
4. `TeqlikTransaction(amount=-minutes, transaction_type="spend_stream_minutes")` ekle
5. Redis wallet cache invalidate
6. `{"ok": True, "minutes_added": minutes, "new_balance": ..., "bonus_minutes": ...}` dön

**Hata kodları:**
- `INSUFFICIENT_TEQLIK` — bakiye yetersiz
- Genel exception → HTTP 500

### 3.5 Maliyet Haritası Endpoint

**Route:** `GET /api/wallet/conversion-rates`

Frontend'e statik hardcode yapmamak için backend maliyet tablosu sağlar:

```json
{
  "stream_minutes": {"teqlik_per_unit": 1, "unit": "minute"},
  "boost":          {"teqlik_per_unit": 50, "unit": "use"},
  "blast":          {"teqlik_per_unit": 10, "unit": "use"},
  "reactivation":   {"teqlik_per_unit": 10, "unit": "use"},
  "ai_desc":        {"teqlik_per_unit": 5,  "unit": "use"},
  "retargeting":    {"teqlik_per_unit": 10, "unit": "use"}
}
```

### 3.6 Wallet Summary Güncellemesi

`GET /api/wallet/summary` → `stream_minutes_bonus` alanı eklenir:

```json
{
  "teqlik_balance": 350,
  "stream_minutes_bonus": 120,
  ...
}
```

### 3.7 Transaction Type & Label

**wallet.py `_TYPE_LABELS`'a ekle:**
```python
"spend_stream_minutes": "Yayın dakikası dönüştürüldü",
```

---

## 4. Frontend Değişiklikleri

### 4.1 Mimari Yaklaşım

```
SubscriptionToolsScreen (stateful - mevcut)
└── _WalletScreenState (stateful - mevcut)
    ├── _tabController: TabController(length: 3)   [ÜYELİK / teqlik AL / İŞLEMLER]
    └── _islemlerTabController: TabController(length: 2)  [YENİ]
        ├── _TeqlikDonusumTab                      [YENİ widget]
        │   ├── Referans Kartları (conversion_rates'ten)
        │   └── _DonusumCTA → _ConvertMinutesSheet [YENİ bottom sheet]
        └── _HareketlerTab (mevcut Hareketler kodu buraya taşınır)
```

**MVVM:**
- `WalletConversionViewModel` (Riverpod `AsyncNotifier`) — dönüşüm işlemi state'i
- `conversionRatesProvider` (Riverpod `FutureProvider`) — `GET /wallet/conversion-rates`
- `WalletService.convertToStreamMinutes(minutes)` eklenir

### 4.2 Event Bus

```dart
class WalletConversionSuccessEvent {
  final int minutesAdded;
  final int newBalance;
  final int bonusMinutes;
  const WalletConversionSuccessEvent({...});
}
```

`CreditsChangedEvent` zaten var — dönüşüm sonrası fire edilir.

### 4.3 Yeni Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `screens/viewmodels/wallet_conversion_view_model.dart` | AsyncNotifier — convert işlemi |
| `widgets/wallet/teqlik_donusum_tab.dart` | Referans kartları + CTA |
| `widgets/wallet/convert_minutes_sheet.dart` | Bottom sheet modal |

### 4.4 Değiştirilen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `screens/profile_screen.dart` | Tab yeniden yapılandırması, iç TabController |
| `services/wallet_service.dart` | `convertToStreamMinutes()`, `getConversionRates()` |
| `core/event_bus.dart` | `WalletConversionSuccessEvent` |
| `documents/language/app_tr.arb` | Yeni ARB anahtarları |
| `documents/language/app_en.arb` | Yeni ARB anahtarları |
| `backend/app/models/user.py` | `stream_minutes_bonus` alanı |
| `backend/app/routers/wallet.py` | Yeni endpoint'ler + label |
| `backend/app/use_cases/wallet/commands/` | `convert_to_stream_minutes_command.py` |
| `backend/app/use_cases/streams/commands/start_stream.py` | Bonus kontrolü |
| `backend/app/use_cases/streams/stream_finalizer.py` | Bonus tüketim mantığı |
| `backend/app/services/subscription/tier.py` | `TEQLIK_PER_STREAM_MINUTE = 1` sabiti |

### 4.5 ARB Anahtarları (Yeni)

```json
"walletTabBuy":               "teqlik AL",
"walletTabTransactions":      "İŞLEMLER",
"walletTabConversion":        "teqlik DÖNÜŞÜM",
"walletTabMovements":         "HAREKETLER",
"walletConvertTitle":         "teqlik DÖNÜŞÜM",
"walletConvertBalance":       "Mevcut Bakiye",
"walletConvertMinutesLabel":  "Yayın Dakikası Ekle",
"walletConvertTeqlikEq":      "{minutes} dakika = {teqlik} teqlik",
"walletConvertButton":        "DÖNÜŞTÜR",
"walletConvertConfirmTitle":  "Dönüşümü Onayla",
"walletConvertConfirmOk":     "ONAY",
"walletConvertConfirmCancel": "İPTAL",
"walletConvertSuccess":       "{minutes} dakika hesabınıza eklendi!",
"walletConvertInsufficient":  "Yetersiz teqlik bakiyesi",
"walletConvertZeroError":     "Lütfen en az 1 dakika girin",
"walletConvertRateInfo":      "1 dakika yayın = 1 teqlik",
"walletConversionRates":      "Teqlik ile Neler Yapabilirsiniz?",
"walletRateLiveStream":       "Canlı Yayın Dakikası",
"walletRateBoost":            "İlan Öne Çıkarma",
"walletRateBlast":            "Toplu Kitle Bildirimi",
"walletRateReactivation":     "İlan Reaktivasyonu",
"walletRateAiDesc":           "Yapay Zeka İlan Açıklaması",
"walletRateRetargeting":      "Yeniden Ulaşma",
"walletBonusMinutes":         "+{minutes} dk bonus yayın",
"walletTxnSpendStreamMinutes": "Yayın dakikası dönüştürüldü"
```

---

## 5. Güvenlik & Validasyon

| Katman | Kural |
|--------|-------|
| Backend | `SELECT FOR UPDATE` — race condition önleme |
| Backend | `minutes > 0 AND minutes <= 10000` |
| Backend | `teqlik_balance >= minutes` atomik kontrol |
| Backend | Redis cache invalidate sonrası döner |
| Frontend | Input `> 0` ve bakiye `>= input` olmadan DÖNÜŞTÜR disabled |
| Frontend | Çift tıklama koruması (`_converting: bool` flag) |

---

## 6. Test Senaryoları

| Senaryo | Beklenti |
|---------|----------|
| Bakiye=100, convert 50 | Başarı: balance=50, bonus+=50 |
| Bakiye=10, convert 50 | Hata: INSUFFICIENT_TEQLIK |
| Convert 0 | UI engellemeli; API'ya ulaşmamalı |
| Convert -1 | UI + backend engeli |
| Bonus=50, limit=1800, used=1830 | Yayın başlamalı (bonus hakkı var) |
| Bonus=0, limit=1800, used=1800 | Yayın başlamamalı |
| İki eş zamanlı istek | Sadece biri geçmeli (FOR UPDATE lock) |

---

## 7. Uygulama Sırası (ADR §13 Workflow)

```
1. Alembic migration (stream_minutes_bonus)
2. Backend: tier.py TEQLIK_PER_STREAM_MINUTE sabiti
3. Backend: conversion_rates endpoint
4. Backend: ConvertToStreamMinutesCommand use case
5. Backend: wallet.py router endpoint + label
6. Backend: start_stream.py + stream_finalizer.py güncelleme
7. Backend: wallet summary stream_minutes_bonus alanı
8. ARB: Yeni anahtarlar (tr + en) + sync_main.py push
9. Flutter: event_bus.dart → WalletConversionSuccessEvent
10. Flutter: wallet_service.dart → yeni metotlar
11. Flutter: wallet_conversion_view_model.dart (AsyncNotifier)
12. Flutter: convert_minutes_sheet.dart (bottom sheet)
13. Flutter: teqlik_donusum_tab.dart (referans kartları + CTA)
14. Flutter: profile_screen.dart → tab yeniden yapılandırması
15. Test → Commit → Push → teqlif-restart
```

---

## 8. Açık Sorular

| Soru | Öneri |
|------|-------|
| Bonus dakika aylık reset'te silinsin mi? | Hayır — teqlik ödendi, kalıcı olmalı |
| Max dönüşüm limiti? | 10.000 dk/işlem (backend Field le=10000) |
| Conversion rates dinamik mi olsun? | Evet — `/wallet/conversion-rates` endpoint (5 dk Redis cache) |
| `spend_blast` ve `spend_lead_gen` aynı mı? | Evet — aynı maliyet, farklı context. İkisi de gösterilecek |
