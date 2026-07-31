# Pro Insight — Findings

**Temel:** `pro_insight_architecture.md` + `Architectural Decisions.md` + Clean Architecture  
**Son güncelleme:** Temmuz 2026

---

## Özet Tablo

| ID | Başlık | Önem | Kategori | Durum |
|----|--------|------|----------|-------|
| F-01 | Premium guard eksik — 4 endpoint'ten 3'ünde yok | Kritik | Güvenlik | AÇIK |
| F-02 | `AnalyticsService` hataları tamamen yutuyor | Yüksek | AD §4 İhlali | AÇIK |
| F-03 | `/pro/metrics` endpoint'inde Redis cache yok | Yüksek | Performans | AÇIK |
| F-04 | `/competitor-radar` cache yok + her call pgvector | Yüksek | Performans | AÇIK |
| F-05 | `peak_hours` platform geneli — satıcıya özel değil | Yüksek | Doğruluk | AÇIK |
| F-06 | `hot_leads` sadece 20 ilan analiz ediyor — limit mantıksız | Orta | Doğruluk | AÇIK |
| F-07 | `price_intel` sadece 5 ilan, sıralama yok | Orta | Doğruluk | AÇIK |
| F-08 | `_FunnelCard` UI'da `dwells` adımı gösterilmiyor | Orta | UI Tutarsızlığı | AÇIK |
| F-09 | Tüm iş mantığı router'da — Clean Architecture ihlali | Orta | Mimari | AÇIK |
| F-10 | Flutter'da typed model yok — `Map<String, dynamic>` | Orta | Tip Güvenliği | AÇIK |
| F-11 | `demand-radar`'da f-string ClickHouse injection riski | Orta | Güvenlik | AÇIK |
| F-12 | `hot_leads` heat score'da `detail_dwell` sayılmıyor | Orta | Algoritma | AÇIK |
| F-13 | Tips kural motorunda hard-coded Türkçe fallback | Düşük | AD §1 İhlali | AÇIK |
| F-14 | `search_visibility` kullanıcıya ait görünümleri değil platformu sayıyor | Düşük | Doğruluk | AÇIK |
| F-15 | SWR / Hive cache yok — offline çalışma desteklenmiyor | Düşük | Mimari | AÇIK |
| F-16 | `price_intel` fiyat aralığı filtresi çok geniş (0.05× – 20×) | Düşük | Algoritma | AÇIK |

---

## KRİTİK

---

### F-01 — Premium Guard Eksik [KRİTİK]

**Kategori:** Güvenlik  
**Kaynak:** `backend/app/routers/analytics.py`

**Bulgu:**

| Endpoint | Premium Guard | Satır |
|----------|--------------|-------|
| `/pro-insights` | ❌ Yok | L987 |
| `/pro/metrics` | ❌ Yok | L2252 |
| `/competitor-radar/{id}` | ❌ Yok | L2393 |
| `/demand-radar` | ✅ Var | L2154 |

Herhangi bir oturum açmış kullanıcı (free tier dahil) `/pro-insights` ve `/pro/metrics` endpoint'lerine doğrudan çağrı yapabilir.

**Düzeltme:**
```python
# Her pro endpoint'in başına ekle:
if not current_user.is_premium:
    raise ForbiddenException(code="PRO_REQUIRED")
```

**Etki:** Premium özellik gelir kaybı riski; freemium modeli zafiyeti.

---

## YÜKSEK

---

### F-02 — AnalyticsService Hataları Tamamen Yutuyor [YÜKSEK]

**Kategori:** AD §4 İhlali  
**Kaynak:** `mobile/lib/services/analytics_service.dart:183`

**Bulgu:**
```dart
static Future<Map<String, dynamic>?> getProInsights({...}) async {
  try {
    ...
    if (resp.statusCode == 200) {
      return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
    }
    // 401, 403, 500 → null döner, sessiz
  } catch (_) {}  // ← tüm hatalar yutuldu
  return null;
}
```

`_hasError = results[0] == null` sadece null check — kullanıcı neden hata aldığını bilmiyor. `handleError(e, ref.read(localizationProvider))` veya `TeqToast.error()` çağrılmıyor.

**AD §4 İhlali:** "Her stream/catch mutlaka `handleError(e, ref.read(localizationProvider))` çağırmalı."

**Düzeltme:**
```dart
Future<void> _load() async {
  setState(() { _loading = true; _hasError = false; });
  try {
    final results = await Future.wait([...]);
    if (!mounted) return;
    setState(() {
      _data = results[0];
      _metrics = results[1];
      _loading = false;
      _hasError = results[0] == null;
    });
    if (_hasError) handleError(
      AppException('proLoadFailed'),
      ref.read(localizationProvider),
    );
  } catch (e) {
    if (mounted) handleError(e, ref.read(localizationProvider));
  }
}
```

---

### F-03 — `/pro/metrics` Cache Yok [YÜKSEK]

**Kategori:** Performans  
**Kaynak:** `backend/app/routers/analytics.py:2252`

**Bulgu:** `/pro-insights` endpoint'inde Redis cache var (5 dk). Ama `/pro/metrics`:

- ClickHouse'a `AVG(duration_seconds)` sorgusu
- ClickHouse'a `search_events` sorgusu (kategori bazlı)
- ClickHouse'a CTR/saat sorgusu
- PostgreSQL'e `live_stream_viewers` join sorgusu

Her `ProInsightsScreen` açılışında 4 sorgu çalışır. `Future.wait([getProInsights(), getProMetrics()])` çağrısı paralel gittiğinden gecikme toplam değil — ancak gereksiz yük.

**Düzeltme:**
```python
cache_key = f"cache:pro_metrics:{uid}"
cached = await redis.get(cache_key)
if cached:
    return json.loads(cached)
# ...hesapla...
await redis.setex(cache_key, 600, json.dumps(result))  # 10 dk
```

---

### F-04 — `/competitor-radar` Cache Yok + Her Çağrıda pgvector [YÜKSEK]

**Kategori:** Performans  
**Kaynak:** `backend/app/routers/analytics.py:2393`

**Bulgu:** Her çağrıda pgvector cosine distance ile 20 ilan aranıyor. pgvector taraması embedding boyutuna göre O(n) — büyük veri setlerinde ağır.

**Düzeltme:** İlan bazlı, kısa TTL ile cache:
```python
cache_key = f"cache:competitor_radar:{listing_id}"
# TTL: 30 dk (ilan fiyatları çok sık değişmez)
```

---

### F-05 — `peak_hours` Platform Geneli, Satıcıya Özel Değil [YÜKSEK]

**Kategori:** Doğruluk / Yanıltıcı Veri  
**Kaynak:** `backend/app/routers/analytics.py:1317`

**Bulgu:**
```sql
-- Tüm platform event'leri — kullanıcı filtresi YOK:
SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
FROM user_events
WHERE timestamp >= now() - INTERVAL 30 DAY
  AND event_type IN ('view','detail_dwell','bid_hesitation')
GROUP BY hr ORDER BY cnt DESC LIMIT 5
```

Satıcıya "en yoğun saatler" gösterilirken bu satıcının ilanlarına ait saatler değil, tüm platformun saatleri. Satıcı "19:00'da yayın yap" önerisini alırken bu platform geneli bir öneri.

**Düzeltme:**
```sql
-- Satıcının ilanlarına ait event'leri filtrele:
AND item_id IN ({listing_ids})
-- ve/veya item_type filtresi ekle
```

Eğer platform geneli kasıtlıysa, bölüm başlığı "Platfomun Yoğun Saatleri" olarak değiştirilmeli.

---

## ORTA

---

### F-06 — `hot_leads` 20 İlan Limiti Mantıksız [ORTA]

**Kategori:** Doğruluk  
**Kaynak:** `backend/app/routers/analytics.py:1139`

**Bulgu:**
```python
active_ids_r = await db.execute(_hl_q.limit(20))
```

`ORDER BY` yok. Satıcının 100 aktif ilanı varsa 20 tanesi analiz edilir — hangileri olduğu belirsiz. Yüksek ısı skorlu bir ilan analiz dışında kalabilir.

**Düzeltme:**
```python
# Ya limiti kaldır ya da heat sinyalleri yüksek ilanları önce getir:
_hl_q = _hl_q.order_by(Listing.created_at.desc()).limit(50)
```
Ya da ClickHouse sorgusu ile tüm ilanları analiz edip sadece top 5 dön.

---

### F-07 — `price_intel` 5 İlan + Sıralama Yok [ORTA]

**Kategori:** Doğruluk  
**Kaynak:** `backend/app/routers/analytics.py:1210`

**Bulgu:**
```python
my_listings_r = await db.execute(_pi_q.limit(5))
```

Hangi 5 ilan? `ORDER BY` yok — database sıralaması belirsiz. Fiyatı en yüksek / en düşük / en yeni ilanlar yerine rastgele 5 ilan analiz edilebilir.

**Düzeltme:** Anlamlı sıralama ekle:
```python
_pi_q = _pi_q.order_by(Listing.price.desc())  # ya da created_at
```

---

### F-08 — `_FunnelCard` UI'da `dwells` Adımı Gösterilmiyor [ORTA]

**Kategori:** UI Tutarsızlığı  
**Kaynak:** `mobile/lib/screens/pro_insights_screen.dart:519`

**Bulgu:** Backend artık `dwells` alanını funnel dict'te döndürüyor (T-LB-03 sonrası). Ancak `_FunnelCard` build metodu:
```dart
final views = (funnel['views'] as num?)?.toInt() ?? 0;
final hesitations = ...;
final bids = ...;
final sales = ...;
// dwells HİÇ OKUNMUYOR
```

Huni 4 adımlı gösteriliyor: görüntüleme → tereddüt → teklif → satış. `dwells` (detay sayfasında 30+ saniye) adımı eksik.

**Düzeltme:**
```dart
final dwells = (funnel['dwells'] as num?)?.toInt() ?? 0;
// Funnel'a 5. satır ekle:
_FunnelRow(label: loc.t("proFunnelDwells"), count: dwells, maxVal: maxVal, color: Color(0xFF06B6D4)),
```

ARB'ye `proFunnelDwells` key'i de eklenmeli.

---

### F-09 — Tüm İş Mantığı Router'da — Clean Architecture İhlali [ORTA]

**Kategori:** Mimari  
**Kaynak:** `backend/app/routers/analytics.py:987–1449`

**Bulgu:** `pro_insights()` handler 450+ satır iş mantığı içeriyor:
- Heat score algoritması
- Fiyat sinyal eşiği hesabı
- Öneri kural motoru
- 8 farklı DB/CH sorgusu

Clean Architecture'da:
- **Router:** HTTP → DTO → Use Case → HTTP yanıt
- **Use Case:** iş kuralları
- **Repository:** veri erişimi

**Önerilen yapı:**
```
app/
  use_cases/analytics/
    pro_insights_use_case.py   # iş mantığı
    hot_leads_use_case.py
    price_intel_use_case.py
  repositories/
    analytics_repository.py   # CH + PG soyutlaması
  routers/
    analytics.py               # sadece routing + auth
```

---

### F-10 — Flutter'da Typed Model Yok [ORTA]

**Kategori:** Tip Güvenliği  
**Kaynak:** `mobile/lib/screens/pro_insights_screen.dart:20`

**Bulgu:**
```dart
Map<String, dynamic>? _data;
Map<String, dynamic>? _metrics;
```

Tüm erişimler cast + null-coerce ile:
```dart
final kpis = (_data?['kpis'] as Map<String, dynamic>?) ?? {};
final rev30 = (kpis['revenue_30d'] as num?)?.toDouble() ?? 0;
```

Compile-time güvence yok. API şeması değişirse runtime hatası olur.

**Önerilen:**
```dart
class ProInsightsData {
  final ProKpis kpis;
  final ProFunnel funnel;
  final List<HotLead> hotLeads;
  final List<PriceIntel> priceIntel;
  // ...
  factory ProInsightsData.fromJson(Map<String, dynamic> json) { ... }
}
```

---

### F-11 — `demand-radar`'da ClickHouse f-string Injection Riski [ORTA]

**Kategori:** Güvenlik  
**Kaynak:** `backend/app/routers/analytics.py:2172`

**Bulgu:**
```python
_safe = lambda s: _re.sub(r"[^a-zA-Z0-9çğıöşüÇĞİÖŞÜ\-_]", "", s) if s else ""
cat_safe = _safe(category)
cat_filter = f"AND category = '{cat_safe}'" if cat_safe else ""

q_top = f"""
    SELECT query, COUNT(*) AS cnt
    FROM search_events
    ...
    {cat_filter}        ← doğrudan string interpolasyon
"""
```

Regex yeterince güçlü değil; `\-` ve `_` karakterleri ClickHouse query semantiğini bozmasa da parametreli sorgu kullanmak zorunlu. ClickHouse Python client'ı `%(param)s` syntax'ını destekliyor.

**Düzeltme:**
```python
# f-string interpolasyon yerine parametreli:
ch.query("... WHERE category = %(cat)s ...", parameters={"cat": category or ""})
```

---

### F-12 — Heat Score'da `detail_dwell` Sayılmıyor [ORTA]

**Kategori:** Algoritma  
**Kaynak:** `backend/app/routers/analytics.py:1178`

**Bulgu:**
```python
def _heat(lid: int) -> float:
    raw = (
        view_map.get(lid, 0) * 1 +      # view
        like_map.get(lid, 0) * 2 +      # like
        hes_map.get(lid, 0)  * 3        # bid_hesitation
    )
```

ClickHouse sorgusunda `detail_dwell` event'leri çekilmiyor. Detay sayfasında 30+ saniye geçiren kullanıcı güçlü bir satın alma sinyali — bu sinyal heat score'u etkilemiyor.

**Düzeltme:**
```python
# ClickHouse sorgusuna dwell ekle:
ch_r2 = await ch.query(f"""
    SELECT item_id,
           countIf(event_type = 'view') AS views,
           countIf(event_type = 'detail_dwell') AS dwells,
           countDistinctIf(user_id, event_type = 'bid_hesitation') AS hes,
           toUnixTimestamp(max(timestamp)) AS last_event_ts
    FROM user_events
    WHERE item_type = 'listing' AND item_id IN ({ids_str})
    GROUP BY item_id
""")
dwell_map = {int(r[0]): int(r[2]) for r in ch_r2.result_rows}

# Heat score güncelle:
raw = views*1 + like*2 + dwell*2 + hes*3  # dwell'e orta ağırlık
```

---

## DÜŞÜK

---

### F-13 — Tips Kural Motorunda Hard-Coded Türkçe Fallback [DÜŞÜK]

**Kategori:** AD §1 İhlali  
**Kaynak:** `backend/app/routers/analytics.py:1345`

**Bulgu:**
```python
tips.append({
    "body": t.get(
        "proTipPriceDownBody",
        '"{title}" piyasa ortalamasının %{diff} üzerinde...'  # ← Türkçe hard-coded
    ).format(...)
})
```

ARB key yoksa Türkçe metin gösterilir. İngilizce/Arapça/Rusça kullanıcılara Türkçe öneri gider.

**Düzeltme:** Fallback kaldır — ARB key'i sync_translations.py ile garantile.

---

### F-14 — `search_visibility` Kullanıcıya Ait Değil, Platform Geneli [DÜŞÜK]

**Kategori:** Doğruluk / Yanıltıcı Metrik  
**Kaynak:** `backend/app/routers/analytics.py:2301`

**Bulgu:**
```python
# Satıcının kategorilerindeki TÜM arama olayları sayılıyor:
search_ch = await ch.query(f"""
    SELECT category, count(*) AS search_count
    FROM search_events
    WHERE category IN ({cats_str})
      AND timestamp >= now() - INTERVAL 30 DAY
    GROUP BY category
""")
```

"Arama Görünürlüğü" başlığı yanıltıcı — bu satıcının ilanlarının arama sonuçlarında kaç kez göründüğünü değil, o kategoride kaç arama yapıldığını gösteriyor. Gerçek görünürlük için `search_events`'te ayrı bir `impression_listing_id` alanı gerekirdi.

**Önerim:** Metrik başlığını "Bu Kategorilerde Arama Hacmi" olarak değiştir.

---

### F-15 — SWR / Hive Cache Yok — Offline Çalışma Yok [DÜŞÜK]

**Kategori:** Mimari  
**Kaynak:** `mobile/lib/services/analytics_service.dart:183`

**Bulgu:**
```dart
final resp = await http.get(Uri.parse(url), headers: headers);
if (resp.statusCode == 200) {
  return await compute(jsonDecode, resp.body) ...;
}
// Hive cache yok, SWR yok
```

Ana feed (`/feed/hesitated`) ApiService.get stream pattern kullanıyor ve SWR + Hive cache sağlıyor. Pro Insights ham http.get kullanıyor — uygulama offline açıldığında boş sayfa.

**Önerilen:**
```dart
// ApiService.get stream pattern:
ApiService.get<Map<String, dynamic>>(
  url: ...,
  cacheKey: 'pro_insights',
  cacheTtl: const Duration(minutes: 10),
  fromJson: (raw) => raw as Map<String, dynamic>,
).listen((data) => setState(() => _data = data));
```

---

### F-16 — `price_intel` Fiyat Aralığı Filtresi Çok Geniş [DÜŞÜK]

**Kategori:** Algoritma  
**Kaynak:** `backend/app/routers/analytics.py:1216`

**Bulgu:**
```python
price_lo = float(ml.price) * 0.05
price_hi = float(ml.price) * 20.0
```

100 TL'lik ilan → 5 TL'den 2000 TL'ye kadar ilanlarla karşılaştırılıyor. Bu outlier eleme değil, gürültü ekleme. Standart yaklaşım: `AVG ± 2×STDDEV` veya `0.5× – 2.0×`.

**Düzeltme:**
```python
price_lo = float(ml.price) * 0.4
price_hi = float(ml.price) * 2.5
```

---

## Endüstri Standartlarıyla Karşılaştırma

| Özellik | Mevcut | Endüstri Standardı | Gap |
|---------|--------|-------------------|-----|
| Premium guard | 1/4 endpoint'te | Tüm pro endpoint'lerde | Kritik |
| Veri katmanı soyutlama | Yok (router'da ham SQL) | Repository pattern | Yüksek |
| Flutter typed models | Yok | Freezed/json_serializable | Orta |
| Cache stratejisi | Kısmi (sadece 2 endpoint) | Tüm ağır sorgularda | Orta |
| Offline destek | Yok | SWR + Hive | Orta |
| Error handling | Tüm hatalar yutuldu | Kullanıcıya anlamlı mesaj | Yüksek |
| SQL injection önlemi | Kısmi f-string | Parametreli sorgu | Orta |
| Test edilebilirlik | Sıfır (statik metodlar, DI yok) | Unit + integration test | Yüksek |
| Metrik doğruluğu | Kısmi yanıltıcı (peak_hours, search_visibility) | Satıcıya özel filtre | Orta |
| AI/ML açıklanabilirlik | "Piyasa ortalaması" bağlam yok | Metodoloji göster | Düşük |
