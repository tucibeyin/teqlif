# Pro Insight — Task Listesi

**Son güncelleme:** 31 Temmuz 2026  
**Bağlantılı:** `findings.md`, `pro_insight_architecture.md`

---

## Özet Tablo

| ID | Başlık | Kaynak | Öncelik | Durum | Tarih |
|----|--------|--------|---------|-------|-------|
| T-PI-01 | Premium guard — 3 endpoint'e ekle | F-01 | Kritik | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-02 | AnalyticsService error handling — hatalar kullanıcıya iletilsin | F-02 | Yüksek | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-03 | `/pro/metrics` Redis cache ekle | F-03 | Yüksek | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-04 | `/competitor-radar` Redis cache ekle | F-04 | Yüksek | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-05 | `peak_hours` satıcıya özel filtre ekle | F-05 | Yüksek | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-06 | `hot_leads` ilan limitini genişlet + sıralama ekle | F-06 | Orta | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-07 | `price_intel` ilan limitini artır + sıralama ekle | F-07 | Orta | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-08 | `_FunnelCard` UI'a `dwells` adımını ekle | F-08 | Orta | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-09 | demand-radar ClickHouse f-string → parametreli sorgu | F-11 | Orta | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-10 | Heat score'a `detail_dwell` ağırlığı ekle | F-12 | Orta | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-11 | Tips hard-coded Türkçe fallback'leri kaldır | F-13 | Düşük | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-12 | `search_visibility` metrik başlığını düzelt | F-14 | Düşük | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-13 | `price_intel` fiyat aralığı filtresini daralt | F-16 | Düşük | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-14 | Flutter typed model'lar oluştur | F-10 | Araştırma | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-15 | SWR / Hive cache — offline destek | F-15 | Araştırma | ✅ Tamamlandı | 31 Tem 2026 |
| T-PI-16 | Clean Architecture refactor — Use Case katmanı | F-09 | Araştırma | ✅ Tamamlandı | 31 Tem 2026 |

---

## Kritik

---

### T-PI-01 — Premium Guard 3 Endpoint'e Ekle ✅ Tamamlandı

**Kaynak:** F-01  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py)

3 endpoint'in başına `is_premium` kontrolü eklenmeli:

```python
# /pro-insights — L987 handler başına:
@router.get("/pro-insights")
async def pro_insights(...):
    if not current_user.is_premium:
        raise ForbiddenException(code="PRO_REQUIRED")
    ...

# /pro/metrics — L2252 handler başına:
@router.get("/pro/metrics")
async def get_pro_metrics(...):
    if not current_user.is_premium:
        raise ForbiddenException(code="PRO_REQUIRED")
    ...

# /competitor-radar/{listing_id} — L2393 handler başına (listing sahiplik kontrolünden ÖNCE):
@router.get("/competitor-radar/{listing_id}")
async def competitor_radar(...):
    if not current_user.is_premium:
        raise ForbiddenException(code="PRO_REQUIRED")
    ...
```

**Doğrulama:** Free kullanıcı ile her 3 endpoint'i çağır → 403 + `PRO_REQUIRED` bekleniyor.

---

## Yüksek Öncelik

---

### T-PI-02 — AnalyticsService Error Handling

**Kaynak:** F-02  
**Dosya:** [mobile/lib/services/analytics_service.dart](../../../mobile/lib/services/analytics_service.dart#L183)  
**Dosya:** [mobile/lib/screens/pro_insights_screen.dart](../../../mobile/lib/screens/pro_insights_screen.dart#L68)

**analytics_service.dart — getProInsights:**
```dart
// MEVCUT:
static Future<Map<String, dynamic>?> getProInsights({...}) async {
  try {
    ...
    if (resp.statusCode == 200) { return ...; }
  } catch (_) {}
  return null;
}

// ÖNERİLEN — hata fırlat, yutma:
static Future<Map<String, dynamic>> getProInsights({...}) async {
  final token = await StorageService.getToken();
  if (token == null) throw AppException('unauthorized');
  final headers = await buildApiHeaders(token);
  var url = '$kBaseUrl/analytics/pro-insights';
  if (startDate != null || endDate != null) {
    final params = [if (startDate != null) 'start_date=$startDate', if (endDate != null) 'end_date=$endDate'];
    url += '?${params.join('&')}';
  }
  final resp = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
  if (resp.statusCode == 200) {
    return await compute(jsonDecode, resp.body) as Map<String, dynamic>;
  }
  throw AppException('proLoadFailed');
}
```

**pro_insights_screen.dart — _load:**
```dart
// MEVCUT:
final results = await Future.wait([...]);
_hasError = results[0] == null;

// ÖNERİLEN:
Future<void> _load() async {
  setState(() { _loading = true; _hasError = false; });
  try {
    final results = await Future.wait([
      AnalyticsService.getProInsights(startDate: sd, endDate: ed),
      AnalyticsService.getProMetrics(),
    ]);
    if (!mounted) return;
    setState(() {
      _data    = results[0] as Map<String, dynamic>?;
      _metrics = results[1] as Map<String, dynamic>?;
      _loading = false;
    });
  } catch (e) {
    if (mounted) {
      setState(() { _loading = false; _hasError = true; });
      handleError(e, ref.read(localizationProvider));
    }
  }
}
```

**Not:** `getProMetrics` için de aynı pattern uygulanmalı.

---

### T-PI-03 — `/pro/metrics` Redis Cache Ekle ✅ Tamamlandı

**Kaynak:** F-03  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L2252)

```python
@router.get("/pro/metrics")
async def get_pro_metrics(...):
    if not current_user.is_premium:
        raise ForbiddenException(code="PRO_REQUIRED")

    uid = current_user.id

    # ── Cache Check ──────────────────────────────────────────────────────────
    try:
        redis = await get_redis()
        cache_key = f"cache:pro_metrics:{uid}"
        cached = await redis.get(cache_key)
        if cached:
            import json as _json
            return _json.loads(cached)
    except Exception:
        redis = None
        cache_key = None

    # ... mevcut hesaplama mantığı ...

    result = {
        "avg_detail_dwell_seconds": avg_dwell,
        "search_visibility": search_visibility,
        "best_posting_hour": best_hour,
        "return_viewer_rate_pct": return_viewer_rate,
        "return_viewer_count": return_viewer_count,
        "total_viewer_count": total_viewer_count,
    }

    # ── Cache Set ─────────────────────────────────────────────────────────────
    if redis and cache_key:
        try:
            import json as _json
            await redis.setex(cache_key, 600, _json.dumps(result))  # 10 dk
        except Exception:
            pass

    return result
```

---

### T-PI-04 — `/competitor-radar` Redis Cache Ekle ✅ Tamamlandı

**Kaynak:** F-04  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L2393)

```python
@router.get("/competitor-radar/{listing_id}")
async def competitor_radar(...):
    if not current_user.is_premium:
        raise ForbiddenException(code="PRO_REQUIRED")

    # ── Cache Check ──────────────────────────────────────────────────────────
    try:
        redis = await get_redis()
        cache_key = f"cache:competitor_radar:{listing_id}"
        cached = await redis.get(cache_key)
        if cached:
            import json as _json
            return _json.loads(cached)
    except Exception:
        redis = None
        cache_key = None

    # ... mevcut pgvector mantığı ...

    response = {
        "signal": signal,
        "signal_detail": signal_detail,
        "suggested_price": suggested_price,
        "diff_pct": diff_pct,
        "competitors": [...],
        "stats": {...},
    }

    if redis and cache_key:
        try:
            import json as _json
            await redis.setex(cache_key, 1800, _json.dumps(response))  # 30 dk
        except Exception:
            pass

    return response
```

**Not:** Fiyat değişikliğinde cache invalidation için satıcı ilan güncelleme endpoint'ine `redis.delete(f"cache:competitor_radar:{listing_id}")` eklenebilir (opsiyonel, ilk aşamada TTL yeterli).

---

### T-PI-05 — `peak_hours` Satıcıya Özel Filtre ✅ Tamamlandı

**Kaynak:** F-05  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1314)

```python
# MEVCUT — tüm platform:
ph_r = await ch.query("""
    SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
    FROM user_events
    WHERE timestamp >= now() - INTERVAL 30 DAY
      AND event_type IN ('view','detail_dwell','bid_hesitation')
    GROUP BY hr ORDER BY cnt DESC LIMIT 5
""")

# ÖNERİLEN — satıcının ilanlarına filtrelenmiş:
# (listing_ids değişkeni §Funnel bölümünden zaten mevcut)
if listing_ids:
    ids_str_ph = ", ".join(str(i) for i in listing_ids)
    ph_r = await ch.query(f"""
        SELECT toHour(timestamp) AS hr, COUNT(*) AS cnt
        FROM user_events
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND event_type IN ('view','detail_dwell','bid_hesitation')
          AND item_type = 'listing'
          AND item_id IN ({ids_str_ph})
        GROUP BY hr ORDER BY cnt DESC LIMIT 5
    """)
```

**Bağımlılık:** `listing_ids` §Funnel bölümünde hesaplanıyor (L1084). `peak_hours` hesabı (L1313) bundan sonra geldiği için değişken zaten hazır.

---

## Orta Öncelik

---

### T-PI-06 — `hot_leads` İlan Limitini Genişlet + Sıralama Ekle ✅ Tamamlandı

**Kaynak:** F-06  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1133)

```python
# MEVCUT:
_hl_q = (
    select(Listing.id, Listing.title, Listing.price, Listing.category)
    .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE)
)
active_ids_r = await db.execute(_hl_q.limit(20))

# ÖNERİLEN — sıralama ekle, limiti artır:
_hl_q = (
    select(Listing.id, Listing.title, Listing.price, Listing.category)
    .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE)
    .order_by(Listing.created_at.desc())   # ← en yeni önce
)
active_ids_r = await db.execute(_hl_q.limit(50))  # 20 → 50
```

**Not:** Limit artışı ClickHouse sorgusunu etkiler (`item_id IN (...)` listesi büyür). 50 ilan için ClickHouse tarafında önemli yük artışı beklenmez.

---

### T-PI-07 — `price_intel` İlan Limitini Artır + Sıralama Ekle ✅ Tamamlandı

**Kaynak:** F-07  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1203)

```python
# MEVCUT:
_pi_q = (
    select(Listing.id, Listing.title, Listing.price, Listing.category, Listing.embedding)
    .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE,
           Listing.price.is_not(None))
)
my_listings_r = await db.execute(_pi_q.limit(5))

# ÖNERİLEN — fiyat bazlı sıralama + limit artışı:
_pi_q = (
    select(Listing.id, Listing.title, Listing.price, Listing.category, Listing.embedding)
    .where(Listing.user_id == uid, Listing.status == ListingStatus.ACTIVE,
           Listing.price.is_not(None))
    .order_by(Listing.price.desc())   # ← en pahalı önce (fiyat analizi için anlamlı)
)
my_listings_r = await db.execute(_pi_q.limit(10))  # 5 → 10
```

**Not:** Her ilan için pgvector sorgusu çalışıyor — 10 ilan = 10 pgvector sorgusu. `asyncio.gather` ile paralel hale getirilebilir (gelecek iyileştirme).

---

### T-PI-08 — `_FunnelCard` UI'a `dwells` Adımını Ekle ✅ Tamamlandı

**Kaynak:** F-08  
**Dosya:** [mobile/lib/screens/pro_insights_screen.dart](../../../mobile/lib/screens/pro_insights_screen.dart#L519)

**Dart değişikliği:**
```dart
// _FunnelCard.build() — MEVCUT:
final views = (funnel['views'] as num?)?.toInt() ?? 0;
final hesitations = (funnel['hesitations'] as num?)?.toInt() ?? 0;
final bids = (funnel['bids'] as num?)?.toInt() ?? 0;
final sales = (funnel['sales'] as num?)?.toInt() ?? 0;
final maxVal = [views, hesitations, bids, sales].reduce(...).toDouble();

// ÖNERİLEN — dwells ekle:
final dwells = (funnel['dwells'] as num?)?.toInt() ?? 0;
final maxVal = [views, dwells, hesitations, bids, sales].reduce(...).toDouble();

// Widget listesine ekle (hesitations'tan ÖNCE):
_FunnelRow(label: loc.t("proFunnelDwells"), count: dwells, maxVal: maxVal, color: const Color(0xFF06B6D4)),
const SizedBox(height: 8),
```

**ARB değişikliği** (4 dilde):
```json
// app_tr.arb:
"proFunnelDwells": "Detaylı İnceleme",

// app_en.arb:
"proFunnelDwells": "Detail Views",

// app_ar.arb:
"proFunnelDwells": "المشاهدات التفصيلية",

// app_ru.arb:
"proFunnelDwells": "Детальные просмотры",
```

**VPS deploy:** ARB ekledikten sonra `git pull && python3 scripts/sync_translations.py && sudo systemctl restart teqlif`

---

### T-PI-09 — demand-radar f-string → Parametreli ClickHouse Sorgusu ✅ Tamamlandı

**Kaynak:** F-11  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L2172)

```python
# MEVCUT — f-string interpolasyon:
_safe = lambda s: _re.sub(r"[^a-zA-Z0-9çğıöşüÇĞİÖŞÜ\-_]", "", s) if s else ""
cat_safe = _safe(category)
cat_filter = f"AND category = '{cat_safe}'"
q_top = f"""SELECT ... {cat_filter} ..."""

# ÖNERİLEN — parametreli sorgu (ClickHouse Python client destekliyor):
cat_param = category or ""

q_top = """
    SELECT query, COUNT(*) AS cnt
    FROM search_events
    WHERE timestamp >= now() - INTERVAL %(days)s DAY
      AND length(query) >= 2
      AND (%(cat)s = '' OR category = %(cat)s)
    GROUP BY query
    HAVING cnt >= 2
    ORDER BY cnt DESC
    LIMIT 20
"""

q_cat = """
    SELECT category, COUNT(*) AS cnt
    FROM search_events
    WHERE timestamp >= now() - INTERVAL %(days)s DAY
      AND category != ''
      AND (%(cat)s = '' OR category = %(cat)s)
    GROUP BY category
    HAVING cnt >= 2
    ORDER BY cnt DESC
    LIMIT 10
"""

# Aynı parametreleri tüm sorgulara geçir:
params = {"days": days, "cat": cat_param}
top_queries, by_category, ... = await asyncio.gather(
    ch.query(q_top, parameters=params),
    ch.query(q_cat, parameters=params),
    ...
)
```

---

### T-PI-10 — Heat Score'a `detail_dwell` Ağırlığı Ekle ✅ Tamamlandı

**Kaynak:** F-12  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1148)

**ClickHouse sorgusu genişlet:**
```python
ch_r2 = await ch.query(f"""
    SELECT item_id,
           countIf(event_type = 'view') AS views,
           countIf(event_type = 'detail_dwell') AS dwells,    ← EKLE
           countDistinctIf(user_id, event_type = 'bid_hesitation') AS hes,
           toUnixTimestamp(max(timestamp)) AS last_event_ts
    FROM user_events
    WHERE item_type = 'listing' AND item_id IN ({ids_str})
      AND timestamp >= now() - INTERVAL 30 DAY
    GROUP BY item_id
""")
view_map  = {int(r[0]): int(r[1]) for r in ch_r2.result_rows}
dwell_map = {int(r[0]): int(r[2]) for r in ch_r2.result_rows}  ← EKLE
hes_map   = {int(r[0]): int(r[3]) for r in ch_r2.result_rows}  ← index güncelle
ts_map    = {int(r[0]): float(r[4]) for r in ch_r2.result_rows}  ← index güncelle
```

**Heat score formülü güncelle:**
```python
def _heat(lid: int) -> float:
    age_h = max((_now_ts - ts_map.get(lid, _now_ts)) / 3600, 0.0)
    raw = (
        view_map.get(lid, 0)  * 1 +
        like_map.get(lid, 0)  * 2 +
        dwell_map.get(lid, 0) * 2 +   ← EKLE (görüntülemeden güçlü, favoriden zayıf)
        hes_map.get(lid, 0)   * 3
    )
    return raw / (age_h + 2) ** 1.2
```

---

## Düşük Öncelik

---

### T-PI-11 — Tips Hard-Coded Türkçe Fallback'leri Kaldır ✅ Tamamlandı

**Kaynak:** F-13  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1341)

```python
# MEVCUT — fallback Türkçe hard-coded:
"body": t.get(
    "proTipPriceDownBody",
    '"{title}" piyasa ortalamasının %{diff} üzerinde...'
).format(...)

# ÖNERİLEN — fallback kaldır, key zorunlu yap:
body = t.get("proTipPriceDownBody", "")
if body:
    tips.append({
        "icon": "💰", "type": "price",
        "title": t.get("proTipPriceDownTitle", ""),
        "body": body.format(title=..., diff=..., avg=...),
    })
```

Aynı pattern tüm `proTip*` key'lerine uygulanmalı. ARB'de bu key'lerin 4 dilde eksiksiz olduğundan emin ol.

---

### T-PI-12 — `search_visibility` Metrik Başlığını Düzelt ✅ Tamamlandı

**Kaynak:** F-14  
**Dosya:** [mobile/lib/screens/pro_insights_screen.dart](../../../mobile/lib/screens/pro_insights_screen.dart#L1063)  
**Dosya:** [documents/language/app_tr.arb](../../../documents/language/app_tr.arb)

```dart
// MEVCUT ARB key:
"proMetricSearchVisibility": "Arama Görünürlüğü"

// ÖNERİLEN — ne gösterdiğini doğru açıkla:
"proMetricSearchVisibility": "Kategorinde Arama Hacmi"

// app_en.arb:
"proMetricSearchVisibility": "Search Volume in Your Categories"

// app_ar.arb:
"proMetricSearchVisibility": "حجم البحث في فئاتك"

// app_ru.arb:
"proMetricSearchVisibility": "Объём поиска в ваших категориях"
```

**VPS deploy gerekiyor.**

---

### T-PI-13 — `price_intel` Fiyat Aralığı Filtresini Daralt ✅ Tamamlandı

**Kaynak:** F-16  
**Dosya:** [backend/app/routers/analytics.py](../../../backend/app/routers/analytics.py#L1216)

```python
# MEVCUT — çok geniş:
price_lo = float(ml.price) * 0.05
price_hi = float(ml.price) * 20.0

# ÖNERİLEN — makul aralık:
price_lo = float(ml.price) * 0.4
price_hi = float(ml.price) * 2.5
```

**Gerekçe:** Outlier eleme amacıyla 0.05× – 20× çok geniş; 100 TL'lik ilan için 2000 TL ilanlar karşılaştırma havuzuna giriyor. 0.4× – 2.5× aralığı benzer sınıftaki ürünleri karşılaştırır.

---

## Araştırma / Gelecek

---

### T-PI-14 — Flutter Typed Model'lar Oluştur

**Kaynak:** F-10  
**Mevcut durum:** Tüm ekran `Map<String, dynamic>` ve cast kullanıyor.

**Önerilen model yapısı:**
```dart
// mobile/lib/models/pro_insights_data.dart
class ProInsightsData {
  final ProKpis kpis;
  final ProFunnel funnel;
  final List<HotLead> hotLeads;
  final List<PriceIntel> priceIntel;
  final StreamStats streamStats;
  final List<PeakHour> peakHours;
  final List<ProTip> tips;

  factory ProInsightsData.fromJson(Map<String, dynamic> json) { ... }
}

class ProKpis {
  final double revenue30d;
  final double? revenueGrowthPct;
  final int sales30d;
  final int bids30d;
  final int activeListings;
  final double totalRevenue;
  ...
}
```

**Bağımlılık:** T-PI-02 (error handling refactor) ile birlikte yapılırsa daha temiz.

---

### T-PI-15 — SWR / Hive Cache — Offline Destek

**Kaynak:** F-15  

**Mevcut:** `AnalyticsService.getProInsights()` ham `http.get` — offline'da boş sayfa.

**Önerilen:**
```dart
// ApiService.get stream pattern:
void _load() {
  ApiService.get<Map<String, dynamic>>(
    url: '$kBaseUrl/analytics/pro-insights',
    cacheKey: 'pro_insights_${sd ?? ''}',
    cacheTtl: const Duration(minutes: 10),
    bypassCache: bypassCache,
    fromJson: (raw) => raw as Map<String, dynamic>,
  ).listen(
    (data) { if (mounted) setState(() { _data = data; _loading = false; }); },
    onError: (e) { if (mounted) handleError(e, ref.read(localizationProvider)); },
  );
}
```

**Bağımlılık:** T-PI-14 (typed model'lar) tamamlanmışsa `fromJson` clean olur.

---

### T-PI-16 — Clean Architecture Refactor — Use Case Katmanı

**Kaynak:** F-09  

**Mevcut:** `pro_insights()` handler ~450 satır iş mantığı içeriyor (8 sorgu, heat score, fiyat analizi, kural motoru).

**Önerilen yapı:**
```
backend/app/
  use_cases/analytics/
    pro_insights_use_case.py    # orkestrasyon
    hot_leads_use_case.py       # heat score mantığı
    price_intel_use_case.py     # pgvector + sinyal hesabı
    tips_use_case.py            # kural motoru
  repositories/
    analytics_pg_repository.py  # PG sorguları
    analytics_ch_repository.py  # ClickHouse sorguları
  routers/
    analytics.py                # sadece routing + auth + DTO
```

**Öneri:** Bu task tek seferde değil, kademeli migrate edilmeli:
1. İlk adım: `hot_leads` use case (en izole parça)
2. İkinci adım: `price_intel` use case
3. Üçüncü adım: `tips` use case
4. Son adım: Router temizliği

**Not:** T-PI-01–T-PI-13 tamamlanmadan bu task başlatılmamalı — refactor sırasında bug fix fırsatı kaçar.
