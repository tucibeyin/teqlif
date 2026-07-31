# Geri Bak Feed — Findings (Nihai)

**Temel:** `look_back_architecture.md` + `Architectural Decisions.md` çapraz denetimi  
**Son güncelleme:** Temmuz 2026

---

## Özet Tablo

| ID | Başlık | Önem | Durum |
|----|--------|------|-------|
| F-11 | hes_spike semantik hatası — detail_dwell satıcıya "teklif" sinyali sayılıyor | Yüksek | AÇIK |
| F-12 | argMax top_signal override — bid_hesitation'ın üstüne detail_dwell yazılıyor | Yüksek | AÇIK |
| F-13 | _loadHesitated stream onError yok — Architectural Decision §4 ihlali | Orta | AÇIK |
| F-08 | price_point anlamsal çakışması — aynı sütun iki farklı anlam taşıyor | Orta | AÇIK |
| F-09 | hesitated_shelf_tap Thompson Sampling'e dahil değil | Orta | AÇIK |
| F-14 | /hesitated endpoint ClickHouse hatasını sessizce [] dönerek yutuyor | Orta | AÇIK |
| F-15 | subcategory PG user_interactions'a yazılmıyor | Düşük | AÇIK |
| F-16 | hesitation_retarget_task penceresi (7 gün) feed penceresiyle (14 gün) çelişiyor | Düşük | AÇIK |
| F-07 | not_interested TTL tutarsızlığı (7 gün vs 14 gün) | Düşük | AÇIK |
| F-10 | Dismiss ScaffoldMessenger — Architectural Decision §2.7 ihlali | Çok Düşük | AÇIK |
| F-01 | hesitated:{uid} set'i orphan durumda | Orta | DÜZELTILDI (Kısmi) |
| F-02 | detail_dwell hesitated set'ine yazılmıyordu | Yüksek | DÜZELTILDI |
| F-03 | subcategory ClickHouse'a yazılmıyordu | Yüksek | DÜZELTILDI |
| F-04 | Pro Insights'ta 'dwell' event adı hatalıydı | Orta | DÜZELTILDI |
| F-05 | /hesitated endpoint'inde cache yoktu | Orta | DÜZELTILDI |
| F-06 | FAISS IndexIVFFlat eşiği yanlıştı | Kritik | DÜZELTILDI |

---

## AÇIK Bulgular

---

### F-11 — hes_spike Semantik Hatası [YÜKSEK]

**Kategori:** Doğruluk Hatası  
**Kaynak:** `analytics.py:L157–180`

**Bulgu:** `analytics.py`'deki spike dedektörü `bid_hesitation` **ve** `detail_dwell` için aynı sayacı artırır:

```python
# analytics.py L157-158
if payload.interaction_type in ("bid_hesitation", "detail_dwell"):
    ...
    spike_key = f"hes_spike:{payload.item_id}"
    spike_count = await redis.incr(spike_key)
```

Satıcıya gönderilen bildirim mesajı ise:

```python
# worker.py L2872
body=f'"{title}" için bugün {hesitation_count} kişi teklif vermek üzereydi.'
```

**Sorun:** 3 farklı kullanıcı bir ilanı 30+ saniye incelese (3× `detail_dwell`), satıcıya "3 kişi teklif vermek üzereydi" bildirimi gider. Ancak bu kullanıcılar teklif alanına hiç dokunmamış olabilir — "teklif vermek üzereydi" ifadesi doğrudan `bid_hesitation`'ı kastetmektedir.

**Etki:** Satıcı gerçek teklif ilgisini göremez; yanlış fiyatlama kararı verebilir. Güven erozyonu riski.

---

### F-12 — argMax top_signal Override: bid_hesitation Üstüne detail_dwell Yazılabiliyor [YÜKSEK]

**Kategori:** Algoritma Tasarım Hatası  
**Kaynak:** `feed.py:L218–234`, `look_back_architecture.md §5`

**Bulgu:** ClickHouse sorgusu `argMax(event_type, timestamp)` ile `top_signal` hesaplıyor — bu, grup içindeki **en son** zaman damgasındaki event_type'ı seçer.

**Senaryo:**
1. Kullanıcı ilana teklif girdi (T=1) → `bid_hesitation` (güçlü intent)
2. İki gün sonra aynı ilana tekrar göz attı (T=2) → `detail_dwell` (daha zayıf sinyal)
3. `argMax` → `top_signal = 'detail_dwell'` (en son)
4. ORDER BY: `multiIf(top_signal = 'bid_hesitation', 0, 1)` → bu ilan **1 grubuna** düşer
5. Sonuç: Gerçek teklif niyeti olan bir ilan, `bid_hesitation` olmayan ilanlarla aynı öncelikte görünür.

**Kök Neden:** Sıralama "en güçlü sinyal önce" mantığıyla değil "en son sinyal önce" mantığıyla kurulmuş.

**Doğru Yaklaşım:**
```sql
-- MEVCUT (kırılgan):
argMax(event_type, timestamp) AS top_signal

-- ÖNERİLEN (intent-aware):
countIf(event_type = 'bid_hesitation') > 0 AS has_bid_hesitation
-- ORDER BY:
ORDER BY has_bid_hesitation DESC, last_seen DESC
```

---

### F-13 — _loadHesitated Stream onError Yok [ORTA]

**Kategori:** Architectural Decision §4 İhlali  
**Kaynak:** `home_screen.dart:L123–133`, `Architectural Decisions.md §4`

**Bulgu:**

```dart
// home_screen.dart L123-132
void _loadHesitated({bool bypassCache = false}) {
  ApiService.get<List<dynamic>>(
    url: '$kBaseUrl/feed/hesitated',
    ...
  ).listen((data) {              // ← onError yok
    if (mounted) setState(() => _hesitatedListings = data);
  });
}
```

`ApiService.get` Hive cache yokken exception fırlatır. `.listen()` `onError` almadığında Dart bu hatayı mevcut Zone'a yönlendirir — Flutter'da genellikle sessizce log'a düşer. Kullanıcı boş shelf görür, neden boş olduğunu bilemez.

**AD §4 kuralı:** "Her catch bloğu `handleError(e, ref.read(localizationProvider))` çağırmalı."

**Doğru Pattern:**

```dart
ApiService.get<List<dynamic>>(...).listen(
  (data) {
    if (mounted) setState(() => _hesitatedListings = data);
  },
  onError: (e) {
    if (mounted) handleError(e, ref.read(localizationProvider));
  },
);
```

---

### F-08 — price_point Anlamsal Çakışması [ORTA]

**Kategori:** Veri Modeli Tasarım Riski  
**Kaynak:** `look_back_architecture.md §3.1/§3.2`, `feed.py:L309–321`

**Bulgu:** `user_events.price_point` sütunu iki farklı anlam taşıyor:

| Sinyal | price_point anlamı |
|--------|-------------------|
| `detail_dwell` | İlanın o andaki **liste fiyatı** |
| `bid_hesitation` | Kullanıcının yazdığı **teklif tutarı** |

Aynı sütun, farklı katmanların birbirinden bağımsız okuyup farklı yorumlaması gereken iki değer barındırıyor. Bu ClickHouse şemasında kodlanmamış.

**Risk Senaryosu:** Bir ilan için `bid_hesitation` (T=1, user teklifi=80.000₺) ve `detail_dwell` (T=2, liste fiyatı=90.000₺) varsa:
- `argMax(price_point, timestamp)` → `90.000` (en son)
- `top_signal = 'detail_dwell'` (F-12 ile aynı kırılganlık)
- `price_near_offer` guard'ı `signal == 'bid_hesitation'` kontrolü yaptığı için bu spesifik durumda hesap yapılmaz — **ancak mantık F-12 düzeltilirse kırılabilir**.

---

### F-09 — hesitated_shelf_tap Thompson Sampling'e Dahil Değil [ORTA]

**Kategori:** Veri Eksikliği  
**Kaynak:** `worker.py:L515–521`, `home_screen.dart:L497–501`

**Bulgu:** Shelf tap sinyali ClickHouse'a yazılıyor ancak Thompson Sampling event listesinde tanımsız:

```python
# worker.py — Thompson Sampling event listesi (L517)
r["interaction_type"] in (
    "listing_offer_submit", "listing_chat_open", "listing_favorite",
    "listing_share", "listing_like", "detail_dwell",
    "listing_view", "listing_impression", "listing_skip",
    "listing_unfavorite",
    # "hesitated_shelf_tap" ← EKSIK
)
```

**Etki:** Kullanıcı "Geri Bak" shelf'inde bir ilana tıklayıp tekrar ilgilendiğini gösterse de bu sinyal kategorisi `preference_embedding` hesaplamasına ve Thompson Sampling Beta parametrelerine yansımaz.

`hesitated_shelf_tap`, `detail_dwell`'den daha güçlü bir yeniden-ilgi sinyalidir çünkü kullanıcı aktif bir eylem yapmaktadır.

---

### F-14 — /hesitated Endpoint ClickHouse Hatasını Sessizce Yutuyor [ORTA]

**Kategori:** Architectural Decision §4 İhlali  
**Kaynak:** `feed.py:L239–240`

**Bulgu:**

```python
# feed.py L239-240
    except Exception:
        return []
```

ClickHouse client hatası, bağlantı zaman aşımı veya sorgu hatası — hepsi sessizce `[]` döndürüyor. Backend log kaydı yok, client'a hata sinyali gönderilmiyor.

**AD kuralı (§4):** "Kural: Yeni backend hataları için her zaman `AppException` subclass kullan, düz `HTTPException` yazma." Ama burada hata tamamen yutulup boş liste dönüyor — bu `HTTPException`'dan da kötü.

**Etki:** SWR mitigas edebilir (cache varsa). Ancak:
1. İlk yükleme: cache yok → ClickHouse kapalı → kullanıcı neden shelf boş bilemiyor.
2. Monitoring: ClickHouse'un kapalı olduğunu tespit etmek için log incelenmesi gerekiyor.

**Öneri:** En azından `logger.warning(...)` ekle; ClickHouse bağlanamama durumunda hata loglanmalı.

---

### F-15 — subcategory PostgreSQL user_interactions'a Yazılmıyor [DÜŞÜK]

**Kategori:** Veri Katmanı Eksikliği  
**Kaynak:** `worker.py:L429–438`

**Bulgu:** `flush_interactions_to_db`'deki `pg_rows` dict'i `subcategory` içermiyor:

```python
pg_rows.append({
    "user_id": r["user_id"],
    "item_id": r["item_id"],
    "item_type": r["item_type"],
    "interaction_type": r["interaction_type"],
    "duration_seconds": r["duration_seconds"],
    "created_at": r["created_at"],
    # "subcategory" ← YOK
})
```

ClickHouse'a yazılıyor; PostgreSQL'e yazılmıyor. `UserInteraction` modelinde `subcategory` kolonu olsa bile boş geçilecek.

**Etki:** Şu an tüm subcategory bazlı analizler ClickHouse'dan okunuyor, PG'den değil — doğrudan sorun yok. Ancak PG'ye dayanan ML pipeline'ları veya admin sorgular subcategory'ye erişemez.

---

### F-16 — hesitation_retarget_task Penceresi Feed Penceresiyle Çelişiyor [DÜŞÜK]

**Kategori:** Tasarım Tutarsızlığı  
**Kaynak:** `worker.py:L2908`, `feed.py:L229`

**Bulgu:**

| Bileşen | Pencere | Kaynak |
|---------|---------|--------|
| `/feed/hesitated` endpoint | 14 gün | `INTERVAL 14 DAY` |
| `hesitation_retarget_task` | 7 gün | `INTERVAL 7 DAY` |

Kullanıcı bir ilana 10 gün önce teklif niyetiyle baktı → feed'de görünür → fiyat %8 düştü → retarget task onu **bulamıyor** (7 gün dışında).

**Etki:** 7–14 gün arasındaki hesitation verisine push bildirimi gönderilmiyor. Kullanıcı fırsatı kaçırıyor, satıcı potansiyel alıcıya ulaşamıyor.

---

### F-07 — not_interested TTL Tutarsızlığı [DÜŞÜK]

**Kategori:** Tasarım Tutarsızlığı  
**Kaynak:** `feed.py:L95`, `feed.py:L79`

**Bulgu:** `not_interested:{uid}` set'i iki farklı endpoint tarafından farklı TTL ile güncelleniyor:

| Endpoint | TTL |
|----------|-----|
| `POST /not-interested/{id}` | **7 gün** |
| `DELETE /hesitated/{id}` (dismiss) | **14 gün** |

Dismiss işlemi genel "ilgilenmiyorum" aksiyonundan iki kat daha uzun koruyor. Tutarlı bir politika yok; yeni TTL her EXPIRE çağrısıyla yazılan değeri alıyor (son EXPIRE kazanır).

---

### F-10 — Dismiss ScaffoldMessenger Kullanıyor [ÇOK DÜŞÜK]

**Kategori:** Architectural Decision §2.7 İhlali  
**Kaynak:** `home_screen.dart:L520–527`

**Bulgu:**

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text(loc.t('hesitatedDismissed'))),
);
```

AD §2.7: "TeqSnackBar doğrudan TeqToast'a delege eder. `TeqToast.success()` veya `TeqSnackBar.show()` kullan."

Context'e bağımlı native SnackBar kullanımı, projenin merkezi toast altyapısını bypass eder.

---

## DÜZELTİLDİ Bulgular

---

### F-01 — hesitated:{uid} Orphan Set [DÜZELTİLDİ — Kısmi]

**Durum:** Temmuz 2026'da kısmen ele alındı.  
`feed.py` artık bu set'i okumak yerine doğrudan ClickHouse'u sorgular. Set `hes_spike` sayaç mekanizması için tutulmaktadır.

---

### F-02 — detail_dwell hesitated Set'ine Yazılmıyordu [DÜZELTİLDİ]

**Commit:** `75fcf5d8`  
`analytics.py`'de yalnızca `bid_hesitation` `hesitated:{uid}` set'ine yazılıyordu. Her iki sinyal de dahil edildi, TTL 7→14 gün uzatıldı.

---

### F-03 — subcategory ClickHouse'a Yazılmıyordu [DÜZELTİLDİ]

**Commit:** `75fcf5d8`  
`analytics.py` record dict'i ve `worker.py` ClickHouse insert pipeline'ı güncellendi. `subcategory` artık `user_events`'e yazılıyor.

---

### F-04 — Pro Insights'ta 'dwell' Event Adı Hatalıydı [DÜZELTİLDİ]

**Commit:** `75fcf5d8` + T-LB-03 fix  
- `analytics.py`'deki 3 sorguda `'dwell'` → `'detail_dwell'` düzeltildi (etkilenen: `dwells`, `avg_detail_dwell_seconds`, peak hours)
- Ek fix: funnel sorgusunda `r[1]` (dwells) Python'da extract edilmiyordu; `dwells_total` değişkeni ve `"dwells"` funnel dict key'i eklendi
- Not: `avg_detail_dwell_seconds` `/pro-insights`'ta değil, ayrı `/pro/metrics` endpoint'indedir

---

### F-05 — /hesitated Endpoint'inde Cache Yoktu [DÜZELTİLDİ]

**Commit:** `75fcf5d8`  
`feed:hesitated:{uid}` Redis cache eklendi (TTL 15 dk). Dismiss endpoint cache'i invalide ediyor.

---

### F-06 — FAISS IndexIVFFlat Küçük Veri Setlerinde Yanlış Sonuç Veriyordu [DÜZELTİLDİ]

**Commit:** `c6172812`  
IVFFlat eşiği `n < _NLIST` (100) → `n < _NLIST * 39` (3900) olarak düzeltildi. 3900'den az ilanda artık tam arama yapan `IndexFlatIP` kullanılıyor.
