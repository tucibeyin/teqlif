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
