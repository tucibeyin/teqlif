# Teqlif — Veri Yapısı Analizi ve Sadeleştirme Planı

**Hedef:** Kullanıcısız sistem, sıfırdan başlama. CPU/RAM/disk dostu, bakımı kolay, tip güvenli veri katmanı.  
**Kapsam:** PostgreSQL modelleri · API şemaları · Flutter modelleri · Genel mimari  
Son güncelleme: 2026-09-20

---

## Genel Tablo

| Katman | Mevcut Durum | Sorun |
|--------|-------------|-------|
| PostgreSQL | 45 tablo, `users` 47 kolon, `listings` 36 kolon | God Object tablolar |
| API Şemaları | 45+ Pydantic sınıfı, kritik endpoint'lerde `response_model` yok | Duplicate, tipsiz |
| Flutter Modelleri | 45+ sınıf, Freezed yok, tümü manuel `fromJson` | Hata riski, kod tekrarı |
| DB PK'ları | `direct_messages`, `notifications` → int4 | Sınır riski |
| DM büyümesi | Normal mesajlar hiç silinmiyor | Sonsuz büyüme |

---

## 1. PostgreSQL — Model Sorunları

### 1.1 [KRİTİK] `users` Tablosu: God Object (47 Kolon)

Tek tabloda birbirinden bağımsız 6 farklı sorumluluk var:

| Sorumluluk | Kolonlar | Çözüm |
|-----------|----------|-------|
| Kimlik doğrulama | email, hashed_password, status, email_verified, phone, phone_verified | `users` çekirdeğinde kal |
| Profil | full_name, username, bio, profile_image_url, profile_image_thumb_url | `users` çekirdeğinde kal |
| Sosyal medya linkleri | website_url, instagram_url, kick_url, twitch_url, facebook_url, youtube_url, tiktok_url | **Ayrı tabloya taşı** |
| Bildirim tercihleri | notification_prefs (JSON) | **Ayrı tabloya taşı** |
| GDPR onayları | cross_border_consent_*, age_confirmed_at | **Ayrı tabloya taşı** |
| ML/Öneri | preference_embedding (Vector384), max_budget | `users`'da kal (JOIN sık) |
| Premium/Plan | is_premium, plan_type, premium_since, tuci_balance | `users`'da kal (sık erişim) |
| Referral | referral_code, referral_code_expires_at, pending_referred_by | **Ayrı tabloya taşı** |
| Onboarding | onboarding_completed, locale, locale_updated_at | `users`'da kal |

**Hedef yapı:**

```
users                    (~18 kolon — sık erişilen her şey)
  id, email, username, full_name, hashed_password,
  status, email_verified, phone, phone_verified,
  profile_image_url, profile_image_thumb_url,
  is_premium, plan_type, tuci_balance,
  preference_embedding, max_budget,
  onboarding_completed, locale, created_at

user_social_links        (opsiyonel, 1:1)
  user_id (PK, FK), website_url, instagram_url, kick_url,
  twitch_url, facebook_url, youtube_url, tiktok_url

user_notification_prefs  (1:1, varsayılan row oluştur)
  user_id (PK, FK), messages, follows, auction_won, ...
  (JSON yerine kolon — tip güvenli, tek UPDATE ile değişir)

user_consents            (1:1)
  user_id (PK, FK), cross_border_given, cross_border_at,
  cross_border_version, cross_border_ip, age_confirmed_at, ...

referrals tablosu zaten var (referral verisi oraya taşınır)
```

**Kazanç:** `users` tablosu ~18 kolona iner. Sosyal medya bölümü %95 NULL olan 7 kolon yerine sadece link varsa row içerir. `notification_prefs` JSON yerine tipli kolonlar olur.

---

### 1.2 [ÖNEMLİ] `listings` Tablosu: 36 Kolon, ML Alanları Karışık

Tabloda 4 farklı sorumluluk bir arada:

| Sorumluluk | Kolonlar |
|-----------|----------|
| Çekirdek ilan | title, price, condition, category, subcategory, status, images_urls, ... |
| ML/Moderasyon | nsfw_score, quality_score, embedding (Vector384), search_vector (TSVECTOR) |
| Reklam bilgisi | (ad_campaign FK üzerinden — bu ayrı tabloda, doğru) |
| Analitik | view_count, like_count (bunlar Redis'te de tutulabileceği için sorgulanabilir) |

**Öneri:** ML alanları nadiren join ediliyor. Ayrı `listing_ml` tablosu (1:1, lazy-loadable) daha temiz. Ama `search_vector` ve `embedding` aktif sorgu yolunda olduğu için `listings`'de kalabilir.

Daha öncelikli: `listings`'in kaç kolonu gerçekten API response'unda expose ediliyor? `GET /listings/{id}` ve `GET /listings` endpoint'lerinde **response_model yok** (bkz. 2.3). Önce bu düzeltilmeli.

---

### 1.3 [KRİTİK] `direct_messages`: int4 PK + Sonsuz Büyüme

Detay `findings.md` önceki versiyonunda belgelendi. Özet:
- `id: Mapped[int]` → int4, max 2.1B. Normal mesajlar hiç silinmiyor.
- **Düzeltme:** BigInteger PK + retention policy (both sides deleted → 365 gün sonra sil)

---

### 1.4 [KRİTİK] `direct_messages`: OR Sorgusu → `thread_id` ile Çöz

`get_messages_query.py:63` — OR sorgusu yerine `thread_id FK` ile tek equality index.
- `message_threads`'e sequential `id BIGINT` ekle
- `direct_messages`'a `thread_id BIGINT NOT NULL FK` ekle
- Index: `(thread_id, id DESC)` → tüm pagination bu single index'i kullanır

---

### 1.5 [ORTA] `notifications` int4 PK

30 günde siliniyor → bounded growth. Ama sıfırdan başlarken BigInteger maliyetsiz.

---

### 1.6 [BİLGİ] `analytics_events` + `user_interactions`: Çift Yazma Kasıtlı

ClickHouse'dan 22 dakika gecikmeli PG'ye kopyalanıyor. Öneri motoru PG JOINs gerektiriyor. Değiştirme — ama 90 günlük cleanup doğrulanmış, bounded.

---

### 1.7 [BİLGİ] `notification_prefs` JSON → Kolon

`users.notification_prefs` JSONB ile saklanıyor (14 alan). Tip güvenliği yok, kısmi güncelleme için whole-document rewrite gerekiyor.  
Çözüm: `user_notification_prefs` ayrı tablo (1.1'deki bölünmeyle birlikte) — 14 bool/int kolon, her biri tekil UPDATE edilebilir.

---

## 2. API Şemaları — Tutarsızlık ve Eksikler

### 2.1 [KRİTİK] Kritik Endpoint'lerde `response_model` Yok

```python
GET  /listings          # en çok çağrılan endpoint — response_model YOK
GET  /listings/{id}     # — response_model YOK
GET  /auth/me           # — response_model YOK (UserOut dönüyor ama tanımsız)
GET  /auth/me/commerce/purchases  # — response_model YOK
GET  /auth/me/commerce/sales      # — response_model YOK
GET  /auth/init         # büyük init endpoint — response_model YOK
```

**Etki:** FastAPI dokümanı yanlış, Pydantic doğrulaması çalışmıyor, type-safety yok. Gelecekte veri sızdırma riski (internal field'lar client'a gidebilir).

**Düzeltme:** Her endpoint'e açık `response_model=` ekle.

---

### 2.2 [ÖNEMLİ] 4 Farklı "Kısmi Kullanıcı" Şeması

Aynı `users` tablosundan 4 ayrı şema:

```python
UserOut        # 26 alan — tam kullanıcı
StoryAuthorOut # 5 alan  — id, username, full_name, 2x image
BlockedUserOut # 4 alan  — id, username, full_name, 1x image
StreamHostOut  # 3 alan  — id, username, full_name
```

**Düzeltme:** Tek base şema:

```python
class UserMiniOut(BaseModel):
    id: int
    username: str
    full_name: str
    profile_image_thumb_url: str | None = None

# Diğerleri extend eder veya doğrudan UserMiniOut kullanır
StoryAuthorOut = UserMiniOut   # + profile_image_url eklenirse
StreamHostOut  = UserMiniOut   # aynen kullanılabilir
BlockedUserOut = UserMiniOut   # aynen kullanılabilir
```

---

### 2.3 [ÖNEMLİ] `DirectSaleSummaryOut`: Flat Birleşik Şema

16 alanda 2 birbirini dışlayan alan grubu:

```python
# role == "seller" → şunlar dolu, buyer alanları None:
total_revenue, total_quantity_sold, order_count, seller_username

# role == "buyer" → şunlar dolu, seller alanları None:
buyer_quantity, buyer_unit_price, buyer_total, buyer_order_status
```

**Düzeltme:** Discriminated union:

```python
class DirectSaleSummaryBase(BaseModel):
    sale_id: int
    item_name: str
    status: str
    # ... ortak alanlar

class DirectSaleSummaryForSeller(DirectSaleSummaryBase):
    role: Literal["seller"]
    total_revenue: float | None
    total_quantity_sold: int | None
    order_count: int | None

class DirectSaleSummaryForBuyer(DirectSaleSummaryBase):
    role: Literal["buyer"]
    buyer_quantity: int
    buyer_unit_price: float
    buyer_total: float
    buyer_order_status: str

DirectSaleSummaryOut = Annotated[
    DirectSaleSummaryForSeller | DirectSaleSummaryForBuyer,
    Field(discriminator="role")
]
```

---

### 2.4 [ORTA] `AuctionStateOut`: 9 Endpoint, 1 Şema

Auction router'ında start/pause/resume/end/bid/accept/buy-it-now hepsi `AuctionStateOut` döndürüyor. Şema hem "başlamadı" hem "teklif var" hem "bitti" durumlarını Optional alanlarla kapsıyor.

Bu tek şema birden fazla durumu yönettiği için alanların hangi durumda dolu olduğu belirsiz. Küçük ama ilerleyen dönemde hata kaynağı.

**Ertelenebilir** — şu an çalışıyor, ama discriminated union'a taşımak temizler.

---

### 2.5 [ORTA] `UserOut`: 26 Alan, 7 Sosyal Medya URL

`UserOut`'un her response'da 7 sosyal URL alanı taşıması gerekiyor mu? Bu alanların büyük çoğunluğu `None`.

Öneri: `UserOut` sadeleştirilmiş (~15 alan) + ayrı `UserProfileOut` (sosyal linkler dahil, profil sayfası için).

---

### 2.6 [ORTA] `ConversationOut` `is_request` Flag Anti-Pattern

```python
# /conversations ve /requests aynı şemayı döndürüyor
# is_request: bool=False alanı ile ayrılıyor
class ConversationOut(BaseModel):
    is_request: bool = False  # boolean flag ile iki farklı kavramı birleştirme
```

Daha açık: `ConversationOut` ve `MessageRequestOut` ayrı şemalar.

---

### 2.7 [DÜŞÜK] `StoryItemOut`: İki Farklı Story Tipi, Tek Şema

`story_type='video'` için `video_url`, `thumbnail_url` dolu; `story_type='live_redirect'` için `stream_id` dolu, diğerleri None. Discriminated union daha temiz olur.

---

## 3. Flutter Modelleri — Bakım Riski

### 3.1 [KRİTİK] Freezed Yok — 45+ Sınıf Manuel `fromJson`

Tüm modeller elle yazılmış `factory X.fromJson(Map<String, dynamic> json)` ile ayrıştırılıyor. Sorunlar:

- API'de alan adı veya tipi değiştiğinde runtime hata (compile-time değil)
- `copyWith` metotları bazı modellerde hiç yok → state yönetimi zorlaşıyor
- Kod tekrarı: 45+ `fromJson` → her model değişikliğinde elle güncelleme

**Düzeltme:** Freezed + json_serializable ekle. Tüm modelleri generate et.

```dart
@freezed
class StreamOut with _$StreamOut {
  const factory StreamOut({
    required int id,
    required String roomName,
    required String title,
    required String category,
    required int viewerCount,
    required StreamHost host,
    String? subcategory,
    String? thumbnailUrl,
  }) = _StreamOut;

  factory StreamOut.fromJson(Map<String, dynamic> json) =>
      _$StreamOutFromJson(json);
}
```

---

### 3.2 [ÖNEMLİ] Tiplanmamış Dinamik Alanlar

```dart
// ChatMessage
Map<String, dynamic>? announcementPayload  // tip yok

// IncomingCallTapSignal / IncomingCallAutoAcceptSignal
Map<String, dynamic> data  // ham veri

// ListingFilterState
Map<String, dynamic> extraFields  // katalogdan gelen dinamik alanlar
```

`announcementPayload` için backend'deki announcement tiplerini listeleyip sealed class yap.  
`IncomingCallTapSignal.data` için de tip güvenliği eklenebilir.  
`ListingFilterState.extraFields` kasıtlı — katalog dinamik, bu kabul edilebilir.

---

### 3.3 [ORTA] `ProInsightsData`: 11 Sınıf, 1 Ekran

`pro_insights_data.dart` sadece `pro_insights_screen.dart`'ta kullanılıyor ama 11 sınıf içeriyor. Dosya iyi organize edilmiş ama `ProInsightsData` üst modeli 7 nested obje içeriyor. Bu veri yapısı backend'den geliyor — backend'de de aynı komplekslık var.

Uzun vadede bu ekranın "Pro" paketini sadeleştirip almak istediği veriyi küçültmek düşünülebilir.

---

### 3.4 [ORTA] `direct_sale.dart`: 6 Sınıf Tek Dosyada

`DirectSaleState`, `DirectSaleOrder`, `DirectSaleSummary`, `CommercePurchase`, `CommerceSale`, `ListingPriceSignal` → farklı amaçlar için ayrı dosyalar daha iyi.

---

### 3.5 [ORTA] `StreamTokenOut` vs `JoinTokenOut` Örtüşmesi

Her ikisi de LiveKit bağlantı bilgisi içeriyor. Fark: `JoinTokenOut`'ta `title`, `host_username`, `host_livekit_identity` ek alanlar var. Ortak base class veya tek şema + optional alanlar daha temiz olur.

---

### 3.6 [BİLGİ] Çağrı Altyapısı Kompleks ama İyi Yapılandırılmış

`lib/call/` altında 15 dosya: repository, hardware adapter, state machine, room adapter, routing. En karmaşık alt modül ama sorumluluklar iyi ayrılmış. Değiştirilmesi gerekmez.

---

## 4. Öncelik Sırası — Sıfırdan Başlarken

### Hemen Yapılacaklar (DB sıfır, ucuz)

| # | Eylem | Konum | Etki |
|---|-------|-------|------|
| 1 | `direct_messages` + `notifications` BigInteger PK | `models/message.py`, `models/notification.py` | Sınır riski ortadan kalkar |
| 2 | `direct_messages`'a `thread_id` FK + index | `models/message.py` + migration | OR sorgusu kaldırılır |
| 3 | `direct_messages` retention policy | `worker.py` | Sonsuz büyüme durur |
| 4 | `users` tablosu bölünmesi | `models/user.py` + 3 yeni model | God Object çözülür |
| 5 | `notification_prefs` JSON → ayrı tablo | `models/user_notification_prefs.py` | Tip güvenliği |
| 6 | `response_model` tüm endpoint'lere | `routers/listings.py`, `auth.py` | Güvenlik + dokümantasyon |
| 7 | `UserMiniOut` base schema | `schemas/user.py` | 4 duplicate şema azalır |
| 8 | `DirectSaleSummaryOut` discriminated union | `schemas/direct_sale.py` | Tip belirsizliği gider |

### Kısa Vadede (kod kalitesi)

| # | Eylem | Konum | Etki |
|---|-------|-------|------|
| 9 | Freezed + json_serializable ekle | Flutter `models/` | 45+ manuel fromJson ortadan kalkar |
| 10 | `ChatMessage.announcementPayload` tiplendir | `models/chat.dart` | Runtime hata azalır |
| 11 | `UserOut` sadeleştir + `UserProfileOut` ekle | `schemas/user.py` | 7 boş sosyal URL kaldırılır |
| 12 | `ConversationOut` / `MessageRequestOut` ayrı | `schemas/message.py` | is_request flag kaldırılır |

### Orta Vadede (ölçek)

| # | Eylem | Tetikleyici |
|---|-------|-------------|
| 13 | ClickHouse Materialized Views | user_events 20M+ satır |
| 14 | `direct_messages` partitioning | 50M+ satır |
| 15 | `AuctionStateOut` discriminated union | Auction logic karmaşıklaşırsa |

### Eskimiş (yapılmış veya gereksiz)

| Bulgu | Durum |
|-------|-------|
| Redis Streams (Pub/Sub yerine) | **Tamamlandı** — xadd kullanılıyor |
| ClickHouse Dictionaries | **Gereksiz** — LowCardinality zaten var |
| Redis Pool darboğazı | **İzleme** — 440 max conn, Redis 10K limit, sorun yok |

---

## 5. Karmaşıklık Özeti

```
Toplam tablo         : 45
Toplam şema sınıfı   : 45+ Pydantic + 45+ Flutter
Toplam ekran         : 49 (Flutter)
Toplam Dart dosyası  : 259

God Object tablolar  : users (47 kolon), listings (36 kolon)
Tip güvensiz         : listings, auth major endpoint'leri (response_model yok)
Duplicate şemalar    : 4x partial user, DirectSaleSummaryOut union
Manuel fromJson      : 45+ Flutter sınıfı (Freezed yok)
Sonsuz büyüme riski  : direct_messages (normal mesajlar silinmiyor)
Sınır riski          : direct_messages.id, notifications.id → int4
```

En az eforla en fazla kazanç sağlayacak 3 hamle:

1. **`users` tablosunu böl** → her şeyin kaynağındaki şişkinlik gider
2. **`response_model` ekle** → tip güvenliği + API dokümantasyonu düzelir  
3. **Freezed ekle** → Flutter'daki tüm manuel model bakımı ortadan kalkar
