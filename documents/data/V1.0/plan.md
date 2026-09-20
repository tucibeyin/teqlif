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
