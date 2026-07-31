# Pro Insight Kredi Sayaçları — Mimari ve Algoritmik Analiz

**Tarih:** Temmuz 2026  
**Kapsam:** 5 PRO özelliğin uçtan uca DB · API · ML/AI · ClickHouse · Flutter · UX tutarlılık analizi  
**Bağlantılı:** `findings.md`, `pro_insight_architecture.md`, `architectural_decisions.md`

---

## İçindekiler

1. [Sistem Haritası](#1-sistem-haritası)
2. [Toplu Kitle Bildirimi (blast)](#2-toplu-kitle-bildirimi-blast)
3. [Öne Çıkarılmış İlan (boost)](#3-öne-çıkarılmış-ilan-boost)
4. [Yapay Zeka Danışmanı (ai_price)](#4-yapay-zeka-danışmanı-ai_price)
5. [AI Açıklama Yazarı (ai_desc)](#5-ai-açıklama-yazarı-ai_desc)
6. [Reaktivasyon (reactivation)](#6-reaktivasyon-reactivation)
7. [Ortak Kredi Sistemi Analizi](#7-ortak-kredi-sistemi-analizi)
8. [Cross-Feature Tutarlılık Sorunları](#8-cross-feature-tutarlılık-sorunları)
9. [Clean Architecture Uyumluluk Denetimi](#9-clean-architecture-uyumluluk-denetimi)
10. [Bulgular Özeti](#10-bulgular-özeti)

---

## 1. Sistem Haritası

```
┌─────────────────────────────────────────────────────────────┐
│                     Pro Hub Ekranı                          │
│          (5 kredi sayacı — görüntü + tetikleyici)           │
└──────┬──────────┬──────────┬──────────┬──────────┬──────────┘
       │          │          │          │          │
    blast       boost    ai_price   ai_desc  reactivation
       │          │          │          │          │
 ┌─────▼──┐  ┌───▼────┐  ┌──▼─────┐ ┌──▼─────┐ ┌──▼──────┐
 │leads.py│  │ads.py  │  │analyt. │ │listing.│ │use_case │
 │listing.│  │        │  │.py     │ │.py     │ │toggle   │
 └─────┬──┘  └───┬────┘  └──┬─────┘ └──┬─────┘ └──┬──────┘
       │          │          │           │           │
       └──────────┴──────────┴───────────┴───────────┘
                             │
              credit_service.py (Redis sayaçları)
                    + TuciTransaction (PG)
```

**Kredi veri akışı:**
```
API isteği → limit/bakiye kontrolü → iş mantığı çalışır
→ credit_service.increment() → Redis INCR
→ (ücretliyse) TuciTransaction PG'ye yazılır
→ Pro Hub polling → /blast-credits + /boost-credits + /ai-price-credits + /ai-desc-credits + /reactivation-credits
```

---

## 2. Toplu Kitle Bildirimi (blast)

### 2.1 Flutter UI

**Trigger 1 — Retargeting ekranı:**
- `retargeting_screen.dart:148` → `POST /api/leads/send-blast`
- Kitle: lead segmentleri (kategori/şehir/son aktivite)

**Trigger 2 — İlan Detay ekranı:**
- `listing_detail_screen.dart:1867` → `POST /api/listings/{id}/send-mass-notification`
- Kitle: o ilanı görüntüleyenler + kategori ilgisi olanlar

**Pro Hub sayacı:**
- `pro_hub_screen.dart:90` → `GET /api/leads/blast-credits`
- `defaultPremiumLimit: 6, defaultFreeLimit: 3`

### 2.2 Backend — İki Ayrı Endpoint

#### Endpoint A — Lead Blast (`leads.py:157`)
```
POST /api/leads/send-blast
Limit: credit_service.free_limit("blast") → PRO=6, standart=3/ay
Kitle: ClickHouse user_events → aktif user_id listesi (son 30 gün)
       + PG users → FCM token filtresi
Push: Firebase, 50'lik chunk'lar, asyncio.gather
DB: MassNotificationCampaign + (ücretliyse) TuciTransaction
Sayaç: credit_service.increment("blast", ..., count=free_used)
```

#### Endpoint B — İlan Bildirimi (`listings.py:664`)
```
POST /api/listings/{id}/send-mass-notification
Limit: aynı credit_service "blast" sayacını kullanır
Kitle: _build_listing_audience() →
  1. ClickHouse user_events: o ilanı görüntüleyenler + detay bakan + teklif hesitasyon
  2. PG user_interests: kategori ilgisi olanlar
  Birleşim → FCM token filtresi → LIMIT cap
Push: Firebase, 50'lik chunk'lar, asyncio.gather
DB: MassNotificationCampaign + (ücretliyse) TuciTransaction(type="spend_mass_notification")
Sayaç: credit_service.increment("blast", ..., count=free_used)
```

### 2.3 ClickHouse Kullanımı

**_build_listing_audience()** (listings.py:383):
```sql
-- ClickHouse: o ilanı gerçekten ilgilenen kullanıcılar
SELECT DISTINCT user_id FROM user_events
WHERE item_id = {listing_id} AND item_type = 'listing'
  AND event_type IN ('view', 'detail_dwell', 'bid_hesitation')
  AND timestamp >= now() - INTERVAL 30 DAY
```
**Lead blast** (leads.py): ClickHouse `user_events` + `search_events` sorgusu ile kategori aktifliğine göre kitle.

### 2.4 Tespit Edilen Sorunlar

**F-BLAST-01 (Yüksek) — Tek sayaç, iki tetikleyici, farklı transaction type:**
- Retargeting blast → TuciTransaction'a `transaction_type` belirsiz
- İlan bildirimi → `"spend_mass_notification"`
- İkisi aynı Redis sayacını (`blast_credits`) kullanmasına rağmen transaction history'de ayırt edilemiyor. Raporlama ve denetim kör.

**F-BLAST-02 (Orta) — Pro Hub sayacı yalnızca `/api/leads/blast-credits` dinliyor:**
- İlan detay ekranından gönderilen blastlar da aynı sayacı tüketiyor.
- Pro Hub sayacı doğru düşüyor (shared Redis key), ama API URL ayrımı kavramsal karışıklık yaratıyor.

**F-BLAST-03 (Düşük) — Cooldown yalnızca ilan blast'ta var:**
- İlan blast: `MassNotificationCampaign` son kayıttan 24 saat bekler.
- Lead blast: cooldown kontrolü **yok** — kullanıcı aynı dakikada birden fazla lead blast başlatabilir.

---

## 3. Öne Çıkarılmış İlan (boost)

### 3.1 Flutter UI

**Trigger — İlan Detay:**
- `listing_detail_screen.dart:812` → `_boostListing()` → `GET /api/ads/boost-credits` → dialog → `POST /api/ads/campaigns`
- Ücretsiz/ücretli dallanması client'ta yapılıyor

**Pro Hub sayacı:**
- `pro_hub_screen.dart:91` → `AnalyticsService.getBoostCredits()`
- `defaultPremiumLimit: 5, defaultFreeLimit: 1` ← **YANLIŞ fallback**

### 3.2 Backend (`ads.py`)

```
POST /api/ads/campaigns
→ free_limit kontrolü: PRO=3, standart=0
→ aylık kullanım: credit_service.get_used("boost", ...)
→ ücretsiz hak varsa is_free=True → AdCampaign kaydı
→ ücretliyse: tuci_balance kontrolü → TuciTransaction("spend_boost")
→ credit_service.increment("boost", ...)
→ load_active_campaigns_to_redis() → anlık Redis yükleme
```

### 3.3 Worker

`worker.py:2622` — `sync_ad_campaigns_task` her 10 dakikada çalışır:
- Aktif `AdCampaign` kayıtlarını Redis'e yükler
- CPC tıklama gelince: `ad_service.record_ad_click()` → Redis'te atomik bütçe düşümü
- Bütçe tükenince PG'de `status="completed"`

### 3.4 Boost Sıralaması

Boosted ilanlar "Sana Özel" akışında öne çıkar (pgvector cosine distance hesabına boost çarpanı ekleniyor mu?). Feed sorgusu incelenmeli.

### 3.5 Tespit Edilen Sorunlar

**F-BOOST-01 (Kritik) — Pro Hub fallback limitleri gerçek limitlerle çelişiyor:**
| Alan | Pro Hub (Flutter) | credit_service.py |
|------|------------------|--------------------|
| `defaultPremiumLimit` | **5** | **3** (free_pro) |
| `defaultFreeLimit` | **1** | **0** (free_standard) |

API yanıtı gelene kadar kullanıcı 5/ay kazandığını sanıyor, gerçekte 3/ay. UX beklentisi kırılıyor.

**F-BOOST-02 (Orta) — `is_boosted` DB alanı yok:**
- Boost durumu, aktif `AdCampaign` varlığına bakılarak çıkarılıyor.
- Feed sıralaması, tıklama raporlama, Pro Insight hot_leads — bunların hiçbiri boost durumunu doğrudan okuyamıyor; her seferinde JOIN gerekiyor.

**F-BOOST-03 (Düşük) — `AdCampaign` silme/iptal akışı belirsiz:**
- İlan silindiğinde ya da pasife alındığında `AdCampaign` kaydı ne oluyor? Worker 10 dk'da bir kontrol ediyor ama ara dönemde boosted ilan pasife alınmışsa Redis'te kalan kayıt geçersiz kampanya push'u üretebilir.

---

## 4. Yapay Zeka Danışmanı (ai_price)

### 4.1 Flutter UI

**Trigger — İlan oluşturma / düzenleme:**
- `create_listing_screen.dart:242` → `_fetchAiPriceEstimate()`
- `edit_listing_screen.dart:157` → aynı metot

**Pro Hub sayacı:**
- `pro_hub_screen.dart:92` → `AnalyticsService.getAiPriceCredits()`
- `defaultPremiumLimit: 20, defaultFreeLimit: 0` ← **YANLIŞ fallback** (gerçek: 6/ay)

### 4.2 Backend — Fiyat Tahmin Pipeline (`analytics.py:476`)

```
POST /api/analytics/price-estimate
 1. Limit kontrolü: PRO=6/ay, standart=0
    → aşılmış + TUCi yetersizse 402
 2. title+desc+category → MD5 hash → Redis embedding cache
    → miss: ARQ worker'a generate_embedding_task
    → max 15 sn bekle
 3. NER: ner_service.extract_ner() → marka/model/durum
 4. Döviz kuru: PG exchange_rates → usd_try
 5. pgvector cosine: listings.embedding <=> input_embedding
    → filtreler: kategori, durum, aktivite, fiyat aralığı
    → top 150 → ağırlıklı puanlama → final top 30
 6. IQR outlier temizleme (≥10 nokta varsa)
 7. KDE: scipy.stats.gaussian_kde → bimodal tespiti
 8. Güven seviyesi: low/medium/high
 9. credit_service.increment("ai_price", ...)
    → ücretliyse TuciTransaction("spend_ai")
```

### 4.3 ML Bileşenleri

| Bileşen | Model/Teknoloji | Konum |
|---------|----------------|-------|
| Embedding | sentence-transformers/all-MiniLM-L6-v2 | `ml_service.py:28` |
| Vektör arama | pgvector (<=> cosine) | PostgreSQL |
| NER | `ner_service.extract_ner()` | yerel Python |
| İstatistik | IQR + scipy KDE | `analytics.py:720` |
| Döviz | PG `exchange_rates` | statik tablo |
| ClickHouse | **kullanılmıyor** | — |

### 4.4 Tespit Edilen Sorunlar

**F-AIPRICE-01 (Kritik) — Pro Hub fallback `defaultPremiumLimit: 20` ama gerçek limit 6/ay:**
- Kullanıcı Pro Hub'da kredi doluncaya kadar sayacı 20 bazında okuyor.
- `item.data` gelince güncelleniyor ama ağ yokken 20 gösterir → beklenti yönetimi bozuk.

**F-AIPRICE-02 (Yüksek) — `TuciTransaction` type ayrımı yok:**
- `ai_price` ve `ai_desc` her ikisi de `"spend_ai"` type ile yazılıyor.
- Kullanıcı TUCi geçmişinde hangi özelliği kullandığını göremez.

**F-AIPRICE-03 (Orta) — ARQ worker bekleme timeout: 15 sn:**
- Embedding henüz generate edilmemişse (yeni ilan başlığı) kullanıcı 15 sn'ye kadar bekleyebilir.
- Timeout'ta embedding cache'siz işlem devam ediyor mu, yoksa hata mı fırlatılıyor? UX belirsiz.

**F-AIPRICE-04 (Düşük) — `generate_embedding_task` başarısız olursa kredi tüketiliyor mu?**
- Pipeline uç durum: embedding üretimi başarısız → fiyat tahmini kalitesiz verilere döner → `credit_service.increment()` yine de çağrılıyor mu? Kod sırası bunu risk altında bırakıyor.

---

## 5. AI Açıklama Yazarı (ai_desc)

### 5.1 Flutter UI

**Trigger — İlan oluşturma:**
- `create_listing_screen.dart:295` → `_fetchAiDescription()`
- SSE stream: `POST /api/listings/generate-description`
- Metin token token ekranda akıyor (`StreamedResponse` ile)

**Pro Hub sayacı:**
- `pro_hub_screen.dart:93`
- `defaultPremiumLimit: 6, defaultFreeLimit: 0` ← gerçek limitlerle örtüşüyor ✅

### 5.2 Backend — SSE Pipeline (`listings.py:532`)

```
POST /api/listings/generate-description
 1. Limit kontrolü: PRO=6/ay, standart=0
    → aşılmış + TUCi yetersizse 402
 2. event_generator() async generator başlar
 3. generate_listing_description_stream():
    Primary:  Groq API (llama-3.3-70b-versatile)
              → günlük 14.000 req kotası (Redis sayacı)
    Fallback: Gemini API (gemini-3.1-flash-lite)
              → günlük 1.000 req kotası
    Error:    "__LLM_ERROR__" SSE eventi → Flutter hata gösterir
 4. Her chunk: SSE "data:{text}" + 50 ms yapay gecikme
    Padding: 8192 karakter boşluk header (buffering trick)
 5. Stream tamamen bitti → ardından:
    credit_service.increment("ai_desc", ...)
    → ücretliyse TuciTransaction("spend_ai")
    → SSE: {done:true, tuci_spent:N}
```

### 5.3 LLM Katmanı

| Katman | Model | Günlük Kota | Kota Takibi |
|--------|-------|-------------|-------------|
| Primary | Groq llama-3.3-70b-versatile | 14.000 req/gün | Redis sayacı |
| Fallback | Gemini gemini-3.1-flash-lite | 1.000 req/gün | Redis sayacı |

### 5.4 Tespit Edilen Sorunlar

**F-AIDESC-01 (Kritik) — Kredi stream SONRASINDA tüketiliyor: race condition:**
- Stream başlar → kullanıcı metni alır → **bağlantı koparsa** (tarayıcı kapandı, hata) `increment()` çağrılmaz.
- Kullanıcı ücretsiz metni aldı ama kredi düşmedi → kota aşımı.
- Tersine: `increment()` başarılı ama `done` eventi ulaşmadan client bağlantıyı keserse Flutter "kullanım sayıldı mı?" bilemez.

**F-AIDESC-02 (Yüksek) — `TuciTransaction` type = `"spend_ai"` (ai_price ile çakışıyor):**
- Kullanıcı TUCi harcamasını kaynak özelliğe göre ayırt edemiyor.

**F-AIDESC-03 (Orta) — Groq kota dolunca Gemini'ye geçiş sessiz:**
- LLM fallback mantığı son kullanıcıya yansıtılmıyor.
- Kalite farkı (70b vs flash-lite) kullanıcı için şeffaf değil.

**F-AIDESC-04 (Düşük) — 50ms yapay gecikme ve 8192 char padding:**
- Buffering sorunu için geçici çözüm. HTTP/2 veya Transfer-Encoding: chunked yapılandırması gözden geçirilmeli.

---

## 6. Reaktivasyon (reactivation)

### 6.1 Flutter UI

**Trigger — İlan Detay:**
- `listing_detail_screen.dart:336` → `_toggleActive()`
  1. `GET /api/listings/{id}/reactivation-cost` → maliyet sorgulama
  2. 4 dal: 30 gün içi ücretsiz / PRO ücretsiz kredi / PRO ücretli / standart ücretli
  3. Dialog onayı → `PATCH /api/listings/{id}/toggle`
  4. Başarı → `eventBus.fire(CreditsChangedEvent())` → Pro Hub yenilenir

**Pro Hub sayacı:**
- `pro_hub_screen.dart:94`
- `defaultPremiumLimit: 5, defaultFreeLimit: 0` ← **YANLIŞ fallback** (gerçek: 3/ay)

### 6.2 Backend — Use Case Katmanı

Bu özellik diğer 4'ten farklı olarak Clean Architecture'a kısmi uyum sağlıyor:

```
GET /api/listings/{id}/reactivation-cost
  → GetReactivationCostQuery (use_cases/listings/queries/get_reactivation_cost.py:13)
    → 30 gün penceresi: listing.created_at >= now() - 30d → ücretsiz
    → PRO: credit_service.get_remaining("reactivation") → kalan kredi var mı?
    → Maliyet: 10 TUCi (standart veya limit bitmiş PRO)
    → Döner: {within_window, free_remaining, cost, can_afford}

PATCH /api/listings/{id}/toggle
  → ToggleListingCommand (use_cases/listings/commands/toggle_listing.py:22)
    → Reaktivasyon tespiti (pasif → aktif geçiş)
    → 30 gün penceresi → ücretsiz (sayaç tüketilmez)
    → PRO ücretsiz kredi varsa: credit_service.increment("reactivation")
    → Ücretliyse: TuciTransaction("spend_reactivation") + tuci_balance düşümü
    → listing.status = ACTIVE
    → Pencere dışıysa: listing.created_at = now()  ← feed'e "yeni ilan" olarak geri döner
    → AdCampaign + ListingImpression kayıtları temizlenir
```

### 6.3 Tespit Edilen Sorunlar

**F-REACT-01 (Yüksek) — `created_at = now()` side effect zinciri:**
- Reaktivasyon, `listing.created_at`'i sıfırlıyor.
- Bu tarih şu analizlerde kullanılıyor:
  - `hot_leads`: `_hl_q.where(Listing.created_at >= _sd)` filtresi
  - `price_intel`: `_pi_q.where(Listing.created_at >= _sd)` filtresi
  - İlan yaşı hesabı (`age_h`) heat score'da
- Reaktive edilen eski ilan, ertesi gün Pro Insights'ta "yeni" gibi davranabilir.

**F-REACT-02 (Yüksek) — Pro Hub fallback `defaultPremiumLimit: 5`, gerçek: 3/ay:**
- Yukarıda boost ve ai_price ile aynı sorun.

**F-REACT-03 (Orta) — 30 gün penceresi ile aylık PRO limiti çakışması:**
- PRO kullanıcı, ayda 3 ücretsiz reaktivasyon hakkına sahip.
- Ama 30 gün içindeki reaktivasyonlar bu 3 haktan düşülmüyor.
- Kullanıcı 30 gün içinde 10 kez pasif/aktif yapabilir; hiçbiri kredi tüketmez.
- Bu tasarımsal bir karar olabilir, ama Pro Hub sayacı bu durumu yansıtmıyor (her zaman "3 kalan" gösterir).

**F-REACT-04 (Düşük) — AdCampaign temizleme atomikliği:**
- Reaktivasyon sırasında `AdCampaign` kayıtları siliniyor.
- Worker 10 dakikada bir Redis senkron ediyor — arada aktif görünen bir kampanya olabilir.

---

## 7. Ortak Kredi Sistemi Analizi

### 7.1 credit_service.py — Gerçek Limit Tablosu

| Özellik | Redis Key Prefix | Standart | PRO | TUCi | Dönem |
|---------|-----------------|----------|-----|------|-------|
| blast | `blast_credits` | 3/ay | 6/ay | 10/kişi | premium_since bazlı |
| boost | `boost_credits` | 0 | 3/ay | 50 | premium_since bazlı |
| ai_price | `ai_price_credits` | 0 | 6/ay | 5 | premium_since bazlı |
| ai_desc | `ai_desc_credits` | 0 | 6/ay | 5 | premium_since bazlı |
| reactivation | `reactivation_credits` | 0 | 3/ay | 10 | premium_since bazlı |

### 7.2 Pro Hub Flutter Fallback Mismatch Tablosu

| Özellik | Flutter defaultPremiumLimit | Gerçek PRO Limit | Uyum |
|---------|----------------------------|-----------------|------|
| blast | 6 | 6 | ✅ |
| boost | **5** | **3** | ❌ |
| ai_price | **20** | **6** | ❌ |
| ai_desc | 6 | 6 | ✅ |
| reactivation | **5** | **3** | ❌ |

3 özellikte Flutter'daki hardcoded fallback değerler gerçek limitlerle örtüşmüyor. `item.data` API'den gelene kadar (ağ gecikmesi / hata) kullanıcı yanlış kota görüyor.

### 7.3 billing_period Mekanizması

```python
def billing_period_start(premium_since: datetime) -> date:
    # Kullanıcının abonelik başlangıç gününe göre aylık dönem
    # Örn: premium_since=15 Ekim → her ayın 15'i yeni dönem
    day = premium_since.day
    today = date.today()
    if today.day >= day:
        return date(today.year, today.month, day)
    # Geçen aya dön
    ...
```

**Redis key:** `{prefix}:{user_id}:{period_start}` — dönem değişince eski key erişilemez hale gelir, yeni sayaç sıfırdan başlar.

**Sorun:** Standart kullanıcı (`premium_since=None`) için key: `{prefix}:{user_id}:None` — tüm standart kullanıcılar aynı dönem sınırı altında değil. Blast için standart=3 hakkı var ama dönem takibi `None` key ile yapıldığından **TTL hiç ayarlanmıyor** (kod incelenmeli).

### 7.4 TuciTransaction type tutarsızlıkları

| Özellik | transaction_type | Sorun |
|---------|-----------------|-------|
| blast (leads) | belirsiz / eksik | ❌ Kayıt yok olabilir |
| blast (listing) | `"spend_mass_notification"` | ✅ |
| boost | `"spend_boost"` | ✅ |
| ai_price | `"spend_ai"` | ⚠️ ai_desc ile aynı |
| ai_desc | `"spend_ai"` | ⚠️ ai_price ile aynı |
| reactivation | `"spend_reactivation"` | ✅ |

---

## 8. Cross-Feature Tutarlılık Sorunları

### 8.1 Veri Akışı Tutarsızlıkları

**Reaktivasyon → Funnel/HotLeads çakışması:**
```
Senaryo:
  İlan 45 gün önce yayınlandı → passife alındı → reaktive edildi
  listing.created_at = now() (sıfırlandı)
  Pro Insights "son 30 gün" filtresiyle çalışıyor
  → Bu ilan hot_leads ve funnel'da "yeni" gibi görünür
  → Ama ClickHouse user_events'te eski event'ler var (45 günlük)
  → Funnel views: yüksek (eski eventler)
  → Hot_leads age_h: 0 (yeni created_at)
  → Heat score: yapay yüksek
```

**Boost → Pro Insights price_intel çakışması:**
```
Boost kampanyası aktif ilan → rakip radar'da görünür
  → /competitor-radar pgvector sorgusu bunu filtrelemiyor
  → Satıcı kendi boosted ilanlarının rakip olarak görünmemesi için
    Listing.user_id != current_user.id filtresi var ✅
  → Ama başkasının boosted ilanı rakip listesine giriyor (kasıtlı?)
```

**Blast → ClickHouse event zinciri:**
```
Blast gönderildi → kullanıcı tıkladı → listing_detail açıldı
  → ClickHouse user_events: "view" + "detail_dwell" event'leri yazılır
  → Bir sonraki blast hesaplaması bu eventleri "organik ilgi" sayar
  → Blast sonrası döngüsel bias: blast → event → hedef kitleye girebilir
```

### 8.2 Notification Deduplication

- İlan blast (listings.py): `follows` tablosundan takipçileri çıkarıyor ✅
- Lead blast (leads.py): benzer kontrol var mı? — incelenmeli
- Aynı kullanıcı hem lead segmentinde hem de ilan blast hedef kitlesinde olabilir → aynı gün iki farklı blast alabilir.

---

## 9. Clean Architecture Uyumluluk Denetimi

`architectural_decisions.md` ve Clean Architecture prensiplerine göre değerlendirme:

| Özellik | Use Case | Repository | Error Handling | Uyum |
|---------|----------|------------|---------------|------|
| blast | ❌ leads.py inline | ❌ doğrudan DB | ⚠️ kısmi | Düşük |
| boost | ❌ ads.py inline | ❌ doğrudan DB | ⚠️ kısmi | Düşük |
| ai_price | ❌ analytics.py inline | ❌ doğrudan DB | ✅ iyi | Düşük |
| ai_desc | ❌ listings.py inline | ❌ doğrudan DB | ✅ iyi | Düşük |
| reactivation | ✅ ToggleListingCommand | ✅ kısmi UoW | ✅ iyi | **Yüksek** |

**Reaktivasyon** tek istisna: `GetReactivationCostQuery` ve `ToggleListingCommand` use case katmanında, unit test yazılabilir durumda.

Diğer 4 özellik: iş mantığı (limit kontrolü, kitle seçimi, push gönderme, kredi düşümü) doğrudan router'da. Değişime kapalı, teste kapalı.

---

## 10. Bulgular Özeti

| ID | Özellik | Açıklama | Önem |
|----|---------|----------|------|
| F-BLAST-01 | blast | Aynı sayaç, iki farklı endpoint → transaction type ayrımı yok | Yüksek |
| F-BLAST-02 | blast | Lead blast'ta cooldown yok | Orta |
| F-BOOST-01 | boost | Pro Hub fallback 5, gerçek limit 3 | Kritik |
| F-BOOST-02 | boost | `is_boosted` DB alanı yok, JOIN gerekiyor | Orta |
| F-BOOST-03 | boost | Pasife alınan boosted ilan → Redis'te gecikme | Düşük |
| F-AIPRICE-01 | ai_price | Pro Hub fallback 20, gerçek limit 6 | Kritik |
| F-AIPRICE-02 | ai_price | `spend_ai` type — ai_desc ile çakışıyor | Yüksek |
| F-AIPRICE-03 | ai_price | ARQ timeout UX belirsizliği | Orta |
| F-AIPRICE-04 | ai_price | Embedding başarısız → kredi tüketimi risk | Orta |
| F-AIDESC-01 | ai_desc | SSE sonrası kredi → bağlantı kopunca tüketilmiyor | Kritik |
| F-AIDESC-02 | ai_desc | `spend_ai` type — ai_price ile çakışıyor | Yüksek |
| F-AIDESC-03 | ai_desc | LLM fallback (Groq→Gemini) kullanıcıya şeffaf değil | Orta |
| F-REACT-01 | reactivation | `created_at` sıfırlanması → Insights'ta yapay veri | Yüksek |
| F-REACT-02 | reactivation | Pro Hub fallback 5, gerçek limit 3 | Kritik |
| F-REACT-03 | reactivation | 30 gün penceresi ve aylık limit etkileşimi şeffaf değil | Orta |
| F-CROSS-01 | hepsi | 3 özellikte Pro Hub fallback limitleri gerçekle uyuşmuyor | Kritik |
| F-CROSS-02 | hepsi | ai_price + ai_desc aynı TuciTransaction type → raporlama kör | Yüksek |
| F-CROSS-03 | blast+react | Reaktivasyon → Blast hedef kitlesi → Funnel event döngüsü | Orta |
| F-ARCH-01 | hepsi | 4/5 özellikte iş mantığı router'da (CA ihlali) | Yüksek |

### Acil Düzeltmeler (Kritik)

1. **Pro Hub fallback değerlerini credit_service.py ile senkronize et** — boost:3, ai_price:6, reactivation:3
2. **F-AIDESC-01** — ai_desc'te krediyi stream BAŞLAMADAN düş (ya da idempotent token mekanizması kur)
3. **F-AIPRICE-02 / F-AIDESC-02** — TuciTransaction type'ı `"spend_ai_price"` ve `"spend_ai_desc"` olarak ayır

### Önerilen İyileştirme Sırası

```
1. Kritik (hemen): Pro Hub fallback fix → credit_service enum'u tek kaynak
2. Yüksek (kısa vadeli): TuciTransaction type ayrımı + SSE kredi mekanizması
3. Orta (sprint): blast cooldown + reaktivasyon Insights etkisi belgelenmesi
4. Uzun vadeli: 4 özellik için use case katmanı (reaktivasyon örnek alınarak)
```
