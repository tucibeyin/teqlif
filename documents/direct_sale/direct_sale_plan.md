# Direkt Satış (Direct Sale) Geliştirme Planı

> **Mimari Şerh:** Bu plandaki ve geliştirilecek olan tüm kodlar `documents/architectural_decisions.md` dosyasına uyumlu olmak zorundadır.

> **Görev Takibi:** Geliştirme sürecindeki tüm adımlar ve tasklar `documents/direct_sale/direct_sale_task.md` dosyasında bulunmaktadır.

> **Referans Ekran:** `create_listing_screen.dart` — pattern kararları için pilot ekran.

---

## İçindekiler

1. [State Machine (Durum Makinesi)](#1-state-machine)
2. [Host'tan Alınan Veriler](#2-hosttan-alınan-veriler-form-kararları)
   - [2.B Alıcı Deneyimi](#2b-alıcı-viewer-deneyimi)
   - [2.C Viewer Widget Davranışları](#2c-viewer-widget--state-bazlı-davranışlar)
3. [API Endpoint Listesi](#3-api-endpoint-listesi)
4. [Veritabanı Şeması](#4-veritabanı-şeması)
5. [Redis Key Şeması](#5-redis-key-şeması)
6. [WS Event Sözleşmesi](#6-ws-event-sözleşmesi)
7. [ClickHouse Tracking](#7-clickhouse-tracking)
8. [Geliştirme Fazları](#8-geliştirme-fazları)
9. [Satın Alma Mesajlaşması](#9-satın-alma-mesajlaşması)
10. [Alışverişlerim / Satışlarım Entegrasyonu](#10-alışverişlerim--satışlarım-entegrasyonu)
11. [Proof Fotoğrafı](#11-proof-fotoğrafı)
12. [CommercePanelWrapper Kararları](#12-commercepanelwrapper-kararları)
13. [i18n — ARB Key'leri](#13-i18n--arb-keyleri)
14. [Commerce Bounded Context — Unified API ve Modeller](#14-commerce-bounded-context--unified-api-ve-modeller)
15. [Mimari Tutarlılık Kontrol Listesi](#15-mimari-tutarlılık-kontrol-listesi)

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

**Eklenen field'ler:**

`end_reason` — satış `ended` state'ine geçtiğinde neden bittiğini saklar. UI bu field'i okur; "Stok tükendi", "Satış sonlandırıldı", "Yayın kapandı" mesajlarını buna göre gösterir.

`orders_voided` — satış `cancelled` state'ine geçtiğinde host'un mevcut siparişler için verdiği kararı saklar. `true` → siparişler iptal edildi; `false` → siparişler geçerli kalıyor.

**"Bitir" ile "İptal" ayrımı:**

| Eylem | Hedef State | Siparişler |
|---|---|---|
| **Bitir** | `ended` (end_reason: `host_ended`) | Her zaman geçerli |
| **İptal** | `cancelled` | Host seçer: void veya geçerli |

---

### 1.2 State Listesi (6 State)

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
Terminal state. Normal tamamlanma — tüm siparişler geçerlidir.

- **Host UI:** Özet kart — kaç adet satıldı, toplam gelir. "Yeni Satış Başlat" butonu.
- **Viewer UI:** `end_reason`'a göre mesaj (aşağıya bak). Panel yavaşça kapanır.
- **Geçiş:** `CommercePanelWrapper` bu state'i alınca `idle`'a döner → mod seçimi yeniden başlar.

**`end_reason` değerleri:**

| Değer | Anlamı | Viewer Mesajı |
|---|---|---|
| `sold_out` | Stok tükendi | "Tüm ürünler satıldı!" |
| `host_ended` | Host "Bitir"e bastı | "Satış sonlandırıldı." |
| `stream_closed` | Yayın kapandı | "Yayın sona erdi." |

---

#### `cancelled`
Terminal state. Host "İptal"e bastı. Siparişlerin akıbeti `orders_voided` field'ine göre belirlenir.

- **Host UI:** İptal onay dialogu (aşağıya bak). Sonrası `ended` ile aynı özet kart.
- **Viewer UI:** "Satış iptal edildi." mesajı. Panel kapanır.
- **Geçiş:** `CommercePanelWrapper` bu state'i alınca `idle`'a döner.

**İptal dialogu akışı:**

Sipariş yoksa (`remaining_stock == total_stock`) → basit onay, doğrudan `cancelled`.

Sipariş varsa:
```
┌─────────────────────────────────────┐
│  Satışı iptal etmek istiyor musun? │
│  Bu ana kadar X sipariş verildi.   │
│                                     │
│ [ Siparişleri İptal Et ]           │  → cancelled + orders_voided: true
│ [ Siparişleri Geçerli Tut ]        │  → cancelled + orders_voided: false
│ [ Vazgeç ]                         │  → hiçbir şey olmaz
└─────────────────────────────────────┘
```

**`orders_voided: true`:** Her `direct_sale_order.status` → `'cancelled'` olarak güncellenir. Alıcılara DM + push: "Satış iptal edildi, siparişiniz geçersiz sayıldı."

**`orders_voided: false`:** Siparişlere dokunulmaz. Alıcılara DM: "Satış iptal edildi, siparişiniz geçerli."

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
               │   └──────┬───────────┬──────────────┘   │
               │          │           │                   │
         "Duraklat"  stok = 0     "İptal"           "Bitir" /
               │          │           │           stream kapandı
               ▼          ▼           ▼                   │
   ┌─────────────┐  ┌──────────┐  ┌──────────────────┐    │
   │   paused    │  │ sold_out │  │    cancelled     │    │
   │ (alım off)  │  │ (5 sn)   │  │ orders_voided:   │    │
   └──┬──────────┘  └────┬─────┘  │ true | false     │    │
      │                  │ (5 sn) └──────────────────┘    │
 "Devam Et"              │                                 │
      │            "İptal"│                                │
      │                  ▼                                 │
      │     ┌─────────────────────────────────┐            │
      └────►│             ended               │◄───────────┘
            │   end_reason: sold_out          │
            │             host_ended          │
            │             stream_closed       │
            └──────────────┬──────────────────┘
                           │ CommercePanelWrapper
                           ▼
                         idle
```

> `paused` → `cancelled` geçişi de mümkündür (host duraklatılmış satışı da iptal edebilir).

---

### 1.4 Auction State Machine ile Kıyaslama

| | Auction | Direct Sale |
|---|---|---|
| Başlangıç | `idle` | `idle` |
| Çalışıyor | `active` | `active` |
| Duraklatıldı | `paused` | `paused` |
| Özel bekleme | `buy_it_now_pending` | `sold_out` |
| Normal bitti | `ended` | `ended` + `end_reason` |
| Host iptali | — | `cancelled` + `orders_voided` |

Her iki sistem de aynı temel pattern'i izler. `cancelled` direct sale'e özgü — auction'da karşılığı yok.

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

## 2.B Alıcı (Viewer) Deneyimi

### 2.B.1 Satın Alma Akışı — Ürün Kartı + Unified Modal

Viewer aktif satış panelindeki **tıklanabilir ürün kartına** basar — ayrı bir "Hemen Al" butonu yoktur. Kart hem bilgi kaynağı hem CTA'dır. Sektör standardı (TikTok Shop Live, Shopee Live).

```
Tıklanabilir ürün kartı (panel üzerinde)
    ↓
Bottom sheet (aşağıdan süzülür) — ürün detayı + satın alma:
  ┌─────────────────────────────┐
  │ [Proof / Ürün Görseli]      │  ← proof_image_url önce, yoksa product_image_url, yoksa placeholder
  │ Kırmızı Çanta               │
  │ 450 TL      Kalan: 3 adet  │
  │ ─────────────────────────── │
  │           ✓ 2 adet aldın   │  ← sadece daha önce aldıysa görünür (lokal state)
  │                             │
  │ Adet:  [−]  1  [+]         │
  │ Toplam: 450 TL              │
  │                             │
  │  [   Hemen Satın Al   ]    │
  └─────────────────────────────┘
  Dışarı tap veya aşağı sürükle → kapanır
```

**Görsel önceliği:** `proof_image_url` (host'un satış başında çektiği) → `product_image_url` (listing'den kopyalanan) → ikon placeholder.

**"Vazgeç" senaryosu:** Bottom sheet'i kapatmak. API çağrısı yapılmaz, stok değişmez, backend haberdar olmaz.

### 2.B.2 Adet (Quantity) Kuralları

| Kural | Değer | Gerekçe |
|---|---|---|
| Varsayılan | 1 | Impulse purchase — en hızlı akış |
| Minimum | 1 | — |
| Maksimum | `min(remaining_stock, 10)` | Sistem limiti: 10. Kalan stok daha azsa stok limiti geçerli. |
| Tipi | Integer stepper `[−] n [+]` | Sayısal keyboard yerine stepper — hata oranı düşük |

> **Sistem limiti = 10.** Host bu limiti değiştiremez (şimdilik). İleride host kontrolüne taşımak: tek bir DB kolonu + form field'i — mevcut validasyon değişmez.

### 2.B.3 Tekrar Satın Alma

> **Karar: İzin verilir.** Viewer aynı satıştan birden fazla order verebilir.

**Gerekçe:** Max 10/order limiti zaten var. Birden fazla order ile birden fazla kişiye alabileceği durum geçerli bir kullanım senaryosudur. Kısıtlamak için ekstra backend logic ve DB constraint yazılması orantısız efor.

**Şeffaflık:** Viewer önceki alımını bottom sheet'te görür — "✓ X adet aldın" badge'i. Flutter **lokal state**'te tutulur, backend'e ekstra sorgu atılmaz. Satış `ended` olunca sıfırlanır.

### 2.B.4 Viewer Lokal State Machine

Backend'e yansımaz — tamamen Flutter widget state'i.

```
browsing
  │ "Hemen Al" tap
  ▼
confirming  (bottom sheet açık)
  │ dışarı tap / swipe down
  ├──────────────────► browsing   (API yok, stok değişmez)
  │
  │ "Satın Al" tap
  ▼
purchasing  (API in-flight, spinner)
  │ başarı
  ├──────────────────► purchased  (badge güncellenir, bottom sheet kapanır)
  │ hata
  └──────────────────► error      (toast: stok bitti / ağ hatası vb.)
                            │ toast kapanınca
                            ▼
                         confirming veya browsing
```

### 2.B.5 State'e Göre Viewer UI Özeti

| Satış State | Ürün Kartı Tıklanabilir mi | Modal Açılır mı | Açıklama |
|---|---|---|---|
| `active` | ✅ Evet | ✅ Evet | Normal akış — modal açılır, satın alma yapılabilir |
| `paused` | ✅ Görünür | ❌ Hayır | Kart görünür ama tap'e yanıt vermez |
| `sold_out` | ❌ Gizli | ❌ Hayır | "Stok tükendi" banneri, kart kaybolur |
| `ended` | ❌ Gizli | ❌ Hayır | Panel kapanıyor, `end_reason` mesajı |
| `cancelled` | ❌ Gizli | ❌ Hayır | Panel kapanıyor, toast mesajı |

---

## 2.C Viewer Widget — State Bazlı Davranışlar

Her direct sale state'inde izleyicinin gördüğü widget davranışı. WS event'i geldiğinde Flutter bu tabloya göre UI günceller.

### 2.C.1 State Tablosu

| State | Widget | Ürün Kartı | Gösterilen İçerik | Animasyon |
|---|---|---|---|---|
| `idle` | Minimal chip | — | 🛍️ "Henüz satış yok" | — |
| `active` | Tam panel | ✅ Tıklanabilir → modal | Görsel · başlık · fiyat · stok sayacı | Slide-up (aşağıdan) |
| `paused` | Tam panel, soluk | 👁 Görünür, tap yok | "Satış duraklatıldı" badge'i · stok donmuş | — |
| `sold_out` | Tam panel | ❌ Gizli | "Stok tükendi 🎉" banner | Konfeti (5 sn) |
| `ended` | Kapanıyor | ❌ Gizli | `end_reason`'a göre mesaj | Fade-out |
| `cancelled` | Kapanıyor | ❌ Gizli | `orders_voided`'a göre toast | Fade-out |

### 2.C.2 `idle` — Minimal Chip

```
╭──────────────────────────╮
│  🛍️  Henüz satış yok    │
╰──────────────────────────╯
```

- Soluk, küçük, UI'ı domine etmez
- Satış başlayınca (`direct_sale_started` WS event) chip kaybolur → panel slide-up ile açılır
- Auction aktifse chip görünmez — `CommercePanelWrapper` zaten `AuctionPanel`'i gösteriyor

### 2.C.3 `active` — Tıklanabilir Ürün Kartı

Panel üzerinde ayrı bir "Hemen Al" butonu yoktur — **kartın tamamı tıklanabilir**, modal açar (§2.B.1).

`direct_sale_purchased` WS event'i geldiğinde stok sayacı canlı güncellenir.

`remaining_stock ≤ 3` olduğunda aciliyet moduna geçer:

```
┌────────────────────────────────┐
│ [Görsel]  Kırmızı Çanta    ›  │  ← tıklanabilir, chevron hint
│           450 TL              │
│           ⚠️ Son 3 adet!      │  ← kırmızı/turuncu vurgu
└────────────────────────────────┘
```

Kartın sağındaki `›` (chevron) tıklanabilirliği işaret eder. `paused` durumunda kart görünür ama tap'e yanıt vermez (modal açılmaz).

### 2.C.4 `ended` — `end_reason` Mesajları

| `end_reason` | Viewer Mesajı |
|---|---|
| `sold_out` | "Tüm ürünler satıldı! 🎉" |
| `host_ended` | "Satış sonlandırıldı." |
| `stream_closed` | "Yayın sona erdi." |

Mesaj kısa süre (≈2 sn) gösterilir, ardından panel tamamen kapanır → `idle` chip'e döner.

### 2.C.5 `cancelled` — `orders_voided` Mesajları

Flutter'da `totalPurchasedQuantity` local state'i zaten tutuluyor (§2.B.3). Ekstra API çağrısı gerekmez.

| Viewer durumu | `orders_voided` | Toast rengi | Mesaj |
|---|---|---|---|
| Hiç almadı | `false` veya `true` | Nötr | "Satış iptal edildi." |
| Satın aldı | `false` | Yeşil | "Satış iptal edildi, siparişiniz geçerli." |
| Satın aldı | `true` | Kırmızı | "Satış iptal edildi, siparişiniz geçersiz sayıldı." |

Toast gösterildikten sonra panel kapanır → `idle` chip'e döner.

### 2.C.6 Geç Katılan Viewer

Viewer stream'e aktif bir satış sırasında katılırsa widget WS event beklemez — `GET /direct-sales/{stream_id}/state` endpoint'inden (§3) güncel state'i çeker ve doğrudan `active` paneli gösterir.

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
| `POST` | `/direct-sales/{id}/cancel` | Host | `active`/`paused` → `cancelled`; body: `{orders_voided: bool}` |
| `POST` | `/direct-sales/{id}/purchase` | Viewer | Satın al — atomik stok azalt |

### 3.2 `POST /direct-sales/start` Payload

```json
{
  "listing_id": 123,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "stock_quantity": 5,
  "proof_image_url": "/uploads/abc123.png"
}
```
> `proof_image_url` opsiyonel — host "Geç" seçtiyse `null`. Upstream'de `_showProofCaptureDialog` return semantiği: `null` = akış iptal, `''` = atlandı, `"url"` = çekildi (§11.3).

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
- `quantity` ≥ 1, ≤ 10 (sistem limiti), integer
- Satış `active` değilse → `DIRECT_SALE_NOT_ACTIVE` hatası
- `quantity` > `remaining_stock` → `DIRECT_SALE_INSUFFICIENT_STOCK` hatası
- `remaining_stock` = 0 → `DIRECT_SALE_SOLD_OUT` hatası

**Tekrar satın alma:** Aynı viewer aynı satıştan birden fazla order verebilir. Backend bu kontrolü yapmaz — stok yeterli olduğu sürece her istek işlenir.

### 3.4 `GET /direct-sales/{stream_id}/state` Response

```json
{
  "status": "active",
  "sale_id": 42,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "total_stock": 5,
  "remaining_stock": 3,
  "product_image_url": "/uploads/abc.jpg",
  "proof_image_url": "/uploads/proof.jpg",
  "end_reason": null
}
```
> `proof_image_url` nullable. Late-join viewer bu endpoint'i çeker (§2.C.6) — viewer modalının proof görseli göstermesi için gereklidir.

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

    status           VARCHAR(20) NOT NULL DEFAULT 'active',  -- idle|active|paused|sold_out|ended|cancelled
    end_reason       VARCHAR(30),                -- sold_out | host_ended | stream_closed
    orders_voided    BOOLEAN NOT NULL DEFAULT FALSE,  -- cancelled state'inde host siparişleri iptal etti mi

    viewer_count_at_start INTEGER,                          -- satış başında yayındaki izleyici sayısı (ML conversion feature)
    category         VARCHAR(50),                            -- listing.category snapshot; null → manuel mod (ML classification feature)

    started_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    ended_at         TIMESTAMP WITH TIME ZONE,

    CONSTRAINT chk_remaining_lte_total CHECK (remaining_stock <= total_stock),
    CONSTRAINT chk_end_reason CHECK (
        end_reason IN ('sold_out', 'host_ended', 'stream_closed') OR end_reason IS NULL
    ),
    CONSTRAINT chk_direct_sale_status CHECK (
        status IN ('active', 'paused', 'sold_out', 'ended', 'cancelled')
    )
    -- NOT: 'idle' DB state değil — "kayıt yok" anlamına gelir. DB'de hiçbir zaman 'idle' yazılmaz.
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
    seller_id   INTEGER NOT NULL REFERENCES users(id),                          -- host_id snapshot; mesajlaşma JOIN'siz
    buyer_id    INTEGER NOT NULL REFERENCES users(id),
    listing_id  INTEGER REFERENCES listings(id) ON DELETE SET NULL,             -- direct_sales.listing_id snapshot; link için
    quantity    INTEGER NOT NULL CHECK (quantity >= 1),
    unit_price  NUMERIC(10, 2) NOT NULL,   -- satış anındaki fiyat snapshot'ı
    status      VARCHAR(20) NOT NULL DEFAULT 'completed',  -- completed | cancelled
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX ix_direct_sale_orders_sale_id   ON direct_sale_orders(sale_id);
CREATE INDEX ix_direct_sale_orders_buyer_id  ON direct_sale_orders(buyer_id);
CREATE INDEX ix_direct_sale_orders_seller_id ON direct_sale_orders(seller_id);
```

**`seller_id` + `listing_id` neden var?** Satın alma sonrası DirectMessage gönderiminde `direct_sales` JOIN'i olmadan çalışır. Purchase anındaki FK snapshot'ı; listing sonradan silinse bile satış kaydı bozulmaz. `listing_id ON DELETE SET NULL`: silinmiş listing linki mesajda görünür ama deep link çalışmaz — kabul edilebilir.

**`unit_price` neden var?** Host satış sırasında fiyatı değiştiremez, ama ileride bu kapı açılırsa order'da o anki fiyat saklı kalır. Muhasebe kaydı için de doğru pratik.

**`UNIQUE(sale_id, buyer_id)` neden yok?** Tekrar satın almaya izin veriliyor — aynı viewer aynı satıştan birden fazla order verebilir. Her order bağımsız bir kayıt.

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
- `-1` → satış Redis'te yok
- `-2` → yetersiz stok (purchase reddedildi, stok değişmedi)
- `0` → son adet satıldı → `sold_out` akışı başlar
- `>0` → başarılı, dönen değer kalan stok

> **Not:** Orijinal tasarımda `0=insufficient` / `"0"=son adet` ayrımı Python `int` vs `bytes` farkına dayanıyordu — brittle. Uygulama `-2` sentinel'i kullanır.

### 5.4 Cache Taksonomisi

`architectural_decisions.md §9` — 5 kategori. Direct sale'in kullandığı kategoriler:

| Cache Tipi | Nerede kullanılıyor | Silinme tetikleyicisi |
|---|---|---|
| **LIFECYCLE** | `direct_sale:{stream_id}:state`, `direct_sale:{stream_id}:stock` | Satış `ended` veya `cancelled` olunca |
| **EPHEMERAL** | `GET /me/commerce/purchases` (60s TTL, per user), `GET /me/commerce/sales` (60s TTL), `GET /direct-sales/{id}/summary` (30s TTL) | TTL sona erince |
| **SECURITY_CRITICAL** | — | — |

**`GET /direct-sales/{id}/orders`:** Cache'lenmez — aktif satış sırasında canlı değişir.

**`GET /direct-sales/{stream_id}/state`:** Cache'lenmez — Redis hash'ten direkt okunur, zaten O(1).

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
| `direct_sale_cancelled` | `POST /cancel` | Tüm viewer'lar + host |

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
  "product_image_url": "/uploads/abc.jpg",
  "proof_image_url": "/uploads/proof.jpg"
}
```
> `proof_image_url` nullable — host "Geç" seçtiyse `null`. Viewer modalı görsel önceliğini buna göre uygular: `proof_image_url` → `product_image_url` → placeholder (§2.B.1).

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

#### `direct_sale_cancelled`
```json
{
  "type": "direct_sale_cancelled",
  "sale_id": 42,
  "orders_voided": true
}
```
> `orders_voided: true` → viewer'ın satın aldığı varsa "Siparişiniz iptal edildi" toast'u gösterilir.
> `orders_voided: false` → "Satış iptal edildi, siparişiniz geçerli" toast'u gösterilir.

### 6.3 CommercePanelWrapper Dinleme Kuralı

| Alınan Event | Wrapper Davranışı |
|---|---|
| `direct_sale_started` | `idle` → `DirectSalePanel` (active) göster |
| `direct_sale_ended` | Panel kapat → `idle` mod seçimine dön |
| `direct_sale_cancelled` | Panel kapat → `idle` mod seçimine dön |
| `auction_started` (mevcut) | `idle` → `AuctionPanel` göster |
| `auction_ended` (mevcut) | Panel kapat → `idle` mod seçimine dön |

---

## 7. ClickHouse Tracking

### 7.1 Dual-Write Stratejisi

Auction'daki pattern ile özdeş — iki hedef, iki amaç:

| Hedef | Tablo | Amaç |
|---|---|---|
| ML sinyali | `user_events` (mevcut) | `user_interests` güncelleme, BPR/ALS eğitimi |
| Dönüşüm analizi | `direct_sale_events` (yeni) | Huni analizi, host performansı, fiyat elastikiyeti |

Her iki yazma da `fire_and_forget` — satın alma akışını bloke etmez.

### 7.2 `user_events` — ML Sinyali (Mevcut Tablo)

Satın alma tamamlandığında auction win ile **aynı pattern**:

```python
fire_and_forget(track_user_event(
    event_type="direct_sale_purchase",
    user_id=buyer_id,
    item_id=listing_id,         # null → manuel mod
    item_type="direct_sale",
    category=sale.category,     # direct_sales.category snapshot
))
```

Bu satır `user_interests(user_id, category, subcategory, score)` güncellemesini tetikler — alıcının kategori affinitesi artar. Auction win ile tam uyumlu.

### 7.3 `direct_sale_events` — Yeni ClickHouse Tablosu

```sql
CREATE TABLE direct_sale_events (
    event_id     UUID DEFAULT generateUUIDv4(),
    event_type   LowCardinality(String),      -- aşağıya bak
    sale_id      UInt32,
    stream_id    UInt32,
    host_id      UInt32,
    user_id      UInt32,                      -- buyer (purchase) veya host (sale events)
    order_id     Nullable(UInt32),
    listing_id   Nullable(UInt32),
    category     LowCardinality(Nullable(String)),
    quantity     Nullable(UInt8),
    unit_price   Nullable(Decimal(10, 2)),
    total_price  Nullable(Decimal(10, 2)),
    remaining_stock_before Nullable(UInt16),
    remaining_stock_after  Nullable(UInt16),
    viewer_count Nullable(UInt32),            -- sale_started anındaki izleyici sayısı
    end_reason   LowCardinality(Nullable(String)),
    orders_voided Nullable(Bool),
    created_at   DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (sale_id, created_at, event_type);
```

`architectural_decisions.md §3.1` — yeni sütun gerekirse `ALTER TABLE ... ADD COLUMN`, yeni tablo açılmaz.

### 7.4 Event Listesi ve Tetiklenme Noktaları

| `event_type` | Tetikleyici | Dolu alanlar |
|---|---|---|
| `sale_started` | `POST /start` başarısı | sale_id, host_id, listing_id, category, unit_price, viewer_count, remaining_stock_before=total_stock |
| `sale_impression` | Viewer paneli gördü (Flutter client) | sale_id, user_id, remaining_stock_before |
| `purchase_intent` | "Hemen Al" bottom sheet açıldı (Flutter) | sale_id, user_id, remaining_stock_before |
| `purchase_completed` | `POST /purchase` commit başarısı | sale_id, order_id, user_id, quantity, unit_price, total_price, remaining_stock_before, remaining_stock_after |
| `sale_ended` | `POST /end` veya 5 sn sold_out timer | sale_id, host_id, end_reason, remaining_stock_after, viewer_count |
| `sale_cancelled` | `POST /cancel` | sale_id, host_id, orders_voided, order_count (toplam iptal edilen) |

**`sale_impression` ve `purchase_intent`:** Backend değil, Flutter client tarafında loglanır — mevcut `POST /api/analytics/user-events` endpoint'ine `event_type` eklenerek gönderilir.

### 7.5 ML Huni Analizi

```
sale_impression
    → purchase_intent      (impression → intent dönüşüm oranı)
        → purchase_completed   (intent → purchase dönüşüm oranı)
```

**Conversion rate = `purchase_completed / sale_impression`** — `viewer_count_at_start` (§4.2) ile normalize edilir.

Bu veri Faz 6'da şunları sağlar:
- Kategori bazlı optimal fiyat önerisi (geçmiş `unit_price` + dönüşüm oranı)
- Host'a "kaç adet listele" tahmini (geçmiş `viewer_count` + satılan adet)
- Stok tükenme süresi tahmini (aciliyet UI tetikleme optimizasyonu)

**Kural:** `architectural_decisions.md §3.3` — Faz 6 başlamadan önce minimum 2-4 hafta gerçek satış verisi birikmelidir.

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
- Backend: `direct_sale_events` yeni ClickHouse tablosu (`CREATE TABLE` — §7.3 DDL)
- Flutter: client-side event loglama (`sale_impression`, `purchase_intent`)
- Not: gelecekte `direct_sale_events`'e kolon eklemek gerekirse `ALTER TABLE ADD COLUMN` (ADR §3.1)

**Bağımlılık:** Faz 4 (event'lerin ne olduğu belli olmuş olmalı)

---

### Faz 6 — ML / AI (Sonra)

`architectural_decisions.md §3.3` kuralı: veri birikmeden model güncellenmez. 2–4 hafta gerçek satış verisi birikmeli.

- Fiyat önerisi (geçmiş satış verisi bazlı)
- Talep tahmini (kaç adet listelemeli)

**Bağımlılık:** Faz 5 + 2–4 hafta veri birikimi

---

## 9. Satın Alma Mesajlaşması

### 9.1 Model Kararı

> **Karar: Mevcut `DirectMessage` modeli kullanılır.** Auction BIN completion pattern ile özdeş.

Satın alma DB commit'i başarıyla tamamlandıktan sonra:
1. `DirectMessage(sender_id=host_id, receiver_id=buyer_id, content=dm_content)` oluşturulur
2. Aynı session'a eklenir, commit edilir
3. WS broadcast: hem buyer'a hem host'a aynı payload (`dm:{buyer_id}` + `dm:{host_id}`)
4. Buyer'a push notification gönderilir

### 9.2 DM İçerik Formatı

```python
total_price = unit_price * quantity
price_line = fmt_price(total_price)
if quantity > 1:
    price_line += f" ({quantity} adet × {fmt_price(unit_price)})"

dm_content = (
    f"🛍️ Satın alma tamamlandı! Tebrikler!\n"
    f"📦 Ürün: {title}\n"
    f"💰 Fiyat: {price_line}"
)

if listing_id:
    dm_content += f"\n🔗 teqlif://listing/{listing_id}"

dm_content += f"\n📋 teqlif://direct-sale/{sale_id}"
```

**Örnek mesaj (listing_id=123, quantity=2, unit_price=450):**
```
🛍️ Satın alma tamamlandı! Tebrikler!
📦 Ürün: Kırmızı Çanta
💰 Fiyat: 900 TL (2 adet × 450 TL)
🔗 teqlif://listing/123
📋 teqlif://direct-sale/42
```

### 9.3 Deep Link Tablosu

| Link | Hedef | Koşul |
|---|---|---|
| `teqlif://listing/{listing_id}` | Listing detay ekranı | Sadece `listing_id` varsa eklenir |
| `teqlif://direct-sale/{sale_id}` | Satış özeti ekranı | Her zaman eklenir |

### 9.4 WS Broadcast (Her İki Tarafa)

Auction pattern ile özdeş — aynı DM payload hem buyer hem host'un kanalına yayınlanır:

```python
fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{buyer_id}", dm_payload))
fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{host_id}", dm_payload))
```

### 9.5 Mesajlaşma Tetiklenme Noktası

`POST /direct-sales/{id}/purchase` → Lua atomik stok başarılı → DB order oluştu → commit → **DM oluştur + WS broadcast**.

Başarısız commit veya stok yetersizliği durumunda DM oluşturulmaz.

---

## 10. Alışverişlerim / Satışlarım Entegrasyonu

> **Mimari karar:** Mevcut `/me/purchases` ve `/me/sales` endpoint'leri yalnızca `auctions` tablosunu sorgular. Direct sale eklenmesiyle bu endpoint'ler **`/me/commerce/purchases`** ve **`/me/commerce/sales`** olarak yeniden tasarlanır — ileriki satış tipleri (FixedPrice, GroupBuy vb.) sıfır backend değişikliğiyle bu endpoint'lere eklenir.

### 10.1 Unified Purchase Response — `/me/commerce/purchases`

Her item bir purchase (order) kaydıdır. `type` field'i Flutter'a rendering kararını verir.

```json
{
  "type": "direct",
  "id": 7,
  "sale_id": 42,
  "item_name": "Kırmızı Çanta",
  "unit_price": 450.0,
  "quantity": 2,
  "final_price": 900.0,
  "seller_username": "host_user",
  "image_url": "/uploads/abc.jpg",
  "proof_image_url": "/uploads/proof.jpg",
  "order_status": "completed",
  "created_at": "2026-08-03T14:22:00Z"
}
```

Auction item'ı aynı formatta — auction'a özgü alanlar `null`:

```json
{
  "type": "auction",
  "id": 99,
  "sale_id": null,
  "item_name": "Deri Cüzdan",
  "unit_price": null,
  "quantity": null,
  "final_price": 350.0,
  "seller_username": "seller_user",
  "image_url": "/uploads/xyz.jpg",
  "proof_image_url": "/uploads/proof2.jpg",
  "order_status": "completed",
  "is_bought_it_now": true,
  "created_at": "2026-07-10T10:00:00Z"
}
```

Badge kuralı: `type == "direct"` → "Direkt Satış" · `type == "auction" && is_bought_it_now` → "Hemen Al" · `type == "auction"` → "Teklif"

### 10.2 Unified Sale Response — `/me/commerce/sales`

Her item bir satış kaydıdır. Direct sale'de satış bazlı özet; auction'da kazanan bazlı kayıt.

```json
{
  "type": "direct",
  "id": 42,
  "item_name": "Kırmızı Çanta",
  "total_revenue": 900.0,
  "total_quantity_sold": 3,
  "order_count": 2,
  "buyer_username": null,
  "image_url": "/uploads/abc.jpg",
  "ended_at": "2026-08-03T14:30:00Z",
  "end_reason": "host_ended",
  "orders_voided": false
}
```

### 10.3 Flutter Modelleri

```dart
enum CommerceType { auction, directSale }

class CommercePurchase {
  final CommerceType type;
  final int id;                   // order_id (direct) | auction_id (auction)
  final int? saleId;              // direct_sale.id; null → auction
  final String itemName;
  final double finalPrice;
  final double? unitPrice;        // null → auction
  final int? quantity;            // null → auction
  final String? sellerUsername;
  final String? imageUrl;
  final String? proofImageUrl;
  final String orderStatus;       // "completed" | "cancelled"
  final bool? isBoughtItNow;      // null → direct
  final DateTime createdAt;
}

class CommerceSale {
  final CommerceType type;
  final int id;
  final String itemName;
  final double totalRevenue;
  final int? totalQuantitySold;   // null → auction
  final int? orderCount;          // null → auction
  final String? buyerUsername;    // null → direct (çoklu alıcı)
  final String? imageUrl;
  final DateTime? endedAt;
  final String? endReason;        // null → auction
  final bool? ordersVoided;       // null → auction
}
```

### 10.4 "Alıcılar" Bottom Sheet

Satışlarım kartındaki "Alıcılar >" satırına basılınca **bottom sheet açılır** — yeni ekrana navigate edilmez.

```
┌────────────────────────────────────┐
│      Alıcılar — Kırmızı Çanta     │
│  ──────────────────────────────── │
│  @ahmet_k        2 adet   900 TL  │
│                        03.08.26   │
│  ──────────────────────────────── │
│  @zeynep_m       1 adet   450 TL  │
│                        03.08.26   │
└────────────────────────────────────┘
```

Endpoint:

```
GET /direct-sales/{id}/orders
```

Sadece `host_id == current_user.id` yetkisi. Response: `buyer_username`, `quantity`, `unit_price`, `total_price`, `created_at`, `status`.

### 10.5 Satışlarım Kart Tasarımı

```
┌────────────────────────────────────┐
│ [Görsel] Kırmızı Çanta   900 TL   │
│          Direkt Satış   03.08.26   │
│          3 adet · 2 alıcı         │
│                    Alıcılar  >    │
└────────────────────────────────────┘
```

`end_reason` badge'i (opsiyonel): "Stok tükendi" / "Sonlandırıldı" / "Yayın kapandı" — küçük chip.

---

## 11. Proof Fotoğrafı

### 11.1 Zamanlama Kararı

> **Karar:** Proof fotoğrafı satış **başlamadan önce** çekilir — auction'daki gibi bittikten sonra değil.

**Gerekçe:**
- Direct sale'de alıcı tekdir — birden fazla order olabilir. Sonradan çekilseydi kime gönderilecekti?
- Satışa başlamadan önce çekilen proof "ürün elimde" sinyali verir — daha güçlü güven.
- Canlı yayın doğasına uygun: host zaten ürünü kameraya tutarak satışa başlar.

### 11.2 Teknik Akış

```
Host form doldurur (title, fiyat, stok)
    ↓
"Başlat" tıklanır
    ↓
_showProofCaptureDialog() açılır (isDismissible: false)
    → "Fotoğraf Çek":
         RenderRepaintBoundary.toImage()   ← canlı video frame screenshot
         PNG bytes → POST /api/upload (multipart, max 10MB)
         MinIO: put_object("{uuid}.png") + thumbnail "{uuid}_thumb.png" (400×400, 85% JPEG)
         nginx: /uploads/{uuid}.png   ← /api prefix YOK
         URL döner
    → "Geç": URL = null (zorunlu değil, akış devam eder)
    ↓
POST /direct-sales/start { ..., proof_image_url: url | null }
direct_sales.proof_image_url kayıt altına alınır
```

### 11.3 Modal — Auction ile Aynı

Auction'daki `_showProofCaptureDialog` modalı birebir yeniden kullanılır:

| Özellik | Değer |
|---|---|
| Tip | `showModalBottomSheet` |
| `isDismissible` | `false` — dışarı tapa kapatılamaz |
| `enableDrag` | `false` — swipe ile kapatılamaz |
| "Fotoğraf Çek" butonu | `captureProofImage` callback → screenshot → upload |
| "Geç" butonu | `Navigator.pop(ctx, '')` — boş string = atlandı |
| Return semantiği | `null` = iptal (akış durur) · `''` = atlandı · `"url"` = çekildi |

Host her iki durumda da ("çek" veya "geç") ilerleyebilir — `isDismissible: false` kazara kapatmayı önler, akışı garantiler.

### 11.4 `captureProofImage` Callback

`host_stream_screen.dart`'taki `_captureProofImageHelper` her iki panele de geçirilir:

```dart
// host_stream_screen.dart — mevcut
Future<String?> _captureProofImageHelper() async {
    final boundary = _videoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary!.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final result = await UploadService.uploadBytes(byteData!.buffer.asUint8List(), 'proof.jpg');
    return result.url;
}
```

**Kod tekrarı notu:** Modal şu an `_AuctionPanelState`'in private method'u. `DirectSalePanel` de kullanacağından Faz 4'te ortak bir yardımcı fonksiyona çıkarılır.

### 11.5 Mimari Karar — Upload Zamanlaması

> **Karar: Anında yükle (upload immediately on capture).**

Üç alternatif değerlendirildi:

| Seçenek | Akış | Sonuç |
|---|---|---|
| **A — Anında yükle** ✅ | Çek → MinIO → URL → POST /start | **Seçildi** |
| B — Cihazda cache, sonra gönder | Çek → byte'lar bellekte → POST /start body'sine ekle | Reddedildi |
| C — Satış bitince yükle | Çek → bellekte tut → sale ended → MinIO | Reddedildi |

**Seçenek A'nın gerekçesi:**

Proof fotoğrafının birincil amacı, satış **boyunca** izleyiciye güven sinyali vermektir (§2.B.1 ürün detay modalı). Satış devam ederken URL sunucuda hazır olmalı. Seçenek C bu amacı tamamen çökertir.

Seçenek B'nin sorunu: stream crash, app arka plana alınma veya bağlantı kesilmesi senaryolarında byte'lar kaybolur. Ayrıca mevcut mimaride `POST /start` payload'una raw image bytes koymak kötü pratik.

**Orphan dosya riski:**

Host fotoğrafı çekip "Başlat"a basmadan vazgeçerse MinIO'da kayıtsız dosya kalır. Bu:
- Kabul edilebilir tradeoff — auction proof'ta da aynı durum geçerli
- Depolama maliyeti ihmal edilebilir (birkaç KB/MB)
- Gelecekte periyodik background cleanup job ile temizlenebilir (Faz 6+ kapsam)

**Akış (kesinleşti):**

```
Fotoğraf çek
  → RenderRepaintBoundary.toImage() → PNG bytes
  → UploadService.uploadBytes() → POST /api/upload → MinIO
  → URL döner → modal'da tutulur
  → Host "Başlat" tıklar
  → POST /direct-sales/start { proof_image_url: url | null }
  → direct_sales.proof_image_url kalıcı olarak kaydedilir
```

MinIO + nginx'in `/uploads/` proxying'i statik dosya için yeterli — ek Redis cache gereksiz.

### 11.6 DB Değişikliği

`direct_sales` tablosuna ek kolon:

```sql
proof_image_url  VARCHAR(500),   -- başlangıç anı video frame screenshot; nullable
```

`POST /direct-sales/start` payload'una eklenir:

```json
{
  "listing_id": 123,
  "title": "Kırmızı Çanta",
  "price": 450.0,
  "stock_quantity": 5,
  "proof_image_url": "/uploads/abc123.png"
}
```

---

## 12. CommercePanelWrapper Kararları

### 12.1 Sorumluluklar

`CommercePanelWrapper`, `host_stream_screen.dart` ve `swipe_live_screen.dart`'ta şu an `AuctionPanel`'in doğrudan çağrıldığı **2 call site'ı** kapsar. Her ikisinde de `AuctionPanel` kaldırılıp `CommercePanelWrapper` yerleştirilir.

### 12.2 İç State (Flutter Lokal)

Backend'e yansımaz — tamamen widget lokal state'i:

```dart
enum _CommerceMode { idle, auction, directSale }
```

| `_CommerceMode` | Host görür | Viewer görür |
|---|---|---|
| `idle` | Mod seçim UI (Açık Artırma / Direkt Satış) | Minimal chip "🛍️ Henüz satış yok" |
| `auction` | `AuctionPanel` | `AuctionPanel` viewer side |
| `directSale` | `DirectSalePanel` | `DirectSalePanel` viewer side |

### 12.3 WS Event Yönlendirme

`CommercePanelWrapper`, stream topic'ini dinler ve event'e göre `_CommerceMode`'u günceller:

| Gelen Event | `_CommerceMode` geçişi |
|---|---|
| `auction_started` | `idle` → `auction` |
| `auction_ended` | `auction` → `idle` |
| `direct_sale_started` | `idle` → `directSale` |
| `direct_sale_ended` | `directSale` → `idle` |
| `direct_sale_cancelled` | `directSale` → `idle` |

### 12.4 `captureProofImage` Callback Zinciri

`host_stream_screen.dart`'taki `_captureProofImageHelper` her iki panel'e wrapper üzerinden iletilir:

```
host_stream_screen
    └── CommercePanelWrapper(captureProofImage: _captureProofImageHelper)
            ├── AuctionPanel(captureProofImage: captureProofImage)      ← iç mantık değişmez
            └── DirectSalePanel(captureProofImage: captureProofImage)   ← yeni, aynı callback
```

### 12.5 AuctionPanel'e Dokunulmaz

`AuctionPanel`'in iç mantığına sıfır değişiklik. Tek fark: artık `host_stream_screen` yerine `CommercePanelWrapper` tarafından mount ediliyor. Dışarıdan bakışı değişir, içi tamamen aynı.

### 12.6 Idle Chip Sahipliği

`idle` chip'i (`🛍️ Henüz satış yok`) `CommercePanelWrapper` render eder — ne `AuctionPanel` ne `DirectSalePanel`. Wrapper, ne auction ne direct sale aktif olmadığında chip'i gösterir.

---

## 13. i18n — ARB Key'leri

Tüm key'ler mevcut convention'a uygun `camelCase`. Parametreli key'lerde `@key` metadata bloğu eklenir.

**Workflow:** ARB → push → `git pull` VPS → `sync_translations.py` (`feedback_translation_workflow.md`)

### 13.1 CommercePanelWrapper

| Key | TR | EN | RU |
|---|---|---|---|
| `commerceSelectTitle` | Satış Türü Seç | Select Sale Type | Выберите тип продажи |
| `commerceSelectAuction` | Açık Artırma | Auction | Аукцион |
| `commerceSelectDirectSale` | Direkt Satış | Direct Sale | Прямая продажа |

### 13.2 Direct Sale — Idle Chip

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleIdleChip` | Henüz satış yok | No active sale | Нет активной продажи |

### 13.3 Direct Sale — Durum Badge'leri

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleStatusActive` | AKTİF | ACTIVE | АКТИВНА |
| `directSaleStatusPaused` | DURAKLADI | PAUSED | ПРИОСТАНОВЛЕНА |
| `directSaleStatusSoldOut` | STOK TÜKENDİ | SOLD OUT | РАСПРОДАНО |
| `directSaleStatusEnded` | BİTTİ | ENDED | ЗАВЕРШЕНА |
| `directSaleStatusCancelled` | İPTAL | CANCELLED | ОТМЕНЕНА |

### 13.4 Direct Sale — Viewer Mesajları

| Key | TR | EN | RU |
|---|---|---|---|
| `directSalePausedLabel` | Satış duraklatıldı | Sale paused | Продажа приостановлена |
| `directSaleSoldOutBanner` | Stok tükendi 🎉 | Sold out 🎉 | Распродано 🎉 |
| `directSaleEndedSoldOut` | Tüm ürünler satıldı! 🎉 | Everything sold out! 🎉 | Всё распродано! 🎉 |
| `directSaleEndedByHost` | Satış sonlandırıldı. | Sale ended. | Продажа завершена. |
| `directSaleEndedStreamClosed` | Yayın sona erdi. | Stream ended. | Трансляция завершена. |
| `directSaleCancelledNeutral` | Satış iptal edildi. | Sale cancelled. | Продажа отменена. |
| `directSaleCancelledOrderKept` | Satış iptal edildi, siparişiniz geçerli. | Sale cancelled, your order is valid. | Продажа отменена, ваш заказ в силе. |
| `directSaleCancelledOrderVoided` | Satış iptal edildi, siparişiniz geçersiz sayıldı. | Sale cancelled, your order has been voided. | Продажа отменена, ваш заказ аннулирован. |

Parametreli key'ler:

```json
"directSaleStockUrgency": "Son {count} adet!",
"@directSaleStockUrgency": {
  "placeholders": { "count": { "type": "int" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleStockUrgency` | Son {count} adet! | Only {count} left! | Осталось {count}! |

### 13.5 Direct Sale — Host Form

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleFormTitle` | Satış Başlat | Start Sale | Начать продажу |
| `directSaleFormProductTitle` | Ürün Adı | Product Name | Название товара |
| `directSaleFormPrice` | Fiyat (₺) | Price (₺) | Цена (₺) |
| `directSaleFormStock` | Stok Adedi | Stock Quantity | Количество |
| `directSaleFormSelectListing` | İlan Seç | Select Listing | Выбрать объявление |
| `directSaleFormManual` | Manuel Giriş | Manual Entry | Ввод вручную |
| `directSaleFormNoListing` | İlan bağlantısı yok | No listing linked | Без объявления |

### 13.6 Direct Sale — Host Kontrol Butonları

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleStartBtn` | ▶ Başlat | ▶ Start | ▶ Начать |
| `directSalePauseBtn` | Duraklat | Pause | Пауза |
| `directSaleResumeBtn` | Devam Et | Resume | Продолжить |
| `directSaleEndBtn` | Bitir | End Sale | Завершить |
| `directSaleCancelBtn` | İptal Et | Cancel Sale | Отменить |

### 13.7 Direct Sale — Host Satış Sırasında

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleStockLabel` | Kalan Stok | Remaining Stock | Остаток |
| `directSaleSoldLabel` | Satıldı | Sold | Продано |
| `directSaleRevenueLabel` | Toplam Gelir | Total Revenue | Общий доход |

### 13.8 Direct Sale — Bitir Dialogu

Parametreli key'ler:

```json
"directSaleEndDialogBody": "Şimdiye kadar {count} sipariş verildi. Bu siparişler geçerli kalacak.",
"@directSaleEndDialogBody": {
  "placeholders": { "count": { "type": "int" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleEndDialogTitle` | Satışı Bitir | End Sale | Завершить продажу |
| `directSaleEndDialogBody` | Şimdiye kadar {count} sipariş verildi. Bu siparişler geçerli kalacak. | {count} orders placed. These orders will remain valid. | Размещено {count} заказов. Они останутся в силе. |
| `directSaleEndDialogBodyNoOrders` | Satışı bitirmek istediğinizden emin misiniz? | Are you sure you want to end the sale? | Вы уверены, что хотите завершить продажу? |

### 13.9 Direct Sale — İptal Dialogu

Parametreli key'ler:

```json
"directSaleCancelDialogBody": "Bu ana kadar {count} sipariş verildi. Mevcut siparişler ne olsun?",
"@directSaleCancelDialogBody": {
  "placeholders": { "count": { "type": "int" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleCancelDialogTitle` | Satışı İptal Et | Cancel Sale | Отменить продажу |
| `directSaleCancelDialogBody` | Bu ana kadar {count} sipariş verildi. Mevcut siparişler ne olsun? | {count} orders placed so far. What should happen to them? | Поступило {count} заказов. Что делать с ними? |
| `directSaleCancelDialogBodyNoOrders` | Satışı iptal etmek istediğinizden emin misiniz? | Are you sure you want to cancel the sale? | Вы уверены, что хотите отменить продажу? |
| `directSaleCancelVoidOrders` | Siparişleri İptal Et | Cancel Orders | Отменить заказы |
| `directSaleCancelKeepOrders` | Siparişleri Geçerli Tut | Keep Orders | Сохранить заказы |

### 13.10 Direct Sale — Satış Özeti (Host)

Parametreli key'ler:

```json
"directSaleSummarySold": "{count} adet satıldı",
"@directSaleSummarySold": {
  "placeholders": { "count": { "type": "int" } }
},
"directSaleSummaryRevenue": "Toplam: {amount}",
"@directSaleSummaryRevenue": {
  "placeholders": { "amount": { "type": "String" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleSummaryTitle` | Satış Tamamlandı | Sale Completed | Продажа завершена |
| `directSaleSummarySold` | {count} adet satıldı | {count} sold | Продано {count} |
| `directSaleSummaryRevenue` | Toplam: {amount} | Total: {amount} | Итого: {amount} |
| `directSaleNewSaleBtn` | Yeni Satış Başlat | Start New Sale | Начать новую продажу |

### 13.11 Direct Sale — Satın Alma Bottom Sheet (Viewer)

Parametreli key'ler:

```json
"directSaleBuySheetPreviousBadge": "✓ {count} adet aldın",
"@directSaleBuySheetPreviousBadge": {
  "placeholders": { "count": { "type": "int" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleBuyBtn` | Hemen Al | Buy Now | Купить |
| `directSaleBuySheetTitle` | Satın Al | Purchase | Купить |
| `directSaleBuySheetQuantity` | Adet | Quantity | Количество |
| `directSaleBuySheetTotal` | Toplam | Total | Итого |
| `directSaleBuySheetPreviousBadge` | ✓ {count} adet aldın | ✓ You bought {count} | ✓ Вы купили {count} |
| `directSaleBuySheetConfirm` | Satın Al | Buy | Купить |

### 13.12 Direct Sale — Proof Fotoğrafı Dialogu

Auction `hostAcceptSaleDialog*` key'leri yeniden kullanılabilir; ancak "başlamadan önce" bağlamı farklı olduğu için ayrı key:

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleProofDialogTitle` | Satışa Başlıyorsunuz | Starting Your Sale | Начало продажи |
| `directSaleProofDialogBody` | Satışa başlamadan önce ürünü kameraya gösterin ve onay fotoğrafını çekin. | Show the product on camera before starting the sale and take a proof photo. | Покажите товар на камеру и сделайте фото перед началом продажи. |

Butonlar auction ile aynı → `hostAcceptSaleBtnCapture` ve `hostAcceptSaleBtnSkip` yeniden kullanılır.

### 13.13 Direct Sale — Hata Mesajları

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleNotActive` | Satış artık aktif değil. | Sale is no longer active. | Продажа больше не активна. |
| `directSaleSoldOutError` | Üzgünüz, stok tükendi. | Sorry, sold out. | К сожалению, товар распродан. |
| `directSaleInsufficientStock` | Yeterli stok yok. | Insufficient stock. | Недостаточно товара. |
| `directSaleAlreadyActive` | Zaten aktif bir satış var. | A sale is already active. | Продажа уже активна. |

### 13.14 Alışverişlerim / Satışlarım — Eklentiler

| Key | TR | EN | RU |
|---|---|---|---|
| `saleTypeDirect` | Direkt Satış | Direct Sale | Прямая продажа |
| `directSaleOrdersTitle` | Alıcılar | Buyers | Покупатели |
| `directSaleOrderCancelled` | İptal edildi | Cancelled | Отменён |

Parametreli key'ler:

```json
"directSaleOrderQuantity": "{count} adet",
"@directSaleOrderQuantity": {
  "placeholders": { "count": { "type": "int" } }
}
```

| Key | TR | EN | RU |
|---|---|---|---|
| `directSaleOrderQuantity` | {count} adet | {count} pcs | {count} шт. |

---

## 14. Commerce Bounded Context — Unified API ve Modeller

### 14.1 Mimari Vizyon

```
Commerce (bounded context)
├── Auction          → teqlif://auction/{id}
├── DirectSale       → teqlif://direct-sale/{id}
└── (gelecek tipler) → teqlif://{type}/{id}
```

Her satış tipi kendi state machine'ine, DB tablosuna ve API router'ına sahip. Ortak nokta: `CommercePurchase` / `CommerceSale` unified modeli ve `/me/commerce/*` endpoint'leri.

### 14.2 Direct Sale Detail Screen (`teqlif://direct-sale/{id}`)

Deep link, `sale_id` ile açılır. Ekran **rol bazlı içerik** gösterir — aynı layout, farklı veri.

**Backend endpoint:**

```
GET /direct-sales/{id}/summary
```

Auth guard: `current_user.id == sale.host_id` (satıcı) VEYA `direct_sale_orders.buyer_id == current_user.id` (alıcı).

**Satıcı (host) görünümü:**

```
┌────────────────────────────────────┐
│ [Proof Görseli]                    │
│ Kırmızı Çanta                      │
│ Direkt Satış · 03.08.2026          │
│ ────────────────────────────────── │
│ Toplam Gelir          900 TL       │
│ Satılan Adet          3            │
│ Alıcı Sayısı          2            │
│ Durum                 Tamamlandı   │
│ ────────────────────────────────── │
│         [ Alıcıları Gör ]          │  → bottom sheet (§10.4)
└────────────────────────────────────┘
```

**Alıcı görünümü:**

```
┌────────────────────────────────────┐
│ [Proof Görseli]                    │
│ Kırmızı Çanta                      │
│ Direkt Satış · 03.08.2026          │
│ ────────────────────────────────── │
│ Satıcı                @host_user   │
│ Adet                  2            │
│ Birim Fiyat           450 TL       │
│ Toplam                900 TL       │
│ Sipariş Durumu        Tamamlandı   │
└────────────────────────────────────┘
```

`order_status == "cancelled"` → "İptal edildi" badge'i, kırmızı.

**Backend response:**

```json
{
  "role": "buyer",
  "sale_id": 42,
  "item_name": "Kırmızı Çanta",
  "proof_image_url": "/uploads/proof.jpg",
  "image_url": "/uploads/abc.jpg",
  "status": "ended",
  "end_reason": "host_ended",
  "ended_at": "2026-08-03T14:30:00Z",
  "seller_username": "host_user",

  "buyer_quantity": 2,
  "buyer_unit_price": 450.0,
  "buyer_total": 900.0,
  "buyer_order_status": "completed",

  "total_revenue": null,
  "total_quantity_sold": null,
  "order_count": null
}
```

`role == "seller"` gelince `total_revenue`, `total_quantity_sold`, `order_count` dolu; `buyer_*` alanları `null`.

### 14.3 Refactor Yol Haritası

Paylaşılan bileşenler hazır olduğunda minimum eforla ayrıştırılabilir:

| Bileşen | Şu an | Refactor hedefi |
|---|---|---|
| `_showProofCaptureDialog` | `_AuctionPanelState` private method | `ProofCaptureSheet` bağımsız widget |
| `/me/purchases` + `/me/sales` | Auction-only endpoint'ler | `/me/commerce/purchases` + `/me/commerce/sales` |
| `PurchaseDetailScreen` | Auction-only | `CommerceDetailScreen(type, id)` — rol + tip bazlı |
| `SaleDetailScreen` | Auction-only | `CommerceDetailScreen` ile birleşir |

**Kural:** Refactor Faz 4 öncesinde yapılmaz — yeni feature'lar önce çalışır hale gelir, sonra temizlenir.

---

## 15. Mimari Tutarlılık Kontrol Listesi

`architectural_decisions.md` kurallarına karşı direct sale planının uyum durumu.

### 15.1 Backend

| Kural | Durum | Not |
|---|---|---|
| Yeni hatalar `AppException` subclass olmalı | ✅ | `DirectSaleNotFoundException`, `DirectSaleNotActiveException`, `DirectSaleSoldOutException`, `DirectSaleInsufficientStockException`, `DirectSaleAlreadyActiveException` — Faz 2'de yazılacak |
| Hata response formatı `{success, error: {code, message}}` | ✅ | AppException handler otomatik karşılar |
| `bump_schema_version()` migration sonunda çağrılmalı | ✅ | Faz 1 migration'ına eklenmez — `direct_sales` ve `direct_sale_orders` tabloları `catalog`/`cities`/`field_config` endpoint'lerini etkilemiyor. ADR §9: bu çağrı yalnızca SCHEMA_VERSIONED cache'i etkileyen migration'larda gerekli. |
| ClickHouse dual-write fire-and-forget | ✅ | §7.2 ve §7.3 — auction pattern ile özdeş |
| `update_user_preference_embedding` kuyruğa alınmalı | ✅ | Satın alma commit sonrası buyer_id için kuyruğa alınır — auction win ile aynı |
| LIFECYCLE cache temizleme | ✅ | Satış bitişinde `direct_sale:{stream_id}:state` ve `stock` silinir |
| Rate limiting | ⚠️ | `POST /purchase` endpoint'ine rate limit eklenmeli (örn: 10/minute per user) — Faz 3'te |

### 15.2 Flutter

| Kural | Durum | Not |
|---|---|---|
| OTA Localization — `loc.t()` / `loc.tOr()` | ✅ | §13 ARB key'leri tanımlı |
| `handleError(e, loc)` — tüm catch blokları | ✅ | Faz 4'te uygulanacak |
| `TeqAsyncButton` — async tetikleyen butonlar | ✅ | "Hemen Al", "Başlat", "Bitir", "İptal" → `TeqAsyncButton` |
| MVVM — `AsyncNotifier` / `Notifier` | ✅ | `DirectSaleViewModel` (host) + `DirectSaleViewerViewModel` (viewer) — Faz 4 |
| `ConsumerStatefulWidget` / `ref.watch(localizationProvider)` | ✅ | Tüm yeni ekranlar |
| `dart analyze` — 0 error, 0 warning | ✅ | Faz 4 çıkışında kontrol |
| 4 dil testi: TR / EN / RU + AR | ✅ | §13'teki key'ler 3 dilde tanımlı (AR Faz 4'te eklenecek) |

### 15.3 ML / ClickHouse

| Kural | Durum | Not |
|---|---|---|
| Veri önce prensibi — model güncellemesi veri birikmeden yapılmaz | ✅ | §8 Faz 6 açıkça "2-4 hafta bekleme" içeriyor |
| ClickHouse ALTER TABLE — yeni tablo açma | ✅ | `direct_sale_events` yeni tablo; gelecekte kolon → ADD COLUMN |
| `user_events` dual-write — ML sinyali | ✅ | §7.2 — auction win ile aynı pattern |
| Eğitim frekansları korunuyor | ✅ | BPR/ALS/K-Means frekansı değişmiyor; `direct_sale_purchase` sinyali ekleniyor |

### 15.4 Açık Kalan Mimari Sorular (Faz Başında Kapatılacak)

| Soru | Faz |
|---|---|
| `purchase_intent` ve `sale_impression` Flutter client'ten mı, yoksa backend'den mi loglanmalı? | Faz 3 |
| `GET /me/commerce/*` EPHEMERAL cache key formatı (`teqlif:cache:ephemeral:user:{id}:commerce:*`) | Faz 2 |
| AR (Arapça) ARB key çevirileri | Faz 4 |
| `DirectSaleViewModel` state class tasarımı (sealed class mı, basit class mı?) | Faz 4 |

---

## Kural Özeti

| Kural | Detay |
|---|---|
| State sayısı | 6: `idle`, `active`, `paused`, `sold_out`, `ended`, `cancelled` |
| Terminal field | `end_reason`: `sold_out` · `host_ended` · `stream_closed` (sadece `ended` için) |
| İptal kararı | `cancelled` + `orders_voided: bool` — host sipariş akıbetini seçer |
| Order status | `direct_sale_orders.status`: `completed` · `cancelled` |
| `starting` | Backend state değil — widget lokal flag |
| Stok yönetimi | Redis Lua atomik — race condition sıfır |
| Cache tipi | LIFECYCLE (auction ile aynı) |
| Tablo yapısı | Auction'dan ayrı: `direct_sales` + `direct_sale_orders` |
| Mesajlaşma | `DirectMessage` model — auction BIN pattern; buyer + host her ikisine WS broadcast |
| Order denorm. | `seller_id` + `listing_id` → `direct_sale_orders`'da snapshot; JOIN'siz mesajlaşma |
| ML feature'ları | `viewer_count_at_start` + `category` → `direct_sales`'de; conversion rate + kategori bazlı analiz |
| Proof fotoğrafı | Satış başlamadan önce — canlı frame screenshot → MinIO; auction modal birebir yeniden kullanılır |
| CommercePanelWrapper | 2 call site (`host_stream_screen`, `swipe_live_screen`); iç state `_CommerceMode {idle, auction, directSale}` |
| AuctionPanel dokunuşu | Sıfır — yalnızca mount eden yer değişiyor |
| i18n | 13 grupta ~60 key; TR/EN/RU; ARB → sync_translations.py workflow'u |
| Commerce bounded context | `/me/commerce/purchases` + `/me/commerce/sales` unified endpoint; `CommercePurchase` / `CommerceSale` Flutter modeli |
| Direct sale detail screen | `teqlif://direct-sale/{id}` → `GET /direct-sales/{id}/summary`; rol bazlı (buyer/seller) tek ekran |
| Refactor hedefi | `ProofCaptureSheet`, `CommerceDetailScreen` — Faz 4 sonrası; önce çalış, sonra temizle |
| ClickHouse | Dual-write: `user_events` (ML) + `direct_sale_events` (huni analizi); 6 event tipi |
| Cache | LIFECYCLE (aktif satış Redis) + EPHEMERAL (60s `/me/commerce/*`, 30s summary); `/orders` cache'lenmez |
| ML pipeline | `purchase_completed` → `user_events` → `user_interests` + `update_user_preference_embedding` kuyruğu |
| Mimari uyum | `architectural_decisions.md` §3/§5/§8/§9 ile tam uyumlu; açık sorular §15.4'te |
| Satışlarım UI | 1 kart/satış; "Alıcılar" → bottom sheet modal (ekran geçişi yok) |
| Alışverişlerim UI | 1 satır/order — auction ile aynı mantık; `sale_type` badge'i ayırt eder |
| Pattern uyumu | Auction state machine ile tutarlı |
