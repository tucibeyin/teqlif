# Teqlif Açık Artırma — Bulgular Raporu

> **Tarih:** 2026-07-28  
> **Kaynak:** Backend servis logları + Flutter client logları + kaynak kod analizi  
> **Olay:** stream_id=2070, host=tesbih (user_id=16), bidder=teqlif (user_id=3)

---

## 1. Olay Özeti

`tesbih` kullanıcısı canlı yayında ilanlı açık artırma başlattı. `teqlif` kullanıcısı yayına girip teklif verdi. 3. tekliften sonra sistem tarafından otomatik mute'landı ve ardından host unmute yapmaya çalışırken "kendinizi susturamazsınız" hatası ile karşılaştı.

---

## 2. Log Kanıtları

### 2.1 Backend Shill Bidding Skor Oluşumu

```
14:36:33 | bid=₺25  | shill_score=40 | HTTP 200 ✅ | WARN, sayaç→1
14:36:35 | bid=-    | -              | HTTP 429 ❌ | BID_RATE_LIMIT (3s dolmadı)
14:36:40 | bid=₺50  | shill_score=55 | HTTP 200 ✅ | WARN, sayaç→2
14:36:44 | bid=₺75  | shill_score=70 | HTTP 403 ❌ | BID_BLOCKED_MUTE ← MUTE
```

### 2.2 IP Eşleşmesi
```
bidder_ip : 176.54.231.186
host_ip   : 176.54.231.186  (auction start'ta Redis'e kaydedildi)
Durum     : Aynı ağdan bağlantı (NAT / ortak Wi-Fi)
```

### 2.3 Skor Dökümü — Adım Adım
```
Teklif 1: IP(+40) + unverified(+0) + age(+0) + prior_0(+0)  = 40 → WARN, counter=1
Teklif 2: IP(+40) + unverified(+0) + age(+0) + prior_1(+15) = 55 → WARN, counter=2
Teklif 3: IP(+40) + unverified(+0) + age(+0) + prior_2(+30) = 70 → MUTE
```

`teqlif` hesabı verified (unverified cezası +0) ve köklü hesap (yaş cezası +0).  
**Tek sebep: aynı IP → 3 teklifte mute eşiğine ulaşıldı.**

---

## 3. Tespit Edilen Hatalar

### Hata 1 — False Positive Mute (KRITIK)
**Verified ve köklü bir hesap, aynı ağdan bağlandığı için 3 meşru teklifle kalıcı mute'landı.**

Kök neden: Shill score sistemi yalnızca IP eşleşmesini tetikleyici olarak kullanıyor. Sonraki her teklifle shill_cnt sayacı artıyor ve eşik aşılıyor. Verified hesap olmasına rağmen skor 3 adımda 70'e ulaşıyor.

Gerçek dünya: Ev, ofis, kafe gibi ortak ağlarda birden fazla kullanıcı aynı NAT IP'sini paylaşır. Bu durum son derece yaygın ve meşrudur.

### Hata 2 — Host Unmute Yapamadı (KRITIK)
**Shill mute'u host client'ına WebSocket event olarak iletilmedi.**

Kök neden:
- `ModerationService.mute()` çağrıldığında → `publish_mod_event()` ile `MUTED` WS eventi yayınlanır → host client'ı `_mutedUsers` setini günceller.
- `AuctionCommands.place_bid()` shill tespitinde → `redis.sadd(mute_key)` yapılır **ama `publish_mod_event()` çağrılmaz.**

Sonuç: Host UI'ında `teqlif` hâlâ "mute değil" görünüyordu. Host moderasyon panelinden yanlış kullanıcıyı hedef aldı veya events zinciri karıştı → `STREAM_MOD_SELF_FORBIDDEN` hatası.

### Hata 3 — Error Log'da user=guest (MINOR)
```
[DomainError] None | code=BID_RATE_LIMIT user=guest
```
429 dönen istekte kimliği doğrulanmış kullanıcı `teqlif` (user_id=3) olmasına rağmen error handler `user=guest` logluyordu. Error handler, authentication context'e erişemiyor.

### Hata 4 — Flutter LIVE_UI_ACTIVE Döngüsü (MINOR)
```
17:36:50 → LIVE_UI_ACTIVE
17:37:05 → FEED_UPDATE → LIVE_UI_ACTIVE (tekrar!)
17:37:17 → LIVE_UI_ACTIVE (tekrar!)
...her ~12-15 saniyede bir
```
Feed poller yayın izleme sırasında durmuyor. Her `getActiveStreams` çağrısında `LIVE_UI_ACTIVE` eventi tetikleniyor. Mute senaryosunda host'un unmute denemesini zorlaştırdı (navigation stack sürekli yeniden inşa ediliyor).

---

## 4. Mimari Kök Nedenler

| # | Sorun | Konum |
|---|---|---|
| M1 | `AuctionCommands` → `from app.routers.moderation import mute_key` | Use Case → Router bağımlılığı (Dependency Rule ihlali) |
| M2 | Fraud detection `place_bid()` içine gömülü | FraudDetectionService ayrılmamış |
| M3 | İki farklı mute kanalı, WS senkronizasyonu eksik | Hata 2'nin mimarisi |
| M4 | Shill mute geri alınamaz, admin override yok | Ürün güvenlik açığı |
| M5 | Shill eşiği 2 sinyalle aşılabiliyor | Verified kullanıcı false positive |

---

## 5. Endüstri Standardı Karşılaştırması

| Platform | Fraud Tespit | Otomatik Aksiyon | İnsan Onayı |
|---|---|---|---|
| **eBay** | ML tabanlı davranış analizi | Review queue | Zorunlu |
| **Amazon** | Geçmiş örüntü + sinyal skoru | Geçici askıya alma | İnsan incelemesi |
| **Bidpath** | Rule engine + ML | Uyarı + throttle | Admin override |
| **Teqlif (mevcut)** | IP + sayaç skoru | Kalıcı mute | ❌ Yok |

---

## 6. Etkilenen Alanlar

- **İzleyiciler:** Verified kullanıcılar aynı ağdan bağlandıklarında false positive mute riski
- **Host'lar:** Shill mute bildirimi alamıyorlar; unmute yapamıyorlar
- **Platform güveni:** Meşru kullanıcı cezalandırıldığında kullanıcı deneyimi zarar görüyor

---

## 7. Mimari Analiz — Ek Bulgular (Clean Architecture + Architectural Decisions)

> Bu bölüm kaynak kod analizi sonucu bulunan ek ihlalleri ve boşlukları belgeler.  
> Kaynak: `auction_commands.py`, `auction_architecture.md`, `worker.py`, `error_handlers.py`

---

### Bulgu F-07 — `stream:{stream_id}:muted` Set TTL Eksik (REDIS)

**Kategori:** Redis Memory Leak · Seviye: Orta

**Durum:** `place_bid()` içinde `redis.sadd(mute_key(stream_id), str(user.id))` çağrısı yapılıyor ama `expire()` hiç çağrılmıyor.

**Etki:** Stream kapandıktan sonra mute set'i Redis'te sonsuza kadar kalır. Stream ID'leri PostgreSQL sequential PK olduğundan yeniden kullanılmıyor — bu key'in yanlış bir stream'e uygulanması riski yok. Ancak uzun vadede (binlerce tamamlanmış artırma) Redis belleği sessizce büyür.

**Karşılaştırma:** `moderation_service.py` → `mute()` metodu TTL set ediyor (`_TTL`). Shill detection kodu bu metodu bypass ederek direkt Redis yazıyor ve TTL'i kaçırıyor.

**Çözüm:** PLAN.md T-01 (`system_mute()`) uygulanınca otomatik çözülür — metot `expire()` çağırıyor.

---

### Bulgu F-08 — İkinci Use Case → Router Bağımlılığı (CLEAN ARCHITECTURE)

**Kategori:** Dependency Rule İhlali · Seviye: Orta

**Durum:** `place_bid()` içinde iki ayrı router import'u var:

```python
# Satır 512 — M1 (PLAN.md'de belgelenmiş)
from app.routers.moderation import mute_key

# Satır 511 — YENİ TESPİT
from app.routers.notifications import push_notification
```

`from app.routers.notifications import push_notification` use case metodunun içinde lazy import olarak gizlenmiş. Architectural Decisions'da Use Case → Router bağımlılığı yasak.

**Çözüm:** `push_notification` ya `services/notification_service.py`'a taşınmalı ya da Use Case katmanından çağrılacak bir abstraction arkasına alınmalı.

---

### Bulgu F-09 — Eksik PostgreSQL İndeksleri (DB PERFORMANS)

**Kategori:** Veritabanı Eksikliği · Seviye: Orta

Kaynak kod analizi ve şema incelemesinde eksik index'ler tespit edildi:

| Tablo | Eksik İndeks | Etkilenen Sorgu |
|---|---|---|
| `bids` | `(bidder_id)` | Kullanıcı teklif geçmişi ekranı — tam tablo taraması |
| `auctions` | `(winner_id)` | Kullanıcı kazanma geçmişi ekranı — tam tablo taraması |
| `purchases` | `(buyer_id, purchase_type)` | Kullanıcı satın alma geçmişi — tam tablo taraması |
| `purchases` | `(auction_id)` | Artırma → satın alma eşleşmesi (accept_bid sonrası doğrulama) |

Mevcut tek dokumentli index: `bids(stream_id, created_at)` — `/bids` endpointini kapsar ama kullanıcı taraflı sorguları kapsamaz.

---

### Bulgu F-10 — ClickHouse Tracking Körlüğü (ANALYTICS/ML)

**Kategori:** Event Tracking Boşluğu · Seviye: Yüksek

Aşağıdaki artırma olayları ClickHouse `user_events` tablosuna hiç yazılmıyor:

| Event | Neden Önemli |
|---|---|
| `bid_fraud_warn` / `bid_fraud_mute` | Trust score'a fraud sinyali beslenemiyor; ML model eğitilemez |
| `bid_blocked_verify` | Telefon doğrulama engel oranı bilinmiyor; UX iyileştirme verisi yok |
| `bid_rate_limited` | Bot aktivitesi ve spam paterni ölçülemiyor |
| `buy_it_now_requested` | BIN talep oranı bilinmiyor |
| `buy_it_now_rejected` / `buy_it_now_accepted` | BIN conversion funnel ölçülemiyor |
| `auction_paused` / `auction_resumed` | Pause süresi ve host davranışı analiz edilemiyor |

Bu boşluklar `compute_trust_scores_task`'ın fraud sinyallerini görmemesine, ML fraud modelinin eğitilememesine ve BIN feature'ının optimize edilememesine yol açıyor.

---

### Bulgu F-11 — İnkrement Tablosu Kategoriden Bağımsız (ÜRÜN/ML)

**Kategori:** Ürün Eksikliği · Seviye: Düşük

Minimum teklif artış kuralı (₺1/₺10/₺25/₺50) tüm kategorilerde ve tüm artırma yapılarında aynı. Bu sabit tablo:
- ₺50 başlangıçlı hızlı artırmada ₺1 increment → çok küçük, artırma çabuk biter
- ₺5.000 başlangıçlı elektronik artırmada ₺50 increment → başlangıç fiyatının %1'i bile değil

Endüstri standardı: başlangıç fiyatının %2–5'i increment (eBay, Sotheby's). Kategori ve katılımcı sayısına duyarlı dinamik increment daha iyi kullanıcı deneyimi sağlar.

**Not:** Bu tasarım kararı mevcut implementasyonu bozmaz. ML destekli geliştirme, veri birikiminden sonra yapılabilir (bkz. auction_architecture.md Bölüm 16.2).

---

## 8. Özet — Tüm Bulgular

| Bulgu | Kategori | Öncelik | Plan'da mı? |
|---|---|---|---|
| F-01 | False Positive Shill Mute | Kritik | ✅ PLAN T-03 |
| F-02 | Host Unmute WS Senkronizasyonu | Kritik | ✅ PLAN T-01 |
| F-03 | Error Log user=guest | Minor | ✅ PLAN T-11 |
| F-04 | Flutter LIVE_UI_ACTIVE Döngüsü | Minor | ✅ PLAN T-13 |
| F-05 (M1) | Use Case → Router import (mute_key) | Mimari | ✅ PLAN T-05 |
| F-05 (M2) | Fraud gömülü place_bid içinde | Mimari | ✅ PLAN T-06 |
| F-05 (M3) | İki mute kanalı WS senkronizasyonsuz | Mimari | ✅ PLAN T-01 |
| F-05 (M4) | Shill mute geri alınamaz | Güvenlik | ✅ PLAN T-04 |
| F-06 | Verified kullanıcı skor simülasyonu | Analiz | ✅ PLAN Bölüm 2 |
| F-07 | muted set TTL eksik | Redis | ⚠️ PLAN T-15 (yeni) |
| F-08 | push_notification router import | Clean Arch | ⚠️ PLAN T-18 (yeni) |
| F-09 | Eksik DB index (bids/auctions/purchases) | DB | ⚠️ PLAN T-16 (yeni) |
| F-10 | ClickHouse tracking boşlukları | Analytics/ML | ⚠️ PLAN T-07 (genişletilecek) |
| F-11 | Sabit increment tablosu | Ürün/ML | ⚠️ İleride (veri birikimi gerekli) |
