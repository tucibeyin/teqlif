# Teqlif Açık Artırma Sistemi — Mimari ve Business Rules

> **Son güncelleme:** 2026-07-28  
> **Kaynak:** `backend/app/use_cases/auctions/`, `backend/app/routers/auction.py`, `backend/app/core/`

---

## 1. Genel Bakış

Teqlif açık artırma sistemi canlı yayın üzerine inşa edilmiş, gerçek zamanlı bir teklif/satın alma altyapısıdır. Üç farklı artırma türünü destekler:

| Tür | Açıklama |
|---|---|
| **Hızlı Artırma** | İlansız, sadece ürün adı ve başlangıç fiyatıyla açılır |
| **İlanlı Artırma** | Sistemdeki mevcut bir ilanla bağlantılı; ilan kapandığında otomatik pasif olur |
| **Hemen Al (BIN)** | Her iki türde de opsiyonel fiyat tanımlanabilir; izleyici talebini host onaylar |

---

## 2. Veri Modeli

### 2.1 PostgreSQL Tabloları

#### `auctions`
| Alan | Tip | Açıklama |
|---|---|---|
| `id` | PK | |
| `stream_id` | FK → live_streams | |
| `listing_id` | FK → listings (nullable) | Bağlı ilan; silinirse NULL |
| `item_name` | String(300) | |
| `start_price` | Float | |
| `buy_it_now_price` | Float (nullable) | Hemen al fiyatı |
| `final_price` | Float (nullable) | Kazanan teklif veya BIN fiyatı |
| `is_bought_it_now` | Boolean | BIN ile mi kapandı? |
| `winner_id` | FK → users (nullable) | |
| `winner_username` | String(100) | |
| `bid_count` | Integer | |
| `status` | String(20) | `completed` |
| `started_at` | DateTime | |
| `ended_at` | DateTime (nullable) | |
| `proof_image_url` | String(2000) | Teslimat kanıtı |

#### `bids`
| Alan | Tip | Açıklama |
|---|---|---|
| `id` | PK | |
| `stream_id` | FK → live_streams | |
| `bidder_id` | FK → users | |
| `bidder_username` | String(100) | Denormalized snapshot |
| `amount` | Float | |
| `created_at` | DateTime | |

> Composite index: `(stream_id, created_at)` — son teklif sorgularını hızlandırır.

#### `purchases`
| Alan | Tip | Açıklama |
|---|---|---|
| `id` | PK | |
| `buyer_id` | FK → users | |
| `listing_id` | FK → listings (nullable) | |
| `auction_id` | FK → auctions (nullable) | |
| `price` | Float | |
| `purchase_type` | String(20) | `AUCTION_WIN` veya `BUY_IT_NOW` |
| `created_at` | DateTime | |

### 2.2 Redis Hash — Canlı Artırma State'i

**Key:** `auction:{stream_id}`  
**TTL:** 24 saat

| Field | Açıklama |
|---|---|
| `status` | `idle` / `active` / `paused` / `buy_it_now_pending` / `buy_it_now_locked` / `ended` |
| `item_name` | Ürün adı |
| `start_price` | Başlangıç fiyatı |
| `buy_it_now_price` | Hemen al fiyatı (boş ise BIN yok) |
| `current_bid` | Anlık en yüksek teklif |
| `current_bidder_id` | Teklif sahibi user_id |
| `current_bidder_name` | Teklif sahibi username |
| `bid_count` | Toplam teklif sayısı |
| `host_id` | Yayın sahibi user_id |
| `host_ip` | Yayın başlangıcında kaydedilen host IP |
| `stream_id` | |
| `listing_id` | Bağlı ilan ID (yoksa boş) |
| `bin_buyer_id` | BIN talebi sırasında dolu olur |
| `bin_buyer_username` | BIN talebi sırasında dolu olur |
| `pre_pending_status` | BIN pending öncesi status (geri yükleme için) |

---

## 3. Durum Makinesi (State Machine)

```
                    ┌─────────────┐
                    │    idle     │  Redis hash yok / artırma başlamadı
                    └──────┬──────┘
                           │ start()
                    ┌──────▼──────┐
                ┌──►│   active    │◄──────────────────────────────────┐
                │   └──┬──────────┘                                   │
                │      │ pause()    ┌───────────────┐                 │
                │      ├──────────► │    paused     │                 │
                │      │            └───────┬────────┘                │
                │      │             resume()└───────────────────────►┤
                │      │ request_buy_it_now()                         │
                │      ├──────────────────────────► ┌─────────────────┐
                │      │                            │ buy_it_now      │
                │      │                            │   _pending      │
                │      │                            └──────┬──────────┘
                │      │               reject()            │ accept()
                │      │◄──────────────────────────────────┘   │
                │      │                                        ▼
                │      │                            ┌───────────────────┐
                │      │                            │buy_it_now_locked  │→ ended
                │      │                            └───────────────────┘
                │      │ accept_bid() / end_auction()
                │      └──────────► ┌─────────────┐
                │                   │    ended    │
                └───────────────────┴─────────────┘
                         (Redis key silindi)
```

---

## 4. API Endpoints

| Method | Path | Yetki | Açıklama |
|---|---|---|---|
| `GET` | `/api/auction/{stream_id}` | Herkese açık | Mevcut artırma durumu (Redis-only) |
| `GET` | `/api/auction/{stream_id}/bids` | Auth | Son 50 teklif listesi |
| `POST` | `/api/auction/{stream_id}/start` | Host/Mod | Artırma başlat |
| `POST` | `/api/auction/{stream_id}/pause` | Host/Mod | Artırmayı duraklat |
| `POST` | `/api/auction/{stream_id}/resume` | Host/Mod | Artırmayı devam ettir |
| `POST` | `/api/auction/{stream_id}/end` | Host/Mod | Artırmayı bitir (kazanan yok) |
| `POST` | `/api/auction/{stream_id}/bid` | Auth | Teklif ver |
| `POST` | `/api/auction/{stream_id}/buy-it-now` | Auth | Hemen al talebi gönder |
| `POST` | `/api/auction/{stream_id}/buy-it-now/accept` | Host | Hemen al talebi kabul et |
| `POST` | `/api/auction/{stream_id}/buy-it-now/reject` | Host | Hemen al talebi reddet |
| `POST` | `/api/auction/{stream_id}/accept` | Host/Mod | Mevcut teklifi kabul et |
| `WS` | `/api/auction/{stream_id}/ws` | Opsiyonel Auth | Gerçek zamanlı durum akışı |

---

## 5. İzleyici (Bidder) Business Rules

### 5.1 Kimlik Kontrolleri
- Host kendi artırmasına teklif veremez → `HOST_CANNOT_BID` (403)
- Mute'lu kullanıcı teklif veremez → `BID_BLOCKED_MUTE` (403)
- Artırma `active` durumunda olmalı → `AUCTION_NOT_ACTIVE` (400)
- Schema seviyesi: teklif miktarı > 0 olmalı → 422

### 5.2 Hız Sınırı — İki Katmanlı
```
Katman 1 (Action Guard): 1 teklif / 3 saniye (user_id bazlı)
  Key  : act_rate:{user_id}:place_bid
  Hata : BID_RATE_LIMIT (429)

Katman 2 (Router Limiter): 10 teklif / dakika (user_id veya IP)
  Kütüphane: slowapi
  Hata : 429 Too Many Requests
```

### 5.3 Minimum Teklif Artış Kuralı
```
İlk teklif (bid_count == 0): amount >= start_price
Sonraki teklifler           : amount >= current_bid + increment

Increment tablosu:
  current_bid <  100  → increment = ₺1
  100 <= current < 500 → increment = ₺10
  500 <= current < 1000 → increment = ₺25
  current >= 1000      → increment = ₺50
```
İhlal → `BID_TOO_LOW` (400)

Kontrol **iki adımlı atomik Lua scripti** ile yapılır:
1. `_VALIDATE_BID_SCRIPT` — DB commit öncesi read-only kontrol
2. `_BID_SCRIPT` — DB commit sonrası re-validate + atomik Redis güncelleme

### 5.4 Yüksek Teklif — Telefon Doğrulama Zorunluluğu

| Koşul | is_verified = true | is_verified = false |
|---|---|---|
| Mutlak tutar eşiği | > ₺10.000 | > ₺5.000 |
| Katlama eşiği (baz ≥ ₺500) | mevcut × 10 aşılırsa | mevcut × 7 aşılırsa |

Bu eşiklerden biri aşıldığında `user.phone` mevcut ve `user.phone_verified = true` olmalı.  
İhlal → `BID_BLOCKED_VERIFY` (403) + fraud_log Redis ZADD kaydı

### 5.5 Shill Bidding Tespit Sistemi

Yalnızca `bidder_ip == host_ip` iken aktive olur; IP eşleşmezse hiçbir shill kontrolü çalışmaz.

| Sinyal | Puan |
|---|---|
| Bidder IP == Host IP (tetikleyici) | +40 |
| Hesap email veya telefon doğrulanmamış | +30 |
| Hesap yaşı < 7 gün | +20 |
| `shill_cnt:{stream_id}:{user_id}` sayacı × 15 (max 30) | +15 ~ +30 |

**Karar tablosu:**
| Toplam Skor | Eylem |
|---|---|
| < 40 | Normal — kontrol bile yapılmadı |
| 40 – 69 | Uyarı: sayaç +1 (24h TTL), teklif geçer |
| ≥ 70 | Kalıcı mute (`stream:{stream_id}:muted` setine eklenir) + `BID_BLOCKED_MUTE` |

**Verified kullanıcı — aynı ağ false positive hesabı:**
```
Teklif 1: IP(+40) → skor=40 → WARN, sayaç=1 ✅
Teklif 2: IP(+40) + prior_1(+15) → skor=55 → WARN, sayaç=2 ✅
Teklif 3: IP(+40) + prior_2(+30) → skor=70 → KALICI MUTE ❌ ← false positive
```

Tüm shill denemeleri `fraud_log` (Redis ZADD, 30 günlük) ve logger'a yazılır.

### 5.6 Idempotency Koruması
`X-Idempotency-Key` header ile aynı teklif isteği 30 saniye içinde tekrar gelirse cached response dönülür; iş mantığı ikinci kez çalışmaz.

---

## 6. Host Business Rules

### 6.1 Yetki Modeli
| Aksiyon | Host | Co-Host (Mod) |
|---|---|---|
| start / pause / resume / end | ✅ | ✅ |
| accept_bid | ✅ | ✅ |
| buy-it-now accept/reject | ✅ | ❌ (yalnızca host) |
| mute / kick | ✅ | ✅ |
| promote / demote | ✅ | ❌ |
| Co-host'u hedef alma | ✅ | ❌ |

### 6.2 Artırma Başlatma
- Artırma zaten `active` ise → `AUCTION_ALREADY_ACTIVE` (400)
- İlanlı artırmada ilan `DELETED` ise → `LISTING_NOT_FOUND` (404)
- Host IP, başlangıçta Redis hash'e yazılır (shill detection için)
- `listing_id` verilmezse `item_name` zorunlu (min 2 karakter)

### 6.3 Teklif Kabul (accept_bid) — Saga Pattern

```
Adım 1: create_auction
  Compensate: sil + Redis status'ü original_status'e döndür

Adım 2: deactivate_listing (listing_id varsa)
  Compensate: listing.status'ü önceki değere döndür

Adım 3: create_purchase + DirectMessage + UserInteraction
  Compensate: None (audit trail korunur)

→ DB commit (tek commit noktası)
→ auction:bidders:{stream_id} set'inden tüm katılımcıları al
→ Redis auction key ve bidder set sil
→ WS: AUCTION_STATE (ended, winner_accepted=true)
→ Push: kazanana bildirim
→ ARQ queue: kaybedenlere bildirim
→ ClickHouse: auction_won + listing_sold event
→ Chat: özet mesajı broadcast
```

### 6.4 Artırma İptali (end_auction)
- bid_count > 0 ise Auction kaydı DB'ye yazılır (audit)
- `winner_accepted: false` — kazanan onaylanmadı
- İlan pasif **yapılmaz**
- Kaybedenlere bildirim kuyruğa alınır

---

## 7. Hemen Al (Buy It Now) Akışı

```
İzleyici ──► POST /buy-it-now
              Redis: active/paused → buy_it_now_pending (atomik Lua)
              WS: BUY_IT_NOW_REQUESTED → tüm odaya

    ├─ KABUL: Host ──► POST /buy-it-now/accept
    │          Redis: pending → locked (atomik Lua)
    │          DB: Auction + Purchase commit
    │          İlan pasif
    │          WS: AUCTION_ENDED_BY_BUY_IT_NOW
    │          DM: kazanana özet mesajı
    │          Push: alıcıya bildirim
    │          Chat: özet mesajı broadcast
    │
    └─ RED: Host ──► POST /buy-it-now/reject
               Redis: pending → pre_pending_status (önceki durum)
               Redis: bin_cooldown:{stream_id}:{buyer_id} = 60s
               WS: BUY_IT_NOW_REJECTED
```

**BIN kuralları:**
- Host satın alamaz → `HOST_CANNOT_BUY` (403)
- Mute'lu kullanıcı talep gönderemez → `STREAM_MUTED_PURCHASE` (403)
- Mevcut teklif ≥ BIN fiyatı → `BIDS_EXCEED_BUY_NOW` (400)
- BIN fiyatı tanımlı değilse → `BUY_NOW_UNAVAILABLE` (400)
- Reddedilirse 60s cooldown → `BUY_NOW_REJECTED_COOLDOWN` (429)

---

## 8. WebSocket Katmanı

### Bağlantı Akışı
```
1. WS accept
2. İstemci 5s timeout içinde {token: "..."} gönderir (opsiyonel)
3. register_ws_session → eş zamanlı oturum limiti kontrolü
4. GetAuctionStateQuery → anlık Redis state gönderilir
5. outbox_replay → son 30s içindeki kaçırılan eventler replay edilir
6. receive_loop: 40s timeout — ping alınmazsa bağlantı kesilir
```

### Multi-Worker Event Dağıtımı
```
place_bid()
  └─► publish_auction()
        ├─ Redis Stream XADD "auction_broadcast" (tüm worker'lara)
        │    └─ Her worker'ın pubsub_listener → local_broadcast()
        │         └─ O worker'daki WebSocket bağlantıları
        └─ outbox_publish() → "auction:events:{stream_id}"
             └─ WS reconnect'te outbox_replay() ile kaçırılanlar
```

### Event Outbox
- **Key:** `auction:events:{stream_id}` (Redis Stream)
- **Max:** 200 event (approximate MAXLEN)
- **TTL:** 24 saat
- **Replay filtresi:** yalnızca son 30 saniyedekiler; eski server event'leri atlanır

---

## 9. Lua Scriptleri — Atomiklik Garantisi

| Script | Çağrıldığı Yer | Amaç |
|---|---|---|
| `_VALIDATE_BID_SCRIPT` | place_bid → DB commit ÖNCE | Read-only; status + min artış doğrulama |
| `_BID_SCRIPT` | place_bid → DB commit SONRA | Re-validate + current_bid/bidder_id/name güncelle |
| `_BUY_IT_NOW_REQUEST_SCRIPT` | request_buy_it_now | active/paused → buy_it_now_pending |
| `_BUY_IT_NOW_ACCEPT_SCRIPT` | accept_buy_it_now | pending → locked; buyer bilgisi okunur |
| `_BUY_IT_NOW_REJECT_SCRIPT` | reject_buy_it_now | pending → pre_pending_status; buyer bilgisi temizlenir |

> **Race condition koruması:** DB commit ile Redis güncelleme arasında başka teklif geldiyse `_BID_SCRIPT` re-validate ile yakalar → `CONCURRENT_BID_OUTBID`. DB kaydı audit trail olarak tutulur.

---

## 10. Background Worker Görevleri

| Görev | Kuyruk | Tetikleyen | Açıklama |
|---|---|---|---|
| `notify_auction_losers_task` | `critical` | accept_bid / end_auction / accept_buy_it_now | Kaybeden teklif verenlere push |
| `notify_outbid_task` | `critical` | place_bid | Geçilen teklif sahibine push |

**Outbid dedup job_id:** `outbid:{stream_id}:{prev_bidder_id}:{int(amount)}`  
Aynı tutar için duplicate ARQ retry'da tek push gönderilmesini garantiler.

---

## 11. Fraud Log

- **Key:** `fraud_log` (Redis Sorted Set)
- **Score:** Unix timestamp
- **TTL:** 30 gün (otomatik eski kayıt temizleme)
- **Kaydedilen olaylar:** `shill_bidding`, `troll_bid_no_phone`
- **Payload:** `{fraud_type, stream_id, user_id, username, extra}`

---

## 12. Bilinen Kısıtlar ve Teknik Borç

| # | Sorun | Kök Neden | Etki |
|---|---|---|---|
| 1 | Shill mute `publish_mod_event()` çağırmıyor | Moderasyon servisi atlanıyor, direkt Redis yazımı | Host client mute'dan haberdar olmaz; unmute senaryosu bozulur |
| 2 | Verified kullanıcı aynı ağdan 3 teklifte mute olur | IP eşleşmesi + 2 warn birikimi = eşik | Meşru izleyici false positive ile bloke edilir |
| 3 | `AuctionCommands` → `from app.routers.moderation import mute_key` | Bağımlılık yönü ihlali | Use Case → Router; Clean Architecture Dependency Rule çiğneniyor |
| 4 | Otomatik fraud kararı geri alınamaz | Admin override mekanizması yok | Hatalı mute stream boyunca kalıcılaşır |
| 5 | Fraud detection `place_bid` içine gömülü | FraudDetectionService yok | Bağımsız test edilemez; değişiklik riski yüksek |
| 6 | `stream:{stream_id}:muted` set'ine TTL atalanmıyor | Direkt `redis.sadd()` çağrısı, expire yok | Stream bittikten sonra key sonsuza kadar Redis'te kalır; düşük ama gerçek memory leak |
| 7 | `place_bid()` içinde `from app.routers.notifications import push_notification` lazy import | Metod içi import | Use Case → Router bağımlılığı; mute_key import'una ek ihlal noktası |
| 8 | `bids` tablosunda `(bidder_id)` index yok | İlk tasarım | Kullanıcı teklif geçmişi sorgusu tam tablo taraması yapar |
| 9 | `auctions` tablosunda `(winner_id)` index yok | İlk tasarım | Kullanıcı kazanma geçmişi sorgusu tam tablo taraması yapar |
| 10 | BIN flow ve pause/resume ClickHouse'da izlenmiyor | Takip edilmemiş event türleri | BIN kabul/red oranı ve pause süresi ölçülemez |

---

## 13. PostgreSQL Derinlemesine

### 13.1 Tablo Rolleri

| Tablo | Rol |
|---|---|
| `auctions` | Artırma sonuç kaydı (sadece biten artırmalar) — canlı state **Redis'tedir** |
| `bids` | Her teklifin audit kaydı (race condition'da bile tutulur) |
| `purchases` | Tamamlanan işlem kayıtları (AUCTION_WIN / BUY_IT_NOW) |

`auctions` tablosu live durumu temsil etmez. Canlı artırma state'i tamamen Redis Hash `auction:{stream_id}` içindedir. PostgreSQL sadece artırma bitince (accept_bid / end_auction / accept_buy_it_now) yazılır.

### 13.2 Mevcut İndeksler

| Tablo | İndeks | Amaç |
|---|---|---|
| `bids` | `(stream_id, created_at)` composite | Son teklif sorguları (`/bids` endpoint) |
| `user_interactions` | `(user_id, interaction_type)` | Trust score sorguları |

### 13.3 Eksik İndeksler (Tespit Edildi)

| Tablo | Eksik İndeks | Etkilenen Sorgu | Öncelik |
|---|---|---|---|
| `bids` | `(bidder_id)` | Kullanıcı teklif geçmişi | 🟠 P1 |
| `auctions` | `(winner_id)` | Kullanıcı kazanma geçmişi | 🟠 P1 |
| `purchases` | `(buyer_id, purchase_type)` | Kullanıcı satın alma geçmişi | 🟠 P1 |
| `purchases` | `(auction_id)` | Artırma → satın alma eşleşmesi | 🟡 P2 |
| `user_interactions` | fraud partial index | Admin fraud sorguları | 🟡 P2 (PLAN.md T-10) |

### 13.4 `auctions` Tablo — `winner_accepted` Alanı

```
winner_accepted = True  → accept_bid ile biten (kazanan var, işlem tamamlandı)
winner_accepted = False → end_auction ile biten (kazanan yok, bid_count > 0 ise audit)
```

Tüm UI konfeti/kazanma animasyonu `winner_accepted === true` kontrolüne bağlanmalı.

### 13.5 Saga Pattern — Hata Yönetimi

`accept_bid` 3 adımlı saga; her adımın compensation fonksiyonu var:

```
Adım 1 (create_auction)      → DB hatasında: sil + Redis status geri yükle
Adım 2 (deactivate_listing)  → DB hatasında: listing.status önceki değere döner
Adım 3 (create_purchase +    → Compensation yok — audit trail korunur
         DirectMessage +
         UserInteraction)
→ Tek DB commit noktası
→ Başarı: Redis cleanup + WS + push + ARQ queue + ClickHouse
```

Race condition senaryosunda DB commit başarılıysa bile Redis `_BID_SCRIPT` re-validate edebilir (`CONCURRENT_BID_OUTBID`). Bu durumda bid DB'de audit olarak kalır, WS event publish edilmez. Bu bilinçli bir karar.

---

## 14. Redis Key Haritası — Tam TTL Envanteri

| Key Pattern | Tip | TTL | Silinme Zamanı | Açıklama |
|---|---|---|---|---|
| `auction:{stream_id}` | Hash | 24 saat | `end_auction` / `accept_bid` → explicit DEL | Canlı artırma state'i |
| `auction:bidders:{stream_id}` | Set | ∞ (TTL yok) | Saga step 3 → explicit DEL | Artırmaya katılan user_id'ler |
| `auction:events:{stream_id}` | Stream | 24 saat | — | Event outbox; max 200 entry (MAXLEN ~) |
| `shill_cnt:{stream_id}:{user_id}` | String | 24 saat | Otomatik expire | Shill uyarı sayacı |
| `stream:{stream_id}:muted` | Set | **TTL YOK** ⚠️ | Stream akışında temizlenmiyor | Muted user_id'ler |
| `shill_mute:{stream_id}` | Hash | 24 saat (planlı) | — | **YENİ (PLAN.md T-01)** — shill mute meta |
| `bin_cooldown:{stream_id}:{buyer_id}` | String | 60 saniye | Otomatik expire | BIN reddi sonrası cooldown |
| `fraud_log` | Sorted Set | 30 gün (rolling) | `zremrangebyscore` | Global fraud kayıt log'u |
| `act_rate:{user_id}:place_bid` | String | 3 saniye | Otomatik expire | Teklif hız limiti sayacı |
| `i18n:{lang}` | String | 1 saat | sync_translations.py DEL | OTA lokalizasyon cache'i |

> ⚠️ `stream:{stream_id}:muted` hiçbir zaman expire edilmiyor. Stream kapandığında `redis.sadd()` sonrası `expire()` çağrılmıyor. Düşük ancak gerçek memory leak; stream_id PostgreSQL PK'sı olduğundan yeniden kullanılmasa da key birikir.

---

## 15. Analytics ve Tracking Katmanı

### 15.1 ClickHouse Şeması

```
user_events (
  user_id   UInt64,
  event_type String,
  item_id   UInt64,
  item_type  String,   -- 'stream' | 'listing' | ...
  price_point Float32,
  created_at DateTime
)
```

### 15.2 Mevcut Tracked Event'ler (Artırma)

| Event Type | Nerede Yazılıyor | Açıklama |
|---|---|---|
| `bid_placed` | `auction.py` router | Her başarılı teklif |
| `auction_won` | `accept_bid()` saga | Kazanan teklif kabul edildi |
| `auction_ended` | `end_auction()` | Kazanan olmadan bitti |
| `listing_sold` | `accept_bid()` saga | İlanlı artırma satıldı |

### 15.3 Eksik Event'ler (Tracking Boşlukları)

| Event Type | Neden Eksik | ML/Analytics Etkisi |
|---|---|---|
| `bid_fraud_warn` | FraudDetectionService yok | Trust score fraud sinyali beslenemiyor |
| `bid_fraud_mute` | Direkt Redis, CH yok | Mute oranı ölçülemiyor |
| `bid_blocked_verify` | Exception'da CH yok | Telefon doğrulama engel oranı bilinmiyor |
| `bid_rate_limited` | Exception'da CH yok | Bot/spam aktivite tespit edilemiyor |
| `buy_it_now_requested` | Event yok | BIN talep oranı ölçülemiyor |
| `buy_it_now_rejected` | Event yok | Host red oranı / cooldown analizi yok |
| `buy_it_now_accepted` | `accept_buy_it_now` içinde yok | BIN conversion funnel eksik |
| `auction_paused` | `pause_auction` içinde yok | Yayın davranışı analizi yok |
| `auction_resumed` | `resume_auction` içinde yok | Pause süresi hesaplanamıyor |

### 15.4 Trust Score Sinyalleri

`compute_trust_scores_task` şu an ClickHouse'dan şunları alıyor:
```sql
countIf(event_type = 'auction_won')                    AS wins
countIf(event_type IN ('auction_won','auction_ended')) AS total_auctions
countIf(event_type = 'bid_placed')                     AS bids
```

Eksik sinyal:
- `bid_fraud_warn` sayısı → fraud geçmişi
- `bid_fraud_mute` sayısı → kalıcı fraud kaydı
- BIN kabul oranı → güvenilir alıcı mı?

---

## 16. ML / AI Fırsatları

### 16.1 Fraud Detection — Kural Motoru → ML

**Mevcut:** IP + 3 kural → skor → eşik. Bağlamdan bağımsız, sinyaller arasında ilişki yok.

**Öneri:** Scikit-learn veya LightGBM tabanlı ikili sınıflandırıcı:
```
Feature'lar:
  - IP eşleşmesi (bool)
  - Hesap yaşı (gün)
  - is_verified (bool)
  - Aynı stream'de önceki teklif sayısı
  - Bid-to-bid zaman aralığı (ms) — bot pattern tespiti
  - Tarihsel fraud oran (user'ın geçmiş stream'leri)
  - Host ile ortak geçmiş stream sayısı

Eğitim verisi: fraud_log (Redis → CSV export) + manuel etiketleme
Hedef: false positive <%1, gerçek shill yakalama >%80
```

Bu model `FraudDetectionService.evaluate_bid()` içinde `_score_rule_based()` ile paralel çalışabilir; ilk 6 ay rule-based devam eder.

### 16.2 Dinamik Teklif Artış Tablosu

**Mevcut:** Sabit adımlar (₺1/₺10/₺25/₺50) — tüm kategorilerde aynı.

**Öneri:** Kategori + başlangıç fiyatı + katılımcı sayısına göre dinamik increment:
```python
def optimal_increment(category: str, start_price: float, bidder_count: int) -> float:
    # Elektronik, mevcut_fiyat=₺3000, 8 teklif veren → ₺100 increment (değer teklif hissini artırır)
    # Antika, mevcut_fiyat=₺500, 2 teklif veren → ₺25 (düşük increment katılımı artırır)
```

ClickHouse'daki tarihsel teklif verisi ile A/B test edilebilir:
- Kontrol: sabit increment
- Deney: ML increment
- Metrik: toplam teklif sayısı ve final_price / start_price oranı

### 16.3 BIN Fiyat Önerisi

Host yeni artırma açarken ML modeli optimal BIN fiyat önerisi sunabilir:
```
Girdi: kategori, alt kategori, extra fields (marka, model, yıl, durum)
Benzer tamamlanan artırmalar: son 90 gün, aynı subkategori
Öneri: final_price medianı × 1.2 → BIN fiyatı teklifi
Arayüz: "Bu ürün genellikle ₺X–₺Y arası satılıyor, BIN için ₺Z öneriyoruz"
```

### 16.4 Anomali Tespiti — Koordineli Shill Ring

Tek kullanıcı tespiti yetersiz kalan senaryolar için grup tespiti:
```
Senaryo: 3 farklı IP'den 5 kullanıcı aynı host'un her yayınına giriyor, sadece 1 teklif veriyor, sonra çıkıyor.
Mevcut sistem: bireysel IP kontrolü → kimse mute edilmez.

Çözüm: Graph-based anomaly detection
  - Düğüm: kullanıcı / host
  - Kenar: "birlikte yayın izledi" (stream co-occurrence)
  - Şüpheli cluster: aynı N kullanıcı grubu birden fazla host ile yüksek co-occurrence
```

Bu, teklif verilmeden önce stream join event'lerini ClickHouse'a yazmayı gerektirir.

### 16.5 Kısa Vadeli ML Yol Haritası

| Aşama | Veri Gereksinimi | Tahmini Süre |
|---|---|---|
| T-07 (ClickHouse fraud event'leri) | — | 1 sprint |
| Fraud verisi birikimi | 4-8 hafta gerçek traffic | — |
| Rule-based baseline kalibrasyonu (PLAN Bölüm 2) | Mevcut | 1 sprint |
| Scikit-learn fraud classifier eğitimi | 500+ etiketli örnek | 2 sprint |
| Dinamik increment A/B testi | 90 gün ClickHouse bid data | 3 sprint |
