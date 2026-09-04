# Privacy V2.0 — Follow-Based Mesajlaşma & Arama İzni Uygulama Planı

> **Kaynak kararlar:** `documents/privacy/V2.0/privacy.md` — Karar 3 (güncellendi) + Karar 9 (yeni)
> **ADR referansı:** `documents/teqlif_architectural_decisions.md`
> **V1 planı:** `documents/privacy/PLAN.md` (önceki karar seti — Task 1–6 ayrı)
> **Son güncelleme:** 2026-09-04

---

## Mimari Prensipler

Bu plandaki tüm değişiklikler aşağıdaki ADR kurallarına uyar:

| Kural | Uygulama |
|-------|----------|
| **CQRS** — iş mantığı router'dan ayrı | Yeni business logic → `use_cases/*/commands/` veya `use_cases/*/queries/` |
| **AppException** — hata kodları | Her yeni hata kodu `AppException` subclass'ı ile eklenir, `ErrorMapper`'a eklenir |
| **OTA Localization** | Kullanıcıya gösterilen her string ARB'e eklenir, `sync_translations.py` ile deploy edilir |
| **Clean Router** | Router sadece auth, HTTP, use_case çağrısı yapar; sorgu/iş mantığı yazmaz |
| **TeqAsyncButton** | Async iş tetikleyen yeni butonlar `TeqAsyncButton` kullanır |
| **handleError + ErrorMapper** | Yeni backend hata kodları `ErrorMapper`'a eklenir |
| **MVVM** | Yeni state gerektiren mobile ekranlar `Notifier`/`AsyncNotifier` kullanır |

---

## Çalışma Kuralı

Her adımda sıra şu:
1. Yapılacakları kullanıcıya sun
2. Onay al
3. Implement et
4. Commit et
5. Bu dosyaya kayıt et

---

## Uygulama Sırası

| # | Alan | İş | Durum |
|---|------|-----|-------|
| 1 | DB | `message_threads` — `initiator_id` + `call_allowed` kolonları | ⬜ |
| 2 | Backend | Mesajlaşma — `is_request` mantığı follow-based'e güncelle | ⬜ |
| 3 | Backend | Follow kabul → pending thread auto-accept | ⬜ |
| 4 | Backend | Arama — `compute_can_call()` + `calls.py` kontrolü güncelle | ⬜ |
| 5 | Backend | Profil API — `can_call` + `is_followed_by` alanı ekle | ⬜ |
| 6 | Backend | Thread call-permission endpoint (`PATCH`) | ⬜ |
| 7 | Backend | WS — `can_call_changed` event | ⬜ |
| 8 | Mobile | `call_service.dart` — `CALL_FORBIDDEN` → teqToast | ⬜ |
| 9 | Mobile | `public_profile_screen.dart` — `can_call` kullan | ⬜ |
| 10 | Mobile | Mesaj thread ekranı — toggle + ⓘ ikonu + disabled call butonu | ⬜ |
| 11 | Mobile | Mesajlar ekranı — "Mesaj İstekleri" sekmesi | ⬜ |
| 12 | Deploy | Alembic + restart | ⬜ |

---

## Task 1 — DB: `message_threads` Yeni Kolonlar

**Migration adı:** `zzzo_msg_threads_v2` (≤32 karakter)

**Dosya:** `backend/alembic/versions/zzzo_msg_threads_v2.py`

```python
def upgrade() -> None:
    # initiator_id: thread'i kimin başlattığı — acceptor belirleme için kalıcı kayıt
    op.add_column('message_threads',
        sa.Column('initiator_id', sa.Integer(),
                  sa.ForeignKey('users.id', ondelete='SET NULL'),
                  nullable=True))

    # call_allowed: acceptor'ın arama toggle'ı, default OFF
    op.add_column('message_threads',
        sa.Column('call_allowed', sa.Boolean(), nullable=False,
                  server_default=sa.false()))

def downgrade() -> None:
    op.drop_column('message_threads', 'call_allowed')
    op.drop_column('message_threads', 'initiator_id')
```

**Model — `backend/app/models/message_thread.py`:**

```python
initiator_id: Mapped[int | None] = mapped_column(
    Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
)
call_allowed: Mapped[bool] = mapped_column(
    Boolean, nullable=False, server_default=false()
)
```

**Notlar:**
- `initiator_id` mevcut thread'lerde `NULL` kalır — kod `NULL` durumunu "bilinmiyor / izin yok" olarak ele alır.
- `call_allowed` mevcut thread'lerde `FALSE` — zaten doğru default (toggle kapalı).
- V1 PLAN'daki `zz_message_threads_01`'den sonra chain'e girer.

**Deploy:** `alembic upgrade head`. Backend/mobile değişiklik gerekmez.

---

## Task 2 — Backend: `is_request` Mantığı Follow-Based'e Güncelle

**Dosya:** `backend/app/use_cases/messages/commands/send_direct_message.py`

**Kural:** Alıcı göndereni takip etmiyorsa `is_request = True`. `is_private` artık bu kararı etkilemez.

**Mevcut kod (değişecek, ~satır 78–87):**

```python
is_req = False
if receiver.is_private:
    follow_accepted = await self.uow.session.scalar(
        select(Follow).where(
            Follow.follower_id == sender_id,
            Follow.followed_id == receiver_id,
            Follow.status == "accepted",
        )
    )
    if not follow_accepted:
        is_req = True
```

**Yeni kod:**

```python
receiver_follows_sender = await self.uow.session.scalar(
    select(Follow).where(
        Follow.follower_id == receiver_id,
        Follow.followed_id == sender_id,
        Follow.status == "accepted",
    )
)
is_req = not bool(receiver_follows_sender)

if not existing_thread:
    self.uow.session.add(MessageThread(
        user_a_id=min(sender_id, receiver_id),
        user_b_id=max(sender_id, receiver_id),
        is_request=is_req,
        initiator_id=sender_id,
        call_allowed=False,
    ))
    if is_req:
        redis = await get_redis()
        await redis.incr(f"msg:unread:request:{receiver_id}")
```

**Davranış değişim tablosu:**

| Senaryo | Eski | Yeni |
|---------|------|------|
| Karşılıklı follow | Direkt | Direkt ✓ |
| A→B follow, sender=A (takip eden mesaj atıyor) | Direkt ❌ | İstek ✓ |
| A→B follow, sender=B (takip edilen mesaj atıyor) | Direkt | Direkt ✓ |
| Gizli hesap, takipçi değil | İstek | İstek ✓ |
| Follow yok | Direkt ❌ | İstek ✓ |

**Deploy:** Backend restart. Task 1 tamamlanmış olmalı.

---

## Task 3 — Backend: Follow Accept + `auth.py` Temizliği

### 3.1 `follows.py` — Değişiklik Yok, Kapsam Genişliyor

V1 PLAN Task 5.4'teki auto-accept kodu (`follows.py` accept endpoint) olduğu gibi çalışıyor:

```python
user_a, user_b = min(follower_id, current_user.id), max(follower_id, current_user.id)
await db.execute(
    update(MessageThread)
    .where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
        MessageThread.status == "pending",
    )
    .values(status="accepted")
)
redis = await get_redis()
await redis.decr(f"msg:unread:request:{current_user.id}")
```

Task 2 sonrasında public hesaplar arası thread'ler de `pending` düşebileceği için bu satırlar artık her follow kabulünde kritik. Kod değişmez, etki alanı genişler.

### 3.2 `auth.py` — `is_private=False` Geçiş Bloğu Silinir

**Dosya:** `backend/app/routers/auth.py` — PATCH /auth/me

V1 PLAN Task 5.5'teki şu blok tamamen kaldırılır:

```python
# KALDIRILACAK — is_private artık thread tipini belirlemez
if "is_private" in body and not body["is_private"] and current_user.is_private:
    await db.execute(
        update(MessageThread)
        .where(
            or_(
                MessageThread.user_a_id == current_user.id,
                MessageThread.user_b_id == current_user.id,
            ),
            MessageThread.status == "pending",
        )
        .values(status="accepted")
    )
    redis = await get_redis()
    await redis.delete(f"msg:unread:request:{current_user.id}")
```

`is_private` toggle'ı artık thread state'ini etkilemez. Kullanıcı hesabını açık yaptığında mevcut pending thread'ler olduğu gibi kalır.

**Deploy:** Backend restart. Migration yok.

---

## Task 4 — Backend: `compute_can_call()` + `GetThreadStatusQuery` + `calls.py`

### 4.1 `compute_can_call()` Helper

**Dosya:** `backend/app/use_cases/messages/queries/get_thread_status_query.py`

Mevcut dosyanın başına helper fonksiyon eklenir:

```python
def _compute_can_call(
    viewer_follows_target: bool,
    target_follows_viewer: bool,
    thread_status: str | None,
    call_allowed: bool,
) -> bool:
    """caller=viewer, callee=target perspektifinden can_call hesaplar."""
    # Mutual follow
    if viewer_follows_target and target_follows_viewer:
        return True
    # Takip edilen (viewer) → Takipçi (target): her zaman arayabilir
    if target_follows_viewer and not viewer_follows_target:
        return True
    # Takipçi (viewer) → Takip edilen (target): toggle kontrolü
    if viewer_follows_target and not target_follows_viewer:
        return call_allowed if thread_status == "accepted" else False
    # Follow yok — kabul edilmiş thread + toggle
    if thread_status == "accepted":
        return call_allowed
    return False
```

### 4.2 `GetThreadStatusQuery` Güncellemesi

Mevcut mutual-follow-only `can_call` hesabı kaldırılır, helper kullanılır:

```python
async def execute(self, uid: int, other_id: int) -> dict:
    user_a, user_b = min(uid, other_id), max(uid, other_id)
    thread = await self.uow.session.scalar(
        select(MessageThread).where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
        )
    )

    follows_other = await self.uow.session.scalar(
        select(Follow).where(
            Follow.follower_id == uid, Follow.followed_id == other_id,
            Follow.status == "accepted"
        )
    )
    followed_by_other = await self.uow.session.scalar(
        select(Follow).where(
            Follow.follower_id == other_id, Follow.followed_id == uid,
            Follow.status == "accepted"
        )
    )

    can_call = _compute_can_call(
        viewer_follows_target=follows_other is not None,
        target_follows_viewer=followed_by_other is not None,
        thread_status=thread.status if thread else None,
        call_allowed=thread.call_allowed if thread else False,
    )

    if not thread:
        return {"status": None, "is_initiator": False, "can_call": can_call}
    return {
        "status": thread.status,
        "is_initiator": thread.initiator_id == uid,
        "can_call": can_call,
        "call_allowed": thread.call_allowed,  # acceptor toggle state'i için
    }
```

### 4.3 `calls.py` — Mutual Follow Guard Güncellenmesi

**Dosya:** `backend/app/routers/calls.py` — satır 520–532

```python
# MEVCUT — DEĞİŞECEK
follows_callee = await db.scalar(...)
followed_by_callee = await db.scalar(...)
if follows_callee is None or followed_by_callee is None:
    raise AppException(status_code=403, code="CALL_FORBIDDEN")
```

**Yeni:**

```python
from app.use_cases.messages.queries.get_thread_status_query import (
    GetThreadStatusQuery, _compute_can_call
)

follows_callee = await db.scalar(
    select(Follow).where(
        Follow.follower_id == current_user.id,
        Follow.followed_id == callee_id,
        Follow.status == "accepted",
    )
)
followed_by_callee = await db.scalar(
    select(Follow).where(
        Follow.follower_id == callee_id,
        Follow.followed_id == current_user.id,
        Follow.status == "accepted",
    )
)
user_a, user_b = min(current_user.id, callee_id), max(current_user.id, callee_id)
thread = await db.scalar(
    select(MessageThread).where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
    )
)
can_call = _compute_can_call(
    viewer_follows_target=follows_callee is not None,
    target_follows_viewer=followed_by_callee is not None,
    thread_status=thread.status if thread else None,
    call_allowed=thread.call_allowed if thread else False,
)
if not can_call:
    logger.info(
        "[CALL_PROCESS][OUT] start_call REJECTED | reason=call_forbidden caller=%d callee=%d",
        current_user.id, callee_id,
    )
    raise AppException(status_code=403, code="CALL_FORBIDDEN")
```

**Deploy:** Backend restart. Migration yok (Task 1 tamamlanmış olmalı).

---

## Task 5 — Backend: Profil API `can_call` + `is_followed_by`

**Dosya:** `backend/app/use_cases/users/queries/get_user_profile.py`

Mevcut `follow_status` / `is_following` hesabından (~satır 54–60) sonra:

```python
# is_followed_by: target, current_user'ı takip ediyor mu?
is_followed_by = False
if current_user:
    followed_by_row = await self.uow.session.scalar(
        select(Follow).where(
            Follow.follower_id == target.id,
            Follow.followed_id == current_user.id,
            Follow.status == "accepted",
        )
    )
    is_followed_by = followed_by_row is not None
    profile_data["is_followed_by"] = is_followed_by

# can_call: current_user → target araması mümkün mü?
if current_user and current_user.id != target.id:
    from app.use_cases.messages.queries.get_thread_status_query import _compute_can_call
    user_a, user_b = min(current_user.id, target.id), max(current_user.id, target.id)
    thread = await self.uow.session.scalar(
        select(MessageThread).where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
        )
    )
    profile_data["can_call"] = _compute_can_call(
        viewer_follows_target=profile_data.get("is_following", False),
        target_follows_viewer=is_followed_by,
        thread_status=thread.status if thread else None,
        call_allowed=thread.call_allowed if thread else False,
    )
else:
    profile_data["can_call"] = False
```

**Mobile:** `public_profile_screen.dart` — profil verisi yüklendiğinde `_canCall` state'ine set edilir (bkz. Task 9).

**Deploy:** Backend restart. Migration yok.

---

## Task 6 — Backend: Call-Permission Toggle Endpoint

**Dosya:** `backend/app/routers/messages.py`

```python
from app.models.message_thread import MessageThread

class CallPermissionBody(BaseModel):
    call_allowed: bool

@router.patch("/thread/{other_user_id}/call-permission")
async def update_call_permission(
    other_user_id: int,
    body: CallPermissionBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_a, user_b = min(current_user.id, other_user_id), max(current_user.id, other_user_id)
    thread = await db.scalar(
        select(MessageThread).where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
            MessageThread.status == "accepted",
        )
    )
    if not thread:
        raise NotFoundException(code="THREAD_NOT_FOUND")

    # Yalnızca acceptor (initiator olmayan) toggle yapabilir
    if thread.initiator_id == current_user.id:
        raise ForbiddenException(code="CALL_PERMISSION_NOT_YOURS")

    thread.call_allowed = body.call_allowed
    await db.commit()

    # WS: initiator'a can_call_changed gönder (Task 7)
    await _broadcast_can_call_changed(
        to_user_id=thread.initiator_id,
        from_user_id=current_user.id,
        can_call=body.call_allowed,
    )

    return {"call_allowed": thread.call_allowed}
```

**ErrorMapper (mobile):**

```dart
case 'CALL_PERMISSION_NOT_YOURS':
  return loc.t('callPermissionNotYours');
case 'THREAD_NOT_FOUND':
  return loc.t('threadNotFound');
```

**ARB:**

```json
"callPermissionNotYours": "Arama iznini yalnızca karşı taraf değiştirebilir",
"threadNotFound": "Konuşma bulunamadı"
```

**Deploy:** Backend restart. Migration yok.

---

## Task 7 — Backend: WS `can_call_changed` Event

### 7.1 Broadcast Yardımcı Fonksiyon

**Dosya:** `backend/app/routers/messages.py` (veya `ws_utils.py` — mevcut broadcast altyapısı neredeyse oraya)

```python
async def _broadcast_can_call_changed(
    to_user_id: int,
    from_user_id: int,
    can_call: bool,
) -> None:
    """Initiator'a toggle değişimini bildir."""
    payload = {
        "type": "can_call_changed",
        "user_id": from_user_id,   # kimin toggle'ı değiştirdiği / follow'u değişti
        "can_call": can_call,
    }
    await broadcast_dm(to_user_id, payload)
```

### 7.2 Follow Değişiminde Tetikleme

**Dosya:** `backend/app/routers/follows.py` — follow accept / unfollow endpoint'leri

Follow kabul veya iptali durumunda, ilgili thread varsa her iki tarafa `can_call_changed` gönderilir:

```python
# Follow accept sonrası:
# A, B'nin takip isteğini kabul etti → B artık A'yı takip ediyor
# Bu mutual follow'a yol açabilir → A'nın B'yi arama izni değişir
# B'ye: A artık seni arayabilir mi?
# A'ya: B'nin seni arama durumu değişti mi?
await _broadcast_can_call_changed_if_thread(follower_id, current_user.id, db)
```

Benzer şekilde unfollow / follow request cancel durumlarında tetiklenir.

### 7.3 Mobile: WS Event Dinleme

**Dosya:** `mobile/lib/screens/viewmodels/direct_chat_request_view_model.dart`

`DirectChatRequestNotifier`'a WS event listener eklenir:

```dart
// ws_service.dart'tan gelen can_call_changed event'ini dinle
void _onCanCallChanged(Map<String, dynamic> data) {
  final userId = data['user_id'] as int;
  if (userId != arg) return;  // arg = otherUserId
  final canCall = data['can_call'] as bool;
  final current = state.value;
  if (current == null) return;
  state = AsyncValue.data(current.copyWith(canCall: canCall));
}
```

**Deploy:** Backend restart. Mobile rebuild.

---

## Task 8 — Mobile: `call_service.dart` — `CALL_FORBIDDEN` Toast

### 8.1 `EndReason` Enum

**Dosya:** `mobile/lib/call/state/end_reason.dart`

```dart
enum EndReason {
  normal,
  rejected,
  missed,
  noAnswer,
  busy,
  permissionDenied,
  error,
  unreachable,
  callForbidden,  // ← yeni: arama iznin yok
}
```

### 8.2 `call_service.dart` — AppException Handler

**Dosya:** `mobile/lib/services/call_service.dart` — satır 333–341

```dart
} on AppException catch (e) {
  _cpLog('OUT', 'startCall AppException | code=${e.code}');
  if (e.code == 'USER_BUSY') {
    _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.busy));
    _scheduleReset();
  } else if (e.code == 'CALL_FORBIDDEN') {             // ← yeni
    _cpLog('OUT', 'CALL_FORBIDDEN → teqToast');
    _setState(state.value.copyWith(status: CallStatus.ended, endReason: EndReason.callForbidden));
    _scheduleReset();
    TeqToast.show(loc.t('callForbiddenToast'));        // ← toast göster
  } else {
    _setState(state.value.copyWith(status: CallStatus.ended));
    _scheduleReset();
  }
}
```

**ARB:**

```json
"callForbiddenToast": "Bu kullanıcıyı şu an arayamazsın"
```

**Deploy:** Mobile rebuild.

---

## Task 9 — Mobile: `public_profile_screen.dart` — `can_call` Kullan

**Dosya:** `mobile/lib/screens/public_profile_screen.dart`

### 9.1 State Değişkeni

```dart
// Mevcut:
String _followStatus = 'none';

// Yeni (ekle):
bool _canCall = false;
```

### 9.2 Profil Yüklendiğinde Set Et

Profil API response'u yüklendiğinde (~satır 141):

```dart
_followStatus = state.followStatus;
_canCall = state.canCall ?? false;   // ← profil API'dan gelen can_call
```

### 9.3 Call Butonu Koşulu

**Satır 172 (public profil call butonu):**

```dart
// MEVCUT:
if (_followStatus == 'accepted')
  IconButton(icon: Icon(Icons.call), ...)

// YENİ:
if (_canCall)
  IconButton(icon: Icon(Icons.call), ...)
```

**Satır 442 (mesajlar kısmındaki call aksiyonu, varsa):**

Aynı `_followStatus == 'accepted'` → `_canCall` değişimi uygulanır.

**Not:** `can_call` profil API'dan zaten geliyor (Task 5 sonrası). Mobile'da yeni bir endpoint çağrısı gerekmez.

**Deploy:** Mobile rebuild.

---

## Task 10 — Mobile: Mesaj Thread Ekranı — Toggle + ⓘ İkonu

**Dosya:** `mobile/lib/screens/messages_screen.dart`

### 10.1 Mevcut Durum

Satır 2135–2162: `canCall=false` ise call butonu tamamen gizleniyor (`SizedBox.shrink()`).

### 10.2 Yeni Davranış

```
canCall=true                     → ✅ Aktif call butonu (değişmez)
canCall=false, isInitiator=true  → ⓘ ikonu + disabled call butonu
canCall=false, isInitiator=false → toggle + ⓘ ikonu + disabled call butonu
```

### 10.3 Kod Değişikliği

```dart
Consumer(
  builder: (context, ref, _) {
    final requestState = ref.watch(directChatRequestProvider(widget.otherUserId));
    final state = requestState.valueOrNull;
    final canCall = state?.canCall ?? false;
    final isInitiator = state?.isInitiator ?? true;
    final callAllowed = state?.callAllowed ?? false;

    if (canCall) {
      // Aktif call butonu (mevcut kod korunur)
      return IconButton(
        icon: const Icon(Icons.call, size: 22),
        onPressed: () => _startCall(),
      );
    }

    // canCall=false — thread accepted ama izin yok
    if (state?.status != 'accepted') return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isInitiator)
          // Acceptor: toggle göster
          Switch(
            value: callAllowed,
            onChanged: (val) => ref
                .read(directChatRequestProvider(widget.otherUserId).notifier)
                .setCallAllowed(val),
          ),
        // ⓘ ikonu
        IconButton(
          icon: const Icon(Icons.info_outline, size: 20),
          tooltip: isInitiator
              ? loc.t('callPermissionInfo')
              : loc.t('callPermissionDefaultOff'),
          onPressed: () => TeqToast.show(
            isInitiator
                ? loc.t('callPermissionInfo')
                : loc.t('callPermissionDefaultOff'),
          ),
        ),
        // Disabled call butonu
        IconButton(
          icon: Icon(Icons.call, size: 22, color: Theme.of(context).disabledColor),
          onPressed: null,
        ),
      ],
    );
  },
),
```

### 10.4 `DirectChatRequestState` Güncellemesi

**Dosya:** `mobile/lib/screens/viewmodels/direct_chat_request_view_model.dart`

```dart
class DirectChatRequestState {
  // ... mevcut alanlar
  final bool callAllowed;   // ← yeni: acceptor toggle state'i

  const DirectChatRequestState({
    // ...
    this.callAllowed = false,
  });
}
```

`_fetch()` içinde `data['call_allowed']` set edilir (Task 4.2'de endpoint'e eklendi).

`setCallAllowed()` methodu:

```dart
Future<void> setCallAllowed(bool val) async {
  final current = state.value;
  if (current == null) return;
  state = AsyncValue.data(current.copyWith(callAllowed: val, canCall: val));
  try {
    await NotificationService.updateCallPermission(arg, val);
  } catch (e) {
    // Rollback
    state = AsyncValue.data(current);
    handleError(e, ref.read(localizationProvider));
  }
}
```

**`NotificationService`'e eklenecek:**

```dart
static Future<void> updateCallPermission(int otherUserId, bool callAllowed) async {
  await _safeCall(
    () async => http.patch(
      Uri.parse('$kBaseUrl/messages/thread/$otherUserId/call-permission'),
      headers: await _headers(),
      body: jsonEncode({'call_allowed': callAllowed}),
    ),
  );
}
```

**ARB:**

```json
"callPermissionInfo":      "Karşılıklı takip olmadığı için arama iznini karşı taraf verebilir",
"callPermissionDefaultOff": "Arama özelliği varsayılan olarak kapalıdır",
"callToggleLabel":          "Arama İzni"
```

**Deploy:** Mobile rebuild.

---

## Task 11 — Mobile: Mesajlar Ekranı — "Mesaj İstekleri" Sekmesi

V1 PLAN Task 5.6–5.9 büyük ölçüde geçerlidir. V2'de fark şudur: `status='pending'` artık yalnızca gizli hesaplardan değil, follow ilişkisine göre **tüm hesaplardan** gelebilir.

UI değişikliği gerekmez — mevcut `_RequestBanner`, `requestsTabViewModelProvider`, accept/decline akışı değişmeden çalışır.

**Güncellenen içerik:**

ARB stringi güncellenir (V1'den farklı):

```json
"messageRequestsHint": "Seni takip etmeyen kişilerden gelen mesajlar"
```

(V1'de "Takipçi olmayan" yazmaktaydı — V2'de anlam daha doğru: "seni takip etmeyen".)

**Deploy:** `sync_translations.py` → Mobile rebuild.

---

## ARB Anahtarları — V2 Yeni / Güncellenen Key'ler

| Key | Task | Türkçe |
|-----|------|--------|
| `callForbiddenToast` | 8 | Bu kullanıcıyı şu an arayamazsın |
| `callPermissionNotYours` | 6 | Arama iznini yalnızca karşı taraf değiştirebilir |
| `callPermissionInfo` | 10 | Karşılıklı takip olmadığı için arama iznini karşı taraf verebilir |
| `callPermissionDefaultOff` | 10 | Arama özelliği varsayılan olarak kapalıdır |
| `callToggleLabel` | 10 | Arama İzni |
| `threadNotFound` | 6 | Konuşma bulunamadı |
| `messageRequestsHint` | 11 | Seni takip etmeyen kişilerden gelen mesajlar *(V1'den güncellendi)* |

**Toplam:** 7 key (6 yeni + 1 güncelleme)

---

## Migration Özeti

| Migration | Task | Değişiklik |
|-----------|------|-----------|
| `zzzo_msg_threads_v2` | Task 1 | `message_threads.call_allowed BOOLEAN NOT NULL DEFAULT FALSE` |

Diğer task'lar için migration gerekmez.

---

## Deploy Sırası

**Task 1 (migration):**

```bash
git pull && alembic upgrade head && sudo systemctl restart teqlif teqlif-staging
```

**Task 2–7 (backend only):**

```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif teqlif-staging
```

**Task 8–11 (mobile + çeviri):**

```bash
# VPS:
python3 scripts/sync_translations.py

# Local:
flutter build ipa --dart-define-from-file=dart_defines/production.json
```

**Tam sıra:**

```
Task 1 → deploy (migration)
Task 2–7 → deploy (backend restart)
Task 8–11 → deploy (mobile build + sync_translations)
```
