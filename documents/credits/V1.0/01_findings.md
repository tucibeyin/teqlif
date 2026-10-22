# Kredi Sistemi Mimari Analizi — V1.0

**Tarih:** 2026-10-22  
**Kapsam:** blast · boost · ai_desc · reactivation  
**Durum:** Bulgular kaydedildi; tüm kod düzeltmeleri uygulandı

---

## 1. Özellik Tablosu

| Özellik | Standart ücretsiz | PRO ücretsiz | TEQlik maliyeti | Standart erişim |
|---|---|---|---|---|
| blast | 3/ay | 6/ay | 10/kişi (ücreti aşan) | ✅ Karma model |
| boost | 0 | 3/ay | 50 | ✅ Direkt ücretli |
| ai_desc | 0 | 6/ay | 5 | ✅ Her seferinde ücretli |
| reactivation | 0 (30 gün penceresi ücretsiz) | 3/ay | 10 | ✅ Pencere + ücretli |

---

## 2. Depolama (Redis)

### Key formatları

| Kullanıcı tipi | Key formatı | TTL |
|---|---|---|
| PRO | `{prefix}:{uid}:{YYYY-MM-DD}` (anniversary başlangıcı) | Dönem bitişine kadar |
| Standart | `{prefix}:{uid}:{YYYY-MM}` | Ay sonuna kadar |

### Bulgu — Standart Kullanıcı Redis Boşluğu

Boost, ai_desc ve reactivation için `free_standard = 0` olduğundan `credit_service.increment()` standart kullanıcı için **hiç çağrılmıyor**. Bu teknik olarak doğru — kredi yok ki saysın. Ancak yan etki:

- `/boost-credits`, `/ai-desc-credits` gibi endpointler standart kullanıcı için her zaman `used: 0` döndürüyor
- TEQlik harcamasının Redis'te izi yok; sadece `TeqlikTransaction` tablosunda kayıt var
- Gerçek kullanım yoğunluğu izlenemiyor (analitik kör nokta)

### Bulgu — Fail-Open Davranış

```python
async def get_used(...) -> int:
    except Exception:
        return 0  # Redis down → kredi limiti bypass edilir
```

`get_used()` ve `increment()` tüm exceptionları yutuyor. Redis kesintisi durumunda:
- Standart kullanıcı `used = 0` görür → limit aşımı engeli kalkar
- PRO kullanıcı ücretsiz limitini tüketmiş gibi görünmez → fazladan ücretsiz kullanım

**Tasarım sorusu:** Bu kasıtlı "fail-open" mı, yoksa gözden kaçan bir risk mi — netleştirilmeli.

---

## 3. Kullanım Öncesi Kontrol

| Özellik | Pre-check | Konum | Değerlendirme |
|---|---|---|---|
| blast | ✅ | `leads.py → send_blast` başı | Doğru — cap + bakiye |
| boost | ✅ | `ads.py → boost_listing` başı | Doğru — bakiye yoksa reddeder |
| ai_desc | ✅ | `listings.py` → LLM öncesi | Doğru, ama bkz. §5 |
| reactivation | ✅ | `toggle_listing.py` → UoW commit öncesi | Doğru — 30 gün penceresi önce kontrol |

---

## 4. Kullanım Sonrası Düşürme

### Blast — Minor Race Window

```python
await db.commit()                                    # DB yazıldı
await credit_service.increment("blast", ...)         # Redis SONRA
```

DB commit oldu ama Redis yazımı başarısız olursa → kullanıcı blast yaptı, sayaç artmadı.  
PRO'da ücretsiz limit aşımı tespit edilemez. Düşük olasılık ama gerçek pencere.

### Boost — Aynı Pattern

Aynı DB→Redis sıra sorunu. Minor inconsistency.

### ai_desc — En Riskli Yer ⚠️

```python
try:
    await db.execute(UPDATE users SET teqlik_balance - cost ...)
    db.add(TeqlikTransaction(...))
    await db.commit()
except Exception as exc:
    logger.error("[AI Desc] Kredi sayma başarısız: %s", exc)
    # HATA YUTULUR — kullanıcı LLM yanıtını ücretsiz almış olur
```

Exception log'a yazılıyor ama kullanıcıya hata dönmüyor. LLM yanıtı zaten verildiği için TEQlik düşmeden ai_desc bedava olabilir. **Düzeltme önerilir.**

### Reactivation — Doğru Pattern

UoW commit sonrası `increment()` çağrısı aynı minor gap'i taşıyor. Ancak atomik deduction doğru:

```python
UPDATE users SET teqlik_balance = GREATEST(0, teqlik_balance - :cost)
WHERE id = :uid AND teqlik_balance >= :cost
RETURNING teqlik_balance
-- RETURNING None → InsufficientFundsException
```

---

## 5. Merkezileşme Değerlendirmesi

### Güçlü Yanlar ✅

| Özellik | Durum |
|---|---|
| `credit_service.py` tek kaynak | Tüm limitler, maliyetler, Redis key'leri buradan |
| `FeatureName` Literal type | Tip güvencesi; yanlış özellik adı compile-time hata |
| `billing_period_start()` PRO anniversary hesabı | Tutarlı, tek yer |
| `TeqlikTransaction` audit log | Her işlemde oluşturuluyor |
| `_PREMIUM_TYPES` frozenset | ✅ Düzeltildi — kullanıcı tipi map'i, static bool değil |

### Zayıf Yanlar ❌

| Sorun | Etki | Öncelik |
|---|---|---|
| ai_desc TEQlik düşürme `try/except` yutulur | Ücretsiz LLM yanıtı alınabilir | Yüksek |
| Standart kullanıcı TEQlik harcaması Redis'te yok | Analitik kör nokta, abuse detection eksik | Orta |
| DB commit → Redis increment atomik değil | Minor race: sayaç artmayabilir | Orta |
| `get_used()` fail-open davranış belgelenmemiş | Redis kesintisinde limit bypass | Orta |
| Her router kendi check→use→deduct→increment pipeline'ını yazıyor | 5 ayrı dosyada tekrar, farklı hata riski | Düşük |

---

## 6. Kod Değişiklikleri (Bu Analiz Kapsamında Uygulanan)

### `credit_service.py` — `_PREMIUM_TYPES` map eklendi

**Önce:**
```python
def free_limit(feature: FeatureName, is_premium: bool) -> int:
    return cfg["free_pro"] if is_premium else cfg["free_standard"]
```

**Sonra:**
```python
_PREMIUM_TYPES: frozenset[str] = frozenset({"pro"})

def free_limit(feature: FeatureName, user_type: str) -> int:
    return cfg["free_pro"] if user_type in _PREMIUM_TYPES else cfg["free_standard"]
```

`per_op_cap()` da aynı şekilde güncellendi. Yeni bir kullanıcı tipi gelirse (örn. `"enterprise"`) sadece `_PREMIUM_TYPES`'a eklenir; çağıran kodların değişmesine gerek kalmaz.

### Güncellenen Caller Dosyaları

| Dosya | Değişen Satır sayısı | Değişiklik |
|---|---|---|
| `routers/ads.py` | 2 | `== 'pro'` → `user_type` |
| `routers/leads.py` | 10 | `== 'pro'` + `is_premium=True` → `user_type` |
| `routers/listings.py` | 2 | `is_premium=True` → `user_type` |
| `routers/analytics.py` | 1 | `is_premium=True` → `user_type` |
| `use_cases/listings/commands/toggle_listing.py` | 1 | `is_premium=True` → `user_type` |
| `use_cases/listings/queries/get_reactivation_cost.py` | 1 | `is_premium=True` → `user_type` |

---

## 7. Boost UI/UX Denetimi (2026-10-22 eklendi)

### Akış: `listing_detail_screen.dart → _boostListing()`

Boost butonu → `/ads/boost-credits` GET → `/users/me` GET → dialog göster → `/ads/campaigns` POST

### Bulunan ve Düzeltilen Buglar

**B-01 (Kritik — Düzeltildi):** Standart kullanıcı frontend'de bloklıydı  
```dart
// Eski kod — kaldırıldı
if (!isPro) {
  showSnackBar("boostOnlyPro");
  return;
}
```
Backend PRO_REQUIRED kaldırılmışken frontend hâlâ engelliyordu. Standart kullanıcı paid dialog'a hiç ulaşamıyordu.

**B-02 (Kritik — Düzeltildi):** Ücretli boost "Onayla" butonu işlem yapmıyordu  
```dart
// Eski: sadece dialog kapatıyordu
onPressed: teqlikBalance >= 50 ? () => Navigator.pop(dlgCtx, true) : null,

// Yeni: gerçekten boost işlemi başlatıyor
onPressed: teqlikBalance >= 50 ? performBoost : null,
```

**B-03 (UX — Düzeltildi):** Standart kullanıcı için badge yanlış mesaj gösteriyordu  
`limit=0` olduğunda `boostDialogPaidBadge` → "Bu ay **0** ücretsiz hakkını kullandın" görünüyordu.  
Yeni mantık: `limit == 0 → boostDialogPaidBadgeStandard` ("Standart üyelerde aylık ücretsiz boost hakkı bulunmaz")

### ARB Değişiklikleri

| Key | İşlem | Sebep |
|---|---|---|
| `boostDialogPaidBadgeStandard` | Eklendi (5 dil) | Standart kullanıcı için özel badge |
| `boostOnlyPro` | Silindi (5 dil) | Flutter'da artık çağrılmıyor (orphan) |

### Kalan UX Eksikliği

- `boostDialogPaidCostValue` ARB'de hardcoded "50 teqlik" — `credit_service` cost değişirse ARB de güncellenmeli
- Boost'tan önce `/ads/boost-credits` + `/users/me` iki ayrı HTTP isteği atılıyor — single endpoint ile birleştirilebilir

---

## 9. Tüm Kredili Akışlar UI Karşılaştırması (2026-10-22 eklendi)

### Karşılaştırma Tablosu

| Özellik | Pre-flight bilgi | Onay dialogu | Maliyet gösterimi | Bakiye gösterimi | Puan |
|---|---|---|---|---|---|
| **Blast** | ✅ Kitle endpoint | ✅ Zengin dialog (kişi seçici, canlı hesap) | ✅ Dinamik | ✅ Kırmızı uyarı | 10/10 |
| **Boost** | ✅ Credits + bakiye | ✅ İki modlu dialog | ⚠️ ARB hardcoded | ✅ Renkli | 8/10 (buglar düzeltildi) |
| **Reactivation** | ✅ Maliyet endpoint | ⚠️ Sade AlertDialog metin | ✅ Dinamik metin | ✅ Metinde | 7/10 |
| **ai_desc** | ❌ Standart için hiç yok | ❌ Dialog yoktu | ❌ Standart tamamen kör | ❌ | 2/10 → düzeltildi |

### ai_desc Kritik Bulgular ve Düzeltmeler

**B-04 (Kritik — Düzeltildi):** Standart kullanıcı 5 TEQlik harcarken hiç uyarı görmüyordu  
Butona tıklayınca direkt LLM çağrısı → TEQlik sessizce düşüyordu.

**B-05 (Kritik — Düzeltildi):** PRO kullanıcı kredi bitince de onay yok  
`creditsRemaining = 0` → sarı badge gösterir ama tıklayınca yine sessiz TEQlik düşer.

**B-06 (UX — Düzeltildi):** Standart kullanıcı AI butonunda maliyet görmüyordu  
`if (isPro)` bloğu içinde `_CreditBadge` → standart kullanıcıya hiç badge gösterilmiyordu.

**Düzeltme:** `_fetchAiDescription()` başında onay dialog mantığı eklendi:
- `!_isPro` → "5 TEQlik Harcanacak" dialog
- `_isPro && creditsLeft <= 0` → "Aylık Krediniz Doldu. 5 TEQlik" dialog
- `_isPro && creditsLeft > 0` → doğrudan işlem (ücretsiz, dialog yok)
- Standart kullanıcı için `_AiDescButton`'a sarı "5 teqlik" maliyet badge eklendi

### Reactivation Küçük Eksiklik (Açık)

`withinWindow = true` durumunda (30 gün içi) hiç dialog gösterilmiyor — işlem sessizce gerçekleşiyor. Kullanıcı neden ücretsiz olduğunu bilmiyor. Minor UX gap, kritik değil.

### ARB Değişiklikleri

| Key | İşlem |
|---|---|
| `aiDescConfirmStandardTitle/Body` | Eklendi (5 dil) |
| `aiDescConfirmProExhaustedTitle/Body` | Eklendi (5 dil) |
| `aiDescConfirmAction` | Eklendi (5 dil) |
| `aiDescCostBadge` | Eklendi (5 dil) |

---

## 10. Açık Maddeler (Uygulanmadı)

| # | Madde | Öncelik |
|---|---|---|
| A-01 | `listings.py` ai_desc deduction `try/except` → hata kullanıcıya dönmeli | Yüksek |
| A-02 | Standart kullanıcı TEQlik harcamasını Redis'te say (`paid_usage:{feature}:{uid}:{YYYY-MM}`) | Orta |
| A-03 | `get_used()` fail-open davranışını belgele veya Redis circuit-breaker ekle | Orta |
| A-04 | Ortak `execute_credit_gate()` helper — 5 router'daki boilerplate azaltır | Düşük |

---

## 11. Özet Skor

| Boyut | Puan | Not |
|---|---|---|
| Depolama sağlığı | 7/10 | Standart Redis izi yok, fail-open belgelenmemiş |
| Kontrol doğruluğu | 9/10 | Tüm feature'larda LLM/DB öncesi kontrol var |
| Düşürme doğruluğu | 6/10 | ai_desc exception yutuyor; DB→Redis gap |
| Merkezileşme | 9/10 | `_PREMIUM_TYPES` map eklendi, tek kaynak güçlendi |
