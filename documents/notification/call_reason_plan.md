# Call Permission Reason — Implementation Plan

> **Hedef:** Disabled arama butonu iki farklı duruma göre iki farklı toast göstersin
> **Yaklaşım:** Backend reason dönsün → client okusun → tahmin etmesin

---

## Sorun

`_compute_can_call()` şu an `bool` dönüyor. Client neden `false` olduğunu bilmiyor:
- **Durum A** — Takip ilişkisi yok (`no_follow`)
- **Durum B** — Accepted thread var ama acceptor call_allowed=False (`call_disabled`)

Client'ın `_followStatus` veya `callAllowed`'dan türetmesi:
- Stale state riski (sayfa yüklendikten sonra state değişebilir)
- Her ekranda ayrı türetme mantığı → tutarsızlık

---

## Mimari Karar

`_compute_can_call()` → `tuple[bool, CanCallReason | None]` döner.
Reason, API response ve WS event içinde taşınır.
Client hiçbir zaman reason'ı türetmez — her zaman sunucudan okur.

---

## Backend Tasks

### Task 1 — `CanCallReason` enum + `_compute_can_call()` güncelle

**Dosya:** `backend/app/services/calls_service.py` (veya `privacy_service.py`)

```python
from enum import StrEnum

class CanCallReason(StrEnum):
    NO_FOLLOW    = "no_follow"      # Takip ilişkisi yok
    CALL_DISABLED = "call_disabled" # Accepted thread var, call_allowed=False

def _compute_can_call(
    sender_id: int,
    receiver_id: int,
    thread: MessageThread | None,
    follows: ...,
) -> tuple[bool, CanCallReason | None]:
    # Mutual follow → True, reason=None
    # Follower→followed + accepted thread + call_allowed=True → True, reason=None
    # Accepted thread + call_allowed=False → False, reason=CALL_DISABLED
    # Hiç ilişki yok / accepted thread yok → False, reason=NO_FOLLOW
```

### Task 2 — Profil API `can_call_reason` ekle

**Dosya:** `backend/app/routers/users.py` (veya profile use_case)

Response'a `can_call_reason: str | None` eklenir.
`_compute_can_call()` tuple döndüğü için ikinci eleman direkt alınır.

```python
can_call, can_call_reason = _compute_can_call(...)
return {
    ...,
    "can_call": can_call,
    "can_call_reason": can_call_reason,  # "no_follow" | "call_disabled" | null
}
```

### Task 3 — Thread status API `can_call_reason` ekle

**Dosya:** `backend/app/use_cases/messages/queries/get_thread_status_query.py`

Thread status endpoint'i (`GET /api/messages/thread/{user_id}/status`) de
`can_call_reason` döner. `DirectChatRequestState` bu endpoint'ten besleniyor.

### Task 4 — `can_call_changed` WS event'e reason ekle

**Dosya:** `backend/app/services/calls_service.py` (can_call_changed broadcast kodu)

```python
await ws_manager.broadcast_local(f"dm:{user_id}", {
    "type": "can_call_changed",
    "user_id": other_user_id,
    "can_call": can_call,
    "reason": can_call_reason,  # ← eklenir
})
```

---

## Mobile Tasks

### Task 5 — `PublicProfileState` — `canCallReason` alanı

**Dosya:** `mobile/lib/screens/viewmodels/public_profile_view_model.dart`

```dart
class PublicProfileState {
  final bool canCall;
  final String? canCallReason; // "no_follow" | "call_disabled" | null
  ...
}
```

ViewModel `build()` içinde:
```dart
canCall: (data['can_call'] as bool?) ?? false,
canCallReason: data['can_call_reason'] as String?,
```

### Task 6 — `DirectChatRequestState` — `canCallReason` alanı

**Dosya:** `mobile/lib/screens/viewmodels/direct_chat_request_view_model.dart`

```dart
class DirectChatRequestState {
  final bool canCall;
  final String? canCallReason; // eklenir
  ...
}
```

`_fetch()` içinde:
```dart
canCallReason: data['can_call_reason'] as String?,
```

`updateCanCall()` metodu güncellenir:
```dart
void updateCanCall(bool canCall, String? reason) {
  // state.copyWith(canCall: canCall, canCallReason: reason)
}
```

WS handler (`messages_screen`):
```dart
if (type == 'can_call_changed') {
  final canCall = (data['can_call'] as bool?) ?? false;
  final reason = data['reason'] as String?;
  ref.read(...notifier).updateCanCall(canCall, reason);
}
```

### Task 7 — Shared helper: `callPermissionToast()`

**Dosya:** `mobile/lib/utils/call_permission_helper.dart` (yeni dosya)

```dart
void callPermissionToast(String? reason, TranslationPack loc) {
  final message = switch (reason) {
    'no_follow'    => loc.tOr('callReasonNoFollow', 'Aramak için takipleşmeniz gerekiyor'),
    'call_disabled'=> loc.tOr('callReasonCallDisabled', 'Karşı taraf aramaya izin vermemiş'),
    _              => loc.tOr('callReasonNoFollow', 'Aramak için takipleşmeniz gerekiyor'),
  };
  TeqToast.info(message);
}
```

Her iki ekranda aynı helper çağrılır — tek yer, tek mantık.

### Task 8 — UI: `public_profile_screen` + `messages_screen`

**`public_profile_screen.dart`:**
```dart
onPressed: _canCall
    ? () { /* startCall */ }
    : () => callPermissionToast(state.canCallReason, loc),
```

**`messages_screen.dart`:**
```dart
onPressed: canCall
    ? () { /* startCall */ }
    : () => callPermissionToast(requestState.canCallReason, loc),
```

---

## ARB / OTA Tasks

### Task 9 — ARB key'leri ekle (4 dil)

**Dosyalar:** `app_tr.arb`, `app_en.arb`, `app_ar.arb`, `app_ru.arb`

| Key | TR | EN |
|---|---|---|
| `callReasonNoFollow` | Aramak için takipleşmeniz gerekiyor | You need to follow each other to call |
| `callReasonCallDisabled` | Karşı taraf aramaya izin vermemiş | The other person has disabled calls |

Mevcut `callForbiddenInfo` key'i kaldırılır (artık kullanılmıyor).

Deploy: `sync_translations.py` → Redis cache otomatik invalidate edilir.

---

## Etkilenen Dosyalar

| Katman | Dosya | Değişiklik |
|---|---|---|
| Backend Domain | `calls_service.py` | `CanCallReason` enum + `_compute_can_call()` tuple |
| Backend Router | `users.py` | `can_call_reason` profile response'a eklenir |
| Backend Use Case | `get_thread_status_query.py` | `can_call_reason` thread status'a eklenir |
| Backend Service | WS broadcast | `can_call_changed` event'e `reason` eklenir |
| Mobile ViewModel | `public_profile_view_model.dart` | `canCallReason: String?` alanı |
| Mobile ViewModel | `direct_chat_request_view_model.dart` | `canCallReason` + `updateCanCall` güncellenir |
| Mobile Util | `call_permission_helper.dart` | `callPermissionToast()` helper (yeni) |
| Mobile UI | `public_profile_screen.dart` | helper çağrısı |
| Mobile UI | `messages_screen.dart` | helper çağrısı |
| ARB | 4 dil dosyası | `callReasonNoFollow` + `callReasonCallDisabled` |

---

## Neden Bu Mimari

| Karar | Alternatif | Neden bu |
|---|---|---|
| Backend reason dönsün | Client `_followStatus`'tan türetsin | Stale state yok, tek kaynak, her ekranda tutarlı |
| `CanCallReason` StrEnum | Plain string sabitleri | Tip güvenliği, IDE autocomplete, hata yakalanır |
| Shared `callPermissionToast()` helper | Her ekranda switch tekrarı | DRY — reason → mesaj mantığı tek yerde |
| WS event'e reason eklenir | Client mevcut state'ten türetir | Real-time geçişlerde doğru mesaj garantisi |
| `callForbiddenInfo` kaldırılır | İkisi birden yaşasın | Dead key bırakmamak; tek kaynak |

---

## Task Takibi

- [ ] Task 1 — `CanCallReason` enum + `_compute_can_call()` tuple
- [ ] Task 2 — Profil API `can_call_reason`
- [ ] Task 3 — Thread status API `can_call_reason`
- [ ] Task 4 — WS `can_call_changed` event reason
- [ ] Task 5 — `PublicProfileState.canCallReason`
- [ ] Task 6 — `DirectChatRequestState.canCallReason` + `updateCanCall`
- [ ] Task 7 — `callPermissionToast()` helper
- [ ] Task 8 — UI çağrıları
- [ ] Task 9 — ARB + deploy
