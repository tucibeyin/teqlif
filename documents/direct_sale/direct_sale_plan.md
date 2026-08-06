# Direkt Satış (Direct Sale) Geliştirme Planı

> **Mimari Şerh:** Bu plandaki ve geliştirilecek olan tüm kodlar `documents/architectural_decisions.md` dosyasına uyumlu olmak zorundadır.

> **Görev Takibi:** Geliştirme sürecindeki tüm adımlar ve tasklar `documents/direct_sale/direct_sale_task.md` dosyasında bulunmaktadır.

> **Referans Ekran:** `create_listing_screen.dart` — pattern kararları için pilot ekran.

---

## İçindekiler

1. [State Machine (Durum Makinesi)](#1-state-machine)
2. [WS Event Sözleşmesi](#2-ws-event-sözleşmesi)
3. [API Endpoint Listesi](#3-api-endpoint-listesi)
4. [Veritabanı Şeması](#4-veritabanı-şeması)
5. [Redis Key Şeması](#5-redis-key-şeması)
6. [ClickHouse Tracking](#6-clickhouse-tracking)
7. [Geliştirme Fazları](#7-geliştirme-fazları)

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

## 2. WS Event Sözleşmesi

*Bu bölüm Faz 0 tamamlandığında doldurulacak.*

Tanımlanacak event'ler:
- `direct_sale_started` — `active` geçişi; ürün bilgileri, fiyat, stok
- `direct_sale_paused` — `paused` geçişi
- `direct_sale_resumed` — `active` geri dönüşü
- `direct_sale_purchased` — bir satın alma gerçekleşti; kalan stok, alıcı adı
- `direct_sale_sold_out` — `sold_out` geçişi
- `direct_sale_ended` — `ended` geçişi; `end_reason`

---

## 3. API Endpoint Listesi

*Bu bölüm Faz 0 tamamlandığında doldurulacak.*

Planlanan endpoint'ler:
- `POST /direct-sales/start` — yeni satış başlat
- `GET /direct-sales/{stream_id}/state` — güncel state sorgula
- `POST /direct-sales/{id}/pause` — duraklat
- `POST /direct-sales/{id}/resume` — devam et
- `POST /direct-sales/{id}/end` — sonlandır
- `POST /direct-sales/{id}/purchase` — satın al (viewer)

---

## 4. Veritabanı Şeması

*Bu bölüm Faz 0 tamamlandığında doldurulacak.*

Planlanan tablolar:
- `direct_sales` — satış kaydı (stream_id, status, end_reason, price, total_stock, remaining_stock, ...)
- `direct_sale_orders` — her satın alma kaydı (sale_id, buyer_id, quantity, created_at, ...)

**Karar:** Auction tablosundan ayrı tablo. İki sistemin kolonları örtüşmüyor (bid tracking vs. stock management).

---

## 5. Redis Key Şeması

*Bu bölüm Faz 0 tamamlandığında doldurulacak.*

Planlanan key'ler:
- `direct_sale:{stream_id}:state` — mevcut state hash
- `direct_sale:{stream_id}:stock` — kalan stok (integer, Lua atomik)

**Karar:** Stok azaltma Lua script ile atomik yapılacak — aynı açık artırma teklif pattern'i. Race condition yok.

**Cache Taksonomisi:** LIFECYCLE (architectural_decisions.md §9 — stream/auction gibi, olayın bitişiyle temizlenir).

---

## 6. ClickHouse Tracking

*Bu bölüm Faz 0 tamamlandığında doldurulacak.*

Planlanan event'ler:
- `sale_started` — host satış başlattı
- `sale_impression` — viewer paneli gördü
- `purchase_intent` — "Satın Al" butonuna bastı
- `purchase_completed` — satın alma tamamlandı
- `sale_ended` — satış bitti (`end_reason` ile)

---

## 7. Geliştirme Fazları

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
