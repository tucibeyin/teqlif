# Privacy & Block — Implementasyon Planı

> **Kaynak kararlar:** `documents/privacy/privacy.md`
> **ADR referansı:** `documents/teqlif_architectural_decisions.md`
> **Son güncelleme:** 2026-09-01

---

## Mimari Prensipler

Bu plandaki tüm değişiklikler aşağıdaki ADR kurallarına uyar:

| Kural | Uygulama |
|-------|----------|
| **CQRS** — iş mantığı router'dan ayrı | Yeni business logic → `use_cases/*/commands/` veya `use_cases/*/queries/` |
| **AppException** — hata kodları | Her yeni hata kodu `AppException` subclass'ı ile eklenir, `ErrorMapper`'a eklenir |
| **OTA Localization** | Kullanıcıya gösterilen her string ARB'e eklenir, `sync_translations.py` ile deploy edilir |
| **bump_schema_version()** | `catalog / cities / field_config` etkileyen migration'larda zorunlu — bu planda bu tablolar etkilenmez, gerek yok |
| **Clean Router** | Router sadece auth, HTTP, use_case çağrısı yapar; sorgu/iş mantığı yazmaz |
| **TeqAsyncButton** | Async iş tetikleyen yeni butonlar `TeqAsyncButton` kullanır |
| **handleError + ErrorMapper** | Yeni backend hata kodları `ErrorMapper`'a eklenir |
| **MVVM** | Yeni state gerektiren mobile ekranlar (Mesaj İstekleri sekmesi) `Notifier`/`AsyncNotifier` kullanır |

---

## Uygulama Sırası

```
Task 1  Bug Fix 1      story_service.py — pending follow fix + block filtresi, migration yok
Task 2  Karar 2        get_user_profile.py — profil gating, migration yok
Task 3  Karar 4        follows.py — follower/following liste gating, migration yok
Task 4  Karar 6        Block sistem backend düzeltmeleri, migration yok
Task 5  Karar 3        Mesaj İstekleri — yeni tablo (migration), en kapsamlı değişiklik
Task 6  Karar 5        Privacy banner — mobile-only, migration yok
```

---

## Task 1 — Bug Fix 1 + Karar 7: Story Tray

**Dosya:** `backend/app/services/story_service.py`

İki ayrı düzeltme aynı sorgulara uygulanır.

### 1a. Pending Follow Bug Fix

`Follow.status == "accepted"` filtresi her iki sorguya eklenir.

### 1b. Block Filtresi (Karar 7)

Engelleme iki yönlü çalışır: engellenen engelleyenin story'lerini göremez; engelleyen de engellediği kişinin story'lerini görmez.

**Adım A — Video sorgusu (~satır 125):**

```python
from app.models.block import UserBlock

_blocked_users = (
    select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    .union_all(
        select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    )
)

video_query = (
    select(Story, User)
    .join(User, User.id == Story.user_id)
    .join(Follow, Follow.followed_id == Story.user_id)
    .where(
        Follow.follower_id == current_user_id,
        Follow.status == "accepted",         # Bug Fix 1
        Story.expires_at > func.now(),
        Story.user_id.not_in(_blocked_users),  # Karar 7
    )
    .order_by(Story.created_at.asc())
)
```

**Adım B — Canlı yayın sorgusu (~satır 149):**

```python
live_query = (
    select(LiveStream, User)
    .join(User, User.id == LiveStream.host_id)
    .join(Follow, Follow.followed_id == LiveStream.host_id)
    .where(
        Follow.follower_id == current_user_id,
        Follow.status == "accepted",             # Bug Fix 1
        LiveStream.is_live == True,
        LiveStream.host_id.not_in(_blocked_users),  # Karar 7
    )
)
```

**Deploy:** Backend restart. Migration yok. Mobile değişiklik yok.

---

## Task 2 — Karar 2: Backend Profil API Gating

**Dosya:** `backend/app/use_cases/users/queries/get_user_profile.py`

### 2.1 Gating Mantığı

Mevcut blok kontrollerinden (~satır 76) sonra, `follower_count` sorgusu yapılmadan önce:

```python
if target.is_private:
    is_following_accepted = await self.uow.session.scalar(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.followed_id == target.id,
            Follow.status == "accepted",
        )
    ) if current_user else None

    if not is_following_accepted and (not current_user or current_user.id != target.id):
        return {
            "id": target.id,
            "username": target.username,
            "avatar_url": target.profile_image_url,
            "is_private": True,
            "is_premium": target.is_premium,
            "is_verified": target.is_verified,
            "badge": target.badge,
            "trust_score": target.trust_score,
            "active_listings_count": ...,   # mevcut sayım sorgusu korunur
            "follow_status": ...,           # mevcut follow_status hesabı korunur
            "is_blocked": profile_data["is_blocked"],
            "is_live": target.is_live,
            "active_stream_id": target.active_stream_id,
            # bio, full_name, sosyal linkler, follower_count, following_count → döndürülmez
        }
```

### 2.2 Redis Cache Invalidation

**Dosya:** `backend/app/routers/auth.py` — PATCH /auth/me endpoint'i

```python
if "is_private" in body and body["is_private"] != current_user.is_private:
    redis = await get_redis()
    await redis.delete(f"user:profile:{current_user.id}")
```

**Deploy:** Backend restart. Migration yok.

---

## Task 3 — Karar 4: Follower/Following Liste Gizliliği

**Dosya:** `backend/app/routers/follows.py`

### 3.1 Liste Endpoint'lerine Gating

`GET /api/follows/{user_id}/followers` ve `GET /api/follows/{user_id}/following`:

```python
if target.is_private and current_user.id != target.id:
    is_following = await db.scalar(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.followed_id == target.id,
            Follow.status == "accepted",
        )
    )
    if not is_following:
        raise ForbiddenException(code="FOLLOWERS_LIST_PRIVATE")
```

### 3.2 ErrorMapper

**Dosya:** `mobile/lib/core/error_mapper.dart`

```dart
case 'FOLLOWERS_LIST_PRIVATE':
  return loc.t('followListPrivate');
```

### 3.3 Mobile — Follower Sayısına Tıklama Engeli

`public_profile_screen.dart` — follower/following sayısına tıklama:

```dart
// Tıklama yalnızca erişim izni varsa tetiklenir:
final canViewList = !_isPrivate || _followStatus == 'accepted' || _isOwnProfile;

GestureDetector(
  onTap: canViewList ? () => _openFollowList(type) : null,
  child: _buildFollowCount(...),
)
```

Backend 403 gelirse `handleError(e, loc)` → ErrorMapper mesajı gösterir.

### 3.4 ARB

```json
"followListPrivate":     "Bu liste gizlidir",
"followListPrivateDesc": "Listeyi görmek için takip et"
```

**Deploy:** Backend restart. Migration yok.

---

## Task 4 — Karar 6 + Karar 8: Block Sistem Backend Düzeltmeleri

Beş bağımsız backend değişikliği. Migration gerektirmez.

---

### 4a. İlan Detay — Teklif Ver Butonu (Disabled)

**Backend — `backend/app/use_cases/listings/commands/create_offer.py`:**

`SELF_BID_FORBIDDEN` kontrolünden sonra:

```python
from app.models.block import UserBlock
from sqlalchemy import or_, and_

block_exists = await self.uow.session.scalar(
    select(UserBlock).where(
        or_(
            and_(UserBlock.blocker_id == listing.user_id, UserBlock.blocked_id == current_user.id),
            and_(UserBlock.blocker_id == current_user.id, UserBlock.blocked_id == listing.user_id),
        )
    )
)
if block_exists:
    raise ForbiddenException(code="OFFER_FORBIDDEN")
```

**Backend — `backend/app/use_cases/listings/queries/get_listing_details_query.py`:**

Response dict'e `seller_is_blocked: bool` alanı eklenir:

```python
seller_is_blocked = await _check_block(session, current_user.id, listing.user_id)
# response dict:
"seller_is_blocked": seller_is_blocked,
```

**Mobile — `listing_detail_screen.dart`:**

```dart
// API'den gelen seller_is_blocked ile buton disabled edilir
TeqAsyncButton(
  isDisabled: _sellerIsBlocked,
  onPressed: _sellerIsBlocked ? null : _makeOffer,
  text: loc.t('makeOffer'),
)
```

**ErrorMapper:**

```dart
case 'OFFER_FORBIDDEN': return loc.t('offerBlockedError');
```

**ARB:**

```json
"offerBlockedError": "Bu kullanıcıyla işlem yapamazsınız"
```

---

### 4b. Arama — İlan Block Filtresi Kaldırma

**Dosya:** `backend/app/routers/search.py`

`_block_filters` fonksiyonu ilan sonuçlarına uygulanmıyor — yalnızca kullanıcı ve yayın sonuçlarında kalıyor.

**Kaldırılacak satırlar:**

```python
# GET /api/search/explore — text search (satır ~264):
listing_q = _block_filters(listing_q, Listing.user_id, current_user_id)  # ← kaldır

# GET /api/search/listings (satır ~467):
stmt = _block_filters(stmt, Listing.user_id, current_user_id)  # ← kaldır

# Semantic/raw SQL yollarında (~satır 278-282 ve ~358-364):
block_clause = """
    AND l.user_id NOT IN (
        SELECT blocked_id FROM user_blocks ...
    )
"""
# Bu block_clause'lar listing sorguları için oluşturuluyorsa → kaldır
```

**Korunan (değişmez):**

```python
# Kullanıcı araması (satır ~71, ~219):
query = _block_filters(query, User.id, current_user_id)  # ← kalır

# Yayın araması (satır ~155, ~242):
stream_q = _block_filters(stream_q, LiveStream.host_id, current_user_id)  # ← kalır
```

---

### 4c. Canlı Yayın — WebSocket Katılımda Otomatik Susturma

**Dosya:** `backend/app/routers/chat.py`

Adım 4 (kick kontrolü, ~satır 346) ile adım 5 (session limit, ~satır 363) arasına:

```python
# ── 4.5 Block kontrolü → otomatik mute ───────────────────────────────────
if not is_host:
    try:
        async with AsyncSessionLocal() as _db:
            from app.models.block import UserBlock
            from sqlalchemy import or_, and_
            _block = await _db.scalar(
                select(UserBlock).where(
                    or_(
                        and_(UserBlock.blocker_id == host_id, UserBlock.blocked_id == user_id),
                        and_(UserBlock.blocker_id == user_id, UserBlock.blocked_id == host_id),
                    )
                )
            )
        if _block:
            redis = await get_redis()
            from app.services.moderation_service import mute_key
            await redis.sadd(mute_key(stream_id), str(user_id))
            logger.info(
                "[CHAT WS] Block nedeniyle otomatik mute | stream=%s user=%s host=%s",
                stream_id, user_id, host_id,
            )
    except Exception as exc:
        logger.warning("[CHAT WS] Block-mute kontrolü başarısız | %s", exc)
```

---

### 4d. Canlı Yayın — Host Viewer Listesinde Block Filtresi

**Dosya:** `backend/app/use_cases/streams/queries/get_viewers.py`

`redis.smembers(...)` sonrasına:

```python
members = await redis.smembers(f"live:viewer_set:{stream_id}")

if members:
    from app.models.block import UserBlock
    from sqlalchemy import or_, and_
    member_ids = [int(m) for m in members]
    blocked_rows = await self.uow.session.execute(
        select(UserBlock.blocked_id, UserBlock.blocker_id).where(
            or_(
                and_(UserBlock.blocker_id == user.id, UserBlock.blocked_id.in_(member_ids)),
                and_(UserBlock.blocked_id == user.id, UserBlock.blocker_id.in_(member_ids)),
            )
        )
    )
    blocked_set = set()
    for row in blocked_rows.all():
        blocked_set.add(row.blocked_id)
        blocked_set.add(row.blocker_id)
    blocked_set.discard(user.id)
    members = {m for m in members if int(m) not in blocked_set}

return {"viewers": sorted(list(members))}
```

---

### 4e. Canlı Yayın /following/live — Block Filtresi (Karar 8)

**Dosya:** `backend/app/use_cases/streams/queries/misc_queries.py`

**Mevcut durum:** `GetFollowedLiveStreamsQuery`'de `_apply_block_filter` import edilmiş ama kullanılmıyor. `GetActiveStreamsQuery` (satır 57) ve `GetRecommendedStreamsQuery`'de uygulanmış — bu endpoint'te eksik kalmış.

**Fix:**

```python
async def execute(self, current_user_id: int) -> list:
    query = (
        select(LiveStream)
        .join(Follow, Follow.followed_id == LiveStream.host_id)
        .where(
            Follow.follower_id == current_user_id,
            LiveStream.is_live == True,
        )
        .order_by(LiveStream.started_at.desc())
    )
    query = _apply_block_filter(query, LiveStream.host_id, current_user_id)  # ← ekle
    # ... geri kalan kod değişmez
```

**Deploy:** Backend restart. Migration yok.

---

## Task 5 — Karar 3: Mesaj İstekleri Sistemi

**En kapsamlı değişiklik — DB migration gerektirir.**

---

### 5.1 Mevcut Durum

`direct_messages` tablosu: `sender_id, receiver_id, content, ...` — her mesaj ayrı satır. Konuşma (thread) kavramı yok. `is_request` durumunu pair başına tutmak için yeni `message_threads` tablosu gerekir.

**Cooldown yok.** Engellenen kişinin mesajlaşması block mekanizmasıyla (`messages.py:306` — mevcut `ForbiddenException`) zaten engelleniyor. Reddetme sonrası ek cooldown uygulanmaz.

---

### 5.2 DB Migration

**Migration adı:** `zz_message_threads_01` (≤32 karakter)

```sql
CREATE TABLE message_threads (
    user_a_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_request BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_a_id, user_b_id),
    CONSTRAINT ordered_user_pair CHECK (user_a_id < user_b_id)
);

CREATE INDEX ix_message_threads_user_b ON message_threads(user_b_id);
```

**Kural:** `user_a_id < user_b_id` — canonical pair her zaman `(min(a,b), max(a,b))`.

**Model — `backend/app/models/message_thread.py`:**

```python
class MessageThread(Base):
    __tablename__ = "message_threads"
    user_a_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    user_b_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    is_request: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

`backend/app/models/__init__.py`'e eklenir: `from .message_thread import MessageThread`

---

### 5.3 SendDirectMessageCommand — is_request Mantığı

**Dosya:** `backend/app/use_cases/messages/commands/send_direct_message.py`

Mesaj oluşturulduktan sonra thread kaydı oluşturulur/kontrol edilir:

```python
from app.models.message_thread import MessageThread
from app.models.follow import Follow

# Thread kaydı — ilk mesajsa oluştur, varsa atla
user_a, user_b = min(sender_id, receiver_id), max(sender_id, receiver_id)
existing_thread = await self.uow.session.scalar(
    select(MessageThread).where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
    )
)
if not existing_thread:
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
    self.uow.session.add(MessageThread(
        user_a_id=user_a,
        user_b_id=user_b,
        is_request=is_req,
    ))
    if is_req:
        redis = await get_redis()
        await redis.incr(f"msg:unread:request:{receiver_id}")
```

---

### 5.4 Follow Accept — Thread Taşıma

**Dosya:** `backend/app/routers/follows.py` — takip isteği kabul endpoint'i

```python
from app.models.message_thread import MessageThread

user_a, user_b = min(follower_id, current_user.id), max(follower_id, current_user.id)
await db.execute(
    update(MessageThread)
    .where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
        MessageThread.is_request == True,
    )
    .values(is_request=False)
)
redis = await get_redis()
await redis.decr(f"msg:unread:request:{current_user.id}")
```

---

### 5.5 is_private → False Geçişinde Toplu Taşıma

**Dosya:** `backend/app/routers/auth.py` — PATCH /auth/me

```python
if "is_private" in body and not body["is_private"] and current_user.is_private:
    await db.execute(
        update(MessageThread)
        .where(
            or_(
                MessageThread.user_a_id == current_user.id,
                MessageThread.user_b_id == current_user.id,
            ),
            MessageThread.is_request == True,
        )
        .values(is_request=False)
    )
    redis = await get_redis()
    await redis.delete(f"msg:unread:request:{current_user.id}")
```

---

### 5.6 Yeni API Endpoint'leri

**Dosya:** `backend/app/routers/messages.py`

```
GET  /api/messages/requests                    → Mesaj isteklerini listele
POST /api/messages/requests/{user_id}/accept   → İsteği kabul et (is_request=False)
POST /api/messages/requests/{user_id}/decline  → İsteği reddet (soft delete)
```

**Accept:**

```python
@router.post("/requests/{user_id}/accept")
async def accept_message_request(user_id: int, current_user=Depends(...), db=Depends(...)):
    user_a, user_b = min(user_id, current_user.id), max(user_id, current_user.id)
    result = await db.execute(
        update(MessageThread)
        .where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
            MessageThread.is_request == True,
        )
        .returning(MessageThread)
    )
    if not result.scalar_one_or_none():
        raise NotFoundException(code="MESSAGE_REQUEST_NOT_FOUND")
    await db.commit()
    redis = await get_redis()
    await redis.decr(f"msg:unread:request:{current_user.id}")
    return {"status": "accepted"}
```

**Decline — soft delete:**

```python
@router.post("/requests/{user_id}/decline")
async def decline_message_request(user_id: int, current_user=Depends(...), db=Depends(...)):
    user_a, user_b = min(user_id, current_user.id), max(user_id, current_user.id)
    await db.execute(delete(MessageThread).where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
    ))
    await db.execute(
        update(DirectMessage)
        .where(
            or_(
                and_(DirectMessage.sender_id == user_id, DirectMessage.receiver_id == current_user.id),
                and_(DirectMessage.sender_id == current_user.id, DirectMessage.receiver_id == user_id),
            )
        )
        .values(is_hidden=True)
    )
    await db.commit()
    redis = await get_redis()
    await redis.decr(f"msg:unread:request:{current_user.id}")
    return {"status": "declined"}
    # Gönderene BİLDİRİM GİTMEZ
```

---

### 5.7 Redis

```
msg:unread:{user_id}          → mevcut key, regular mesajlar (değişmez)
msg:unread:request:{user_id}  → yeni key, istek mesajları (Integer sayaç, TTL yok)
```

---

### 5.8 Notification Tipi

```python
# events.py veya notification service — yeni event tipi:
# "message_request" — mevcut "new_message"'den ayrı FCM payload
# { "type": "message_request", "sender_username": ..., "preview": "..." }
```

---

### 5.9 Mobile API Contract

Backend değişikliklerinin mobile'a yansıması:

- `GET /api/messages/conversations` response'una `is_request: bool` eklenir (thread'den join ile)
- `GET /api/messages/requests` → sadece `is_request=True` thread'ler
- `GET /api/messages/unread` response'una `request_count: int` eklenir (`msg:unread:request:{uid}` Redis)

**Mobile UI** (sekme tasarımı ve request conversation view):

Mesajlar ekranının iç yapısı:

```
MainNavigation → "Mesajlar" tab
  └── messages_screen.dart
        ├── Tab: "Mesajlar"       → mevcut konuşma listesi (is_request=False)
        └── Tab: "Mesaj İstekleri {n}" → is_request=True thread'ler
              └── Request conversation view
                    ├── Banner: "Bu kişiyi tanımıyor olabilirsin."
                    ├── [Kabul Et] → POST /requests/{user_id}/accept
                    └── [Reddet]   → POST /requests/{user_id}/decline
```

Sekme badge: `msg:unread:request:{uid}` sayacından gelir.
MVVM: `MessagesViewModel` (mevcut) genişletilir — `requestCount` state'i eklenir.

---

### 5.10 ARB

```json
"messageRequests":        "Mesaj İstekleri",
"messageRequestsHint":    "Takipçi olmayan kişilerden gelen mesajlar",
"messageRequestBanner":   "Bu kişiyi tanımıyor olabilirsin.",
"acceptMessageRequest":   "Kabul Et",
"declineMessageRequest":  "Reddet",
"messageRequestAccepted": "Mesajın kabul edildi",
"messageRequestsEmpty":   "Mesaj isteği yok",
"messageRequestNotif":    "{name} sana mesaj gönderdi"
```

**Deploy:** `alembic upgrade head` → `sync_translations.py` → `systemctl restart teqlif`

---

## Task 6 — Karar 5: Privacy Discovery Banner

**Tamamen mobile-only. Backend değişiklik yok.**

### 6.1 Storage Keys

**Dosya:** `mobile/lib/services/storage_service.dart`

```dart
static const _privacyBannerShownKey = 'teqlif_privacy_banner_shown';

static Future<bool> getPrivacyBannerShown() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_privacyBannerShownKey) ?? false;
}
static Future<void> setPrivacyBannerShown(bool val) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_privacyBannerShownKey, val);
}
```

### 6.2 profile_screen.dart

```dart
// Profil yükleme sonrası:
final shown = await StorageService.getPrivacyBannerShown();
if (!shown && !_isPrivate && mounted) {
  setState(() => _showPrivacyBanner = true);
}

// Kapatınca:
await StorageService.setPrivacyBannerShown(true);
setState(() => _showPrivacyBanner = false);

// Gösterim koşulu:
// _isOwnProfile && _showPrivacyBanner && !_isPrivate
```

### 6.3 ARB

```json
"privacyBannerTitle":  "Profilini gizleyebilirsin",
"privacyBannerDesc":   "Ayarlar bölümünden hesabını gizli yapabilirsin.",
"privacyBannerAction": "Ayarlara Git"
```

---

## ARB Anahtarları — Tüm Yeni Keyler

| Key | Task | Türkçe |
|-----|------|--------|
| `followListPrivate` | 3 | Bu liste gizlidir |
| `followListPrivateDesc` | 3 | Listeyi görmek için takip et |
| `offerBlockedError` | 4a | Bu kullanıcıyla işlem yapamazsınız |
| `messageRequests` | 5 | Mesaj İstekleri |
| `messageRequestsHint` | 5 | Takipçi olmayan kişilerden gelen mesajlar |
| `messageRequestBanner` | 5 | Bu kişiyi tanımıyor olabilirsin. |
| `acceptMessageRequest` | 5 | Kabul Et |
| `declineMessageRequest` | 5 | Reddet |
| `messageRequestAccepted` | 5 | Mesajın kabul edildi |
| `messageRequestsEmpty` | 5 | Mesaj isteği yok |
| `messageRequestNotif` | 5 | {name} sana mesaj gönderdi |
| `privacyBannerTitle` | 6 | Profilini gizleyebilirsin |
| `privacyBannerDesc` | 6 | Ayarlar bölümünden hesabını gizli yapabilirsin. |
| `privacyBannerAction` | 6 | Ayarlara Git |

**Toplam:** 14 yeni ARB key, 4 dil (TR, EN, AR, RU)

---

## Migration Özeti

| Migration | Task | Değişiklik |
|-----------|------|-----------|
| `zz_message_threads_01` | Task 5 | `message_threads` tablosu + index |

Diğer tasklar için migration gerekmez.

---

## Deploy Sırası

**Task 1–4 ve 6 (migration yok):**

```bash
git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```

**Task 5 (migration var):**

```bash
git pull && alembic upgrade head && python3 scripts/sync_translations.py && sudo systemctl restart teqlif
```
