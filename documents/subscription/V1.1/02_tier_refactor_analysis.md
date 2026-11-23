# V1.1 Tier Refactor — Analiz ve Eylem Planı

**Tarih:** 2026-11-23  
**Durum:** 🔴 Kritik — §8/§9 implemetasyonuna başlamadan önce tamamlanmalı

---

## Problem

`tier.py` doğru yazıldı (`is_paid_tier`, `PAID_TIERS`, çok-tier sabitler), ama backend'in geri kalanı
ve Flutter hâlâ eski "PRO/non-PRO" ikili modelini kullanıyor:

| Eski pattern | Doğru karşılık | Neden yanlış |
|---|---|---|
| `user_type == 'pro'` | `is_paid_tier(user_type)` | PRO+/PREMIUM kullanıcıları dışarıda kalır |
| `user_type != 'pro'` | `not is_paid_tier(user_type)` | Aynı |
| `receiver_type == "pro"` | `is_paid_tier(receiver_type)` | Gift geliri PRO+'a yanlış hesaplanır |
| `"is_pro": x == 'pro'` | `"user_type": x` | Semantic yanlış, Flutter'a tam tier gelmiyor |
| `_isPro: bool` (Flutter) | `_userType: String` | Sadece iki durum modeller, dört oluyor |
| `isPro: bool` (Flutter param) | kaldırılıp `userType: String` | Downstream widgetlar yanlış render eder |

---

## Backend: Düzeltilecek Dosyalar

### 🔴 Kritik Bug — Yanlış hesaplama

#### 1. `send_gift_command.py` — host hediye geliri
```python
# YANLIŞ: PRO+'lı ve PREMIUM yayıncı %70 alır (sadece 'pro' %95 alıyor)
_HOST_SHARE_PRO = 95
_HOST_SHARE_STD = 70
host_share_pct = _HOST_SHARE_PRO if receiver_type == "pro" else _HOST_SHARE_STD
```
```python
# DOĞRU: tier.py'daki COMMISSION_RATE kullan (PRO %75, PRO+ %90, PREMIUM %100)
from app.services.subscription.tier import commission_rate
host_share_pct = int(commission_rate(receiver_type) * 100)
```
**Not:** `_HOST_SHARE_PRO = 95` değeri de yanlış — `tier.py`'da PRO komisyonu %75 (0.75). Bu eski bir
değer, `tier.py` ile çelişiyor. `commission_rate()` fonksiyonuna devredince otomatik düzelir.

#### 2. `search_listings_query.py` — arama sıralama
```python
# YANLIŞ: Sadece PRO üste çıkar, PRO+ ve PREMIUM sıralamada standart ile aynı
(User.user_type == 'pro').desc()
```
```python
# DOĞRU: Herhangi bir ücretli tier üste çıkar
# SQLAlchemy: User.user_type.in_(['pro', 'pro_plus', 'premium']).desc()
# veya tier.py import ile: case(...)
(User.user_type != 'standard').desc()
```

#### 3. `streams.py:213` — ready_buyers count
```python
# YANLIŞ: Ready buyer = sadece 'pro' kullanıcı
ready_buyers = sum(1 for r in user_data if (r.user_type == 'pro'))
```
```python
# DOĞRU:
ready_buyers = sum(1 for r in user_data if r.user_type != 'standard')
```

### 🟡 Önemli — Ücretsiz limit mantığı yanlış tier'a uygulanıyor

#### 4. `get_reactivation_cost.py` ve `toggle_listing.py`
```python
# YANLIŞ: Sadece 'pro' ücretsiz reactivation hakkı alıyor
if current_user.user_type == 'pro':
    used = credit_service.get_used(...)
    is_free = used < credit_service.free_limit(...)
```
```python
# DOĞRU: Tüm ücretli tier'lar reactivation hakkı almalı
if is_paid_tier(current_user.user_type):
    used = ...
    is_free = used < credit_service.free_limit(...)
```

#### 5. `listings.py:865,877` — AI desc ve MONTHLY_LIMIT error code
```python
# YANLIŞ
if current_user.user_type != 'pro' or ai_used_new > _ai_desc_limit:
# YANLIŞ
code="MONTHLY_LIMIT_INSUFFICIENT_FUNDS" if current_user.user_type == 'pro' else "INSUFFICIENT_FUNDS"
```
```python
# DOĞRU
if not is_paid_tier(current_user.user_type) or ai_used_new > _ai_desc_limit:
code="MONTHLY_LIMIT_INSUFFICIENT_FUNDS" if is_paid_tier(current_user.user_type) else "INSUFFICIENT_FUNDS"
```

#### 6. `admin_data.py:244`
```python
# YANLIŞ: admin tier toggle — 'pro' olmayan → pro yapılıyor anlamına geliyor
is_now_pro = user.user_type != 'pro'
```
Bu satır admin paneline özgü — bağlamı incelenip ayrıca ele alınmalı.

### 🟢 Kabul Edilebilir — Backward compat için tutulacak

#### 7. API responses'taki `is_pro` alanı
Flutter hâlâ `summaryData['is_pro']` okuyor. İki yaklaşım:
- **A) `is_pro` kalsın ama `user_type` da eklensin** → Flutter `user_type`'a geçsin, `is_pro` deprecated
- **B) Sadece `user_type` dönsün** → Flutter güncellenmeden önce boş kalır

**Karar:** A seçeneği — `is_pro` kalsın (backward compat), `user_type` eklendi (zaten yapıldı).
Uzun vadede Flutter `is_pro`'yu bırakıp `user_type != 'standard'` kontrolüne geçsin.

---

## Flutter: Düzeltilecek Dosyalar

### 🔴 WalletScreen (`profile_screen.dart`)

| Şu an | Olmalı |
|---|---|
| `final bool isPro` (param) | `final String userType` |
| `bool _isPro` (state) | `String _userType` |  
| `_isPro = summaryData['is_pro']` | `_userType = summaryData['user_type']` |
| `isPro: _isPro` → widgetlara | `userType: _userType` |
| `_EarningsPill(isPro: _isPro)` | `_EarningsPill(userType: _userType)` |
| `_ProTab(isPro: _isPro)` | zaten `userType` eklendi ✅ |

### 🟡 CreateListingScreen

```dart
// YANLIŞ: sadece bool
bool _isPro = false;
// _isPro = isPro (StorageService'ten bool geliyor)
```
```dart
// DOĞRU
String _userType = 'standard';
// _userType = userType (StorageService'ten user_type string)
```

### 🟡 _EarningsPill widget

`isPro: bool` parametresi var — commission bilgisi için `userType: String` olmalı.

---

## `_HOST_SHARE_PRO = 95` Tutarsızlığı — Özel Durum

`tier.py`'da:
- PRO → 75% (0.75)
- PRO+ → 90% (0.90)  
- PREMIUM → 100% (1.00)

`send_gift_command.py`'da:
- PRO → 95% ← **TİER.PY İLE ÇAKIŞIYOR**
- STD → 70% ← **TİER.PY İLE ÇAKIŞIYOR (50%)**

Bu tarihi bir çelişki. `tier.py` V1.1 ile yazıldı, `send_gift_command.py` eski değerleri içeriyor.
**`commission_rate()` fonksiyonu tek kaynak olmalı** — `_HOST_SHARE_PRO` ve `_HOST_SHARE_STD`
sabitlerini kaldırıp `commission_rate(receiver_type)` fonksiyonuna devredilmeli.

---

## Eylem Sırası

1. ✅ **Belgeleme** — Bu dosya
2. 🔲 **Backend kritik buglar** — `send_gift_command`, `search_listings`, `streams`, `reactivation`, `listings`, `toggle_listing`
3. 🔲 **Flutter `_isPro` → `_userType`** — WalletScreen, CreateListingScreen, _EarningsPill
4. 🔲 **Test** — staging'de hediye gönderme, listing reactivation, arama sıralama

---

## Kapsam Dışı (Bu Refactoring'de Yapılmayacak)

- `admin_data.py` tier toggle — admin özelliği, ayrı analiz gerekiyor
- `is_pro` API field'ı kaldırılmayacak — Flutter backward compat için tutulacak
- `premium_since` field rename — kapsamlı migration, ayrı ADR gerektirir
