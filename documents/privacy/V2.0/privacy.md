# Teqlif — Privacy & Block Sistem Durumu

> **Tarih:** 2026-09-01 · **Son güncelleme:** 2026-09-04
> **Kapsam:** Mevcut durum tabloları + alınan kararlar
> **Kaynak:** Codebase taraması — backend + mobile tam analiz
> **Güncelleme:** Karar 3 follow-based modele güncellendi; Karar 9 (arama izni modeli) eklendi

---

## Tablo 1 — `is_private` Sistemi: Mevcut Durum

### Tanım

`users.is_private: Boolean, default=False, server_default="false"`

Kullanıcı kendi profil ekranındaki toggle ile değiştirir.
API: `PATCH /api/auth/me` → `{"is_private": true/false}`

### Etki Tablosu

| Alan / Özellik | Backend Koruması | Mobile UI Koruması | Dosya / Satır | Notlar |
|----------------|-----------------|-------------------|---------------|--------|
| **Takip isteği tipi** | ✅ `"pending"` | ✅ Saat ikonu gösterilir | `follows.py:98`, `public_profile_screen.dart:543` | Tek gerçek backend etkisi |
| **Profil API response** | ❌ Yok | — | `get_user_profile.py` | `is_private=True` olsa da bio, sosyal linkler, follower sayısı, following sayısı tam dönüyor |
| **Profil sayfası — ilan grid'i** | ❌ Yok | ✅ Kilit ekranı | `public_profile_screen.dart:593` | Sadece render engelleniyor; backend ilanları yine de döndürüyor |
| **Profil sayfası — avatar / story ring** | ❌ Yok | ❌ Yok | `public_profile_screen.dart:808` | Ring sadece `isLive` ve `isPremium`'a göre değişiyor, `is_private` etkisi yok |
| **Profil sayfası — mesaj butonu** | ❌ Yok | ❌ Yok | `public_profile_screen.dart:154` | Her profilde görünüyor, follow_status kontrolü yok |
| **Profil sayfası — call butonu** | ❌ Yok | ✅ Dolaylı | `public_profile_screen.dart:172` | `_followStatus == 'accepted'` kontrolü var → gizli hesapta pending ise görünmüyor |
| **Ana feed** | ❌ Yok | ❌ Yok | `feed_queries.py` | Gizli hesabın ilanları herkese çıkıyor |
| **İlan arama** | ❌ Yok | ❌ Yok | `listings.py`, `search.py` | Gizli hesabın ilanları aramada görünüyor |
| **İlan detay sayfası** | ❌ Yok | ❌ Yok | `listings.py` | Herkes açıp görebiliyor |
| **Kullanıcı arama** | ❌ Yok | ❌ Yok | `search.py` | Gizli hesap aramada normal görünüyor, kilit ikonu yok, `is_private` response'da dönmüyor |
| **Follower / following listesi** | ❌ Yok | ❌ Yok | `follows.py` | Herkes görebiliyor |
| **Story tray (following)** | ⚠️ Dolaylı | ⚠️ Dolaylı | `story_service.py:128` | Follow JOIN ile dolaylı koruma var ama `Follow.status == 'accepted'` filtresi eksik → pending takipçi görebilir |
| **Canlı yayın listesi** | ❌ Yok | ❌ Yok | `streams.py` | Gizli hesap yayın açtığında herkese listeleniyor |
| **Canlı yayın WebSocket (chat)** | ❌ Yok | ❌ Yok | `chat.py` | Herhangi biri girebilir |
| **Mesaj gönderme** | ❌ Yok | ❌ Yok | `messages.py` | Gizli hesaba follow olmadan mesaj gönderilebiliyor |
| **Default değer — yeni kullanıcı** | ❌ `False` | ❌ `False` | `user.py:59`, `schemas/user.py:69` | Kayıtta `is_private` set edilmiyor; DB ve uygulama default `False` |
| **Onboarding — privacy sorusu** | ❌ Yok | ❌ Yok | `register_screen.dart` | Kayıt formunda ülke, consent var; gizlilik tercihi yok |

### Karar Bekleyen Noktalar

- [x] Default `is_private` değeri → **False** (Karar 1)
- [x] Backend profil gating → **uygulanacak** (Karar 2)
- [ ] Mesaj butonu — `is_private` ile bağlantısı kesildi; artık follow-based (Karar 3 güncellendi)
- [ ] Follower/following listesi gizliliği → **kararlaştırıldı** (Karar 4)
- [ ] Story tray `Follow.status == 'accepted'` bug'ı → **düzeltilecek** (Bug Fix 1)
- [ ] Onboarding'de privacy sorusu → **yok** (Karar 5)

---

## Tablo 2 — Block Sistemi: Mevcut Durum

### Tanım

`user_blocks (id, blocker_id FK→users, blocked_id FK→users, created_at)`
UniqueConstraint: `(blocker_id, blocked_id)` — tek yönlü kayıt, sorgular her iki yönü kontrol eder.

Endpoint'ler:
- `POST /api/users/{username}/block` — engelle
- `DELETE /api/users/{username}/block` — engeli kaldır
- `GET /api/users/blocked` — engellenen listesi

### Etki Tablosu

| Alan / Özellik | Backend Koruması | Mobile UI Koruması | Dosya / Satır | Notlar |
|----------------|-----------------|-------------------|---------------|--------|
| **Profil API — ben onu engelledim** | ✅ | — | `get_user_profile.py:62` | Kısmi data döner, `is_blocked: true`, erken return |
| **Profil API — o beni engelledi** | ✅ | — | `get_user_profile.py:76` | `NotFoundException("USER_NOT_FOUND")` fırlatılır |
| **Mesaj gönderme** | ✅ | — | `messages.py:306` | `ForbiddenException("MESSAGING_FORBIDDEN")` — iki yönlü |
| **Mesaj yükleme (dosya/medya)** | ✅ | — | `messages.py:476` | Aynı iki yönlü block kontrolü |
| **Canlı yayın listesi `/active`** | ✅ | — | `stream_utils.py` → `_apply_block_filter` | Block filtresi uygulanıyor |
| **Canlı yayın listesi `/recommended`** | ✅ | — | `stream_utils.py` → `_apply_block_filter` | Block filtresi uygulanıyor |
| **Canlı yayın `/suggested-streamers`** | ✅ | — | `streams.py` — raw SQL `user_blocks` | Block filtresi uygulanıyor |
| **Kullanıcı arama** | ✅ | — | `users.py:197` | Block filtresi var (iki yön) |
| **Genel arama `/search/explore`** | ✅ (giriş yapanlar için) | — | `search.py` → `_block_filters` | Users + listings + streams için uygulanıyor |
| **Ana feed** | ❌ Yok | ❌ Yok | `feed_queries.py` | Engellediğin kullanıcının ilanları feed'de çıkıyor |
| **İlan listesi / detay** | ❌ Yok | ❌ Yok | `listings.py` | Engellediğin kullanıcının ilanına erişilebiliyor |
| **Canlı yayın `/following/live`** | ❌ Yok | ❌ Yok | `streams.py` | Block filtresi yok; engellediğin birini takip ediyorsan yayını listede çıkabilir |
| **Canlı yayın WebSocket (sohbet)** | ❌ Yok | ❌ Yok | `chat.py` | Engellenen kişi yayına girip sohbet edebiliyor; yalnızca kick kontrolü var |
| **Story tray** | ❌ Yok | ❌ Yok | `story_service.py:128` | Block filtresi yok; Follow JOIN var ama follow edip block yaptıysan story hâlâ görünür |
| **Canlı yayın listesi `/active` (giriş yapılmamış)** | ❌ Yok | — | `streams.py` | Giriş yapılmamış istek için block filtresi uygulanamaz (doğal) |
| **Engelleme — mobil UI block butonu** | — | ✅ | `public_profile_screen.dart:432` | PopupMenu içinde; `toggleBlock()` ViewModel çağrısı |
| **Engelleme — engellenen kullanıcılar listesi** | ✅ | ✅ | `blocked_users_screen.dart` | Tam ekran + ViewModel mevcut |
| **Engelleme sonrası profil sayfası kapanması** | — | ✅ | `public_profile_view_model.dart` | Block sonrası navigator.pop tetikleniyor |

### Karar Bekleyen Noktalar

- [ ] Feed'e block filtresi eklenecek mi? (`feed_queries.py`)
- [ ] İlan listesine / detay sayfasına block filtresi eklenecek mi? (`listings.py`)
- [ ] Canlı yayın WebSocket'e block kontrolü eklenecek mi? (`chat.py`)
- [ ] Story tray'e block filtresi eklenecek mi? (`story_service.py`)
- [ ] Canlı yayın `/following/live`'a block filtresi eklenecek mi? (`streams.py`)

---

## Referans — Kod Konumları

| Sistem | Backend | Mobile |
|--------|---------|--------|
| is_private modeli | `backend/app/models/user.py:59` | `mobile/lib/models/user.dart:9` |
| is_private schema | `backend/app/schemas/user.py:69,105` | — |
| is_private toggle API | `backend/app/routers/auth.py:359` | `profile_screen.dart:1045` |
| is_private profil gating | `backend/app/use_cases/users/queries/get_user_profile.py` | `public_profile_screen.dart:593` |
| Follow → pending/accepted | `backend/app/routers/follows.py:98` | — |
| Story tray | `backend/app/services/story_service.py:102` | `story_viewer_screen.dart` |
| Block modeli | `backend/app/models/block.py` | — |
| Block endpoints | `backend/app/routers/users.py:57` | `public_profile_screen.dart:432` |
| Block profil gating | `backend/app/use_cases/users/queries/get_user_profile.py:62` | — |
| Block mesaj kontrolü | `backend/app/routers/messages.py:306` | — |
| Block stream filtresi | `backend/app/use_cases/streams/stream_utils.py` | — |
| Block arama filtresi | `backend/app/routers/search.py` | — |

---

---

# Kararlar

> Her karar: iş kararı + UX/UI akışı + DB + Redis + ARB + etki bayrakları içerir.
> Implementasyon detayları (ML sorguları, ClickHouse kolonları vb.) ayrıca `documents/privacy/PLAN.md` içinde tutulur.

---

## Karar 1 — Default `is_private` Değeri

**Karar:** `is_private = False` (herkese açık)

**Gerekçe:** Teqlif marketplace-önce bir platform. Yeni kullanıcıların hemen keşfedilebilir olması sosyal grafın büyümesi ve satıcıların ilk ilanından görünür olması için kritik. Gizlilik isteyen kullanıcı profil ayarlarındaki toggle ile kolayca kapatabilir.

### Değişiklik

**DB:** Değişiklik yok. `users.is_private: default=False, server_default="false"` mevcut haliyle kalır.

**Backend:** `UserRegister` schema'sına `is_private` alanı eklenmez — kayıt sırasında bu tercih sorulmaz.

**Mobile:** `register_screen.dart` değişmez.

**Redis:** Değişiklik yok.

**ARB:** Değişiklik yok.

### ⚠️ Etki Bayrakları

- Onboarding akışında privacy sorusu şu an **yok** — bu karar değiştirmeden bırakıyor. İlerleyen bir sprintte onboarding'e "Profilini kimler görebilsin?" sorusu eklenebilir.

---

## Karar 2 — Backend Profil API Gating

**Karar:** `is_private=True` olan bir kullanıcının profiline takipçi olmayan biri istekte bulunduğunda backend kısıtlı bir response döndürür.

**Gerekçe:** Şu an `GET /api/users/{username}` herkese tam profil döndürüyor — bio, sosyal linkler, follower/following sayısı takipçi olmayan birine de geliyor. `is_private` sadece bir veri alanı olarak dönüyor, gating uygulamıyor. Bu gerçek bir API güvenlik açığı.

### Kısıtlı Response — Takipçi Olmayan Görebilir

| Alan | Takipçi olmayan görür mü? | Gerekçe |
|------|--------------------------|---------|
| `id`, `username`, `avatar_url` | ✅ | Minimum kimlik |
| `is_private` | ✅ | UI'ın kilit ekranı göstermesi için gerekli |
| `is_premium`, `is_verified` | ✅ | Güven sinyali |
| `badge`, `trust_score` | ✅ | Alıcı için minimum güven bilgisi |
| `active_listings_count` | ✅ | Satıcı hakkında temel bilgi |
| `follow_status` | ✅ | UI'ın takip butonunu doğru göstermesi için |
| `is_blocked` | ✅ | UI engelleme durumunu bilmeli |
| `is_live`, `active_stream_id` | ✅ | Canlı yayın herkese görünür (ayrı karar) |
| `bio` | ❌ | Kişisel içerik |
| `website_url` | ❌ | Kişisel içerik |
| `instagram_url`, `kick_url`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url` | ❌ | Sosyal linkler |
| `follower_count`, `following_count` | ❌ | Sosyal grafik bilgisi |
| `full_name` | ❌ | Kişisel bilgi |

### Uygulama Noktası

**Dosya:** `backend/app/use_cases/users/queries/get_user_profile.py`

Mevcut blok kontrollerinden sonra, `follower_count` sorgusu yapılmadan önce gating eklenir:

```python
# is_private + takipçi değilse kısıtlı response
if target.is_private and not is_following and (not current_user or current_user.id != target.id):
    return { ...kısıtlı alanlar... }
```

### DB

Değişiklik yok — sadece sorgu mantığı değişir.

### Redis

`user:profile:{user_id}` cache key'i varsa: kullanıcı `is_private` toggle yaptığında invalidate edilmeli.

```python
# PATCH /auth/me içinde is_private değiştiğinde:
await redis.delete(f"user:profile:{current_user.id}")
```

### ARB

Değişiklik yok — mobilde zaten `loc.t('thisAccountIsPrivate')` var.

### ⚠️ Etki Bayrakları

- **Analytics:** Gizli hesaba ait profil görüntüleme event'leri (`profile_view`) takipçi olmayan kişilerden geldiğinde farklı etiketlenmeli. Yoksa bu görüntülemeler yanlış engagement sinyali üretir.
- **ML:** Profil verisi eksik döndüğü için `preference_embedding` güncellemesinde gizli hesap sinyalleri etkilenmez (listing tabanlı embedding korunur).

---

## Karar 3 — Mesaj İstekleri Sistemi *(Güncellendi: Follow-Based Model)*

**Karar:** Mesaj türü `is_private` alanından bağımsız olarak tamamen **follow ilişkisine** göre belirlenir. Takip edilen kişi takipçisine direkt mesaj atabilir; takipçi takip ettiği kişiye mesaj isteği gönderir. Mutual follow her iki yönde de direkt mesajlaşmayı açar. Follow ilişkisi yoksa her iki yön de mesaj isteği üzerinden çalışır.

**Gerekçe:** `is_private` artık mesaj türünü belirlemiyor — bu değişkeni tek gerçek etkisi follow isteği tipidir (pending/accepted). Mesajlaşmada güven sinyali follow ilişkisidir: takip edilen kişi takipçisine görünür olmayı zaten kabul etmiştir, bu yüzden takipçinin mesajı direkt gelmeli. Asimetrik ama tutarlı bir model.

---

### Mesajlaşma Matrisi

| Follow Durumu | Mesaj Yönü | Thread Türü | Sonuç |
|---|---|---|---|
| Karşılıklı | A→B | Direkt | ✅ Serbest |
| Karşılıklı | B→A | Direkt | ✅ Serbest |
| A→B (tek yönlü) | A (takip eden) → B | İstek | ⏳ Kabul / Red |
| A→B (tek yönlü) | B (takip edilen) → A | Direkt | ✅ Serbest |
| Takip Yok | A→B | İstek | ⏳ Kabul / Red |
| Takip Yok | B→A | İstek | ⏳ Kabul / Red |

**Thread kalıcılığı:** Thread bir kez kabul/direkt olunca follow durumu değişse de **direkt kalır.** Tek yönlü follow → mutual follow geçişinde bekleyen istek **auto-accept** olur.

---

### UX Akışı

**Gönderen (takipçi, veya follow yok) tarafından:**

```
1. Profili açar → mesaj butonuna basar
2. Mesaj gönderir (UI değişmez)
3. Konuşma kendi Mesajlar listesinde görünür
4. Thread tipi:
   - Alıcı göndereni takip ediyorsa → Direkt (alıcıda da Mesajlar'a düşer)
   - Alıcı göndereni takip etmiyorsa → İstek (alıcıda Mesaj İstekleri'ne düşer)
```

**Alıcı (takip etmediği kişiden istek geldiğinde):**

```
1. Mesajlar ekranını açar
2. "Mesajlar" ve "Mesaj İstekleri 🔴" iki sekme görünür
3. Mesaj İstekleri sekmesini açar
4. Gönderenin adı + kısaltılmış mesaj önizlemesi görünür
5. Konuşmayı açar → tam mesajı okur
6. İki aksiyon butonu:
   [Kabul Et]   →  konuşma Mesajlar sekmesine taşınır
                   gönderene bildirim: "Mesajın kabul edildi"
   [Reddet]     →  konuşma silinir (arşivlenmez)
                   gönderene BİLDİRİM GİTMEZ (gizlilik)
```

**Tek yönlü follow → mutual follow geçişi:**

```
1. B, A'nın takip isteğini kabul eder (artık mutual follow)
2. Sistem otomatik kontrol: A'dan bekleyen mesaj isteği var mı?
3. Varsa → konuşma Mesajlar sekmesine otomatik taşınır
4. Alıcıya ayrıca bildirim gitmez (takip kabulü yeterli)
```

---

### UI Değişiklikleri

**Messages ekranı (`messages_screen.dart`):**

```
Mevcut: Tek liste (tüm konuşmalar)

Yeni:
┌─────────────────────────────────────────┐
│  [  Mesajlar  ] [  Mesaj İstekleri 3  ] │
├─────────────────────────────────────────┤
│  ... konuşma listesi ...                │
└─────────────────────────────────────────┘

- Sekme badge'i: bekleyen istek sayısı
- İstek sekmesinde mesaj önizlemesi kısaltılmış (ilk 40 karakter)
```

**Request konuşma görünümü:**

```
┌─────────────────────────────────────────┐
│  Bu kişiyi tanımıyor olabilirsin.        │
│  [  Kabul Et  ]    [  Reddet  ]         │
├─────────────────────────────────────────┤
│  ... mesaj içeriği ...                  │
└─────────────────────────────────────────┘
```

**Profil ekranı (`public_profile_screen.dart`):**

Mesaj butonu gizli hesapta da görünür kalır — değişiklik yok. Arka planda mesaj "request" olarak işaretlenir.

---

### DB

Mevcut mesaj/konuşma tablosuna `is_request` ve `initiator_id` kolonları eklenir:

```sql
ALTER TABLE message_threads ADD COLUMN is_request BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE message_threads ADD COLUMN initiator_id INTEGER REFERENCES users(id);
```

`initiator_id`: thread oluşturulduktan sonra değişmez; arama izninde acceptor'ı belirlemek için kullanılır (bkz. Karar 9).

Mesaj gönderimi sırasında `is_request` belirlenir:

```python
# POST /api/messages/send içinde
# Kural: alıcı göndereni takip etmiyorsa → istek
receiver_follows_sender = await db.scalar(
    select(Follow).where(
        Follow.follower_id == receiver_id,
        Follow.followed_id == sender_id,
        Follow.status == "accepted"
    )
)
is_request = not receiver_follows_sender
# thread.is_request = is_request, thread.initiator_id = sender_id
```

Mutual follow geçişinde (`follows.py` — accept endpoint):

```python
# B, A'nın takip isteğini kabul ettiğinde (artık mutual follow):
# A → B yönündeki bekleyen mesaj isteklerini auto-accept et
await db.execute(
    update(MessageThread)
    .where(
        MessageThread.initiator_id == followed_user_id,  # A (isteği atan)
        MessageThread.participant_b == current_user.id,  # B (kabul eden)
        MessageThread.is_request == True
    )
    .values(is_request=False)
)
```

---

### Redis

Okunmamış mesaj sayısı ayrı tutulur:

```
msg:unread:{user_id}          →  mevcut key, regular mesajlar
msg:unread:request:{user_id}  →  yeni key, request mesajlar
```

`is_private` değişiminde artık otomatik taşıma **yapılmaz** — thread tipi follow ilişkisine göre belirlenmiştir, `is_private` toggle'ı bunu etkilemez.

---

### ARB

```json
"messageRequests":          "Mesaj İstekleri",
"messageRequestsHint":      "Seni takip etmeyen kişilerden gelen mesajlar",
"messageRequestBanner":     "Bu kişiyi tanımıyor olabilirsin.",
"acceptMessageRequest":     "Kabul Et",
"declineMessageRequest":    "Reddet",
"messageRequestAccepted":   "Mesajın kabul edildi",
"messageRequestsEmpty":     "Mesaj isteği yok",
"messageRequestNotif":      "{name} sana mesaj gönderdi"
```

---

### Edge Case Kararları

| Durum | Karar |
|-------|-------|
| **Mutual follow** → önceden istek olarak başlamış thread var | Otomatik Mesajlar'a taşınır (auto-accept), ayrıca bildirim gitmez |
| Mesaj isteği **reddedilirse** | Gönderen bildirim almaz; tekrar mesaj gönderemez (backend 7 gün cooldown) |
| Takip **kabul edilmiş** → sonra unfollowed | Thread Mesajlar'da kalır, `is_request=False` değişmez — thread kalıcı |
| Unfollow → **yeni** mesaj gönderilirse | Yeni thread artık istek — eski thread kalıcı |
| Aynı kişiden **birden fazla mesaj** | Tek thread — birden fazla mesaj ekler, birden fazla request oluşturmaz |
| **Block** → mesaj isteği varken | Mesaj isteği silinir; block bildirimi normal davranışı izler |
| `is_private` **değişirse** | Thread tipi **değişmez** — follow ilişkisi belirler, is_private değil |

---

### ⚠️ Etki Bayrakları

- **Bildirimler:** `message_request` yeni bir notification tipi olarak eklenmeli — mevcut `new_message` tipinden ayrı.
- **ClickHouse:** Mesaj event'lerine `is_request` alanı eklenmeli. Request mesajlarından gelen etkileşimler feed engagement analitiğine karıştırılmamalı.
- **BPR / User interests:** `is_request=True` konuşmalarındaki etkileşimler (mesaj açma, yanıt) tercih sinyali üretmemeli — istenmeyen mesaj olabilir.
- **Unread badge:** App badge sayısı (`app_badge_plus`) hesaplanırken `msg:unread:request:{user_id}` ayrı sayılmalı; ana badge'e dahil edilip edilmeyeceği ayrıca kararlaştırılacak.

---

## Karar 9 — Arama İzni Modeli (Follow-Based)

**Karar:** Arama izni tamamen follow ilişkisine göre belirlenir. Takip edilen kişi takipçisini her zaman arayabilir. Takipçi, takip ettiği kişiyi yalnızca o kişi toggle'ı açarsa arayabilir. Mutual follow her iki yönde de serbest arama açar. Arama izni **dinamiktir** — follow durumu değiştiğinde anında güncellenir (messaging thread'in aksine kalıcı değil).

**Gerekçe:** Sesli iletişim mesajlaşmaya göre daha doğrudan ve kişisel. Follow ilişkisi burada da güven katmanı işlevi görür. Takip edilen kişi (satıcı) takipçisini (müşteri) arayabilmeli; tersi durumda ise takip edilen kişinin izni gerekiyor. Mesaj isteği üzerinden başlayan iletişimlerde arama izni acceptor'da (thread'i kabul eden) kalır.

---

### Arama Matrisi

| Follow Durumu | Thread Durumu | Arama Yönü | İzin |
|---|---|---|---|
| Karşılıklı | — | A→B | ✅ |
| Karşılıklı | — | B→A | ✅ |
| A→B (tek yönlü) | — | A (takip eden) → B | 🔒 B toggle |
| A→B (tek yönlü) | — | B (takip edilen) → A | ✅ |
| Takip Yok | Yok / Beklemede | Her iki yön | ❌ |
| Takip Yok | Kabul | Initiator → Acceptor | 🔒 Acceptor toggle |
| Takip Yok | Kabul | Acceptor → Initiator | 🔒 Acceptor toggle |

**İki matris arasındaki temel fark:**

| | Mesajlaşma | Arama |
|---|---|---|
| Takip edilen → Takip eden | ✅ Direkt | ✅ Direkt |
| Takip eden → Takip edilen | ⏳ İstek | 🔒 Toggle |
| Thread kabul sonrası | Kalıcı direkt | Follow durumuna bakar |
| State kalıcılığı | Evet | Hayır — dinamik |

---

### Toggle Mekanizması

Toggle sahibi: **acceptor** (mesaj isteğini kabul eden kişi veya tek yönlü follow'da takip edilen).

- **Default:** OFF (kapalı)
- Toggle ON → initiator da arayabilir, acceptor da arayabilir
- Toggle OFF → her iki yön de kapalı

**UI — Mesaj thread'i ekranı:**

```
Initiator (toggle OFF iken):
  [ⓘ]  [📞 Disabled]
  ⓘ ikonuna basınca: "Karşılıklı takip olmadığı için arama iznini karşı taraf verebilir"

Acceptor (toggle OFF iken):
  [ⓘ]  [🔘 Toggle: OFF]  [📞 Disabled]
  ⓘ ikonuna basınca: "Arama özelliği varsayılan olarak kapalıdır"
  Toggle ON yapılınca: her iki taraf da arayabilir, 📞 aktif olur
```

---

### DB

`message_threads` tablosuna `call_allowed` kolonu eklenir:

```sql
ALTER TABLE message_threads ADD COLUMN call_allowed BOOLEAN NOT NULL DEFAULT FALSE;
```

`call_allowed` yalnızca acceptor tarafından değiştirilebilir:

```python
# PATCH /api/messages/threads/{thread_id}/call-permission
# Yalnızca acceptor (initiator_id != current_user.id) yapabilir
if thread.initiator_id == current_user.id:
    raise ForbiddenException(code="CALL_PERMISSION_NOT_YOURS")
thread.call_allowed = body.call_allowed
```

`can_call` hesaplama mantığı (her sorguda dinamik):

```python
def compute_can_call(
    viewer_id: int,
    target_id: int,
    viewer_follows_target: bool,
    target_follows_viewer: bool,
    thread: MessageThread | None,
) -> bool:
    # Mutual follow
    if viewer_follows_target and target_follows_viewer:
        return True
    # Takip edilen → Takipçi (viewer = takip edilen)
    if target_follows_viewer and not viewer_follows_target:
        return True
    # Takipçi → Takip edilen (toggle kontrolü)
    if viewer_follows_target and not target_follows_viewer:
        return thread.call_allowed if thread else False
    # Takip yok — thread toggle kontrolü
    if thread and thread.is_request is False:
        return thread.call_allowed
    return False
```

---

### Real-time: `can_call_changed` WS Event

Follow veya toggle değiştiğinde `can_call` yeniden hesaplanır ve karşı tarafa WS event'i gönderilir:

**Tetikleyiciler:**
- Follow kabul / iptal / unfollow
- `call_allowed` toggle değişimi

**Event şeması:**

```json
{
  "type": "can_call_changed",
  "user_id": 123,        // can_call durumu değişen kullanıcı ID'si
  "can_call": true       // yeni değer (viewer'a göre)
}
```

**Backend:** Her iki tetikleyicide de ilgili thread/follow'dan etkilenen kullanıcılara WS üzerinden event push edilir.

**Mobile:** `CallService` veya `MessageThreadViewModel` event'i dinler → arama butonu UI'ı günceller.

---

### `can_call` — Profil Ekranı

`GET /api/users/{username}` response'una `can_call: bool` eklenir:

```python
# get_user_profile.py içinde
can_call = compute_can_call(
    viewer_id=current_user.id,
    target_id=target.id,
    viewer_follows_target=is_following,
    target_follows_viewer=is_followed_by,
    thread=active_thread,  # None ise follow-only kontrol
)
```

Mobile: profil ekranında arama butonu `can_call` değerine göre render edilir — mevcut `_followStatus == 'accepted'` kontrolü kaldırılır.

---

### Hata Yönetimi

`CALL_FORBIDDEN` backend response'u artık frontend'de yakalanır:

```dart
// call_service.dart içinde
case 'CALL_FORBIDDEN':
  TeqToast.show('Bu kullanıcıyı şu an arayamazsın');
  return;
```

---

### ARB

```json
"callPermissionNotYours":     "Arama iznini yalnızca karşı taraf değiştirebilir",
"callPermissionInfo":         "Karşılıklı takip olmadığı için arama iznini karşı taraf verebilir",
"callPermissionDefaultOff":   "Arama özelliği varsayılan olarak kapalıdır",
"callToggleLabel":            "Arama İzni",
"callForbiddenToast":         "Bu kullanıcıyı şu an arayamazsın"
```

---

### Edge Case Kararları

| Durum | Karar |
|-------|-------|
| Mutual follow → unfollow | `can_call` dinamik olarak güncellenir; toggle durumu korunur |
| Toggle ON → unfollow olur | `can_call` yeniden hesaplanır — toggle ON ama follow yok → follow kuralı geçerli |
| Thread silinirse | `call_allowed` verisi kaybolur; yeni thread oluşursa default OFF |
| Block yapılırsa | `can_call = false` override — block her şeyin üstünde |
| Bekleyen istek (pending thread) | Arama yok — thread kabul edilene kadar `can_call = false` |

### ⚠️ Etki Bayrakları

- **`calls.py` router:** `/call/start` endpoint'inde `can_call` kontrolü — mevcut mutual-follow-only kontrolünü bu mantıkla değiştir.
- **`public_profile_screen.dart:172`:** `_followStatus == 'accepted'` → `_canCall` (profil API'dan gelen `can_call` değeri).
- **`call_service.dart:333`:** `CALL_FORBIDDEN` → `teqToast` ile kullanıcıya bilgi ver.
- **Alembic:** `call_allowed` + `initiator_id` kolonları için yeni migration.

---

## Karar 4 — Follower/Following Listesi Gizliliği

**Karar:** Gizli hesabın follower ve following **sayıları** herkese görünür. **Listeler** (kimin takip ettiği, kimi takip ettiği) yalnızca takipçilere açılır.

**Gerekçe:** Sayılar sosyal kanıt işlevi görür — satıcının güvenilirlik sinyali. Liste ise sosyal grafik bilgisi; gizli hesap bu detayı kamusal alanda paylaşmak istemeyebilir. Bu ikisi ayrı tutularak denge sağlanır.

---

### UX Akışı

**Takipçi olmayan biri gizli hesabın profilini açtığında:**

```
Profil sayfası:
  142 takipçi   89 takip edilen    ← sayılar görünür
  [Takip Et] butonu

  → "142 takipçi" yazısına tıklarsa:
    "Bu hesap gizlidir" mesajı veya sayfa açılmaz
    (liste endpoint'i 403 döner)
```

**Takipçi olan biri gizli hesabın profilini açtığında:**

```
  142 takipçi   89 takip edilen    ← sayılar görünür
  → "142 takipçi" yazısına tıklar → liste açılır (mevcut davranış)
```

---

### Uygulama Noktaları

**Backend — `follows.py`:**

`GET /api/follows/{user_id}/followers` ve `GET /api/follows/{user_id}/following` endpoint'lerine gating eklenir:

```python
# target kullanıcı is_private=True ise ve istek yapan takipçi değilse:
if target.is_private and not is_following and current_user.id != target.id:
    raise ForbiddenException(code="FOLLOWERS_LIST_PRIVATE")
```

`follower_count` ve `following_count` sayıları `GetUserProfileQuery` response'unda korunur — Karar 2'deki kısıtlı response'a dahil edilir.

**Mobile — `public_profile_screen.dart`:**

Follower/following sayısına tıklanınca açılan `FollowListScreen`:
- 403 response geldiğinde `ForbiddenException` yakalanır
- Kilit mesajı gösterilir: `loc.t('followListPrivate')`
- Alternatif: tıklama aksiyonu `_isPrivate && _followStatus != 'accepted'` ise hiç tetiklenmez

---

### DB

Değişiklik yok — sadece endpoint'lere gating mantığı eklenir.

### Redis

Değişiklik yok — follower/following listeleri cache'leniyorsa mevcut invalidasyon yeterli; is_private gating sorgu katmanında yapılır.

### ARB

```json
"followListPrivate":  "Bu liste gizlidir",
"followListPrivateDesc": "Listeyi görmek için takip et"
```

### Edge Case Kararları

| Durum | Karar |
|-------|-------|
| Kendi profilini açan hesap | Liste her zaman görünür |
| Public hesabın listesi | Değişmez — herkese açık |
| Gizli hesap public'e geçerse | Liste herkese açılır |
| Admin/moderatör | Backend'de ayrı yetkiyle liste erişimi korunur |

### ⚠️ Etki Bayrakları

- **"Ortak takipçiler" özelliği** (varsa veya ilerleyen sprintte eklenecekse): Gizli hesaplar için bu özellik devre dışı bırakılmalı veya sadece takipçilere gösterilmeli.

---

## Bug Fix 1 — Story Tray: Pending Takipçi Story Görüyor

**Durum:** Bug. Karar gerektirmiyor.

**Sorun:** `story_service.py` — `get_following_stories` metodu Follow tablosuna JOIN yapıyor ama `Follow.status == 'accepted'` filtresi yok. Gizli bir hesaba takip isteği gönderip henüz kabul edilmemişken (`status='pending'`) o kişinin hikayeleri following tray'inde görünüyor.

Aynı sorun canlı yayın satırında da var:

```python
# story_service.py:128 — Video hikayeleri (MEVCUT - HATALI)
.where(
    Follow.follower_id == current_user_id,
    Story.expires_at > func.now(),
    # Follow.status kontrolü YOK
)

# story_service.py:152 — Canlı yayınlar (MEVCUT - HATALI)
.where(
    Follow.follower_id == current_user_id,
    LiveStream.is_live == True,
    # Follow.status kontrolü YOK
)
```

**Fix:**

```python
# Her iki WHERE bloğuna eklenecek tek satır:
Follow.status == "accepted",
```

**Dosya:** `backend/app/services/story_service.py` — satır 128 ve 152 civarı

**Etki:** Backend restart yeterli. DB migration yok. Mobile değişiklik yok. Test: pending takip isteği olan gizli hesabın story'si tray'de görünmemeli.

---

## Karar 5 — Gizli Hesap Özelliğinin Tanıtımı (Contextual Discovery)

**Karar:** Onboarding'e soru veya slide eklenmez. Kullanıcı kendi profilini **ilk kez açtığında** bir kez gösterilen, kapatılabilir bir banner ile gizli hesap özelliğinden haberdar edilir. Banner tekrar gösterilmez.

**Gerekçe:** Kullanıcı profilini ilk gördüğü an bu bilgi anlamlı — "profilim var, bunu gizleyebilirmişim" bağlamı kurulmuş oluyor. Onboarding'de ise henüz profil kavramını kavramadan bu bilgi boşa gider.

---

### UX

```
┌─────────────────────────────────────────────┐
│ 💡  Profilini gizleyebilirsin               │
│     Ayarlar bölümünden hesabını gizli        │
│     yapabilirsin.          [Ayarlara Git] [×]│
└─────────────────────────────────────────────┘
```

- Profilin üst kısmında, avatar bloğunun hemen altında çıkar
- `[×]` ile kapatılır → bir daha gösterilmez
- `[Ayarlara Git]` → profile_screen'in Gizlilik ayarı bölümüne scroll eder veya direkt toggle'a odaklanır
- Banner sadece **kendi profilinde** gösterilir, public profillerde çıkmaz
- `is_private=True` yapılmışsa banner gösterilmez (zaten aktif)

---

### Gösterim Koşulları

| Koşul | Davranış |
|-------|---------|
| Kullanıcı kendi profilini ilk kez açıyor | Banner gösterilir |
| Daha önce kapatmış | Banner gösterilmez |
| `is_private=True` | Banner gösterilmez (özellik zaten aktif) |
| Uygulama yeniden yüklenirse | Banner tekrar gösterilir (device-local storage — kabul edilebilir) |

---

### Uygulama Noktası

**Dosya:** `mobile/lib/screens/profile_screen.dart`

`initState` veya profil verisi yüklendikten sonra:

```dart
final shown = await StorageService.getPrivacyBannerShown();
if (!shown && !_isPrivate) {
  setState(() => _showPrivacyBanner = true);
}

// Kapatınca:
await StorageService.setPrivacyBannerShown(true);
setState(() => _showPrivacyBanner = false);
```

---

### DB

Değişiklik yok — backend'e istek atmaz.

### Redis

Değişiklik yok.

### Storage

`StorageService` / `SharedPreferences`'e iki yeni key:

```dart
static const _privacyBannerShownKey = 'teqlif_privacy_banner_shown';

static Future<bool> getPrivacyBannerShown() async { ... }
static Future<void> setPrivacyBannerShown(bool val) async { ... }
```

### ARB

```json
"privacyBannerTitle":  "Profilini gizleyebilirsin",
"privacyBannerDesc":   "Ayarlar bölümünden hesabını gizli yapabilirsin.",
"privacyBannerAction": "Ayarlara Git"
```

### ⚠️ Etki Bayrakları

- Yok — tamamen mobile-local bir özellik.

---

## Karar 6 — Block Sistemi Tam Davranış Tanımı

**Felsefe:** Block = iletişim ve doğrudan etkileşim kanallarını kapatmak. Pasif içerik tüketimi (görüntüleme, izleme) serbest bırakılır.

**Gerekçe:** Teqlif ticaret uygulaması. İki kullanıcının birbirini engellemesi onların ticaret ekosisteminden tamamen kopmasını gerektirmiyor — sadece doğrudan temasa geçememelerini gerektiriyor. Alıcı engellediği satıcının ilanını görüp satın alabilmeli; ama mesaj atamamalı, teklif verememeli.

---

### Tam Davranış Tablosu

| Alan | Engellenen yapabilir mi? | Mevcut Durum | Değişiklik |
|------|--------------------------|--------------|-----------|
| Feed'de ilanları görme | ✅ Evet | ❌ Yok (feed filtresi yok) | Değişmez — feed block filtresi eklenmez |
| Aramada ilanları görme | ✅ Evet | ✅ Var (search block filtresi var) | Tersine çevrilir — ilanlar görünür kalır |
| İlan detay — görüntüleme | ✅ Evet | ❌ Yok | Değişmez |
| İlan detay — teklif ver | ❌ Hayır | ❌ Kontrol yok | Buton disabled + backend kontrolü |
| Engelleyenin public profiline gitme | ❌ Hayır | ✅ NotFoundException | Değişmez (mevcut çalışıyor) |
| Public profilde mesaj butonu | ❌ Hayır | ❌ Her zaman görünüyor | Gizlenir — `_isBlocked` kontrolü |
| Canlı yayın — yayına girme | ✅ Evet | ✅ Girebiliyor | Değişmez |
| Canlı yayın — açık artırma teklifi ve tüm aksiyonlar | ❌ Hayır | ❌ Kontrol yok | Otomatik susturma kapsar (mevcut altyapı) |
| Canlı yayın — host viewer listesi | ❌ Hayır | ❌ Kontrol yok | Viewer listesinden filtrelenir |
| Mesajlaşma (send) | ❌ Hayır | ✅ ForbiddenException | Değişmez (mevcut çalışıyor) |
| Story tray | ❌ Hayır | ⚠️ Follow yoksa görünmüyor | Değişmez — follow olmadığı için zaten korumalı |

---

### Uygulama Noktaları

#### 1. İlan Detay — Teklif Ver Butonu

**Mobile:** `listing_detail_screen.dart` — teklif butonu render koşuluna block kontrolü eklenir:

```dart
// Teklif butonu yalnızca block yoksa gösterilir
if (!_isBlockedBySeller && !_hasBlockedSeller)
  TeqAsyncButton(label: loc.t('makeOffer'), ...)
```

`_isBlockedBySeller` ve `_hasBlockedSeller` değerleri listing detail API response'undan veya seller profil verisinden gelir.

**Backend:** `POST /api/offers` (veya teklif endpoint'i) — `messages.py`'deki gibi iki yönlü block kontrolü:

```python
if block_exists:
    raise ForbiddenException(code="OFFER_FORBIDDEN")
```

#### 2. Public Profilde Mesaj Butonu

**Mobile:** `public_profile_screen.dart:154` — mevcut kod:

```dart
// MEVCUT (her zaman görünüyor):
if (_user != null && !_isOwnProfile)
  IconButton(icon: Icon(Icons.chat_bubble_outline), ...)

// YENİ (_isBlocked kontrolü eklenir):
if (_user != null && !_isOwnProfile && !_isBlocked)
  IconButton(icon: Icon(Icons.chat_bubble_outline), ...)
```

Backend'de mesaj send endpoint'i zaten block kontrolü yapıyor — ek değişiklik yok.

#### 3. Canlı Yayın — Otomatik Susturma

**Backend:** `chat.py` — WebSocket bağlantısı kurulurken block kontrolü:

```python
# Kullanıcı WebSocket'e bağlandığında:
block_exists = await db.scalar(
    select(UserBlock).where(
        or_(
            and_(UserBlock.blocker_id == host_id, UserBlock.blocked_id == user_id),
            and_(UserBlock.blocker_id == user_id, UserBlock.blocked_id == host_id),
        )
    )
)
if block_exists:
    # Mevcut susturma (mute) mekanizması uygulanır
    await apply_mute(stream_id, user_id)
```

Mute mekanizması: sohbet, reaksiyon ve tüm canlı yayın aksiyonları devre dışı kalır. Yayını izlemeye devam edebilir.

#### 4. Canlı Yayın — Host Viewer Listesi

**Backend:** Viewer listesi endpoint'ine host için block filtresi:

```python
# Host kendi viewer listesini çekerken engellenen kullanıcılar filtrelenir
AND user_id NOT IN (
    SELECT blocked_id FROM user_blocks WHERE blocker_id = :host_id
    UNION
    SELECT blocker_id FROM user_blocks WHERE blocked_id = :host_id
)
```

#### 5. Arama — İlan Görünürlüğü Düzeltmesi

Mevcut `search.py`'de kullanıcı araması block filtresi var — doğru. Ama **ilan araması** block filtresi uyguluyor olabilir (incelenmeli). Felsefemize göre aramada ilanlar görünmeli — block filtresi ilan sonuçlarından çıkarılır, yalnızca kullanıcı sonuçlarında kalır.

---

### DB

Değişiklik yok — `user_blocks` tablosu mevcut haliyle kullanılır.

### Redis

Değişiklik yok — mevcut cache key'leri korunur.

### ARB

```json
"offerBlockedError": "Bu kullanıcıyla işlem yapamazsınız"
```

### Edge Case Kararları

| Durum | Karar |
|-------|-------|
| Engel kaldırılırsa | Tüm kısıtlamalar anında kalkar |
| İki kullanıcı karşılıklı engellerse | Aynı davranış her iki yön için geçerli |
| Engellenen canlı yayında mute iken engel kaldırılırsa | Mute kalkar (yeni join gerekebilir veya anlık kaldırılır — implementasyona göre) |

### ⚠️ Etki Bayrakları

- **ClickHouse / Analytics:** Engellenen kullanıcının listing view event'leri normal kaydedilmeye devam eder — pasif tüketim serbest olduğu için.
- **BPR / ML:** Engellenen kullanıcının ilanları feed'de görünüyor — bu etkileşim sinyalleri BPR training'e giriyor. Şimdilik kabul edilebilir; veri birikince iyileştirilebilir.
- **Offer endpoint:** `POST /api/listings/{id}/offers` → `use_cases/listings/commands/create_offer.py` (doğrulandı).

---

## Karar 7 — Story Tray Block Filtresi

**Karar:** Engelleme iki yönlü story erişimini keser. Engellenen kişi engelleyenin story'lerini göremez; engelleyen de engellediği kişinin story'lerini görmez.

**Dosya:** `backend/app/services/story_service.py`

`get_following_stories` metodundaki her iki sorguya (video hikayeleri ~satır 125 ve canlı yayın ~satır 149) block filtresi eklenir:

```python
_blocked_users = (
    select(UserBlock.blocked_id).where(UserBlock.blocker_id == current_user_id)
    .union_all(
        select(UserBlock.blocker_id).where(UserBlock.blocked_id == current_user_id)
    )
)
# Video sorgusu WHERE'ine: Story.user_id.not_in(_blocked_users)
# Live sorgusu WHERE'ine:  LiveStream.host_id.not_in(_blocked_users)
```

Bug Fix 1 (`Follow.status == "accepted"`) ile aynı sorgulara aynı anda uygulanır — ayrı deployment gerektirmez.

### DB / Redis / ARB

Değişiklik yok.

### ⚠️ Etki Bayrakları

- **Story analytics:** Engelleme sonrası bu kullanıcıdan gelen story görüntüleme sinyalleri sıfırlanır — ML için doğru davranış.

---

## Karar 8 — Canlı Yayın `/following/live` Block Filtresi

**Karar:** Takip edilen birini engelledikten sonra o kişinin yayını `/following/live` listesinde çıkmaz.

**Gerekçe:** Kod analizi — `GetActiveStreamsQuery` ve önerilen yayınlar `_apply_block_filter` uygularken `GetFollowedLiveStreamsQuery` aynı filtreden yoksun. Tutarsız bir durum; diğer endpoint'lerle uyumlu hale getirilmeli.

**Dosya:** `backend/app/use_cases/streams/queries/misc_queries.py`

```python
# GetFollowedLiveStreamsQuery.execute() içinde sorgu oluşturulduktan sonra:
query = _apply_block_filter(query, LiveStream.host_id, current_user_id)
# _apply_block_filter zaten import edilmiş, sadece çağrılmıyor
```

### DB / Redis / ARB

Değişiklik yok.

### ⚠️ Etki Bayrakları

- Yok — yalnızca `/following/live` endpoint'ini etkiler.
