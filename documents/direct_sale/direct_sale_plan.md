# Direkt Satış (Direct Sale) Geliştirme Planı

> **Mimari Şerh:** Bu plandaki ve geliştirilecek olan tüm kodlar `documents/architectural_decisions.md` dosyasına uyumlu olmak zorundadır.

> **Görev Takibi:** Geliştirme sürecindeki tüm adımlar ve tasklar `documents/direct_sale/direct_sale_task.md` dosyasında bulunmaktadır.

> **Referans Ekran:** `create_listing_screen.dart` — pattern kararları için pilot ekran.

---

## İçindekiler

1. [State Machine (Durum Makinesi)](#1-state-machine)
2. [Host'tan Alınan Veriler](#2-hosttan-alınan-veriler-form-kararları)
3. [API Endpoint Listesi](#3-api-endpoint-listesi)
4. [Veritabanı Şeması](#4-veritabanı-şeması)
5. [Redis Key Şeması](#5-redis-key-şeması)
6. [WS Event Sözleşmesi](#6-ws-event-sözleşmesi)
7. [ClickHouse Tracking](#7-clickhouse-tracking)
8. [Geliştirme Fazları](#8-geliştirme-fazları)

---

## 1. State Machine

### 1.1 Tasarım Kararları

**Referans platformlar:** TikTok Shop Live, Shopee Live, Amazon Live

**Kaldırılan state'ler ve gerekçeleri:**

| Kaldırılan | Gerekçe |
|---|---|
| `starting` | Saf bir UI geçiş animasyonu — backend state değil. Host "Başlat"a basınca backend anında `active` olur; widget içinde lokal `_isStarting` flag yeterli. |
| `ended_early` | `ended` + `end_reason: "host_ended"` ile karşılanır. |
| `closed` | `ended` + `end_reason: "stream_closed"` ile karşılanır. `closed` kelimesi stream kapatmayla karışıyordu. |

**Eklenen field:**

`end_reason` — satış `ended` state'ine geçtiğinde neden bittiğini saklar. UI bu field'i okur; "Stok tükendi", "Satış sonlandırıldı", "Yayın kapandı" mesajlarını buna göre gösterir.

---

### 1.2 State Listesi (5 State)

#### `idle`
Satış henüz başlamadı veya bir önceki satış bitti ve sistem sıfırlandı.

- **Host UI:** `CommercePanelWrapper` mod seçim ekranı gösterir — [Açık Artırma | Direkt Satış].
- **Viewer UI:** Satış paneli görünmez.
- **Geçiş:** Host "Başlat" → `active`

---

#### `active`
Satış aktif olarak sürüyor. Stok azalabilir, alıcılar satın alabilir.

- **Host UI:** Ürün adı, fiyat, kalan stok sayacı. **"Duraklat"** ve **"Bitir"** butonları.
- **Viewer UI:** Ürün kartı (görsel, ad, fiyat, kalan stok). **"Satın Al"** butonu.
- **Geçişler:**
  - Host "Duraklat" → `paused`
  - Stok = 0 → `sold_out`
  - Host "Bitir" → `ended` (end_reason: `host_ended`)
  - Stream kapanırsa → `ended` (end_reason: `stream_closed`)

---

#### `paused`
Host geçici olarak satışı durdurdu. Stok değişmez, satın alma engellenir.

**Ne zaman kullanılır:** Ürün açıklaması yaparken, teknik sorun çözümünde veya bir sonraki ürüne geçerken kısa duraklamada.

- **Host UI:** **"Devam Et"** ve **"Bitir"** butonları. "Satış duraklatıldı" badge'i.
- **Viewer UI:** "Satın Al" butonu devre dışı. "Satış duraklatıldı" bilgisi.
- **Geçişler:**
  - Host "Devam Et" → `active`
  - Host "Bitir" → `ended` (end_reason: `host_ended`)
  - Stream kapanırsa → `ended` (end_reason: `stream_closed`)

---

#### `sold_out`
Stok sıfırlandı. Geçici terminal bekleme state'i — 5 saniye sonra otomatik `ended` geçer.

**Neden ayrı bir state?** UI'da "Stok tükendi 🎉" confetti/banner animasyonu için zaman penceresi gerekiyor. Bu 5 saniyelik pencere olmadan `ended` anında gelir ve animasyon çalışamaz.

- **Host UI:** "Tüm stok satıldı!" konfeti. Otomatik kapanma countdown.
- **Viewer UI:** "Stok tükendi" banneri. "Satın Al" butonu gizlenir.
- **Geçiş:** 5 saniye sonra otomatik → `ended` (end_reason: `sold_out`)

---

#### `ended`
Terminal state. Satış her koşulda burada biter. `end_reason` neden bittiğini açıklar.

- **Host UI:** Özet kart — kaç adet satıldı, toplam gelir. "Yeni Satış Başlat" butonu.
- **Viewer UI:** `end_reason`'a göre mesaj (aşağıya bak). Panel yavaşça kapanır.
- **Geçiş:** `CommercePanelWrapper` bu state'i alınca `idle`'a döner → mod seçimi yeniden başlar.

**`end_reason` değerleri:**

| Değer | Anlamı | Viewer Mesajı |
|---|---|---|
| `sold_out` | Stok tükendi | "Tüm ürünler satıldı!" |
| `host_ended` | Host erken bitirdi | "Satış sonlandırıldı." |
| `stream_closed` | Yayın kapandı | "Yayın sona erdi." |

---

### 1.3 State Geçiş Diyagramı

```
                    ┌─────────────────────────────────┐
                    │              idle               │
                    │   (CommercePanelWrapper seçim)  │
                    └──────────────┬──────────────────┘
                                   │ host "Başlat"
                                   ▼
                    ┌─────────────────────────────────┐
               ┌───│             active              │───┐
               │   │   (stok sayacı, satın al aktif) │   │
               │   └──────────────┬──────────────────┘   │
               │                  │                       │
         "Duraklat"          stok = 0               "Bitir" /
               │                  │               stream kapandı
               ▼                  ▼                       │
   ┌───────────────────┐  ┌──────────────────┐            │
   │      paused       │  │    sold_out      │            │
   │  (satın alma off) │  │  (5 sn bekleme)  │            │
   └──────┬────────────┘  └────────┬─────────┘            │
          │                        │ otomatik (5 sn)       │
    "Devam Et"                     │                       │
          │                        ▼                       │
          │           ┌─────────────────────────────────┐  │
          └──────────►│             ended               │◄─┘
                      │   end_reason: sold_out          │
                      │             host_ended          │
                      │             stream_closed       │
                      └──────────────┬──────────────────┘
                                     │ CommercePanelWrapper
                                     ▼
                                   idle
```

---

### 1.4 Auction State Machine ile Kıyaslama

| | Auction | Direct Sale |
|---|---|---|
| Başlangıç | `idle` | `idle` |
| Çalışıyor | `active` | `active` |
| Duraklatıldı | `paused` | `paused` |
| Özel bekleme | `buy_it_now_pending` | `sold_out` |
| Bitti | `ended` | `ended` + `end_reason` |

Her iki sistem de aynı temel pattern'i izler. Tutarlılık korundu.

---

## 2. Host'tan Alınan Veriler (Form Kararları)

### 2.1 İki Giriş Modu

Host satış başlatırken iki yoldan birini seçer:

| Mod | Açıklama |
|---|---|
| **Listing seç** | Host'un aktif ilanlarından biri seçilir. `title` ve `price` otomatik dolar, düzenlenebilir. Stok her zaman manuel girilir. |
| **Manuel giriş** | İlan bağlantısı yoktur. `title` ve `price` boş açılır, host yazar. |

### 2.2 Her Field için Kural

| Field | Zorunlu | Listing seçilince | Manuel modda | Kural |
|---|---|---|---|---|
| `title` | ✅ | `listing.title` ile dolar, düzenlenebilir | Boş, host yazar | Max 100 karakter (`listing.title` limiti ile tutarlı) |
| `price` | ✅ | `listing.price` ile dolar, düzenlenebilir | Boş, host yazar | `listing.price` her zaman dolu — create_listing zorunlu tutar. Null check gerekmez. |
| `stock_quantity` | ✅ | **Her zaman manuel** — listing'de stok field'i yok | Manuel | Min 1, integer |
| `product_image_url` | ❌ | `listing.image_url` (start anında kopyalanır) | `null` | Yükleme akışı yok. Listing seçilmezse görsel yok. |
| `listing_id` | ❌ | FK referansı — sadece kayıt amaçlı | `null` | Listing'i etkilemez — bağımsız yaşar. |

### 2.3 Listing Bağımsızlığı Kuralı

> **Karar (Seçenek B):** Direct sale, listing'in bir satış kanalıdır. Satış `ended` veya `sold_out` olduğunda `listing.status` **değişmez**. İkisi bağımsız yaşar.

**Gerekçe:** Aynı ilan birden fazla direct sale'de kullanılabilir. Listing yönetimi host'un sorumluluğundadır.

**Sonuç:** `purchase` endpoint'i asla `listings` tablosuna yazmaz.

### 2.4 Görsel Kuralı

> `product_image_url`, satış **başlatıldığı anda** listing'den kopyalanır ve `direct_sales` tablosuna yazılır.

Listing sonradan silinse veya görseli değişse bile satış kaydı etkilenmez. Viewer WS event'inden bu URL'yi direkt alır — ikinci bir API çağrısına gerek yoktur.

---

## 3. API Endpoint Listesi

### 3.1 Endpoint Tablosu

| Method | Path | Kim çağırır | Açıklama |
|---|---|---|---|
| `POST` | `/direct-sales/start` | Host | Yeni satış başlat → `active` |
| `GET` | `/direct-sales/{stream_id}/state` | Host + Viewer | Güncel state sorgula (WS reconnect sonrası) |
| `POST` | `/direct-sales/{id}/pause` | Host | `active` → `paused` |
| `POST` | `/direct-sales/{id}/resume` | Host | `paused` → `active` |
| `POST` | `/direct-sales/{id}/end` | Host | `active`/`paused` → `ended` (end_reason: `host_ended`) |
| `POST` | `/direct-sales/{id}/purchase` | Viewer | Satın al — atomik stok azalt |

### 3.2 `POST /direct-sales/start` Payload

```json
{
  "listing_id": 123,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "stock_quantity": 5
}
```

**Validasyon kuralları:**
- `listing_id` null ise `title` zorunlu
- `listing_id` varsa `title` opsiyonel (gelirse override eder, gelmezse `listing.title` kullanılır)
- `price` her zaman zorunlu (listing seçilse bile override edilebilir)
- `stock_quantity` ≥ 1, integer, zorunlu
- Aynı stream'de zaten `active` veya `paused` bir satış varsa → `DIRECT_SALE_ALREADY_ACTIVE` hatası

### 3.3 `POST /direct-sales/{id}/purchase` Payload

```json
{
  "quantity": 1
}
```

**Validasyon kuralları:**
- `quantity` ≥ 1, integer
- Satış `active` değilse → `DIRECT_SALE_NOT_ACTIVE` hatası
- Stok yetersizse → `DIRECT_SALE_INSUFFICIENT_STOCK` hatası
- Stok = 0 ise → `DIRECT_SALE_SOLD_OUT` hatası

### 3.4 `GET /direct-sales/{stream_id}/state` Response

```json
{
  "status": "active",
  "sale_id": 42,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "total_stock": 5,
  "remaining_stock": 3,
  "product_image_url": "https://...",
  "end_reason": null
}
```

---

## 4. Veritabanı Şeması

### 4.1 Karar

> Auction tablosundan **ayrı** iki tablo. İki sistemin kolonları örtüşmüyor — bid tracking vs. stock management tamamen farklı kavramlar.

### 4.2 `direct_sales` Tablosu

```sql
CREATE TABLE direct_sales (
    id               SERIAL PRIMARY KEY,
    stream_id        INTEGER NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    host_id          INTEGER NOT NULL REFERENCES users(id),
    listing_id       INTEGER REFERENCES listings(id) ON DELETE SET NULL,  -- kayıt amaçlı, zorunlu değil

    title            VARCHAR(100) NOT NULL,
    price            NUMERIC(10, 2) NOT NULL,
    product_image_url VARCHAR(500),              -- start anında listing'den kopyalanır, sonra bağımsız

    total_stock      INTEGER NOT NULL CHECK (total_stock >= 1),
    remaining_stock  INTEGER NOT NULL CHECK (remaining_stock >= 0),

    status           VARCHAR(20) NOT NULL DEFAULT 'active',
    end_reason       VARCHAR(30),                -- sold_out | host_ended | stream_closed

    started_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    ended_at         TIMESTAMP WITH TIME ZONE,

    CONSTRAINT chk_remaining_lte_total CHECK (remaining_stock <= total_stock),
    CONSTRAINT chk_end_reason CHECK (
        end_reason IN ('sold_out', 'host_ended', 'stream_closed') OR end_reason IS NULL
    )
);

CREATE INDEX ix_direct_sales_stream_id ON direct_sales(stream_id);
CREATE INDEX ix_direct_sales_status    ON direct_sales(status);
```

**`listing_id` neden nullable?** Manuel modda listing bağlantısı yok. `ON DELETE SET NULL`: listing silinirse satış kaydı kaybolmaz, referans null olur.

**`product_image_url` neden kopyalanır?** Listing sonradan değişse veya silinse bile satış geçmişi bozulmaz.

### 4.3 `direct_sale_orders` Tablosu

```sql
CREATE TABLE direct_sale_orders (
    id          SERIAL PRIMARY KEY,
    sale_id     INTEGER NOT NULL REFERENCES direct_sales(id) ON DELETE CASCADE,
    buyer_id    INTEGER NOT NULL REFERENCES users(id),
    quantity    INTEGER NOT NULL CHECK (quantity >= 1),
    unit_price  NUMERIC(10, 2) NOT NULL,   -- satış anındaki fiyat snapshot'ı
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_direct_sale_orders_sale_id   ON direct_sale_orders(sale_id);
CREATE INDEX ix_direct_sale_orders_buyer_id  ON direct_sale_orders(buyer_id);
```

**`unit_price` neden var?** Host satış sırasında fiyatı değiştiremez, ama ileride bu kapı açılırsa order'da o anki fiyat saklı kalır. Muhasebe kaydı için de doğru pratik.

### 4.4 Listing Tablosuna Dokunulmaz

> **Kural:** `direct_sale_orders` tablosu asla `listings` tablosuna yazmaz. `listing.status` direct sale tarafından değiştirilmez.

---

## 5. Redis Key Şeması

### 5.1 Key Listesi

| Key | Tip | İçerik | TTL |
|---|---|---|---|
| `direct_sale:{stream_id}:state` | Hash | Tüm aktif satış state'i | LIFECYCLE — satış bitince silinir |
| `direct_sale:{stream_id}:stock` | String (int) | Kalan stok — Lua atomik azaltma | LIFECYCLE |

### 5.2 `direct_sale:{stream_id}:state` Hash Alanları

```
sale_id           → "42"
status            → "active"
title             → "Kırmızı Çanta"
price             → "450.00"
total_stock       → "5"
remaining_stock   → "3"
product_image_url → "https://..."
end_reason        → ""
```

### 5.3 Atomik Stok Azaltma — Lua Script

```lua
-- KEYS[1] = "direct_sale:{stream_id}:stock"
-- ARGV[1] = istenen miktar (quantity)
local current = tonumber(redis.call('GET', KEYS[1]))
if current == nil then return -1 end      -- satış bulunamadı
if current < tonumber(ARGV[1]) then return 0 end  -- yetersiz stok
redis.call('DECRBY', KEYS[1], ARGV[1])
return redis.call('GET', KEYS[1])         -- kalan stok
```

**Return değerleri:**
- `-1` → satış Redis'te yok (hata)
- `0` → yetersiz stok
- `>0` → başarılı, dönen değer kalan stok
- `"0"` (string sıfır) → son adet satıldı → `sold_out` akışı başlar

### 5.4 Cache Taksonomisi

> **LIFECYCLE** (`architectural_decisions.md §9`) — stream veya auction ile aynı. Satış bitince Redis key'leri temizlenir. Manuel müdahale gerekmez.

---

---

## 6. WS Event Sözleşmesi

Tüm event'ler `stream_id` bazlı topic'e yayınlanır: `stream:{stream_id}`.  
Pattern: auction event'leri ile tutarlı — aynı WS bağlantısı, aynı topic.

### 6.1 Event Tablosu

| Event Type | Tetikleyici | Alıcı |
|---|---|---|
| `direct_sale_started` | `POST /start` başarılı | Tüm viewer'lar + host |
| `direct_sale_paused` | `POST /pause` | Tüm viewer'lar + host |
| `direct_sale_resumed` | `POST /resume` | Tüm viewer'lar + host |
| `direct_sale_purchased` | `POST /purchase` başarılı | Tüm viewer'lar + host |
| `direct_sale_sold_out` | `remaining_stock` = 0 | Tüm viewer'lar + host |
| `direct_sale_ended` | `POST /end` veya otomatik (5 sn sold_out timer) | Tüm viewer'lar + host |

### 6.2 Event Payload'ları

#### `direct_sale_started`
```json
{
  "type": "direct_sale_started",
  "sale_id": 42,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "total_stock": 5,
  "remaining_stock": 5,
  "product_image_url": "https://..."
}
```

#### `direct_sale_paused`
```json
{
  "type": "direct_sale_paused",
  "sale_id": 42
}
```

#### `direct_sale_resumed`
```json
{
  "type": "direct_sale_resumed",
  "sale_id": 42,
  "remaining_stock": 3
}
```

#### `direct_sale_purchased`
```json
{
  "type": "direct_sale_purchased",
  "sale_id": 42,
  "buyer_username": "ahmet_k",
  "quantity": 1,
  "remaining_stock": 2
}
```
> `buyer_id` payload'a **girmez** — privacy. Sadece `buyer_username`.

#### `direct_sale_sold_out`
```json
{
  "type": "direct_sale_sold_out",
  "sale_id": 42
}
```

#### `direct_sale_ended`
```json
{
  "type": "direct_sale_ended",
  "sale_id": 42,
  "end_reason": "host_ended",
  "total_sold": 3,
  "total_revenue": 1350.0
}
```
> `end_reason`: `sold_out` | `host_ended` | `stream_closed`

### 6.3 CommercePanelWrapper Dinleme Kuralı

| Alınan Event | Wrapper Davranışı |
|---|---|
| `direct_sale_started` | `idle` → `DirectSalePanel` (active) göster |
| `direct_sale_ended` | Panel kapat → `idle` mod seçimine dön |
| `auction_started` (mevcut) | `idle` → `AuctionPanel` göster |
| `auction_ended` (mevcut) | Panel kapat → `idle` mod seçimine dön |

---

## 7. ClickHouse Tracking

*Bu bölüm Faz 5'te doldurulacak — event'ler netleştikten sonra.*

Planlanan event'ler:
- `sale_started` — host satış başlattı
- `sale_impression` — viewer paneli gördü (scroll yüzdesi ≥ %80)
- `purchase_intent` — "Satın Al" butonuna dokundu
- `purchase_completed` — satın alma tamamlandı
- `sale_ended` — satış bitti (`end_reason` ile)

**Kural:** `architectural_decisions.md §3.3` — veri birikmeden ML modelleri güncellenmez.

---

## 8. Geliştirme Fazları

### Faz 0 — Kontrat (Kod Yok)
Tüm sözleşmelerin kağıt üzerinde tamamlanması. Bu dosyanın §2–§6 bölümlerini doldur.

**Çıktı:** `direct_sale_plan.md` tam dolu, `direct_sale_task.md` task listesi hazır.
**Bağımlılık:** Hiçbir şey. Burası her şeyin türevidir.

---

### Faz 1 — Veritabanı Temeli
- `direct_sales` ve `direct_sale_orders` tabloları
- Alembic migration (SQL olarak üretilir, VPS'te çalıştırılır)
- SQLAlchemy model + Pydantic şemaları

**Bağımlılık:** Faz 0 (DB şeması netleşmiş olmalı)

---

### Faz 2 — Backend Core (State Machine + Host API)

Kritik: **Redis Lua ile atomik stok yönetimi** bu fazda çözülür.

- Redis state manager: `start`, `pause`, `resume`, `end` geçişleri
- Lua script: stok azaltma atomik (aynı auction Lua pattern'i)
- FastAPI router: host kontrol endpoint'leri
- WS broadcast: state değişikliklerini stream viewer'larına yay
- LIFECYCLE cache

**Bağımlılık:** Faz 1

---

### Faz 3 — Purchase Flow (Satın Alma)

- `POST /direct-sales/{id}/purchase` endpoint
- Lua: `if remaining_stock > 0 → decrement → return 1 else return 0` — race condition yok
- Başarıda: DB'ye order, WS `direct_sale_purchased` broadcast (kalan stok + alıcı)
- Başarısızda: `DIRECT_SALE_SOLD_OUT` AppException
- 5 saniye `sold_out` timer → otomatik `ended`

**Bağımlılık:** Faz 2

---

### Faz 4 — Flutter UI

Backend hazır olmadan başlanmaz.

- `CommercePanelWrapper` — mod seçici (Açık Artırma / Direkt Satış)
- `DirectSalePanel` host view: başlat / duraklat / bitir
- `DirectSalePanel` viewer view: ürün kartı, stok sayacı, satın al
- WS dinleyici + state machine — MVVM (Riverpod `AsyncNotifier`)
- `architectural_decisions.md` kuralları: OTA loc, `handleError`, `TeqAsyncButton`
- `sold_out` konfeti animasyonu

**Bağımlılık:** Faz 3

---

### Faz 5 — ClickHouse Tracking

Mevcut event tracking pattern'ine ek:
- Backend: `direct_sale_events` ClickHouse tablosu (`ALTER TABLE ADD COLUMN` pattern)
- Flutter: client-side event loglama

**Bağımlılık:** Faz 4 (event'lerin ne olduğu belli olmuş olmalı)

---

### Faz 6 — ML / AI (Sonra)

`architectural_decisions.md §3.3` kuralı: veri birikmeden model güncellenmez. 2–4 hafta gerçek satış verisi birikmeli.

- Fiyat önerisi (geçmiş satış verisi bazlı)
- Talep tahmini (kaç adet listelemeli)

**Bağımlılık:** Faz 5 + 2–4 hafta veri birikimi

---

## Kural Özeti

| Kural | Detay |
|---|---|
| State sayısı | 5: `idle`, `active`, `paused`, `sold_out`, `ended` |
| Terminal field | `end_reason`: `sold_out` · `host_ended` · `stream_closed` |
| `starting` | Backend state değil — widget lokal flag |
| Stok yönetimi | Redis Lua atomik — race condition sıfır |
| Cache tipi | LIFECYCLE (auction ile aynı) |
| Tablo yapısı | Auction'dan ayrı: `direct_sales` + `direct_sale_orders` |
| Pattern uyumu | Auction state machine ile tutarlı |
