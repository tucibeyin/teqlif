# Teqlif — Lightweight Veri Mimarisi Uygulama Planı

**Hedef:** CPU/RAM/disk/bant genişliği dostu, endüstri standardında, sıfırdan doğru kurulmuş veri katmanı.  
**Bağlam:** Sistem henüz kullanıcıya açık değil — migration maliyeti sıfır, her düzeltme şimdi yapılır.  
Son güncelleme: 2026-09-20

> **Tamamlanan acil aksiyon:** `POST /analytics/price-estimate` ve `GET /ai-price-credits` durduruldu (`analytics.py`). Her çağrıda tetiklenen numpy/scipy KDE, ARQ embedding görevi ve 150 satır pgvector sorgusu artık çalışmıyor. Kod korundu — Faz 7 tamamlanınca açılacak.

Her faz bağımsız uygulanabilir. Sıra önemlidir: üst katmanlar alttaki düzeltmelere bağımlıdır.

---

## Faz 0 — Finansal Veri Tipi Düzeltmesi *(en kritik, ilk yapılacak)*

### Problem

Para değerleri `Float` (IEEE 754) ile saklanıyor. `Float` ikili kayan noktalı aritmetik kullandığından para hesaplarında hata birikir:

```python
>>> 0.1 + 0.2
0.30000000000000004
```

Etkilenen tablolar ve kolonlar:

| Tablo | Kolon | Mevcut | Olması Gereken |
|-------|-------|--------|----------------|
| `listings` | `price` | `Float` | `Numeric(10, 2)` |
| `listings` | `buy_it_now_price` | `Float` | `Numeric(10, 2)` |
| `listings` | `last_sold_price` | `Float` | `Numeric(10, 2)` |
| `listings` | `last_start_price` | `Float` | `Numeric(10, 2)` |
| `auctions` | `start_price` | `Float` | `Numeric(10, 2)` |
| `auctions` | `buy_it_now_price` | `Float` | `Numeric(10, 2)` |
| `auctions` | `final_price` | `Float` | `Numeric(10, 2)` |
| `bids` | `amount` | `Float` | `Numeric(10, 2)` |
| `purchases` | `price` | `Float` | `Numeric(10, 2)` |
| `direct_sales` | `price` | `Numeric(10,2)` | ✅ Zaten doğru |
| `direct_sale_orders` | `unit_price` | `Numeric(10,2)` | ✅ Zaten doğru |

`nsfw_score`, `quality_score`, `duration_seconds` → bunlar ölçüm değeri, Float kabul edilebilir.

### Çözüm

```python
# models/listing.py, auction.py, bid.py, purchase.py
from sqlalchemy import Numeric

price: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2), nullable=True)
```

Python tip: `from decimal import Decimal` + `Mapped[Optional[Decimal]]`

### Etki

API'den gelen değerler Pydantic'te `float` olarak parse edilip DB'ye yazılıyor. Pydantic şemalarında da `Decimal` tipine geçilmesi gerekecek (Faz 4 ile birlikte).

---

## Faz 1 — PostgreSQL Şema Yeniden Tasarımı

### 1.1 BigInteger PK'lar

**Etkilenen tablolar:**

| Tablo | Neden Kritik |
|-------|-------------|
| `direct_messages` | Normal mesajlar hiç silinmiyor → sonsuz büyüme |
| `notifications` | 30 günde siliniyor → bounded, ama maliyetsiz |
| `listings` | Her aktif kullanıcı birden fazla ilan açabilir |
| `analytics_events` | 90 günde siliniyor → bounded |
| `user_interactions` | 90 günde siliniyor → bounded |
| `bids` | Yoğun yayınlarda çok satır |
| `calls` | Bounded ama büyüyebilir |

```python
# Tüm etkilenen modellerde:
from sqlalchemy import BigInteger
id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
```

FK kolonları da BigInteger olmalı:
```python
sender_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id", ...), ...)
```

### 1.2 direct_messages — thread_id + OR Sorgusu Kaldırma

**Problem:** `get_messages_query.py:63` — OR sorgusu: 2× Index Scan + BitmapOr + Heap Fetch.  
`message_threads` zaten canonical pair (`user_a < user_b`) tutuyor. Eksik: DM'de `thread_id` yok.

**Çözüm:**

```python
# models/message_thread.py — sequential PK ekle
id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
# Eski composite uniqueness constraint olarak koru:
__table_args__ = (
    UniqueConstraint("user_a_id", "user_b_id", name="uq_thread_pair"),
    Index("ix_message_threads_user_b", "user_b_id"),
)
```

```python
# models/message.py — thread_id ekle
thread_id: Mapped[int] = mapped_column(
    BigInteger, ForeignKey("message_threads.id", ondelete="CASCADE"), nullable=False
)
__table_args__ = (
    Index("ix_dm_thread_created", "thread_id", "id"),       # pagination için
    Index("ix_dm_receiver_is_read", "receiver_id", "is_read"),
    Index("ix_dm_content_type_created", "content_type", "created_at"),
)
```

```python
# use_cases/messages/queries/get_messages_query.py — OR kaldır
base_where = [
    DirectMessage.thread_id == thread_id,   # tek equality check
    ~and_(DirectMessage.sender_id == uid, DirectMessage.deleted_for_sender == True),
    ~and_(DirectMessage.receiver_id == uid, DirectMessage.deleted_for_receiver == True),
]
```

### 1.3 direct_messages — Retention Policy

```python
# worker.py — cleanup_hidden_messages_task'a ek kural:
DELETE FROM direct_messages
WHERE deleted_for_sender = TRUE
  AND deleted_for_receiver = TRUE
  AND created_at < NOW() - INTERVAL '365 days'
```

### 1.4 users — God Object Bölünmesi (47 kolon → ~18)

**Mevcut 47 kolon → 4 tabloya bölünür:**

**`users` (core, ~18 kolon — her request'te okunur):**
```python
id (BigInteger PK), email, username, full_name, hashed_password,
status (Enum), email_verified, phone, phone_verified,
profile_image_url, profile_image_thumb_url,
is_premium, plan_type, tuci_balance,
preference_embedding (Vector384), max_budget,
onboarding_completed, locale, created_at
```

**`user_social_links` (1:1, sadece dolu olduğunda row var):**
```python
user_id (BigInteger PK FK), website_url, instagram_url, kick_url,
twitch_url, facebook_url, youtube_url, tiktok_url, updated_at
```

**`user_notification_prefs` (1:1, her kullanıcı için row oluştur):**
```python
user_id (BigInteger PK FK),
messages (bool=True), follows (bool=True), auction_won (bool=True),
stream_started (bool=True), new_listing (bool=True), new_bid (bool=True),
outbid (bool=True), smart_alert (bool=True), ratings (bool=True),
receive_blast_notifications (bool=True),
bid_threshold_tl (int=0),
quiet_hours_enabled (bool=False), quiet_from (str="22:00"), quiet_to (str="08:00")
```

JSON yerine tipli kolonlar → kısmi UPDATE mümkün, type-safe.

**`user_consents` (1:1, GDPR):**
```python
user_id (BigInteger PK FK),
age_confirmed_at (DateTime?),
cross_border_given (bool=False), cross_border_at (DateTime?),
cross_border_version (String(10)?), cross_border_ip (String(45)?),
cross_border_locale (String(5)?), cross_border_revoked_at (DateTime?)
```

Referral verileri zaten `referrals` tablosuna taşınabilir.

### 1.5 listings — image_urls Text → JSONB + Tekrarlayan Kolon

`listings.image_url` (String) ve `listings.image_urls` (Text/JSON string) → iki ayrı kolon, biri gereksiz.

```python
# Mevcut:
image_url: String(500)        # tek görsel
image_urls: Text               # JSON string array — tip güvensiz

# Olması gereken:
image_urls: JSONB              # ["url1", "url2", ...] — ilk eleman ana görsel
# image_url kaldırılır, image_urls[0] kullanılır
```

`Text` yerine `JSONB` → PostgreSQL JSON operatörleri çalışır, partial update mümkün, GIN index eklenebilir.

### 1.6 String Enum'lar → PostgreSQL ENUM

Durum alanları string yerine ENUM olmalı — geçersiz değer DB seviyesinde reddedilir, disk daha verimli.

| Tablo | Kolon | Mevcut | Olması Gereken |
|-------|-------|--------|----------------|
| `direct_messages` | `content_type` | String(20) | ENUM: text/image/video/voice/file |
| `follows` | `status` | String(20) | ENUM: pending/accepted/declined |
| `calls` | `status` | String(20) | ENUM: calling/active/ended/missed/rejected |
| `message_threads` | `status` | String(20) | ENUM: pending/accepted/declined |
| `direct_sales` | `status` | String(20) | ENUM: active/paused/ended/cancelled |
| `auctions` | `status` | String(20) | ENUM: active/paused/ended |

`UserStatus`, `ListingStatus` zaten ENUM — doğru pattern, diğerlerine de uygulanmalı.

### 1.7 URL String Uzunlukları

MinIO URL formatı: `http://minio1.teqlif.com:9010/teqlif/uuid.ext` ≈ 60 karakter.  
Tüm URL kolonları `String(500)` → `String(255)` yeterli. Disk ve buffer cache tasarrufu.

---

## Faz 2 — Media Pipeline

### 2.1 Görsel Yükleme: Kayıpsız WebP'ye Çevir

**Mevcut:** Yüklenen format ne ise (JPG, PNG, GIF, WebP) olduğu gibi saklanıyor.  
Thumbnail: 400×400, JPEG quality=85.

**Sorun:** 5MB PNG yüklenir → 5MB PNG saklanır. WebP aynı kalitede %25-35 daha küçük.

**Çözüm:** `upload.py` ve `media_processor.py:ImageProcessor`'da sunucu tarafında WebP'ye çevir:

```python
# media_processor.py — make_thumbnail yerine tam dönüşüm
def convert_to_webp(data: bytes, max_dim: int = 1600, quality: int = 82) -> bytes:
    """Orijinal görseli WebP'ye çevirir, max_dim kısa kenarını sınırlar."""
    img = Image.open(io.BytesIO(data))
    try:
        from PIL import ImageOps
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")
    # Uzun kenarı max_dim ile sınırla, oranı koru
    img.thumbnail((max_dim, max_dim), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=quality, method=4)
    return buf.getvalue()

def make_thumbnail_webp(data: bytes, size: int = 400) -> bytes:
    """400x400 WebP thumbnail."""
    img = Image.open(io.BytesIO(data))
    # ... (mevcut crop logic)
    img.save(buf, format="WEBP", quality=75, method=4)
    return buf.getvalue()
```

**Depolama key değişikliği:** `.jpg/.png` → `.webp`

**İlan görseli limiti:** 5MB → WebP dönüşümü sonrası ortalama boyut ~400-800KB.

### 2.2 Listing Videosu: Gerçek Transcode

**Mevcut:** `ffmpeg -c:v copy` — video stream kopyalanıyor, yeniden kodlanmıyor.  
50MB H.265 veya ProRes yüklenir → 50MB olduğu gibi saklanır.

**Sorun:**
- Depolama maliyeti kontrolsüz
- CDN bant genişliği yüksek
- Format uyumluluk sorunu (bazı cihazlar H.265 oynatamaz)
- Progressive streaming çalışmıyor (faststart var ama bitrate normalize değil)

**Çözüm:** Gerçek transcode pipeline:

```python
# upload.py — _process_listing_video değişikliği
compress_cmd = [
    "ffmpeg", "-y", "-i", src,
    "-c:v", "libx264",          # H.264 — evrensel uyumluluk
    "-crf", "28",               # ~1-3 Mbps 1080p için (23 yüksek kalite, 28 makul)
    "-preset", "fast",          # encode hızı / sıkıştırma dengesi
    "-vf", "scale=-2:720",      # 720p — 1080p gereksiz yük
    "-c:a", "aac", "-b:a", "96k",  # ses 128k'dan 96k'ya
    "-movflags", "+faststart",  # progressive HTTP streaming
    "-t", str(int(LISTING_VIDEO_MAX_SECS)),
    video_path,
]
```

**Beklenen boyut:** 60 saniyelik 720p H.264 CRF28 ≈ 8-15MB (mevcut max 50MB'dan çok daha az).

**Gereklilik:** node1 (medya sunucusu) ve worker node'larında `libx264` ile derlenmiş FFmpeg.  
Kontrol: `ffmpeg -codecs | grep libx264`

### 2.3 DM Videosu: Thumbnail Kalitesi Düzeltmesi

**Mevcut:** `ffmpeg -q:v 2` ile thumbnail — bu yüksek kalite (1=en iyi, 31=en düşük). İyi.  
Ama DM videosu için de transcode yok.

**Kısa vadede:** DM videosu için de basit normalize (scale=720, CRF28, faststart).  
Limit: `VIDEO_MAX_BYTES = 30MB` → transcode sonrası ~5-8MB.

### 2.4 URL'lerin DB'de Saklanma Biçimi

**Mevcut:** Tam MinIO URL saklanıyor: `http://minio1.teqlif.com:9010/teqlif/uuid.webp`

**Sorun:** MinIO node değişirse, domain değişirse, protocol değişirse → tüm URL'ler bozulur. Milyonlarca satır UPDATE gerekir.

**Çözüm:** Sadece `key` sakla, URL çalışma zamanında oluştur:

```python
# Mevcut: "http://minio1.teqlif.com:9010/teqlif/abc123.webp" (56 bytes)
# Öneri:  "abc123.webp" (11 bytes) — ~5× daha kısa

# URL oluşturmak için:
def build_url(key: str) -> str:
    return f"{settings.uploads_base_url}/{key}"
```

Bu değişiklik URL kolonlarını `String(255)` → `String(100)` altına çeker.

**Not:** Bu değişiklik `storage_service.py` ve tüm URL dönen endpoint'leri etkiler. Faz 4 API temizliğiyle birlikte yapılmalı.

### 2.5 Profil Görseli: Boyut Sınırı

**Mevcut:** `IMAGE_MAX_BYTES = 5MB` — profil görseli için çok büyük.

**Öneri:**
```python
PROFILE_IMAGE_MAX_BYTES = 2 * 1024 * 1024   # 2MB → WebP 800px → ~100-200KB
LISTING_IMAGE_MAX_BYTES = 5 * 1024 * 1024   # 5MB → WebP 1600px → ~200-500KB
```

Profil görseli `max_dim=800`, ilan görseli `max_dim=1600`.

### 2.6 Medya Sil → Storage Temizliği

**Mevcut:** Mesaj silindiğinde MinIO'dan silme var (`storage.delete_object`). Listing silindiğinde var mı? Kontrol gerekli.

---

## Faz 3 — Redis Denetimi

### 3.1 TTL'siz Key'ler

Aşağıdaki key'ler `set()` ile yazılıyor, TTL yok:

| Dosya | Key Pattern | Risk | Çözüm |
|-------|-------------|------|-------|
| `webhooks.py:259` | `live:viewers:{stream_id}` | Stream biterse key kalır | Stream sonunda DEL veya `ex=86400` |
| `chat_commands.py:169` | `live:viewers:{stream_id}` | Aynı | Aynı |
| `direct_sale_redis.py:70` | `stock:{sale_id}` | Sale biterse key kalır | Sale sonunda DEL veya `ex=86400` |
| `start_stream.py:94` | Stream key | Stream sonunda temizleniyor mu? | Kontrol + TTL |
| `circuit_breaker.py` | Circuit state key | Kalıcı devre durumu | `ex=3600` |

**Düzeltme şablonu:**
```python
# TTL'siz:
await redis.set(key, 0)

# TTL'li:
await redis.set(key, 0, ex=86400)  # veya stream/sale ömrüne göre
```

### 3.2 `direct_sale_redis.py` — Stok Sayacı

`stock:{sale_id}` key'i `redis.set(stock_key, total_stock)` ile yazılıyor.  
Sale bittiğinde bu key temizleniyor mu? Hayır.

```python
# Düzeltme: sale sonunda
await redis.delete(f"stock:{sale_id}")
# veya yazarken TTL ekle:
await redis.set(f"stock:{sale_id}", total_stock, ex=86400)
```

### 3.3 `_redis_blpop` vs `_redis_stream` — Pool Kullanım Denetimi

`_redis_blpop`: BLPOP için, socket_timeout=None. Şu an hangi kodlar kullanıyor?

```bash
grep -rn "get_redis_blpop\|get_redis_stream" backend/app/ --include="*.py"
```

Eğer `_redis_blpop` hiç kullanılmıyorsa kaldırılabilir (pool tasarrufu).

### 3.4 Feed Cache — TTL Tutarlılığı

```python
# routers/feed.py
await redis.expire(key, 14 * 86400)   # for-you feed cursor: 14 gün
await redis.setex(cache_key, 900, ...)  # listing cache: 15 dk
```

For-you feed cursor 14 gün makul. Listing cache 15 dk. TTL'ler mantıklı.

---

## Faz 4 — API Şema Temizliği

### 4.1 response_model Tüm Endpoint'lere

```python
# routers/listings.py
@router.get("", response_model=Page[ListingOut])
@router.get("/{id}", response_model=ListingOut)

# routers/auth.py
@router.get("/me", response_model=UserOut)
@router.get("/init", response_model=InitResponse)
@router.get("/me/commerce/purchases", response_model=Page[CommercePurchaseOut])
@router.get("/me/commerce/sales", response_model=Page[CommerceSaleOut])
```

### 4.2 UserMiniOut — Duplicate Şema Birleştirme

```python
# schemas/user.py
class UserMiniOut(BaseModel):
    id: int
    username: str
    full_name: str
    profile_image_thumb_url: str | None = None
    model_config = ConfigDict(from_attributes=True)

# Türevler:
class StreamHostOut(UserMiniOut): pass          # aynı
class BlockedUserOut(UserMiniOut): pass         # aynı
class StoryAuthorOut(UserMiniOut):
    profile_image_url: str | None = None        # ek alan
```

### 4.3 DirectSaleSummaryOut — Discriminated Union

```python
class DirectSaleSummaryBase(BaseModel):
    sale_id: int; item_name: str; status: str
    proof_image_url: str | None = None; image_url: str | None = None
    end_reason: str | None = None; ended_at: datetime | None = None

class DirectSaleSummaryForSeller(DirectSaleSummaryBase):
    role: Literal["seller"]
    total_revenue: Decimal | None = None
    total_quantity_sold: int | None = None
    order_count: int | None = None
    seller_username: str | None = None

class DirectSaleSummaryForBuyer(DirectSaleSummaryBase):
    role: Literal["buyer"]
    buyer_quantity: int; buyer_unit_price: Decimal; buyer_total: Decimal
    buyer_order_status: str

DirectSaleSummaryOut = Annotated[
    DirectSaleSummaryForSeller | DirectSaleSummaryForBuyer,
    Field(discriminator="role")
]
```

### 4.4 UserOut Sadeleştirme

```python
# UserOut — core (her request'te)
class UserOut(BaseModel):
    id: int; email: str; username: str; full_name: str
    status: UserStatus; is_verified: bool; created_at: datetime
    is_private: bool = False; phone_verified: bool = False
    is_premium: bool = False; plan_type: str | None = None
    onboarding_completed: bool = False; locale: str = "tr"
    profile_image_url: str | None = None
    profile_image_thumb_url: str | None = None
    tuci_balance: int = 100

# Sosyal linkler ayrı endpoint (profil sayfası için):
class UserProfileOut(UserOut):
    bio: str | None = None
    # user_social_links join'den gelir:
    website_url: str | None = None
    instagram_url: str | None = None
    # ...
```

### 4.5 price Alanları — Decimal

```python
# schemas'ta:
from decimal import Decimal
price: Decimal | None = None
# Pydantic otomatik JSON serialize eder ("12.50" string olarak)
```

### 4.6 ConversationOut — is_request Kaldır

```python
class ConversationOut(BaseModel):     # /conversations
    user_id: int; username: str; full_name: str
    last_message: str; last_at: datetime
    unread_count: int; last_message_type: str = "text"

class MessageRequestOut(BaseModel):   # /requests
    # Aynı alanlar + request'e özgü
    initiator_id: int; status: str
```

---

## Faz 5 — ClickHouse Optimizasyonu

### 5.1 Materialized View — Günlük Reklam İstatistikleri

`ads.py:338,352,375` — her API çağrısında `SELECT COUNT FROM user_events WHERE ...` tam tablo taraması.

```sql
CREATE MATERIALIZED VIEW mv_ad_daily_stats
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (item_type, item_id, event_type, day)
AS
SELECT
    item_type,
    item_id,
    event_type,
    toDate(timestamp) AS day,
    countState() AS cnt
FROM user_events
GROUP BY item_type, item_id, event_type, day;

-- Sorgu:
SELECT item_id, event_type, countMerge(cnt) AS total
FROM mv_ad_daily_stats
WHERE item_type = 'listing' AND day >= today() - 7
GROUP BY item_id, event_type;
```

### 5.2 ORDER BY Uyumu Kontrolü

`user_events` ORDER BY: `(timestamp, item_id)` — sık sorgu: `WHERE item_type = 'X' AND item_id = Y`.  
Bu sorguda `item_id` ikinci sırada, `item_type` hiç yok → tam index fayda sağlamıyor.

```sql
-- Mevcut:
ORDER BY (timestamp, item_id)

-- Öneri (reklam/ilan sorgularına göre):
ORDER BY (item_type, item_id, timestamp)
```

Ama bu değişiklik tablonun tüm verilerini yeniden sıralar. Sıfırdan başlarken doğru ORDER BY ile kur.

---

## Faz 6 — Flutter Model Katmanı

### 6.1 Freezed + json_serializable

```yaml
# pubspec.yaml
dependencies:
  freezed_annotation: ^2.4.x
  json_annotation: ^4.9.x

dev_dependencies:
  freezed: ^2.4.x
  json_serializable: ^6.8.x
  build_runner: ^2.4.x
```

```dart
// models/stream.dart — sonrası
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
  factory StreamOut.fromJson(Map<String, dynamic> json) => _$StreamOutFromJson(json);
}
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 6.2 ChatMessage.announcementPayload — Tip Güvenliği

```dart
// Mevcut:
Map<String, dynamic>? announcementPayload

// Olması gereken — sealed class:
@freezed
sealed class AnnouncementPayload with _$AnnouncementPayload {
  const factory AnnouncementPayload.auctionResult({
    required String winner, required double amount,
  }) = AuctionResultPayload;
  const factory AnnouncementPayload.saleEnded({
    required int totalSold,
  }) = SaleEndedPayload;
  // ...
}
```

### 6.3 Decimal Fiyatlar Flutter'da

Pydantic artık `Decimal` döndürdüğünde JSON'da string ("12.50") gelir.

```dart
// Yanlış:
final double price = json['price'] as double;  // null safety sorunu

// Doğru:
final String priceStr = json['price']?.toString() ?? '0';
final double price = double.parse(priceStr);
// veya money_formatter gibi bir paket
```

---

## Uygulama Sırası Özeti

```
Faz 0: Float → Numeric  (listing.py, auction.py, bid.py, purchase.py)
  ↓
Faz 1: PostgreSQL şema
  1.1 BigInteger PKlar
  1.2 thread_id + OR kaldır
  1.3 DM retention
  1.4 users bölünmesi
  1.5 image_urls → JSONB
  1.6 String → ENUM
  1.7 URL String(500) → String(255)
  ↓
Faz 2: Media pipeline
  2.1 WebP dönüşümü
  2.2 Video transcode
  2.3 DM video normalize
  2.4 URL'ler DB'de key olarak sakla (Faz 4 ile birlikte)
  ↓
Faz 3: Redis TTL denetimi
  ↓
Faz 4: API şema temizliği
  response_model + UserMiniOut + DirectSaleSummaryOut + Decimal
  ↓
Faz 5: ClickHouse MV + ORDER BY
  ↓
Faz 6: Flutter Freezed + Decimal + AnnouncementPayload
  ↓
Faz 7: ML Feature Pipeline  [price-estimate şu an DURDURULDU]
  ↓
Faz 8: Finansal Audit Trail
  ↓
Faz 9: KVKK / Veri Silme Zinciri
  ↓
Faz 10: Veri Kalite Monitörü
  ↓
Faz 11: Outbox Pattern (opsiyonel)
```

---

---

## Faz 7 — ML Feature Pipeline *(price-estimate şu an durduruldu)*

### Durum

`POST /analytics/price-estimate` → **503 FEATURE_TEMPORARILY_DISABLED** (analytics.py:496-498).  
`GET /ai-price-credits` → **Sabit boş yanıt** döndürüyor.  
Kod silinmedi — bu faz tamamlandığında erken return kaldırılır.

### Neden Durduruldu

Her `/price-estimate` çağrısında tetiklenen yük:
- ARQ worker'a `generate_embedding_task` → model inference (CPU yoğun)
- 150 satır `pgvector` `<=>` distance sorgusu
- `numpy` + `scipy.stats.gaussian_kde` her request'te import + hesap
- Redis'te embedding cache (7 gün TTL — büyüme kontrolsüz)

### Yeniden Açılabilmesi İçin Gerekli Altyapı

**7.1 Listing Embedding Pipeline (Zaten Kısmen Var)**

`generate_listing_embedding_task` listing oluşturulunca çalışıyor (`listings.py:205`). Bu iyi.  
Eksik: **toplu backfill** — mevcut listing'lerin `embedding` kolonu NULL.

```python
# worker.py — yeni scheduled task
@cron(hour=2, minute=0)  # Her gece 02:00
async def backfill_listing_embeddings(ctx):
    """embedding IS NULL olan listing'ler için embedding üret (max 500/gece)."""
```

**7.2 User Preference Embedding — Güncelleme Stratejisi**

Şu an cold start trigger (3/5/10/20 etkileşimde) mevcut ama:
- `update_user_preference_embedding` task ne yapıyor? Hangi modelle vektör üretiyor?
- Embedding vektörü kayıtlı mı yoksa sadece hesaplanıp kullanılıyor mu?

Bu soruları cevaplamadan `price-estimate`'i açmak anlamsız — cold start sorununu çözmez.

**7.3 Embedding Cache Kontrolü**

```python
# Cache key: f"cache:embedding:{md5(text)}"  — TTL: 7 gün
# Sorun: farklı kullanıcılar aynı text → aynı cache, bu doğru
# Sorun: cache boyutu büyüdükçe Redis memory artar
# Çözüm: TTL'yi 24 saate indir (price-estimate açılınca)
await redis.setex(emb_cache_key, 86400, emb_str)
```

**7.4 scipy/numpy — Lazy Import Koruma**

```python
# Her request'te import etmek yavaş. Endpoint açılınca module-level import:
import numpy as np
from scipy.stats import gaussian_kde
# analytics.py başına taşı
```

**7.5 Price-Estimate Açılış Kontrolü**

```python
# Şu an kapalı (analytics.py:496):
raise _HTTPException(status_code=503, detail={"code": "FEATURE_TEMPORARILY_DISABLED"})
# Açmak için bu 2 satırı kaldır, docstring güncelle.
```

---

## Faz 8 — Finansal Audit Trail

### Problem

`bids`, `purchases`, `direct_sale_orders` mutable satırlar. Bir satır güncellendiğinde önceki değer kaybolur.  
Muhasebe, fraud detection ve KVKK için finansal işlemlerin **değişmez geçmişi** zorunlu.

### Çözüm

```sql
CREATE TABLE financial_events (
    id          BIGSERIAL PRIMARY KEY,
    event_type  TEXT NOT NULL,        -- 'bid_placed', 'bid_cancelled', 'purchase_created',
                                      --   'auction_ended', 'sale_ended', 'refund'
    entity_type TEXT NOT NULL,        -- 'bid', 'purchase', 'direct_sale_order', 'auction'
    entity_id   BIGINT NOT NULL,
    amount      NUMERIC(10, 2) NOT NULL,
    currency    TEXT NOT NULL DEFAULT 'TRY',
    actor_id    BIGINT REFERENCES users(id) ON DELETE SET NULL,
    metadata    JSONB,                -- ek bağlam (karşı taraf, ödeme yöntemi, vb.)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sadece ekle, hiç güncelleme/silme yok
-- Row-level security: sadece INSERT izni
CREATE INDEX ix_fe_entity ON financial_events (entity_type, entity_id);
CREATE INDEX ix_fe_actor   ON financial_events (actor_id, created_at);
```

### Tetikleyici Noktalar

| Olay | Dosya | Eklenecek satır |
|------|-------|-----------------|
| Bid placed | `bid_commands.py` | `financial_events` INSERT |
| Bid cancelled | `bid_commands.py` | `financial_events` INSERT |
| Auction ended | `auction_commands.py` | `financial_events` INSERT |
| Purchase created | `purchase_commands.py` | `financial_events` INSERT |
| Direct sale order | `direct_sale_commands.py` | `financial_events` INSERT |

---

## Faz 9 — KVKK / Veri Silme Zinciri

### Yasal Yükümlülük

KVKK md.7: kişisel veri "ilgili kişinin talebiyle" silinmeli ya da anonimleştirilmeli.  
Şu an `DELETE /auth/me` endpoint'i var mı? Varsa ne yapıyor?

```bash
grep -rn "delete_account\|account.*delete\|DELETE.*users" backend/app/routers/ --include="*.py"
```

### Silme Zinciri Tasarımı

```
Kullanıcı "Hesabı Sil" isteği
  ↓
users.status = "pending_deletion"
users.deletion_requested_at = NOW()
  ↓
30 gün sonra scheduled worker:
  ├── users: email/phone → "deleted_{id}@deleted.com", full_name → "Silinmiş Kullanıcı"
  ├── direct_messages: content → "[silindi]", media_url → NULL  (satır kalır, thread korunur)
  ├── listings: soft delete, görsel URL'leri MinIO'dan sil
  ├── MinIO: profil görseli sil
  ├── user_notification_prefs: sil
  ├── user_social_links: sil
  ├── analytics_events (ClickHouse): user_id → 0 (UPDATE — CH'da yavaş, batch ile)
  └── user_interactions (ClickHouse): user_id → 0
```

### financial_events İstisnası

Finansal kayıtlar (`financial_events`) KVKK kapsamında 10 yıl saklanmalı (Türk Ticaret Kanunu).  
`actor_id` → `NULL` yapılır, `metadata` içindeki PII temizlenir. Satır silinmez.

---

## Faz 10 — Veri Kalite Monitörü

### Günlük Bütünlük Kontrolleri

```sql
-- Scheduled worker, her gece 03:00

-- 1. Tamamlanmış açık artırmaların final_price boş olmaması
SELECT COUNT(*) FROM auctions
WHERE status = 'ended' AND final_price IS NULL;

-- 2. Satın alımların tekabül eden auctions ile uyumu
SELECT COUNT(*) FROM purchases p
LEFT JOIN auctions a ON a.id = p.auction_id
WHERE p.auction_id IS NOT NULL AND a.id IS NULL;

-- 3. Negative balance (teorik olarak imkansız ama kontrol et)
SELECT COUNT(*) FROM users WHERE tuci_balance < 0;

-- 4. Orphan DM media (MinIO'da var, DB'de yok — veya tersi)
-- Bu daha karmaşık: storage_service audit ile
```

### ClickHouse Event Volume Alarmı

```python
# Prometheus metric: clickhouse_event_insert_rate
# Alarm: son 1 saatte 0 event insert → ClickHouse bağlantısı kopmuş olabilir
```

---

## Faz 11 — Outbox Pattern *(opsiyonel, ölçek büyüdüğünde)*

### Problem

Şu an `analytics_events` ve `user_interactions` ikili yazma (dual-write) ile ClickHouse'a gidiyor.  
Network hatası → PostgreSQL write başarılı, ClickHouse write başarısız → sessiz veri kaybı.

### Çözüm: Transactional Outbox

```sql
CREATE TABLE outbox_events (
    id          BIGSERIAL PRIMARY KEY,
    topic       TEXT NOT NULL,        -- 'analytics', 'user_interaction'
    payload     JSONB NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    sent_at     TIMESTAMPTZ           -- NULL = henüz işlenmedi
);
```

```python
# Mevcut dual-write yerine:
async with db.begin():
    db.add(analytics_event)
    db.add(OutboxEvent(topic="analytics", payload=event.dict()))
    # ClickHouse write BURADA YOK — worker okuyacak

# Worker (5 saniyede bir):
pending = SELECT * FROM outbox_events WHERE sent_at IS NULL ORDER BY id LIMIT 1000
# → ClickHouse batch insert
# → UPDATE outbox_events SET sent_at = NOW() WHERE id = ANY(...)
```

Bu, Teqlif'in mevcut ölçeğinde zorunlu değil — ama ClickHouse veri tutarsızlığı gözlemlenirse uygulanır.

---

## Endüstri Standardı Karşılaştırması

| Konu | Mevcut | Endüstri Standardı | Faz |
|------|--------|-------------------|-----|
| Para tipi | Float | Numeric/Decimal | 0 |
| URL depolama | Tam URL (500 char) | Key (100 char) | 2.4 |
| Görsel format | Orijinal (jpg/png) | WebP (sunucu side) | 2.1 |
| Video depolama | Raw (50MB) | Transcoded 720p H.264 (~10MB) | 2.2 |
| PK tipi | int4 | int8 büyüyen tablolarda | 1.1 |
| Status alanları | String(20) | ENUM | 1.6 |
| JSON in Column | Text (string) | JSONB | 1.5 |
| Bildirim tercihleri | JSON | Tipli kolonlar | 1.4 |
| God Object tablo | 47 kolon | ~18 kolon | 1.4 |
| Type-safe models | Manuel fromJson | Freezed generated | 6.1 |
| Union types | Flat schema | Discriminated union | 4.3 |
| API type safety | response_model eksik | Her endpoint'te | 4.1 |
| Redis TTL | Bazı key'lerde yok | Her key'e TTL | 3.1 |
| CH aggregation | Full scan | Materialized View | 5.1 |
| CH ORDER BY | timestamp first | Query pattern first | 5.2 |
| ML pipeline | Yok (price-estimate durduruldu) | Feature store + batch embed | 7 |
| Finansal audit | Yok (mutable tables) | Append-only event log | 8 |
| Veri silme | Yok (soft delete sadece) | KVKK cascade + anonymize | 9 |
| Veri kalite | Yok | Günlük integrity checks | 10 |
| Dual-write güvenliği | Sessiz kayıp riski | Outbox pattern | 11 |

---

---

# Tam Veri Modeli Audit — Ham Bulgular

*38 SQLAlchemy model, 13 Pydantic schema, 16 Flutter model incelendi. 2026-09-20*

---

## A. PostgreSQL Model Bulguları

### A.1 Finansal Float Hataları — Tam Liste

Plan Faz 0'da listings/auctions/bids/purchases vardı. Audit'te ek iki tablo bulundu:

| Tablo | Kolon | Dosya |
|-------|-------|-------|
| `listings` | price, buy_it_now_price, last_sold_price, last_start_price | models/listing.py |
| `auctions` | start_price, buy_it_now_price, final_price | models/auction.py |
| `bids` | amount | models/bid.py |
| `purchases` | price | models/purchase.py |
| `listing_offers` | amount | models/listing_offer.py ← **Faz 0'da eksikti** |
| `search_alerts` | max_price | models/search_alert.py ← **Faz 0'da eksikti** |
| `users` | max_budget | models/user.py ← **Faz 0'da eksikti** |
| `exchange_rates` | usd_try, eur_try | models/market_index.py ← kur değeri, Numeric(10,4) |

`exchange_rates` için Numeric(10,4) — dört ondalık basamak kur hassasiyeti için gerekli.

---

### A.2 BigInteger PK/FK — Öncelik Sırası

Hacim beklentisine göre sıralanmış:

| Tablo | Öncelik | Neden |
|-------|---------|-------|
| `direct_messages` | 🔴 Kritik | Hiç silinmiyor |
| `tuci_transactions` | 🔴 Kritik | Her işlem yeni satır |
| `stream_likes` | 🔴 Kritik | Unique constraint yok, her kalp = satır |
| `analytics_events` | 🟠 Yüksek | Yüksek frekanslı event |
| `user_interactions` | 🟠 Yüksek | Yüksek frekanslı event |
| `story_views` | 🟠 Yüksek | Her kullanıcı × her hikaye |
| `bids` | 🟠 Yüksek | Yoğun yayınlarda çok satır |
| `listing_likes` | 🟡 Orta | Büyük ölçek potansiyeli |
| `notifications` | 🟡 Orta | 30 günde siliniyor, bounded |
| `follows`, `user_blocks` | 🟢 Düşük | Sınırlı büyüme |

Tüm FK kolonları da ilgili tablolarla aynı tipte olmalı.

---

### A.3 ENUM Dönüşümleri — Tam Liste

| Tablo | Kolon | Mevcut | ENUM Değerleri |
|-------|-------|--------|----------------|
| `direct_messages` | content_type | String(20) | text / image / video / voice / file |
| `message_threads` | status | String(20) | pending / accepted / declined |
| `follows` | status | String(20) | pending / accepted / declined |
| `calls` | status | String(20) | calling / active / ended / rejected / missed |
| `call_participants` | role | String(16) | initiator / callee / guest |
| `call_participants` | status | String(16) | invited / ringing / joined / left / rejected / timeout / removed |
| `direct_sales` | status | String(20) | active / paused / ended / cancelled |
| `direct_sales` | end_reason | String(30) | sold_out / host_ended / stream_closed |
| `direct_sale_orders` | status | String(20) | completed / cancelled |
| `purchases` | purchase_type | String(20) | AUCTION / BUY_IT_NOW |
| `referrals` | status | String(20) | pending / completed |
| `stories` | media_type | String(10) | video (şimdilik tek değer) |
| `category_fields` | type | String(20) | text / number / dropdown |
| `auctions` | status | String(20) | active / paused / ended |

---

### A.4 Kritik Hatalar (Kod Seviyesinde)

#### A.4.1 `auctions.status` default="completed" — YANLIŞ

```python
# models/auction.py:23
status: Mapped[str] = mapped_column(String(20), default="completed")
```

Yeni oluşturulan auction başlangıçta "completed" durumunda. Doğru başlangıç değeri "active" olmalı.
Flutter `AuctionState` modeli status değerleri: `idle / active / paused / ended / buy_it_now_pending`.

**Düzeltme:** `default="active"` — veya ENUM tanımlanırsa `default=AuctionStatus.ACTIVE`.

#### A.4.2 `report.created_at` — Timezone Eksik

```python
# models/report.py:15
created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

`DateTime(timezone=True)` yok, `func.now()` yerine Python-side `datetime.utcnow`. PostgreSQL'de timezone-naive sütun.

**Düzeltme:**
```python
created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

#### A.4.3 `app_configs.updated_at` — Timezone Kendisi Siliniyor

```python
# models/app_config.py
updated_at = Column(DateTime,
    default=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
    onupdate=lambda: datetime.now(timezone.utc).replace(tzinfo=None))
```

Timezone'u kendin ekleyip `.replace(tzinfo=None)` ile siliyorsun. Tutarsız.

**Düzeltme:**
```python
updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
```

Ayrıca `app_config.key` ve `app_config.value` için uzunluk sınırı yok: `Column(String)`. 
**Düzeltme:** `Column(String(100))` ve `Column(String(2000))`.

#### A.4.4 `listings.active_room_id` — ForeignKey Eksik

```python
# models/listing.py:58
active_room_id: Mapped[Optional[int]] = mapped_column(nullable=True, index=True)
```

`live_streams.id`'ye FK constraint yok. Stream silindiğinde bu sütun eski ID'yi tutar, cascade yok.

**Düzeltme:**
```python
active_room_id: Mapped[Optional[int]] = mapped_column(
    ForeignKey("live_streams.id", ondelete="SET NULL"), nullable=True, index=True
)
```

#### A.4.5 `call_participants.livekit_token` — Token DB'de Saklanıyor

```python
# models/call.py:51
livekit_token: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
```

LiveKit token'ları kısa ömürlü JWT. DB'de saklamak:
- Güvenlik açığı (token leak)
- Storage israfı
- Expired token'lar birikir

**Çözüm:** Redis'e taşı, `call:{call_id}:token:{user_id}` key, TTL = call duration + 1 saat.

```python
# DB'den kaldır, Redis'te sakla:
await redis.set(f"call:{call_id}:token:{user_id}", token, ex=7200)
```

#### A.4.6 `stories.video_path` — Lokal Disk

```python
# models/story.py:26
video_path: Mapped[str] = mapped_column(String(500), nullable=False)
```

Story videoları lokal diske yazılıyor (highlights ile aynı sorun). MinIO'ya taşınmalı.
- Sunucu yeniden başlarsa dosyalar kaybolabilir
- Multi-node'da çalışmaz (hangi node'da?)
- Yedekleme yok

**Çözüm:** Yükleme sırasında MinIO'ya yaz, `video_path` kolonunu kaldır, sadece `video_url` (MinIO key) kalsın.

---

### A.5 Yapısal Sorunlar

#### A.5.1 `analytics_events` ve `user_interactions` — Eski Column() Stili

```python
# models/analytics.py — eski stil, SQLAlchemy 2.0 öncesi
id = Column(Integer, primary_key=True, index=True)
session_id = Column(String(255), index=True, nullable=False)
```

Tüm diğer tablolar `Mapped[int] = mapped_column(...)` kullanıyor. Type checking çalışmıyor.

**Düzeltme:**
```python
id: Mapped[int] = mapped_column(BigInteger, primary_key=True, index=True)
session_id: Mapped[str] = mapped_column(String(36), index=True, nullable=False)
```

#### A.5.2 `listings.image_url` + `listings.image_urls` — Tekrar Kolon

İki ayrı kolon:
- `image_url: String(500)` — tek görsel (thumbnail/birincil)
- `image_urls: Text` — JSON string array, tüm görseller

`image_url`, `image_urls[0]`'ın tekrarı. **Çözüm:** `image_url` kaldırılır, `image_urls → JSONB`, ilk eleman birincil görsel.

#### A.5.3 `user_interests.raw_signals` — Belgesiz JSONB

```python
raw_signals: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
```

İçeriği belgelenmiş değil. Ne saklanıyor? `{view: 5, click: 2, purchase: 1}`?

**Çözüm:** Yorum satırı veya tipli alt-schema: `{"view": int, "click": int, "purchase": int, "bid": int}`.

#### A.5.4 `message_threads` — Composite PK, Sequential ID Yok

Mevcut PK: `(user_a_id, user_b_id)`. `direct_messages`'a `thread_id` FK eklemek için `message_threads.id` (sequential BigInteger) gerekiyor.

Plan Faz 1.2'de ele alındı.

---

### A.6 String Uzunlukları — Tam Denetim

| Tablo | Kolon | Mevcut | Gerçek İhtiyaç | Öneri |
|-------|-------|--------|----------------|-------|
| `users` | profile_image_url | String(500) | MinIO key ~60 chr | String(255) |
| `users` | 7× sosyal URL | String(500) her biri | URL ~255 chr max | String(255) |
| `users` | fcm_token | String(500) | FCM token ~163 chr | String(300) |
| `users` | voip_token | String(500) | APNs token ~200 chr | String(300) |
| `users` | locale | String(10) | "tr", "en" = 2-5 chr | String(5) |
| `listings` | image_url, thumbnail_url, video_url | String(500) | MinIO key ~60 chr | String(255) |
| `auctions` | proof_image_url | String(2000) | URL ~255 chr | String(500) |
| `direct_messages` | media_url, thumbnail_url | String(500) | MinIO key ~60 chr | String(255) |
| `live_streams` | thumbnail_url | String(500) | MinIO key ~60 chr | String(255) |
| `analytics_events` | session_id | String(255) | UUID = 36 chr | String(36) |
| `app_configs` | key | String (sınırsız) | ~50 chr | String(100) |
| `app_configs` | value | String (sınırsız) | ~500 chr | String(2000) |
| `stories` | video_path, video_url | String(500) | Disk path / URL | String(255) |

---

## B. Pydantic Schema Bulguları

### B.1 Eksik Alanlar

**`UserOut` — `tuci_balance` eksik:**
```python
# schemas/user.py — UserOut sınıfında yok
tuci_balance: int = 100  # ← eklenecek
```
Flutter kullanıcı bakiyesini gösteremiyor çünkü API'den gelmiyor.

**`AuctionStateOut.status` — Literal tipi yok:**
```python
# Mevcut:
status: str
# Olması gereken:
status: Literal['idle', 'active', 'paused', 'ended', 'buy_it_now_pending']
```

**`DirectSaleStateOut.status` — Literal tipi yok:**
```python
status: Literal['idle', 'active', 'paused', 'sold_out', 'ended', 'cancelled']
```

---

### B.2 Float → Decimal Geçişi — Tüm Schema'lar

DB'de Numeric'e geçince Pydantic schema'lar da güncellenmeli:

| Dosya | Sınıf | Alan(lar) |
|-------|-------|-----------|
| schemas/auction.py | AuctionStart | start_price, buy_it_now_price |
| schemas/auction.py | BidIn, BidOut | amount |
| schemas/auction.py | AuctionStateOut | start_price, buy_it_now_price, current_bid |
| schemas/direct_sale.py | DirectSaleStartIn | price |
| schemas/direct_sale.py | DirectSaleStateOut | price |
| schemas/direct_sale.py | DirectSaleSummaryOut | total_revenue, buyer_unit_price, buyer_total |
| schemas/direct_sale.py | DirectSaleOrderOut | unit_price, total_price |
| schemas/listing.py | ListingOfferCreate | amount |
| schemas/listing.py | ListingOfferResponse | amount |

```python
from decimal import Decimal
# float yerine:
price: Decimal
# Optional ise:
price: Optional[Decimal] = None
```

---

### B.3 Eski `class Config` Stili

```python
# Mevcut (eski stil):
class BidOut(BaseModel):
    class Config:
        from_attributes = True

class DirectSaleOrderOut(BaseModel):
    class Config:
        from_attributes = True

# Olması gereken:
model_config = ConfigDict(from_attributes=True)
```

---

### B.4 `stream.py` — VALID_CATEGORIES Hardcoded

```python
VALID_CATEGORIES = {"electronics", "fashion", "home", "vehicles", "sports", "books", "real_estate", "other", "chat"}
```

DB'deki `categories` tablosuyla senkronize değil. Yeni kategori eklenince schema güncellenmeli.

**Çözüm:** `get_valid_category_keys()` utility kullan (analytics.py'de zaten var):
```python
@field_validator("category")
def category_valid(cls, v: str) -> str:
    valid = get_valid_category_keys()
    if valid and v.strip().lower() not in valid:
        raise ValueError("INVALID_CATEGORY")
    return v.strip().lower()
```

---

### B.5 `ConversationOut.is_request` — Mixed Shape

```python
class ConversationOut(BaseModel):
    is_request: bool = False  # thread status == "pending" ise True
```

Normal konuşma ve mesaj isteği aynı schema'da. Plan Faz 4'te ayrıştırılacak.

---

## C. Flutter Model Bulguları

### C.1 Eksik Alanlar — Backend'den Fazlası Geliyor, Flutter Kullanmıyor

**`User` modeli — eksikler:**

| Eksik Alan | Backend Karşılığı | Etki |
|------------|------------------|------|
| `tuciBalance` | `tuci_balance: int` | Bakiye gösterilemiyor |
| `status` | `status: UserStatus` | Hesap durumu bilinmiyor |
| `bio` | `bio: String?` | Kendi profil sayfasında bio görünmüyor |
| `websiteUrl` | `website_url: String?` | Profilde sosyal link yok |
| `instagramUrl` | `instagram_url: String?` | Aynı |
| `kickUrl`, `twitch_url`, `facebook_url`, `youtube_url`, `tiktok_url` | — | Aynı |
| `createdAt` | `created_at: DateTime` | Üyelik tarihi yok |

**`StreamOut` / `StreamHost` modeli — eksikler:**

| Eksik Alan | Backend Karşılığı | Etki |
|------------|------------------|------|
| `StreamHost.fullName` | `full_name: String` | Host ismi gösterilemiyor |
| `StreamHost.profileImageThumbUrl` | `profile_image_thumb_url: String?` | Host avatarı yok |
| `StreamOut.likesCount` | `likes_count: int` | Beğeni sayısı gösterilemiyor |
| `StreamOut.startedAt` | `started_at: DateTime` | Yayın süresi hesaplanamıyor |

---

### C.2 Tip Güvensizliği

**`AuctionState.status` — Plain String:**
```dart
// Mevcut — runtime'da yanlış değer gelirse sessizce çalışmaya devam eder
final String status;

// Olması gereken:
enum AuctionStatus { idle, active, paused, ended, buyItNowPending, error }
final AuctionStatus status;
```

**`ChatMessage.announcementPayload` — Map<String, dynamic>:**
```dart
// Mevcut
final Map<String, dynamic>? announcementPayload;

// Olması gereken — sealed class (plan Faz 6.2'de ele alındı)
```

**`StoryItem.storyType` — Plain String:**
```dart
// Mevcut
final String storyType;  // 'video' | 'live_redirect'

// Olması gereken
enum StoryType { video, liveRedirect }
final StoryType storyType;
```

**`CatalogField.type` — Plain String:**
```dart
// Mevcut
final String type;  // 'text' | 'number' | 'dropdown'

// Olması gereken
enum FieldType { text, number, dropdown }
```

---

### C.3 Double → Decimal Geçişi

DB Numeric'e, Pydantic Decimal'e geçince JSON'da fiyatlar `"12.50"` (string) olarak gelebilir:

```dart
// Mevcut — num? cast başarısız olabilir:
price: (j['price'] as num?)?.toDouble()

// Güvenli çözüm:
static double _parsePrice(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}
```

Etkilenen modeller: `DirectSaleState`, `DirectSaleOrder`, `DirectSaleSummary`, `CommercePurchase`, `CommerceSale`, `AuctionState`, `ListingOffer`.

---

### C.4 İyi Pattern'lar (Değiştirilmeyecek)

Bu yapılar endüstri standardında, dokunma:

| Dosya | Pattern | Neden İyi |
|-------|---------|-----------|
| `call_event.dart` | `sealed class CallSignal` | Tip-güvenli WS event handling |
| `commerce_activity.dart` | `sealed class CommerceEvent` | Tip-güvenli commerce events |
| `enums.dart` | enum + extension | Doğru enum pattern |
| `catalog.dart` | Immutable value objects | İyi yapılandırılmış |
| `call_participant.dart` | `copyWith` pattern | State management doğru |

---

## D. Öncelik Matrisi — Tam Liste

```
🔴 Kritik (veri bütünlüğü / güvenlik):
  [D1]  Float → Numeric: listings, auctions, bids, purchases, listing_offers,
              search_alerts, users.max_budget                          (Faz 0)
  [D2]  exchange_rates Float → Numeric(10,4)                           (Faz 0)
  [D3]  auctions.status default "completed" → "active"                 (Faz 1)
  [D4]  report.created_at → DateTime(timezone=True) + func.now()       (Faz 1)
  [D5]  app_configs DateTime + String sınırsız → düzelt                (Faz 1)
  [D6]  listings.active_room_id → ForeignKey ekle                      (Faz 1)
  [D7]  call_participants.livekit_token → Redis'e taşı                 (Faz 1)

🟠 Önemli (ölçek / doğruluk):
  [D8]  BigInteger PKlar (direct_messages, tuci_transactions, stream_likes önce)  (Faz 1.1)
  [D9]  message_threads sequential id + thread_id FK                   (Faz 1.2)
  [D10] image_url tekrar kolon kaldır, image_urls → JSONB              (Faz 1.5)
  [D11] String status'ler → ENUM (tüm tablolar)                        (Faz 1.6)
  [D12] analytics_events / user_interactions → Mapped[] stile geç      (Faz 1)
  [D13] stories.video_path → MinIO                                     (Faz 2)
  [D14] UserOut'a tuci_balance ekle                                    (Faz 4)
  [D15] AuctionStateOut + DirectSaleStateOut → Literal status          (Faz 4)
  [D16] BidOut + DirectSaleOrderOut → model_config = ConfigDict(...)   (Faz 4)
  [D17] stream.py VALID_CATEGORIES → DB'den oku                        (Faz 4)
  [D18] Pydantic float → Decimal (tüm finansal schema'lar)             (Faz 4)

🟡 Temizlik (tip güvenliği):
  [D19] users.notification_prefs → ayrı tablo                          (Faz 1.4)
  [D20] URL String(500) → String(255) + string uzunluk denetimi        (Faz 1.7)
  [D21] Flutter User modeline eksik alanlar ekle                       (Faz 6)
  [D22] Flutter StreamHost.fullName + profileImageThumbUrl ekle        (Faz 6)
  [D23] Flutter AuctionStatus enum                                     (Faz 6)
  [D24] Flutter StoryType enum                                         (Faz 6)
  [D25] Flutter CatalogField.type enum                                 (Faz 6)
  [D26] Flutter Decimal parse helper                                   (Faz 6)
  [D27] Flutter tüm modeller → Freezed                                 (Faz 6.1)
  [D28] user_interests.raw_signals — belgeleme                         (Faz 1)

🟢 Mimari (uzun vadeli):
  [D29] call_participants.livekit_token kaldır (D7 ile birlikte)       (Faz 1)
  [D30] story.video_path kolonu kaldır (D13 ile birlikte)              (Faz 2)
  [D31] users bölünmesi (social_links, notification_prefs, consents)   (Faz 1.4)
  [D32] DirectSaleSummaryOut → discriminated union                     (Faz 4.3)
  [D33] 4 partial-user schema → UserMiniOut base                       (Faz 4.2)
  [D34] financial_events append-only tablo                             (Faz 8)
  [D35] KVKK veri silme zinciri                                        (Faz 9)

🔴 DB Mimarisi:
  [D51] PgBouncer aktivasyonu (use_pgbouncer=True)                     (Faz 13.2) ← ACİL
  [D52] auctions composite index (stream_id, status, ended_at)         (Faz 13.1)
  [D53] teqlik_transactions composite index (user_id, created_at)      (Faz 13.1)
  [D54] listing_offers composite index (listing_id, status)            (Faz 13.1)
  [D55] follows composite index (follower_id, followed_id)             (Faz 13.1)
  [D56] listings.image_urls JSONB → GIN index ekle                     (Faz 13.1)
  [D57] PostgreSQL partition plan (analytics_events, teqlik_tx, dm)    (Faz 13.3)

🟡 Sorgu + Cache:
  [D58] Listing detail Redis cache (60s, invalidate on update)         (Faz 14.1)
  [D59] User profile Redis cache (5min, invalidate on update)          (Faz 14.1)
  [D60] Categories/AppConfig Redis cache (uzun TTL — 1h/10min)        (Faz 14.1)
  [D61] Feed: _fetch_seller_meta N+1 → SQL JOIN                        (Faz 14.2)
  [D62] Redis key namespace düzenlemesi                                 (Faz 14.3)
  [D63] Keyset pagination — listing feed + wallet history              (Faz 14.4)

🔴 Para birimi yeniden adlandırma (tüm katmanlar):
  [D36] DB: users.tuci_balance → teqlik_balance                        (Faz 12)
  [D37] DB: tuci_transactions → teqlik_transactions                    (Faz 12)
  [D38] DB: gift_events.cost_tuci → cost_teqlik                        (Faz 12)
  [D39] DB: mass_notification_campaigns.spent_tuci → spent_teqlik      (Faz 12)
  [D40] Python: TuciTransaction model + dosya yeniden adlandır         (Faz 12)
  [D41] Python: TuciTransactionRepository + dosya yeniden adlandır     (Faz 12)
  [D42] Python: transfer_tuci.py + TransferTuciCommand yeniden adlandır (Faz 12)
  [D43] Python: cost_tuci() + "cost_tuci" dict key → cost_teqlik       (Faz 12)
  [D44] Python: tüm router'larda tuci_* değişkenleri → teqlik_*        (Faz 12)
  [D45] Python: API endpoint /wallet/tuci/* → /wallet/teqlik/*         (Faz 12)
  [D46] API JSON: tüm response field adları tuci → teqlik              (Faz 12)
  [D47] Flutter: tüm tuciBalance / _TuciWalletCard vb. yeniden adlandır (Faz 12)
  [D48] Flutter: tüm 'TUCi' string literalleri → 'Teqlik'              (Faz 12)
  [D49] i18n ARB: tüm "TUCi" display string'leri → "Teqlik"            (Faz 12)
  [D50] i18n ARB: tuciSpent key yeniden adlandır → teqlikSpent         (Faz 12)
```

---

## Faz 12 — Para Birimi Yeniden Adlandırma: "tuci" → "teqlik"

**Amaç:** Sistemdeki tüm katmanlardan "tuci" adını kaldırıp yerine "teqlik" koymak. Hiçbir yerde "tuci" verisi kalmayacak.

**Kapsam:** 23 Python dosyası (224 referans) + 15 Flutter dosyası (87 referans) + 4 ARB dil dosyası.

**Bağımlılık:** Bu faz bağımsızdır; diğer fazlarla çakışmaz. Ancak Alembic migration yazılmadan önce var olan `tuci_transaction` tablosunu kullanan tüm arka uç servislerinin migration'ı kesmemesi için tek adımda uygulanmalıdır (eski isim → yeni isim atomik).

---

### 12.1 — Veritabanı (Alembic Migration)

**Dosya:** `backend/alembic/versions/<revision>_rename_tuci_to_teqlik.py`

Her komut ayrı `op.execute()` olmalı (asyncpg multi-statement yasağı — bkz. `feedback_alembic_asyncpg.md`):

```python
def upgrade():
    # 1. users tablosu
    op.execute("ALTER TABLE users RENAME COLUMN tuci_balance TO teqlik_balance")

    # 2. tuci_transactions → teqlik_transactions
    op.execute("ALTER TABLE tuci_transactions RENAME TO teqlik_transactions")

    # 3. gift_events
    op.execute("ALTER TABLE gift_events RENAME COLUMN cost_tuci TO cost_teqlik")

    # 4. mass_notification_campaigns
    op.execute("ALTER TABLE mass_notification_campaigns RENAME COLUMN spent_tuci TO spent_teqlik")

def downgrade():
    op.execute("ALTER TABLE mass_notification_campaigns RENAME COLUMN spent_teqlik TO spent_tuci")
    op.execute("ALTER TABLE gift_events RENAME COLUMN cost_teqlik TO cost_tuci")
    op.execute("ALTER TABLE teqlik_transactions RENAME TO tuci_transactions")
    op.execute("ALTER TABLE users RENAME COLUMN teqlik_balance TO tuci_balance")
```

**Etkilenen tablolar:**

| Tablo | Eski kolon/ad | Yeni kolon/ad |
|-------|--------------|--------------|
| `users` | `tuci_balance` | `teqlik_balance` |
| `tuci_transactions` | *(tablo adı)* | `teqlik_transactions` |
| `gift_events` | `cost_tuci` | `cost_teqlik` |
| `mass_notification_campaigns` | `spent_tuci` | `spent_teqlik` |

---

### 12.2 — Python Model Dosyaları

#### 12.2.1 Dosya yeniden adlandırma

| Eski dosya | Yeni dosya |
|-----------|-----------|
| `backend/app/models/tuci_transaction.py` | `backend/app/models/teqlik_transaction.py` |
| `backend/app/repositories/tuci_transaction_repository.py` | `backend/app/repositories/teqlik_transaction_repository.py` |
| `backend/app/use_cases/wallet/commands/transfer_tuci.py` | `backend/app/use_cases/wallet/commands/transfer_teqlik.py` |

#### 12.2.2 Sınıf ve fonksiyon yeniden adlandırma

| Eski ad | Yeni ad | Dosya |
|---------|---------|-------|
| `TuciTransaction` | `TeqlikTransaction` | `models/teqlik_transaction.py` |
| `__tablename__ = "tuci_transactions"` | `"teqlik_transactions"` | models |
| `TuciTransactionRepository` | `TeqlikTransactionRepository` | repositories |
| `TransferTuciCommand` | `TransferTeqlikCommand` | use_cases |
| `TuciAirdropRequest` | `TeqlikAirdropRequest` | routers/admin_data.py |
| `cost_tuci()` | `cost_teqlik()` | services/credit_service.py |
| `"cost_tuci"` (dict key) | `"cost_teqlik"` | services/credit_service.py `_FEATURES` |

#### 12.2.3 SQLAlchemy model kolonu

```python
# models/user.py
# Eski:
tuci_balance: Mapped[int] = mapped_column(BigInteger, default=0)
# Yeni:
teqlik_balance: Mapped[int] = mapped_column(BigInteger, default=0)
```

#### 12.2.4 Etkilenen Python dosyaları (tam liste)

```
backend/app/models/user.py
backend/app/models/tuci_transaction.py         → teqlik_transaction.py
backend/app/models/gift_event.py
backend/app/models/mass_notification_campaign.py
backend/app/repositories/tuci_transaction_repository.py  → teqlik_transaction_repository.py
backend/app/use_cases/wallet/commands/transfer_tuci.py   → transfer_teqlik.py
backend/app/services/credit_service.py
backend/app/routers/admin_data.py
backend/app/routers/ads.py
backend/app/routers/analytics.py
backend/app/routers/auth.py
backend/app/routers/leads.py
backend/app/routers/listings.py
backend/app/routers/wallet.py
backend/app/routers/users.py
backend/app/schemas/user.py
backend/app/schemas/wallet.py
backend/app/dependencies/*.py   (tuci_balance bağımlılıkları varsa)
```

---

### 12.3 — API Endpoint Yeniden Adlandırma

| Eski endpoint | Yeni endpoint | Dosya |
|--------------|--------------|-------|
| `GET /wallet/tuci/summary` | `GET /wallet/teqlik/summary` | `routers/wallet.py` |
| `POST /wallet/tuci/airdrop` | `POST /wallet/teqlik/airdrop` | `routers/admin_data.py` |

**Not:** Eski endpoint'ler geçici olarak `307 Temporary Redirect` ile yeni adrese yönlendirilebilir (Flutter güncellemesi deploy edilene kadar).

---

### 12.4 — API JSON Response Alanları

Flutter bu alanları okuyarak gösteriyor. Python'daki renaming yeterli değil — response serileştirmesini de güncellemek gerekiyor.

| Eski JSON key | Yeni JSON key | Endpoint / schema |
|--------------|--------------|------------------|
| `tuci_balance` | `teqlik_balance` | `UserOut`, `AuthResponse`, `WalletSummary` |
| `wallet_balance` | `teqlik_balance` | `auth.py` login response (listing_detail_screen okuyor) |
| `cost_tuci` | `cost_teqlik` | `CreditCostResponse`, `FeatureUsageOut` |
| `spent_tuci` | `spent_teqlik` | `WalletSummary`, `AdminStats` |
| `tuci_cost` | `teqlik_cost` | yerel değişkenler → response field'a yansıyan |
| `total_tuci_circulation` | `total_teqlik_circulation` | `admin_data.py` stats endpoint |
| `today_tuci_spent` | `today_teqlik_spent` | `admin_data.py` stats endpoint |

**Kritik:** Flutter `listing_detail_screen.dart:845` şu anda `ud['wallet_balance']` okuyor. Bu key yeniden adlandırılırsa Flutter da aynı anda güncellenmeli (atomik deploy).

---

### 12.5 — Flutter Dart Dosyaları

#### 12.5.1 Sınıf ve değişken yeniden adlandırma

| Eski ad | Yeni ad | Dosya |
|---------|---------|-------|
| `tuciBalance` | `teqlikBalance` | `providers/profile_view_model.dart` |
| `tuciHistory` | `teqlikHistory` | `providers/profile_view_model.dart` |
| `tuciSpent` | `teqlikSpent` | `providers/ai_desc_provider.dart` |
| `_TuciWalletCard` | `_TeqlikWalletCard` | `screens/profile_screen.dart` |
| `_TuciWalletCardState` | `_TeqlikWalletCardState` | `screens/profile_screen.dart` |

#### 12.5.2 JSON parse güncellemesi

```dart
// listing_detail_screen.dart:845 - Eski:
tuciBalance = ((ud['wallet_balance'] ?? 0) as num).toInt();

// Yeni (API key adı da teqlik_balance olacaksa):
teqlikBalance = ((ud['teqlik_balance'] ?? 0) as num).toInt();
```

#### 12.5.3 Display string'leri

Tüm `'TUCi'` string literalleri `'Teqlik'` ile değiştirilecek:

```dart
// Örnekler (tüm dosyalarda):
'TUCi Cüzdanı'    → 'Teqlik Cüzdanı'
'TUCi Harca'      → 'Teqlik Harca'
'TUCi Kazan'      → 'Teqlik Kazan'
'${amount} TUCi'  → '${amount} Teqlik'
'50 TUCi'         → '50 Teqlik'
```

#### 12.5.4 Etkilenen Flutter dosyaları (tam liste)

```
mobile/lib/screens/profile_screen.dart
mobile/lib/screens/listing_detail_screen.dart
mobile/lib/screens/retargeting_screen.dart
mobile/lib/screens/faq_screen.dart
mobile/lib/screens/swipe_live_screen.dart
mobile/lib/providers/profile_view_model.dart
mobile/lib/providers/ai_desc_provider.dart
mobile/lib/models/user.dart           (tuciBalance alanı eklendiyse)
mobile/lib/widgets/wallet_widget.dart (varsa)
```

---

### 12.6 — i18n ARB Dosyaları

**Dosyalar:**
- `documents/language/app_tr.arb`
- `documents/language/app_en.arb`
- `documents/language/app_ar.arb`
- `documents/language/app_ru.arb`

#### 12.6.1 Display değerleri (tüm dillerde "TUCi" → "Teqlik")

| ARB Key | Eski değer (TR) | Yeni değer (TR) |
|---------|----------------|----------------|
| `walletTitle` | `"TUCi Cüzdanım"` | `"Teqlik Cüzdanım"` |
| `buyTuci` | `"TUCi Satın Al"` | `"Teqlik Satın Al"` |
| `boostDialogPaidConfirm` | `"50 TUCi Öde ve Başlat"` | `"50 Teqlik Öde ve Başlat"` |
| `blastConfirmCostPaidLabel` | `"TUCi Maliyeti"` | `"Teqlik Maliyeti"` |
| `faqIconNameTuci` | `"TUCi"` | `"Teqlik"` |
| `faqQBadgesTuci` | `"TUCi nedir?"` | `"Teqlik nedir?"` |
| `faqABadgesTuci` | `"TUCi, teqlif'in..."` | `"Teqlik, teqlif'in..."` |
| *(diğerleri)* | `*TUCi*` | `*Teqlik*` |

#### 12.6.2 Key yeniden adlandırma (opsiyonel ama tutarlılık için önerilir)

| Eski key | Yeni key |
|---------|---------|
| `tuciSpent` | `teqlikSpent` |
| `faqIconNameTuci` | `faqIconNameTeqlik` |
| `faqQBadgesTuci` | `faqQBadgesTeqlik` |
| `faqABadgesTuci` | `faqABadgesTeqlik` |
| `buyTuci` | `buyTeqlik` |

**Not:** ARB key yeniden adlandırması, `t('tuciSpent')` çağrılarını da güncellemesi gerektirir. Flutter dosyalarında `t('tuciSpent')` referansları taranmalıdır.

---

### 12.7 — Uygulama Sırası

```
1. Alembic migration yaz + test et (staging'de)
2. Python dosyalarını yeniden adlandır
3. Tüm import referanslarını güncelle
4. API endpoint yönlendirmelerini ekle (geçici 307)
5. Flutter dosyalarını güncelle (JSON key + class adları + string'ler)
6. ARB dosyalarını güncelle
7. Staging'de E2E test (cüzdan yükleme, harcama, geçmiş görüntüleme)
8. Production deploy (Python + Flutter aynı anda)
9. Eski endpoint yönlendirmelerini kaldır (1 sürüm sonra)
```

**Atomiklik notu:** Python (API) ve Flutter aynı anda deploy edilmeli. Eski Flutter yeni API'yi okursa `teqlik_balance` key'ini bulamaz → 0 gösterir. Deploy penceresi kısa tutulmalı veya API geçici olarak her iki key'i de döndürmeli:

```python
# Geçici geriye dönük uyumluluk (1 sürüm):
return {
    "teqlik_balance": user.teqlik_balance,
    "tuci_balance": user.teqlik_balance,  # eski Flutter için
}
```

---

### 12.8 — Doğrulama Kontrol Listesi

```
□ grep -r "tuci" backend/app/ --include="*.py" → 0 sonuç
□ grep -r "TUCi\|tuci" mobile/lib/ --include="*.dart" → 0 sonuç  
□ grep -r "TUCi\|tuci" documents/language/*.arb → 0 sonuç
□ alembic history'de migration görünüyor
□ SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name='teqlik_balance' → 1 satır
□ SELECT table_name FROM information_schema.tables WHERE table_name='teqlik_transactions' → 1 satır
□ Flutter cüzdan ekranı "Teqlik" gösteriyor
□ API /wallet/teqlik/summary 200 dönüyor
□ Eski /wallet/tuci/summary 307 → /wallet/teqlik/summary yönlendiriyor
```

---

## Faz 15 — Kaynak Sınırları ve Node Kısıtları

**Amaç:** Planın her fazının hangi node'u nasıl etkilediğini donanım sınırlarıyla eşleştirmek. Her Faz uygulanmadan önce bu bölüme bakılmalı.

---

### 15.1 — Node Haritası

| Node | Rol | CPU | RAM | Disk | Ağ |
|------|-----|-----|-----|------|-----|
| **node5** | Core/Prod backend | 4× EPYC 7763 | 7.8 GB + 8 GB swap | 49 GB SSD | — |
| **node3** | Staging + Monitoring | 4× EPYC 7763 | 3.8 GB + 4 GB swap | 49 GB SSD | 5 TB/ay, throttle sonrası 10 Mbit/s |
| **node1** | Edge 1 (Prod) | 6× Intel Haswell | 11.4 GB + 2 GB swap | 98 GB NVMe | 2 Gbps **unmetered** |
| **node4** | Edge 2 | 6× Intel Haswell | 11.4 GB + 8 GB swap | 98 GB NVMe | — |
| **gateway** | Reverse Proxy | 2× QEMU 2.29 GHz | 1.9 GB + 1 GB swap | 58.9 GB SSD | 1 Gbps, 100 Mbps 24h ort. throttle |
| **node2** | AI Proxy | 1× Xeon E5-2670 | 1.4 GB + 2 GB swap | 14.7 GB | — |

---

### 15.2 — node5 RAM Bütçesi

**Sorun:** Redis 4 GB + PG shared_buffers ~2 GB = **6 GB tüketilmiş** → FastAPI + ARQ workers için ~1.8 GB kalıyor. Swap kullanımı zaten aktif.

**Mevcut → hedef konfigürasyon:**

```
Servis                    Mevcut       Hedef
─────────────────────────────────────────────────
Redis maxmemory           4.0 GB       4.0 GB (sabit — AOF + hot data)
PG shared_buffers         ~2.0 GB      1.5 GB  ← düşür
PG work_mem               4 MB/conn    4 MB/conn (PgBouncer sonrası conn az)
FastAPI worker sayısı     4            3       ← 1 azalt
ARQ worker sayısı         ?            2 max   ← rate limit
OS + diğer                ~0.5 GB      ~0.5 GB
─────────────────────────────────────────────────
Toplam hedef              ~7.5 GB      ~7.0 GB  (0.8 GB marj kaldı)
```

**PostgreSQL `postgresql.conf` değişiklikleri:**

```ini
shared_buffers = 1536MB          # 2048MB'dan düşür
effective_cache_size = 4GB       # shared_buffers + OS page cache
work_mem = 4MB                   # connection başına, düşük tut
maintenance_work_mem = 128MB     # VACUUM/INDEX için
max_connections = 30             # PgBouncer'dan sonra direkt bağlantı az
```

**Etki:** PgBouncer aktif edilince (Faz 13.2) 120 bağlantı → 20-30'a düşer. Her PG backend ~5 MB → **~450-500 MB RAM kurtarılır.**

---

### 15.3 — node5 Disk Bütçesi

**Sorun:** 49 GB SSD → küçük.

**Mevcut tahmini kullanım:**

```
Servis                    Tahmini      Risk
──────────────────────────────────────────────────────
PostgreSQL data           5–15 GB      📈 büyüyor
Redis AOF dump            1–2 GB       sabit
Hikayeler (yerel disk)    ? GB         📈 BOMBa — Faz 0/D13 acil
Loglar                    2–3 GB       rotasyon var mı?
OS + sistem               3–4 GB       sabit
──────────────────────────────────────────────────────
Kalan                     ~20–30 GB    daralıyor
```

**Aksiyonlar:**

1. **D13 — stories.video_path → MinIO (Faz 2):** Yerel videolar node5 diskini dolduruyor. Bu Faz 2'nin en yüksek öncelikli öğesi — disk alanı açar.
2. **Log rotasyonu denetimi:** `journalctl --disk-usage` ile mevcut log hacmini ölç.
3. **PG WAL:** `wal_keep_size = 64MB` (default 0, ama replication yoksa büyük WAL gereksiz).
4. **ClickHouse node5'te OLMAYACAK** — bkz. 15.5.

---

### 15.4 — node3 Kaynak Kısıtları

**3.8 GB RAM, 15+ servis** — en kalabalık node. Her yeni servis doğrudan swap'a yansır.

**RAM dağılımı (tahmini):**

```
Servis                    Tahmini
──────────────────────────────────
Staging FastAPI (2 worker) ~300 MB
Staging PostgreSQL         ~400 MB
Staging Redis              ~200 MB
Staging ARQ (2 worker)     ~200 MB
Prometheus                 ~300 MB
Loki                       ~200 MB
Alertmanager               ~50 MB
LiveKit staging            ~200 MB
MinIO staging              ~150 MB
AI proxy                   ~100 MB
OS + diğer                 ~300 MB
──────────────────────────────────
Toplam tahmini             ~2.4 GB  (swap: ~1.4 GB)
```

**Tuning:**

```ini
# Prometheus — tsdb retention düşür (staging'de 30 gün gerekmez)
--storage.tsdb.retention.time=7d   # 30d yerine

# Loki — chunk boyutu küçült, memory cache azalt  
chunk_target_size: 524288    # 1048576 → 512KB
ingestion_rate_mb: 4         # küçük staging için

# Staging FastAPI — 1 worker yeterli
# teqlif-staging.service: ExecStart içinde --workers 1
```

**Bandwidth (5 TB/ay, 10 Mbit/s throttle):**

- 5 TB/ay ≈ 1.67 GB/gün ≈ 19 Mbit/s ortalama
- Prometheus scraping + Loki log shipping **WireGuard içinden** (iç ağ) yapılmalı — dış IP'ye çıkmamalı
- MinIO staging: büyük medya upload/download testleri node3 bandwithini yakabilir → staging testlerinde dikkat
- **Plan Faz 5 (ClickHouse):** ClickHouse node3'e kurulmayacak (hem RAM hem disk hem bandwidth sorunlu)

---

### 15.5 — ClickHouse Yerleşimi

**Faz 5'teki ClickHouse hangi node'a gidecek?**

| Node | Uygunluk | Gerekçe |
|------|---------|---------|
| **node1** ✅ | **En uygun** | 11.4 GB RAM, 98 GB NVMe, 2 Gbps unmetered |
| node4 | Uygun | node1 ile aynı specs, yedek seçenek |
| node5 | ❌ Uygun değil | Disk sıkışık (49 GB), RAM bütçesi dar |
| node3 | ❌ Uygun değil | 3.8 GB RAM, bant genişliği sınırlı, disk sıkışık |

**Bağlantı mimarisi:**

```
node5 (FastAPI) → WireGuard 10.10.0.1 → node1 (ClickHouse :9000)
```

**Neden node1:** node5'ten event'ler outbox worker ile node1'deki ClickHouse'a WireGuard üzerinden yazılır. Bu trafik iç ağda kalır, dış bant genişliğini etkilemez. node1'in 98 GB NVMe'si ClickHouse'un compressed columnar storage için ideal.

---

### 15.6 — gateway Kısıtları

**1.9 GB RAM, 100 Mbps 24h ort. throttle.**

**Kural: gateway'den veri geçmez, sadece yönlendirilir.**

Halihazırda doğru yapılandırılmış olanlar (memory: `project_dns_records.md`):
- `uploads.teqlif.com` → DNS Only → node1 direkt
- `live.teqlif.com` → DNS Only → LiveKit direkt
- `minio.teqlif.com` → DNS Only → MinIO direkt

**Plan kapsamındaki dikkat noktaları:**

1. **Faz 14.1 — API response gzip:** Listing feed response'u (20 ilan × JSON) ~15 KB → gzip ile ~3 KB. gateway Nginx'te `gzip on` aktif olmalı — CPU maliyeti minimumdur, bant genişliği tasarrufu yüksek.

2. **Faz 6 — Flutter WebSocket:** LiveKit signaling gateway'den geçmiyor (DNS Only) — iyi. Chat WebSocket gateway'den geçiyor — her bağlantı memory'de tutulur. 1.9 GB RAM'de yüzlerce aktif WS bağlantısı sığar ama 10 binlerce sığmaz.

3. **Faz 5 — ClickHouse HTTP arayüzü:** Asla gateway üzerinden expose edilmeyecek. Sadece WireGuard iç ağdan erişim.

4. **Gateway'e yeni servis eklenmeyecek** — nginx dışında hiçbir uygulama çalışmamalı.

---

### 15.7 — ML Pipeline Kaynak Sınırları (Faz 7)

GPU yok, tüm node'lar CPU-only. ML inference node5'te çalışacak (4 core EPYC).

**CPU bütçesi:**

```python
# backend/app/services/ml/*.py
import torch
torch.set_num_threads(1)  # ML inference için max 1 core
torch.set_num_interop_threads(1)
```

**ARQ worker kısıtı:**

```python
# Embedding görevi — önce devre dışı (Faz 3'te)
# Faz 7'de aktifleştirilince:
# ARQ'da rate limit: dakikada max 10 embedding görevi
# Off-peak scheduling: 02:00–06:00 arası batch embedding
```

**RAM kısıtı:**
- FAISS index: model boyutuna göre değişir (küçük model = ~200 MB, büyük = 1+ GB)
- node5'te ML için en fazla **500 MB RAM** ayrılmalı → model seçimi buna göre yapılmalı
- ALS matrix factorization: scipy sparse matrix, veri boyutuna bağlı — batch işlem, RAM'de tutulmamalı

---

### 15.8 — Plan Fazlarının Node Etki Matrisi

Her Faz'ın hangi node'u nasıl etkilediğini gösteren özet:

| Faz | Etkilenen Node | CPU | RAM | Disk | Ağ | Önlem |
|-----|--------------|-----|-----|------|-----|-------|
| Faz 0 (Float→Numeric) | node5, node3 | - | - | +küçük | - | Migration bakım penceresi |
| Faz 1 (BigInt, index) | node5, node3 | ↑ geçici | - | +küçük | - | Index migration CONCURRENTLY yasak |
| Faz 2 (MinIO) | node5 ↓, node1 ↑ | - | - | **↓ önemli** | ↑ node1 | Media taşıma önce staging'de test |
| Faz 3 (Redis) | node5 | - | ↑ dikkat | - | - | maxmemory 4 GB aşılmamalı |
| Faz 5 (ClickHouse) | **node1** | ↑ | ↑ | ↑ | ↑ iç ağ | node5/node3'e kurma |
| Faz 7 (ML) | node5 | **↑ yüksek** | ↑ 500 MB | ↑ model dosyası | - | CPU thread limit zorunlu |
| Faz 9 (outbox) | node5 | ↑ küçük | - | ↑ küçük | ↑ iç ağ | node5→node1 WireGuard event akışı |
| Faz 13 (PgBouncer) | node5 | - | **↓ 450 MB kurtarır** | - | - | max_connections 30'a düşür |
| Faz 14 (cache) | node5 Redis | - | ↑ dikkat | - | - | Redis kullanımı izle |

---

### 15.9 — İzleme Eşikleri

Bu plan boyunca Prometheus'ta şu alertler aktif olmalı:

```yaml
# node5 için kritik eşikler
node_memory_MemAvailable_bytes < 500MB   → CRITICAL (swap'ta)
node_filesystem_free_bytes{node5} < 5GB → WARNING
pg_stat_activity_count > 25             → WARNING (PgBouncer sonrası)
redis_memory_used_bytes > 3.8GB         → WARNING (4GB limitine yakın)

# node3 için
node_memory_MemAvailable_bytes{node3} < 200MB  → WARNING
node_filesystem_free_bytes{node3} < 3GB        → WARNING

# gateway için
node_network_transmit_bytes_total (rate) > 100Mbit/s sustained → WARNING
``` — DB Mimarisi

**Ön koşul:** Faz 0–6 tamamlanmış olmalı (yanlış tipe index koymak boşa gider).

**Hedef:** Veri yapısına uygun index stratejisi, bağlantı havuzu ve uzun vadeli büyüme planı.

---

### 13.1 — Eksik Index'ler

**Mevcut durum:** `listings`, `gift_events`, `notifications`, `calls` için composite index'ler iyi tanımlı. Ancak birkaç kritik tablo eksik.

#### 13.1.1 Auctions

```python
# models/auction.py — TableArgs'a eklenecek
Index("ix_auctions_stream_status", "stream_id", "status"),
Index("ix_auctions_stream_ended", "stream_id", "ended_at"),
Index("ix_auctions_listing_status", "listing_id", "status"),
```

**Neden:** Auction expiry poller `WHERE status='active' AND ended_at < now()` sorgusunu çalıştırıyor. `ended_at` + `status` birlikte taranmalı.

#### 13.1.2 Teqlik Transactions (eski: tuci_transactions)

```python
# models/teqlik_transaction.py — TableArgs'a eklenecek
Index("ix_teqlik_tx_user_created", "user_id", "created_at"),
Index("ix_teqlik_tx_type_created", "transaction_type", "created_at"),
```

**Neden:** Cüzdan geçmişi `WHERE user_id = ? ORDER BY created_at DESC LIMIT 20` ile çekiliyor. Sadece `user_id` index var, `created_at` sıralama için ek sort gerekiyor.

#### 13.1.3 Listing Offers

```python
# models/listing_offer.py — TableArgs'a eklenecek
Index("ix_listing_offers_listing_status", "listing_id", "status"),
Index("ix_listing_offers_user_status", "user_id", "status"),
```

**Neden:** "Bu ilana gelen aktif teklifler" sorgusu `(listing_id, status='pending')` üzerinden gidiyor.

#### 13.1.4 Follows

```python
# models/follow.py — TableArgs'a eklenecek
Index("ix_follows_follower_followed", "follower_id", "followed_id"),
```

**Neden:** "A, B'yi takip ediyor mu?" kontrolü sık yapılıyor. Ayrı ayrı index'ler bu sorguya yetmiyor.

#### 13.1.5 Purchases

```python
# models/purchase.py — TableArgs'a eklenecek
Index("ix_purchases_buyer_created", "buyer_id", "created_at"),
Index("ix_purchases_buyer_type", "buyer_id", "purchase_type"),
```

#### 13.1.6 Direct Messages (thread_id eklendikten sonra — Faz 1.2)

```python
# Faz 1.2'den sonra mevcut composite index'i değiştir:
# Eski: Index("ix_direct_messages_conv_created", "sender_id", "receiver_id", "created_at")
# Yeni (thread_id eklendikten sonra):
Index("ix_direct_messages_thread_created", "thread_id", "created_at"),
Index("ix_dm_receiver_unread", "receiver_id", "is_read"),
```

**Neden:** Şu anki `(sender_id, receiver_id, created_at)` index'i A→B konuşmasını yakalar ama B→A yakalamiyor. `thread_id` FK eklendikten sonra tek index yeterli.

#### 13.1.7 Listings.image_urls (JSONB'ye geçtikten sonra — Faz 0)

```python
# models/listing.py — TableArgs'a eklenecek (Faz 0 tamamlandıktan sonra)
Index('ix_listings_image_urls_gin', 'image_urls', postgresql_using='gin'),
```

**Neden:** `image_urls @> '["url"]'` operatörü GIN olmadan seq scan yapar.

#### 13.1.8 Index Özet Tablosu

| Tablo | Yeni Index | Tip | Öncelik |
|-------|-----------|-----|---------|
| `auctions` | `(stream_id, status)`, `(stream_id, ended_at)` | BTree | 🔴 Yüksek |
| `teqlik_transactions` | `(user_id, created_at)` | BTree | 🔴 Yüksek |
| `listing_offers` | `(listing_id, status)` | BTree | 🟡 Orta |
| `follows` | `(follower_id, followed_id)` | BTree | 🟡 Orta |
| `purchases` | `(buyer_id, created_at)` | BTree | 🟡 Orta |
| `direct_messages` | `(thread_id, created_at)` | BTree | Faz 1.2 sonrası |
| `listings.image_urls` | GIN | GIN | Faz 0 sonrası |

**Not:** Index'ler `CREATE INDEX CONCURRENTLY` kullanılamaz (teqlif env.py transaction içinde çalışıyor — bkz. `feedback_alembic_concurrently.md`). Her index ayrı `op.execute()` + transaction dışı migration gerektirir. Bkz. Faz 13.1.9.

#### 13.1.9 Index Migration Stratejisi

asyncpg + Alembic'te CONCURRENTLY yasak olduğu için index'ler maintenance window'da sırayla eklenmeli:

```python
# Alembic migration — her index ayrı transaction
def upgrade():
    op.execute("CREATE INDEX ix_auctions_stream_status ON auctions (stream_id, status)")
    op.execute("CREATE INDEX ix_auctions_stream_ended ON auctions (stream_id, ended_at)")
    op.execute("CREATE INDEX ix_teqlik_tx_user_created ON teqlik_transactions (user_id, created_at)")
    # ... devam
```

---

### 13.2 — PgBouncer Aktivasyonu (ACİL)

**Mevcut durum:** `backend/app/config.py` zaten `use_pgbouncer: bool = False` ve `database.py` bunu destekliyor. Sadece aktifleştirilmesi gerekiyor.

**Sorun:** 4 worker × (20 pool + 10 overflow) = **120 potansiyel bağlantı**. PostgreSQL default `max_connections = 100`. Yoğun trafikte limit aşılabilir.

**Hedef yapı:**

```
FastAPI workers (4×)
    ↓ SQLAlchemy pool_size=5, max_overflow=2 per worker = 28 bağlantı
PgBouncer :5432 (transaction mode)
    ↓ pool_size=20
PostgreSQL :5433 (direkt erişim kapat)
```

**Yapılacaklar:**

1. `backend/app/config.py`: `use_pgbouncer: bool = True`
2. `DATABASE_URL` → PgBouncer port'una yönlendir (örn. 5432; PG → 5433'e taşı)
3. SQLAlchemy pool boyutlarını düşür: `pool_size=5, max_overflow=2`
4. PgBouncer `pool_mode = transaction` (prepared statement devre dışı — asyncpg zaten prepared statement kullanmaz)
5. `pool_pre_ping = True` kalsın (PgBouncer bağlantı sağlığını handle eder ama ping zarar vermez)

**PgBouncer `pgbouncer.ini` temel ayarları:**

```ini
[databases]
teqlif = host=127.0.0.1 port=5433 dbname=teqlif

[pgbouncer]
pool_mode = transaction
max_client_conn = 200
default_pool_size = 20
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
```

---

### 13.3 — PostgreSQL Partitioning Planı (Deferred)

Şu anda partitioning gerektiren bir veri hacmi yok. Ancak büyüme planı için eşik değerleri belirlenmeli:

| Tablo | Partitioning Türü | Eşik | Tahmini Süre |
|-------|------------------|------|-------------|
| `analytics_events` | Range (created_at, aylık) | 10M satır | 12+ ay |
| `teqlik_transactions` | Range (created_at, aylık) | 5M satır | 18+ ay |
| `direct_messages` | Range (created_at, aylık) | 20M satır | 12+ ay |

**Not:** PostgreSQL native partitioning mevcut tabloları bölmez — yeni tablo + veri taşıma + rename gerektirir. Bu operasyon planlı maintenance gerektirir ve erken yapılmamalı.

**ClickHouse** zaten `PARTITION BY toYYYYMM(timestamp)` ile partitioned — analytics trafiği buraya taşınınca PG partitioning ihtiyacı azalır.

---

### 13.4 — Read Replica (Uzun Vadeli)

Admin dashboard ve raporlama sorguları primary'yi etkiliyor. ClickHouse analytics layer tamamlandıktan sonra:

- Ağır admin sorguları → ClickHouse
- Geriye kalan read-heavy endpointler (listing search, user profile) → PG read replica

Şu an için: PgBouncer + index optimizasyonu yeterli.

---

## Faz 14 — Sorgu ve Cache Katmanı

**Ön koşul:** Faz 13 tamamlanmış olmalı (doğru index olmadan cache stratejisi boşa gider).

**Hedef:** Her ekranın yükleme süresini DB'den değil, Redis'ten besleyerek minimize etmek; N+1 sorgularını elemek; pagination'ı scale'e uygun hale getirmek.

---

### 14.1 — Redis Cache Stratejisi (Endpoint Bazlı)

**Mevcut cache'lenen endpointler:**

| Cache Key Pattern | TTL | Endpoint |
|------------------|-----|---------|
| `interests:{user_id}` | 15dk | Feed affinity |
| `subcat_interests:{user_id}` | 15dk | Feed subcategory |
| `feed:hesitated:{user_id}` | 15dk | Feed personalization |
| `cache:market_trends_global_{locale}` | 5dk | Analytics market trends |
| `cache:pro_insights:{uid}:...` | 5dk | Analytics pro insights |
| `cache:demand_radar:{days}:{category}` | 5dk | Analytics demand |
| `seller:badge:{uid}` | 25sa | Seller badge |
| `trust_score:{uid}` | ~15dk | Trust score |

**Eksik — eklenecek endpointler:**

| Cache Key Pattern | TTL | Invalidasyon | Endpoint |
|------------------|-----|-------------|---------|
| `listing:{id}` | 60s | Listing update/delete | `GET /listings/{id}` |
| `user_profile:{username}` | 5dk | User update | `GET /users/{username}` |
| `categories:all:{locale}` | 1sa | Admin kategori değişikliği | `GET /categories` |
| `app_config:{key}` | 10dk | Admin config update | `GET /app-config` |
| `streams:live` | 30s | Stream start/end webhook | `GET /streams` |
| `listing_offers:{listing_id}` | 30s | Offer create/accept/reject | `GET /listings/{id}/offers` |

**Cache invalidasyon kuralları:**

```python
# Listing güncelleme/silinme → cache temizle
async def invalidate_listing_cache(listing_id: int):
    redis = await get_redis()
    await redis.delete(f"listing:{listing_id}")

# User profil güncelleme → cache temizle  
async def invalidate_user_cache(username: str):
    redis = await get_redis()
    await redis.delete(f"user_profile:{username}")
```

**TTL seçim kriterleri:**
- **30s**: Gerçek zamanlı sayılabilir veri (stream listesi, aktif teklifler)
- **60s**: Listing detay (hızlı satış olabilir)
- **5dk**: Kullanıcı profili (nadiren değişir ama staleness kabul edilebilir)
- **10dk+**: Konfigürasyon, kategoriler (çok nadir değişir)
- **25sa+**: Worker tarafından hesaplanan rozet/skor

---

### 14.2 — N+1 Sorgu Tespiti ve Çözümü

#### 14.2.1 Feed: `_fetch_seller_meta` N+1

**Mevcut durum:** `feed_queries.py` listing listesi döndükten sonra her listing için Python loop içinde `_fetch_seller_meta(user_id)` çağrıyor.

**Sorun:** 20 ilanın feed'i = 20 ayrı SELECT.

**Çözüm:**

```python
# Şu an (N+1):
for row in listings:
    seller = await _fetch_seller_meta(row["user_id"])

# Hedef (1 sorgu):
seller_ids = [row["user_id"] for row in listings]
sellers = await session.execute(
    select(User.id, User.username, User.profile_image_thumb_url, User.is_verified)
    .where(User.id.in_(seller_ids))
)
seller_map = {s.id: s for s in sellers}
```

#### 14.2.2 Listing Detail: Birden Fazla Ayrı Sorgu

**Mevcut durum:** Listing detay endpoint'i büyük olasılıkla ayrı sorgularla şunları çekiyor:
- Listing
- Seller user
- Aktif auction (varsa)
- Son 5 bid (varsa)
- Aktif offers

**Hedef:** Listing + seller tek `JOIN` ile; auction + bids tek sorgu; cache'lenmiş sonuç.

#### 14.2.3 Stream: Participants N+1

**Mevcut durum:** `stream.py` `host: Mapped["User"] = relationship("User", lazy="selectin")` → iyi (selectin). Ancak participant listesi ayrı sorgu olabilir.

**Kontrol edilecek:** Stream detay endpoint'inde kaç sorgu çalıştığını `EXPLAIN` veya logging ile ölçmek.

#### 14.2.4 Favorites: Her İlanda "Favorilendi Mi?" Kontrolü

**Mevcut durum:** Feed listesi dönerken her ilan için ayrı `is_favorited` check yapılıyor olabilir.

**Hedef:**
```python
# Tek sorguda toplu favorite check:
fav_listing_ids = await session.execute(
    select(ListingLike.listing_id)
    .where(ListingLike.user_id == current_user.id)
    .where(ListingLike.listing_id.in_(listing_ids))
)
fav_set = set(fav_listing_ids.scalars())
```

---

### 14.3 — Redis Key Namespace Düzenlemesi

**Mevcut durum:** Key'ler tutarsız:
- `interests:{uid}` (prefix yok)
- `cache:market_trends_global_{locale}` (`cache:` prefix)
- `seller:badge:{uid}` (`seller:` prefix)
- `trust_score:{uid}` (prefix yok)

**Hedef namespace:**

```
teqlif:{env}:{domain}:{identifier}

Örnekler:
  teqlif:prod:feed:interests:{uid}
  teqlif:prod:listing:detail:{id}
  teqlif:prod:user:profile:{username}
  teqlif:prod:analytics:market_trends:{locale}
  teqlif:prod:auth:refresh:{token}
  teqlif:prod:stream:live_list
```

**Not:** Namespace değişikliği tüm Redis key okuma/yazma kodunu etkiler. Tek seferde değil, aşamalı geçiş yapılmalı. Eski key'ler TTL süresi dolunca kendiliğinden temizlenir.

---

### 14.4 — Pagination Stratejisi

#### 14.4.1 Mevcut Durum

Büyük olasılıkla `OFFSET`-based pagination kullanılıyor:

```sql
SELECT * FROM listings ORDER BY created_at DESC LIMIT 20 OFFSET 100
```

**Sorun:** `OFFSET 100` çalışmak için 120 satır okur, 100'ünü atar. Büyük tablolarda yavaşlar.

#### 14.4.2 Keyset (Cursor) Pagination

**Hedef:** `created_at` + `id` ile cursor-based pagination:

```sql
-- İlk sayfa:
SELECT * FROM listings WHERE status='active'
ORDER BY created_at DESC, id DESC LIMIT 20

-- Sonraki sayfa (cursor: last_seen_at + last_seen_id):
SELECT * FROM listings WHERE status='active'
  AND (created_at, id) < (:last_seen_at, :last_seen_id)
ORDER BY created_at DESC, id DESC LIMIT 20
```

**Uygulanacak endpoint'ler:**

| Endpoint | Öncelik | Not |
|---------|---------|-----|
| Listing feed | 🔴 Yüksek | Büyük tablo, sık kullanım |
| Wallet geçmişi (`GET /wallet/history`) | 🔴 Yüksek | Finansal tablo |
| Mesaj geçmişi (`GET /messages`) | 🟡 Orta | thread_id eklendikten sonra |
| Bildirimler | 🟡 Orta | `(user_id, created_at)` index var |

**Flutter uyumu:** Cursor-based pagination Flutter'daki infinite scroll widget'larıyla doğrudan uyumludur. Cursor JSON base64 encode edilerek `next_cursor` field olarak döndürülür.

---

### 14.5 — JSONB Sorgu Optimizasyonu

Faz 0'da `listings.image_urls` Text → JSONB'ye geçtikten sonra:

```python
# Eski (Python'da parse):
listing = await get_listing(id)
images = json.loads(listing.image_urls)  # Python'da

# Yeni (DB'de doğrudan):
result = await session.execute(
    select(Listing.id, Listing.image_urls[0].label("first_image"))
    .where(Listing.id == listing_id)
)
```

```sql
-- Belirli URL içeren ilanları bul (GIN index kullanır):
SELECT id FROM listings
WHERE image_urls @> '["https://uploads.teqlif.com/x.jpg"]'::jsonb
```

---

### 14.6 — Uygulama Sırası

```
1. PgBouncer aktif et (13.2) ← en acil, bağlantı limiti sorunu var
2. Eksik index migration'larını yaz + staging'de test et (13.1)
3. Listing detail + user profile cache ekle (14.1)
4. Categories + AppConfig cache ekle (14.1)
5. Feed N+1 → batch seller fetch (14.2)
6. Favorites toplu check (14.2)
7. Keyset pagination: listing feed + wallet (14.4)
8. Redis key namespace geçişi (14.3) — aşamalı
9. JSONB sorgu optimizasyonu (14.5) — Faz 0 sonrası
10. EXPLAIN ANALYZE ile production'da ölçüm + ince ayar
```

---

### 14.7 — Ölçüm ve Başarı Kriterleri

```
□ PgBouncer aktif → max DB bağlantısı < 30 (4 worker + admin + poller)
□ Listing feed p95 < 200ms (cache hit)
□ Listing detail p95 < 150ms (cache hit)
□ Wallet geçmişi p95 < 100ms (keyset + index)
□ EXPLAIN ANALYZE: feed sorgusu → Seq Scan yok (index scan)
□ Redis hit rate > %80 (listing detail + feed)
□ pg_stat_activity: waiting connections = 0 normal yükte
```
